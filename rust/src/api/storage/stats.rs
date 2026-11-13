//! Reading progress, history, streaks, recaps and recommendations.

use crate::api::models::{
    ChapterHistory, ContinueReadingItem, Genre, GenreCount, MangaRecapData, ReadingHistoryItem,
    ReadingPosition, ReadingSessionInfo, ReadingStatistics, ReadingStreakInfo, RecapMangaItem,
    RecommendedManga, TimeOfDayDistribution,
};
use crate::api::storage::with_conn;
use anyhow::Result;
use rusqlite::{params, OptionalExtension};

pub(crate) fn save_reading_progress(progress: ReadingPosition) -> Result<()> {
    with_conn(|conn| {
        conn.execute(
            "INSERT OR REPLACE INTO reading_progress (manga_id, chapter_volume, chapter_number, page_index, scroll_position, last_read_at)
             VALUES (?1, ?2, ?3, ?4, ?5, datetime('now', 'localtime'))",
            params![progress.manga_id, progress.chapter_volume, progress.chapter_number, progress.page_index, progress.scroll_position],
        )?;

        // Auto-enroll into user_lists if not already present
        let has_list: bool = conn
            .query_row(
                "SELECT COUNT(1) FROM user_lists WHERE manga_id = ?1",
                params![progress.manga_id],
                |r| r.get::<_, i32>(0),
            )
            .map(|c| c > 0)
            .unwrap_or(false);

        if !has_list {
            let _ = conn.execute(
                "INSERT OR IGNORE INTO user_lists (manga_id, list_type, added_at) VALUES (?1, 'reading', datetime('now'))",
                params![progress.manga_id],
            );
        }

        Ok(())
    })
}

pub(crate) fn get_reading_progress(manga_id: i64) -> Result<Option<ReadingPosition>> {
    with_conn(|conn| {
        let mut stmt = conn.prepare("SELECT * FROM reading_progress WHERE manga_id = ?1")?;
        let row = stmt
            .query_row(params![manga_id], |row| {
                Ok(ReadingPosition {
                    manga_id: row.get("manga_id")?,
                    chapter_volume: row.get("chapter_volume")?,
                    chapter_number: row.get("chapter_number")?,
                    page_index: row.get("page_index")?,
                    scroll_position: row.get("scroll_position")?,
                    last_read_at: row.get("last_read_at")?,
                })
            })
            .optional()?;
        Ok(row)
    })
}

pub(crate) fn mark_chapter_read(
    manga_id: i64,
    volume: String,
    number: String,
    page_index: i64,
    total_pages: i64,
    is_completed: bool,
) -> Result<()> {
    let was_completed = with_conn(|conn| {
        let previous: Option<bool> = conn
            .query_row(
                "SELECT is_completed FROM chapter_history WHERE manga_id = ?1 AND volume = ?2 AND number = ?3",
                params![manga_id, volume, number],
                |row| row.get(0),
            )
            .optional()?;

        conn.execute(
            "INSERT OR REPLACE INTO chapter_history (manga_id, volume, number, page_index, total_pages, is_completed, last_read_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, datetime('now', 'localtime'))",
            params![manga_id, volume, number, page_index, total_pages, is_completed],
        )?;

        Ok(previous.unwrap_or(false))
    })?;

    // Progress is persisted repeatedly while the last page is open; the streak must
    // only advance on the transition to a completed chapter, otherwise the daily
    // counter grows on every save tick.
    if is_completed && !was_completed {
        let _ = record_chapter_read_for_streak();
    }
    Ok(())
}

/// Streaks are a human-facing concept: the day rolls over at local midnight, not at
/// UTC midnight, otherwise a chapter read at 01:00 Moscow time would still count as
/// yesterday and silently break the streak.
fn local_date(days_ago: i64) -> String {
    (chrono::Local::now() - chrono::Duration::days(days_ago))
        .format("%Y-%m-%d")
        .to_string()
}

pub(crate) fn get_reading_streak() -> Result<ReadingStreakInfo> {
    with_conn(|conn| {
        let row = conn
            .query_row(
                "SELECT current_streak, max_streak, last_read_date, today_chapters_count, total_days_read, total_chapters_read, history_json
                 FROM reading_streak WHERE id = 1",
                [],
                |row| {
                    let hist_str: String =
                        row.get("history_json").unwrap_or_else(|_| "[]".to_string());
                    let history_dates: Vec<String> =
                        serde_json::from_str(&hist_str).unwrap_or_default();
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
            )
            .optional()?;

        let today_str = local_date(0);
        let yesterday_str = local_date(1);

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
            None => Ok(ReadingStreakInfo {
                current_streak: 0,
                max_streak: 0,
                last_read_date: String::new(),
                today_chapters_count: 0,
                is_active_today: false,
                total_days_read: 0,
                total_chapters_read: 0,
                history_dates: Vec::new(),
            }),
        }
    })
}

pub(crate) fn record_chapter_read_for_streak() -> Result<ReadingStreakInfo> {
    with_conn(|conn| {
        let today_str = local_date(0);
        let yesterday_str = local_date(1);

        let existing = conn
            .query_row(
                "SELECT current_streak, max_streak, last_read_date, today_chapters_count, total_days_read, total_chapters_read, history_json
                 FROM reading_streak WHERE id = 1",
                [],
                |row| {
                    let hist_str: String =
                        row.get("history_json").unwrap_or_else(|_| "[]".to_string());
                    let history_dates: Vec<String> =
                        serde_json::from_str(&hist_str).unwrap_or_default();
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
            )
            .optional()?;

        let (new_streak, new_max, today_count, total_days, total_chaps, history_dates) =
            match existing {
                Some((curr_streak, max_s, last_date, t_count, tot_days, tot_chaps, mut h_dates)) => {
                    if last_date == today_str {
                        (curr_streak, max_s, t_count + 1, tot_days, tot_chaps + 1, h_dates)
                    } else if last_date == yesterday_str {
                        let s = curr_streak + 1;
                        let m = max_s.max(s);
                        if !h_dates.contains(&today_str) {
                            h_dates.push(today_str.clone());
                            if h_dates.len() > 60 {
                                h_dates.remove(0);
                            }
                        }
                        (s, m, 1, tot_days + 1, tot_chaps + 1, h_dates)
                    } else {
                        let s = 1;
                        let m = max_s.max(1);
                        if !h_dates.contains(&today_str) {
                            h_dates.push(today_str.clone());
                            if h_dates.len() > 60 {
                                h_dates.remove(0);
                            }
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
    })
}

pub(crate) fn sync_reading_streak(days: i64) -> Result<ReadingStreakInfo> {
    with_conn(|conn| {
        let today_str = local_date(0);
        let max_s = days.max(1);
        let mut history_dates = Vec::new();
        let count = 7.min(days);
        for i in (0..count).rev() {
            history_dates.push(local_date(i));
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
    })
}

pub(crate) fn get_chapter_history(manga_id: i64) -> Result<Vec<ChapterHistory>> {
    with_conn(|conn| {
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
    })
}

pub(crate) fn get_reading_statistics() -> Result<ReadingStatistics> {
    with_conn(|conn| {
        // 1. Total chapters read and pages read
        let (total_chaps_read, total_pages_read): (i64, i64) = conn
            .query_row(
                "SELECT COUNT(1), COALESCE(SUM(total_pages), 0) FROM chapter_history WHERE is_completed = 1",
                [],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap_or((0, 0));

        // 2. Library counts
        let completed_count: i64 = conn
            .query_row(
                "SELECT COUNT(1) FROM user_lists WHERE list_type = 'completed'",
                [],
                |row| row.get(0),
            )
            .unwrap_or(0);

        let in_progress_count: i64 = conn
            .query_row(
                "SELECT COUNT(1) FROM user_lists WHERE list_type = 'reading'",
                [],
                |row| row.get(0),
            )
            .unwrap_or(0);

        let total_lib_count: i64 = conn
            .query_row("SELECT COUNT(DISTINCT manga_id) FROM user_lists", [], |row| row.get(0))
            .unwrap_or(0);

        let total_downloads: i64 = conn
            .query_row("SELECT COUNT(1) FROM downloaded_chapters", [], |row| row.get(0))
            .unwrap_or(0);

        // 3. Streak info
        let (cur_streak, max_streak, total_active_days): (i64, i64, i64) = conn
            .query_row(
                "SELECT current_streak, max_streak, total_days_read FROM reading_streak WHERE id = 1",
                [],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .unwrap_or((0, 0, 0));

        // 4. Genre breakdown
        let mut genre_counts: std::collections::HashMap<String, i64> =
            std::collections::HashMap::new();
        let mut stmt = conn.prepare(
            "SELECT genres_json FROM manga WHERE id IN (SELECT DISTINCT manga_id FROM chapter_history)",
        )?;
        let rows = stmt.query_map([], |row| row.get::<_, String>(0))?;
        for json_str in rows.flatten() {
            if let Ok(genres) = serde_json::from_str::<Vec<Genre>>(&json_str) {
                for g in genres {
                    *genre_counts.entry(g.name).or_insert(0) += 1;
                }
            }
        }

        let total_genres_weight: i64 = genre_counts.values().sum();
        let mut top_genres: Vec<GenreCount> = genre_counts
            .into_iter()
            .map(|(name, count)| {
                let pct = if total_genres_weight > 0 {
                    (count as f64 / total_genres_weight as f64) * 100.0
                } else {
                    0.0
                };
                GenreCount { name, count, percentage: (pct * 10.0).round() / 10.0 }
            })
            .collect();
        top_genres.sort_by_key(|a| std::cmp::Reverse(a.count));
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
            total_pages_read,
            completed_manga_count: completed_count,
            in_progress_manga_count: in_progress_count,
            total_library_count: total_lib_count,
            total_downloaded_chapters: total_downloads,
            current_streak_days: cur_streak,
            max_streak_days: max_streak,
            total_active_days,
            top_genres,
            time_of_day: TimeOfDayDistribution {
                night_count: night,
                morning_count: morning,
                afternoon_count: afternoon,
                evening_count: evening,
            },
        })
    })
}

pub(crate) fn get_manga_recap() -> Result<MangaRecapData> {
    with_conn(|conn| {
        // Total chapters & pages read from chapter_history
        let (total_chapters_read, total_pages_read): (i64, i64) = conn
            .query_row(
                "SELECT COUNT(*), COALESCE(SUM(total_pages), 0) FROM chapter_history WHERE is_completed = 1 OR page_index > 0",
                [],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap_or((0, 0));

        // Reading streak stats
        let (current_streak, max_streak, total_days): (i64, i64, i64) = conn
            .query_row(
                "SELECT current_streak, max_streak, total_days_read FROM reading_streak WHERE id = 1",
                [],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .unwrap_or((0, 0, 0));

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
        for item in manga_rows.flatten() {
            top_manga.push(item);
        }

        // Top genres
        let mut stmt_genres = conn.prepare(
            "SELECT m.genres_json FROM chapter_history h
             JOIN manga m ON h.manga_id = m.id
             WHERE m.genres_json IS NOT NULL AND m.genres_json != '[]'",
        )?;

        let mut genre_counts: std::collections::HashMap<String, i64> =
            std::collections::HashMap::new();
        let mut total_genre_hits = 0i64;

        let genre_rows = stmt_genres.query_map([], |row| {
            let json_str: String = row.get(0)?;
            Ok(json_str)
        })?;

        for json_str in genre_rows.flatten() {
            if let Ok(genres) = serde_json::from_str::<Vec<Genre>>(&json_str) {
                for g in genres {
                    *genre_counts.entry(g.name).or_insert(0) += 1;
                    total_genre_hits += 1;
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

        top_genres.sort_by_key(|a| std::cmp::Reverse(a.count));
        top_genres.truncate(5);

        // Time of day distribution from chapter_history
        let mut stmt_time =
            conn.prepare("SELECT strftime('%H', last_read_at) as read_hour FROM chapter_history")?;

        let mut night = 0i64;
        let mut morning = 0i64;
        let mut afternoon = 0i64;
        let mut evening = 0i64;

        let time_rows = stmt_time.query_map([], |row| {
            let hour_str: Option<String> = row.get(0)?;
            Ok(hour_str.and_then(|s| s.parse::<i64>().ok()).unwrap_or(12))
        })?;

        for hour in time_rows.flatten() {
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

        let total_session_seconds: i64 = conn
            .query_row("SELECT COALESCE(SUM(session_seconds), 0) FROM reading_sessions", [], |row| {
                row.get(0)
            })
            .unwrap_or(0);

        let estimated_reading_hours = if total_session_seconds > 0 {
            total_session_seconds as f64 / 3600.0
        } else {
            (total_chapters_read as f64 * 3.5) / 60.0
        };

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
    })
}

pub(crate) fn record_reading_session(manga_id: i64, seconds: i64) -> Result<()> {
    if seconds <= 0 {
        return Ok(());
    }
    with_conn(|conn| {
        conn.execute(
            "INSERT INTO reading_sessions (manga_id, session_seconds, started_at) VALUES (?1, ?2, datetime('now'))",
            params![manga_id, seconds],
        )?;
        Ok(())
    })
}

pub(crate) fn get_reading_session_stats() -> Result<ReadingSessionInfo> {
    with_conn(|conn| {
        let total_seconds: i64 = conn
            .query_row(
                "SELECT COALESCE(SUM(session_seconds), 0) FROM reading_sessions",
                [],
                |row| row.get(0),
            )
            .unwrap_or(0);

        let total_sessions: i64 = conn
            .query_row("SELECT COUNT(1) FROM reading_sessions", [], |row| row.get(0))
            .unwrap_or(0);

        let today_seconds: i64 = conn
            .query_row(
                "SELECT COALESCE(SUM(session_seconds), 0) FROM reading_sessions WHERE date(started_at) = date('now')",
                [],
                |row| row.get(0),
            )
            .unwrap_or(0);

        let week_seconds: i64 = conn
            .query_row(
                "SELECT COALESCE(SUM(session_seconds), 0) FROM reading_sessions WHERE started_at >= datetime('now', '-7 days')",
                [],
                |row| row.get(0),
            )
            .unwrap_or(0);

        let avg = if total_sessions > 0 {
            total_seconds / total_sessions
        } else {
            0
        };

        Ok(ReadingSessionInfo {
            total_reading_seconds: total_seconds,
            total_sessions,
            avg_session_seconds: avg,
            today_reading_seconds: today_seconds,
            week_reading_seconds: week_seconds,
        })
    })
}

pub(crate) fn get_reading_history(limit: i64, offset: i64) -> Result<Vec<ReadingHistoryItem>> {
    with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT ch.manga_id, m.slug_url, m.name, m.rus_name, m.cover_url,
                    ch.volume, ch.number, ch.is_completed, ch.last_read_at,
                    ch.total_pages, ch.page_index
             FROM chapter_history ch
             JOIN manga m ON m.id = ch.manga_id
             ORDER BY ch.last_read_at DESC
             LIMIT ?1 OFFSET ?2"
        )?;

        let iter = stmt.query_map(params![limit, offset], |row| {
            Ok(ReadingHistoryItem {
                manga_id: row.get("manga_id")?,
                slug_url: row.get("slug_url")?,
                name: row.get("name")?,
                rus_name: row.get("rus_name")?,
                cover_url: row.get("cover_url")?,
                volume: row.get("volume")?,
                number: row.get("number")?,
                is_completed: row.get("is_completed")?,
                last_read_at: row.get("last_read_at")?,
                total_pages: row.get("total_pages")?,
                page_index: row.get("page_index")?,
            })
        })?;

        let mut list = Vec::new();
        for i in iter.flatten() {
            list.push(i);
        }
        Ok(list)
    })
}

pub(crate) fn delete_reading_history_item(
    manga_id: i64,
    volume: &str,
    number: &str,
) -> Result<()> {
    with_conn(|conn| {
        conn.execute(
            "DELETE FROM chapter_history WHERE manga_id = ?1 AND volume = ?2 AND number = ?3",
            params![manga_id, volume, number],
        )?;
        Ok(())
    })
}

pub(crate) fn clear_reading_history() -> Result<()> {
    with_conn(|conn| {
        conn.execute("DELETE FROM chapter_history", [])?;
        Ok(())
    })
}

pub(crate) fn get_recommendations(limit: i64) -> Result<Vec<RecommendedManga>> {
    with_conn(|conn| {
        let mut stmt = conn.prepare(
            "SELECT m.genres_json FROM manga m
             JOIN user_lists ul ON ul.manga_id = m.id
             WHERE ul.list_type IN ('reading', 'completed', 'favorites')"
        )?;

        let mut genre_weights: std::collections::HashMap<String, i64> =
            std::collections::HashMap::new();
        let rows = stmt.query_map([], |row| {
            let json_str: String = row.get(0)?;
            Ok(json_str)
        })?;

        for r in rows.flatten() {
            if let Ok(genres) = serde_json::from_str::<Vec<Genre>>(&r) {
                for g in genres {
                    *genre_weights.entry(g.name).or_insert(0) += 1;
                }
            }
        }

        if genre_weights.is_empty() {
            let mut pop_stmt = conn.prepare(
                "SELECT m.id, m.slug_url, m.name, m.rus_name, m.cover_url, m.cover_thumb_url, m.manga_type, m.rating_average
                 FROM manga m
                 ORDER BY CAST(m.rating_votes AS INTEGER) DESC
                 LIMIT ?1"
            )?;
            let pop_rows = pop_stmt.query_map(params![limit], |row| {
                Ok(RecommendedManga {
                    manga_id: row.get("id")?,
                    slug_url: row.get("slug_url")?,
                    name: row.get("name")?,
                    rus_name: row.get("rus_name")?,
                    cover_url: row.get("cover_url")?,
                    cover_thumb_url: row.get("cover_thumb_url")?,
                    manga_type: row.get("manga_type")?,
                    rating_average: row.get("rating_average")?,
                    score: 10.0,
                    reason: "Популярно среди читателей".to_string(),
                })
            })?;
            return Ok(pop_rows.flatten().collect());
        }

        let mut cand_stmt = conn.prepare(
            "SELECT m.id, m.slug_url, m.name, m.rus_name, m.cover_url, m.cover_thumb_url, m.manga_type, m.rating_average, m.genres_json
             FROM manga m
             WHERE m.id NOT IN (
                 SELECT manga_id FROM user_lists WHERE list_type IN ('reading', 'completed', 'dropped')
             )"
        )?;

        let mut scored_list: Vec<RecommendedManga> = Vec::new();
        let cand_rows = cand_stmt.query_map([], |row| {
            let genres_json: String = row.get("genres_json")?;
            let rating_str: String = row.get("rating_average")?;
            let rating: f64 = rating_str.parse().unwrap_or(0.0);
            let id: i64 = row.get("id")?;
            let slug_url: String = row.get("slug_url")?;
            let name: String = row.get("name")?;
            let rus_name: String = row.get("rus_name")?;
            let cover_url: String = row.get("cover_url")?;
            let cover_thumb_url: String = row.get("cover_thumb_url")?;
            let manga_type: String = row.get("manga_type")?;

            Ok((id, slug_url, name, rus_name, cover_url, cover_thumb_url, manga_type, rating_str, rating, genres_json))
        })?;

        for item in cand_rows.flatten() {
            let (id, slug_url, name, rus_name, cover_url, cover_thumb_url, manga_type, rating_str, rating, genres_json) = item;
            let mut score = rating * 0.5;
            let mut top_matching_genre = String::new();
            let mut max_g_weight = 0;

            if let Ok(genres) = serde_json::from_str::<Vec<Genre>>(&genres_json) {
                for g in genres {
                    if let Some(&w) = genre_weights.get(&g.name) {
                        score += (w as f64) * 2.0;
                        if w > max_g_weight {
                            max_g_weight = w;
                            top_matching_genre = g.name;
                        }
                    }
                }
            }

            if score > 0.0 {
                let reason = if !top_matching_genre.is_empty() {
                    format!("Похоже на ваши любимые тайтлы ({})", top_matching_genre)
                } else {
                    "Высокий рейтинг".to_string()
                };

                scored_list.push(RecommendedManga {
                    manga_id: id,
                    slug_url,
                    name,
                    rus_name,
                    cover_url,
                    cover_thumb_url,
                    manga_type,
                    rating_average: rating_str,
                    score,
                    reason,
                });
            }
        }

        scored_list.sort_by(|a, b| b.score.partial_cmp(&a.score).unwrap_or(std::cmp::Ordering::Equal));
        scored_list.truncate(limit as usize);

        Ok(scored_list)
    })
}

pub(crate) fn get_continue_reading_manga() -> Result<Vec<ContinueReadingItem>> {
    with_conn(|conn| {
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
                has_new_chapters: false,
                new_chapters_count: 0,
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
    })
}