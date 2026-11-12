use anyhow::{Context, Result};
use once_cell::sync::Lazy;
use std::collections::HashMap;
use std::fs::File;
use std::io::{Read, Write};
use std::path::Path;
use std::sync::Mutex;
use std::time::SystemTime;
use zip::write::SimpleFileOptions;
use crate::api::storage::get_downloaded_chapters;

const MAX_OPEN_ARCHIVES: usize = 3;
const COMIC_INFO_NAME: &str = "ComicInfo.xml";
const IMAGE_EXTENSIONS: [&str; 6] = [".jpg", ".jpeg", ".png", ".webp", ".avif", ".gif"];

struct CachedArchive {
    archive: zip::ZipArchive<File>,
    names: Vec<String>,
    file_len: u64,
    modified: Option<SystemTime>,
    last_used: u64,
}

struct ArchiveCache {
    entries: HashMap<String, CachedArchive>,
    tick: u64,
}

static ARCHIVE_CACHE: Lazy<Mutex<ArchiveCache>> = Lazy::new(|| {
    Mutex::new(ArchiveCache {
        entries: HashMap::new(),
        tick: 0,
    })
});

pub async fn export_chapter_as_cbz(
    manga_slug: String,
    volume: String,
    number: String,
    app_dir: String,
    output_path: String,
) -> Result<String> {
    let manga_dir = format!("{}/manga/{}", app_dir, manga_slug);
    let source_cbz = format!("{}/v{}_c{}.cbz", manga_dir, volume, number);
    let legacy_dir = format!("{}/v{}_c{}", manga_dir, volume, number);

    if Path::new(&source_cbz).exists() {
        if paths_refer_to_same_file(&source_cbz, &output_path) {
            anyhow::bail!("Output path points at the downloaded archive: {}", output_path);
        }
        export_from_archive(&source_cbz, &manga_slug, &volume, &number, &output_path)?;
        return Ok(output_path);
    }

    if Path::new(&legacy_dir).exists() {
        export_from_directory(&legacy_dir, &manga_slug, &volume, &number, &output_path)?;
        return Ok(output_path);
    }

    anyhow::bail!(
        "Chapter is not downloaded: neither {} nor {} exists",
        source_cbz,
        legacy_dir
    );
}

pub async fn export_manga_as_cbz(
    manga_slug: String,
    manga_id: i64,
    app_dir: String,
    output_dir: String,
) -> Result<Vec<String>> {
    let chapters = get_downloaded_chapters(manga_id).await?;
    let mut exported_files = Vec::new();

    tokio::fs::create_dir_all(&output_dir).await.context("Failed to create output directory")?;

    for chapter in chapters {
        let output_path = format!("{}/{} - v{} c{}.cbz", output_dir, manga_slug, chapter.volume, chapter.number);
        match export_chapter_as_cbz(
            manga_slug.clone(),
            chapter.volume.clone(),
            chapter.number.clone(),
            app_dir.clone(),
            output_path.clone(),
        ).await {
            Ok(path) => exported_files.push(path),
            Err(e) => {
                eprintln!("Failed to export v{} c{}: {}", chapter.volume, chapter.number, e);
            }
        }
    }

    Ok(exported_files)
}

pub fn get_cbz_page_count(cbz_path: String) -> Result<i64> {
    with_open_archive(&cbz_path, |_archive, names| Ok(names.len() as i64))
}

pub fn read_cbz_page(cbz_path: String, page_index: i64) -> Result<Vec<u8>> {
    with_open_archive(&cbz_path, |archive, names| {
        let target = names
            .get(page_index as usize)
            .ok_or_else(|| anyhow::anyhow!("Page index {} out of range (total: {})", page_index, names.len()))?;

        let mut entry = archive
            .by_name(target)
            .with_context(|| format!("Failed to find page {} in CBZ", target))?;
        let mut buf = Vec::new();
        entry.read_to_end(&mut buf)?;
        Ok(buf)
    })
}

fn lock_cache() -> std::sync::MutexGuard<'static, ArchiveCache> {
    ARCHIVE_CACHE.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
}

/// Drops the cached handle for a path. Windows refuses to delete or replace a file
/// that still has an open handle, so callers that remove downloaded chapters must
/// evict the entry first.
pub(crate) fn invalidate_archive_cache(cbz_path: &str) {
    lock_cache().entries.remove(cbz_path);
}

/// Serves an open archive from the bounded cache, reopening it when the file on disk
/// changed. The downloader writes a `.tmp` file and renames it into place, so a new
/// length or mtime is the only reliable signal that a cached handle is obsolete;
/// a failed read also evicts the handle because the reader's position may be broken.
fn with_open_archive<T>(
    cbz_path: &str,
    action: impl FnOnce(&mut zip::ZipArchive<File>, &[String]) -> Result<T>,
) -> Result<T> {
    let metadata = std::fs::metadata(cbz_path)
        .with_context(|| format!("Failed to read CBZ metadata: {}", cbz_path))?;
    let file_len = metadata.len();
    let modified = metadata.modified().ok();

    let mut cache = lock_cache();
    cache.tick += 1;
    let tick = cache.tick;

    let is_stale = cache
        .entries
        .get(cbz_path)
        .map(|entry| entry.file_len != file_len || entry.modified != modified)
        .unwrap_or(true);
    if is_stale {
        cache.entries.remove(cbz_path);
    }

    if !cache.entries.contains_key(cbz_path) {
        while cache.entries.len() >= MAX_OPEN_ARCHIVES {
            let oldest = cache
                .entries
                .iter()
                .min_by_key(|(_, entry)| entry.last_used)
                .map(|(key, _)| key.clone());
            match oldest {
                Some(key) => {
                    cache.entries.remove(&key);
                }
                None => break,
            }
        }
        // Opening parses the whole central directory, so a partially written or corrupt
        // archive fails here and never reaches the cache.
        cache.entries.insert(cbz_path.to_string(), open_archive(cbz_path, file_len, modified)?);
    }

    let result = {
        let entry = cache
            .entries
            .get_mut(cbz_path)
            .expect("archive inserted into cache above");
        entry.last_used = tick;
        action(&mut entry.archive, &entry.names)
    };

    if result.is_err() {
        cache.entries.remove(cbz_path);
    }
    result
}

fn open_archive(cbz_path: &str, file_len: u64, modified: Option<SystemTime>) -> Result<CachedArchive> {
    let file = File::open(cbz_path).with_context(|| format!("Failed to open CBZ file: {}", cbz_path))?;
    let mut archive = zip::ZipArchive::new(file)
        .with_context(|| format!("Failed to read CBZ archive: {}", cbz_path))?;

    let mut names = Vec::new();
    for index in 0..archive.len() {
        if let Ok(entry) = archive.by_index_raw(index) {
            let name = entry.name().to_string();
            if is_image_entry(&name) {
                names.push(name);
            }
        }
    }
    names.sort();

    Ok(CachedArchive {
        archive,
        names,
        file_len,
        modified,
        last_used: 0,
    })
}

fn is_image_entry(name: &str) -> bool {
    let lower = name.to_ascii_lowercase();
    IMAGE_EXTENSIONS.iter().any(|ext| lower.ends_with(ext))
}

fn paths_refer_to_same_file(first: &str, second: &str) -> bool {
    match (std::fs::canonicalize(first), std::fs::canonicalize(second)) {
        (Ok(first), Ok(second)) => first == second,
        _ => false,
    }
}

fn stored_options() -> SimpleFileOptions {
    SimpleFileOptions::default().compression_method(zip::CompressionMethod::Stored)
}

fn escape_xml_text(value: &str) -> String {
    let mut escaped = String::with_capacity(value.len());
    for ch in value.chars() {
        match ch {
            '&' => escaped.push_str("&amp;"),
            '<' => escaped.push_str("&lt;"),
            '>' => escaped.push_str("&gt;"),
            '"' => escaped.push_str("&quot;"),
            '\'' => escaped.push_str("&apos;"),
            _ => escaped.push(ch),
        }
    }
    escaped
}

fn comic_info_xml(series: &str, volume: &str, number: &str, page_count: i64) -> String {
    format!(
        r#"<?xml version="1.0" encoding="utf-8"?>
<ComicInfo xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
  <Series>{}</Series>
  <Volume>{}</Volume>
  <Number>{}</Number>
  <PageCount>{}</PageCount>
  <Manga>YesAndRightToLeft</Manga>
</ComicInfo>"#,
        escape_xml_text(series),
        escape_xml_text(volume),
        escape_xml_text(number),
        page_count
    )
}

/// Rewrites the downloaded archive into the export file. Images are already compressed,
/// so entries are stored verbatim instead of being deflated again on the device.
fn export_from_archive(
    source_cbz: &str,
    series: &str,
    volume: &str,
    number: &str,
    output_path: &str,
) -> Result<()> {
    let source_file = File::open(source_cbz)
        .with_context(|| format!("Failed to open source CBZ: {}", source_cbz))?;
    let mut source = zip::ZipArchive::new(source_file)
        .with_context(|| format!("Failed to read source CBZ: {}", source_cbz))?;

    let output_file = File::create(output_path).context("Failed to create CBZ file")?;
    let mut writer = zip::ZipWriter::new(output_file);
    let options = stored_options();

    let mut page_count = 0i64;
    let mut has_comic_info = false;

    for index in 0..source.len() {
        let mut entry = match source.by_index(index) {
            Ok(entry) => entry,
            Err(_) => continue,
        };
        if entry.is_dir() {
            continue;
        }

        let name = entry.name().to_string();
        if name.eq_ignore_ascii_case(COMIC_INFO_NAME) {
            has_comic_info = true;
        }
        if is_image_entry(&name) {
            page_count += 1;
        }

        writer
            .start_file(&name, options)
            .with_context(|| format!("Failed to add {} to CBZ", name))?;
        std::io::copy(&mut entry, &mut writer)
            .with_context(|| format!("Failed to copy {} into CBZ", name))?;
    }

    if !has_comic_info {
        writer
            .start_file(COMIC_INFO_NAME, options)
            .context("Failed to start ComicInfo.xml")?;
        writer
            .write_all(comic_info_xml(series, volume, number, page_count).as_bytes())
            .context("Failed to write ComicInfo.xml")?;
    }

    writer.finish().context("Failed to finalize zip")?;
    Ok(())
}

fn export_from_directory(
    source_dir: &str,
    series: &str,
    volume: &str,
    number: &str,
    output_path: &str,
) -> Result<()> {
    let file = File::create(output_path).context("Failed to create CBZ file")?;
    let mut zip = zip::ZipWriter::new(file);
    let options = SimpleFileOptions::default().compression_method(zip::CompressionMethod::Deflated);

    let mut entries: Vec<_> = std::fs::read_dir(source_dir)?
        .filter_map(|e| e.ok())
        .collect();

    entries.sort_by_key(|e| e.file_name());

    let mut page_count = 0;
    for entry in entries {
        let path = entry.path();
        if path.is_file() {
            let file_name = entry.file_name().to_string_lossy().to_string();
            zip.start_file(&file_name, options).context("Failed to start file in zip")?;
            let mut f = File::open(&path).context("Failed to open image file")?;
            let mut buffer = Vec::new();
            f.read_to_end(&mut buffer)?;
            zip.write_all(&buffer).context("Failed to write to zip")?;
            page_count += 1;
        }
    }

    zip.start_file(COMIC_INFO_NAME, options).context("Failed to start ComicInfo.xml")?;
    zip.write_all(comic_info_xml(series, volume, number, page_count).as_bytes())
        .context("Failed to write ComicInfo.xml")?;

    zip.finish().context("Failed to finalize zip")?;
    Ok(())
}