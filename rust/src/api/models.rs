use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MangaSearchResult {
    pub id: i64,
    pub name: String,
    pub rus_name: String,
    pub eng_name: String,
    pub slug: String,
    pub slug_url: String,
    pub cover_url: String,
    pub cover_thumb_url: String,
    pub manga_type: String,
    pub type_id: i64,
    pub status: String,
    pub status_id: i64,
    pub age_restriction: String,
    pub rating_average: String,
    pub rating_votes: String,
    pub release_date: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HomePageData {
    pub popular: Vec<MangaSearchResult>,
    pub newest: Vec<MangaSearchResult>,
    pub latest_updates: Vec<MangaSearchResult>,
    pub top_views: Vec<MangaSearchResult>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MangaDetails {
    pub id: i64,
    pub name: String,
    pub rus_name: String,
    pub eng_name: String,
    pub slug: String,
    pub slug_url: String,
    pub cover_url: String,
    pub cover_thumb_url: String,
    pub manga_type: String,
    pub type_id: i64,
    pub status: String,
    pub status_id: i64,
    pub age_restriction: String,
    pub rating_average: String,
    pub rating_votes: String,
    pub release_date: Option<String>,
    pub summary: String,
    pub genres: Vec<Genre>,
    pub tags: Vec<Tag>,
    pub authors: Vec<Person>,
    pub artists: Vec<Person>,
    pub views_total: String,
    pub views_formatted: String,
    pub chapters_count: i64,
    pub format_labels: Vec<String>,
    pub publisher_name: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Genre { pub id: i64, pub name: String }
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Tag { pub id: i64, pub name: String }
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Person { pub id: i64, pub name: String, pub slug: String }

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConstantItem {
    pub id: i64,
    pub name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MangaConstants {
    pub types: Vec<ConstantItem>,
    pub statuses: Vec<ConstantItem>,
    pub scanlate_statuses: Vec<ConstantItem>,
    pub age_restrictions: Vec<ConstantItem>,
    pub formats: Vec<ConstantItem>,
    pub genres: Vec<ConstantItem>,
    pub tags: Vec<ConstantItem>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommentItem {
    pub id: i64,
    pub root_id: Option<i64>,
    pub parent_comment: Option<i64>,
    pub comment_level: i64,
    pub text: String,
    pub created_at: String,
    pub username: String,
    pub user_avatar: String,
    pub votes_up: i64,
    pub votes_down: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommentsData {
    pub root: Vec<CommentItem>,
    pub replies: Vec<CommentItem>,
    pub has_next_page: bool,
    pub page: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MangaRelationItem {
    pub relation_title: String,
    pub manga: MangaSearchResult,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MangaSimilarItem {
    pub reason: String,
    pub votes_up: i64,
    pub votes_down: i64,
    pub manga: MangaSearchResult,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Chapter {
    pub id: i64,
    pub volume: String,
    pub number: String,
    pub name: Option<String>,
    pub branch_id: Option<i64>,
    pub branches_count: i64,
    pub is_paid: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChapterPage {
    pub url: String,
    pub width: Option<i64>,
    pub height: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DownloadProgress {
    pub manga_slug: String,
    pub chapter_number: String,
    pub chapter_volume: String,
    pub current_page: i64,
    pub total_pages: i64,
    pub current_chapter: i64,
    pub total_chapters: i64,
    pub bytes_downloaded: i64,
    pub state: DownloadState,
    pub error_message: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum DownloadState {
    Queued,
    Downloading,
    WaitingForNetwork,
    Paused,
    Completed,
    Failed,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum ListType {
    Reading,
    PlanToRead,
    Completed,
    Dropped,
    Favorites,
    OnHold,
}

impl ListType {
    pub fn as_str(&self) -> &'static str {
        match self {
            ListType::Reading => "reading",
            ListType::PlanToRead => "plan_to_read",
            ListType::Completed => "completed",
            ListType::Dropped => "dropped",
            ListType::Favorites => "favorites",
            ListType::OnHold => "on_hold",
        }
    }
    
    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "reading" => Some(ListType::Reading),
            "plan_to_read" => Some(ListType::PlanToRead),
            "completed" => Some(ListType::Completed),
            "dropped" => Some(ListType::Dropped),
            "favorites" => Some(ListType::Favorites),
            "on_hold" => Some(ListType::OnHold),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LibraryEntry {
    pub manga_id: i64,
    pub slug_url: String,
    pub name: String,
    pub rus_name: String,
    pub cover_url: String,
    pub list_type: ListType,
    pub added_at: String,
    pub last_read_chapter: Option<String>,
    pub last_read_volume: Option<String>,
    pub unread_count: i64,
    pub rating_average: String,
    pub total_chapters: i64,
    pub read_chapters: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReadingPosition {
    pub manga_id: i64,
    pub chapter_volume: String,
    pub chapter_number: String,
    pub page_index: i64,
    pub scroll_position: f64,
    pub last_read_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChapterHistory {
    pub manga_id: i64,
    pub volume: String,
    pub number: String,
    pub page_index: i64,
    pub total_pages: i64,
    pub is_completed: bool,
    pub last_read_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DownloadedChapterInfo {
    pub id: i64,
    pub manga_id: i64,
    pub volume: String,
    pub number: String,
    pub branch_id: Option<i64>,
    pub page_count: i64,
    pub download_path: String,
    pub downloaded_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DownloadedMangaGroup {
    pub manga_id: i64,
    pub slug_url: String,
    pub name: String,
    pub rus_name: String,
    pub cover_url: String,
    pub chapters: Vec<DownloadedChapterInfo>,
    pub total_size_bytes: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChapterDownloadRequest {
    pub volume: String,
    pub number: String,
    pub branch_id: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReadingStreakInfo {
    pub current_streak: i64,
    pub max_streak: i64,
    pub last_read_date: String,
    pub today_chapters_count: i64,
    pub is_active_today: bool,
    pub total_days_read: i64,
    pub total_chapters_read: i64,
    pub history_dates: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContinueReadingItem {
    pub manga_id: i64,
    pub slug_url: String,
    pub name: String,
    pub rus_name: String,
    pub cover_url: String,
    pub last_read_volume: String,
    pub last_read_chapter: String,
    pub last_read_at: String,
    pub total_chapters: i64,
    pub read_chapters: i64,
    pub unread_count: i64,
    pub has_new_chapters: bool,
    pub new_chapters_count: i64,
}
