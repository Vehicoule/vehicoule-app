//! User playlists. Entries are ordered by `(order_key, id)`; keys are fractional (`order`).
//!
//! Errors vs no-ops: `rename`, `add` and `move_entry` need a live playlist / entry and fail
//! on unknown or deleted ids (the caller acts on something it believes exists). `delete` and
//! `remove_entry` are idempotent: removing what is already gone (double tap, or a delete that
//! synced first) succeeds silently.

use rusqlite::types::{FromSql, FromSqlResult, ToSql, ToSqlOutput, ValueRef};
use rusqlite::{Connection, OptionalExtension, params};

use super::catalog::index;
use super::items::{canonical, fts_rowid, invalid};
use super::{CollectionSort, ItemId, Kind, Page, Tx, collection_order, is_valid_key, key_between};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct EntryId(pub uuid::Uuid);

impl ToSql for EntryId {
    fn to_sql(&self) -> rusqlite::Result<ToSqlOutput<'_>> {
        Ok(ToSqlOutput::Borrowed(ValueRef::Blob(self.0.as_bytes())))
    }
}

impl FromSql for EntryId {
    fn column_result(value: ValueRef<'_>) -> FromSqlResult<Self> {
        ItemId::column_result(value).map(|i| EntryId(i.0))
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Place {
    End,
    Start,
    After(EntryId),
}

/// A `playlist` item plus its `playlists` row, indexed for search.
pub fn create(tx: &Tx, title: &str, description: Option<&str>) -> rusqlite::Result<ItemId> {
    let id = ItemId::new();
    let (stamp, device) = (
        tx.stamp.updated_at,
        tx.stamp.device_id.as_bytes().as_slice(),
    );
    tx.tx.execute(
        "INSERT INTO items (id, kind, title, updated_at, device_id) VALUES (?1, ?2, ?3, ?4, ?5)",
        params![id, Kind::Playlist.as_str(), title, stamp, device],
    )?;
    tx.tx.execute(
        "INSERT INTO playlists (item_id, description, created_at, updated_at, device_id)
         VALUES (?1, ?2, ?3, ?4, ?5)",
        params![id, description, tx.now_ms, stamp, device],
    )?;
    index(tx, id)?;
    Ok(id)
}

pub fn rename(tx: &Tx, playlist: ItemId, title: &str) -> rusqlite::Result<()> {
    live(&tx.tx, playlist)?;
    tx.tx.execute(
        "UPDATE items SET title = ?2, updated_at = ?3, device_id = ?4 WHERE id = ?1",
        params![
            playlist,
            title,
            tx.stamp.updated_at,
            tx.stamp.device_id.as_bytes().as_slice()
        ],
    )?;
    index(tx, playlist)
}

/// Logical: the playlist and its entries disappear from every read and from search.
pub fn delete(tx: &Tx, playlist: ItemId) -> rusqlite::Result<()> {
    let p = params![
        playlist,
        tx.now_ms,
        tx.stamp.updated_at,
        tx.stamp.device_id.as_bytes().as_slice()
    ];
    let set = "SET deleted_at = ?2, updated_at = ?3, device_id = ?4";
    let n = tx.tx.execute(
        &format!("UPDATE playlists {set} WHERE item_id = ?1 AND deleted_at IS NULL"),
        p,
    )?;
    if n > 0 {
        tx.tx
            .execute(&format!("UPDATE items {set} WHERE id = ?1"), p)?;
        tx.tx.execute(
            "DELETE FROM library_fts WHERE rowid = ?1 AND item_id = ?2",
            params![fts_rowid(playlist), playlist],
        )?;
    }
    Ok(())
}

/// Adds `items` (tracks, as roots) at `at`, keeping their given order. Always new entries:
/// removed ones stay deleted, so two devices re-adding a track yield two copies.
pub fn add(
    tx: &Tx,
    playlist: ItemId,
    items: &[ItemId],
    at: Place,
) -> rusqlite::Result<Vec<EntryId>> {
    let c = &tx.tx;
    live(c, playlist)?;
    let roots = items
        .iter()
        .map(|&item| {
            let root = canonical(c, item)?;
            let kind: Option<String> = c
                .query_row(
                    "SELECT kind FROM items WHERE id = ?1 AND deleted_at IS NULL",
                    [root],
                    |r| r.get(0),
                )
                .optional()?;
            match kind.as_deref() {
                Some(k) if k == Kind::Track.as_str() => Ok(root),
                _ => Err(invalid(format!("playlists: {item} is not a track"))),
            }
        })
        .collect::<rusqlite::Result<Vec<_>>>()?;
    let (mut lo, hi) = gap(&ordered(c, playlist, None)?, at)?;
    let mut out = Vec::with_capacity(items.len());
    for item in roots {
        let key = key_between(lo.as_deref(), hi.as_deref());
        let id = EntryId(uuid::Uuid::now_v7());
        c.execute(
            "INSERT INTO playlist_items (id, playlist_id, item_id, order_key, added_at, updated_at, device_id)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            params![
                id,
                playlist,
                item,
                key,
                tx.now_ms,
                tx.stamp.updated_at,
                tx.stamp.device_id.as_bytes().as_slice()
            ],
        )?;
        out.push(id);
        lo = Some(key);
    }
    Ok(out)
}

pub fn move_entry(tx: &Tx, entry: EntryId, at: Place) -> rusqlite::Result<()> {
    let c = &tx.tx;
    let playlist: ItemId = c
        .query_row(
            "SELECT e.playlist_id FROM playlist_items e JOIN playlists p ON p.item_id = e.playlist_id
             WHERE e.id = ?1 AND e.deleted_at IS NULL AND p.deleted_at IS NULL",
            [entry],
            |r| r.get(0),
        )
        .optional()?
        .ok_or_else(|| invalid(format!("playlists: no entry {}", entry.0)))?;
    if at == Place::After(entry) {
        return Ok(());
    }
    let (lo, hi) = gap(&ordered(c, playlist, Some(entry))?, at)?;
    c.execute(
        "UPDATE playlist_items SET order_key = ?2, updated_at = ?3, device_id = ?4 WHERE id = ?1",
        params![
            entry,
            key_between(lo.as_deref(), hi.as_deref()),
            tx.stamp.updated_at,
            tx.stamp.device_id.as_bytes().as_slice()
        ],
    )?;
    Ok(())
}

pub fn remove_entry(tx: &Tx, entry: EntryId) -> rusqlite::Result<()> {
    tx.tx.execute(
        "UPDATE playlist_items SET deleted_at = ?2, updated_at = ?3, device_id = ?4
         WHERE id = ?1 AND deleted_at IS NULL",
        params![
            entry,
            tx.now_ms,
            tx.stamp.updated_at,
            tx.stamp.device_id.as_bytes().as_slice()
        ],
    )?;
    Ok(())
}

/// Live entries of playlist `?1`: `e` the entry, `r` its item's root (deleted roots hidden).
const LIVE_ENTRIES: &str = "FROM playlist_items e
     JOIN playlists p ON p.item_id = e.playlist_id JOIN items i ON i.id = e.item_id
     JOIN items r ON r.id = COALESCE(i.merged_into, i.id)
     WHERE e.playlist_id = ?1 AND e.deleted_at IS NULL AND p.deleted_at IS NULL
       AND r.deleted_at IS NULL";

/// Live entries in `(order_key, id)` order; each shows its item's root (deleted roots hidden).
pub fn entries(
    c: &Connection,
    playlist: ItemId,
    page: Page,
) -> rusqlite::Result<Vec<(EntryId, ItemId)>> {
    let mut st = c.prepare(&format!(
        "SELECT e.id, r.id {LIVE_ENTRIES} ORDER BY e.order_key, e.id LIMIT ?2 OFFSET ?3"
    ))?;
    st.query_map(params![playlist, page.limit, page.offset], |r| {
        Ok((r.get(0)?, r.get(1)?))
    })?
    .collect()
}

/// Number of `entries`.
pub(crate) fn live_count(c: &Connection, playlist: ItemId) -> rusqlite::Result<u32> {
    c.query_row(
        &format!("SELECT count(*) {LIVE_ENTRIES}"),
        [playlist],
        |r| r.get(0),
    )
}

/// The playlist an entry belongs to (removed entries too).
pub fn playlist_of(c: &Connection, entry: EntryId) -> rusqlite::Result<Option<ItemId>> {
    c.query_row(
        "SELECT playlist_id FROM playlist_items WHERE id = ?1",
        [entry],
        |r| r.get(0),
    )
    .optional()
}

/// User playlists not deleted, in `sort` order (`Recent`: newest first).
pub fn list(c: &Connection, sort: CollectionSort) -> rusqlite::Result<Vec<ItemId>> {
    let (with, order) = collection_order(sort, "max(pl.created_at)");
    let mut st = c.prepare(&format!(
        "{with} SELECT r.id FROM playlists pl JOIN items i ON i.id = pl.item_id
         JOIN items r ON r.id = COALESCE(i.merged_into, i.id)
         WHERE pl.deleted_at IS NULL GROUP BY r.id ORDER BY {order}"
    ))?;
    st.query_map([], |r| r.get(0))?.collect()
}

fn live(c: &Connection, playlist: ItemId) -> rusqlite::Result<()> {
    let found: bool = c.query_row(
        "SELECT EXISTS (SELECT 1 FROM playlists WHERE item_id = ?1 AND deleted_at IS NULL)",
        [playlist],
        |r| r.get(0),
    )?;
    if found {
        Ok(())
    } else {
        Err(invalid(format!("playlists: no user playlist {playlist}")))
    }
}

/// Live entries in `(order_key, id)` order, without `skip`.
fn ordered(
    c: &Connection,
    playlist: ItemId,
    skip: Option<EntryId>,
) -> rusqlite::Result<Vec<(EntryId, String)>> {
    let mut st = c.prepare(
        "SELECT id, order_key FROM playlist_items WHERE playlist_id = ?1 AND deleted_at IS NULL
         ORDER BY order_key, id",
    )?;
    st.query_map([playlist], |r| Ok((r.get(0)?, r.get(1)?)))?
        .filter(|e| !matches!(e, Ok((id, _)) if Some(*id) == skip))
        .collect()
}

/// Bounds for a key at `at`: the nearest valid keys on each side, the upper one strictly
/// above the lower one. Equal keys (two devices, same insert) and invalid ones (sync) are
/// skipped, so `key_between` never sees them; with a tie right after `After(e)`, the new key
/// lands after the whole tie.
fn gap(
    list: &[(EntryId, String)],
    at: Place,
) -> rusqlite::Result<(Option<String>, Option<String>)> {
    let p = match at {
        Place::Start => 0,
        Place::End => list.len(),
        Place::After(e) => {
            1 + list
                .iter()
                .position(|x| x.0 == e)
                .ok_or_else(|| invalid(format!("playlists: no entry {} here", e.0)))?
        }
    };
    let lo = list[..p]
        .iter()
        .rev()
        .map(|x| &x.1)
        .find(|k| is_valid_key(k));
    let hi = list[p..]
        .iter()
        .map(|x| &x.1)
        .find(|k| is_valid_key(k) && lo.is_none_or(|lo| *k > lo));
    Ok((lo.cloned(), hi.cloned()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::library::catalog::{self, tests::track_data};
    use crate::library::{Db, fold, likes, plays};

    fn all() -> Page {
        Page {
            offset: 0,
            limit: 100,
        }
    }

    fn tracks(tx: &Tx, n: usize) -> rusqlite::Result<Vec<ItemId>> {
        (0..n)
            .map(|i| catalog::upsert_track(tx, "deezer", &track_data(&i.to_string(), None)))
            .collect()
    }

    fn items_of(c: &Connection, pl: ItemId) -> rusqlite::Result<Vec<ItemId>> {
        Ok(entries(c, pl, all())?.into_iter().map(|e| e.1).collect())
    }

    #[test]
    fn playlist_add_and_move_keep_order() {
        let db = Db::open_in_memory().unwrap();
        db.write_blocking(|tx| {
            let c = &tx.tx;
            let t = tracks(tx, 4)?;
            let (a, b, cc, d) = (t[0], t[1], t[2], t[3]);
            let pl = create(tx, "Mix", None)?;
            let e = add(tx, pl, &[a, b, cc], Place::End)?;
            assert_eq!(items_of(c, pl)?, vec![a, b, cc]);
            move_entry(tx, e[2], Place::After(e[0]))?;
            assert_eq!(items_of(c, pl)?, vec![a, cc, b]);
            add(tx, pl, &[d], Place::Start)?;
            assert_eq!(items_of(c, pl)?, vec![d, a, cc, b]);
            // Several items after one entry keep their given order, right after it.
            add(tx, pl, &[b, d], Place::After(e[0]))?;
            assert_eq!(items_of(c, pl)?, vec![d, a, b, d, cc, b]);
            move_entry(tx, e[0], Place::End)?;
            assert_eq!(items_of(c, pl)?, vec![d, b, d, cc, b, a]);
            assert_eq!(
                entries(
                    c,
                    pl,
                    Page {
                        offset: 1,
                        limit: 2
                    }
                )?
                .len(),
                2
            );
            // Every stored key is well formed.
            let mut st = c.prepare("SELECT order_key FROM playlist_items")?;
            let keys: Vec<String> = st.query_map([], |r| r.get(0))?.collect::<Result<_, _>>()?;
            assert_eq!(keys.len(), 6);
            assert!(keys.iter().all(|k| is_valid_key(k)));
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn equal_order_keys_sort_by_id() {
        let db = Db::open_in_memory().unwrap();
        db.write_blocking(|tx| {
            let c = &tx.tx;
            let t = tracks(tx, 3)?;
            let pl = create(tx, "Mix", None)?;
            let e = add(tx, pl, &[t[0], t[1]], Place::End)?;
            // Two devices picked the same key: the id breaks the tie, the same way every time.
            c.execute("UPDATE playlist_items SET order_key = 'V'", [])?;
            let mut by_id = e.clone();
            by_id.sort_by_key(|x| x.0);
            let read = || -> rusqlite::Result<Vec<EntryId>> {
                Ok(entries(c, pl, all())?.into_iter().map(|x| x.0).collect())
            };
            assert_eq!(read()?, by_id);
            assert_eq!(read()?, by_id);

            // Moving after the first of the tie never feeds equal keys to key_between.
            let (first, second) = (by_id[0], by_id[1]);
            let third = add(tx, pl, &[t[2]], Place::End)?[0];
            move_entry(tx, third, Place::After(first))?;
            let order = read()?;
            assert_eq!(order.len(), 3);
            assert_eq!(&order[..2], &[first, second]);
            add(tx, pl, &[t[2]], Place::After(first))?;
            add(tx, pl, &[t[2]], Place::Start)?;
            assert_eq!(read()?.len(), 5);
            assert_eq!(read()?, read()?);
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn invalid_neighbour_keys_are_skipped() {
        let db = Db::open_in_memory().unwrap();
        db.write_blocking(|tx| {
            let c = &tx.tx;
            let t = tracks(tx, 2)?;
            let pl = create(tx, "Mix", None)?;
            let e = add(tx, pl, &[t[0]], Place::End)?;
            // A foreign or corrupt key (sync): never handed to key_between.
            c.execute("UPDATE playlist_items SET order_key = 'é0'", [])?;
            add(tx, pl, &[t[1]], Place::End)?;
            add(tx, pl, &[t[1]], Place::Start)?;
            add(tx, pl, &[t[1]], Place::After(e[0]))?;
            assert_eq!(entries(c, pl, all())?.len(), 4);
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn deleted_playlist_is_hidden() {
        let db = Db::open_in_memory().unwrap();
        db.write_blocking(|tx| {
            let c = &tx.tx;
            let t = tracks(tx, 1)?;
            let keep = create(tx, "Keep", None)?;
            let gone = create(tx, "Gone", Some("bye"))?;
            add(tx, gone, &[t[0]], Place::End)?;
            assert_eq!(
                list(c, crate::library::CollectionSort::Recent)?,
                vec![gone, keep]
            );
            delete(tx, gone)?;
            assert_eq!(list(c, crate::library::CollectionSort::Recent)?, vec![keep]);
            assert!(entries(c, gone, all())?.is_empty());
            assert!(add(tx, gone, &[t[0]], Place::End).is_err());
            assert!(rename(tx, gone, "Back").is_err());
            let (rows, deleted): (i64, i64) = c.query_row(
                "SELECT count(*), count(deleted_at) FROM playlists WHERE item_id = ?1",
                [gone],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )?;
            assert_eq!((rows, deleted), (1, 1));
            let fts: i64 = c.query_row(
                "SELECT count(*) FROM library_fts WHERE item_id = ?1",
                [gone],
                |r| r.get(0),
            )?;
            assert_eq!(fts, 0);
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn rename_updates_title_and_search() {
        let db = Db::open_in_memory().unwrap();
        db.write_blocking(|tx| {
            let c = &tx.tx;
            let pl = create(tx, "Été", None)?;
            rename(tx, pl, "Hiver Noël")?;
            let title: String =
                c.query_row("SELECT title FROM items WHERE id = ?1", [pl], |r| r.get(0))?;
            assert_eq!(title, "Hiver Noël");
            let fts: String = c.query_row(
                "SELECT title FROM library_fts WHERE item_id = ?1",
                [pl],
                |r| r.get(0),
            )?;
            assert_eq!(fts, fold("Hiver Noël"));
            assert!(rename(tx, ItemId::new(), "x").is_err());
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn removed_entry_stays_deleted_and_readd_is_a_new_entry() {
        let db = Db::open_in_memory().unwrap();
        db.write_blocking(|tx| {
            let c = &tx.tx;
            let t = tracks(tx, 2)?;
            let pl = create(tx, "Mix", None)?;
            let e = add(tx, pl, &[t[0], t[1]], Place::End)?;
            remove_entry(tx, e[0])?;
            remove_entry(tx, e[0])?;
            assert_eq!(items_of(c, pl)?, vec![t[1]]);
            let back = add(tx, pl, &[t[0]], Place::Start)?;
            assert_eq!(back.len(), 1);
            assert_ne!(back[0], e[0]);
            assert_eq!(entries(c, pl, all())?, vec![(back[0], t[0]), (e[1], t[1])]);
            let (rows, old_deleted): (i64, bool) = c.query_row(
                "SELECT (SELECT count(*) FROM playlist_items),
                        (SELECT deleted_at IS NOT NULL FROM playlist_items WHERE id = ?1)",
                [e[0]],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )?;
            assert_eq!((rows, old_deleted), (3, true));
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn add_takes_tracks_only_and_entries_hide_deleted_items() {
        let db = Db::open_in_memory().unwrap();
        db.write_blocking(|tx| {
            let c = &tx.tx;
            let t = tracks(tx, 2)?;
            let pl = create(tx, "Mix", None)?;
            let other = create(tx, "Other", None)?;
            assert!(add(tx, pl, &[other], Place::End).is_err());
            assert!(add(tx, pl, &[ItemId::new()], Place::End).is_err());
            assert!(items_of(c, pl)?.is_empty());
            add(tx, pl, &[t[0], t[1]], Place::End)?;
            c.execute("UPDATE items SET deleted_at = 1 WHERE id = ?1", [t[0]])?;
            assert_eq!(items_of(c, pl)?, vec![t[1]]);
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn move_after_itself_is_a_no_op_and_unknown_entries_fail() {
        let db = Db::open_in_memory().unwrap();
        db.write_blocking(|tx| {
            let c = &tx.tx;
            let t = tracks(tx, 2)?;
            let pl = create(tx, "Mix", None)?;
            let e = add(tx, pl, &[t[0], t[1]], Place::End)?;
            let key = |id: EntryId| -> rusqlite::Result<String> {
                c.query_row(
                    "SELECT order_key FROM playlist_items WHERE id = ?1",
                    [id],
                    |r| r.get(0),
                )
            };
            let before = key(e[0])?;
            move_entry(tx, e[0], Place::After(e[0]))?;
            assert_eq!(key(e[0])?, before);
            assert_eq!(items_of(c, pl)?, vec![t[0], t[1]]);
            let ghost = EntryId(uuid::Uuid::now_v7());
            assert!(move_entry(tx, ghost, Place::End).is_err());
            assert!(move_entry(tx, e[0], Place::After(ghost)).is_err());
            remove_entry(tx, ghost)?;
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn writes_carry_sync_columns() {
        let db = Db::open_in_memory().unwrap();
        let dev = db.device_id();
        let tables = ["likes", "playlists", "playlist_items", "plays"];
        let check = |stamp: i64| {
            db.read_blocking(move |c| {
                for t in tables {
                    let (n, ok): (i64, i64) = c.query_row(
                        &format!(
                            "SELECT count(*), sum(updated_at = ?1 AND device_id = ?2) FROM {t}"
                        ),
                        params![stamp, dev.as_bytes().as_slice()],
                        |r| Ok((r.get(0)?, r.get(1)?)),
                    )?;
                    assert!(n > 0 && n == ok, "{t}: {ok}/{n} rows carry the stamp");
                }
                Ok(())
            })
            .unwrap()
        };
        let (stamp, ids) = db
            .write_blocking(|tx| {
                let t = tracks(tx, 1)?[0];
                likes::set(tx, t, true)?;
                let pl = create(tx, "Mix", None)?;
                let e = add(tx, pl, &[t], Place::End)?[0];
                let play = plays::start(tx, t, "test", None)?;
                Ok((tx.stamp.updated_at, (t, pl, e, play)))
            })
            .unwrap();
        check(stamp);
        let (t, pl, e, play) = ids;
        let stamp = db
            .write_blocking(move |tx| {
                likes::set(tx, t, false)?;
                move_entry(tx, e, Place::Start)?;
                plays::set_listened(tx, play, 1000)?;
                delete(tx, pl)?;
                Ok(tx.stamp.updated_at)
            })
            .unwrap();
        check(stamp);
        let stamp = db
            .write_blocking(move |tx| {
                likes::set(tx, t, true)?;
                remove_entry(tx, e)?;
                Ok(tx.stamp.updated_at)
            })
            .unwrap();
        db.read_blocking(move |c| {
            for t in ["likes", "playlist_items"] {
                let ok: bool =
                    c.query_row(&format!("SELECT updated_at = ?1 FROM {t}"), [stamp], |r| {
                        r.get(0)
                    })?;
                assert!(ok, "{t}");
            }
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn playlists_sort_recent_played_title() {
        use crate::library::CollectionSort;
        use crate::library::plays::tests::{now_ms, play_at};
        let db = Db::open_in_memory().unwrap();
        let (x, y, t) = db
            .write_blocking(|tx| {
                let x = create(tx, "zouk", None)?;
                let y = create(tx, "Électro", None)?;
                let t = tracks(tx, 1)?[0];
                add(tx, x, &[t], Place::End)?;
                // Same wall ms possible: make y the newer one.
                tx.tx.execute(
                    "UPDATE playlists SET created_at = created_at + 1000 WHERE item_id = ?1",
                    [y],
                )?;
                Ok((x, y, t))
            })
            .unwrap();
        play_at(&db, t, now_ms(), 60_000, None);
        let sorted = |sort| db.read_blocking(move |c| list(c, sort)).unwrap();
        assert_eq!(sorted(CollectionSort::Recent), vec![y, x]);
        assert_eq!(sorted(CollectionSort::Played), vec![x, y]);
        assert_eq!(sorted(CollectionSort::Title), vec![y, x]);
    }
}
