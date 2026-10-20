//! Lyrics cache, one row per item; reads and writes go to the item's root.

use rusqlite::{Connection, OptionalExtension, params};

use super::items::{canonical, invalid};
use super::{ItemId, Tx};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LyricsRow {
    pub provider: String,
    pub plain: Option<String>,
    /// `(ms, line)`, stored as JSON `[[ms,"line"],…]`; empty = no synced lyrics (NULL).
    pub synced: Vec<(u32, String)>,
}

/// The root's lyrics, else the newest of its merged items'.
pub fn get(c: &Connection, item: ItemId) -> rusqlite::Result<Option<LyricsRow>> {
    let root = canonical(c, item)?;
    let row = c
        .query_row(
            "SELECT provider, plain, synced FROM lyrics
             WHERE item_id IN (SELECT id FROM items WHERE id = ?1 OR merged_into = ?1)
             ORDER BY item_id = ?1 DESC, fetched_at DESC LIMIT 1",
            [root],
            |r| Ok((r.get(0)?, r.get(1)?, r.get::<_, Option<String>>(2)?)),
        )
        .optional()?;
    row.map(|(provider, plain, synced)| {
        let synced = match synced {
            Some(s) => {
                serde_json::from_str(&s).map_err(|e| invalid(format!("lyrics.synced: {e}")))?
            }
            None => Vec::new(),
        };
        Ok(LyricsRow {
            provider,
            plain,
            synced,
        })
    })
    .transpose()
}

/// Stored on the item's root, `fetched_at` = now.
pub fn put(tx: &Tx, item: ItemId, row: &LyricsRow) -> rusqlite::Result<()> {
    let root = canonical(&tx.tx, item)?;
    let synced = if row.synced.is_empty() {
        None
    } else {
        Some(
            serde_json::to_string(&row.synced)
                .map_err(|e| invalid(format!("lyrics.synced: {e}")))?,
        )
    };
    tx.tx.execute(
        "INSERT INTO lyrics (item_id, provider, plain, synced, fetched_at) VALUES (?1, ?2, ?3, ?4, ?5)
         ON CONFLICT (item_id) DO UPDATE SET provider = excluded.provider, plain = excluded.plain,
           synced = excluded.synced, fetched_at = excluded.fetched_at",
        params![root, row.provider, row.plain, synced, tx.now_ms],
    )?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::library::catalog::{self, tests::track_data};
    use crate::library::{Db, items};

    #[test]
    fn lyrics_roundtrip_keeps_synced_lines() {
        let db = Db::open_in_memory().unwrap();
        let row = LyricsRow {
            provider: "lrclib".into(),
            plain: Some("un\n\"deux\"".into()),
            synced: vec![(0, "un".into()), (1500, "\"deux\" é, [x]".into())],
        };
        let r2 = row.clone();
        let (a, b) = db
            .write_blocking(move |tx| {
                let a = catalog::upsert_track(tx, "deezer", &track_data("1", None))?;
                let b = catalog::upsert_track(tx, "deezer", &track_data("2", None))?;
                put(tx, b, &r2)?;
                Ok((a, b))
            })
            .unwrap();
        let (got, none) = db.read_blocking(|c| Ok((get(c, b)?, get(c, a)?))).unwrap();
        assert_eq!(got.as_ref(), Some(&row));
        assert_eq!(none, None);

        // After a merge the lyrics are found from either item.
        db.write_blocking(move |tx| items::merge(tx, a, b)).unwrap();
        let (from_a, from_b) = db
            .read_blocking(move |c| Ok((get(c, a)?, get(c, b)?)))
            .unwrap();
        assert_eq!(from_a.as_ref(), Some(&row));
        assert_eq!(from_b, Some(row));
    }
}
