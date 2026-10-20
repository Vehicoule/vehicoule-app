use rusqlite::{Connection, OptionalExtension, params};

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

/// Queues the item's root. No-op while the merge group has a queued, running or done row; a
/// group whose rows all failed has the picked one queued again.
pub fn enqueue(tx: &Tx, item: ItemId, quality: &str) -> rusqlite::Result<()> {
    let root = canonical(&tx.tx, item)?;
    match pick(&tx.tx, root)? {
        Some((_, state)) if state != DownloadState::Failed => {}
        Some((row, _)) => {
            tx.tx.execute(
                "UPDATE downloads SET state = 'queued', quality = ?2, path = NULL, mime = NULL,
                   loudness_db = NULL, bytes_total = NULL, bytes_done = 0, error = NULL,
                   finished_at = NULL
                 WHERE item_id = ?1",
                params![row, quality],
            )?;
        }
        None => {
            tx.tx.execute(
                "INSERT INTO downloads (item_id, state, quality, created_at)
                 VALUES (?1, 'queued', ?2, ?3)",
                params![root, quality, tx.now_ms],
            )?;
        }
    }
    Ok(())
}

/// Writes every field of `row` to the physical row `get` returns for `row.item`;
/// `finished_at` is set when it reaches done or failed.
pub fn update(tx: &Tx, row: &DownloadRow) -> rusqlite::Result<()> {
    let Some((physical, _)) = pick(&tx.tx, canonical(&tx.tx, row.item)?)? else {
        return Err(invalid(format!("downloads: no download for {}", row.item)));
    };
    tx.tx.execute(
        "UPDATE downloads SET state = ?2, path = ?3, quality = ?4, mime = ?5, loudness_db = ?6,
           bytes_total = ?7, bytes_done = ?8, error = ?9,
           finished_at = CASE WHEN ?2 IN ('done', 'failed') THEN COALESCE(finished_at, ?10) END
         WHERE item_id = ?1",
        params![
            physical,
            row.state.as_str(),
            row.path,
            row.quality,
            row.mime,
            row.loudness_db,
            row.bytes_total.map(|b| b as i64),
            row.bytes_done as i64,
            row.error,
            tx.now_ms
        ],
    )?;
    Ok(())
}

/// The root's download: its merge group's best row (see `pick`), `item` set to the root.
pub fn get(c: &Connection, item: ItemId) -> rusqlite::Result<Option<DownloadRow>> {
    let Some((physical, _)) = pick(c, canonical(c, item)?)? else {
        return Ok(None);
    };
    Ok(rows(c, "WHERE d.item_id = ?1", [physical])?
        .into_iter()
        .next())
}

/// One row per root, ranked like `get`: done first, then in progress, then failed; oldest
/// first within each.
pub fn list(c: &Connection, state: Option<DownloadState>) -> rusqlite::Result<Vec<DownloadRow>> {
    match state {
        Some(s) => rows(c, "WHERE d.state = ?1", [s.as_str()]),
        None => rows(c, "", []),
    }
}

/// Forgets the row `get` returns and hands back its file to delete. Merges don't rewrite
/// downloads, so a group can hold several rows: the next one surfaces for a later `remove`.
pub fn remove(tx: &Tx, item: ItemId) -> rusqlite::Result<Option<String>> {
    let c = &tx.tx;
    let Some((physical, _)) = pick(c, canonical(c, item)?)? else {
        return Ok(None);
    };
    let path = c.query_row(
        "SELECT path FROM downloads WHERE item_id = ?1",
        [physical],
        |r| r.get(0),
    )?;
    c.execute("DELETE FROM downloads WHERE item_id = ?1", [physical])?;
    Ok(path)
}

const RANK: &str =
    "CASE d.state WHEN 'done' THEN 0 WHEN 'failed' THEN 2 ELSE 1 END, d.created_at, d.item_id";

/// The physical row (`item_id`, state) that stands for `root`: best of its merge group.
fn pick(c: &Connection, root: ItemId) -> rusqlite::Result<Option<(ItemId, DownloadState)>> {
    c.query_row(
        &format!(
            "SELECT d.item_id, d.state FROM downloads d
             WHERE d.item_id IN (SELECT id FROM items WHERE id = ?1 OR merged_into = ?1)
             ORDER BY {RANK} LIMIT 1"
        ),
        [root],
        |r| Ok((r.get(0)?, state(r, 1)?)),
    )
    .optional()
}

fn state(r: &rusqlite::Row, at: usize) -> rusqlite::Result<DownloadState> {
    let s: String = r.get(at)?;
    DownloadState::parse(&s).ok_or_else(|| {
        rusqlite::Error::FromSqlConversionFailure(
            at,
            rusqlite::types::Type::Text,
            format!("unknown download state {s:?}").into(),
        )
    })
}

/// First row per root, in `RANK` order.
fn rows(
    c: &Connection,
    filter: &str,
    p: impl rusqlite::Params,
) -> rusqlite::Result<Vec<DownloadRow>> {
    let mut st = c.prepare(&format!(
        "SELECT COALESCE(i.merged_into, i.id), d.state, d.path, d.quality, d.mime, d.loudness_db,
           d.bytes_total, d.bytes_done, d.error
         FROM downloads d JOIN items i ON i.id = d.item_id {filter} ORDER BY {RANK}"
    ))?;
    let all = st.query_map(p, |r| {
        Ok(DownloadRow {
            item: r.get(0)?,
            state: state(r, 1)?,
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

    fn raw(c: &Connection, item: ItemId) -> Option<(String, Option<String>)> {
        c.query_row(
            "SELECT state, path FROM downloads WHERE item_id = ?1",
            [item],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .ok()
    }

    fn finish(tx: &Tx, item: ItemId, path: &str) -> rusqlite::Result<()> {
        enqueue(tx, item, "flac")?;
        let mut row = get(&tx.tx, item)?.unwrap();
        row.state = DownloadState::Done;
        row.path = Some(path.into());
        update(tx, &row)
    }

    #[test]
    fn merged_group_downloads_are_handled_row_by_row() {
        let db = Db::open_in_memory().unwrap();
        db.write_blocking(|tx| {
            let c = &tx.tx;
            let a = catalog::upsert_track(tx, "deezer", &track_data("1", None))?;
            let b = catalog::upsert_track(tx, "deezer", &track_data("2", None))?;
            finish(tx, a, "/a.flac")?;
            finish(tx, b, "/b.flac")?;
            assert_eq!(crate::library::items::merge(tx, b, a)?, a);

            // One row per root in reads; update touches only the row get picked.
            assert_eq!(list(c, None)?.len(), 1);
            let mut row = get(c, a)?.unwrap();
            assert_eq!(row.item, a);
            let picked = row.path.clone().unwrap();
            let other = if picked == "/a.flac" {
                (b, "/b.flac")
            } else {
                (a, "/a.flac")
            };
            row.bytes_done = 42;
            update(tx, &row)?;
            assert_eq!(raw(c, other.0), Some(("done".into(), Some(other.1.into()))));
            // A done row in the group: enqueue does nothing.
            enqueue(tx, a, "mp3")?;
            enqueue(tx, b, "mp3")?;
            let n: i64 = c.query_row("SELECT count(*) FROM downloads", [], |r| r.get(0))?;
            assert_eq!(n, 2);
            // Each remove hands back one file; the other row resurfaces for the next one.
            let mut paths = vec![remove(tx, a)?.unwrap(), remove(tx, b)?.unwrap()];
            paths.sort();
            assert_eq!(paths, vec!["/a.flac", "/b.flac"]);
            assert_eq!(remove(tx, a)?, None);

            // Root without a row, merged item done: enqueue on the root adds nothing.
            let x = catalog::upsert_track(tx, "deezer", &track_data("3", None))?;
            let y = catalog::upsert_track(tx, "deezer", &track_data("4", None))?;
            finish(tx, y, "/y.flac")?;
            assert_eq!(crate::library::items::merge(tx, y, x)?, x);
            enqueue(tx, x, "mp3")?;
            assert_eq!(raw(c, x), None);
            assert_eq!(get(c, x)?.unwrap().path.as_deref(), Some("/y.flac"));
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
