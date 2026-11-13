//! Offline full-text index over every title stored locally.
//!
//! The index is derived data: rows in `manga` are the source of truth, so the table
//! can always be recreated. It is only recreated when the stored table shape differs
//! from [FTS_COLUMNS], which is what lets new searchable columns (authors, tags)
//! land without a migration path while keeping startup read-only in the common case.

use crate::api::models::{MangaDetails, MangaSearchResult};
use crate::api::storage::{with_conn, FTS_AVAILABLE};
use anyhow::Result;
use rusqlite::{params, Connection};
use std::sync::atomic::Ordering;

/// Columns the current index shape must contain. A table without all of them is
/// stale (for example the pre-tag four-column version) and gets recreated.
const FTS_COLUMNS: [&str; 6] = ["name", "rus_name", "eng_name", "slug_url", "authors", "tags"];

/// Standalone table (not external content) so rows are maintained explicitly without
/// the REPLACE-trigger pitfalls of external content tables.
const FTS_SCHEMA: &str = "
    DROP TABLE IF EXISTS manga_fts;
    CREATE VIRTUAL TABLE IF NOT EXISTS manga_fts USING fts5(
        name, rus_name, eng_name, slug_url, authors, tags,
        tokenize='unicode61 remove_diacritics 2'
    );";

/// Creates the index if its shape is outdated and refills it only when the row count
/// no longer matches the `manga` table. Returns whether FTS5 is usable; a build
/// without the FTS5 module keeps working through the LIKE fallback.
pub(crate) fn init_fts(conn: &Connection) -> bool {
    if !has_current_schema(conn) && conn.execute_batch(FTS_SCHEMA).is_err() {
        return false;
    }
    let _ = rebuild_if_stale(conn);
    true
}

fn has_current_schema(conn: &Connection) -> bool {
    let mut statement = match conn.prepare("PRAGMA table_info(manga_fts)") {
        Ok(statement) => statement,
        Err(_) => return false,
    };
    let columns: Vec<String> = match statement
        .query_map([], |row| row.get::<_, String>(1))
        .and_then(|rows| rows.collect())
    {
        Ok(columns) => columns,
        Err(_) => return false,
    };
    FTS_COLUMNS
        .iter()
        .all(|required| columns.iter().any(|column| column == required))
}

/// A count mismatch means the index lost rows (interrupted write) or kept rows for
/// titles that no longer exist; either way one pass restores it.
fn rebuild_if_stale(conn: &Connection) -> rusqlite::Result<()> {
    let indexed: i64 = conn.query_row("SELECT COUNT(*) FROM manga_fts", [], |row| row.get(0))?;
    let stored: i64 = conn.query_row("SELECT COUNT(*) FROM manga", [], |row| row.get(0))?;
    if indexed != stored {
        rebuild(conn)?;
    }
    Ok(())
}

/// Rebuilds the whole index from the manga table. Cheap for the size of a personal
/// library and used after bulk writes (imports) where per-row maintenance would be
/// more expensive than one pass.
pub(crate) fn rebuild(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute("DELETE FROM manga_fts", [])?;

    let mut select = conn.prepare(
        "SELECT id, COALESCE(name, ''), COALESCE(rus_name, ''), COALESCE(eng_name, ''),
                COALESCE(slug_url, ''), COALESCE(authors_json, '[]'), COALESCE(tags_json, '[]')
         FROM manga",
    )?;
    let rows = select.query_map([], |row| {
        Ok((
            row.get::<_, i64>(0)?,
            row.get::<_, String>(1)?,
            row.get::<_, String>(2)?,
            row.get::<_, String>(3)?,
            row.get::<_, String>(4)?,
            row.get::<_, String>(5)?,
            row.get::<_, String>(6)?,
        ))
    })?;

    let mut insert = conn.prepare(
        "INSERT INTO manga_fts(rowid, name, rus_name, eng_name, slug_url, authors, tags)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
    )?;

    for row in rows {
        let (id, name, rus_name, eng_name, slug_url, authors_json, tags_json) = row?;
        insert.execute(params![
            id,
            normalize(&name),
            normalize(&rus_name),
            normalize(&eng_name),
            normalize(&slug_url),
            author_names(&authors_json),
            tag_names(&tags_json),
        ])?;
    }

    Ok(())
}

pub(crate) fn upsert_row(conn: &Connection, manga: &MangaDetails) {
    if !FTS_AVAILABLE.load(Ordering::Relaxed) {
        return;
    }
    let authors = join_normalized(manga.authors.iter().map(|p| p.name.as_str()));
    let tags = join_normalized(manga.tags.iter().map(|t| t.name.as_str()));
    let _ = conn.execute("DELETE FROM manga_fts WHERE rowid = ?1", params![manga.id]);
    let _ = conn.execute(
        "INSERT INTO manga_fts(rowid, name, rus_name, eng_name, slug_url, authors, tags)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        params![
            manga.id,
            normalize(&manga.name),
            normalize(&manga.rus_name),
            normalize(&manga.eng_name),
            normalize(&manga.slug_url),
            authors,
            tags
        ],
    );
}

/// FTS5 treats a lot of punctuation as query syntax; user input is reduced to
/// prefix-matched string literals so a stray quote cannot break the query.
fn build_fts_query(raw: &str) -> String {
    let mut tokens = Vec::new();
    for token in raw.split(|c: char| !c.is_alphanumeric()) {
        if token.is_empty() {
            continue;
        }
        tokens.push(format!("\"{}\"*", token.replace('"', "\"\"")));
    }
    tokens.join(" ")
}

/// Reduces text to bare alphanumeric tokens separated by single spaces. The
/// unicode61 tokenizer splits on punctuation anyway, so this only guarantees that the
/// stored text holds no quote or comma fragments an FTS query could trip over.
fn normalize(raw: &str) -> String {
    let mut out = String::with_capacity(raw.len());
    let mut pending_space = false;
    for ch in raw.chars() {
        if ch.is_alphanumeric() {
            if pending_space && !out.is_empty() {
                out.push(' ');
            }
            out.push(ch);
            pending_space = false;
        } else {
            pending_space = true;
        }
    }
    out
}

fn join_normalized<'a>(names: impl Iterator<Item = &'a str>) -> String {
    let mut out = String::new();
    for name in names {
        let clean = normalize(name);
        if clean.is_empty() {
            continue;
        }
        if !out.is_empty() {
            out.push(' ');
        }
        out.push_str(&clean);
    }
    out
}

fn author_names(authors_json: &str) -> String {
    names_from_json(authors_json)
}

fn tag_names(tags_json: &str) -> String {
    names_from_json(tags_json)
}

/// Authors and tags are stored as `[{"id": ..., "name": ...}]`. Only the name is
/// needed, and being strict about the other fields would silently drop rows written by
/// older versions or by the MAL importer, so unknown and missing keys are ignored.
#[derive(serde::Deserialize)]
struct NamedEntry {
    name: String,
}

fn names_from_json(json: &str) -> String {
    let entries: Vec<NamedEntry> = serde_json::from_str(json).unwrap_or_default();
    join_normalized(entries.iter().map(|entry| entry.name.as_str()))
}

fn map_local_manga_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<MangaSearchResult> {
    Ok(MangaSearchResult {
        id: row.get("id")?,
        name: row.get("name")?,
        rus_name: row.get("rus_name").unwrap_or_default(),
        eng_name: row.get("eng_name").unwrap_or_default(),
        slug: row.get("slug").unwrap_or_default(),
        slug_url: row.get("slug_url")?,
        cover_url: row.get("cover_url").unwrap_or_default(),
        cover_thumb_url: row.get("cover_thumb_url").unwrap_or_default(),
        manga_type: row.get("manga_type").unwrap_or_default(),
        type_id: row.get("type_id").unwrap_or(0),
        status: row.get("status").unwrap_or_default(),
        status_id: row.get("status_id").unwrap_or(0),
        age_restriction: row.get("age_restriction").unwrap_or_default(),
        rating_average: row.get("rating_average").unwrap_or_else(|_| "0".to_string()),
        rating_votes: row.get("rating_votes").unwrap_or_else(|_| "0".to_string()),
        release_date: row.get("release_date").ok(),
    })
}

/// Offline full-text search over every title stored locally (library, opened or
/// downloaded). An empty query lists the most recently touched titles, which keeps
/// the catalog usable without a network connection.
pub(crate) fn search_library(query: String, limit: i64) -> Result<Vec<MangaSearchResult>> {
    with_conn(|conn| {
        let max_rows = limit.clamp(1, 200);
        let trimmed = query.trim();
        let mut results = Vec::new();

        if trimmed.is_empty() {
            let mut stmt =
                conn.prepare("SELECT * FROM manga ORDER BY last_updated DESC, id DESC LIMIT ?1")?;
            let iter = stmt.query_map(params![max_rows], map_local_manga_row)?;
            for row in iter {
                results.push(row?);
            }
            return Ok(results);
        }

        if FTS_AVAILABLE.load(Ordering::Relaxed) {
            let fts_query = build_fts_query(trimmed);
            if !fts_query.is_empty() {
                if let Ok(mut stmt) = conn.prepare(
                    "SELECT m.* FROM manga_fts f JOIN manga m ON m.id = f.rowid
                     WHERE manga_fts MATCH ?1
                     ORDER BY bm25(manga_fts) LIMIT ?2",
                ) {
                    if let Ok(iter) =
                        stmt.query_map(params![fts_query, max_rows], map_local_manga_row)
                    {
                        for row in iter.flatten() {
                            results.push(row);
                        }
                    }
                }
            }
        }

        // Covers builds whose SQLite lacks FTS5 and queries the tokenizer cannot serve.
        // The JSON columns are matched too so author and tag lookups behave the same
        // way as the FTS path.
        if results.is_empty() {
            let pattern = format!("%{}%", trimmed.to_lowercase());
            let mut stmt = conn.prepare(
                "SELECT * FROM manga
                 WHERE lower(name) LIKE ?1 OR lower(rus_name) LIKE ?1
                    OR lower(eng_name) LIKE ?1 OR lower(slug_url) LIKE ?1
                    OR lower(authors_json) LIKE ?1 OR lower(tags_json) LIKE ?1
                 ORDER BY last_updated DESC LIMIT ?2",
            )?;
            let iter = stmt.query_map(params![pattern, max_rows], map_local_manga_row)?;
            for row in iter.flatten() {
                results.push(row);
            }
        }

        Ok(results)
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn seeded_connection() -> Connection {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(
            "CREATE TABLE manga (
                id INTEGER PRIMARY KEY,
                name TEXT,
                rus_name TEXT,
                eng_name TEXT,
                slug_url TEXT,
                authors_json TEXT,
                tags_json TEXT
            );",
        )
        .unwrap();
        conn.execute(
            "INSERT INTO manga (id, name, rus_name, eng_name, slug_url, authors_json, tags_json)
             VALUES (1, 'Solo Leveling', '', '', 'solo-leveling',
                     '[{\"id\":1,\"name\":\"Chugong\"},{\"id\":2,\"name\":\"Dubu\"}]',
                     '[{\"id\":3,\"name\":\"Action, Fantasy\"}]')",
            [],
        )
        .unwrap();
        conn
    }

    fn match_count(conn: &Connection, query: &str) -> i64 {
        conn.query_row(
            "SELECT COUNT(1) FROM manga_fts WHERE manga_fts MATCH ?1",
            params![query],
            |row| row.get(0),
        )
        .unwrap()
    }

    #[test]
    fn indexes_author_and_tag_names() {
        let conn = seeded_connection();
        assert!(init_fts(&conn), "bundled SQLite should provide FTS5");
        rebuild(&conn).unwrap();

        assert_eq!(match_count(&conn, "chugong"), 1);
        assert_eq!(match_count(&conn, "dubu"), 1);
        assert_eq!(match_count(&conn, "fantasy"), 1);
        assert_eq!(match_count(&conn, "action"), 1);
        assert_eq!(match_count(&conn, "leveling"), 1);
        assert_eq!(match_count(&conn, "nonexistent"), 0);
    }

    #[test]
    fn normalises_punctuation_out_of_indexed_text() {
        assert_eq!(normalize("  Action,  Fantasy  "), "Action Fantasy");
        assert_eq!(normalize("\"Quoted\" title"), "Quoted title");
        assert_eq!(normalize("---"), "");
        assert_eq!(
            join_normalized(["Ivan Petrov", "O'Neil"].into_iter()),
            "Ivan Petrov O Neil"
        );
    }

    #[test]
    fn query_builder_keeps_tokens_quoted() {
        assert_eq!(
            build_fts_query("solo, \"leveling\""),
            "\"solo\"* \"leveling\"*"
        );
        assert_eq!(build_fts_query("   "), "");
    }

    fn sample_manga() -> MangaDetails {
        use crate::api::models::{Genre, Person, Tag};

        MangaDetails {
            id: 42,
            name: "Solo Leveling".to_string(),
            rus_name: "Поднятие уровня в одиночку".to_string(),
            eng_name: "Solo Leveling".to_string(),
            slug: "solo-leveling".to_string(),
            slug_url: "solo-leveling".to_string(),
            cover_url: String::new(),
            cover_thumb_url: String::new(),
            manga_type: "manga".to_string(),
            type_id: 1,
            status: "ongoing".to_string(),
            status_id: 1,
            age_restriction: "16+".to_string(),
            rating_average: "9.1".to_string(),
            rating_votes: "100".to_string(),
            release_date: Some("2018".to_string()),
            summary: String::new(),
            genres: vec![Genre { id: 1, name: "Action".to_string() }],
            tags: vec![Tag { id: 2, name: "Fantasy".to_string() }],
            authors: vec![Person {
                id: 3,
                name: "Chugong".to_string(),
                slug: "chugong".to_string(),
            }],
            artists: Vec::new(),
            views_total: "0".to_string(),
            views_formatted: "0".to_string(),
            chapters_count: 10,
            format_labels: Vec::new(),
            publisher_name: None,
        }
    }

    /// Reproduces an upgrade from a build whose index had no author/tag columns: init
    /// must replace the old table and the first saved title must be findable by author.
    #[test]
    fn upgrade_replaces_legacy_index_and_indexes_new_columns() {
        let dir = std::env::temp_dir().join("mangaloader-search-test");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();

        let legacy = Connection::open(dir.join("mangaloader.db")).unwrap();
        legacy
            .execute_batch(
                "CREATE VIRTUAL TABLE manga_fts USING fts5(
                    name, rus_name, eng_name, slug_url,
                    tokenize='unicode61 remove_diacritics 2'
                );",
            )
            .unwrap();
        drop(legacy);

        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        runtime.block_on(async {
            crate::api::storage::init_database(dir.to_string_lossy().to_string())
                .await
                .unwrap();
            crate::api::storage::save_manga(sample_manga()).await.unwrap();

            let by_author = crate::api::storage::search_library("chugong".to_string(), 10)
                .await
                .unwrap();
            assert_eq!(by_author.len(), 1);
            assert_eq!(by_author[0].id, 42);

            let by_tag = crate::api::storage::search_library("fantasy".to_string(), 10)
                .await
                .unwrap();
            assert_eq!(by_tag.len(), 1);

            let by_title = crate::api::storage::search_library("leveling".to_string(), 10)
                .await
                .unwrap();
            assert_eq!(by_title.len(), 1);
        });

        let _ = std::fs::remove_dir_all(&dir);
    }
}