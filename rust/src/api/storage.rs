use crate::api::models::{
    DownloadedChapterInfo, DownloadedMangaGroup, LibraryEntry, ListType, MangaDetails, ReadingPosition, Genre, Tag, Person, ChapterHistory,
    Chapter, ReadingStreakInfo, ContinueReadingItem
};
use anyhow::{Context, Result};
use once_cell::sync::Lazy;
use rusqlite::{params, Connection, OptionalExtension};
use std::sync::Mutex;

static DB: Lazy<Mutex<Option<Connection>>> = Lazy::new(|| Mutex::new(None));

pub async fn init_database(app_dir: String) -> Result<()> {
    let db_path = format!("{}/mangaloader.db", app_dir);
    let conn = Connection::open(&db_path).context("Failed to open SQLite database")?;

    conn.execute_batch(
        "
        CREATE TABLE IF NOT EXISTS manga (
            id INTEGER PRIMARY KEY,
            slug_url TEXT NOT NULL UNIQUE,
            name TEXT NOT NULL,
            rus_name TEXT DEFAULT '',
            eng_name TEXT DEFAULT '',
            cover_url TEXT DEFAULT '',
            cover_thumb_url TEXT DEFAULT '',
            manga_type TEXT DEFAULT '',
            status TEXT DEFAULT '',
            rating_average TEXT DEFAULT '0',
            rating_votes TEXT DEFAULT '0',
            summary TEXT DEFAULT '',
            genres_json TEXT DEFAULT '[]',
            tags_json TEXT DEFAULT '[]',
            chapters_count INTEGER DEFAULT 0,
            release_date TEXT,
            last_updated INTEGER DEFAULT 0,
            type_id INTEGER DEFAULT 0,
            status_id INTEGER DEFAULT 0,
            age_restriction TEXT DEFAULT '',
            slug TEXT DEFAULT '',
            authors_json TEXT DEFAULT '[]',
            artists_json TEXT DEFAULT '[]',
            views_total TEXT DEFAULT '0',
            views_formatted TEXT DEFAULT '0',
            format_labels_json TEXT DEFAULT '[]',
            publisher_name TEXT
        );

        CREATE TABLE IF NOT EXISTS user_lists (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            manga_id INTEGER NOT NULL,
            list_type TEXT NOT NULL CHECK(list_type IN ('reading','plan_to_read','completed','dropped','favorites','on_hold')),
            added_at TEXT NOT NULL DEFAULT (datetime('now')),
            UNIQUE(manga_id, list_type),
            FOREIGN KEY (manga_id) REFERENCES manga(id)
        );

        CREATE TABLE IF NOT EXISTS reading_progress (
            manga_id INTEGER PRIMARY KEY,
            chapter_volume TEXT NOT NULL DEFAULT '0',
            chapter_number TEXT NOT NULL DEFAULT '0',
            page_index INTEGER DEFAULT 0,
            scroll_position REAL DEFAULT 0.0,
            last_read_at TEXT NOT NULL DEFAULT (datetime('now')),
            FOREIGN KEY (manga_id) REFERENCES manga(id)
        );

        CREATE TABLE IF NOT EXISTS downloaded_chapters (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            manga_id INTEGER NOT NULL,
            volume TEXT NOT NULL,
            number TEXT NOT NULL,
            branch_id INTEGER,
            page_count INTEGER DEFAULT 0,
            download_path TEXT NOT NULL,
            downloaded_at TEXT NOT NULL DEFAULT (datetime('now')),
            UNIQUE(manga_id, volume, number),
            FOREIGN KEY (manga_id) REFERENCES manga(id)
        );

        CREATE TABLE IF NOT EXISTS chapter_history (
            manga_id INTEGER NOT NULL,
            volume TEXT NOT NULL,
            number TEXT NOT NULL,
            page_index INTEGER DEFAULT 0,
            total_pages INTEGER DEFAULT 0,
            is_completed BOOLEAN DEFAULT 0,
            last_read_at TEXT NOT NULL DEFAULT (datetime('now')),
            PRIMARY KEY (manga_id, volume, number),
            FOREIGN KEY (manga_id) REFERENCES manga(id)
        );

        CREATE TABLE IF NOT EXISTS reading_streak (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            current_streak INTEGER NOT NULL DEFAULT 0,
            max_streak INTEGER NOT NULL DEFAULT 0,
            last_read_date TEXT NOT NULL DEFAULT '',
            today_chapters_count INTEGER NOT NULL DEFAULT 0,
            total_days_read INTEGER NOT NULL DEFAULT 0,
            total_chapters_read INTEGER NOT NULL DEFAULT 0,
            history_json TEXT NOT NULL DEFAULT '[]'
        );

        CREATE TABLE IF NOT EXISTS cached_chapters (
            manga_id INTEGER NOT NULL,
            volume TEXT NOT NULL,
            number TEXT NOT NULL,
            name TEXT DEFAULT '',
            branch_id INTEGER,
            is_paid BOOLEAN DEFAULT 0,
            created_at TEXT DEFAULT '',
            PRIMARY KEY (manga_id, volume, number)
        );
        "
    )?;

    *DB.lock().unwrap() = Some(conn);
    Ok(())
}

fn get_conn() -> Result<std::sync::MutexGuard<'static, Option<Connection>>> {
    let guard = DB.lock().unwrap();
    if guard.is_none() {
        anyhow::bail!("Database not initialized");
    }
    Ok(guard)
}

pub async fn save_manga(manga: MangaDetails) -> Result<()> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();

    let genres_json = serde_json::to_string(&manga.genres).unwrap_or_else(|_| "[]".to_string());
    let tags_json = serde_json::to_string(&manga.tags).unwrap_or_else(|_| "[]".to_string());
    let authors_json = serde_json::to_string(&manga.authors).unwrap_or_else(|_| "[]".to_string());
    let artists_json = serde_json::to_string(&manga.artists).unwrap_or_else(|_| "[]".to_string());
    let format_labels_json = serde_json::to_string(&manga.format_labels).unwrap_or_else(|_| "[]".to_string());

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
    Ok(())
}

pub async fn get_cached_manga(slug_url: String) -> Result<Option<MangaDetails>> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();

    let mut stmt = conn.prepare("SELECT * FROM manga WHERE slug_url = ?1")?;
    let row = stmt.query_row(params![slug_url], |row| {
        let genres_str: String = row.get("genres_json").unwrap_or_else(|_| "[]".to_string());
        let tags_str: String = row.get("tags_json").unwrap_or_else(|_| "[]".to_string());
        let authors_str: String = row.get("authors_json").unwrap_or_else(|_| "[]".to_string());
        let artists_str: String = row.get("artists_json").unwrap_or_else(|_| "[]".to_string());
        let format_labels_str: String = row.get("format_labels_json").unwrap_or_else(|_| "[]".to_string());

        let genres: Vec<Genre> = serde_json::from_str(&genres_str).unwrap_or_default();
        let tags: Vec<Tag> = serde_json::from_str(&tags_str).unwrap_or_default();
        let authors: Vec<Person> = serde_json::from_str(&authors_str).unwrap_or_default();
        let artists: Vec<Person> = serde_json::from_str(&artists_str).unwrap_or_default();
        let format_labels: Vec<String> = serde_json::from_str(&format_labels_str).unwrap_or_default();

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
    }).optional()?;

    Ok(row)
}

pub async fn add_to_list(manga_id: i64, list_type: String) -> Result<()> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();
    // Ensure manga is in only one user list at a time
    conn.execute(
        "DELETE FROM user_lists WHERE manga_id = ?1",
        params![manga_id],
    )?;
    conn.execute(
        "INSERT INTO user_lists (manga_id, list_type, added_at) VALUES (?1, ?2, datetime('now'))",
        params![manga_id, list_type],
    )?;
    Ok(())
}

pub async fn remove_from_list(manga_id: i64, list_type: String) -> Result<()> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();
    if list_type == "all" || list_type.is_empty() {
        conn.execute(
            "DELETE FROM user_lists WHERE manga_id = ?1",
            params![manga_id],
        )?;
    } else {
        conn.execute(
            "DELETE FROM user_lists WHERE manga_id = ?1 AND list_type = ?2",
            params![manga_id, list_type],
        )?;
    }
    Ok(())
}



pub async fn get_list(list_type: String) -> Result<Vec<LibraryEntry>> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();

    let mut stmt = conn.prepare(
        "SELECT m.id, m.slug_url, m.name, m.rus_name, m.cover_url, m.rating_average, m.chapters_count,
                ul.list_type, ul.added_at, rp.chapter_number, rp.chapter_volume, 0 as unread_count,
                COALESCE((SELECT COUNT(1) FROM chapter_history ch WHERE ch.manga_id = m.id AND ch.is_completed = 1), 0) as read_chapters_count
         FROM user_lists ul
         JOIN manga m ON m.id = ul.manga_id
         LEFT JOIN reading_progress rp ON m.id = rp.manga_id
         WHERE ul.list_type = ?1
         ORDER BY ul.added_at DESC"
    )?;

    let iter = stmt.query_map(params![list_type], |row| {
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
    })?;

    let mut res = Vec::new();
    for row in iter {
        res.push(row?);
    }
    Ok(res)
}

pub async fn get_manga_list_type(manga_id: i64) -> Result<Option<String>> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();
    let mut stmt = conn.prepare("SELECT list_type FROM user_lists WHERE manga_id = ?1 LIMIT 1")?;
    let row: Option<String> = stmt.query_row(params![manga_id], |row| row.get(0)).optional()?;
    Ok(row)
}

pub async fn save_reading_progress(progress: ReadingPosition) -> Result<()> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();
    conn.execute(
        "INSERT OR REPLACE INTO reading_progress (manga_id, chapter_volume, chapter_number, page_index, scroll_position, last_read_at)
         VALUES (?1, ?2, ?3, ?4, ?5, datetime('now'))",
        params![progress.manga_id, progress.chapter_volume, progress.chapter_number, progress.page_index, progress.scroll_position],
    )?;

    // Auto-enroll into user_lists if not already present
    let has_list: bool = conn.query_row(
        "SELECT COUNT(1) FROM user_lists WHERE manga_id = ?1",
        params![progress.manga_id],
        |r| r.get::<_, i32>(0),
    ).map(|c| c > 0).unwrap_or(false);

    if !has_list {
        let _ = conn.execute(
            "INSERT OR IGNORE INTO user_lists (manga_id, list_type, added_at) VALUES (?1, 'reading', datetime('now'))",
            params![progress.manga_id],
        );
    }

    Ok(())
}

pub async fn get_reading_progress(manga_id: i64) -> Result<Option<ReadingPosition>> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();
    let mut stmt = conn.prepare("SELECT * FROM reading_progress WHERE manga_id = ?1")?;
    let row = stmt.query_row(params![manga_id], |row| {
        Ok(ReadingPosition {
            manga_id: row.get("manga_id")?,
            chapter_volume: row.get("chapter_volume")?,
            chapter_number: row.get("chapter_number")?,
            page_index: row.get("page_index")?,
            scroll_position: row.get("scroll_position")?,
            last_read_at: row.get("last_read_at")?,
        })
    }).optional()?;
    Ok(row)
}

pub async fn mark_chapter_downloaded(
    manga_id: i64, volume: String, number: String, page_count: i64, download_path: String
) -> Result<()> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();
    conn.execute(
        "INSERT OR REPLACE INTO downloaded_chapters (manga_id, volume, number, page_count, download_path, downloaded_at)
         VALUES (?1, ?2, ?3, ?4, ?5, datetime('now'))",
        params![manga_id, volume, number, page_count, download_path],
    )?;
    Ok(())
}

pub async fn is_chapter_downloaded(manga_id: i64, volume: String, number: String) -> Result<bool> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();
    let mut stmt = conn.prepare("SELECT count(1) FROM downloaded_chapters WHERE manga_id = ?1 AND volume = ?2 AND number = ?3")?;
    let count: i32 = stmt.query_row(params![manga_id, volume, number], |row| row.get(0))?;
    Ok(count > 0)
}

fn sort_downloaded_chapters_ascending(chapters: &mut [DownloadedChapterInfo]) {
    chapters.sort_by(|a, b| {
        let vol_a = a.volume.parse::<f64>().unwrap_or(0.0);
        let vol_b = b.volume.parse::<f64>().unwrap_or(0.0);
        let num_a = a.number.parse::<f64>().unwrap_or(0.0);
        let num_b = b.number.parse::<f64>().unwrap_or(0.0);
        vol_a.partial_cmp(&vol_b).unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| num_a.partial_cmp(&num_b).unwrap_or(std::cmp::Ordering::Equal))
    });
}

pub async fn get_downloaded_chapters(manga_id: i64) -> Result<Vec<DownloadedChapterInfo>> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();
    let mut stmt = conn.prepare("SELECT * FROM downloaded_chapters WHERE manga_id = ?1")?;
    let iter = stmt.query_map(params![manga_id], |row| {
        Ok(DownloadedChapterInfo {
            id: row.get("id")?,
            manga_id: row.get("manga_id")?,
            volume: row.get("volume")?,
            number: row.get("number")?,
            branch_id: row.get("branch_id")?,
            page_count: row.get("page_count")?,
            download_path: row.get("download_path")?,
            downloaded_at: row.get("downloaded_at")?,
        })
    })?;
    
    let mut res = Vec::new();
    for r in iter {
        res.push(r?);
    }
    sort_downloaded_chapters_ascending(&mut res);
    Ok(res)
}

pub async fn get_all_downloaded_chapters() -> Result<Vec<DownloadedChapterInfo>> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();
    let mut stmt = conn.prepare("SELECT * FROM downloaded_chapters ORDER BY downloaded_at DESC")?;
    let iter = stmt.query_map([], |row| {
        Ok(DownloadedChapterInfo {
            id: row.get("id")?,
            manga_id: row.get("manga_id")?,
            volume: row.get("volume")?,
            number: row.get("number")?,
            branch_id: row.get("branch_id")?,
            page_count: row.get("page_count")?,
            download_path: row.get("download_path")?,
            downloaded_at: row.get("downloaded_at")?,
        })
    })?;
    
    let mut res = Vec::new();
    for r in iter {
        res.push(r?);
    }
    Ok(res)
}

pub async fn get_downloaded_manga_groups() -> Result<Vec<DownloadedMangaGroup>> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();

    let mut stmt = conn.prepare(
        "SELECT 
            COALESCE(m.id, dc.manga_id) as manga_id,
            COALESCE(m.slug_url, '') as slug_url,
            COALESCE(m.name, 'Unknown Manga') as name,
            COALESCE(m.rus_name, '') as rus_name,
            COALESCE(m.cover_url, '') as cover_url,
            dc.id as dc_id,
            dc.volume,
            dc.number,
            dc.branch_id,
            dc.page_count,
            dc.download_path,
            dc.downloaded_at
         FROM downloaded_chapters dc
         LEFT JOIN manga m ON dc.manga_id = m.id
         ORDER BY manga_id ASC, dc.downloaded_at DESC"
    )?;

    struct RowItem {
        manga_id: i64,
        slug_url: String,
        name: String,
        rus_name: String,
        cover_url: String,
        ch: DownloadedChapterInfo,
    }

    let iter = stmt.query_map([], |row| {
        Ok(RowItem {
            manga_id: row.get("manga_id")?,
            slug_url: row.get("slug_url")?,
            name: row.get("name")?,
            rus_name: row.get("rus_name")?,
            cover_url: row.get("cover_url")?,
            ch: DownloadedChapterInfo {
                id: row.get("dc_id")?,
                manga_id: row.get("manga_id")?,
                volume: row.get("volume")?,
                number: row.get("number")?,
                branch_id: row.get("branch_id")?,
                page_count: row.get("page_count")?,
                download_path: row.get("download_path")?,
                downloaded_at: row.get("downloaded_at")?,
            },
        })
    })?;

    let mut groups_map: std::collections::BTreeMap<i64, DownloadedMangaGroup> = std::collections::BTreeMap::new();

    for r in iter {
        let item = r?;
        let file_size = match std::fs::metadata(&item.ch.download_path) {
            Ok(meta) => meta.len() as i64,
            Err(_) => 0,
        };

        let group = groups_map.entry(item.manga_id).or_insert_with(|| DownloadedMangaGroup {
            manga_id: item.manga_id,
            slug_url: item.slug_url.clone(),
            name: item.name.clone(),
            rus_name: item.rus_name.clone(),
            cover_url: item.cover_url.clone(),
            chapters: Vec::new(),
            total_size_bytes: 0,
        });

        group.total_size_bytes += file_size;
        group.chapters.push(item.ch);
    }

    let mut list: Vec<DownloadedMangaGroup> = groups_map.into_values().collect();
    for group in &mut list {
        sort_downloaded_chapters_ascending(&mut group.chapters);
    }

    Ok(list)
}

pub async fn delete_downloaded_chapter(manga_id: i64, volume: String, number: String) -> Result<()> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();

    let path_opt: Option<String> = {
        let mut stmt = conn.prepare("SELECT download_path FROM downloaded_chapters WHERE manga_id = ?1 AND volume = ?2 AND number = ?3")?;
        stmt.query_row(params![manga_id, volume, number], |row| row.get(0)).optional()?
    };

    if let Some(path) = path_opt {
        let _ = std::fs::remove_file(&path);
    }

    conn.execute(
        "DELETE FROM downloaded_chapters WHERE manga_id = ?1 AND volume = ?2 AND number = ?3",
        params![manga_id, volume, number],
    )?;

    Ok(())
}

pub async fn delete_downloaded_manga(manga_id: i64) -> Result<()> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();

    let paths: Vec<String> = {
        let mut stmt = conn.prepare("SELECT download_path FROM downloaded_chapters WHERE manga_id = ?1")?;
        let iter = stmt.query_map(params![manga_id], |row| row.get(0))?;
        let mut list = Vec::new();
        for p in iter {
            if let Ok(p_str) = p {
                list.push(p_str);
            }
        }
        list
    };

    for path in paths {
        let _ = std::fs::remove_file(&path);
    }

    conn.execute(
        "DELETE FROM downloaded_chapters WHERE manga_id = ?1",
        params![manga_id],
    )?;

    Ok(())
}

pub async fn get_all_library_manga() -> Result<Vec<LibraryEntry>> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();
    
    let mut stmt = conn.prepare(
        "SELECT m.id, m.slug_url, m.name, m.rus_name, m.cover_url, m.rating_average, m.chapters_count,
                ul.list_type, ul.added_at, rp.chapter_number, rp.chapter_volume, 0 as unread_count,
                COALESCE((SELECT COUNT(1) FROM chapter_history ch WHERE ch.manga_id = m.id AND ch.is_completed = 1), 0) as read_chapters_count
         FROM user_lists ul
         JOIN manga m ON m.id = ul.manga_id
         LEFT JOIN reading_progress rp ON m.id = rp.manga_id
         ORDER BY ul.added_at DESC"
    )?;

    let iter = stmt.query_map([], |row| {
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
    })?;

    let mut res = Vec::new();
    for r in iter {
        res.push(r?);
    }
    Ok(res)
}

pub async fn mark_chapter_read(manga_id: i64, volume: String, number: String, page_index: i64, total_pages: i64, is_completed: bool) -> Result<()> {
    {
        let guard = get_conn()?;
        let conn = guard.as_ref().unwrap();
        conn.execute(
            "INSERT OR REPLACE INTO chapter_history (manga_id, volume, number, page_index, total_pages, is_completed, last_read_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, datetime('now'))",
            params![manga_id, volume, number, page_index, total_pages, is_completed],
        )?;
    }

    if is_completed {
        let _ = record_chapter_read_for_streak().await;
    }
    Ok(())
}

pub async fn get_reading_streak() -> Result<ReadingStreakInfo> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();

    let row = conn.query_row(
        "SELECT current_streak, max_streak, last_read_date, today_chapters_count, total_days_read, total_chapters_read, history_json
         FROM reading_streak WHERE id = 1",
        [],
        |row| {
            let hist_str: String = row.get("history_json").unwrap_or_else(|_| "[]".to_string());
            let history_dates: Vec<String> = serde_json::from_str(&hist_str).unwrap_or_default();
            Ok(ReadingStreakInfo {
                current_streak: row.get("current_streak")?,
                max_streak: row.get("max_streak")?,
                last_read_date: row.get("last_read_date")?,
                today_chapters_count: row.get("today_chapters_count")?,
                is_active_today: false,
                total_days_read: row.get("total_days_read")?,
                total_chapters_read: row.get("total_chapters_read")?,
                history_dates,
            })
        },
    ).optional()?;

    let today_str = chrono::Utc::now().format("%Y-%m-%d").to_string();
    let yesterday_str = (chrono::Utc::now() - chrono::Duration::days(1)).format("%Y-%m-%d").to_string();

    match row {
        Some(mut info) => {
            if info.last_read_date == today_str {
                info.is_active_today = true;
            } else if info.last_read_date == yesterday_str {
                info.is_active_today = false;
            } else if !info.last_read_date.is_empty() {
                info.current_streak = 0;
                info.today_chapters_count = 0;
                info.is_active_today = false;
            }
            Ok(info)
        }
        None => {
            Ok(ReadingStreakInfo {
                current_streak: 0,
                max_streak: 0,
                last_read_date: String::new(),
                today_chapters_count: 0,
                is_active_today: false,
                total_days_read: 0,
                total_chapters_read: 0,
                history_dates: Vec::new(),
            })
        }
    }
}

pub async fn record_chapter_read_for_streak() -> Result<ReadingStreakInfo> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();

    let today_str = chrono::Utc::now().format("%Y-%m-%d").to_string();
    let yesterday_str = (chrono::Utc::now() - chrono::Duration::days(1)).format("%Y-%m-%d").to_string();

    let existing = conn.query_row(
        "SELECT current_streak, max_streak, last_read_date, today_chapters_count, total_days_read, total_chapters_read, history_json
         FROM reading_streak WHERE id = 1",
        [],
        |row| {
            let hist_str: String = row.get("history_json").unwrap_or_else(|_| "[]".to_string());
            let history_dates: Vec<String> = serde_json::from_str(&hist_str).unwrap_or_default();
            Ok((
                row.get::<_, i64>("current_streak")?,
                row.get::<_, i64>("max_streak")?,
                row.get::<_, String>("last_read_date")?,
                row.get::<_, i64>("today_chapters_count")?,
                row.get::<_, i64>("total_days_read")?,
                row.get::<_, i64>("total_chapters_read")?,
                history_dates,
            ))
        },
    ).optional()?;

    let (new_streak, new_max, today_count, total_days, total_chaps, history_dates) = match existing {
        Some((curr_streak, max_s, last_date, t_count, tot_days, tot_chaps, mut h_dates)) => {
            if last_date == today_str {
                (curr_streak, max_s, t_count + 1, tot_days, tot_chaps + 1, h_dates)
            } else if last_date == yesterday_str {
                let s = curr_streak + 1;
                let m = max_s.max(s);
                if !h_dates.contains(&today_str) {
                    h_dates.push(today_str.clone());
                    if h_dates.len() > 60 { h_dates.remove(0); }
                }
                (s, m, 1, tot_days + 1, tot_chaps + 1, h_dates)
            } else {
                let s = 1;
                let m = max_s.max(1);
                if !h_dates.contains(&today_str) {
                    h_dates.push(today_str.clone());
                    if h_dates.len() > 60 { h_dates.remove(0); }
                }
                (s, m, 1, tot_days + 1, tot_chaps + 1, h_dates)
            }
        }
        None => {
            let s = 1;
            let m = 1;
            let h_dates = vec![today_str.clone()];
            (s, m, 1, 1, 1, h_dates)
        }
    };

    let hist_json = serde_json::to_string(&history_dates).unwrap_or_else(|_| "[]".to_string());

    conn.execute(
        "INSERT INTO reading_streak (id, current_streak, max_streak, last_read_date, today_chapters_count, total_days_read, total_chapters_read, history_json)
         VALUES (1, ?1, ?2, ?3, ?4, ?5, ?6, ?7)
         ON CONFLICT(id) DO UPDATE SET
            current_streak=excluded.current_streak,
            max_streak=excluded.max_streak,
            last_read_date=excluded.last_read_date,
            today_chapters_count=excluded.today_chapters_count,
            total_days_read=excluded.total_days_read,
            total_chapters_read=excluded.total_chapters_read,
            history_json=excluded.history_json",
        params![new_streak, new_max, today_str, today_count, total_days, total_chaps, hist_json],
    )?;

    Ok(ReadingStreakInfo {
        current_streak: new_streak,
        max_streak: new_max,
        last_read_date: today_str,
        today_chapters_count: today_count,
        is_active_today: true,
        total_days_read: total_days,
        total_chapters_read: total_chaps,
        history_dates,
    })
}

pub async fn sync_reading_streak(days: i64) -> Result<ReadingStreakInfo> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();

    let today_str = chrono::Utc::now().format("%Y-%m-%d").to_string();
    let max_s = days.max(1);
    let mut history_dates = Vec::new();
    let count = 7.min(days);
    for i in (0..count).rev() {
        let d = chrono::Utc::now() - chrono::Duration::days(i);
        history_dates.push(d.format("%Y-%m-%d").to_string());
    }
    let hist_json = serde_json::to_string(&history_dates).unwrap_or_else(|_| "[]".to_string());

    conn.execute(
        "INSERT INTO reading_streak (id, current_streak, max_streak, last_read_date, today_chapters_count, total_days_read, total_chapters_read, history_json)
         VALUES (1, ?1, ?2, ?3, 1, ?4, ?5, ?6)
         ON CONFLICT(id) DO UPDATE SET
            current_streak=excluded.current_streak,
            max_streak=MAX(max_streak, excluded.max_streak),
            last_read_date=excluded.last_read_date,
            today_chapters_count=excluded.today_chapters_count,
            total_days_read=MAX(total_days_read, excluded.total_days_read),
            total_chapters_read=MAX(total_chapters_read, excluded.total_chapters_read),
            history_json=excluded.history_json",
        params![days, max_s, today_str, days, days * 3, hist_json],
    )?;

    Ok(ReadingStreakInfo {
        current_streak: days,
        max_streak: max_s,
        last_read_date: today_str,
        today_chapters_count: 1,
        is_active_today: true,
        total_days_read: days,
        total_chapters_read: days * 3,
        history_dates,
    })
}

pub async fn cache_chapters(manga_id: i64, chapters: Vec<Chapter>) -> Result<()> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();

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
}

pub async fn get_cached_chapters(manga_id: i64) -> Result<Vec<Chapter>> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();

    let mut stmt = conn.prepare(
        "SELECT id, volume, number, name, branch_id, branches_count, is_paid
         FROM cached_chapters WHERE manga_id = ?1"
    )?;

    let iter = stmt.query_map(params![manga_id], |row| {
        let name: String = row.get("name")?;
        Ok(Chapter {
            id: row.get("id")?,
            volume: row.get("volume")?,
            number: row.get("number")?,
            name: if name.is_empty() { None } else { Some(name) },
            branch_id: row.get("branch_id")?,
            branches_count: row.get("branches_count")?,
            is_paid: row.get("is_paid")?,
        })
    })?;

    let mut chapters = Vec::new();
    for c in iter {
        chapters.push(c?);
    }

    if chapters.is_empty() {
        let mut d_stmt = conn.prepare(
            "SELECT volume, number, branch_id
             FROM downloaded_chapters WHERE manga_id = ?1"
        )?;
        let d_iter = d_stmt.query_map(params![manga_id], |row| {
            Ok(Chapter {
                id: 0,
                volume: row.get("volume")?,
                number: row.get("number")?,
                name: None,
                branch_id: row.get("branch_id")?,
                branches_count: 0,
                is_paid: false,
            })
        })?;
        for c in d_iter {
            chapters.push(c?);
        }
    }

    Ok(chapters)
}

pub async fn get_continue_reading_manga() -> Result<Vec<ContinueReadingItem>> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();

    let mut stmt = conn.prepare(
        "SELECT m.id, m.slug_url, m.name, m.rus_name, m.cover_url, m.chapters_count,
                rp.chapter_volume, rp.chapter_number, rp.last_read_at,
                (SELECT COUNT(1) FROM chapter_history ch WHERE ch.manga_id = m.id AND ch.is_completed = 1) as read_count
         FROM reading_progress rp
         JOIN manga m ON m.id = rp.manga_id
         ORDER BY rp.last_read_at DESC"
    )?;

    let iter = stmt.query_map([], |row| {
        let total_chaps: i64 = row.get("chapters_count").unwrap_or(0);
        let read_chaps: i64 = row.get("read_count").unwrap_or(0);
        let unread = (total_chaps - read_chaps).max(0);
        let has_new = read_chaps > 0 && unread > 0 && total_chaps > read_chaps;

        Ok(ContinueReadingItem {
            manga_id: row.get("id")?,
            slug_url: row.get("slug_url")?,
            name: row.get("name")?,
            rus_name: row.get("rus_name")?,
            cover_url: row.get("cover_url")?,
            last_read_volume: row.get("chapter_volume")?,
            last_read_chapter: row.get("chapter_number")?,
            last_read_at: row.get("last_read_at")?,
            total_chapters: total_chaps,
            read_chapters: read_chaps,
            unread_count: unread,
            has_new_chapters: has_new,
            new_chapters_count: if has_new { unread } else { 0 },
        })
    })?;

    let mut list = Vec::new();
    for item_res in iter {
        let item = item_res?;
        if item.total_chapters > 0 && item.read_chapters >= item.total_chapters {
            continue;
        }
        list.push(item);
    }

    Ok(list)
}

pub async fn get_chapter_history(manga_id: i64) -> Result<Vec<ChapterHistory>> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();
    let mut stmt = conn.prepare("SELECT * FROM chapter_history WHERE manga_id = ?1")?;
    let iter = stmt.query_map(params![manga_id], |row| {
        Ok(ChapterHistory {
            manga_id: row.get("manga_id")?,
            volume: row.get("volume")?,
            number: row.get("number")?,
            page_index: row.get("page_index")?,
            total_pages: row.get("total_pages")?,
            is_completed: row.get("is_completed")?,
            last_read_at: row.get("last_read_at")?,
        })
    })?;
    
    let mut res = Vec::new();
    for r in iter {
        res.push(r?);
    }
    Ok(res)
}

#[derive(Debug, serde::Serialize, serde::Deserialize)]
pub struct BackupData {
    pub version: i64,
    pub manga: Vec<MangaDetails>,
    pub user_lists: Vec<BackupUserList>,
    pub reading_progress: Vec<ReadingPosition>,
    pub chapter_history: Vec<ChapterHistory>,
}

#[derive(Debug, serde::Serialize, serde::Deserialize)]
pub struct BackupUserList {
    pub manga_id: i64,
    pub list_type: String,
    pub added_at: String,
}

pub async fn export_backup_json() -> Result<String> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();

    // 1. All saved manga
    let mut stmt = conn.prepare("SELECT * FROM manga")?;
    let manga_iter = stmt.query_map([], |row| {
        let genres_str: String = row.get("genres_json").unwrap_or_else(|_| "[]".to_string());
        let tags_str: String = row.get("tags_json").unwrap_or_else(|_| "[]".to_string());
        let authors_str: String = row.get("authors_json").unwrap_or_else(|_| "[]".to_string());
        let artists_str: String = row.get("artists_json").unwrap_or_else(|_| "[]".to_string());
        let format_labels_str: String = row.get("format_labels_json").unwrap_or_else(|_| "[]".to_string());

        let genres: Vec<Genre> = serde_json::from_str(&genres_str).unwrap_or_default();
        let tags: Vec<Tag> = serde_json::from_str(&tags_str).unwrap_or_default();
        let authors: Vec<Person> = serde_json::from_str(&authors_str).unwrap_or_default();
        let artists: Vec<Person> = serde_json::from_str(&artists_str).unwrap_or_default();
        let format_labels: Vec<String> = serde_json::from_str(&format_labels_str).unwrap_or_default();

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
    for m in manga_iter { if let Ok(item) = m { manga_list.push(item); } }

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
    for l in lists_iter { if let Ok(item) = l { user_lists.push(item); } }

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
    for p in prog_iter { if let Ok(item) = p { reading_progress.push(item); } }

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
    for h in hist_iter { if let Ok(item) = h { chapter_history.push(item); } }

    let backup = BackupData {
        version: 1,
        manga: manga_list,
        user_lists,
        reading_progress,
        chapter_history,
    };

    Ok(serde_json::to_string_pretty(&backup)?)
}

pub async fn import_backup_json(json_content: String) -> Result<bool> {
    let backup: BackupData = serde_json::from_str(&json_content)
        .context("Invalid backup file format")?;

    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();

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

    Ok(true)
}
