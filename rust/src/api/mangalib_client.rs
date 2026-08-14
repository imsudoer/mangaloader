use anyhow::{Context, Result};
use once_cell::sync::Lazy;
use reqwest::header::{HeaderMap, HeaderValue};
use reqwest::{Client, ClientBuilder};
use serde_json::Value;
use std::sync::Mutex;
use crate::api::models::{Chapter, ChapterPage, CommentItem, CommentsData, ConstantItem, Genre, HomePageData, MangaConstants, MangaDetails, MangaRelationItem, MangaSearchResult, MangaSimilarItem, Person, Tag};

static COOKIES: Lazy<Mutex<Option<String>>> = Lazy::new(|| Mutex::new(None));
static HTTP_CLIENT: Lazy<Client> = Lazy::new(|| {
    ClientBuilder::new()
        .timeout(std::time::Duration::from_secs(30))
        .build()
        .expect("Failed to build reqwest client")
});

#[flutter_rust_bridge::frb(sync)]
pub fn get_app_architecture() -> String {
    format!("{}-{}", std::env::consts::OS, std::env::consts::ARCH)
}

const HEADERS_API: &[(&str, &str)] = &[
    ("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:154.0) Gecko/20100101 Firefox/154.0"),
    ("Accept", "*/*"),
    ("Accept-Language", "ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7"),
    ("Site-Id", "1"),
    ("Content-Type", "application/json"),
    ("Client-Time-Zone", "Europe/Moscow"),
    ("Origin", "https://mangalib.org"),
    ("Referer", "https://mangalib.org/"),
    ("Sec-Fetch-Dest", "empty"),
    ("Sec-Fetch-Mode", "cors"),
    ("Sec-Fetch-Site", "cross-site"),
];

const HEADERS_IMG: &[(&str, &str)] = &[
    ("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:154.0) Gecko/20100101 Firefox/154.0"),
    ("Accept", "image/avif,image/webp,image/png,image/svg+xml,image/*;q=0.8,*/*;q=0.5"),
    ("Referer", "https://mangalib.org/"),
    ("Sec-Fetch-Dest", "image"),
    ("Sec-Fetch-Mode", "no-cors"),
    ("Sec-Fetch-Site", "cross-site"),
];

const CDN_SERVERS: [&str; 5] = [
    "https://img3.cdnlibs.org",
    "https://img2.cdnlibs.org",
    "https://img4.cdnlibs.org",
    "https://img.cdnlibs.org",
    "https://img1.cdnlibs.org",
];

fn get_api_headers() -> HeaderMap {
    let mut headers = HeaderMap::new();
    for (k, v) in HEADERS_API {
        headers.insert(*k, HeaderValue::from_static(v));
    }
    if let Some(cookie) = COOKIES.lock().unwrap().as_ref() {
        if let Ok(hv) = HeaderValue::from_str(cookie) {
            headers.insert("Cookie", hv);
        }
    }
    headers
}

fn get_img_headers() -> HeaderMap {
    let mut headers = HeaderMap::new();
    for (k, v) in HEADERS_IMG {
        headers.insert(*k, HeaderValue::from_static(v));
    }
    headers
}

#[flutter_rust_bridge::frb(sync)]
pub fn set_cookies(cookies: String) {
    let mut guard = COOKIES.lock().unwrap();
    *guard = Some(cookies);
}

fn parse_manga_item(item: &Value) -> MangaSearchResult {
    let cover_def = item.get("cover").and_then(|c| c.get("default")).and_then(|v| v.as_str()).unwrap_or("");
    let cover_thumb = item.get("cover").and_then(|c| c.get("thumbnail")).and_then(|v| v.as_str()).unwrap_or("");
    
    let cover_url = if cover_def.starts_with('/') {
        format!("https://cover.cdnlibs.org{}", cover_def)
    } else {
        cover_def.to_string()
    };
    let cover_thumb_url = if cover_thumb.starts_with('/') {
        format!("https://cover.cdnlibs.org{}", cover_thumb)
    } else {
        cover_thumb.to_string()
    };

    let id = item.get("id").and_then(|v| v.as_i64()).unwrap_or(0);
    let slug = item.get("slug").and_then(|v| v.as_str()).unwrap_or("");
    let mut slug_url = item.get("slug_url").and_then(|v| v.as_str()).unwrap_or("").to_string();
    if slug_url.is_empty() && id > 0 && !slug.is_empty() {
        slug_url = format!("{}--{}", id, slug);
    } else if slug_url.is_empty() && !slug.is_empty() {
        slug_url = slug.to_string();
    }

    let rating_average = item.get("rating")
        .and_then(|r| r.get("averageFormated").or_else(|| r.get("average")))
        .and_then(|v| {
            if let Some(s) = v.as_str() {
                if s != "0" && !s.is_empty() { Some(s.to_string()) } else { None }
            } else if let Some(n) = v.as_f64() {
                if n > 0.0 { Some(format!("{:.1}", n)) } else { None }
            } else {
                None
            }
        })
        .or_else(|| {
            item.get("rate_avg").and_then(|v| {
                if let Some(s) = v.as_str() {
                    if s != "0" && !s.is_empty() { Some(s.to_string()) } else { None }
                } else if let Some(n) = v.as_f64() {
                    if n > 0.0 { Some(format!("{:.1}", n)) } else { None }
                } else {
                    None
                }
            })
        })
        .unwrap_or_else(|| "0".to_string());

    let rating_votes = item.get("rating")
        .and_then(|r| r.get("votesFormated").or_else(|| r.get("votes")))
        .and_then(|v| {
            if let Some(s) = v.as_str() { Some(s.to_string()) }
            else if let Some(n) = v.as_i64() { Some(n.to_string()) }
            else { None }
        })
        .unwrap_or_else(|| "0".to_string());

    MangaSearchResult {
        id,
        name: item.get("name").and_then(|v| v.as_str()).unwrap_or("").to_string(),
        rus_name: item.get("rus_name").and_then(|v| v.as_str()).unwrap_or("").to_string(),
        eng_name: item.get("eng_name").and_then(|v| v.as_str()).unwrap_or("").to_string(),
        slug: slug.to_string(),
        slug_url,
        cover_url,
        cover_thumb_url,
        manga_type: item.get("type").and_then(|t| t.get("label")).and_then(|v| v.as_str()).unwrap_or("").to_string(),
        type_id: item.get("type").and_then(|t| t.get("id")).and_then(|v| v.as_i64()).unwrap_or(0),
        status: item.get("status").and_then(|s| s.get("label")).and_then(|v| v.as_str()).unwrap_or("").to_string(),
        status_id: item.get("status").and_then(|s| s.get("id")).and_then(|v| v.as_i64()).unwrap_or(0),
        age_restriction: item.get("ageRestriction").and_then(|a| a.get("label")).and_then(|v| v.as_str()).unwrap_or("").to_string(),
        rating_average,
        rating_votes,
        release_date: item.get("releaseDateString").or_else(|| item.get("releaseDate")).and_then(|v| v.as_str()).map(|s| s.to_string()),
    }
}

pub async fn search_manga(query: String) -> Result<Vec<MangaSearchResult>> {
    let url = format!(
        "https://api.cdnlibs.org/api/manga?fields[]=rate_avg&fields[]=rate&fields[]=releaseDate&q={}&site_id[]=1",
        urlencoding::encode(&query)
    );
    let res = HTTP_CLIENT.get(&url).headers(get_api_headers()).send().await?.json::<Value>().await?;
    
    let mut results = Vec::new();
    if let Some(data) = res.get("data").and_then(|d| d.as_array()) {
        for item in data {
            results.push(parse_manga_item(item));
        }
    }
    Ok(results)
}

pub async fn get_homepage() -> Result<HomePageData> {
    let url = "https://api.cdnlibs.org/api/";
    let res = HTTP_CLIENT.get(url).headers(get_api_headers()).send().await?.json::<Value>().await?;
    
    let mut popular = Vec::new();
    let mut newest = Vec::new();
    let mut latest_updates = Vec::new();
    let mut top_views = Vec::new();
    
    if let Some(data) = res.get("data") {
        if let Some(pop_arr) = data.get("popular").and_then(|v| v.as_array()) {
            for item in pop_arr {
                popular.push(parse_manga_item(item));
            }
        }
        if let Some(new_arr) = data.get("newest").and_then(|v| v.as_array()) {
            for item in new_arr {
                newest.push(parse_manga_item(item));
            }
        }
        if let Some(upd_arr) = data.get("latest_updates").and_then(|v| v.as_array()) {
            for item in upd_arr {
                latest_updates.push(parse_manga_item(item));
            }
        }
        if let Some(views_items) = data.get("currently_views").and_then(|v| v.get("items")) {
            if let Some(obj) = views_items.as_object() {
                for (_k, arr) in obj {
                    if let Some(items) = arr.as_array() {
                        for it in items {
                            if let Some(media) = it.get("media") {
                                top_views.push(parse_manga_item(media));
                            }
                        }
                    }
                }
            }
        }
    }
    
    Ok(HomePageData {
        popular,
        newest,
        latest_updates,
        top_views,
    })
}

pub async fn get_top_views(time: String) -> Result<Vec<MangaSearchResult>> {
    let time_val = if time.is_empty() { "day" } else { time.as_str() };
    let url = format!("https://api.cdnlibs.org/api/media/top-views?time={}", time_val);
    let res = HTTP_CLIENT.get(&url).headers(get_api_headers()).send().await?.json::<Value>().await?;

    let mut results = Vec::new();
    if let Some(items) = res.get("data").and_then(|d| d.get("items")).and_then(|i| i.as_object()) {
        for (_k, arr) in items {
            if let Some(list) = arr.as_array() {
                for it in list {
                    if let Some(media) = it.get("media") {
                        results.push(parse_manga_item(media));
                    }
                }
            }
        }
    }
    Ok(results)
}

pub async fn get_latest_updates(page: i64) -> Result<Vec<MangaSearchResult>> {
    let p = if page < 1 { 1 } else { page };
    let url = format!("https://api.cdnlibs.org/api/latest-updates?page={}", p);
    let res = HTTP_CLIENT.get(&url).headers(get_api_headers()).send().await?.json::<Value>().await?;

    let mut results = Vec::new();
    if let Some(data) = res.get("data").and_then(|d| d.as_array()) {
        for item in data {
            results.push(parse_manga_item(item));
        }
    }
    Ok(results)
}

pub async fn get_catalog(
    page: i64,
    sort_by: String,
    type_ids: Vec<i64>,
    status_ids: Vec<i64>,
    genre_ids: Vec<i64>,
    tag_ids: Vec<i64>,
    age_ids: Vec<i64>,
    format_ids: Vec<i64>,
    scanlate_ids: Vec<i64>,
) -> Result<Vec<MangaSearchResult>> {
    let p = if page < 1 { 1 } else { page };
    let normalized_sort = match sort_by.as_str() {
        "popular" | "popularity" | "views" => "views",
        "rate_avg" | "rating" => "rate_avg",
        "created_at" | "newest" | "updates" => "created_at",
        "chap_count" | "chapters" => "chap_count",
        "releaseDate" | "year" => "releaseDate",
        "name" | "alphabet" => "name",
        _ => "views",
    };

    let mut url = format!(
        "https://api.cdnlibs.org/api/manga?fields[]=rate&fields[]=rate_avg&fields[]=userBookmark&site_id[]=1&page={}&sort_by={}",
        p, normalized_sort
    );

    for tid in type_ids {
        url.push_str(&format!("&types[]={}", tid));
    }
    for sid in status_ids {
        url.push_str(&format!("&status[]={}", sid));
    }
    for gid in genre_ids {
        url.push_str(&format!("&genres[]={}", gid));
    }
    for tag_id in tag_ids {
        url.push_str(&format!("&tags[]={}", tag_id));
    }
    for age_id in age_ids {
        url.push_str(&format!("&age_restriction[]={}", age_id));
    }
    for format_id in format_ids {
        url.push_str(&format!("&format[]={}", format_id));
    }
    for scanlate_id in scanlate_ids {
        url.push_str(&format!("&scanlate_status[]={}", scanlate_id));
    }

    let res = HTTP_CLIENT.get(&url).headers(get_api_headers()).send().await?.json::<Value>().await?;

    let mut results = Vec::new();
    if let Some(data) = res.get("data").and_then(|d| d.as_array()) {
        for item in data {
            results.push(parse_manga_item(item));
        }
    }
    Ok(results)
}

pub async fn get_constants() -> Result<MangaConstants> {
    let url = "https://api.cdnlibs.org/api/constants?fields[]=genres&fields[]=tags&fields[]=types&fields[]=scanlateStatus&fields[]=status&fields[]=format&fields[]=ageRestriction";
    let res = HTTP_CLIENT.get(url).headers(get_api_headers()).send().await?.json::<Value>().await?;
    let data = res.get("data").context("Missing data in constants")?;

    let parse_items = |key: &str| -> Vec<ConstantItem> {
        data.get(key).and_then(|v| v.as_array()).map(|arr| {
            arr.iter().filter_map(|i| {
                let id = i.get("id").and_then(|v| v.as_i64())?;
                let name = i.get("name")
                    .or_else(|| i.get("label"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();
                if !name.is_empty() {
                    Some(ConstantItem { id, name })
                } else {
                    None
                }
            }).collect()
        }).unwrap_or_default()
    };

    Ok(MangaConstants {
        types: parse_items("types"),
        statuses: parse_items("status"),
        scanlate_statuses: parse_items("scanlateStatus"),
        age_restrictions: parse_items("ageRestriction"),
        formats: parse_items("format"),
        genres: parse_items("genres"),
        tags: parse_items("tags"),
    })
}

fn extract_text_from_tiptap(content: &Value) -> String {
    let mut result = String::new();
    if let Some(arr) = content.as_array() {
        for node in arr {
            if let Some(node_type) = node.get("type").and_then(|v| v.as_str()) {
                if node_type == "text" {
                    if let Some(text) = node.get("text").and_then(|v| v.as_str()) {
                        result.push_str(text);
                    }
                } else if node_type == "paragraph" {
                    if let Some(inner) = node.get("content") {
                        result.push_str(&extract_text_from_tiptap(inner));
                        result.push('\n');
                    }
                } else if let Some(inner) = node.get("content") {
                    result.push_str(&extract_text_from_tiptap(inner));
                }
            }
        }
    }
    result.trim().to_string()
}

pub async fn get_manga_details(slug_url: String) -> Result<MangaDetails> {
    let url = format!(
        "https://api.cdnlibs.org/api/manga/{}?fields[]=summary&fields[]=genres&fields[]=tags&fields[]=authors&fields[]=artists&fields[]=views&fields[]=releaseDate&fields[]=rate_avg&fields[]=rate&fields[]=chap_count&fields[]=status_id&fields[]=format&fields[]=publisher&fields[]=eng_name&fields[]=otherNames&fields[]=background",
        slug_url
    );
    let res = HTTP_CLIENT.get(&url).headers(get_api_headers()).send().await?.json::<Value>().await?;
    let data = res.get("data").context("Missing data field in API response")?;

    let summary = if let Some(summary_obj) = data.get("summary").and_then(|s| s.get("content")) {
        extract_text_from_tiptap(summary_obj)
    } else {
        String::new()
    };

    let parse_list = |key: &str| -> Vec<Genre> {
        data.get(key).and_then(|v| v.as_array()).map(|arr| {
            arr.iter().map(|i| Genre {
                id: i.get("id").and_then(|v| v.as_i64()).unwrap_or(0),
                name: i.get("name").and_then(|v| v.as_str()).unwrap_or("").to_string(),
            }).collect()
        }).unwrap_or_default()
    };

    let parse_people = |key: &str| -> Vec<Person> {
        data.get(key).and_then(|v| v.as_array()).map(|arr| {
            arr.iter().map(|i| Person {
                id: i.get("id").and_then(|v| v.as_i64()).unwrap_or(0),
                name: i.get("name").and_then(|v| v.as_str()).unwrap_or("").to_string(),
                slug: i.get("slug").and_then(|v| v.as_str()).unwrap_or("").to_string(),
            }).collect()
        }).unwrap_or_default()
    };

    let genres = parse_list("genres");
    let tags = data.get("tags").and_then(|v| v.as_array()).map(|arr| {
        arr.iter().map(|i| Tag {
            id: i.get("id").and_then(|v| v.as_i64()).unwrap_or(0),
            name: i.get("name").and_then(|v| v.as_str()).unwrap_or("").to_string(),
        }).collect()
    }).unwrap_or_default();

    let authors = parse_people("authors");
    let artists = parse_people("artists");

    let format_labels: Vec<String> = data.get("format").and_then(|v| v.as_array()).map(|arr| {
        arr.iter().filter_map(|i| i.get("name").and_then(|v| v.as_str()).map(|s| s.to_string())).collect()
    }).unwrap_or_default();

    let details = MangaDetails {
        id: data.get("id").and_then(|v| v.as_i64()).unwrap_or(0),
        name: data.get("name").and_then(|v| v.as_str()).unwrap_or("").to_string(),
        rus_name: data.get("rus_name").and_then(|v| v.as_str()).unwrap_or("").to_string(),
        eng_name: data.get("eng_name").and_then(|v| v.as_str()).unwrap_or("").to_string(),
        slug: data.get("slug").and_then(|v| v.as_str()).unwrap_or("").to_string(),
        slug_url: data.get("slug_url").and_then(|v| v.as_str()).unwrap_or("").to_string(),
        cover_url: data.get("cover").and_then(|c| c.get("default")).and_then(|v| v.as_str()).unwrap_or("").to_string(),
        cover_thumb_url: data.get("cover").and_then(|c| c.get("thumbnail")).and_then(|v| v.as_str()).unwrap_or("").to_string(),
        manga_type: data.get("type").and_then(|t| t.get("label")).and_then(|v| v.as_str()).unwrap_or("").to_string(),
        type_id: data.get("type").and_then(|t| t.get("id")).and_then(|v| v.as_i64()).unwrap_or(0),
        status: data.get("status").and_then(|s| s.get("label")).and_then(|v| v.as_str()).unwrap_or("").to_string(),
        status_id: data.get("status").and_then(|s| s.get("id")).and_then(|v| v.as_i64()).unwrap_or(0),
        age_restriction: data.get("ageRestriction").and_then(|a| a.get("label")).and_then(|v| v.as_str()).unwrap_or("").to_string(),
        rating_average: data.get("rating").and_then(|r| r.get("average")).and_then(|v| v.as_str()).unwrap_or("0").to_string(),
        rating_votes: data.get("rating").and_then(|r| r.get("votesFormated")).and_then(|v| v.as_str()).unwrap_or("0").to_string(),
        release_date: data.get("releaseDate").and_then(|v| v.as_str()).map(|s| s.to_string()),
        summary,
        genres,
        tags,
        authors,
        artists,
        views_total: data.get("views").and_then(|v| v.get("total")).and_then(|v| v.as_str().map(|s| s.to_string()).or_else(|| v.as_i64().map(|n| n.to_string()))).unwrap_or("0".to_string()),
        views_formatted: data.get("views").and_then(|v| v.get("formated")).and_then(|v| v.as_str()).unwrap_or("0").to_string(),
        chapters_count: data.get("items_count").and_then(|i| i.get("uploaded")).and_then(|v| v.as_i64()).unwrap_or(0),
        format_labels,
        publisher_name: data.get("publisher").and_then(|p| p.get("name")).and_then(|v| v.as_str()).map(|s| s.to_string()),
    };

    let _ = crate::api::storage::save_manga(details.clone()).await;
    Ok(details)
}

pub async fn get_chapters(slug_url: String) -> Result<Vec<Chapter>> {
    let url = format!("https://api.cdnlibs.org/api/manga/{}/chapters", slug_url);
    let res = HTTP_CLIENT.get(&url).headers(get_api_headers()).send().await?.json::<Value>().await?;
    let data_opt = res.get("data").and_then(|v| v.as_array());
    let data = match data_opt {
        Some(d) => d,
        None => return Ok(Vec::new()),
    };

    let mut chapters = Vec::new();
    for c in data {
        let is_paid = c.get("restricted_view")
            .or_else(|| c.get("branches").and_then(|b| b.as_array()).and_then(|arr| arr.first()).and_then(|b| b.get("restricted_view")))
            .map(|rv| {
                rv.get("is_open").and_then(|v| v.as_bool()).unwrap_or(true) == false
            })
            .unwrap_or(false);
        chapters.push(Chapter {
            id: c.get("id").and_then(|v| v.as_i64()).unwrap_or(0),
            volume: c.get("volume").and_then(|v| v.as_str().map(|s| s.to_string()).or_else(|| v.as_i64().map(|n| n.to_string()))).unwrap_or_default(),
            number: c.get("number").and_then(|v| v.as_str().map(|s| s.to_string()).or_else(|| v.as_f64().map(|n| n.to_string()))).unwrap_or_default(),
            name: c.get("name").and_then(|v| v.as_str()).map(|s| s.to_string()),
            branch_id: c.get("branches").and_then(|b| b.as_array()).and_then(|arr| arr.first()).and_then(|b| b.get("branch_id")).and_then(|v| v.as_i64()),
            branches_count: c.get("branches_count").and_then(|v| v.as_i64()).unwrap_or(1),
            is_paid,
        });
    }
    Ok(chapters)
}


pub async fn get_chapter_pages(slug_url: String, volume: String, number: String, branch_id: Option<i64>) -> Result<Vec<ChapterPage>> {
    let mut url = format!("https://api.cdnlibs.org/api/manga/{}/chapter?number={}&volume={}", slug_url, number, volume);
    if let Some(bid) = branch_id {
        url = format!("{}&branch_id={}", url, bid);
    }
    let res = HTTP_CLIENT.get(&url).headers(get_api_headers()).send().await?.json::<Value>().await?;
    
    // Check if the chapter is restricted / paid / early access
    if let Some(rv) = res.get("data").and_then(|d| d.get("restricted_view")) {
        if rv.get("is_open").and_then(|v| v.as_bool()) == Some(false) {
            let exp = rv.get("expired_at").and_then(|v| v.as_str()).unwrap_or("");
            if !exp.is_empty() {
                anyhow::bail!("Глава заблокирована (ранний доступ на MangaLib)");
            } else {
                anyhow::bail!("Глава заблокирована (платный доступ на MangaLib)");
            }
        }
    }
    
    // Try multiple paths to find pages
    let pages_arr = res.get("data")
        .and_then(|d| {
            // Try direct: data.pages
            d.get("pages").and_then(|p| p.as_array())
                // Try: data.chapter.pages
                .or_else(|| d.get("chapter").and_then(|c| c.get("pages")).and_then(|p| p.as_array()))
        })
        .ok_or_else(|| {
            let preview = serde_json::to_string(&res).unwrap_or_default();
            let truncated = if preview.len() > 300 { &preview[..300] } else { &preview };
            anyhow::anyhow!("Страницы главы не найдены в ответе API. {}", truncated)
        })?;

    let mut pages = Vec::new();
    for p in pages_arr {
        let page_url = p.get("url").and_then(|v| v.as_str()).unwrap_or_default().to_string();
        if page_url.is_empty() {
            continue;
        }
        pages.push(ChapterPage {
            url: page_url,
            width: p.get("width").and_then(|v| v.as_i64()),
            height: p.get("height").and_then(|v| v.as_i64()),
        });
    }
    Ok(pages)
}

pub async fn find_working_cdn(test_page_url: String) -> Result<String> {
    let clean_url = if test_page_url.starts_with("//manga") {
        test_page_url.replacen("//manga", "/manga", 1)
    } else if test_page_url.starts_with("//") {
        test_page_url.replacen("//", "/", 1)
    } else if !test_page_url.starts_with('/') {
        format!("/{}", test_page_url)
    } else {
        test_page_url.clone()
    };

    let client = ClientBuilder::new()
        .timeout(std::time::Duration::from_secs(5))
        .build()
        .unwrap_or_else(|_| HTTP_CLIENT.clone());

    for cdn in CDN_SERVERS.iter() {
        let full_url = format!("{}{}", cdn, clean_url);
        if let Ok(res) = client.get(&full_url).headers(get_img_headers()).send().await {
            if res.status().is_success() {
                return Ok(cdn.to_string());
            }
        }
    }
    // Fallback to primary working server
    Ok("https://img3.cdnlibs.org".to_string())
}

pub async fn download_image(url: String) -> Result<Vec<u8>> {
    let mut last_err = anyhow::anyhow!("Failed to download image from {}", url);
    for _ in 0..3 {
        match HTTP_CLIENT.get(&url).headers(get_img_headers()).send().await {
            Ok(res) => {
                if res.status().is_success() {
                    let bytes = res.bytes().await?;
                    if !bytes.is_empty() {
                        return Ok(bytes.to_vec());
                    }
                } else {
                    last_err = anyhow::anyhow!("HTTP status {} for {}", res.status(), url);
                }
            }
            Err(e) => {
                last_err = anyhow::anyhow!("Request error for {}: {}", url, e);
                tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;
            }
        }
    }
    Err(last_err)
}

#[flutter_rust_bridge::frb(sync)]
pub fn parse_manga_url(url: String) -> Option<String> {
    if let Some(idx) = url.find("/ru/manga/") {
        let remainder = &url[idx + "/ru/manga/".len()..];
        return Some(remainder.split('/').next().unwrap_or(remainder).to_string());
    }
    if let Some(idx) = url.find("/ru/") {
        let remainder = &url[idx + "/ru/".len()..];
        let slug = remainder.split('/').next().unwrap_or(remainder);
        if !slug.is_empty() {
            return Some(slug.to_string());
        }
    }
    None
}

pub async fn get_manga_comments(manga_id: i64, page: i64) -> Result<CommentsData> {
    let url = format!(
        "https://api.cdnlibs.org/api/comments?page={}&post_id={}&post_type=manga&sort_by=id&sort_type=desc",
        page, manga_id
    );
    let res = HTTP_CLIENT
        .get(&url)
        .headers(get_api_headers())
        .send()
        .await
        .context("Failed to send request for comments")?;

    if !res.status().is_success() {
        anyhow::bail!("Failed to get comments: HTTP {}", res.status());
    }

    let json: Value = res.json().await.context("Failed to parse comments JSON")?;

    let parse_item = |c: &Value| -> Option<CommentItem> {
        let id = c["id"].as_i64()?;
        let raw_comment = c["comment"].as_str().unwrap_or("");
        let clean_text = raw_comment
            .replace("<p>", "")
            .replace("</p>", "\n")
            .replace("<br>", "\n")
            .replace("<br/>", "\n")
            .replace("&quot;", "\"")
            .replace("&amp;", "&")
            .replace("&lt;", "<")
            .replace("&gt;", ">")
            .trim()
            .to_string();

        let user = &c["user"];
        let username = user["username"].as_str().unwrap_or("Аноним").to_string();
        let user_avatar = user["avatar"]["url"].as_str().unwrap_or("").to_string();

        let votes = &c["votes"];
        let votes_up = votes["up"].as_i64().unwrap_or(0);
        let votes_down = votes["down"].as_i64().unwrap_or(0);

        let created_at = c["created_at"].as_str().unwrap_or("").to_string();
        let root_id = c["root_id"].as_i64();
        let parent_comment = c["parent_comment"].as_i64();
        let comment_level = c["comment_level"].as_i64().unwrap_or(0);

        Some(CommentItem {
            id,
            root_id,
            parent_comment,
            comment_level,
            text: clean_text,
            created_at,
            username,
            user_avatar,
            votes_up,
            votes_down,
        })
    };

    let mut root_comments = Vec::new();
    let mut reply_comments = Vec::new();

    if let Some(root_arr) = json["data"]["root"].as_array() {
        for c in root_arr {
            if let Some(item) = parse_item(c) {
                root_comments.push(item);
            }
        }
    }

    if let Some(reply_arr) = json["data"]["replies"].as_array() {
        for c in reply_arr {
            if let Some(item) = parse_item(c) {
                reply_comments.push(item);
            }
        }
    }

    let has_next_page = json["meta"]["has_next_page"].as_bool().unwrap_or(false);
    let current_page = json["meta"]["page"].as_i64().unwrap_or(page);

    Ok(CommentsData {
        root: root_comments,
        replies: reply_comments,
        has_next_page,
        page: current_page,
    })
}

pub async fn get_manga_relations(slug_url: String) -> Result<Vec<MangaRelationItem>> {
    let url = format!("https://api.cdnlibs.org/api/manga/{}/relations", slug_url);
    let res = HTTP_CLIENT
        .get(&url)
        .headers(get_api_headers())
        .send()
        .await
        .context("Failed to get relations")?;

    if !res.status().is_success() {
        return Ok(Vec::new());
    }

    let json: Value = res.json().await.unwrap_or(Value::Null);
    let mut relations = Vec::new();

    if let Some(arr) = json.get("data").and_then(|d| d.as_array()) {
        for item in arr {
            let rel_title = item.get("related_type")
                .and_then(|rt| rt.get("label"))
                .and_then(|l| l.as_str())
                .unwrap_or("Связанное")
                .to_string();

            if let Some(media) = item.get("media") {
                let manga = parse_manga_item(media);
                relations.push(MangaRelationItem {
                    relation_title: rel_title,
                    manga,
                });
            }
        }
    }

    Ok(relations)
}

pub async fn get_manga_similar(slug_url: String) -> Result<Vec<MangaSimilarItem>> {
    let url = format!("https://api.cdnlibs.org/api/manga/{}/similar", slug_url);
    let res = HTTP_CLIENT
        .get(&url)
        .headers(get_api_headers())
        .send()
        .await
        .context("Failed to get similar manga")?;

    if !res.status().is_success() {
        return Ok(Vec::new());
    }

    let json: Value = res.json().await.unwrap_or(Value::Null);
    let mut similar_items = Vec::new();

    if let Some(arr) = json.get("data").and_then(|d| d.as_array()) {
        for item in arr {
            let reason = item.get("similar")
                .and_then(|s| s.as_str())
                .unwrap_or("Похожее")
                .to_string();

            let votes_up = item.get("votes").and_then(|v| v.get("up")).and_then(|u| u.as_i64()).unwrap_or(0);
            let votes_down = item.get("votes").and_then(|v| v.get("down")).and_then(|d| d.as_i64()).unwrap_or(0);

            if let Some(media) = item.get("media") {
                let manga = parse_manga_item(media);
                similar_items.push(MangaSimilarItem {
                    reason,
                    votes_up,
                    votes_down,
                    manga,
                });
            }
        }
    }

    Ok(similar_items)
}
