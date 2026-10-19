//! Generic SQLite store: items of every kind, user data, caches. Schema in `migrations/`.

mod db;
mod hlc;
mod ids;
mod order;

pub use db::{Db, DbError, Tx};
pub use hlc::{Hlc, Stamp};
pub use ids::{ItemId, Kind};
pub use order::key_between;

pub struct Page {
    pub offset: u32,
    pub limit: u32,
}
