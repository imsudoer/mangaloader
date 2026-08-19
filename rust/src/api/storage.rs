use crate::api::models::{
    DownloadedChapterInfo, DownloadedMangaGroup, LibraryEntry, ListType, MangaDetails, ReadingPosition, Genre, Tag, Person, ChapterHistory,
    Chapter, ReadingStreakInfo, ContinueReadingItem, CustomUserList, ReadingStatistics, GenreCount, TimeOfDayDistribution, MalImportResult,
    AppSettingItem, MangaRecapData, RecapMangaItem, MangaSearchResult
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
            id INTEGER DEFAULT 0,
            name TEXT DEFAULT '',
            branch_id INTEGER,
            branches_count INTEGER DEFAULT 0,
            is_paid BOOLEAN DEFAULT 0,
            created_at TEXT DEFAULT '',
            PRIMARY KEY (manga_id, volume, number)
        );

        CREATE TABLE IF NOT EXISTS custom_user_lists (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            color TEXT DEFAULT '#8A897C',
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );

        CREATE TABLE IF NOT EXISTS custom_list_items (
            list_id INTEGER NOT NULL,
            manga_id INTEGER NOT NULL,
            added_at TEXT NOT NULL DEFAULT (datetime('now')),
            PRIMARY KEY(list_id, manga_id),
            FOREIGN KEY(list_id) REFERENCES custom_user_lists(id) ON DELETE CASCADE,
            FOREIGN KEY(manga_id) REFERENCES manga(id)
        );

        CREATE TABLE IF NOT EXISTS manga_custom_tags (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            manga_id INTEGER NOT NULL,
            tag_name TEXT NOT NULL,
            UNIQUE(manga_id, tag_name),
            FOREIGN KEY(manga_id) REFERENCES manga(id)
        );

        CREATE TABLE IF NOT EXISTS app_settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        "
    )?;

    // Safe column additions for older database versions
    let migrations = [
        "ALTER TABLE manga ADD COLUMN views_total TEXT DEFAULT '0'",
        "ALTER TABLE manga ADD COLUMN views_formatted TEXT DEFAULT '0'",
        "ALTER TABLE manga ADD COLUMN format_labels_json TEXT DEFAULT '[]'",
        "ALTER TABLE manga ADD COLUMN publisher_name TEXT",
        "ALTER TABLE manga ADD COLUMN slug TEXT DEFAULT ''",
        "ALTER TABLE manga ADD COLUMN type_id INTEGER DEFAULT 0",
        "ALTER TABLE manga ADD COLUMN status_id INTEGER DEFAULT 0",
        "ALTER TABLE manga ADD COLUMN age_restriction TEXT DEFAULT ''",
        "ALTER TABLE manga ADD COLUMN authors_json TEXT DEFAULT '[]'",
        "ALTER TABLE manga ADD COLUMN artists_json TEXT DEFAULT '[]'",
        "ALTER TABLE cached_chapters ADD COLUMN id INTEGER DEFAULT 0",
        "ALTER TABLE cached_chapters ADD COLUMN branches_count INTEGER DEFAULT 0",
    ];
    for sql in migrations {
        let _ = conn.execute(sql, []);
    }

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

pub async fn bulk_import_bookmarks(items: Vec<MangaSearchResult>, list_type: String) -> Result<i64> {
    let mut guard = get_conn()?;
    let conn = guard.as_mut().unwrap();
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
    Ok(count)
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
    for c in iter {
        if let Ok(chap) = c {
            chapters.push(chap);
        }
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

// ==========================================
// Custom Lists & Custom Tags
// ==========================================

pub async fn get_custom_lists() -> Result<Vec<CustomUserList>> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();

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
}

pub async fn create_custom_list(name: String, color: String) -> Result<CustomUserList> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();

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
}

pub async fn delete_custom_list(list_id: i64) -> Result<()> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();

    conn.execute("DELETE FROM custom_list_items WHERE list_id = ?1", params![list_id])?;
    conn.execute("DELETE FROM custom_user_lists WHERE id = ?1", params![list_id])?;
    Ok(())
}

pub async fn add_to_custom_list(list_id: i64, manga_id: i64) -> Result<()> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();

    conn.execute(
        "INSERT OR IGNORE INTO custom_list_items (list_id, manga_id) VALUES (?1, ?2)",
        params![list_id, manga_id],
    )?;
    Ok(())
}

pub async fn remove_from_custom_list(list_id: i64, manga_id: i64) -> Result<()> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();

    conn.execute(
        "DELETE FROM custom_list_items WHERE list_id = ?1 AND manga_id = ?2",
        params![list_id, manga_id],
    )?;
    Ok(())
}

pub async fn get_manga_custom_lists(manga_id: i64) -> Result<Vec<i64>> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();

    let mut stmt = conn.prepare("SELECT list_id FROM custom_list_items WHERE manga_id = ?1")?;
    let iter = stmt.query_map(params![manga_id], |row| row.get::<_, i64>(0))?;
    let mut list = Vec::new();
    for id in iter {
        list.push(id?);
    }
    Ok(list)
}

pub async fn get_custom_list_entries(list_id: i64) -> Result<Vec<LibraryEntry>> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();

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
}

pub async fn add_custom_tag(manga_id: i64, tag_name: String) -> Result<()> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();

    let clean = tag_name.trim().to_string();
    if !clean.is_empty() {
        conn.execute(
            "INSERT OR IGNORE INTO manga_custom_tags (manga_id, tag_name) VALUES (?1, ?2)",
            params![manga_id, clean],
        )?;
    }
    Ok(())
}

pub async fn remove_custom_tag(manga_id: i64, tag_name: String) -> Result<()> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();

    conn.execute(
        "DELETE FROM manga_custom_tags WHERE manga_id = ?1 AND tag_name = ?2",
        params![manga_id, tag_name.trim()],
    )?;
    Ok(())
}

pub async fn get_custom_tags(manga_id: i64) -> Result<Vec<String>> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();

    let mut stmt = conn.prepare("SELECT tag_name FROM manga_custom_tags WHERE manga_id = ?1 ORDER BY id ASC")?;
    let iter = stmt.query_map(params![manga_id], |row| row.get::<_, String>(0))?;
    let mut list = Vec::new();
    for t in iter {
        list.push(t?);
    }
    Ok(list)
}

pub async fn get_all_custom_tags() -> Result<Vec<String>> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();

    let mut stmt = conn.prepare("SELECT DISTINCT tag_name FROM manga_custom_tags ORDER BY tag_name ASC")?;
    let iter = stmt.query_map([], |row| row.get::<_, String>(0))?;
    let mut list = Vec::new();
    for t in iter {
        list.push(t?);
    }
    Ok(list)
}

// ==========================================
// Reading Statistics
// ==========================================

pub async fn get_reading_statistics() -> Result<ReadingStatistics> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();

    // 1. Total chapters read and pages read
    let (total_chaps_read, total_pages_read): (i64, i64) = conn.query_row(
        "SELECT COUNT(1), COALESCE(SUM(total_pages), 0) FROM chapter_history WHERE is_completed = 1",
        [],
        |row| Ok((row.get(0)?, row.get(1)?)),
    ).unwrap_or((0, 0));

    // 2. Library counts
    let completed_count: i64 = conn.query_row(
        "SELECT COUNT(1) FROM user_lists WHERE list_type = 'completed'",
        [],
        |row| row.get(0),
    ).unwrap_or(0);

    let in_progress_count: i64 = conn.query_row(
        "SELECT COUNT(1) FROM user_lists WHERE list_type = 'reading'",
        [],
        |row| row.get(0),
    ).unwrap_or(0);

    let total_lib_count: i64 = conn.query_row(
        "SELECT COUNT(DISTINCT manga_id) FROM user_lists",
        [],
        |row| row.get(0),
    ).unwrap_or(0);

    let total_downloads: i64 = conn.query_row(
        "SELECT COUNT(1) FROM downloaded_chapters",
        [],
        |row| row.get(0),
    ).unwrap_or(0);

    // 3. Streak info
    let (cur_streak, max_streak, total_active_days): (i64, i64, i64) = conn.query_row(
        "SELECT current_streak, max_streak, total_days_read FROM reading_streak WHERE id = 1",
        [],
        |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
    ).unwrap_or((0, 0, 0));

    // 4. Genre breakdown
    let mut genre_counts: std::collections::HashMap<String, i64> = std::collections::HashMap::new();
    let mut stmt = conn.prepare("SELECT genres_json FROM manga WHERE id IN (SELECT DISTINCT manga_id FROM chapter_history)")?;
    let rows = stmt.query_map([], |row| row.get::<_, String>(0))?;
    for r in rows {
        if let Ok(json_str) = r {
            if let Ok(genres) = serde_json::from_str::<Vec<Genre>>(&json_str) {
                for g in genres {
                    *genre_counts.entry(g.name).or_insert(0) += 1;
                }
            }
        }
    }

    let total_genres_weight: i64 = genre_counts.values().sum();
    let mut top_genres: Vec<GenreCount> = genre_counts.into_iter().map(|(name, count)| {
        let pct = if total_genres_weight > 0 {
            (count as f64 / total_genres_weight as f64) * 100.0
        } else {
            0.0
        };
        GenreCount { name, count, percentage: (pct * 10.0).round() / 10.0 }
    }).collect();
    top_genres.sort_by(|a, b| b.count.cmp(&a.count));
    top_genres.truncate(8);

    // 5. Time of day distribution
    let mut time_stmt = conn.prepare("SELECT strftime('%H', last_read_at) FROM chapter_history")?;
    let time_rows = time_stmt.query_map([], |row| row.get::<_, Option<String>>(0))?;
    let mut night = 0i64;
    let mut morning = 0i64;
    let mut afternoon = 0i64;
    let mut evening = 0i64;

    for tr in time_rows {
        if let Ok(Some(h_str)) = tr {
            if let Ok(h) = h_str.parse::<i32>() {
                if h < 6 {
                    night += 1;
                } else if h < 12 {
                    morning += 1;
                } else if h < 18 {
                    afternoon += 1;
                } else {
                    evening += 1;
                }
            }
        }
    }

    Ok(ReadingStatistics {
        total_chapters_read: total_chaps_read,
        total_pages_read: total_pages_read,
        completed_manga_count: completed_count,
        in_progress_manga_count: in_progress_count,
        total_library_count: total_lib_count,
        total_downloaded_chapters: total_downloads,
        current_streak_days: cur_streak,
        max_streak_days: max_streak,
        total_active_days: total_active_days,
        top_genres,
        time_of_day: TimeOfDayDistribution {
            night_count: night,
            morning_count: morning,
            afternoon_count: afternoon,
            evening_count: evening,
        },
    })
}

// ==========================================
// MAL (MyAnimeList) XML Export / Import
// ==========================================

pub async fn export_mal_xml() -> Result<String> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();

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

    for r in rows {
        if let Ok(entry) = r {
            xml.push_str(&entry);
        }
    }
    xml.push_str("</myanimelist>");
    Ok(xml)
}

pub async fn import_mal_xml(xml_content: String) -> Result<MalImportResult> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();

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
            let exists: bool = conn.query_row(
                "SELECT 1 FROM manga WHERE id = ?1",
                params![id],
                |_| Ok(true),
            ).unwrap_or(false);

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

    Ok(MalImportResult {
        imported_count: imported,
        updated_count: updated,
        failed_count: failed,
    })
}

pub async fn get_setting(key: String) -> Result<Option<String>> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();

    let mut stmt = conn.prepare("SELECT value FROM app_settings WHERE key = ?1")?;
    let mut rows = stmt.query(params![key])?;

    if let Some(row) = rows.next()? {
        Ok(Some(row.get(0)?))
    } else {
        Ok(None)
    }
}

pub async fn set_setting(key: String, value: String) -> Result<()> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();

    conn.execute(
        "INSERT OR REPLACE INTO app_settings (key, value) VALUES (?1, ?2)",
        params![key, value],
    )?;

    Ok(())
}

pub async fn get_all_settings() -> Result<Vec<AppSettingItem>> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();

    let mut stmt = conn.prepare("SELECT key, value FROM app_settings")?;
    let rows = stmt.query_map([], |row| {
        Ok(AppSettingItem {
            key: row.get(0)?,
            value: row.get(1)?,
        })
    })?;

    let mut items = Vec::new();
    for row in rows {
        if let Ok(item) = row {
            items.push(item);
        }
    }

    Ok(items)
}

pub async fn get_manga_recap() -> Result<MangaRecapData> {
    let guard = get_conn()?;
    let conn = guard.as_ref().unwrap();

    // Total chapters & pages read from chapter_history
    let (total_chapters_read, total_pages_read): (i64, i64) = conn.query_row(
        "SELECT COUNT(*), COALESCE(SUM(total_pages), 0) FROM chapter_history WHERE is_completed = 1 OR page_index > 0",
        [],
        |row| Ok((row.get(0)?, row.get(1)?)),
    ).unwrap_or((0, 0));

    // Reading streak stats
    let (current_streak, max_streak, total_days): (i64, i64, i64) = conn.query_row(
        "SELECT current_streak, max_streak, total_days_read FROM reading_streak WHERE id = 1",
        [],
        |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
    ).unwrap_or((0, 0, 0));

    // Top read manga
    let mut stmt_manga = conn.prepare(
        "SELECT m.id, m.name, m.rus_name, m.cover_url, COUNT(h.number) as chaps_count
         FROM chapter_history h
         JOIN manga m ON h.manga_id = m.id
         GROUP BY m.id
         ORDER BY chaps_count DESC
         LIMIT 5",
    )?;

    let manga_rows = stmt_manga.query_map([], |row| {
        Ok(RecapMangaItem {
            manga_id: row.get(0)?,
            name: row.get(1)?,
            rus_name: row.get(2)?,
            cover_url: row.get(3)?,
            chapters_read: row.get(4)?,
        })
    })?;

    let mut top_manga = Vec::new();
    for row in manga_rows {
        if let Ok(item) = row {
            top_manga.push(item);
        }
    }

    // Top genres
    let mut stmt_genres = conn.prepare(
        "SELECT m.genres_json FROM chapter_history h
         JOIN manga m ON h.manga_id = m.id
         WHERE m.genres_json IS NOT NULL AND m.genres_json != '[]'",
    )?;

    let mut genre_counts: std::collections::HashMap<String, i64> = std::collections::HashMap::new();
    let mut total_genre_hits = 0i64;

    let genre_rows = stmt_genres.query_map([], |row| {
        let json_str: String = row.get(0)?;
        Ok(json_str)
    })?;

    for json_res in genre_rows {
        if let Ok(json_str) = json_res {
            if let Ok(genres) = serde_json::from_str::<Vec<Genre>>(&json_str) {
                for g in genres {
                    *genre_counts.entry(g.name).or_insert(0) += 1;
                    total_genre_hits += 1;
                }
            }
        }
    }

    let mut top_genres: Vec<GenreCount> = genre_counts
        .into_iter()
        .map(|(name, count)| {
            let pct = if total_genre_hits > 0 {
                (count as f64 / total_genre_hits as f64) * 100.0
            } else {
                0.0
            };
            GenreCount {
                name,
                count,
                percentage: (pct * 10.0).round() / 10.0,
            }
        })
        .collect();

    top_genres.sort_by(|a, b| b.count.cmp(&a.count));
    top_genres.truncate(5);

    // Time of day distribution from chapter_history
    let mut stmt_time = conn.prepare(
        "SELECT strftime('%H', last_read_at) as read_hour FROM chapter_history",
    )?;

    let mut night = 0i64;
    let mut morning = 0i64;
    let mut afternoon = 0i64;
    let mut evening = 0i64;

    let time_rows = stmt_time.query_map([], |row| {
        let hour_str: Option<String> = row.get(0)?;
        Ok(hour_str.and_then(|s| s.parse::<i64>().ok()).unwrap_or(12))
    })?;

    for h_res in time_rows {
        if let Ok(hour) = h_res {
            if hour < 6 {
                night += 1;
            } else if hour < 12 {
                morning += 1;
            } else if hour < 18 {
                afternoon += 1;
            } else {
                evening += 1;
            }
        }
    }

    let estimated_reading_hours = (total_chapters_read as f64 * 3.5) / 60.0;

    Ok(MangaRecapData {
        total_chapters_read,
        total_pages_read,
        estimated_reading_hours: (estimated_reading_hours * 10.0).round() / 10.0,
        current_streak,
        max_streak,
        active_days_count: total_days,
        top_genres,
        top_manga,
        time_of_day: TimeOfDayDistribution {
            night_count: night,
            morning_count: morning,
            afternoon_count: afternoon,
            evening_count: evening,
        },
    })
}


