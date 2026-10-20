//! Per-plugin key/value store. Limits are enforced by plugin-host, not here.

use rusqlite::{Connection, OptionalExtension, params};

use super::Tx;

pub fn get(c: &Connection, plugin: &str, key: &str) -> rusqlite::Result<Option<Vec<u8>>> {
    c.query_row(
        "SELECT value FROM plugin_kv WHERE plugin_id = ?1 AND key = ?2",
        [plugin, key],
        |r| r.get(0),
    )
    .optional()
}

pub fn set(tx: &Tx, plugin: &str, key: &str, value: &[u8]) -> rusqlite::Result<()> {
    tx.tx.execute(
        "INSERT INTO plugin_kv (plugin_id, key, value) VALUES (?1, ?2, ?3)
         ON CONFLICT (plugin_id, key) DO UPDATE SET value = excluded.value",
        params![plugin, key, value],
    )?;
    Ok(())
}

pub fn delete(tx: &Tx, plugin: &str, key: &str) -> rusqlite::Result<()> {
    tx.tx.execute(
        "DELETE FROM plugin_kv WHERE plugin_id = ?1 AND key = ?2",
        [plugin, key],
    )?;
    Ok(())
}

/// Bytes of all keys (UTF-8) and values of `plugin`, as plugin-host's `Storage::kv_usage`.
pub fn usage(c: &Connection, plugin: &str) -> rusqlite::Result<u64> {
    c.query_row(
        "SELECT COALESCE(sum(octet_length(key) + length(value)), 0) FROM plugin_kv WHERE plugin_id = ?1",
        [plugin],
        // A sum of lengths is never negative.
        |r| r.get::<_, i64>(0).map(|n| n as u64),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::library::Db;

    #[test]
    fn kv_usage_counts_keys_and_values() {
        let db = Db::open_in_memory().unwrap();
        db.write_blocking(|tx| {
            set(tx, "p", "a", &[1, 2, 3])?;
            set(tx, "p", "bé", &[0; 10])?;
            set(tx, "q", "x", &[0; 100])
        })
        .unwrap();
        let usage_p = |db: &Db| db.read_blocking(|c| usage(c, "p")).unwrap();
        // "bé" is 3 bytes in UTF-8.
        assert_eq!(usage_p(&db), (1 + 3) + (3 + 10));
        assert_eq!(db.read_blocking(|c| usage(c, "none")).unwrap(), 0);
        assert_eq!(
            db.read_blocking(|c| get(c, "p", "a")).unwrap(),
            Some(vec![1, 2, 3])
        );

        db.write_blocking(|tx| set(tx, "p", "a", &[9])).unwrap();
        assert_eq!(usage_p(&db), (1 + 1) + (3 + 10));
        db.write_blocking(|tx| delete(tx, "p", "bé")).unwrap();
        assert_eq!(usage_p(&db), 2);
        assert_eq!(db.read_blocking(|c| get(c, "p", "bé")).unwrap(), None);
        assert_eq!(db.read_blocking(|c| usage(c, "q")).unwrap(), 101);
    }
}
