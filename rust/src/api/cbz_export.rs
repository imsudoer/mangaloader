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

/// Pixel size of a page image. Zeroes mean the header was not recognised, and
/// the reader then falls back to a portrait estimate for that page.
pub struct CbzPageSize {
    pub width: i64,
    pub height: i64,
}

pub fn get_cbz_page_count(cbz_path: String) -> Result<i64> {
    with_open_archive(&cbz_path, |_archive, names| Ok(names.len() as i64))
}

/// Reads only the image headers, which is what the reader needs to reserve the
/// exact height of every page before any of them is decoded. Full pages can be
/// multi-megabyte webtoon strips, so decoding them just to learn the aspect ratio
/// would stall the first frame of a chapter.
pub fn get_cbz_page_sizes(cbz_path: String) -> Result<Vec<CbzPageSize>> {
    with_open_archive(&cbz_path, |archive, names| {
        let mut sizes = Vec::with_capacity(names.len());
        for name in names {
            let mut entry = archive
                .by_name(name)
                .with_context(|| format!("Failed to find page {} in CBZ", name))?;
            let mut header = Vec::with_capacity(8192);
            let mut chunk = [0u8; 8192];
            let mut found = None;
            while header.len() < 256 * 1024 {
                let read = entry.read(&mut chunk)?;
                if read == 0 {
                    break;
                }
                header.extend_from_slice(&chunk[..read]);
                if let Some(size) = image_dimensions(&header) {
                    found = Some(size);
                    break;
                }
            }
            let (width, height) = found.unwrap_or((0, 0));
            sizes.push(CbzPageSize {
                width: width as i64,
                height: height as i64,
            });
        }
        Ok(sizes)
    })
}

fn image_dimensions(bytes: &[u8]) -> Option<(u32, u32)> {
    if bytes.len() >= 24 && bytes.starts_with(&[0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A]) {
        let width = u32::from_be_bytes(bytes[16..20].try_into().ok()?);
        let height = u32::from_be_bytes(bytes[20..24].try_into().ok()?);
        return (width > 0 && height > 0).then_some((width, height));
    }
    if bytes.len() >= 10 && bytes.starts_with(b"GIF8") {
        let width = u16::from_le_bytes(bytes[6..8].try_into().ok()?) as u32;
        let height = u16::from_le_bytes(bytes[8..10].try_into().ok()?) as u32;
        return (width > 0 && height > 0).then_some((width, height));
    }
    if bytes.starts_with(&[0xFF, 0xD8]) {
        return jpeg_dimensions(bytes);
    }
    if bytes.len() >= 12 && &bytes[0..4] == b"RIFF" && &bytes[8..12] == b"WEBP" {
        return webp_dimensions(bytes);
    }
    if bytes.len() >= 12 && (&bytes[4..12] == b"ftypavif" || &bytes[4..12] == b"ftypavis") {
        return avif_dimensions(bytes);
    }
    None
}

fn jpeg_dimensions(bytes: &[u8]) -> Option<(u32, u32)> {
    let mut index = 2;
    while index + 9 <= bytes.len() {
        if bytes[index] != 0xFF {
            index += 1;
            continue;
        }
        let marker = bytes[index + 1];
        if marker == 0xD8 || marker == 0x01 || (0xD0..=0xD7).contains(&marker) {
            index += 2;
            continue;
        }
        if marker == 0xDA || marker == 0xD9 {
            return None;
        }
        let length = u16::from_be_bytes([bytes[index + 2], bytes[index + 3]]) as usize;
        let is_sof = matches!(
            marker,
            0xC0..=0xC3 | 0xC5..=0xC7 | 0xC9..=0xCB | 0xCD..=0xCF
        );
        if is_sof {
            let height = u16::from_be_bytes([bytes[index + 5], bytes[index + 6]]) as u32;
            let width = u16::from_be_bytes([bytes[index + 7], bytes[index + 8]]) as u32;
            return (width > 0 && height > 0).then_some((width, height));
        }
        if length < 2 {
            return None;
        }
        index += 2 + length;
    }
    None
}

fn webp_dimensions(bytes: &[u8]) -> Option<(u32, u32)> {
    let mut index = 12;
    while index + 8 <= bytes.len() {
        let tag = &bytes[index..index + 4];
        let size = u32::from_le_bytes(bytes[index + 4..index + 8].try_into().ok()?) as usize;
        let data = bytes.get(index + 8..)?;
        match tag {
            b"VP8X" if data.len() >= 10 => {
                let width = 1 + u32::from_le_bytes([data[4], data[5], data[6], 0]);
                let height = 1 + u32::from_le_bytes([data[7], data[8], data[9], 0]);
                return (width > 1 && height > 1).then_some((width, height));
            }
            b"VP8 " if data.len() >= 10 && data[3..6] == [0x9D, 0x01, 0x2A] => {
                let width = (u16::from_le_bytes([data[6], data[7]]) & 0x3FFF) as u32;
                let height = (u16::from_le_bytes([data[8], data[9]]) & 0x3FFF) as u32;
                return (width > 0 && height > 0).then_some((width, height));
            }
            b"VP8L" if data.len() >= 5 && data[0] == 0x2F => {
                let bits = u32::from_le_bytes([data[1], data[2], data[3], data[4]]);
                let width = (bits & 0x3FFF) + 1;
                let height = ((bits >> 14) & 0x3FFF) + 1;
                return Some((width, height));
            }
            _ => {}
        }
        index += 8 + size + (size & 1);
    }
    None
}

fn avif_dimensions(bytes: &[u8]) -> Option<(u32, u32)> {
    let offset = bytes.windows(4).position(|window| window == b"ispe")?;
    if offset + 16 > bytes.len() {
        return None;
    }
    let width = u32::from_be_bytes(bytes[offset + 8..offset + 12].try_into().ok()?);
    let height = u32::from_be_bytes(bytes[offset + 12..offset + 16].try_into().ok()?);
    (width > 0 && height > 0).then_some((width, height))
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
#[cfg(test)]
mod page_size_tests {
    use super::image_dimensions;

    #[test]
    fn reads_png_header() {
        let mut bytes = vec![0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A];
        bytes.extend_from_slice(&13u32.to_be_bytes());
        bytes.extend_from_slice(b"IHDR");
        bytes.extend_from_slice(&760u32.to_be_bytes());
        bytes.extend_from_slice(&11521u32.to_be_bytes());
        assert_eq!(image_dimensions(&bytes), Some((760, 11521)));
    }

    #[test]
    fn reads_jpeg_sof() {
        let mut bytes = vec![0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x04, 0x00, 0x00];
        bytes.extend_from_slice(&[0xFF, 0xC0, 0x00, 0x11, 0x08]);
        bytes.extend_from_slice(&1200u16.to_be_bytes());
        bytes.extend_from_slice(&800u16.to_be_bytes());
        bytes.extend_from_slice(&[0x03, 0x01, 0x11, 0x00, 0x02, 0x11, 0x00, 0x03, 0x11, 0x00]);
        assert_eq!(image_dimensions(&bytes), Some((800, 1200)));
    }

    #[test]
    fn reads_lossless_webp_header() {
        let mut bytes = Vec::new();
        bytes.extend_from_slice(b"RIFF");
        bytes.extend_from_slice(&0u32.to_le_bytes());
        bytes.extend_from_slice(b"WEBPVP8L");
        bytes.extend_from_slice(&5u32.to_le_bytes());
        bytes.push(0x2F);
        let bits = (11520u32 << 14) | 759u32;
        bytes.extend_from_slice(&bits.to_le_bytes());
        assert_eq!(image_dimensions(&bytes), Some((760, 11521)));
    }

    #[test]
    fn rejects_unknown_headers() {
        assert_eq!(image_dimensions(b"not an image at all"), None);
    }
}
