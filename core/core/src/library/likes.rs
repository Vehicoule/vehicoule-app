use rusqlite::{Connection, params};

use super::catalog::in_group;
use super::items::canonical;
use super::{CollectionSort, ItemId, Kind, Page, TrackSort, Tx, collection_order, track_order};

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
    list_collections(c, kind, CollectionSort::Recent, page)
}

/// Liked albums, artists or playlists in `sort` order.
pub fn list_collections(
    c: &Connection,
    kind: Kind,
    sort: CollectionSort,
    page: Page,
) -> rusqlite::Result<Vec<ItemId>> {
    let (with, order) = collection_order(sort, LIKED_AT);
    query(c, kind, &with, &order, page)
}

/// Liked tracks in `sort` order.
pub fn list_tracks(c: &Connection, sort: TrackSort, page: Page) -> rusqlite::Result<Vec<ItemId>> {
    query(c, Kind::Track, "", &track_order(sort, LIKED_AT), page)
}

const LIKED_AT: &str = "max(l.liked_at)";

fn query(
    c: &Connection,
    kind: Kind,
    with: &str,
    order: &str,
    page: Page,
) -> rusqlite::Result<Vec<ItemId>> {
    let mut st = c.prepare(&format!(
        "{with} SELECT r.id FROM likes l JOIN items i ON i.id = l.item_id
         JOIN items r ON r.id = COALESCE(i.merged_into, i.id)
         WHERE l.deleted_at IS NULL AND r.kind = ?1 AND r.deleted_at IS NULL
         GROUP BY r.id ORDER BY {order} LIMIT ?2 OFFSET ?3"
    ))?;
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
    use crate::library::plays::tests::{DAY, now_ms, play_at, song};
    use crate::library::{CollectionSort, TrackSort, items};

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

    /// Likes each item, `liked_at` 1 s apart in the given order.
    fn like_in_order(db: &Db, items: Vec<ItemId>) {
        db.write_blocking(move |tx| {
            for (i, &id) in items.iter().enumerate() {
                set(tx, id, true)?;
                tx.tx.execute(
                    "UPDATE likes SET liked_at = ?2 WHERE item_id = ?1",
                    params![id, 1_000 * i as i64],
                )?;
            }
            Ok(())
        })
        .unwrap();
    }

    fn album_of(db: &Db, t: ItemId) -> ItemId {
        db.read_blocking(move |c| Ok(catalog::track(c, t)?.unwrap().album.unwrap().0))
            .unwrap()
    }

    #[test]
    fn liked_sorts_recent_played_title() {
        let db = Db::open_in_memory().unwrap();
        let (b, a, c) = db
            .write_blocking(|tx| {
                Ok((
                    song(tx, "b", "b1", "X", Some("Bravo"))?,
                    song(tx, "a", "a1", "X", Some("alpha"))?,
                    song(tx, "c", "c1", "X", Some("Charlie"))?,
                ))
            })
            .unwrap();
        let (bravo, alpha, charlie) = (album_of(&db, b), album_of(&db, a), album_of(&db, c));
        like_in_order(&db, vec![bravo, alpha, charlie]);
        let now = now_ms();
        play_at(&db, c, now - 2 * DAY, 60_000, None);
        play_at(&db, b, now - DAY, 60_000, None);
        // A skip is not a play.
        play_at(&db, a, now, 29_999, None);
        let sorted = |sort| {
            db.read_blocking(move |cn| list_collections(cn, Kind::Album, sort, page()))
                .unwrap()
        };
        assert_eq!(sorted(CollectionSort::Recent), vec![charlie, alpha, bravo]);
        // Never played goes last.
        assert_eq!(sorted(CollectionSort::Played), vec![bravo, charlie, alpha]);
        // Folded: "alpha" before "Bravo".
        assert_eq!(sorted(CollectionSort::Title), vec![alpha, bravo, charlie]);
    }

    #[test]
    fn liked_tracks_sort_by_artist_uses_fold() {
        let db = Db::open_in_memory().unwrap();
        let (edith, zaz) = db
            .write_blocking(|tx| {
                Ok((
                    song(tx, "e", "Bonjour", "Édith", None)?,
                    song(tx, "z", "Allo", "Zaz", None)?,
                ))
            })
            .unwrap();
        like_in_order(&db, vec![edith, zaz]);
        let sorted = |sort| {
            db.read_blocking(move |c| list_tracks(c, sort, page()))
                .unwrap()
        };
        assert_eq!(sorted(TrackSort::Artist), vec![edith, zaz]);
        assert_eq!(sorted(TrackSort::Title), vec![zaz, edith]);
        assert_eq!(sorted(TrackSort::Added), vec![zaz, edith]);
    }

    #[test]
    fn sorted_pages_do_not_overlap() {
        let db = Db::open_in_memory().unwrap();
        // Same title, artist and liked_at: only the tie-break orders them.
        db.write_blocking(|tx| {
            for i in 0..4 {
                let t = song(tx, &i.to_string(), "Same", "Same", Some("Same"))?;
                set(tx, t, true)?;
            }
            Ok(())
        })
        .unwrap();
        let pages = |a: Vec<ItemId>, b: Vec<ItemId>| {
            let mut all: Vec<ItemId> = a.into_iter().chain(b).collect();
            all.sort();
            all.dedup();
            all.len()
        };
        let at = |offset| Page { offset, limit: 2 };
        for sort in [TrackSort::Added, TrackSort::Title, TrackSort::Artist] {
            let (a, b) = db
                .read_blocking(move |c| {
                    Ok((list_tracks(c, sort, at(0))?, list_tracks(c, sort, at(2))?))
                })
                .unwrap();
            assert_eq!(pages(a, b), 4, "{sort:?}");
        }
        let album = db
            .read_blocking(|c| list_tracks(c, TrackSort::Added, page()))
            .map(|t| album_of(&db, t[0]))
            .unwrap();
        db.write_blocking(move |tx| {
            set(tx, album, true)?;
            for i in 0..3 {
                let a = song(tx, &format!("x{i}"), "S", "S", Some(&format!("Same {i}")))?;
                let a = catalog::track(&tx.tx, a)?.unwrap().album.unwrap().0;
                tx.tx
                    .execute("UPDATE items SET title = 'Same' WHERE id = ?1", [a])?;
                set(tx, a, true)?;
            }
            Ok(())
        })
        .unwrap();
        for sort in [
            CollectionSort::Recent,
            CollectionSort::Played,
            CollectionSort::Title,
        ] {
            let (a, b) = db
                .read_blocking(move |c| {
                    Ok((
                        list_collections(c, Kind::Album, sort, at(0))?,
                        list_collections(c, Kind::Album, sort, at(2))?,
                    ))
                })
                .unwrap();
            assert_eq!(pages(a, b), 4, "{sort:?}");
        }
    }

    #[test]
    fn played_sort_follows_merged_plays() {
        let db = Db::open_in_memory().unwrap();
        let (a, b, c) = db
            .write_blocking(|tx| {
                Ok((
                    song(tx, "a", "A", "X", Some("Xa"))?,
                    song(tx, "b", "A", "X", None)?,
                    song(tx, "c", "C", "X", Some("Yc"))?,
                ))
            })
            .unwrap();
        let (xa, yc) = (album_of(&db, a), album_of(&db, c));
        like_in_order(&db, vec![xa, yc]);
        let now = now_ms();
        // Xa's track a was played as its twin b, after Yc's track.
        play_at(&db, b, now - DAY, 60_000, None);
        play_at(&db, c, now - 2 * DAY, 60_000, None);
        db.write_blocking(move |tx| items::merge(tx, a, b)).unwrap();
        let got = db
            .read_blocking(|cn| list_collections(cn, Kind::Album, CollectionSort::Played, page()))
            .unwrap();
        assert_eq!(got, vec![xa, yc]);
    }

    /// 100 liked albums of 50 tracks, 50 artists, one play per track: a page sorted by latest
    /// play stays fast (it took ~10 s with the per-row subquery).
    #[test]
    fn played_sort_is_fast_on_a_big_catalogue() {
        let db = Db::open_in_memory().unwrap();
        let albums = db
            .write_blocking(|tx| {
                let c = &tx.tx;
                let (stamp, dev) = (tx.stamp.updated_at, tx.stamp.device_id.as_bytes().as_slice());
                let mut item = c.prepare(
                    "INSERT INTO items (id, kind, title, updated_at, device_id) VALUES (?1, ?2, ?3, ?4, ?5)",
                )?;
                let mut new = |kind: &str, title: String| -> rusqlite::Result<ItemId> {
                    let id = ItemId::new();
                    item.execute(params![id, kind, title, stamp, dev])?;
                    Ok(id)
                };
                let albums = (0..100)
                    .map(|i| new("album", format!("Album {i}")))
                    .collect::<rusqlite::Result<Vec<_>>>()?;
                let artists = (0..50)
                    .map(|i| new("artist", format!("Artist {i}")))
                    .collect::<rusqlite::Result<Vec<_>>>()?;
                for (i, &a) in albums.iter().enumerate() {
                    c.execute("INSERT INTO music_albums (item_id) VALUES (?1)", [a])?;
                    c.execute(
                        "INSERT INTO likes (item_id, liked_at, updated_at, device_id) VALUES (?1, ?2, ?3, ?4)",
                        params![a, i as i64, stamp, dev],
                    )?;
                }
                for i in 0..5000 {
                    let t = new("track", format!("Track {i}"))?;
                    c.execute(
                        "INSERT INTO music_tracks (item_id, album_id) VALUES (?1, ?2)",
                        params![t, albums[i % 100]],
                    )?;
                    c.execute(
                        "INSERT INTO music_track_artists (track_id, artist_id, position) VALUES (?1, ?2, 0)",
                        params![t, artists[i % 50]],
                    )?;
                    c.execute(
                        "INSERT INTO plays (id, item_id, started_at, listened_ms, source, updated_at, device_id)
                         VALUES (?1, ?2, ?3, 60000, 'test', ?4, ?5)",
                        params![uuid::Uuid::now_v7().as_bytes().as_slice(), t, 1_000 + i as i64, stamp, dev],
                    )?;
                }
                Ok(albums)
            })
            .unwrap();
        let started = std::time::Instant::now();
        let got = db
            .read_blocking(|c| {
                list_collections(
                    c,
                    Kind::Album,
                    CollectionSort::Played,
                    Page {
                        offset: 0,
                        limit: 50,
                    },
                )
            })
            .unwrap();
        let took = started.elapsed();
        // The latest play of album k is track 4900 + k.
        let want: Vec<ItemId> = albums.iter().rev().take(50).copied().collect();
        assert_eq!(got, want);
        assert!(took.as_millis() < 500, "a sorted page took {took:?}");
    }
}
