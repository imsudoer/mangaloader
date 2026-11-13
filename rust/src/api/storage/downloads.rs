//! Locally downloaded chapters and their on-disk payloads.

use crate::api::models::{DownloadedChapterInfo, DownloadedMangaGroup};
use crate::api::storage::with_conn;
use anyhow::Result;
use rusqlite::{params, OptionalExtension};

pub(crate) fn mark_chapter_downloaded(
    manga_id: i64,
    volume: String,
    number: String,
    page_count: i64,
    download_path: String,
) -> Result<()> {
    with_conn(|conn| {
        conn.execute(
            "INSERT OR REPLACE INTO downloaded_chapters (manga_id, volume, number, page_count, download_path, downloaded_at)
             VALUES (?1, ?2, ?3, ?4, ?5, datetime('now'))",
            params![manga_id, volume, number, page_count, download_path],
        )?;
        Ok(())
    })
}

pub(crate) fn is_chapter_downloaded(manga_id: i64, volume: &str, number: &str) -> Result<bool> {
    with_conn(|conn| {
        let mut stmt = conn.prepare("SELECT count(1) FROM downloaded_chapters WHERE manga_id = ?1 AND volume = ?2 AND number = ?3")?;
        let count: i32 = stmt.query_row(params![manga_id, volume, number], |row| row.get(0))?;
        Ok(count > 0)
    })
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

pub(crate) fn get_downloaded_chapters(manga_id: i64) -> Result<Vec<DownloadedChapterInfo>> {
    with_conn(|conn| {
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
    })
}

pub(crate) fn get_all_downloaded_chapters() -> Result<Vec<DownloadedChapterInfo>> {
    with_conn(|conn| {
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
    })
}

pub(crate) fn get_downloaded_manga_groups() -> Result<Vec<DownloadedMangaGroup>> {
    with_conn(|conn| {
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

        let mut groups_map: std::collections::BTreeMap<i64, DownloadedMangaGroup> =
            std::collections::BTreeMap::new();

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
    })
}

pub(crate) fn delete_downloaded_chapter(
    manga_id: i64,
    volume: &str,
    number: &str,
) -> Result<()> {
    with_conn(|conn| {
        let path_opt: Option<String> = {
            let mut stmt = conn.prepare("SELECT download_path FROM downloaded_chapters WHERE manga_id = ?1 AND volume = ?2 AND number = ?3")?;
            stmt.query_row(params![manga_id, volume, number], |row| row.get(0))
                .optional()?
        };

        if let Some(path) = path_opt {
            crate::api::cbz_export::invalidate_archive_cache(&path);
            let _ = std::fs::remove_file(&path);
        }

        conn.execute(
            "DELETE FROM downloaded_chapters WHERE manga_id = ?1 AND volume = ?2 AND number = ?3",
            params![manga_id, volume, number],
        )?;

        Ok(())
    })
}

pub(crate) fn delete_downloaded_manga(manga_id: i64) -> Result<()> {
    with_conn(|conn| {
        let paths: Vec<String> = {
            let mut stmt =
                conn.prepare("SELECT download_path FROM downloaded_chapters WHERE manga_id = ?1")?;
            let iter = stmt.query_map(params![manga_id], |row| row.get(0))?;
            let mut list = Vec::new();
            for p_str in iter.flatten() {
                list.push(p_str);
            }
            list
        };

        for path in paths {
            crate::api::cbz_export::invalidate_archive_cache(&path);
            let _ = std::fs::remove_file(&path);
        }

        conn.execute("DELETE FROM downloaded_chapters WHERE manga_id = ?1", params![manga_id])?;

        Ok(())
    })
}