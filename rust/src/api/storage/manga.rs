//! Manga metadata cache and chapter cache.

use crate::api::models::{Chapter, Genre, MangaDetails, MangaSearchResult, Person, Tag};
use crate::api::storage::{search, with_conn, with_conn_mut};
use anyhow::Result;
use rusqlite::{params, OptionalExtension};

pub(crate) fn save_manga(manga: MangaDetails) -> Result<()> {
    with_conn(|conn| {
        let genres_json = serde_json::to_string(&manga.genres).unwrap_or_else(|_| "[]".to_string());
        let tags_json = serde_json::to_string(&manga.tags).unwrap_or_else(|_| "[]".to_string());
        let authors_json = serde_json::to_string(&manga.authors).unwrap_or_else(|_| "[]".to_string());
        let artists_json = serde_json::to_string(&manga.artists).unwrap_or_else(|_| "[]".to_string());
        let format_labels_json =
            serde_json::to_string(&manga.format_labels).unwrap_or_else(|_| "[]".to_string());

        conn.execute(
            "INSERT INTO manga (
                id, slug_url, name, rus_name, eng_name, cover_url, cover_thumb_url,
                manga_type, status, rating_average, rating_votes, summary, genres_json, tags_json,
                chapters_count, release_date, last_updated, type_id, status_id, age_restriction,
                slug, authors_json, artists_json, views_total, views_formatted, format_labels_json, publisher_name
            ) VALUES (
                ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, strftime('%s','now'),
                ?17, ?18, ?19, ?20, ?21, ?22, ?23, ?24, ?25, ?26
            )
            ON CONFLICT(slug_url) DO UPDATE SET
                name=excluded.name, rus_name=excluded.rus_name, eng_name=excluded.eng_name,
                cover_url=excluded.cover_url, cover_thumb_url=excluded.cover_thumb_url,
                manga_type=excluded.manga_type, status=excluded.status,
                rating_average=excluded.rating_average, rating_votes=excluded.rating_votes,
                summary=excluded.summary, genres_json=excluded.genres_json, tags_json=excluded.tags_json,
                chapters_count=excluded.chapters_count, release_date=excluded.release_date,
                last_updated=strftime('%s','now'), type_id=excluded.type_id, status_id=excluded.status_id,
                age_restriction=excluded.age_restriction, slug=excluded.slug,
                authors_json=excluded.authors_json, artists_json=excluded.artists_json,
                views_total=excluded.views_total, views_formatted=excluded.views_formatted,
                format_labels_json=excluded.format_labels_json, publisher_name=excluded.publisher_name
            ",
            params![
                manga.id, manga.slug_url, manga.name, manga.rus_name, manga.eng_name,
                manga.cover_url, manga.cover_thumb_url, manga.manga_type, manga.status,
                manga.rating_average, manga.rating_votes, manga.summary, genres_json, tags_json,
                manga.chapters_count, manga.release_date, manga.type_id, manga.status_id,
                manga.age_restriction, manga.slug, authors_json, artists_json, manga.views_total,
                manga.views_formatted, format_labels_json, manga.publisher_name
            ],
        )?;

        search::upsert_row(conn, &manga);
        Ok(())
    })
}

pub(crate) fn bulk_import_bookmarks(
    items: Vec<MangaSearchResult>,
    list_type: &str,
) -> Result<i64> {
    with_conn_mut(|conn| {
        let tx = conn.transaction()?;
        let mut count = 0;

        {
            let mut manga_stmt = tx.prepare_cached(
                "INSERT INTO manga (
                    id, slug_url, name, rus_name, eng_name, cover_url, cover_thumb_url,
                    manga_type, status, rating_average, rating_votes, summary, genres_json, tags_json,
                    chapters_count, release_date, last_updated, type_id, status_id, age_restriction,
                    slug, authors_json, artists_json, views_total, views_formatted, format_labels_json, publisher_name
                ) VALUES (
                    ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, strftime('%s','now'),
                    ?17, ?18, ?19, ?20, '[]', '[]', '0', '0', '[]', NULL
                )
                ON CONFLICT(slug_url) DO UPDATE SET
                    name=excluded.name, rus_name=excluded.rus_name, eng_name=excluded.eng_name,
                    cover_url=excluded.cover_url, cover_thumb_url=excluded.cover_thumb_url,
                    manga_type=excluded.manga_type, status=excluded.status,
                    rating_average=excluded.rating_average, rating_votes=excluded.rating_votes,
                    last_updated=strftime('%s','now'), type_id=excluded.type_id, status_id=excluded.status_id,
                    age_restriction=excluded.age_restriction, slug=excluded.slug"
            )?;

            let mut list_stmt = tx.prepare_cached(
                "INSERT INTO user_lists (manga_id, list_type, added_at)
                 VALUES (?1, ?2, datetime('now'))
                 ON CONFLICT(manga_id) DO UPDATE SET list_type=excluded.list_type"
            )?;

            for m in items {
                let _ = manga_stmt.execute(params![
                    m.id, m.slug_url, m.name, m.rus_name, m.eng_name,
                    m.cover_url, m.cover_thumb_url, m.manga_type, m.status,
                    m.rating_average, m.rating_votes, "", "[]", "[]",
                    0, m.release_date, m.type_id, m.status_id,
                    m.age_restriction, m.slug
                ]);

                let _ = list_stmt.execute(params![m.id, list_type]);
                count += 1;
            }
        }

        tx.commit()?;
        // One pass is cheaper than per-row index maintenance for a bulk import.
        let _ = search::rebuild(conn);
        Ok(count)
    })
}

pub(crate) fn get_cached_manga(slug_url: &str) -> Result<Option<MangaDetails>> {
    with_conn(|conn| {
        let mut stmt = conn.prepare("SELECT * FROM manga WHERE slug_url = ?1")?;
        let row = stmt
            .query_row(params![slug_url], |row| {
                let genres_str: String =
                    row.get("genres_json").unwrap_or_else(|_| "[]".to_string());
                let tags_str: String = row.get("tags_json").unwrap_or_else(|_| "[]".to_string());
                let authors_str: String =
                    row.get("authors_json").unwrap_or_else(|_| "[]".to_string());
                let artists_str: String =
                    row.get("artists_json").unwrap_or_else(|_| "[]".to_string());
                let format_labels_str: String = row
                    .get("format_labels_json")
                    .unwrap_or_else(|_| "[]".to_string());

                let genres: Vec<Genre> = serde_json::from_str(&genres_str).unwrap_or_default();
                let tags: Vec<Tag> = serde_json::from_str(&tags_str).unwrap_or_default();
                let authors: Vec<Person> = serde_json::from_str(&authors_str).unwrap_or_default();
                let artists: Vec<Person> = serde_json::from_str(&artists_str).unwrap_or_default();
                let format_labels: Vec<String> =
                    serde_json::from_str(&format_labels_str).unwrap_or_default();

                Ok(MangaDetails {
                    id: row.get("id")?,
                    name: row.get("name")?,
                    rus_name: row.get("rus_name")?,
                    eng_name: row.get("eng_name")?,
                    slug: row.get("slug")?,
                    slug_url: row.get("slug_url")?,
                    cover_url: row.get("cover_url")?,
                    cover_thumb_url: row.get("cover_thumb_url")?,
                    manga_type: row.get("manga_type")?,
                    type_id: row.get("type_id")?,
                    status: row.get("status")?,
                    status_id: row.get("status_id")?,
                    age_restriction: row.get("age_restriction")?,
                    rating_average: row.get("rating_average")?,
                    rating_votes: row.get("rating_votes")?,
                    release_date: row.get("release_date")?,
                    summary: row.get("summary")?,
                    genres,
                    tags,
                    authors,
                    artists,
                    views_total: row.get("views_total")?,
                    views_formatted: row.get("views_formatted")?,
                    chapters_count: row.get("chapters_count")?,
                    format_labels,
                    publisher_name: row.get("publisher_name")?,
                })
            })
            .optional()?;

        Ok(row)
    })
}

pub(crate) fn cache_chapters(manga_id: i64, chapters: Vec<Chapter>) -> Result<()> {
    with_conn(|conn| {
        let mut stmt = conn.prepare(
            "INSERT INTO cached_chapters (manga_id, volume, number, id, name, branch_id, branches_count, is_paid)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
             ON CONFLICT(manga_id, volume, number) DO UPDATE SET
                id=excluded.id, name=excluded.name, branch_id=excluded.branch_id, branches_count=excluded.branches_count, is_paid=excluded.is_paid"
        )?;

        for ch in chapters {
            let name_str = ch.name.unwrap_or_default();
            let _ = stmt.execute(params![
                manga_id,
                ch.volume,
                ch.number,
                ch.id,
                name_str,
                ch.branch_id,
                ch.branches_count,
                ch.is_paid,
            ]);
        }

        Ok(())
    })
}

pub(crate) fn get_cached_chapters(manga_id: i64) -> Result<Vec<Chapter>> {
    with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT id, volume, number, name, branch_id, branches_count, is_paid
             FROM cached_chapters WHERE manga_id = ?1"
        )?;

        let iter = stmt.query_map(params![manga_id], |row| {
            let name: String = row.get("name").unwrap_or_default();
            Ok(Chapter {
                id: row.get("id").unwrap_or(0),
                volume: row.get("volume")?,
                number: row.get("number")?,
                name: if name.is_empty() { None } else { Some(name) },
                branch_id: row.get("branch_id").unwrap_or(None),
                branches_count: row.get("branches_count").unwrap_or(0),
                is_paid: row.get("is_paid").unwrap_or(false),
            })
        })?;

        let mut chapters = Vec::new();
        for chap in iter.flatten() {
            chapters.push(chap);
        }

        if let Ok(mut d_stmt) = conn.prepare(
            "SELECT volume, number, branch_id FROM downloaded_chapters WHERE manga_id = ?1"
        ) {
            if let Ok(d_iter) = d_stmt.query_map(params![manga_id], |row| {
                Ok(Chapter {
                    id: 0,
                    volume: row.get("volume")?,
                    number: row.get("number")?,
                    name: None,
                    branch_id: row.get("branch_id").unwrap_or(None),
                    branches_count: 0,
                    is_paid: false,
                })
            }) {
                for c in d_iter.flatten() {
                    if !chapters.iter().any(|existing| existing.volume == c.volume && existing.number == c.number) {
                        chapters.push(c);
                    }
                }
            }
        }

        chapters.sort_by(|a, b| {
            let va: f64 = a.volume.parse().unwrap_or(0.0);
            let vb: f64 = b.volume.parse().unwrap_or(0.0);
            if (va - vb).abs() > f64::EPSILON {
                return va.partial_cmp(&vb).unwrap_or(std::cmp::Ordering::Equal);
            }
            let na: f64 = a.number.parse().unwrap_or(0.0);
            let nb: f64 = b.number.parse().unwrap_or(0.0);
            na.partial_cmp(&nb).unwrap_or(std::cmp::Ordering::Equal)
        });

        Ok(chapters)
    })
}

pub(crate) fn update_manga_chapters_count(manga_id: i64, chapters_count: i64) -> Result<()> {
    with_conn(|conn| {
        conn.execute(
            "UPDATE manga SET chapters_count = ?1 WHERE id = ?2 AND chapters_count < ?1",
            params![chapters_count, manga_id],
        )?;
        Ok(())
    })
}