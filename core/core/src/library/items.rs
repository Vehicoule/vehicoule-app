use rusqlite::{Connection, OptionalExtension, params};

use super::{ItemId, Tx};

/// The root of `id` (itself when unmerged or unknown).
pub fn canonical(c: &Connection, id: ItemId) -> rusqlite::Result<ItemId> {
    Ok(c.query_row(
        "SELECT COALESCE(merged_into, id) FROM items WHERE id = ?1",
        [id],
        |r| r.get(0),
    )
    .optional()?
    .unwrap_or(id))
}

/// The newer (UUIDv7) item points to the older; returns the root. User data (likes,
/// playlist entries, plays, downloads) is not rewritten: reads follow `merged_into`.
/// External refs move to the root; the merged item leaves the search index.
pub fn merge(tx: &Tx, a: ItemId, b: ItemId) -> rusqlite::Result<ItemId> {
    let (a, b) = (canonical(&tx.tx, a)?, canonical(&tx.tx, b)?);
    let (root, gone) = if a <= b { (a, b) } else { (b, a) };
    let (found, kinds): (i64, i64) = tx.tx.query_row(
        "SELECT count(*), count(DISTINCT kind) FROM items WHERE id IN (?1, ?2)",
        [root, gone],
        |r| Ok((r.get(0)?, r.get(1)?)),
    )?;
    if found != if root == gone { 1 } else { 2 } {
        return Err(invalid(format!("merge: unknown item {root} or {gone}")));
    }
    if kinds != 1 {
        return Err(invalid(format!("merge: {root} and {gone} differ in kind")));
    }
    if root == gone {
        return Ok(root);
    }
    let device = tx.stamp.device_id.as_bytes().as_slice();
    // One hop only: the merged item and everything that pointed at it now point at the root.
    tx.tx.execute(
        "UPDATE items SET merged_into = ?1, updated_at = ?3, device_id = ?4
         WHERE id = ?2 OR merged_into = ?2",
        params![root, gone, tx.stamp.updated_at, device],
    )?;
    // `AND true`: an upsert fed by a bare SELECT ... WHERE is ambiguous to SQLite's parser
    // (ON could start a join constraint); the extra term disambiguates it.
    tx.tx.execute(
        "INSERT INTO external_refs (item_id, provider, external_id, pinned)
         SELECT ?1, provider, external_id, pinned FROM external_refs WHERE item_id = ?2 AND true
         ON CONFLICT (item_id, provider, external_id) DO UPDATE SET pinned = max(pinned, excluded.pinned)",
        params![root, gone],
    )?;
    tx.tx
        .execute("DELETE FROM external_refs WHERE item_id = ?1", [gone])?;
    tx.tx.execute(
        "DELETE FROM library_fts WHERE rowid = ?1 AND item_id = ?2",
        params![fts_rowid(gone), gone],
    )?;
    Ok(root)
}

/// `library_fts` rowid of an item: its 62 random/counter low bits, so lookups and deletes
/// hit the rowid instead of scanning the UNINDEXED `item_id` column. Unlike `items.rowid`,
/// it survives VACUUM.
/// Writers delete only `rowid AND item_id`, so a (2^-62) collision makes the insert fail
/// instead of replacing another item's row.
pub(crate) fn fts_rowid(id: ItemId) -> i64 {
    let b = id.0.as_bytes();
    i64::from_be_bytes(b[8..].try_into().unwrap())
}

/// A semantic error (bad argument for the store), as a `rusqlite::Error`.
pub(crate) fn invalid(msg: String) -> rusqlite::Error {
    rusqlite::Error::UserFunctionError(msg.into())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::library::Kind;
    use crate::library::catalog::{self, tests::track_data};
    use crate::library::{Db, refs};
    use rusqlite::params;

    fn merged_into(c: &Connection, id: ItemId) -> Option<ItemId> {
        c.query_row("SELECT merged_into FROM items WHERE id = ?1", [id], |r| {
            r.get(0)
        })
        .unwrap()
    }

    #[test]
    fn merge_keeps_user_data_and_dedupes_likes() {
        let db = Db::open_in_memory().unwrap();
        db.write_blocking(|tx| {
            let c = &tx.tx;
            let a = catalog::upsert_track(tx, "deezer", &track_data("1", None))?;
            let b = catalog::upsert_track(tx, "deezer", &track_data("2", None))?;
            let s = (tx.stamp.updated_at, tx.stamp.device_id.as_bytes().as_slice());
            for id in [a, b] {
                c.execute(
                    "INSERT INTO likes (item_id, liked_at, updated_at, device_id) VALUES (?1, 0, ?2, ?3)",
                    params![id, s.0, s.1],
                )?;
            }
            let pl = ItemId::new();
            c.execute(
                "INSERT INTO items (id, kind, title, updated_at, device_id) VALUES (?1, 'playlist', 'p', ?2, ?3)",
                params![pl, s.0, s.1],
            )?;
            c.execute(
                "INSERT INTO playlist_items (id, playlist_id, item_id, order_key, added_at, updated_at, device_id)
                 VALUES (?1, ?2, ?3, 'V', 0, ?4, ?5)",
                params![ItemId::new(), pl, b, s.0, s.1],
            )?;
            for _ in 0..2 {
                c.execute(
                    "INSERT INTO plays (id, item_id, started_at, source, updated_at, device_id)
                     VALUES (?1, ?2, 0, 'test', ?3, ?4)",
                    params![ItemId::new(), b, s.0, s.1],
                )?;
            }

            assert_eq!(merge(tx, b, a)?, a);

            // Nothing rewritten, nothing lost: every user row still exists.
            let count = |sql: &str| c.query_row(sql, [], |r| r.get::<_, i64>(0));
            assert_eq!(count("SELECT count(*) FROM likes")?, 2);
            // Reads following merged_into see one liked root, the root in the playlist, 2 plays on it.
            let liked_roots = count(
                "SELECT count(DISTINCT COALESCE(i.merged_into, i.id)) FROM likes l
                 JOIN items i ON i.id = l.item_id WHERE l.deleted_at IS NULL AND i.kind = 'track'",
            )?;
            assert_eq!(liked_roots, 1);
            let in_playlist: ItemId = c.query_row(
                "SELECT COALESCE(i.merged_into, i.id) FROM playlist_items p JOIN items i ON i.id = p.item_id",
                [],
                |r| r.get(0),
            )?;
            assert_eq!(in_playlist, a);
            let plays: i64 = c.query_row(
                "SELECT count(*) FROM plays p JOIN items i ON i.id = p.item_id
                 WHERE COALESCE(i.merged_into, i.id) = ?1",
                [a],
                |r| r.get(0),
            )?;
            assert_eq!(plays, 2);
            let row = catalog::track(c, b)?.unwrap();
            assert_eq!(row.id, a);
            assert!(row.liked);
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn merge_never_chains() {
        let db = Db::open_in_memory().unwrap();
        db.write_blocking(|tx| {
            let c = &tx.tx;
            let z = catalog::upsert_track(tx, "deezer", &track_data("z", None))?;
            let a = catalog::upsert_track(tx, "deezer", &track_data("a", None))?;
            let b = catalog::upsert_track(tx, "deezer", &track_data("b", None))?;
            assert_eq!(merge(tx, b, a)?, a);
            assert_eq!(merged_into(c, b), Some(a));
            assert_eq!(merge(tx, a, z)?, z);
            assert_eq!(merged_into(c, b), Some(z));
            assert_eq!(merged_into(c, a), Some(z));
            assert_eq!(merged_into(c, z), None);
            assert_eq!(canonical(c, b)?, z);
            // Refs moved to the root; the merged item's search row is gone.
            assert_eq!(refs::item_for(c, "deezer", Kind::Track, "b")?, Some(z));
            assert_eq!(refs::all(c, z)?.len(), 3);
            let fts: i64 = c.query_row(
                "SELECT count(*) FROM library_fts f JOIN items i ON i.id = f.item_id WHERE i.kind = 'track'",
                [],
                |r| r.get(0),
            )?;
            assert_eq!(fts, 1);
            // Merging an item with itself (or its root) is a no-op.
            assert_eq!(merge(tx, b, z)?, z);
            // Kinds never mix.
            let artist = catalog::track(c, z)?.unwrap().artists[0].0;
            assert!(merge(tx, z, artist).is_err());
            // Unknown ids are refused, even merged with themselves.
            let ghost = ItemId::new();
            assert!(merge(tx, z, ghost).is_err());
            assert!(merge(tx, ghost, ghost).is_err());
            Ok(())
        })
        .unwrap();
    }
}
