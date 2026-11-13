//! Local SQLite persistence.
//!
//! This file is the public facade generated bindings talk to (`crate::api::storage::*`).
//! Everything implementation-shaped lives in the submodules; the functions below only
//! keep the exact signature and delegate, so `frb_generated.rs` never needs to know
//! how the storage layer is organised.

mod downloads;
mod library;
mod manga;
mod search;
mod settings;
mod stats;

use crate::api::models::{
    AppSettingItem, Chapter, ChapterHistory, ContinueReadingItem, CustomUserList,
    DownloadedChapterInfo, DownloadedMangaGroup, LibraryEntry, MalImportResult, MangaDetails,
    MangaRecapData, MangaSearchResult, ReadingHistoryItem, ReadingPosition, ReadingSessionInfo,
    ReadingStatistics, ReadingStreakInfo, RecommendedManga,
};
use anyhow::{Context, Result};
use once_cell::sync::Lazy;
use rusqlite::Connection;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;

static DB: Lazy<Mutex<Option<Connection>>> = Lazy::new(|| Mutex::new(None));
pub(crate) static FTS_AVAILABLE: AtomicBool = AtomicBool::new(false);

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

fn get_conn() -> Result<std::sync::MutexGuard<'static, Option<Connection>>> {
    let guard = DB.lock().unwrap();
    if guard.is_none() {
        anyhow::bail!("Database not initialized");
    }
    Ok(guard)
}

/// Runs `f` with the single shared connection. Store code is synchronous by design:
/// the mutex guard must never be held across an `.await`, so the `async` facade
/// functions below do their work entirely inside one of these closures.
pub(crate) fn with_conn<T>(f: impl FnOnce(&Connection) -> Result<T>) -> Result<T> {
    let guard = get_conn()?;
    match guard.as_ref() {
        Some(conn) => f(conn),
        None => anyhow::bail!("Database not initialized"),
    }
}

pub(crate) fn with_conn_mut<T>(f: impl FnOnce(&mut Connection) -> Result<T>) -> Result<T> {
    let mut guard = get_conn()?;
    match guard.as_mut() {
        Some(conn) => f(conn),
        None => anyhow::bail!("Database not initialized"),
    }
}

pub async fn init_database(app_dir: String) -> Result<()> {
    let db_path = format!("{}/mangaloader.db", app_dir);
    let conn = Connection::open(&db_path).context("Failed to open SQLite database")?;

    // The background isolate opens its own connection to the same file. WAL plus a
    // generous busy timeout keeps concurrent readers/writers from failing with
    // "database is locked" while notifications are checked in the background.
    conn.execute_batch(
        "PRAGMA journal_mode = WAL;
         PRAGMA synchronous = NORMAL;
         PRAGMA busy_timeout = 5000;
         PRAGMA foreign_keys = ON;",
    )?;

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

        CREATE TABLE IF NOT EXISTS reading_sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            manga_id INTEGER NOT NULL,
            session_seconds INTEGER NOT NULL,
            started_at TEXT NOT NULL DEFAULT (datetime('now')),
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
        "ALTER TABLE cached_chapters ADD COLUMN page_count INTEGER DEFAULT 0",
    ];
    for sql in migrations {
        let _ = conn.execute(sql, []);
    }

    // Indexes for the hot lookups (list filters, history merges, statistics joins).
    let _ = conn.execute_batch(
        "CREATE INDEX IF NOT EXISTS idx_user_lists_type ON user_lists(list_type);
         CREATE INDEX IF NOT EXISTS idx_user_lists_manga ON user_lists(manga_id);
         CREATE INDEX IF NOT EXISTS idx_progress_last_read ON reading_progress(last_read_at DESC);
         CREATE INDEX IF NOT EXISTS idx_history_manga ON chapter_history(manga_id);
         CREATE INDEX IF NOT EXISTS idx_history_completed ON chapter_history(is_completed);
         CREATE INDEX IF NOT EXISTS idx_cached_chapters_manga ON cached_chapters(manga_id);
         CREATE INDEX IF NOT EXISTS idx_downloaded_manga ON downloaded_chapters(manga_id);
         CREATE INDEX IF NOT EXISTS idx_sessions_manga ON reading_sessions(manga_id);
         CREATE INDEX IF NOT EXISTS idx_custom_items_manga ON custom_list_items(manga_id);
         CREATE INDEX IF NOT EXISTS idx_custom_tags_manga ON manga_custom_tags(manga_id);",
    );

    let fts_ready = search::init_fts(&conn);
    FTS_AVAILABLE.store(fts_ready, Ordering::Relaxed);

    *DB.lock().unwrap() = Some(conn);
    Ok(())
}

// ---------------------------------------------------------------------------
// Manga cache
// ---------------------------------------------------------------------------

pub async fn save_manga(manga: MangaDetails) -> Result<()> {
    manga::save_manga(manga)
}

pub async fn get_cached_manga(slug_url: String) -> Result<Option<MangaDetails>> {
    manga::get_cached_manga(&slug_url)
}

pub async fn bulk_import_bookmarks(
    items: Vec<MangaSearchResult>,
    list_type: String,
) -> Result<i64> {
    manga::bulk_import_bookmarks(items, &list_type)
}

pub async fn cache_chapters(manga_id: i64, chapters: Vec<Chapter>) -> Result<()> {
    manga::cache_chapters(manga_id, chapters)
}

pub async fn get_cached_chapters(manga_id: i64) -> Result<Vec<Chapter>> {
    manga::get_cached_chapters(manga_id)
}

pub async fn update_manga_chapters_count(manga_id: i64, chapters_count: i64) -> Result<()> {
    manga::update_manga_chapters_count(manga_id, chapters_count)
}

// ---------------------------------------------------------------------------
// Library lists, custom lists and custom tags
// ---------------------------------------------------------------------------

pub async fn add_to_list(manga_id: i64, list_type: String) -> Result<()> {
    library::add_to_list(manga_id, &list_type)
}

pub async fn remove_from_list(manga_id: i64, list_type: String) -> Result<()> {
    library::remove_from_list(manga_id, &list_type)
}

pub async fn get_list(list_type: String) -> Result<Vec<LibraryEntry>> {
    library::get_list(&list_type)
}

pub async fn get_all_library_manga() -> Result<Vec<LibraryEntry>> {
    library::get_all_library_manga()
}

pub async fn get_manga_list_type(manga_id: i64) -> Result<Option<String>> {
    library::get_manga_list_type(manga_id)
}

pub async fn get_custom_lists() -> Result<Vec<CustomUserList>> {
    library::get_custom_lists()
}

pub async fn create_custom_list(name: String, color: String) -> Result<CustomUserList> {
    library::create_custom_list(name, color)
}

pub async fn delete_custom_list(list_id: i64) -> Result<()> {
    library::delete_custom_list(list_id)
}

pub async fn add_to_custom_list(list_id: i64, manga_id: i64) -> Result<()> {
    library::add_to_custom_list(list_id, manga_id)
}

pub async fn remove_from_custom_list(list_id: i64, manga_id: i64) -> Result<()> {
    library::remove_from_custom_list(list_id, manga_id)
}

pub async fn get_manga_custom_lists(manga_id: i64) -> Result<Vec<i64>> {
    library::get_manga_custom_lists(manga_id)
}

pub async fn get_custom_list_entries(list_id: i64) -> Result<Vec<LibraryEntry>> {
    library::get_custom_list_entries(list_id)
}

pub async fn add_custom_tag(manga_id: i64, tag_name: String) -> Result<()> {
    library::add_custom_tag(manga_id, tag_name)
}

pub async fn remove_custom_tag(manga_id: i64, tag_name: String) -> Result<()> {
    library::remove_custom_tag(manga_id, tag_name)
}

pub async fn get_custom_tags(manga_id: i64) -> Result<Vec<String>> {
    library::get_custom_tags(manga_id)
}

pub async fn get_all_custom_tags() -> Result<Vec<String>> {
    library::get_all_custom_tags()
}

// ---------------------------------------------------------------------------
// Downloads
// ---------------------------------------------------------------------------

pub async fn mark_chapter_downloaded(
    manga_id: i64,
    volume: String,
    number: String,
    page_count: i64,
    download_path: String,
) -> Result<()> {
    downloads::mark_chapter_downloaded(manga_id, volume, number, page_count, download_path)
}

pub async fn is_chapter_downloaded(
    manga_id: i64,
    volume: String,
    number: String,
) -> Result<bool> {
    downloads::is_chapter_downloaded(manga_id, &volume, &number)
}

pub async fn get_downloaded_chapters(manga_id: i64) -> Result<Vec<DownloadedChapterInfo>> {
    downloads::get_downloaded_chapters(manga_id)
}

pub async fn get_all_downloaded_chapters() -> Result<Vec<DownloadedChapterInfo>> {
    downloads::get_all_downloaded_chapters()
}

pub async fn get_downloaded_manga_groups() -> Result<Vec<DownloadedMangaGroup>> {
    downloads::get_downloaded_manga_groups()
}

pub async fn delete_downloaded_chapter(
    manga_id: i64,
    volume: String,
    number: String,
) -> Result<()> {
    downloads::delete_downloaded_chapter(manga_id, &volume, &number)
}

pub async fn delete_downloaded_manga(manga_id: i64) -> Result<()> {
    downloads::delete_downloaded_manga(manga_id)
}

// ---------------------------------------------------------------------------
// Reading progress, history, streaks and statistics
// ---------------------------------------------------------------------------

pub async fn save_reading_progress(progress: ReadingPosition) -> Result<()> {
    stats::save_reading_progress(progress)
}

pub async fn get_reading_progress(manga_id: i64) -> Result<Option<ReadingPosition>> {
    stats::get_reading_progress(manga_id)
}

pub async fn mark_chapter_read(
    manga_id: i64,
    volume: String,
    number: String,
    page_index: i64,
    total_pages: i64,
    is_completed: bool,
) -> Result<()> {
    stats::mark_chapter_read(manga_id, volume, number, page_index, total_pages, is_completed)
}

pub async fn get_reading_streak() -> Result<ReadingStreakInfo> {
    stats::get_reading_streak()
}

pub async fn record_chapter_read_for_streak() -> Result<ReadingStreakInfo> {
    stats::record_chapter_read_for_streak()
}

pub async fn sync_reading_streak(days: i64) -> Result<ReadingStreakInfo> {
    stats::sync_reading_streak(days)
}

pub async fn get_chapter_history(manga_id: i64) -> Result<Vec<ChapterHistory>> {
    stats::get_chapter_history(manga_id)
}

pub async fn get_reading_statistics() -> Result<ReadingStatistics> {
    stats::get_reading_statistics()
}

pub async fn get_manga_recap() -> Result<MangaRecapData> {
    stats::get_manga_recap()
}

pub async fn record_reading_session(manga_id: i64, seconds: i64) -> Result<()> {
    stats::record_reading_session(manga_id, seconds)
}

pub async fn get_reading_session_stats() -> Result<ReadingSessionInfo> {
    stats::get_reading_session_stats()
}

pub async fn get_reading_history(limit: i64, offset: i64) -> Result<Vec<ReadingHistoryItem>> {
    stats::get_reading_history(limit, offset)
}

pub async fn delete_reading_history_item(
    manga_id: i64,
    volume: String,
    number: String,
) -> Result<()> {
    stats::delete_reading_history_item(manga_id, &volume, &number)
}

pub async fn clear_reading_history() -> Result<()> {
    stats::clear_reading_history()
}

pub async fn get_recommendations(limit: i64) -> Result<Vec<RecommendedManga>> {
    stats::get_recommendations(limit)
}

pub async fn get_continue_reading_manga() -> Result<Vec<ContinueReadingItem>> {
    stats::get_continue_reading_manga()
}

// ---------------------------------------------------------------------------
// Settings and import/export
// ---------------------------------------------------------------------------

pub async fn get_setting(key: String) -> Result<Option<String>> {
    settings::get_setting(key)
}

pub async fn set_setting(key: String, value: String) -> Result<()> {
    settings::set_setting(key, value)
}

pub async fn get_all_settings() -> Result<Vec<AppSettingItem>> {
    settings::get_all_settings()
}

pub async fn export_backup_json() -> Result<String> {
    settings::export_backup_json()
}

pub async fn import_backup_json(json_content: String) -> Result<bool> {
    settings::import_backup_json(json_content)
}

pub async fn export_mal_xml() -> Result<String> {
    settings::export_mal_xml()
}

pub async fn import_mal_xml(xml_content: String) -> Result<MalImportResult> {
    settings::import_mal_xml(xml_content)
}

// ---------------------------------------------------------------------------
// Offline search
// ---------------------------------------------------------------------------

pub async fn search_library(query: String, limit: i64) -> Result<Vec<MangaSearchResult>> {
    search::search_library(query, limit)
}