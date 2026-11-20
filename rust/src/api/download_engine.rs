use crate::api::mangalib_client::{download_image, find_working_cdn, get_chapter_pages};
use crate::api::models::{ChapterDownloadRequest, DownloadProgress, DownloadState};
use crate::api::storage::mark_chapter_downloaded;
use anyhow::{Context, Result};
use once_cell::sync::Lazy;
use std::io::Write;
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tokio::time::{sleep, Duration};
use zip::write::SimpleFileOptions;
use crate::frb_generated::StreamSink;

static DOWNLOAD_ACTIVE: Lazy<Arc<AtomicBool>> = Lazy::new(|| Arc::new(AtomicBool::new(true)));
static DOWNLOAD_CANCELLED: Lazy<Arc<AtomicBool>> = Lazy::new(|| Arc::new(AtomicBool::new(false)));

#[flutter_rust_bridge::frb(sync)]
pub fn pause_downloads() {
    DOWNLOAD_ACTIVE.store(false, Ordering::SeqCst);
}

#[flutter_rust_bridge::frb(sync)]
pub fn resume_downloads() {
    DOWNLOAD_ACTIVE.store(true, Ordering::SeqCst);
}

#[flutter_rust_bridge::frb(sync)]
pub fn cancel_downloads() {
    DOWNLOAD_CANCELLED.store(true, Ordering::SeqCst);
}

fn is_valid_image_data(bytes: &[u8]) -> bool {
    if bytes.len() < 400 {
        return false;
    }
    // JPEG
    if bytes.starts_with(&[0xFF, 0xD8, 0xFF]) {
        return true;
    }
    // PNG
    if bytes.starts_with(&[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
        return true;
    }
    // WEBP: RIFF....WEBP
    if bytes.len() >= 12 && &bytes[0..4] == b"RIFF" && &bytes[8..12] == b"WEBP" {
        return true;
    }
    // GIF
    if bytes.starts_with(b"GIF8") {
        return true;
    }
    // AVIF
    if bytes.len() >= 12 && (&bytes[4..12] == b"ftypavif" || &bytes[4..12] == b"ftypavis") {
        return true;
    }
    // Fallback for unknown extensions: non-HTML and sufficient size
    bytes.len() > 2048 && !bytes.starts_with(b"<!DOCTYPE") && !bytes.starts_with(b"<html")
}

fn normalize_page_path(page_url: &str) -> String {
    if page_url.starts_with("//manga") {
        page_url.replacen("//manga", "/manga", 1)
    } else if page_url.starts_with("//") {
        page_url.replacen("//", "/", 1)
    } else if page_url.starts_with('/') {
        page_url.to_string()
    } else {
        format!("/{}", page_url)
    }
}

const MAX_PAGE_ATTEMPTS: i64 = 8;

/// One HTTP attempt for a page. Retries, CDN switching and progress reporting are
/// handled by the batch loop so several pages can be in flight at once.
async fn fetch_page_bytes(page_url: &str, cdn_base: &str) -> Option<Vec<u8>> {
    let clean_path = normalize_page_path(page_url);
    let full_url = format!("{}{}", cdn_base, clean_path);
    match download_image(full_url).await {
        Ok(bytes) if is_valid_image_data(&bytes) => Some(bytes),
        _ => None,
    }
}

fn write_page(
    zip: &mut zip::ZipWriter<std::fs::File>,
    options: SimpleFileOptions,
    page_url: &str,
    index: usize,
    data: &[u8],
    downloaded_bytes: &mut i64,
) -> Result<()> {
    let ext = Path::new(page_url)
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("jpg");
    let arcname = format!("{:04}.{}", index + 1, ext);
    zip.start_file(&arcname, options)
        .context("Failed to start file in CBZ")?;
    zip.write_all(data)
        .context("Failed to write image to CBZ")?;
    *downloaded_bytes += data.len() as i64;
    Ok(())
}

pub async fn start_chapter_download(
    slug_url: String,
    manga_id: i64,
    chapters: Vec<ChapterDownloadRequest>,
    app_dir: String,
    concurrent_images: i64,
    sink: StreamSink<DownloadProgress>,
) -> Result<()> {
    DOWNLOAD_CANCELLED.store(false, Ordering::SeqCst);
    DOWNLOAD_ACTIVE.store(true, Ordering::SeqCst);

    let window = concurrent_images.clamp(1, 16) as usize;

    let total_chapters = chapters.len() as i64;
    let manga_dir = format!("{}/manga/{}", app_dir, slug_url);
    tokio::fs::create_dir_all(&manga_dir).await.context("Failed to create manga directory")?;

    for (chap_idx, chapter) in chapters.iter().enumerate() {
        if DOWNLOAD_CANCELLED.load(Ordering::SeqCst) {
            break;
        }

        let current_chapter = chap_idx as i64 + 1;
        let mut progress = DownloadProgress {
            manga_slug: slug_url.clone(),
            chapter_number: chapter.number.clone(),
            chapter_volume: chapter.volume.clone(),
            current_page: 0,
            total_pages: 0,
            current_chapter,
            total_chapters,
            bytes_downloaded: 0,
            state: DownloadState::Queued,
            error_message: None,
        };

        let cbz_path = format!("{}/v{}_c{}.cbz", manga_dir, chapter.volume, chapter.number);

        // Skip if already downloaded
        if Path::new(&cbz_path).exists() {
            progress.state = DownloadState::Completed;
            progress.current_page = 1;
            progress.total_pages = 1;
            let _ = sink.add(progress.clone());
            continue;
        }

        let _ = sink.add(progress.clone());

        // Get pages with reconnect retries
        let mut pages = Vec::new();
        let mut page_retry_delay = 2;
        let mut page_retries = 0;

        loop {
            if DOWNLOAD_CANCELLED.load(Ordering::SeqCst) { break; }
            while !DOWNLOAD_ACTIVE.load(Ordering::SeqCst) && !DOWNLOAD_CANCELLED.load(Ordering::SeqCst) {
                progress.state = DownloadState::Paused;
                let _ = sink.add(progress.clone());
                sleep(Duration::from_millis(500)).await;
            }
            if DOWNLOAD_CANCELLED.load(Ordering::SeqCst) { break; }

            match get_chapter_pages(
                slug_url.clone(),
                chapter.volume.clone(),
                chapter.number.clone(),
                chapter.branch_id,
            ).await {
                Ok(p) => {
                    pages = p;
                    break;
                }
                Err(e) => {
                    page_retries += 1;
                    if page_retries > 10 {
                        progress.state = DownloadState::Failed;
                        progress.error_message = Some(e.to_string());
                        let _ = sink.add(progress.clone());
                        break;
                    }
                    progress.state = DownloadState::WaitingForNetwork;
                    progress.error_message = None;
                    let _ = sink.add(progress.clone());
                    sleep(Duration::from_secs(page_retry_delay)).await;
                    page_retry_delay = (page_retry_delay * 2).min(20);
                }
            }
        }

        if pages.is_empty() {
            if !DOWNLOAD_CANCELLED.load(Ordering::SeqCst) && page_retries > 10 {
                progress.state = DownloadState::Failed;
                progress.error_message = Some("Failed to retrieve chapter pages".to_string());
                let _ = sink.add(progress.clone());
            }
            continue;
        }

        progress.total_pages = pages.len() as i64;
        progress.state = DownloadState::Downloading;
        let _ = sink.add(progress.clone());

        // Find CDN
        let mut cdn_base = String::new();
        let mut retry_delay = 1;

        loop {
            if DOWNLOAD_CANCELLED.load(Ordering::SeqCst) { break; }
            if !DOWNLOAD_ACTIVE.load(Ordering::SeqCst) {
                progress.state = DownloadState::Paused;
                let _ = sink.add(progress.clone());
                while !DOWNLOAD_ACTIVE.load(Ordering::SeqCst) && !DOWNLOAD_CANCELLED.load(Ordering::SeqCst) {
                    sleep(Duration::from_millis(500)).await;
                }
                progress.state = DownloadState::Downloading;
                let _ = sink.add(progress.clone());
            }

            match find_working_cdn(pages[0].url.clone()).await {
                Ok(cdn) => {
                    cdn_base = cdn;
                    break;
                }
                Err(_e) => {
                    progress.state = DownloadState::WaitingForNetwork;
                    progress.error_message = None;
                    let _ = sink.add(progress.clone());
                    sleep(Duration::from_secs(retry_delay)).await;
                    retry_delay = (retry_delay * 2).min(20);
                }
            }
        }

        if DOWNLOAD_CANCELLED.load(Ordering::SeqCst) { break; }

        progress.state = DownloadState::Downloading;
        progress.error_message = None;

        // Download all pages and write CBZ. Images are fetched through a bounded
        // window so several requests are in flight at once, while pieces are still
        // written to the archive strictly in page order.
        let cbz_tmp = format!("{}.tmp", cbz_path);
        let file = std::fs::File::create(&cbz_tmp).context("Failed to create CBZ file")?;
        let mut zip = zip::ZipWriter::new(file);
        // Page images are already compressed (JPEG/PNG/WEBP); deflating them again
        // burns CPU on the device for zero size gain.
        let options = SimpleFileOptions::default().compression_method(zip::CompressionMethod::Stored);

        let mut downloaded_bytes: i64 = 0;
        let mut all_ok = true;

        // Do not buffer the whole chapter: completed pages are flushed in order,
        // while a bounded window of pages above the write cursor is in flight.
        let mut pending: std::collections::HashMap<usize, Vec<u8>> = std::collections::HashMap::new();
        let mut next_to_write = 0usize;
        let mut next_to_fetch = 0usize;
        let mut attempts: std::collections::HashMap<usize, i64> = std::collections::HashMap::new();
        let mut retry_delay: i64 = 1;

        while next_to_write < pages.len() {
            if DOWNLOAD_CANCELLED.load(Ordering::SeqCst) {
                all_ok = false;
                break;
            }

            while !DOWNLOAD_ACTIVE.load(Ordering::SeqCst) && !DOWNLOAD_CANCELLED.load(Ordering::SeqCst) {
                progress.state = DownloadState::Paused;
                let _ = sink.add(progress.clone());
                sleep(Duration::from_millis(500)).await;
            }
            if DOWNLOAD_CANCELLED.load(Ordering::SeqCst) {
                all_ok = false;
                break;
            }

            // The window may look further ahead than it writes, so at most a few
            // dozen decoded pages are held in memory.
            let mut batch = Vec::with_capacity(window);
            while batch.len() < window && next_to_fetch < pages.len() {
                let idx = next_to_fetch;
                next_to_fetch += 1;
                if !pending.contains_key(&idx) {
                    batch.push(idx);
                }
            }

            if batch.is_empty() {
                // Nothing left to fetch; flush whatever is still waiting in order.
                while let Some(data) = pending.remove(&next_to_write) {
                    write_page(&mut zip, options, &pages[next_to_write].url, next_to_write, &data, &mut downloaded_bytes)?;
                    next_to_write += 1;
                    progress.current_page = next_to_write as i64;
                    progress.bytes_downloaded = downloaded_bytes;
                    progress.state = DownloadState::Downloading;
                    let _ = sink.add(progress.clone());
                }
                continue;
            }

            let mut set = tokio::task::JoinSet::new();
            for idx in batch {
                let url = pages[idx].url.clone();
                let base = cdn_base.clone();
                set.spawn(async move { (idx, fetch_page_bytes(&url, &base).await) });
            }

            let mut failed = Vec::new();
            while let Some(joined) = set.join_next().await {
                match joined {
                    Ok((idx, Some(data))) => {
                        pending.insert(idx, data);
                    }
                    Ok((idx, None)) => failed.push(idx),
                    Err(_) => {
                        all_ok = false;
                    }
                }
            }

            if !all_ok {
                break;
            }

            if !failed.is_empty() {
                let mut exhausted = false;
                for idx in &failed {
                    let count = attempts.entry(*idx).or_insert(0);
                    *count += 1;
                    if *count >= MAX_PAGE_ATTEMPTS {
                        exhausted = true;
                    }
                }
                if exhausted {
                    progress.state = DownloadState::Failed;
                    progress.error_message =
                        Some(format!("Failed to download page {}", failed[0] + 1));
                    let _ = sink.add(progress.clone());
                    all_ok = false;
                    break;
                }

                progress.state = DownloadState::WaitingForNetwork;
                progress.error_message = None;
                let _ = sink.add(progress.clone());

                if let Ok(new_cdn) = find_working_cdn(pages[failed[0]].url.clone()).await {
                    cdn_base = new_cdn;
                }
                sleep(Duration::from_secs(retry_delay as u64)).await;
                retry_delay = (retry_delay * 2).min(20);
                progress.state = DownloadState::Downloading;
                let _ = sink.add(progress.clone());

                // Rewind to the first missing page; already pending ones are skipped.
                next_to_fetch = failed[0];
                continue;
            }

            retry_delay = 1;

            // Flush the contiguous prefix to the archive.
            while let Some(data) = pending.remove(&next_to_write) {
                write_page(&mut zip, options, &pages[next_to_write].url, next_to_write, &data, &mut downloaded_bytes)?;
                next_to_write += 1;
                progress.current_page = next_to_write as i64;
                progress.bytes_downloaded = downloaded_bytes;
                progress.state = DownloadState::Downloading;
                let _ = sink.add(progress.clone());
            }
        }

        zip.finish().context("Failed to finalize CBZ")?;

        if all_ok && !DOWNLOAD_CANCELLED.load(Ordering::SeqCst) {
            // Rename tmp to final
            std::fs::rename(&cbz_tmp, &cbz_path).context("Failed to rename CBZ temp file")?;

            mark_chapter_downloaded(
                manga_id,
                chapter.volume.clone(),
                chapter.number.clone(),
                pages.len() as i64,
                cbz_path.clone(),
            ).await?;

            progress.state = DownloadState::Completed;
            let _ = sink.add(progress.clone());
        } else {
            // Clean up temp file
            let _ = std::fs::remove_file(&cbz_tmp);
        }
    }

    Ok(())
}
