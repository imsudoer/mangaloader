use anyhow::{Context, Result};
use std::fs::File;
use std::io::{Read, Write};
use std::path::Path;
use zip::write::SimpleFileOptions;
use crate::api::storage::get_downloaded_chapters;

pub async fn export_chapter_as_cbz(
    manga_slug: String,
    volume: String,
    number: String,
    app_dir: String,
    output_path: String,
) -> Result<String> {
    let source_dir = format!("{}/manga/{}/v{}_c{}", app_dir, manga_slug, volume, number);
    
    if !Path::new(&source_dir).exists() {
        anyhow::bail!("Chapter directory does not exist: {}", source_dir);
    }

    let file = File::create(&output_path).context("Failed to create CBZ file")?;
    let mut zip = zip::ZipWriter::new(file);
    let options = SimpleFileOptions::default().compression_method(zip::CompressionMethod::Deflated);

    let mut entries: Vec<_> = std::fs::read_dir(&source_dir)?
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

    // Generate and embed standard ComicInfo.xml
    let comic_info = format!(
        r#"<?xml version="1.0" encoding="utf-8"?>
<ComicInfo xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
  <Series>{}</Series>
  <Volume>{}</Volume>
  <Number>{}</Number>
  <PageCount>{}</PageCount>
  <Manga>YesAndRightToLeft</Manga>
</ComicInfo>"#,
        manga_slug, volume, number, page_count
    );
    zip.start_file("ComicInfo.xml", options).context("Failed to start ComicInfo.xml")?;
    zip.write_all(comic_info.as_bytes()).context("Failed to write ComicInfo.xml")?;

    zip.finish().context("Failed to finalize zip")?;
    Ok(output_path)
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
    let file = File::open(&cbz_path).context("Failed to open CBZ file")?;
    let mut archive = zip::ZipArchive::new(file).context("Failed to read CBZ archive")?;
    let mut count = 0;
    for i in 0..archive.len() {
        if let Ok(entry) = archive.by_index_raw(i) {
            let name = entry.name().to_lowercase();
            if name.ends_with(".jpg") || name.ends_with(".jpeg") || name.ends_with(".png") || name.ends_with(".webp") || name.ends_with(".avif") || name.ends_with(".gif") {
                count += 1;
            }
        }
    }
    Ok(count)
}

pub fn read_cbz_page(cbz_path: String, page_index: i64) -> Result<Vec<u8>> {
    let file = File::open(&cbz_path).context("Failed to open CBZ file")?;
    let mut archive = zip::ZipArchive::new(file).context("Failed to read CBZ archive")?;
    
    // Collect and sort image entry names
    let mut names: Vec<String> = Vec::new();
    for i in 0..archive.len() {
        if let Ok(entry) = archive.by_index_raw(i) {
            let name = entry.name().to_string();
            let lower = name.to_lowercase();
            if lower.ends_with(".jpg") || lower.ends_with(".jpeg") || lower.ends_with(".png") || lower.ends_with(".webp") || lower.ends_with(".avif") || lower.ends_with(".gif") {
                names.push(name);
            }
        }
    }
    names.sort();
    
    let target = names.get(page_index as usize)
        .ok_or_else(|| anyhow::anyhow!("Page index {} out of range (total: {})", page_index, names.len()))?;
    
    let mut entry = archive.by_name(target).context("Failed to find page in CBZ")?;
    let mut buf = Vec::new();
    entry.read_to_end(&mut buf)?;
    Ok(buf)
}
