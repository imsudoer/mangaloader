//! Library lists (built-in and custom) plus per-manga custom tags.

use crate::api::models::{CustomUserList, LibraryEntry, ListType};
use crate::api::storage::with_conn;
use anyhow::Result;
use rusqlite::{params, OptionalExtension};

pub(crate) fn add_to_list(manga_id: i64, list_type: &str) -> Result<()> {
    with_conn(|conn| {
        // Ensure manga is in only one user list at a time
        conn.execute("DELETE FROM user_lists WHERE manga_id = ?1", params![manga_id])?;
        conn.execute(
            "INSERT INTO user_lists (manga_id, list_type, added_at) VALUES (?1, ?2, datetime('now'))",
            params![manga_id, list_type],
        )?;
        Ok(())
    })
}

pub(crate) fn remove_from_list(manga_id: i64, list_type: &str) -> Result<()> {
    with_conn(|conn| {
        if list_type == "all" || list_type.is_empty() {
            conn.execute("DELETE FROM user_lists WHERE manga_id = ?1", params![manga_id])?;
        } else {
            conn.execute(
                "DELETE FROM user_lists WHERE manga_id = ?1 AND list_type = ?2",
                params![manga_id, list_type],
            )?;
        }
        Ok(())
    })
}

pub(crate) fn get_list(list_type: &str) -> Result<Vec<LibraryEntry>> {
    with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT m.id, m.slug_url, m.name, m.rus_name, m.cover_url, m.rating_average, m.chapters_count,
                    ul.list_type, ul.added_at, rp.chapter_number, rp.chapter_volume,
                    MAX(m.chapters_count - COALESCE((SELECT COUNT(1) FROM chapter_history ch WHERE ch.manga_id = m.id AND ch.is_completed = 1), 0), 0) as unread_count,
                    COALESCE((SELECT COUNT(1) FROM chapter_history ch WHERE ch.manga_id = m.id AND ch.is_completed = 1), 0) as read_chapters_count
             FROM user_lists ul
             JOIN manga m ON m.id = ul.manga_id
             LEFT JOIN reading_progress rp ON m.id = rp.manga_id
             WHERE ul.list_type = ?1
             ORDER BY ul.added_at DESC"
        )?;

        let iter = stmt.query_map(params![list_type], map_library_entry)?;

        let mut res = Vec::new();
        for row in iter {
            res.push(row?);
        }
        Ok(res)
    })
}

pub(crate) fn get_all_library_manga() -> Result<Vec<LibraryEntry>> {
    with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT m.id, m.slug_url, m.name, m.rus_name, m.cover_url, m.rating_average, m.chapters_count,
                    ul.list_type, ul.added_at, rp.chapter_number, rp.chapter_volume,
                    MAX(m.chapters_count - COALESCE((SELECT COUNT(1) FROM chapter_history ch WHERE ch.manga_id = m.id AND ch.is_completed = 1), 0), 0) as unread_count,
                    COALESCE((SELECT COUNT(1) FROM chapter_history ch WHERE ch.manga_id = m.id AND ch.is_completed = 1), 0) as read_chapters_count
             FROM user_lists ul
             JOIN manga m ON m.id = ul.manga_id
             LEFT JOIN reading_progress rp ON m.id = rp.manga_id
             ORDER BY ul.added_at DESC"
        )?;

        let iter = stmt.query_map([], map_library_entry)?;

        let mut res = Vec::new();
        for r in iter {
            res.push(r?);
        }
        Ok(res)
    })
}

fn map_library_entry(row: &rusqlite::Row<'_>) -> rusqlite::Result<LibraryEntry> {
    let lt_str: String = row.get("list_type")?;
    let list_type_enum = ListType::from_str(&lt_str).unwrap_or(ListType::Reading);

    Ok(LibraryEntry {
        manga_id: row.get("id")?,
        slug_url: row.get("slug_url")?,
        name: row.get("name")?,
        rus_name: row.get("rus_name")?,
        cover_url: row.get("cover_url")?,
        list_type: list_type_enum,
        added_at: row.get("added_at")?,
        last_read_chapter: row.get("chapter_number")?,
        last_read_volume: row.get("chapter_volume")?,
        unread_count: row.get("unread_count")?,
        rating_average: row.get("rating_average")?,
        total_chapters: row.get("chapters_count").unwrap_or(0),
        read_chapters: row.get("read_chapters_count").unwrap_or(0),
    })
}

pub(crate) fn get_manga_list_type(manga_id: i64) -> Result<Option<String>> {
    with_conn(|conn| {
        let mut stmt = conn.prepare("SELECT list_type FROM user_lists WHERE manga_id = ?1 LIMIT 1")?;
        let row: Option<String> = stmt
            .query_row(params![manga_id], |row| row.get(0))
            .optional()?;
        Ok(row)
    })
}

pub(crate) fn get_custom_lists() -> Result<Vec<CustomUserList>> {
    with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT l.id, l.name, l.color, l.created_at,
                    (SELECT COUNT(1) FROM custom_list_items cli WHERE cli.list_id = l.id) as items_count
             FROM custom_user_lists l
             ORDER BY l.created_at ASC"
        )?;

        let iter = stmt.query_map([], |row| {
            Ok(CustomUserList {
                id: row.get("id")?,
                name: row.get("name")?,
                color: row.get("color")?,
                created_at: row.get("created_at")?,
                items_count: row.get("items_count")?,
            })
        })?;

        let mut list = Vec::new();
        for item in iter {
            list.push(item?);
        }
        Ok(list)
    })
}

pub(crate) fn create_custom_list(name: String, color: String) -> Result<CustomUserList> {
    with_conn(|conn| {
        let clean_name = name.trim().to_string();
        if clean_name.is_empty() {
            anyhow::bail!("List name cannot be empty");
        }
        let col = if color.trim().is_empty() { "#8A897C".to_string() } else { color.trim().to_string() };

        conn.execute(
            "INSERT INTO custom_user_lists (name, color) VALUES (?1, ?2)",
            params![clean_name, col],
        )?;

        let id = conn.last_insert_rowid();
        let created_at = chrono::Utc::now().to_rfc3339();

        Ok(CustomUserList {
            id,
            name: clean_name,
            color: col,
            created_at,
            items_count: 0,
        })
    })
}

pub(crate) fn delete_custom_list(list_id: i64) -> Result<()> {
    with_conn(|conn| {
        conn.execute("DELETE FROM custom_list_items WHERE list_id = ?1", params![list_id])?;
        conn.execute("DELETE FROM custom_user_lists WHERE id = ?1", params![list_id])?;
        Ok(())
    })
}

pub(crate) fn add_to_custom_list(list_id: i64, manga_id: i64) -> Result<()> {
    with_conn(|conn| {
        conn.execute(
            "INSERT OR IGNORE INTO custom_list_items (list_id, manga_id) VALUES (?1, ?2)",
            params![list_id, manga_id],
        )?;
        Ok(())
    })
}

pub(crate) fn remove_from_custom_list(list_id: i64, manga_id: i64) -> Result<()> {
    with_conn(|conn| {
        conn.execute(
            "DELETE FROM custom_list_items WHERE list_id = ?1 AND manga_id = ?2",
            params![list_id, manga_id],
        )?;
        Ok(())
    })
}

pub(crate) fn get_manga_custom_lists(manga_id: i64) -> Result<Vec<i64>> {
    with_conn(|conn| {
        let mut stmt = conn.prepare("SELECT list_id FROM custom_list_items WHERE manga_id = ?1")?;
        let iter = stmt.query_map(params![manga_id], |row| row.get::<_, i64>(0))?;
        let mut list = Vec::new();
        for id in iter {
            list.push(id?);
        }
        Ok(list)
    })
}

pub(crate) fn get_custom_list_entries(list_id: i64) -> Result<Vec<LibraryEntry>> {
    with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT m.id, m.slug_url, m.name, m.rus_name, m.cover_url, cli.added_at,
                    m.rating_average, m.chapters_count,
                    rp.chapter_volume, rp.chapter_number,
                    (SELECT COUNT(1) FROM chapter_history ch WHERE ch.manga_id = m.id AND ch.is_completed = 1) as read_count
             FROM custom_list_items cli
             JOIN manga m ON m.id = cli.manga_id
             LEFT JOIN reading_progress rp ON rp.manga_id = m.id
             WHERE cli.list_id = ?1
             ORDER BY cli.added_at DESC"
        )?;

        let iter = stmt.query_map(params![list_id], |row| {
            let total_chaps: i64 = row.get("chapters_count").unwrap_or(0);
            let read_chaps: i64 = row.get("read_count").unwrap_or(0);
            let unread = (total_chaps - read_chaps).max(0);

            Ok(LibraryEntry {
                manga_id: row.get("id")?,
                slug_url: row.get("slug_url")?,
                name: row.get("name")?,
                rus_name: row.get("rus_name")?,
                cover_url: row.get("cover_url")?,
                list_type: ListType::Reading,
                added_at: row.get("added_at")?,
                last_read_volume: row.get("chapter_volume")?,
                last_read_chapter: row.get("chapter_number")?,
                unread_count: unread,
                rating_average: row.get("rating_average")?,
                total_chapters: total_chaps,
                read_chapters: read_chaps,
            })
        })?;

        let mut list = Vec::new();
        for item in iter {
            list.push(item?);
        }
        Ok(list)
    })
}

pub(crate) fn add_custom_tag(manga_id: i64, tag_name: String) -> Result<()> {
    with_conn(|conn| {
        let clean = tag_name.trim().to_string();
        if !clean.is_empty() {
            conn.execute(
                "INSERT OR IGNORE INTO manga_custom_tags (manga_id, tag_name) VALUES (?1, ?2)",
                params![manga_id, clean],
            )?;
        }
        Ok(())
    })
}

pub(crate) fn remove_custom_tag(manga_id: i64, tag_name: String) -> Result<()> {
    with_conn(|conn| {
        conn.execute(
            "DELETE FROM manga_custom_tags WHERE manga_id = ?1 AND tag_name = ?2",
            params![manga_id, tag_name.trim()],
        )?;
        Ok(())
    })
}

pub(crate) fn get_custom_tags(manga_id: i64) -> Result<Vec<String>> {
    with_conn(|conn| {
        let mut stmt =
            conn.prepare("SELECT tag_name FROM manga_custom_tags WHERE manga_id = ?1 ORDER BY id ASC")?;
        let iter = stmt.query_map(params![manga_id], |row| row.get::<_, String>(0))?;
        let mut list = Vec::new();
        for t in iter {
            list.push(t?);
        }
        Ok(list)
    })
}

pub(crate) fn get_all_custom_tags() -> Result<Vec<String>> {
    with_conn(|conn| {
        let mut stmt =
            conn.prepare("SELECT DISTINCT tag_name FROM manga_custom_tags ORDER BY tag_name ASC")?;
        let iter = stmt.query_map([], |row| row.get::<_, String>(0))?;
        let mut list = Vec::new();
        for t in iter {
            list.push(t?);
        }
        Ok(list)
    })
}