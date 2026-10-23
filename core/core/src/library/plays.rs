use std::collections::HashSet;

use rusqlite::{Connection, params};

use super::items::canonical;
use super::{CollectionSort, ItemId, Kind, Page, TrackSort, Tx};

/// A play counts in tops and "not played since" from 30 s.
pub const COUNTED_MS: i64 = 30_000;
/// The Top 50 window (90 days) and size.
pub const TOP_WINDOW_MS: i64 = 90 * 86_400_000;
pub const TOP_TRACKS: u32 = 50;

/// Records a play of the item's root starting now, from `context` (album, playlist or
/// artist; an unknown id is not recorded); returns the play id.
pub fn start(
    tx: &Tx,
    item: ItemId,
    source: &str,
    context: Option<ItemId>,
) -> rusqlite::Result<uuid::Uuid> {
    let id = uuid::Uuid::now_v7();
    tx.tx.execute(
        "INSERT INTO plays (id, item_id, started_at, source, updated_at, device_id, context_id)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6,
           (SELECT COALESCE(merged_into, id) FROM items WHERE id = ?7))",
        params![
            id.as_bytes().as_slice(),
            canonical(&tx.tx, item)?,
            tx.now_ms,
            source,
            tx.stamp.updated_at,
            tx.stamp.device_id.as_bytes().as_slice(),
            context
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
    Ok(recent_with_time(c, kind, page)?
        .into_iter()
        .map(|(id, _)| id)
        .collect())
}

/// `recent_items` with the start (unix ms) of each one's latest play.
pub fn recent_with_time(
    c: &Connection,
    kind: Kind,
    page: Page,
) -> rusqlite::Result<Vec<(ItemId, i64)>> {
    // Same-ms plays: the later UUIDv7 id wins.
    let mut st = c.prepare(
        "SELECT r.id, max(p.started_at) FROM plays p JOIN items i ON i.id = p.item_id
         JOIN items r ON r.id = COALESCE(i.merged_into, i.id)
         WHERE p.deleted_at IS NULL AND r.kind = ?1 AND r.deleted_at IS NULL
         GROUP BY r.id ORDER BY max(p.started_at) DESC, max(p.id) DESC LIMIT ?2 OFFSET ?3",
    )?;
    st.query_map(params![kind.as_str(), page.limit, page.offset], |r| {
        Ok((r.get(0)?, r.get(1)?))
    })?
    .collect()
}

/// Plays `p` with the live root `r` of the item played.
const PLAYED: &str = "FROM plays p JOIN items i ON i.id = p.item_id
     JOIN items r ON r.id = COALESCE(i.merged_into, i.id)";

/// `p` is a live counted play (>= 30 s) started since `?1`.
fn counted() -> String {
    format!("p.deleted_at IS NULL AND p.listened_ms >= {COUNTED_MS} AND p.started_at >= ?1")
}

/// Most played tracks, or artists of the tracks played, since `since_ms`: by counted plays,
/// then latest play. Albums and playlists: see `top_contexts`.
pub fn top_items(
    c: &Connection,
    kind: Kind,
    since_ms: i64,
    limit: u32,
) -> rusqlite::Result<Vec<ItemId>> {
    let counted = counted();
    let sql = match kind {
        Kind::Track => format!(
            "SELECT r.id {PLAYED} WHERE {counted} AND r.kind = 'track' AND r.deleted_at IS NULL
             GROUP BY r.id ORDER BY count(*) DESC, max(p.started_at) DESC, r.id DESC LIMIT ?2"
        ),
        Kind::Artist => format!(
            "SELECT ar.id {PLAYED} JOIN music_track_artists ta ON ta.track_id = r.id
             JOIN items a ON a.id = ta.artist_id
             JOIN items ar ON ar.id = COALESCE(a.merged_into, a.id)
             WHERE {counted} AND r.kind = 'track' AND ar.deleted_at IS NULL
             GROUP BY ar.id ORDER BY count(DISTINCT p.id) DESC, max(p.started_at) DESC, ar.id DESC
             LIMIT ?2"
        ),
        Kind::Album | Kind::Playlist => return Ok(vec![]),
    };
    let mut st = c.prepare(&sql)?;
    st.query_map(params![since_ms, limit], |r| r.get(0))?
        .collect()
}

/// The Top 50: the 90-day top, completed from the all-time top without duplicates.
pub fn top_tracks(c: &Connection, now_ms: i64) -> rusqlite::Result<Vec<ItemId>> {
    let mut top = top_items(c, Kind::Track, now_ms - TOP_WINDOW_MS, TOP_TRACKS)?;
    if top.len() < TOP_TRACKS as usize {
        for id in top_items(c, Kind::Track, 0, TOP_TRACKS)? {
            if !top.contains(&id) {
                top.push(id);
            }
        }
        top.truncate(TOP_TRACKS as usize);
    }
    Ok(top)
}

/// Live collections plays were started from since `since_ms`: by counted plays, then
/// latest play.
pub fn top_contexts(c: &Connection, since_ms: i64, limit: u32) -> rusqlite::Result<Vec<ItemId>> {
    let mut st = c.prepare(&format!(
        "SELECT x.id FROM plays p JOIN items i ON i.id = p.context_id
         JOIN items x ON x.id = COALESCE(i.merged_into, i.id)
         WHERE p.context_id IS NOT NULL AND {} AND x.deleted_at IS NULL
         GROUP BY x.id ORDER BY count(*) DESC, max(p.started_at) DESC, x.id DESC LIMIT ?2",
        counted()
    ))?;
    st.query_map(params![since_ms, limit], |r| r.get(0))?
        .collect()
}

/// Liked tracks without a counted play since `before_ms`, most recently liked first.
pub fn liked_not_played_since(
    c: &Connection,
    before_ms: i64,
    limit: u32,
) -> rusqlite::Result<Vec<ItemId>> {
    let mut st = c.prepare(&format!(
        "SELECT l_root.id FROM likes l JOIN items li ON li.id = l.item_id
         JOIN items l_root ON l_root.id = COALESCE(li.merged_into, li.id)
         WHERE l.deleted_at IS NULL AND l_root.kind = 'track' AND l_root.deleted_at IS NULL
           AND l_root.id NOT IN (SELECT r.id {PLAYED} WHERE {})
         GROUP BY l_root.id ORDER BY max(l.liked_at) DESC, l_root.id DESC LIMIT ?2",
        counted()
    ))?;
    st.query_map(params![before_ms, limit], |r| r.get(0))?
        .collect()
}

/// Roots of every item played (any length) or liked: discovery leaves them out.
pub fn played_or_liked(c: &Connection) -> rusqlite::Result<HashSet<ItemId>> {
    let mut st = c.prepare(
        "SELECT COALESCE(i.merged_into, i.id) FROM plays p JOIN items i ON i.id = p.item_id
         WHERE p.deleted_at IS NULL
         UNION SELECT COALESCE(i.merged_into, i.id) FROM likes l JOIN items i ON i.id = l.item_id
         WHERE l.deleted_at IS NULL",
    )?;
    st.query_map([], |r| r.get(0))?.collect()
}

/// Track ids of the collection `r` (root), whatever its kind: album, artist, provider or
/// user playlist.
const MEMBERS: &str = "SELECT track_id FROM music_album_tracks WHERE album_id = r.id
     UNION SELECT item_id FROM music_tracks WHERE album_id = r.id
     UNION SELECT track_id FROM music_track_artists WHERE artist_id = r.id
     UNION SELECT track_id FROM music_playlist_tracks WHERE playlist_id = r.id
     UNION SELECT item_id FROM playlist_items WHERE playlist_id = r.id AND deleted_at IS NULL";

/// `ORDER BY` for collections whose root is `r`; `recent` is the date liked or created.
// ponytail: Played is a correlated subquery per row; keep a last_played column if lists get slow
pub(crate) fn collection_order(sort: CollectionSort, recent: &str) -> String {
    match sort {
        CollectionSort::Recent => format!("{recent} DESC, r.id DESC"),
        CollectionSort::Played => format!(
            "(SELECT max(p.started_at) FROM plays p JOIN items pi ON pi.id = p.item_id
              WHERE p.deleted_at IS NULL AND COALESCE(pi.merged_into, pi.id) IN
                (SELECT COALESCE(t.merged_into, t.id) FROM items t WHERE t.id IN ({MEMBERS})))
             DESC, {recent} DESC, r.id DESC"
        ),
        CollectionSort::Title => "fold(r.title), r.id".into(),
    }
}

/// `ORDER BY` for tracks whose root is `r`; `added` is the date liked or downloaded.
pub(crate) fn track_order(sort: TrackSort, added: &str) -> String {
    match sort {
        TrackSort::Added => format!("{added} DESC, r.id DESC"),
        TrackSort::Title => "fold(r.title), r.id".into(),
        TrackSort::Artist => "fold(COALESCE((SELECT ar.title FROM music_track_artists ta
             JOIN items a ON a.id = ta.artist_id JOIN items ar ON ar.id = COALESCE(a.merged_into, a.id)
             WHERE ta.track_id = r.id ORDER BY ta.position LIMIT 1), '')), fold(r.title), r.id"
            .into(),
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use crate::library::Db;
    use crate::library::catalog::{self, ArtistData, tests::track_data};

    pub(crate) const DAY: i64 = 86_400_000;

    pub(crate) fn now_ms() -> i64 {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_millis() as i64
    }

    /// A track titled `title` by `artist`, on album `album` when given.
    pub(crate) fn song(
        tx: &Tx,
        ext: &str,
        title: &str,
        artist: &str,
        album: Option<&str>,
    ) -> rusqlite::Result<ItemId> {
        let mut t = track_data(ext, None);
        t.title = title.into();
        t.artists = vec![ArtistData {
            ext_id: None,
            name: artist.into(),
            artwork: vec![],
        }];
        t.album = album.map(|a| (None, a.to_string()));
        catalog::upsert_track(tx, "deezer", &t)
    }

    /// A play of `t` started at `at`, `listened` ms long, from `ctx`.
    pub(crate) fn play_at(db: &Db, t: ItemId, at: i64, listened: i64, ctx: Option<ItemId>) {
        db.write_blocking(move |tx| {
            let p = start(tx, t, "test", ctx)?;
            tx.tx.execute(
                "UPDATE plays SET started_at = ?2, listened_ms = ?3 WHERE id = ?1",
                params![p.as_bytes().as_slice(), at, listened],
            )?;
            Ok(())
        })
        .unwrap();
    }

    fn album_of(db: &Db, t: ItemId) -> ItemId {
        db.read_blocking(move |c| Ok(catalog::track(c, t)?.unwrap().album.unwrap().0))
            .unwrap()
    }

    fn artist_of(db: &Db, t: ItemId) -> ItemId {
        db.read_blocking(move |c| Ok(catalog::track(c, t)?.unwrap().artists[0].0))
            .unwrap()
    }

    #[test]
    fn plays_record_their_context() {
        let db = Db::open_in_memory().unwrap();
        let t = db
            .write_blocking(|tx| song(tx, "1", "Halo", "Beyoncé", Some("I Am")))
            .unwrap();
        let album = album_of(&db, t);
        let unknown = ItemId::new();
        let (a, b, u) = db
            .write_blocking(move |tx| {
                Ok((
                    start(tx, t, "test", Some(album))?,
                    start(tx, t, "test", None)?,
                    start(tx, t, "test", Some(unknown))?,
                ))
            })
            .unwrap();
        let ctx = |p: uuid::Uuid| {
            db.read_blocking(move |c| {
                c.query_row(
                    "SELECT context_id FROM plays WHERE id = ?1",
                    [p.as_bytes().as_slice()],
                    |r| r.get::<_, Option<ItemId>>(0),
                )
            })
            .unwrap()
        };
        assert_eq!(ctx(a), Some(album));
        assert_eq!(ctx(b), None);
        assert_eq!(ctx(u), None, "an unknown context is not recorded");
    }

    #[test]
    fn top_items_counts_only_30s_plays_in_window() {
        let db = Db::open_in_memory().unwrap();
        let (a, b, c) = db
            .write_blocking(|tx| {
                Ok((
                    song(tx, "a", "A", "One", None)?,
                    song(tx, "b", "B", "Two", None)?,
                    song(tx, "c", "C", "Two", None)?,
                ))
            })
            .unwrap();
        let now = now_ms();
        play_at(&db, a, now - DAY, 30_000, None);
        play_at(&db, a, now - DAY, 200_000, None);
        for _ in 0..3 {
            play_at(&db, b, now - DAY, 29_999, None);
        }
        play_at(&db, b, now - 91 * DAY, 40_000, None);
        play_at(&db, c, now - 2 * DAY, 30_000, None);
        let since = now - 90 * DAY;
        let (one, two) = (artist_of(&db, a), artist_of(&db, b));
        let (tracks, artists, all, cut, albums) = db
            .read_blocking(move |cn| {
                Ok((
                    top_items(cn, Kind::Track, since, 10)?,
                    top_items(cn, Kind::Artist, since, 10)?,
                    top_items(cn, Kind::Track, 0, 10)?,
                    top_items(cn, Kind::Track, since, 1)?,
                    top_items(cn, Kind::Album, since, 10)?,
                ))
            })
            .unwrap();
        assert_eq!(tracks, vec![a, c]);
        assert_eq!(artists, vec![one, two]);
        // All time: b's old play counts; ties go to the latest play.
        assert_eq!(all, vec![a, c, b]);
        assert_eq!(cut, vec![a]);
        assert!(albums.is_empty());
    }

    #[test]
    fn top_50_backfills_from_all_time() {
        let db = Db::open_in_memory().unwrap();
        let (recent, old) = db
            .write_blocking(|tx| {
                Ok((
                    song(tx, "r", "Recent", "X", None)?,
                    song(tx, "o", "Old", "X", None)?,
                ))
            })
            .unwrap();
        let now = now_ms();
        play_at(&db, recent, now - DAY, 60_000, None);
        for _ in 0..3 {
            play_at(&db, old, now - 100 * DAY, 60_000, None);
        }
        let top = db.read_blocking(move |c| top_tracks(c, now)).unwrap();
        // The window's tracks first, then the all-time ones, without duplicates.
        assert_eq!(top, vec![recent, old]);
    }

    #[test]
    fn top_contexts_rank_recent_collections() {
        let db = Db::open_in_memory().unwrap();
        let (x, y) = db
            .write_blocking(|tx| {
                Ok((
                    song(tx, "x", "X1", "A", Some("Album X"))?,
                    song(tx, "y", "Y1", "A", Some("Album Y"))?,
                ))
            })
            .unwrap();
        let (ax, ay) = (album_of(&db, x), album_of(&db, y));
        let pl = db
            .write_blocking(|tx| crate::library::playlists::create(tx, "Mine", None))
            .unwrap();
        let now = now_ms();
        play_at(&db, x, now - DAY, 60_000, Some(ax));
        play_at(&db, x, now - DAY, 60_000, Some(ax));
        play_at(&db, y, now - 2 * DAY, 60_000, Some(pl));
        play_at(&db, y, now - 2 * DAY, 1_000, Some(ay));
        play_at(&db, y, now - 100 * DAY, 60_000, Some(ay));
        play_at(&db, y, now - DAY, 60_000, None);
        let top = db
            .read_blocking(move |c| top_contexts(c, now - 90 * DAY, 10))
            .unwrap();
        assert_eq!(top, vec![ax, pl]);
    }

    #[test]
    fn liked_not_played_since_excludes_recent_plays() {
        let db = Db::open_in_memory().unwrap();
        let t = db
            .write_blocking(|tx| {
                (0..5)
                    .map(|i| song(tx, &i.to_string(), "T", "A", None))
                    .collect::<rusqlite::Result<Vec<_>>>()
            })
            .unwrap();
        let ids = t.clone();
        db.write_blocking(move |tx| {
            // Liked in order 0..4, one second apart; 4 is unliked.
            for (i, &id) in ids.iter().enumerate() {
                crate::library::likes::set(tx, id, true)?;
                tx.tx.execute(
                    "UPDATE likes SET liked_at = ?2 WHERE item_id = ?1",
                    params![id, 1_000 * i as i64],
                )?;
            }
            crate::library::likes::set(tx, ids[4], false)
        })
        .unwrap();
        let now = now_ms();
        play_at(&db, t[0], now - DAY, 40_000, None); // played lately: out
        play_at(&db, t[1], now - 100 * DAY, 40_000, None); // long ago: in
        play_at(&db, t[3], now - DAY, 5_000, None); // a skip is no play: in
        let got = db
            .read_blocking(move |c| liked_not_played_since(c, now - 60 * DAY, 10))
            .unwrap();
        assert_eq!(got, vec![t[3], t[2], t[1]]);
    }

    #[test]
    fn played_or_liked_covers_both() {
        let db = Db::open_in_memory().unwrap();
        let (p, l, gone, none) = db
            .write_blocking(|tx| {
                let t = (
                    song(tx, "p", "P", "A", None)?,
                    song(tx, "l", "L", "A", None)?,
                    song(tx, "g", "G", "A", None)?,
                    song(tx, "n", "N", "A", None)?,
                );
                crate::library::likes::set(tx, t.1, true)?;
                crate::library::likes::set(tx, t.2, true)?;
                crate::library::likes::set(tx, t.2, false)?;
                Ok(t)
            })
            .unwrap();
        play_at(&db, p, now_ms(), 1_000, None);
        let set = db.read_blocking(played_or_liked).unwrap();
        assert!(set.contains(&p) && set.contains(&l));
        assert!(!set.contains(&gone) && !set.contains(&none));
    }

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
            db.write_blocking(move |tx| start(tx, t, "test", None))
                .unwrap();
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
                start(tx, t, "album", None)
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
