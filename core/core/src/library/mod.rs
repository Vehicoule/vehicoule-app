//! Generic SQLite store: items of every kind, user data, caches. Schema in `migrations/`.

pub mod catalog;
mod db;
pub mod downloads;
mod fold;
mod hlc;
mod ids;
pub mod items;
pub mod likes;
mod order;
pub mod playlists;
pub mod plays;
pub mod queue;
pub mod refs;
pub mod search;

pub use db::{Db, DbError, Tx};
pub use fold::fold;
pub use hlc::{Hlc, Stamp};
pub use ids::{ItemId, Kind};
pub use order::{is_valid_key, key_between};

pub struct Page {
    pub offset: u32,
    pub limit: u32,
}
