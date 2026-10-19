//! Provider catalogue cache: upserts keyed by external refs, reads that follow `merged_into`.

use rusqlite::{Connection, OptionalExtension, params};

use super::items::{canonical, fts_rowid, invalid};
use super::{ItemId, Kind, Page, Tx, fold, refs};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Image {
    pub url: String,
    pub width: Option<u32>,
}

#[derive(Debug, Clone)]
pub struct ArtistData {
    /// None: the provider only gives the name.
    pub ext_id: Option<String>,
    pub name: String,
    pub artwork: Vec<Image>,
}

#[derive(Debug, Clone)]
pub struct TrackData {
    pub ext_id: String,
    pub title: String,
    pub artists: Vec<ArtistData>,
    /// (ext_id, title)
    pub album: Option<(Option<String>, String)>,
    pub duration_ms: Option<u32>,
    pub isrc: Option<String>,
    pub explicit: bool,
    pub artwork: Vec<Image>,
}

#[derive(Debug, Clone)]
pub struct AlbumData {
    pub ext_id: String,
    pub title: String,
    pub artists: Vec<ArtistData>,
    pub year: Option<u16>,
    pub track_count: Option<u32>,
    pub artwork: Vec<Image>,
}

#[derive(Debug, Clone)]
pub struct PlaylistData {
    pub ext_id: String,
    pub title: String,
    pub owner: Option<String>,
    pub description: Option<String>,
    pub track_count: Option<u32>,
    pub artwork: Vec<Image>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct TrackRow {
    pub id: ItemId,
    pub title: String,
    pub artists: Vec<(ItemId, String)>,
    pub album: Option<(ItemId, String)>,
    pub duration_ms: Option<u32>,
    pub isrc: Option<String>,
    pub explicit: bool,
    pub artwork: Vec<Image>,
    pub liked: bool,
    pub downloaded: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct CollectionRow {
    pub id: ItemId,
    pub kind: Kind,
    pub title: String,
    pub subtitle: Option<String>,
    pub artwork: Vec<Image>,
    pub track_count: Option<u32>,
    pub liked: bool,
}

pub fn upsert_track(tx: &Tx, provider: &str, t: &TrackData) -> rusqlite::Result<ItemId> {
    let c = &tx.tx;
    let isrc = t
        .isrc
        .as_deref()
        .map(|s| s.trim().to_ascii_uppercase())
        .filter(|s| !s.is_empty());
    let found = match refs::item_for(c, provider, Kind::Track, &t.ext_id)? {
        Some(id) => Some(id),
        None => match &isrc {
            Some(isrc) => c
                .query_row(
                    "SELECT COALESCE(i.merged_into, i.id) FROM music_tracks t JOIN items i ON i.id = t.item_id
                     WHERE t.isrc = ?1 ORDER BY i.id LIMIT 1",
                    [isrc],
                    |r| r.get(0),
                )
                .optional()?,
            None => None,
        },
    };
    let id = ensure(tx, Kind::Track, provider, &t.ext_id, &t.title, found)?;
    let album = match &t.album {
        Some((ext, title)) => {
            let key = ext.clone().unwrap_or_else(|| name_key(title));
            let found = refs::item_for(c, provider, Kind::Album, &key)?;
            let album = ensure(tx, Kind::Album, provider, &key, title, found)?;
            c.execute(
                "INSERT OR IGNORE INTO music_albums (item_id) VALUES (?1)",
                [album],
            )?;
            index(tx, album)?;
            Some(album)
        }
        None => None,
    };
    c.execute(
        "INSERT INTO music_tracks (item_id, album_id, duration_ms, isrc, explicit) VALUES (?1, ?2, ?3, ?4, ?5)
         ON CONFLICT (item_id) DO UPDATE SET album_id = COALESCE(excluded.album_id, album_id),
           duration_ms = COALESCE(excluded.duration_ms, duration_ms),
           isrc = COALESCE(excluded.isrc, isrc), explicit = excluded.explicit",
        params![id, album, t.duration_ms, isrc, t.explicit],
    )?;
    set_artists(tx, ARTISTS_OF_TRACK, id, provider, &t.artists)?;
    set_artwork(tx, id, provider, &t.artwork)?;
    index(tx, id)?;
    Ok(id)
}

pub fn upsert_album(tx: &Tx, provider: &str, a: &AlbumData) -> rusqlite::Result<ItemId> {
    let found = refs::item_for(&tx.tx, provider, Kind::Album, &a.ext_id)?;
    let id = ensure(tx, Kind::Album, provider, &a.ext_id, &a.title, found)?;
    tx.tx.execute(
        "INSERT INTO music_albums (item_id, year, track_count) VALUES (?1, ?2, ?3)
         ON CONFLICT (item_id) DO UPDATE SET year = COALESCE(excluded.year, year),
           track_count = COALESCE(excluded.track_count, track_count)",
        params![id, a.year, a.track_count],
    )?;
    set_artists(tx, ARTISTS_OF_ALBUM, id, provider, &a.artists)?;
    set_artwork(tx, id, provider, &a.artwork)?;
    index(tx, id)?;
    Ok(id)
}

/// Without `ext_id` the artist is keyed `name:` + fold(name): same-name artists of one
/// provider are one item.
pub fn upsert_artist(tx: &Tx, provider: &str, a: &ArtistData) -> rusqlite::Result<ItemId> {
    if a.name.trim().is_empty() {
        return Err(invalid(format!("upsert_artist: blank name ({provider})")));
    }
    let key = a.ext_id.clone().unwrap_or_else(|| name_key(&a.name));
    let found = refs::item_for(&tx.tx, provider, Kind::Artist, &key)?;
    let id = ensure(tx, Kind::Artist, provider, &key, &a.name, found)?;
    tx.tx.execute(
        "INSERT OR IGNORE INTO music_artists (item_id) VALUES (?1)",
        [id],
    )?;
    set_artwork(tx, id, provider, &a.artwork)?;
    index(tx, id)?;
    Ok(id)
}

pub fn upsert_playlist(tx: &Tx, provider: &str, p: &PlaylistData) -> rusqlite::Result<ItemId> {
    let found = refs::item_for(&tx.tx, provider, Kind::Playlist, &p.ext_id)?;
    let id = ensure(tx, Kind::Playlist, provider, &p.ext_id, &p.title, found)?;
    tx.tx.execute(
        "INSERT INTO music_playlists (item_id, owner, description, track_count) VALUES (?1, ?2, ?3, ?4)
         ON CONFLICT (item_id) DO UPDATE SET owner = excluded.owner, description = excluded.description,
           track_count = COALESCE(excluded.track_count, track_count)",
        params![id, p.owner, p.description, p.track_count],
    )?;
    set_artwork(tx, id, provider, &p.artwork)?;
    index(tx, id)?;
    Ok(id)
}

/// Tracks of a provider album or playlist; `append` continues after the current last position.
pub fn set_children(
    tx: &Tx,
    parent: ItemId,
    tracks: &[ItemId],
    append: bool,
) -> rusqlite::Result<()> {
    let c = &tx.tx;
    let parent = canonical(c, parent)?;
    let Some((table, col)) = children_table(c, parent)? else {
        return Err(invalid(format!(
            "set_children: {parent} is not a provider album or playlist"
        )));
    };
    for &t in tracks {
        let kind: Option<String> = c
            .query_row("SELECT kind FROM items WHERE id = ?1", [t], |r| r.get(0))
            .optional()?;
        if kind.as_deref() != Some(Kind::Track.as_str()) {
            return Err(invalid(format!("set_children: {t} is not a track")));
        }
    }
    if !append {
        c.execute(&format!("DELETE FROM {table} WHERE {col} = ?1"), [parent])?;
    }
    let start: i64 = c.query_row(
        &format!("SELECT COALESCE(MAX(position) + 1, 0) FROM {table} WHERE {col} = ?1"),
        [parent],
        |r| r.get(0),
    )?;
    let mut st = c.prepare(&format!(
        "INSERT INTO {table} ({col}, track_id, position) VALUES (?1, ?2, ?3)"
    ))?;
    for (i, t) in tracks.iter().enumerate() {
        st.execute(params![parent, t, start + i as i64])?;
    }
    touch(tx, parent)
}

pub fn track(c: &Connection, id: ItemId) -> rusqlite::Result<Option<TrackRow>> {
    let id = canonical(c, id)?;
    let row = c
        .query_row(
            "SELECT i.title, ar.id, ar.title, t.duration_ms, t.isrc, t.explicit
             FROM items i JOIN music_tracks t ON t.item_id = i.id
             LEFT JOIN items a ON a.id = t.album_id
             LEFT JOIN items ar ON ar.id = COALESCE(a.merged_into, a.id)
             WHERE i.id = ?1",
            [id],
            |r| {
                let album: Option<ItemId> = r.get(1)?;
                Ok((
                    r.get::<_, String>(0)?,
                    album.map(|a| r.get(2).map(|t| (a, t))).transpose()?,
                    r.get(3)?,
                    r.get(4)?,
                    r.get(5)?,
                ))
            },
        )
        .optional()?;
    let Some((title, album, duration_ms, isrc, explicit)) = row else {
        return Ok(None);
    };
    Ok(Some(TrackRow {
        id,
        title,
        artists: artists(c, ARTISTS_OF_TRACK, id)?,
        album,
        duration_ms,
        isrc,
        explicit,
        artwork: artwork(c, id)?,
        liked: in_group(c, "likes WHERE deleted_at IS NULL", id)?,
        downloaded: in_group(c, "downloads WHERE state = 'done'", id)?,
    }))
}

/// Input order kept, unknown ids skipped.
// ponytail: one track() per id; batch with a temp table if long lists get slow
pub fn tracks(c: &Connection, ids: &[ItemId]) -> rusqlite::Result<Vec<TrackRow>> {
    ids.iter()
        .filter_map(|&id| track(c, id).transpose())
        .collect()
}

/// Album, artist or playlist.
pub fn collection(c: &Connection, id: ItemId) -> rusqlite::Result<Option<CollectionRow>> {
    let id = canonical(c, id)?;
    let Some((kind, title)) = c
        .query_row("SELECT kind, title FROM items WHERE id = ?1", [id], |r| {
            Ok((r.get::<_, String>(0)?, r.get(1)?))
        })
        .optional()?
    else {
        return Ok(None);
    };
    let (kind, subtitle, track_count) = match Kind::parse(&kind) {
        Some(Kind::Album) => {
            let names: Vec<String> = artists(c, ARTISTS_OF_ALBUM, id)?
                .into_iter()
                .map(|a| a.1)
                .collect();
            let count = c
                .query_row(
                    "SELECT track_count FROM music_albums WHERE item_id = ?1",
                    [id],
                    |r| r.get(0),
                )
                .optional()?
                .flatten();
            (
                Kind::Album,
                (!names.is_empty()).then(|| names.join(", ")),
                count,
            )
        }
        Some(Kind::Artist) => (Kind::Artist, None, None),
        Some(Kind::Playlist) => {
            let (owner, count) = c
                .query_row(
                    "SELECT owner, track_count FROM music_playlists WHERE item_id = ?1",
                    [id],
                    |r| Ok((r.get(0)?, r.get(1)?)),
                )
                .optional()?
                .unwrap_or((None, None));
            (Kind::Playlist, owner, count)
        }
        _ => return Ok(None),
    };
    Ok(Some(CollectionRow {
        id,
        kind,
        title,
        subtitle,
        artwork: artwork(c, id)?,
        track_count,
        liked: in_group(c, "likes WHERE deleted_at IS NULL", id)?,
    }))
}

/// Tracks of a provider album or playlist, as roots. Other items have none.
pub fn children(c: &Connection, parent: ItemId, page: Page) -> rusqlite::Result<Vec<ItemId>> {
    let parent = canonical(c, parent)?;
    let Some((table, col)) = children_table(c, parent)? else {
        return Ok(vec![]);
    };
    let mut st = c.prepare(&format!(
        "SELECT COALESCE(i.merged_into, i.id) FROM {table} x JOIN items i ON i.id = x.track_id
         WHERE x.{col} = ?1 ORDER BY x.position LIMIT ?2 OFFSET ?3"
    ))?;
    st.query_map(params![parent, page.limit, page.offset], |r| r.get(0))?
        .collect()
}

/// (link table, owner column)
const ARTISTS_OF_TRACK: (&str, &str) = ("music_track_artists", "track_id");
const ARTISTS_OF_ALBUM: (&str, &str) = ("music_album_artists", "album_id");

fn name_key(name: &str) -> String {
    let f = fold(name);
    format!("name:{}", if f.is_empty() { name.trim() } else { &f })
}

/// Finds or creates the item, sets title and stamp, records `(provider, key)`.
fn ensure(
    tx: &Tx,
    kind: Kind,
    provider: &str,
    key: &str,
    title: &str,
    found: Option<ItemId>,
) -> rusqlite::Result<ItemId> {
    let id = match found {
        Some(id) => {
            tx.tx.execute(
                "UPDATE items SET title = ?2, updated_at = ?3, device_id = ?4 WHERE id = ?1",
                params![
                    id,
                    title,
                    tx.stamp.updated_at,
                    tx.stamp.device_id.as_bytes().as_slice()
                ],
            )?;
            id
        }
        None => {
            let id = ItemId::new();
            tx.tx.execute(
                "INSERT INTO items (id, kind, title, updated_at, device_id) VALUES (?1, ?2, ?3, ?4, ?5)",
                params![
                    id,
                    kind.as_str(),
                    title,
                    tx.stamp.updated_at,
                    tx.stamp.device_id.as_bytes().as_slice()
                ],
            )?;
            id
        }
    };
    refs::record(tx, id, provider, key)?;
    Ok(id)
}

fn touch(tx: &Tx, id: ItemId) -> rusqlite::Result<()> {
    tx.tx.execute(
        "UPDATE items SET updated_at = ?2, device_id = ?3 WHERE id = ?1",
        params![
            id,
            tx.stamp.updated_at,
            tx.stamp.device_id.as_bytes().as_slice()
        ],
    )?;
    Ok(())
}

fn set_artists(
    tx: &Tx,
    (table, col): (&str, &str),
    owner: ItemId,
    provider: &str,
    list: &[ArtistData],
) -> rusqlite::Result<()> {
    let ids = list
        .iter()
        .filter(|a| !a.name.trim().is_empty())
        .map(|a| upsert_artist(tx, provider, a))
        .collect::<rusqlite::Result<Vec<_>>>()?;
    tx.tx
        .execute(&format!("DELETE FROM {table} WHERE {col} = ?1"), [owner])?;
    let mut st = tx.tx.prepare(&format!(
        "INSERT INTO {table} ({col}, artist_id, position) VALUES (?1, ?2, ?3)"
    ))?;
    for (i, a) in ids.iter().enumerate() {
        st.execute(params![owner, a, i as i64])?;
    }
    Ok(())
}

/// Replaces this provider's images; an empty list (provider sent none) keeps the old ones.
fn set_artwork(tx: &Tx, id: ItemId, provider: &str, images: &[Image]) -> rusqlite::Result<()> {
    if images.is_empty() {
        return Ok(());
    }
    tx.tx.execute(
        "DELETE FROM artwork WHERE item_id = ?1 AND provider = ?2",
        params![id, provider],
    )?;
    let mut st = tx.tx.prepare(
        "INSERT OR IGNORE INTO artwork (item_id, provider, url, width) VALUES (?1, ?2, ?3, ?4)",
    )?;
    for i in images {
        st.execute(params![id, provider, i.url, i.width])?;
    }
    Ok(())
}

/// One `library_fts` row per item: folded title; folded artists (+ album) or owner.
fn index(tx: &Tx, id: ItemId) -> rusqlite::Result<()> {
    let c = &tx.tx;
    let (kind, title): (String, String) =
        c.query_row("SELECT kind, title FROM items WHERE id = ?1", [id], |r| {
            Ok((r.get(0)?, r.get(1)?))
        })?;
    let mut parts: Vec<String> = Vec::new();
    match Kind::parse(&kind) {
        Some(Kind::Track) => {
            parts.extend(artists(c, ARTISTS_OF_TRACK, id)?.into_iter().map(|a| a.1));
            parts.extend(
                c.query_row(
                    "SELECT r.title FROM music_tracks t JOIN items a ON a.id = t.album_id
                     JOIN items r ON r.id = COALESCE(a.merged_into, a.id) WHERE t.item_id = ?1",
                    [id],
                    |r| r.get::<_, String>(0),
                )
                .optional()?,
            );
        }
        Some(Kind::Album) => {
            parts.extend(artists(c, ARTISTS_OF_ALBUM, id)?.into_iter().map(|a| a.1))
        }
        Some(Kind::Playlist) => parts.extend(
            c.query_row(
                "SELECT owner FROM music_playlists WHERE item_id = ?1",
                [id],
                |r| r.get::<_, Option<String>>(0),
            )
            .optional()?
            .flatten(),
        ),
        _ => {}
    }
    let rowid = fts_rowid(id);
    c.execute(
        "DELETE FROM library_fts WHERE rowid = ?1 AND item_id = ?2",
        params![rowid, id],
    )?;
    c.execute(
        "INSERT INTO library_fts (rowid, item_id, title, subtitle) VALUES (?1, ?2, ?3, ?4)",
        params![rowid, id, fold(&title), fold(&parts.join(" "))],
    )?;
    Ok(())
}

fn children_table(
    c: &Connection,
    parent: ItemId,
) -> rusqlite::Result<Option<(&'static str, &'static str)>> {
    // Provider collections only: user playlists (no `music_playlists` row) live in Task 4 tables.
    let (album, playlist): (bool, bool) = c.query_row(
        "SELECT EXISTS (SELECT 1 FROM music_albums WHERE item_id = ?1),
                EXISTS (SELECT 1 FROM music_playlists WHERE item_id = ?1)",
        [parent],
        |r| Ok((r.get(0)?, r.get(1)?)),
    )?;
    Ok(if album {
        Some(("music_album_tracks", "album_id"))
    } else if playlist {
        Some(("music_playlist_tracks", "playlist_id"))
    } else {
        None
    })
}

/// Root artists, in credit order.
fn artists(
    c: &Connection,
    (table, col): (&str, &str),
    owner: ItemId,
) -> rusqlite::Result<Vec<(ItemId, String)>> {
    let mut st = c.prepare(&format!(
        "SELECT r.id, r.title FROM {table} x JOIN items a ON a.id = x.artist_id
         JOIN items r ON r.id = COALESCE(a.merged_into, a.id)
         WHERE x.{col} = ?1 ORDER BY x.position"
    ))?;
    st.query_map([owner], |r| Ok((r.get(0)?, r.get(1)?)))?
        .collect()
}

fn artwork(c: &Connection, id: ItemId) -> rusqlite::Result<Vec<Image>> {
    let mut st = c.prepare("SELECT url, width FROM artwork WHERE item_id = ?1 ORDER BY rowid")?;
    st.query_map([id], |r| {
        Ok(Image {
            url: r.get(0)?,
            width: r.get(1)?,
        })
    })?
    .collect()
}

/// Whether `<table WHERE filter>` has a row for the root or any item merged into it: user
/// data is never rewritten on merge.
fn in_group(c: &Connection, table_where: &str, root: ItemId) -> rusqlite::Result<bool> {
    c.query_row(
        &format!(
            "SELECT EXISTS (SELECT 1 FROM {table_where} AND item_id IN
               (SELECT id FROM items WHERE id = ?1 OR merged_into = ?1))"
        ),
        [root],
        |r| r.get(0),
    )
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use crate::library::Db;

    pub(crate) fn track_data(ext: &str, isrc: Option<&str>) -> TrackData {
        TrackData {
            ext_id: ext.into(),
            title: format!("Track {ext}"),
            artists: vec![ArtistData {
                ext_id: None,
                name: "Artist".into(),
                artwork: vec![],
            }],
            album: None,
            duration_ms: Some(180_000),
            isrc: isrc.map(Into::into),
            explicit: false,
            artwork: vec![],
        }
    }

    fn img(url: &str, width: u32) -> Image {
        Image {
            url: url.into(),
            width: Some(width),
        }
    }

    fn count(c: &Connection, sql: &str) -> i64 {
        c.query_row(sql, [], |r| r.get(0)).unwrap()
    }

    #[test]
    fn upsert_is_idempotent() {
        let db = Db::open_in_memory().unwrap();
        db.write_blocking(|tx| {
            let c = &tx.tx;
            let a = upsert_track(tx, "deezer", &track_data("123", None))?;
            let mut t = track_data("123", None);
            t.title = "Renamed".into();
            let b = upsert_track(tx, "deezer", &t)?;
            assert_eq!(a, b);
            assert_eq!(
                count(c, "SELECT count(*) FROM items WHERE kind = 'track'"),
                1
            );
            assert_eq!(
                count(c, "SELECT count(*) FROM items WHERE kind = 'artist'"),
                1
            );
            assert_eq!(count(c, "SELECT count(*) FROM external_refs"), 2);
            assert_eq!(track(c, a)?.unwrap().title, "Renamed");
            // One search row per item, refreshed.
            assert_eq!(count(c, "SELECT count(*) FROM library_fts"), 2);
            let (title, subtitle): (String, String) = c.query_row(
                "SELECT title, subtitle FROM library_fts WHERE item_id = ?1",
                [a],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )?;
            assert_eq!((title.as_str(), subtitle.as_str()), ("renamed", "artist"));
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn same_isrc_reuses_item() {
        let db = Db::open_in_memory().unwrap();
        db.write_blocking(|tx| {
            let c = &tx.tx;
            let a = upsert_track(tx, "deezer", &track_data("1", Some("FRZ039800212")))?;
            let b = upsert_track(tx, "itunes", &track_data("9", Some("FRZ039800212")))?;
            assert_eq!(a, b);
            assert_eq!(
                count(c, "SELECT count(*) FROM items WHERE kind = 'track'"),
                1
            );
            assert_eq!(refs::get(c, a, "deezer")?.unwrap().external_id, "1");
            assert_eq!(refs::get(c, a, "itunes")?.unwrap().external_id, "9");
            assert_eq!(refs::all(c, a)?.len(), 2);
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn track_row_carries_artists_album_artwork() {
        let db = Db::open_in_memory().unwrap();
        let (device, stamp, id) = db
            .write_blocking(|tx| {
                let t = TrackData {
                    ext_id: "1".into(),
                    title: "Hymne à l'amour".into(),
                    artists: vec![
                        ArtistData {
                            ext_id: Some("a1".into()),
                            name: "Édith Piaf".into(),
                            artwork: vec![img("https://x/piaf.jpg", 500)],
                        },
                        ArtistData {
                            ext_id: None,
                            name: "Orchestre".into(),
                            artwork: vec![],
                        },
                    ],
                    album: Some((None, "Best Of".into())),
                    duration_ms: Some(200_000),
                    isrc: Some("FRZ039800212".into()),
                    explicit: true,
                    artwork: vec![img("https://x/s.jpg", 250), img("https://x/l.jpg", 1000)],
                };
                Ok((
                    tx.stamp.device_id,
                    tx.stamp.updated_at,
                    upsert_track(tx, "deezer", &t)?,
                ))
            })
            .unwrap();
        db.read_blocking(|c| {
            let row = track(c, id)?.unwrap();
            assert_eq!(row.title, "Hymne à l'amour");
            let names: Vec<&str> = row.artists.iter().map(|a| a.1.as_str()).collect();
            assert_eq!(names, ["Édith Piaf", "Orchestre"]);
            let album = row.album.clone().unwrap();
            assert_eq!(album.1, "Best Of");
            assert_eq!(
                refs::item_for(c, "deezer", Kind::Album, "name:best of")?,
                Some(album.0)
            );
            assert_eq!(
                refs::item_for(c, "deezer", Kind::Artist, "name:orchestre")?,
                Some(row.artists[1].0)
            );
            assert_eq!(
                refs::item_for(c, "deezer", Kind::Artist, "a1")?,
                Some(row.artists[0].0)
            );
            assert_eq!(row.duration_ms, Some(200_000));
            assert_eq!(row.isrc.as_deref(), Some("FRZ039800212"));
            assert!(row.explicit && !row.liked && !row.downloaded);
            assert_eq!(
                row.artwork,
                vec![img("https://x/s.jpg", 250), img("https://x/l.jpg", 1000)]
            );
            let artist = collection(c, row.artists[0].0)?.unwrap();
            assert_eq!(artist.kind, Kind::Artist);
            assert_eq!(artist.artwork, vec![img("https://x/piaf.jpg", 500)]);
            let subtitle: String = c.query_row(
                "SELECT subtitle FROM library_fts WHERE item_id = ?1",
                [id],
                |r| r.get(0),
            )?;
            assert_eq!(subtitle, fold("Édith Piaf Orchestre Best Of"));
            // Every catalogue write carries the transaction stamp.
            let (u, d): (i64, Vec<u8>) = c.query_row(
                "SELECT updated_at, device_id FROM items WHERE id = ?1",
                [id],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )?;
            assert_eq!((u, d.as_slice()), (stamp, device.as_bytes().as_slice()));
            assert_eq!(tracks(c, &[ItemId::new(), id])?.len(), 1);
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn same_name_artists_merge_only_within_provider() {
        let db = Db::open_in_memory().unwrap();
        db.write_blocking(|tx| {
            let a = upsert_track(tx, "deezer", &track_data("1", None))?;
            let b = upsert_track(tx, "deezer", &track_data("2", None))?;
            let c2 = upsert_track(tx, "itunes", &track_data("3", None))?;
            let artist = |id| track(&tx.tx, id).map(|r| r.unwrap().artists[0].0);
            assert_eq!(artist(a)?, artist(b)?);
            assert_ne!(artist(a)?, artist(c2)?);
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn collections_and_children() {
        let db = Db::open_in_memory().unwrap();
        db.write_blocking(|tx| {
            let c = &tx.tx;
            let album = upsert_album(
                tx,
                "deezer",
                &AlbumData {
                    ext_id: "al".into(),
                    title: "Album".into(),
                    artists: vec![ArtistData {
                        ext_id: None,
                        name: "Artist".into(),
                        artwork: vec![],
                    }],
                    year: Some(1999),
                    track_count: Some(3),
                    artwork: vec![img("https://x/a.jpg", 600)],
                },
            )?;
            let pl = upsert_playlist(
                tx,
                "deezer",
                &PlaylistData {
                    ext_id: "pl".into(),
                    title: "Hits".into(),
                    owner: Some("Deezer".into()),
                    description: None,
                    track_count: Some(50),
                    artwork: vec![],
                },
            )?;
            let ids: Vec<ItemId> = (0..3)
                .map(|i| upsert_track(tx, "deezer", &track_data(&i.to_string(), None)))
                .collect::<Result<_, _>>()?;
            let all = || Page {
                offset: 0,
                limit: 10,
            };
            set_children(tx, album, &ids[..2], false)?;
            set_children(tx, album, &ids[2..], true)?;
            assert_eq!(children(c, album, all())?, ids);
            assert_eq!(
                children(
                    c,
                    album,
                    Page {
                        offset: 1,
                        limit: 1
                    }
                )?,
                ids[1..2]
            );
            set_children(tx, album, &[ids[2]], false)?;
            assert_eq!(children(c, album, all())?, [ids[2]]);
            set_children(tx, pl, &ids, false)?;
            assert_eq!(children(c, pl, all())?, ids);
            // A merged child resolves to its root.
            crate::library::items::merge(tx, ids[0], ids[1])?;
            assert_eq!(children(c, pl, all())?, [ids[0], ids[0], ids[2]]);

            let a = collection(c, album)?.unwrap();
            assert_eq!(
                (
                    a.kind,
                    a.title.as_str(),
                    a.subtitle.as_deref(),
                    a.track_count
                ),
                (Kind::Album, "Album", Some("Artist"), Some(3))
            );
            assert_eq!(a.artwork, vec![img("https://x/a.jpg", 600)]);
            let p = collection(c, pl)?.unwrap();
            assert_eq!(
                (p.kind, p.subtitle.as_deref(), p.track_count, p.liked),
                (Kind::Playlist, Some("Deezer"), Some(50), false)
            );
            assert_eq!(collection(c, ids[2])?, None);
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn isrc_is_normalised() {
        let db = Db::open_in_memory().unwrap();
        db.write_blocking(|tx| {
            let a = upsert_track(tx, "deezer", &track_data("1", Some(" frz039800212 ")))?;
            let b = upsert_track(tx, "itunes", &track_data("9", Some("FRZ039800212")))?;
            assert_eq!(a, b);
            assert_eq!(
                track(&tx.tx, a)?.unwrap().isrc.as_deref(),
                Some("FRZ039800212")
            );
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn blank_artists_are_skipped() {
        let db = Db::open_in_memory().unwrap();
        db.write_blocking(|tx| {
            let mut t = track_data("1", None);
            t.artists.insert(
                0,
                ArtistData {
                    ext_id: None,
                    name: "  ".into(),
                    artwork: vec![],
                },
            );
            let id = upsert_track(tx, "deezer", &t)?;
            let names: Vec<String> = track(&tx.tx, id)?
                .unwrap()
                .artists
                .into_iter()
                .map(|a| a.1)
                .collect();
            assert_eq!(names, ["Artist"]);
            let blank = ArtistData {
                ext_id: Some("x".into()),
                name: " ".into(),
                artwork: vec![],
            };
            assert!(upsert_artist(tx, "deezer", &blank).is_err());
            assert_eq!(
                count(&tx.tx, "SELECT count(*) FROM items WHERE kind = 'artist'"),
                1
            );
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn set_children_rejects_bad_parent_or_child() {
        let db = Db::open_in_memory().unwrap();
        db.write_blocking(|tx| {
            let c = &tx.tx;
            let t = upsert_track(tx, "deezer", &track_data("1", None))?;
            let artist = track(c, t)?.unwrap().artists[0].0;
            let album = upsert_album(
                tx,
                "deezer",
                &AlbumData {
                    ext_id: "al".into(),
                    title: "Album".into(),
                    artists: vec![],
                    year: None,
                    track_count: None,
                    artwork: vec![],
                },
            )?;
            // A user playlist: kind playlist, no music_playlists row.
            let user = ItemId::new();
            c.execute(
                "INSERT INTO items (id, kind, title, updated_at, device_id) VALUES (?1, 'playlist', 'mine', 0, x'00')",
                [user],
            )?;
            assert!(set_children(tx, user, &[t], false).is_err());
            assert!(set_children(tx, t, &[t], false).is_err());
            assert!(set_children(tx, album, &[artist], false).is_err());
            assert!(set_children(tx, album, &[ItemId::new()], false).is_err());
            assert_eq!(children(c, user, Page { offset: 0, limit: 10 })?, []);
            set_children(tx, album, &[t], false)?;
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn fts_rowid_collision_fails_loudly() {
        let db = Db::open_in_memory().unwrap();
        db.write_blocking(|tx| {
            let t = upsert_track(tx, "deezer", &track_data("1", None))?;
            // Simulate another item owning this item's search rowid.
            tx.tx.execute(
                "UPDATE library_fts SET item_id = ?2 WHERE rowid = ?1",
                params![fts_rowid(t), ItemId::new()],
            )?;
            assert!(upsert_track(tx, "deezer", &track_data("1", None)).is_err());
            Ok(())
        })
        .unwrap();
    }
}
