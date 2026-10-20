use rusqlite::{Connection, params};

use super::items::{canonical, invalid};
use super::{ItemId, Tx};

/// Stored as lowercase text; the catalogue's `downloaded` flag reads `'done'`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DownloadState {
    Queued,
    Running,
    Done,
    Failed,
}

impl DownloadState {
    pub fn as_str(self) -> &'static str {
        match self {
            DownloadState::Queued => "queued",
            DownloadState::Running => "running",
            DownloadState::Done => "done",
            DownloadState::Failed => "failed",
        }
    }

    pub fn parse(s: &str) -> Option<DownloadState> {
        [Self::Queued, Self::Running, Self::Done, Self::Failed]
            .into_iter()
            .find(|d| d.as_str() == s)
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct DownloadRow {
    pub item: ItemId,
    pub state: DownloadState,
    pub path: Option<String>,
    pub quality: String,
    pub mime: Option<String>,
    pub loudness_db: Option<f32>,
    pub bytes_total: Option<u64>,
    pub bytes_done: u64,
    pub error: Option<String>,
}

/// Queues the item's root; a failed download is queued again, any other is left alone.
pub fn enqueue(tx: &Tx, item: ItemId, quality: &str) -> rusqlite::Result<()> {
    tx.tx.execute(
        "INSERT INTO downloads (item_id, state, quality, created_at) VALUES (?1, 'queued', ?2, ?3)
         ON CONFLICT (item_id) DO UPDATE SET state = 'queued', quality = excluded.quality,
           path = NULL, mime = NULL, loudness_db = NULL, bytes_total = NULL, bytes_done = 0,
           error = NULL, finished_at = NULL
         WHERE state = 'failed'",
        params![canonical(&tx.tx, item)?, quality, tx.now_ms()],
    )?;
    Ok(())
}

/// Writes every field of `row`; `finished_at` is set when it reaches done or failed.
pub fn update(tx: &Tx, row: &DownloadRow) -> rusqlite::Result<()> {
    let n = tx.tx.execute(
        &format!(
            "UPDATE downloads SET state = ?2, path = ?3, quality = ?4, mime = ?5, loudness_db = ?6,
               bytes_total = ?7, bytes_done = ?8, error = ?9,
               finished_at = CASE WHEN ?2 IN ('done', 'failed') THEN COALESCE(finished_at, ?10) END
             WHERE {GROUP}"
        ),
        params![
            canonical(&tx.tx, row.item)?,
            row.state.as_str(),
            row.path,
            row.quality,
            row.mime,
            row.loudness_db,
            row.bytes_total.map(|b| b as i64),
            row.bytes_done as i64,
            row.error,
            tx.now_ms()
        ],
    )?;
    if n == 0 {
        return Err(invalid(format!("downloads: no download for {}", row.item)));
    }
    Ok(())
}

pub fn get(c: &Connection, item: ItemId) -> rusqlite::Result<Option<DownloadRow>> {
    Ok(
        rows(c, &format!("WHERE {GROUP}"), params![canonical(c, item)?])?
            .into_iter()
            .next(),
    )
}

/// Done first, then oldest first.
pub fn list(c: &Connection, state: Option<DownloadState>) -> rusqlite::Result<Vec<DownloadRow>> {
    match state {
        Some(s) => rows(c, "WHERE d.state = ?1", [s.as_str()]),
        None => rows(c, "", []),
    }
}

/// Forgets the download; returns the file to delete.
pub fn remove(tx: &Tx, item: ItemId) -> rusqlite::Result<Option<String>> {
    let found = get(&tx.tx, item)?;
    tx.tx.execute(
        &format!("DELETE FROM downloads WHERE {GROUP}"),
        [canonical(&tx.tx, item)?],
    )?;
    Ok(found.and_then(|r| r.path))
}

/// The downloads of root `?1` and of the items merged into it (merges don't rewrite them).
const GROUP: &str = "item_id IN (SELECT id FROM items WHERE id = ?1 OR merged_into = ?1)";

// ponytail: two downloads of one merged group (both fetched before the merge) collapse to the
// first; the other file is never returned by `remove`. Re-key rows on merge if that matters.
/// One row per root, in `list` order.
fn rows(
    c: &Connection,
    filter: &str,
    p: impl rusqlite::Params,
) -> rusqlite::Result<Vec<DownloadRow>> {
    let mut st = c.prepare(&format!(
        "SELECT COALESCE(i.merged_into, i.id), d.state, d.path, d.quality, d.mime, d.loudness_db,
           d.bytes_total, d.bytes_done, d.error
         FROM downloads d JOIN items i ON i.id = d.item_id {filter}
         ORDER BY d.state = 'done' DESC, d.created_at, d.item_id"
    ))?;
    let all = st.query_map(p, |r| {
        let state: String = r.get(1)?;
        Ok(DownloadRow {
            item: r.get(0)?,
            state: DownloadState::parse(&state).ok_or_else(|| {
                rusqlite::Error::FromSqlConversionFailure(
                    1,
                    rusqlite::types::Type::Text,
                    format!("unknown download state {state:?}").into(),
                )
            })?,
            path: r.get(2)?,
            quality: r.get(3)?,
            mime: r.get(4)?,
            loudness_db: r.get(5)?,
            bytes_total: r.get::<_, Option<i64>>(6)?.map(|b| b as u64),
            bytes_done: r.get::<_, i64>(7)? as u64,
            error: r.get(8)?,
        })
    })?;
    let mut seen = std::collections::HashSet::new();
    let mut out = Vec::new();
    for row in all {
        let row = row?;
        if seen.insert(row.item) {
            out.push(row);
        }
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::library::Db;
    use crate::library::catalog::{self, tests::track_data};

    #[test]
    fn download_remove_returns_path() {
        let db = Db::open_in_memory().unwrap();
        db.write_blocking(|tx| {
            let t = catalog::upsert_track(tx, "deezer", &track_data("1", None))?;
            enqueue(tx, t, "flac")?;
            let mut row = get(&tx.tx, t)?.unwrap();
            assert_eq!(
                (row.state, row.bytes_done, row.path.as_deref()),
                (DownloadState::Queued, 0, None)
            );
            row.state = DownloadState::Done;
            row.path = Some("/music/1.flac".into());
            row.bytes_total = Some(10);
            row.bytes_done = 10;
            row.loudness_db = Some(-7.5);
            update(tx, &row)?;
            assert_eq!(get(&tx.tx, t)?, Some(row.clone()));
            assert!(catalog::track(&tx.tx, t)?.unwrap().downloaded);
            assert_eq!(list(&tx.tx, Some(DownloadState::Done))?, vec![row]);
            assert!(list(&tx.tx, Some(DownloadState::Queued))?.is_empty());
            assert_eq!(remove(tx, t)?.as_deref(), Some("/music/1.flac"));
            assert_eq!(get(&tx.tx, t)?, None);
            assert_eq!(remove(tx, t)?, None);
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn failed_download_is_requeued_and_update_needs_a_row() {
        let db = Db::open_in_memory().unwrap();
        db.write_blocking(|tx| {
            let t = catalog::upsert_track(tx, "deezer", &track_data("1", None))?;
            enqueue(tx, t, "mp3")?;
            let mut row = get(&tx.tx, t)?.unwrap();
            row.state = DownloadState::Failed;
            row.error = Some("timeout".into());
            row.bytes_done = 3;
            update(tx, &row)?;
            enqueue(tx, t, "flac")?;
            let row = get(&tx.tx, t)?.unwrap();
            assert_eq!(
                (
                    row.state,
                    row.quality.as_str(),
                    row.bytes_done,
                    row.error.as_deref()
                ),
                (DownloadState::Queued, "flac", 0, None)
            );
            assert_eq!(list(&tx.tx, None)?.len(), 1);
            remove(tx, t)?;
            assert!(update(tx, &row).is_err());
            Ok(())
        })
        .unwrap();
    }
}
