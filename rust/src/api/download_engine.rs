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

pub async fn start_chapter_download(
    slug_url: String,
    manga_id: i64,
    chapters: Vec<ChapterDownloadRequest>,
    app_dir: String,
    _concurrent_images: i64,
    sink: StreamSink<DownloadProgress>,
) -> Result<()> {
    DOWNLOAD_CANCELLED.store(false, Ordering::SeqCst);
    DOWNLOAD_ACTIVE.store(true, Ordering::SeqCst);

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

        // Get pages
        let pages = match get_chapter_pages(
            slug_url.clone(),
            chapter.volume.clone(),
            chapter.number.clone(),
            chapter.branch_id,
        ).await {
            Ok(p) => p,
            Err(e) => {
                progress.state = DownloadState::Failed;
                progress.error_message = Some(e.to_string());
                let _ = sink.add(progress.clone());
                continue;
            }
        };

        if pages.is_empty() {
            progress.state = DownloadState::Failed;
            progress.error_message = Some("No pages returned by API".to_string());
            let _ = sink.add(progress.clone());
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
                    progress.error_message = Some("Searching CDN...".to_string());
                    let _ = sink.add(progress.clone());
                    sleep(Duration::from_secs(retry_delay)).await;
                    retry_delay = (retry_delay * 2).min(30);
                }
            }
        }

        if DOWNLOAD_CANCELLED.load(Ordering::SeqCst) { break; }

        progress.state = DownloadState::Downloading;
        progress.error_message = None;

        // Download all pages and write CBZ
        let cbz_tmp = format!("{}.tmp", cbz_path);
        let file = std::fs::File::create(&cbz_tmp).context("Failed to create CBZ file")?;
        let mut zip = zip::ZipWriter::new(file);
        let options = SimpleFileOptions::default().compression_method(zip::CompressionMethod::Deflated);

        let mut downloaded_bytes: i64 = 0;
        let mut all_ok = true;

        for (page_idx, page) in pages.iter().enumerate() {
            if DOWNLOAD_CANCELLED.load(Ordering::SeqCst) {
                all_ok = false;
                break;
            }

            while !DOWNLOAD_ACTIVE.load(Ordering::SeqCst) && !DOWNLOAD_CANCELLED.load(Ordering::SeqCst) {
                progress.state = DownloadState::Paused;
                let _ = sink.add(progress.clone());
                sleep(Duration::from_millis(500)).await;
                progress.state = DownloadState::Downloading;
            }
            if DOWNLOAD_CANCELLED.load(Ordering::SeqCst) {
                all_ok = false;
                break;
            }

            let clean_path = if page.url.starts_with("//manga") {
                page.url.replacen("//manga", "/manga", 1)
            } else if page.url.starts_with("//") {
                page.url.replacen("//", "/", 1)
            } else if !page.url.starts_with('/') {
                format!("/{}", page.url)
            } else {
                page.url.clone()
            };
            let full_url = format!("{}{}", cdn_base, clean_path);
            let ext = Path::new(&page.url).extension().and_then(|e| e.to_str()).unwrap_or("jpg");
            let arcname = format!("{:04}.{}", page_idx + 1, ext);

            let mut img_retry_delay = 1;
            loop {
                if DOWNLOAD_CANCELLED.load(Ordering::SeqCst) {
                    all_ok = false;
                    break;
                }
                match download_image(full_url.clone()).await {
                    Ok(bytes) => {
                        zip.start_file(&arcname, options).context("Failed to start file in CBZ")?;
                        zip.write_all(&bytes).context("Failed to write image to CBZ")?;
                        downloaded_bytes += bytes.len() as i64;
                        break;
                    }
                    Err(_e) => {
                        progress.state = DownloadState::WaitingForNetwork;
                        progress.error_message = Some("Retrying download...".to_string());
                        let _ = sink.add(progress.clone());
                        sleep(Duration::from_secs(img_retry_delay)).await;
                        img_retry_delay = (img_retry_delay * 2).min(30);
                        progress.state = DownloadState::Downloading;
                        progress.error_message = None;
                        let _ = sink.add(progress.clone());
                    }
                }
            }

            progress.current_page = (page_idx + 1) as i64;
            progress.bytes_downloaded = downloaded_bytes;
            let _ = sink.add(progress.clone());
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
