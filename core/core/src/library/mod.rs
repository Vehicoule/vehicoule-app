//! Generic SQLite store: items of every kind, user data, caches. Schema in `migrations/`.

mod db;
mod hlc;
mod ids;

pub use db::{Db, DbError, Tx};
pub use hlc::{Hlc, Stamp};
pub use ids::{ItemId, Kind};

pub struct Page {
    pub offset: u32,
    pub limit: u32,
}
