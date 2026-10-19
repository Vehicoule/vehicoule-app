use rusqlite::{Connection, OptionalExtension, params};

use super::items::{canonical, merge};
use super::{ItemId, Kind, Tx};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExtRef {
    pub external_id: String,
    pub pinned: bool,
}

/// Root item referenced by `(provider, external_id)`, pinned refs first. Any kind: providers
/// may reuse an id across kinds, so catalogue code uses the kind-scoped `lookup`.
pub fn item_for(
    c: &Connection,
    provider: &str,
    external_id: &str,
) -> rusqlite::Result<Option<ItemId>> {
    lookup(c, provider, external_id, None)
}

pub(crate) fn lookup(
    c: &Connection,
    provider: &str,
    external_id: &str,
    kind: Option<Kind>,
) -> rusqlite::Result<Option<ItemId>> {
    c.query_row(
        "SELECT COALESCE(i.merged_into, i.id) FROM external_refs r JOIN items i ON i.id = r.item_id
         WHERE r.provider = ?1 AND r.external_id = ?2 AND (?3 IS NULL OR i.kind = ?3)
         ORDER BY r.pinned DESC, i.id LIMIT 1",
        params![provider, external_id, kind.map(Kind::as_str)],
        |r| r.get(0),
    )
    .optional()
}

fn ext_ref(r: &rusqlite::Row, at: usize) -> rusqlite::Result<ExtRef> {
    Ok(ExtRef {
        external_id: r.get(at)?,
        pinned: r.get(at + 1)?,
    })
}

/// The item's ref at `provider`, pinned first, then the earliest recorded.
pub fn get(c: &Connection, item: ItemId, provider: &str) -> rusqlite::Result<Option<ExtRef>> {
    c.query_row(
        "SELECT external_id, pinned FROM external_refs WHERE item_id = ?1 AND provider = ?2
         ORDER BY pinned DESC, rowid LIMIT 1",
        params![canonical(c, item)?, provider],
        |r| ext_ref(r, 0),
    )
    .optional()
}

/// `(provider, ref)` pairs, by provider, pinned first.
pub fn all(c: &Connection, item: ItemId) -> rusqlite::Result<Vec<(String, ExtRef)>> {
    let mut st = c.prepare(
        "SELECT provider, external_id, pinned FROM external_refs WHERE item_id = ?1
         ORDER BY provider, pinned DESC, rowid",
    )?;
    st.query_map([canonical(c, item)?], |r| Ok((r.get(0)?, ext_ref(r, 1)?)))?
        .collect()
}

/// Unpinned ref; ignored when `(item, provider)` already has a pinned one.
pub fn record(tx: &Tx, item: ItemId, provider: &str, external_id: &str) -> rusqlite::Result<()> {
    tx.tx.execute(
        "INSERT OR IGNORE INTO external_refs (item_id, provider, external_id)
         SELECT ?1, ?2, ?3 WHERE NOT EXISTS
           (SELECT 1 FROM external_refs WHERE item_id = ?1 AND provider = ?2 AND pinned = 1)",
        params![canonical(&tx.tx, item)?, provider, external_id],
    )?;
    Ok(())
}

/// Pins `external_id` as the item's only ref at `provider`. An item of the same kind already
/// pinned to it is the same item: both merge. Unpinned matches of it on other items of that
/// kind are dropped. Returns the root.
pub fn pin(tx: &Tx, item: ItemId, provider: &str, external_id: &str) -> rusqlite::Result<ItemId> {
    let c = &tx.tx;
    let mut root = canonical(c, item)?;
    let kind: String = c.query_row("SELECT kind FROM items WHERE id = ?1", [root], |r| r.get(0))?;
    // Refs live on roots (merge moves them), so `item_id` is already a root.
    while let Some(other) = c
        .query_row(
            "SELECT r.item_id FROM external_refs r JOIN items i ON i.id = r.item_id
             WHERE r.provider = ?1 AND r.external_id = ?2 AND r.pinned = 1 AND i.kind = ?3
               AND r.item_id != ?4 LIMIT 1",
            params![provider, external_id, kind, root],
            |r| r.get(0),
        )
        .optional()?
    {
        root = merge(tx, root, other)?;
    }
    c.execute(
        "DELETE FROM external_refs WHERE provider = ?2 AND
           ((item_id = ?1 AND external_id != ?3)
            OR (item_id != ?1 AND external_id = ?3 AND item_id IN (SELECT id FROM items WHERE kind = ?4)))",
        params![root, provider, external_id, kind],
    )?;
    c.execute(
        "INSERT INTO external_refs (item_id, provider, external_id, pinned) VALUES (?1, ?2, ?3, 1)
         ON CONFLICT (item_id, provider, external_id) DO UPDATE SET pinned = 1",
        params![root, provider, external_id],
    )?;
    Ok(root)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::library::Db;
    use crate::library::catalog::{self, tests::track_data};
    use crate::library::items::canonical;

    fn ext(id: &str, pinned: bool) -> ExtRef {
        ExtRef {
            external_id: id.into(),
            pinned,
        }
    }

    #[test]
    fn pinned_ref_wins_and_survives_auto_match() {
        let db = Db::open_in_memory().unwrap();
        db.write_blocking(|tx| {
            let c = &tx.tx;
            let t = catalog::upsert_track(tx, "deezer", &track_data("1", None))?;
            record(tx, t, "ytmusic", "a")?;
            assert_eq!(get(c, t, "ytmusic")?, Some(ext("a", false)));
            assert_eq!(pin(tx, t, "ytmusic", "b")?, t);
            record(tx, t, "ytmusic", "c")?;
            assert_eq!(get(c, t, "ytmusic")?, Some(ext("b", true)));
            assert_eq!(item_for(c, "ytmusic", "a")?, None);
            assert_eq!(item_for(c, "ytmusic", "c")?, None);
            assert_eq!(item_for(c, "ytmusic", "b")?, Some(t));
            let mut refs = all(c, t)?;
            refs.sort_by(|x, y| x.0.cmp(&y.0));
            assert_eq!(
                refs,
                vec![
                    ("deezer".into(), ext("1", false)),
                    ("ytmusic".into(), ext("b", true))
                ]
            );
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn pin_revealing_duplicate_merges() {
        let db = Db::open_in_memory().unwrap();
        db.write_blocking(|tx| {
            let c = &tx.tx;
            let a = catalog::upsert_track(tx, "deezer", &track_data("1", None))?;
            let b = catalog::upsert_track(tx, "deezer", &track_data("2", None))?;
            assert!(a < b);
            assert_eq!(pin(tx, b, "ytmusic", "x")?, b);
            assert_eq!(pin(tx, a, "ytmusic", "x")?, a);
            assert_eq!(canonical(c, b)?, a);
            assert_eq!(get(c, a, "ytmusic")?, Some(ext("x", true)));
            assert_eq!(item_for(c, "ytmusic", "x")?, Some(a));
            // The newer item's refs moved to the root.
            assert_eq!(item_for(c, "deezer", "2")?, Some(a));
            assert_eq!(
                catalog::upsert_track(tx, "deezer", &track_data("2", None))?,
                a
            );
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn pin_does_not_merge_across_kinds() {
        let db = Db::open_in_memory().unwrap();
        db.write_blocking(|tx| {
            let t = catalog::upsert_track(tx, "deezer", &track_data("1", None))?;
            let album = catalog::upsert_album(
                tx,
                "deezer",
                &catalog::AlbumData {
                    ext_id: "1".into(),
                    title: "Album".into(),
                    artists: vec![],
                    year: None,
                    track_count: None,
                    artwork: vec![],
                },
            )?;
            assert_ne!(album, t);
            pin(tx, t, "ytmusic", "x")?;
            assert_eq!(pin(tx, album, "ytmusic", "x")?, album);
            assert_eq!(canonical(&tx.tx, t)?, t);
            Ok(())
        })
        .unwrap();
    }
}
