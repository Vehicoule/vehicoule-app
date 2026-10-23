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
