use rusqlite::{Connection, params};

use super::catalog::in_group;
use super::items::canonical;
use super::{ItemId, Kind, Page, Tx};

/// Likes the item's root, reviving a logically deleted like; unliking sets `deleted_at` on
/// every live like of the root's group (likes made before a merge stay on the merged item).
pub fn set(tx: &Tx, item: ItemId, liked: bool) -> rusqlite::Result<()> {
    let root = canonical(&tx.tx, item)?;
    let (now, stamp, device) = (
        tx.now_ms,
        tx.stamp.updated_at,
        tx.stamp.device_id.as_bytes().as_slice(),
    );
    if liked {
        // A live like keeps its date; a revived one is liked now.
        tx.tx.execute(
            "INSERT INTO likes (item_id, liked_at, updated_at, device_id) VALUES (?1, ?2, ?3, ?4)
             ON CONFLICT (item_id) DO UPDATE SET
               liked_at = CASE WHEN deleted_at IS NULL THEN liked_at ELSE excluded.liked_at END,
               deleted_at = NULL, updated_at = excluded.updated_at, device_id = excluded.device_id",
            params![root, now, stamp, device],
        )?;
    } else {
        tx.tx.execute(
            "UPDATE likes SET deleted_at = ?2, updated_at = ?3, device_id = ?4
             WHERE deleted_at IS NULL AND item_id IN (SELECT id FROM items WHERE id = ?1 OR merged_into = ?1)",
            params![root, now, stamp, device],
        )?;
    }
    Ok(())
}

pub fn is_liked(c: &Connection, item: ItemId) -> rusqlite::Result<bool> {
    in_group(c, "likes WHERE deleted_at IS NULL", canonical(c, item)?)
}

/// Distinct roots of `kind`, most recently liked first.
pub fn list(c: &Connection, kind: Kind, page: Page) -> rusqlite::Result<Vec<ItemId>> {
    let mut st = c.prepare(
        "SELECT r.id FROM likes l JOIN items i ON i.id = l.item_id
         JOIN items r ON r.id = COALESCE(i.merged_into, i.id)
         WHERE l.deleted_at IS NULL AND r.kind = ?1 AND r.deleted_at IS NULL
         GROUP BY r.id ORDER BY max(l.liked_at) DESC, r.id DESC LIMIT ?2 OFFSET ?3",
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

    fn page() -> Page {
        Page {
            offset: 0,
            limit: 50,
        }
    }

    #[test]
    fn like_unlike_is_logical_delete() {
        let db = Db::open_in_memory().unwrap();
        let t = db
            .write_blocking(|tx| {
                let t = catalog::upsert_track(tx, "deezer", &track_data("1", None))?;
                set(tx, t, true)?;
                Ok(t)
            })
            .unwrap();
        db.write_blocking(|tx| set(tx, t, false)).unwrap();
        let (rows, deleted, liked, listed) = db
            .read_blocking(|c| {
                let (n, d): (i64, Option<i64>) = c.query_row(
                    "SELECT count(*), max(deleted_at) FROM likes WHERE item_id = ?1",
                    [t],
                    |r| Ok((r.get(0)?, r.get(1)?)),
                )?;
                Ok((n, d, is_liked(c, t)?, list(c, Kind::Track, page())?))
            })
            .unwrap();
        assert_eq!(rows, 1);
        assert!(deleted.is_some_and(|d| d > 0));
        assert!(!liked);
        assert!(listed.is_empty());

        db.write_blocking(|tx| set(tx, t, true)).unwrap();
        let (rows, deleted, liked, listed) = db
            .read_blocking(|c| {
                let (n, d): (i64, Option<i64>) = c.query_row(
                    "SELECT count(*), max(deleted_at) FROM likes WHERE item_id = ?1",
                    [t],
                    |r| Ok((r.get(0)?, r.get(1)?)),
                )?;
                Ok((n, d, is_liked(c, t)?, list(c, Kind::Track, page())?))
            })
            .unwrap();
        assert_eq!((rows, deleted, liked), (1, None, true));
        assert_eq!(listed, vec![t]);
    }

    #[test]
    fn list_is_most_recent_first_and_kind_scoped() {
        let db = Db::open_in_memory().unwrap();
        let (a, b) = db
            .write_blocking(|tx| {
                let a = catalog::upsert_track(tx, "deezer", &track_data("1", None))?;
                let b = catalog::upsert_track(tx, "deezer", &track_data("2", None))?;
                Ok((a, b))
            })
            .unwrap();
        db.write_blocking(|tx| set(tx, a, true)).unwrap();
        // Same wall ms is possible: ties fall back to the newer root id, so like b in a later tx
        // with a forced later liked_at to keep the assertion about recency, not about ids.
        db.write_blocking(|tx| {
            set(tx, b, true)?;
            tx.tx.execute(
                "UPDATE likes SET liked_at = liked_at + 1000 WHERE item_id = ?1",
                [b],
            )?;
            Ok(())
        })
        .unwrap();
        let (tracks, albums, second) = db
            .read_blocking(|c| {
                Ok((
                    list(c, Kind::Track, page())?,
                    list(c, Kind::Album, page())?,
                    list(
                        c,
                        Kind::Track,
                        Page {
                            offset: 1,
                            limit: 1,
                        },
                    )?,
                ))
            })
            .unwrap();
        assert_eq!(tracks, vec![b, a]);
        assert!(albums.is_empty());
        assert_eq!(second, vec![a]);
    }
}
