use std::fmt;

use rusqlite::types::{FromSql, FromSqlError, FromSqlResult, ToSql, ToSqlOutput, ValueRef};

/// UUIDv7, stored as a 16-byte BLOB.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct ItemId(pub uuid::Uuid);

impl ItemId {
    pub fn new() -> ItemId {
        ItemId(uuid::Uuid::now_v7())
    }
}

impl Default for ItemId {
    fn default() -> Self {
        Self::new()
    }
}

impl fmt::Display for ItemId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.0.fmt(f)
    }
}

impl ToSql for ItemId {
    fn to_sql(&self) -> rusqlite::Result<ToSqlOutput<'_>> {
        Ok(ToSqlOutput::Borrowed(ValueRef::Blob(self.0.as_bytes())))
    }
}

impl FromSql for ItemId {
    fn column_result(value: ValueRef<'_>) -> FromSqlResult<Self> {
        let b = value.as_blob()?;
        uuid::Uuid::from_slice(b)
            .map(ItemId)
            .map_err(|_| FromSqlError::InvalidBlobSize {
                expected_size: 16,
                blob_size: b.len(),
            })
    }
}

/// No CHECK in SQL: new kinds (episode, chapter) need no migration; Rust is the gate.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Track,
    Album,
    Artist,
    Playlist,
}

impl Kind {
    pub fn as_str(self) -> &'static str {
        match self {
            Kind::Track => "track",
            Kind::Album => "album",
            Kind::Artist => "artist",
            Kind::Playlist => "playlist",
        }
    }

    pub fn parse(s: &str) -> Option<Kind> {
        match s {
            "track" => Some(Kind::Track),
            "album" => Some(Kind::Album),
            "artist" => Some(Kind::Artist),
            "playlist" => Some(Kind::Playlist),
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn item_ids_are_v7_and_time_ordered() {
        let a = ItemId::new();
        let b = ItemId::new();
        assert_eq!(a.0.get_version_num(), 7);
        assert!(b > a);
        assert_eq!(a.to_string().len(), 36);
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        let back: ItemId = conn.query_row("SELECT ?1", [a], |r| r.get(0)).unwrap();
        assert_eq!(back, a);
        let len: i64 = conn
            .query_row("SELECT length(?1)", [a], |r| r.get(0))
            .unwrap();
        assert_eq!(len, 16);
    }
}
