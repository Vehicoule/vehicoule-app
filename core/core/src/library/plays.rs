use rusqlite::{Connection, params};

use super::items::canonical;
use super::{ItemId, Kind, Page, Tx};

/// Records a play of the item's root starting now; returns the play id.
pub fn start(tx: &Tx, item: ItemId, source: &str) -> rusqlite::Result<uuid::Uuid> {
    let id = uuid::Uuid::now_v7();
    tx.tx.execute(
        "INSERT INTO plays (id, item_id, started_at, source, updated_at, device_id)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        params![
            id.as_bytes().as_slice(),
            canonical(&tx.tx, item)?,
            tx.now_ms(),
            source,
            tx.stamp.updated_at,
            tx.stamp.device_id.as_bytes().as_slice()
        ],
    )?;
    Ok(id)
}

/// Raises `listened_ms`; a smaller value (late or out-of-order report) is ignored.
pub fn set_listened(tx: &Tx, play: uuid::Uuid, listened_ms: u64) -> rusqlite::Result<()> {
    tx.tx.execute(
        "UPDATE plays SET listened_ms = ?2, updated_at = ?3, device_id = ?4
         WHERE id = ?1 AND listened_ms < ?2",
        params![
            play.as_bytes().as_slice(),
            listened_ms.min(i64::MAX as u64) as i64,
            tx.stamp.updated_at,
            tx.stamp.device_id.as_bytes().as_slice()
        ],
    )?;
    Ok(())
}

/// Distinct roots of `kind`, by latest play first.
pub fn recent_items(c: &Connection, kind: Kind, page: Page) -> rusqlite::Result<Vec<ItemId>> {
    // Same-ms plays: the later UUIDv7 id wins.
    let mut st = c.prepare(
        "SELECT r.id FROM plays p JOIN items i ON i.id = p.item_id
         JOIN items r ON r.id = COALESCE(i.merged_into, i.id)
         WHERE p.deleted_at IS NULL AND r.kind = ?1 AND r.deleted_at IS NULL
         GROUP BY r.id ORDER BY max(p.started_at) DESC, max(p.id) DESC LIMIT ?2 OFFSET ?3",
    )?;
    st.query_map(params![kind.as_str(), page.limit, page.offset], |r| {
        r.get(0)
    })?
    .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::library::Db;
    use crate::library::catalog::{self, tests::track_data};

    #[test]
    fn recent_items_are_distinct() {
        let db = Db::open_in_memory().unwrap();
        let (a, b) = db
            .write_blocking(|tx| {
                let a = catalog::upsert_track(tx, "deezer", &track_data("1", None))?;
                let b = catalog::upsert_track(tx, "deezer", &track_data("2", None))?;
                Ok((a, b))
            })
            .unwrap();
        for t in [a, b, a] {
            db.write_blocking(move |tx| start(tx, t, "test")).unwrap();
        }
        let (tracks, albums) = db
            .read_blocking(|c| {
                let p = || Page {
                    offset: 0,
                    limit: 10,
                };
                Ok((
                    recent_items(c, Kind::Track, p())?,
                    recent_items(c, Kind::Album, p())?,
                ))
            })
            .unwrap();
        assert_eq!(tracks, vec![a, b]);
        assert!(albums.is_empty());
    }

    #[test]
    fn listened_only_grows_and_start_stores_source() {
        let db = Db::open_in_memory().unwrap();
        let play = db
            .write_blocking(|tx| {
                let t = catalog::upsert_track(tx, "deezer", &track_data("1", None))?;
                start(tx, t, "album")
            })
            .unwrap();
        db.write_blocking(move |tx| set_listened(tx, play, 30_000))
            .unwrap();
        db.write_blocking(move |tx| set_listened(tx, play, 10_000))
            .unwrap();
        let (ms, source, started): (i64, String, i64) = db
            .read_blocking(move |c| {
                c.query_row(
                    "SELECT listened_ms, source, started_at FROM plays WHERE id = ?1",
                    [play.as_bytes().as_slice()],
                    |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
                )
            })
            .unwrap();
        assert_eq!((ms, source.as_str()), (30_000, "album"));
        assert!(
            started > 1_600_000_000_000,
            "started_at is wall ms: {started}"
        );
    }
}
