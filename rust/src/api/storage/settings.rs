//! Key/value settings and JSON/XML import-export.

use crate::api::models::{
    AppSettingItem, ChapterHistory, Genre, MalImportResult, MangaDetails, Person, ReadingPosition,
    Tag,
};
use crate::api::storage::{search, with_conn, BackupData, BackupUserList};
use anyhow::{Context, Result};
use rusqlite::params;

pub(crate) fn get_setting(key: String) -> Result<Option<String>> {
    with_conn(|conn| {
        let mut stmt = conn.prepare("SELECT value FROM app_settings WHERE key = ?1")?;
        let mut rows = stmt.query(params![key])?;

        if let Some(row) = rows.next()? {
            Ok(Some(row.get(0)?))
        } else {
            Ok(None)
        }
    })
}

pub(crate) fn set_setting(key: String, value: String) -> Result<()> {
    with_conn(|conn| {
        conn.execute(
            "INSERT OR REPLACE INTO app_settings (key, value) VALUES (?1, ?2)",
            params![key, value],
        )?;
        Ok(())
    })
}

pub(crate) fn get_all_settings() -> Result<Vec<AppSettingItem>> {
    with_conn(|conn| {
        let mut stmt = conn.prepare("SELECT key, value FROM app_settings")?;
        let rows = stmt.query_map([], |row| {
            Ok(AppSettingItem {
                key: row.get(0)?,
                value: row.get(1)?,
            })
        })?;

        let mut items = Vec::new();
        for item in rows.flatten() {
            items.push(item);
        }

        Ok(items)
    })
}

pub(crate) fn export_backup_json() -> Result<String> {
    with_conn(|conn| {
        // 1. All saved manga
        let mut stmt = conn.prepare("SELECT * FROM manga")?;
        let manga_iter = stmt.query_map([], |row| {
            let genres_str: String = row.get("genres_json").unwrap_or_else(|_| "[]".to_string());
            let tags_str: String = row.get("tags_json").unwrap_or_else(|_| "[]".to_string());
            let authors_str: String = row.get("authors_json").unwrap_or_else(|_| "[]".to_string());
            let artists_str: String = row.get("artists_json").unwrap_or_else(|_| "[]".to_string());
            let format_labels_str: String =
                row.get("format_labels_json").unwrap_or_else(|_| "[]".to_string());

            let genres: Vec<Genre> = serde_json::from_str(&genres_str).unwrap_or_default();
            let tags: Vec<Tag> = serde_json::from_str(&tags_str).unwrap_or_default();
            let authors: Vec<Person> = serde_json::from_str(&authors_str).unwrap_or_default();
            let artists: Vec<Person> = serde_json::from_str(&artists_str).unwrap_or_default();
            let format_labels: Vec<String> =
                serde_json::from_str(&format_labels_str).unwrap_or_default();

            Ok(MangaDetails {
                id: row.get("id")?,
                slug_url: row.get("slug_url")?,
                name: row.get("name")?,
                rus_name: row.get("rus_name")?,
                eng_name: row.get("eng_name")?,
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
                slug: row.get("slug")?,
            })
        })?;
        let mut manga_list = Vec::new();
        for item in manga_iter.flatten() {
            manga_list.push(item);
        }

        // 2. User lists
        let mut stmt2 = conn.prepare("SELECT manga_id, list_type, added_at FROM user_lists")?;
        let lists_iter = stmt2.query_map([], |row| {
            Ok(BackupUserList {
                manga_id: row.get(0)?,
                list_type: row.get(1)?,
                added_at: row.get(2)?,
            })
        })?;
        let mut user_lists = Vec::new();
        for item in lists_iter.flatten() {
            user_lists.push(item);
        }

        // 3. Reading progress
        let mut stmt3 = conn.prepare("SELECT manga_id, chapter_volume, chapter_number, page_index, scroll_position, last_read_at FROM reading_progress")?;
        let prog_iter = stmt3.query_map([], |row| {
            Ok(ReadingPosition {
                manga_id: row.get(0)?,
                chapter_volume: row.get(1)?,
                chapter_number: row.get(2)?,
                page_index: row.get(3)?,
                scroll_position: row.get(4)?,
                last_read_at: row.get(5)?,
            })
        })?;
        let mut reading_progress = Vec::new();
        for item in prog_iter.flatten() {
            reading_progress.push(item);
        }

        // 4. Chapter history
        let mut stmt4 = conn.prepare("SELECT manga_id, volume, number, page_index, total_pages, is_completed, last_read_at FROM chapter_history")?;
        let hist_iter = stmt4.query_map([], |row| {
            Ok(ChapterHistory {
                manga_id: row.get(0)?,
                volume: row.get(1)?,
                number: row.get(2)?,
                page_index: row.get(3)?,
                total_pages: row.get(4)?,
                is_completed: row.get(5)?,
                last_read_at: row.get(6)?,
            })
        })?;
        let mut chapter_history = Vec::new();
        for item in hist_iter.flatten() {
            chapter_history.push(item);
        }

        let backup = BackupData {
            version: 1,
            manga: manga_list,
            user_lists,
            reading_progress,
            chapter_history,
        };

        Ok(serde_json::to_string_pretty(&backup)?)
    })
}

pub(crate) fn import_backup_json(json_content: String) -> Result<bool> {
    let backup: BackupData = serde_json::from_str(&json_content)
        .context("Invalid backup file format")?;

    with_conn(|conn| {
        for manga in &backup.manga {
            let genres_json = serde_json::to_string(&manga.genres)?;
            let tags_json = serde_json::to_string(&manga.tags)?;
            let authors_json = serde_json::to_string(&manga.authors)?;
            let artists_json = serde_json::to_string(&manga.artists)?;
            let format_labels_json = serde_json::to_string(&manga.format_labels)?;

            conn.execute(
                "INSERT OR REPLACE INTO manga (
                    id, slug_url, name, rus_name, eng_name, cover_url, cover_thumb_url,
                    manga_type, status, rating_average, rating_votes, summary,
                    genres_json, tags_json, chapters_count, release_date,
                    last_updated, type_id, status_id, age_restriction, slug,
                    authors_json, artists_json, views_total, views_formatted,
                    format_labels_json, publisher_name
                ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, strftime('%s','now'), ?17, ?18, ?19, ?20, ?21, ?22, ?23, ?24, ?25, ?26)",
                params![
                    manga.id, manga.slug_url, manga.name, manga.rus_name, manga.eng_name,
                    manga.cover_url, manga.cover_thumb_url, manga.manga_type, manga.status,
                    manga.rating_average, manga.rating_votes, manga.summary,
                    genres_json, tags_json, manga.chapters_count, manga.release_date,
                    manga.type_id, manga.status_id, manga.age_restriction, manga.slug,
                    authors_json, artists_json, manga.views_total, manga.views_formatted,
                    format_labels_json, manga.publisher_name
                ],
            )?;
        }

        for list in &backup.user_lists {
            conn.execute(
                "INSERT OR REPLACE INTO user_lists (manga_id, list_type, added_at) VALUES (?1, ?2, ?3)",
                params![list.manga_id, list.list_type, list.added_at],
            )?;
        }

        for prog in &backup.reading_progress {
            conn.execute(
                "INSERT OR REPLACE INTO reading_progress (manga_id, chapter_volume, chapter_number, page_index, scroll_position, last_read_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                params![prog.manga_id, prog.chapter_volume, prog.chapter_number, prog.page_index, prog.scroll_position, prog.last_read_at],
            )?;
        }

        for hist in &backup.chapter_history {
            conn.execute(
                "INSERT OR REPLACE INTO chapter_history (manga_id, volume, number, page_index, total_pages, is_completed, last_read_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                params![hist.manga_id, hist.volume, hist.number, hist.page_index, hist.total_pages, hist.is_completed, hist.last_read_at],
            )?;
        }

        let _ = search::rebuild(conn);
        Ok(true)
    })
}

pub(crate) fn export_mal_xml() -> Result<String> {
    with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT m.id, m.name, m.rus_name, m.eng_name, m.chapters_count, ul.list_type,
                    (SELECT COUNT(1) FROM chapter_history ch WHERE ch.manga_id = m.id AND ch.is_completed = 1) as read_count
             FROM user_lists ul
             JOIN manga m ON m.id = ul.manga_id"
        )?;

        let mut xml = String::from("<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n<myanimelist>\n");
        xml.push_str("  <myinfo>\n    <user_export_type>2</user_export_type>\n  </myinfo>\n");

        let rows = stmt.query_map([], |row| {
            let id: i64 = row.get("id")?;
            let name: String = row.get("name")?;
            let eng_name: String = row.get("eng_name")?;
            let list_type_str: String = row.get("list_type")?;
            let read_count: i64 = row.get("read_count").unwrap_or(0);
            let chapters_count: i64 = row.get("chapters_count").unwrap_or(0);

            let mal_status = match list_type_str.as_str() {
                "reading" => "Reading",
                "completed" => "Completed",
                "on_hold" => "On-Hold",
                "dropped" => "Dropped",
                "plan_to_read" => "Plan to Read",
                _ => "Reading",
            };

            let title = if !eng_name.is_empty() { eng_name } else { name };
            let escaped_title = title.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;");

            Ok(format!(
                "  <manga>\n    <manga_mangadb_id>{}</manga_mangadb_id>\n    <manga_title><![CDATA[{}]]></manga_title>\n    <my_read_chapters>{}</my_read_chapters>\n    <my_status>{}</my_status>\n    <manga_num_chapters>{}</manga_num_chapters>\n  </manga>\n",
                id, escaped_title, read_count, mal_status, chapters_count
            ))
        })?;

        for entry in rows.flatten() {
            xml.push_str(&entry);
        }
        xml.push_str("</myanimelist>");
        Ok(xml)
    })
}

pub(crate) fn import_mal_xml(xml_content: String) -> Result<MalImportResult> {
    with_conn(|conn| {
        let mut imported = 0i64;
        let mut updated = 0i64;
        let mut failed = 0i64;

        // Simple robust tag extraction for MAL XML
        let parts: Vec<&str> = xml_content.split("<manga>").collect();
        for block in parts.into_iter().skip(1) {
            let block = match block.split("</manga>").next() {
                Some(b) => b,
                None => continue,
            };

            let extract_tag = |tag: &str| -> Option<String> {
                let start_tag = format!("<{}>", tag);
                let end_tag = format!("</{}>", tag);
                if let Some(start) = block.find(&start_tag) {
                    let after = &block[start + start_tag.len()..];
                    if let Some(end) = after.find(&end_tag) {
                        let mut val = after[..end].trim().to_string();
                        if val.starts_with("<![CDATA[") && val.ends_with("]]>") {
                            val = val[9..val.len() - 3].to_string();
                        }
                        return Some(val);
                    }
                }
                None
            };

            let mal_id = extract_tag("manga_mangadb_id").and_then(|s| s.parse::<i64>().ok());
            let title = extract_tag("manga_title").unwrap_or_default();
            let my_status = extract_tag("my_status").unwrap_or_else(|| "Reading".to_string());
            let read_chapters = extract_tag("my_read_chapters").and_then(|s| s.parse::<i64>().ok()).unwrap_or(0);

            let list_type = match my_status.to_lowercase().as_str() {
                "completed" => "completed",
                "plan to read" => "plan_to_read",
                "dropped" => "dropped",
                "on-hold" | "on hold" => "on_hold",
                _ => "reading",
            };

            if let Some(id) = mal_id {
                // Check if manga exists
                let exists: bool = conn
                    .query_row("SELECT 1 FROM manga WHERE id = ?1", params![id], |_| Ok(true))
                    .unwrap_or(false);

                if !exists && !title.is_empty() {
                    // Insert placeholder entry so user sees the title in their library
                    let _ = conn.execute(
                        "INSERT OR IGNORE INTO manga (id, slug_url, name, rus_name, eng_name, chapters_count)
                         VALUES (?1, ?2, ?3, ?3, ?3, ?4)",
                        params![id, format!("mal-{}", id), title, read_chapters],
                    );
                }

                let inserted = conn.execute(
                    "INSERT OR REPLACE INTO user_lists (manga_id, list_type, added_at) VALUES (?1, ?2, datetime('now'))",
                    params![id, list_type],
                );

                if inserted.is_ok() {
                    imported += 1;
                } else {
                    failed += 1;
                }
            } else {
                updated += 1;
            }
        }

        // Placeholder titles inserted above are new rows in the local catalog, so the
        // title index is refreshed once instead of per row.
        let _ = search::rebuild(conn);

        Ok(MalImportResult {
            imported_count: imported,
            updated_count: updated,
            failed_count: failed,
        })
    })
}