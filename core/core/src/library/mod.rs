//! Generic SQLite store: items of every kind, user data, caches. Schema in `migrations/`.

pub mod catalog;
mod db;
pub mod downloads;
mod fold;
mod hlc;
pub mod http_cache;
mod ids;
pub mod items;
pub mod kv;
pub mod likes;
pub mod lyrics;
mod order;
pub mod playlists;
pub mod plays;
pub mod plugins;
pub mod queue;
pub mod refs;
pub mod search;
pub mod settings;

pub use db::{Db, DbError, Tx};
pub use fold::fold;
pub use hlc::{Hlc, Stamp};
pub use ids::{ItemId, Kind};
pub use order::{is_valid_key, key_between};

pub struct Page {
    pub offset: u32,
    pub limit: u32,
}

/// Liked or downloaded tracks: date added (newest first), or folded title / first artist A→Z.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TrackSort {
    Added,
    Title,
    Artist,
}

/// Albums, artists, playlists: date liked or created (newest first), latest play of one of
/// their tracks, or folded title A→Z. (`Title`, not `Name`: Dart enums already have `.name`.)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CollectionSort {
    Recent,
    Played,
    Title,
}

/// Track ids of the collection `r` (root), whatever its kind: album, artist, provider or
/// user playlist.
const MEMBERS: &str = "SELECT track_id FROM music_album_tracks WHERE album_id = r.id
     UNION SELECT item_id FROM music_tracks WHERE album_id = r.id
     UNION SELECT track_id FROM music_track_artists WHERE artist_id = r.id
     UNION SELECT track_id FROM music_playlist_tracks WHERE playlist_id = r.id
     UNION SELECT item_id FROM playlist_items WHERE playlist_id = r.id AND deleted_at IS NULL";

/// The `WITH` clause to start the query with, and the `ORDER BY` terms, for collections whose
/// root is `r`; `recent` is the date liked or created. `Played` reads `last(root, at)`: the
/// latest counted play of every root track, computed once per query.
pub(crate) fn collection_order(sort: CollectionSort, recent: &str) -> (String, String) {
    match sort {
        CollectionSort::Recent => (String::new(), format!("{recent} DESC, r.id DESC")),
        CollectionSort::Played => (
            format!(
                "WITH last(root, at) AS MATERIALIZED (
                   SELECT COALESCE(i.merged_into, i.id), max(p.started_at)
                   FROM plays p JOIN items i ON i.id = p.item_id
                   WHERE p.deleted_at IS NULL AND p.listened_ms >= {}
                   GROUP BY 1)",
                plays::COUNTED_MS
            ),
            format!(
                "(SELECT max(last.at) FROM items t JOIN last ON last.root = COALESCE(t.merged_into, t.id)
                  WHERE t.id IN ({MEMBERS})) DESC, {recent} DESC, r.id DESC"
            ),
        ),
        CollectionSort::Title => (String::new(), "fold(r.title), r.id".into()),
    }
}

/// `ORDER BY` terms for tracks whose root is `r`; `added` is the date liked or downloaded.
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
