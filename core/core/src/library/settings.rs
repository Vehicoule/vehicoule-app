//! `settings_device` stays on this device; `settings_shared` is synced (HLC columns).

use rusqlite::{Connection, OptionalExtension, params};

use super::Tx;
use super::items::invalid;

pub fn device_get(c: &Connection, key: &str) -> rusqlite::Result<Option<String>> {
    c.query_row(
        "SELECT value FROM settings_device WHERE key = ?1",
        [key],
        |r| r.get(0),
    )
    .optional()
}

/// `device_id` and `hlc_last` are reserved by `Db`: refused.
pub fn device_set(tx: &Tx, key: &str, value: &str) -> rusqlite::Result<()> {
    if matches!(key, "device_id" | "hlc_last") {
        return Err(invalid(format!("settings: {key} is reserved")));
    }
    tx.tx.execute(
        "INSERT INTO settings_device (key, value) VALUES (?1, ?2)
         ON CONFLICT (key) DO UPDATE SET value = excluded.value",
        [key, value],
    )?;
    Ok(())
}

/// `None` when missing or logically deleted.
pub fn shared_get(c: &Connection, key: &str) -> rusqlite::Result<Option<String>> {
    c.query_row(
        "SELECT value FROM settings_shared WHERE key = ?1 AND deleted_at IS NULL",
        [key],
        |r| r.get(0),
    )
    .optional()
}

/// Stamps the row and revives it if logically deleted.
pub fn shared_set(tx: &Tx, key: &str, value: &str) -> rusqlite::Result<()> {
    tx.tx.execute(
        "INSERT INTO settings_shared (key, value, updated_at, device_id) VALUES (?1, ?2, ?3, ?4)
         ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at,
           device_id = excluded.device_id, deleted_at = NULL",
        params![
            key,
            value,
            tx.stamp.updated_at,
            tx.stamp.device_id.as_bytes().as_slice()
        ],
    )?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::library::{Db, DbError};

    fn sync_cols(db: &Db, key: &'static str) -> (i64, Vec<u8>, Option<i64>) {
        db.read_blocking(move |c| {
            c.query_row(
                "SELECT updated_at, device_id, deleted_at FROM settings_shared WHERE key = ?1",
                [key],
                |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
            )
        })
        .unwrap()
    }

    #[test]
    fn device_set_rejects_reserved_keys() {
        let db = Db::open_in_memory().unwrap();
        let id = db.device_id().hyphenated().to_string();
        for key in ["device_id", "hlc_last"] {
            let err = db
                .write_blocking(|tx| device_set(tx, key, "0"))
                .unwrap_err();
            assert!(matches!(err, DbError::Invalid(_)), "{key}: {err:?}");
        }
        assert_eq!(
            db.read_blocking(|c| device_get(c, "device_id")).unwrap(),
            Some(id)
        );
    }

    #[test]
    fn shared_settings_carry_sync_columns() {
        let db = Db::open_in_memory().unwrap();
        let stamp = db
            .write_blocking(|tx| {
                device_set(tx, "volume", "0.8")?;
                shared_set(tx, "theme", "dark")?;
                Ok(tx.stamp.updated_at)
            })
            .unwrap();
        let (dev, shared, unknown) = db
            .read_blocking(|c| {
                Ok((
                    device_get(c, "volume")?,
                    shared_get(c, "theme")?,
                    shared_get(c, "x")?,
                ))
            })
            .unwrap();
        assert_eq!(
            (dev.as_deref(), shared.as_deref(), unknown),
            (Some("0.8"), Some("dark"), None)
        );
        assert_eq!(
            sync_cols(&db, "theme"),
            (stamp, db.device_id().as_bytes().to_vec(), None)
        );

        // A synced delete hides the value; setting it again revives it with a newer stamp.
        db.write_blocking(|tx| {
            tx.tx.execute(
                "UPDATE settings_shared SET deleted_at = 1 WHERE key = 'theme'",
                [],
            )
        })
        .unwrap();
        assert_eq!(db.read_blocking(|c| shared_get(c, "theme")).unwrap(), None);
        let stamp2 = db
            .write_blocking(|tx| shared_set(tx, "theme", "light").map(|_| tx.stamp.updated_at))
            .unwrap();
        assert!(stamp2 > stamp);
        assert_eq!(sync_cols(&db, "theme").2, None);
        assert_eq!(sync_cols(&db, "theme").0, stamp2);
        assert_eq!(
            db.read_blocking(|c| shared_get(c, "theme"))
                .unwrap()
                .as_deref(),
            Some("light")
        );
    }
}
