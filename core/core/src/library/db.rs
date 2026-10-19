use std::path::Path;
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use rusqlite::{Connection, OptionalExtension, Transaction};

use super::hlc::{Hlc, Stamp};

/// Index i holds the migration to `user_version` i + 1.
const MIGRATIONS: &[&str] = &[include_str!("../../migrations/0001_init.sql")];

#[derive(Debug, Clone, PartialEq)]
pub enum DbError {
    Sqlite(String),
    Migration(String),
}

impl From<rusqlite::Error> for DbError {
    fn from(e: rusqlite::Error) -> Self {
        DbError::Sqlite(e.to_string())
    }
}

/// A write transaction; every row it touches carries `stamp`.
pub struct Tx<'a> {
    pub tx: Transaction<'a>,
    pub stamp: Stamp,
}

// ponytail: one connection behind a mutex; add a read connection if UI reads stall behind writes
#[derive(Clone)]
pub struct Db {
    inner: Arc<Mutex<Inner>>,
    device_id: uuid::Uuid,
}

struct Inner {
    conn: Connection,
    hlc: Hlc,
    now: fn() -> u64,
}

fn wall_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_millis() as u64)
}

impl Db {
    pub fn open(path: &Path) -> Result<Db, DbError> {
        Db::init(Connection::open(path)?, wall_ms)
    }

    pub fn open_in_memory() -> Result<Db, DbError> {
        Db::init(Connection::open_in_memory()?, wall_ms)
    }

    fn init(mut conn: Connection, now: fn() -> u64) -> Result<Db, DbError> {
        conn.busy_timeout(Duration::from_millis(5000))?;
        // Checked before any pragma that writes the file: a newer database stays untouched.
        let version: u32 = conn.pragma_query_value(None, "user_version", |r| r.get(0))?;
        if version as usize > MIGRATIONS.len() {
            return Err(DbError::Migration(
                "database from a newer app version".into(),
            ));
        }
        conn.execute_batch(
            "PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON; PRAGMA synchronous = NORMAL;",
        )?;
        for (i, sql) in MIGRATIONS.iter().enumerate().skip(version as usize) {
            let tx = conn.transaction()?;
            tx.execute_batch(sql)
                .map_err(|e| DbError::Migration(format!("{:04}: {e}", i + 1)))?;
            tx.pragma_update(None, "user_version", i as u32 + 1)?;
            tx.commit()?;
        }

        let tx = conn.transaction()?;
        tx.execute(
            "INSERT OR IGNORE INTO settings_device (key, value) VALUES ('device_id', ?1)",
            [uuid::Uuid::now_v7().hyphenated().to_string()],
        )?;
        let get = |key: &str| {
            tx.query_row(
                "SELECT value FROM settings_device WHERE key = ?1",
                [key],
                |r| r.get::<_, String>(0),
            )
            .optional()
        };
        let bad = |key: &str| DbError::Sqlite(format!("invalid settings_device.{key}"));
        let device_id = get("device_id")?
            .and_then(|s| s.parse().ok())
            .ok_or_else(|| bad("device_id"))?;
        let hlc_last = match get("hlc_last")? {
            Some(s) => s.parse().map_err(|_| bad("hlc_last"))?,
            None => 0,
        };
        tx.commit()?;

        let inner = Inner {
            conn,
            hlc: Hlc::starting_at(hlc_last),
            now,
        };
        Ok(Db {
            inner: Arc::new(Mutex::new(inner)),
            device_id,
        })
    }

    pub fn device_id(&self) -> uuid::Uuid {
        self.device_id
    }

    pub async fn read<R: Send + 'static>(
        &self,
        f: impl FnOnce(&Connection) -> rusqlite::Result<R> + Send + 'static,
    ) -> Result<R, DbError> {
        let db = self.clone();
        blocking(move || db.read_blocking(f)).await
    }

    pub async fn write<R: Send + 'static>(
        &self,
        f: impl FnOnce(&Tx) -> rusqlite::Result<R> + Send + 'static,
    ) -> Result<R, DbError> {
        let db = self.clone();
        blocking(move || db.write_blocking(f)).await
    }

    /// For short calls from sync code (plugin-host `Storage`).
    pub fn read_blocking<R>(
        &self,
        f: impl FnOnce(&Connection) -> rusqlite::Result<R>,
    ) -> Result<R, DbError> {
        Ok(f(&self.lock().conn)?)
    }

    /// One HLC tick per transaction, persisted with it; `f` failing rolls everything back.
    pub fn write_blocking<R>(
        &self,
        f: impl FnOnce(&Tx) -> rusqlite::Result<R>,
    ) -> Result<R, DbError> {
        let mut guard = self.lock();
        let Inner { conn, hlc, now } = &mut *guard;
        let tx = conn.transaction()?;
        let stamp = Stamp {
            updated_at: hlc.tick(now()) as i64,
            device_id: self.device_id,
        };
        tx.execute(
            "INSERT INTO settings_device (key, value) VALUES ('hlc_last', ?1)
             ON CONFLICT (key) DO UPDATE SET value = excluded.value",
            [stamp.updated_at.to_string()],
        )?;
        let tx = Tx { tx, stamp };
        let r = f(&tx)?;
        tx.tx.commit()?;
        Ok(r)
    }

    /// A panic while holding the lock leaves the connection valid: recover it.
    fn lock(&self) -> MutexGuard<'_, Inner> {
        self.inner.lock().unwrap_or_else(PoisonError::into_inner)
    }
}

async fn blocking<R: Send + 'static>(
    f: impl FnOnce() -> Result<R, DbError> + Send + 'static,
) -> Result<R, DbError> {
    match tokio::task::spawn_blocking(f).await {
        Ok(r) => r,
        Err(e) => match e.try_into_panic() {
            Ok(p) => std::panic::resume_unwind(p),
            Err(e) => Err(DbError::Sqlite(e.to_string())),
        },
    }
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use super::*;
    use crate::library::ItemId;

    /// Temp db path; removes the db and its WAL files on drop.
    struct TempDb(PathBuf);

    impl TempDb {
        fn new() -> TempDb {
            TempDb(std::env::temp_dir().join(format!("vehicoule-test-{}.db", ItemId::new())))
        }
    }

    impl Drop for TempDb {
        fn drop(&mut self) {
            for ext in ["", "-wal", "-shm"] {
                let _ = std::fs::remove_file(format!("{}{ext}", self.0.display()));
            }
        }
    }

    fn user_version(db: &Db) -> i64 {
        db.read_blocking(|c| c.pragma_query_value(None, "user_version", |r| r.get(0)))
            .unwrap()
    }

    #[test]
    fn migrations_apply_once() {
        let p = TempDb::new();
        assert_eq!(user_version(&Db::open(&p.0).unwrap()), 1);
        let db = Db::open(&p.0).unwrap();
        assert_eq!(user_version(&db), 1);
        let fts: i64 = db
            .read_blocking(|c| c.query_row("SELECT count(*) FROM library_fts", [], |r| r.get(0)))
            .unwrap();
        assert_eq!(fts, 0);
    }

    #[test]
    fn newer_database_is_refused() {
        let p = TempDb::new();
        Connection::open(&p.0)
            .unwrap()
            .pragma_update(None, "user_version", 99)
            .unwrap();
        let err = Db::open(&p.0).err().unwrap();
        assert_eq!(
            err,
            DbError::Migration("database from a newer app version".into())
        );
        let raw = Connection::open(&p.0).unwrap();
        let v: i64 = raw
            .pragma_query_value(None, "user_version", |r| r.get(0))
            .unwrap();
        let mode: String = raw
            .pragma_query_value(None, "journal_mode", |r| r.get(0))
            .unwrap();
        assert_eq!(v, 99);
        assert_eq!(mode, "delete");
    }

    #[test]
    fn pragmas_are_set() {
        let p = TempDb::new();
        let db = Db::open(&p.0).unwrap();
        let (mode, fk, sync, busy) = db
            .read_blocking(|c| {
                let q = |name| {
                    c.pragma_query_value(None, name, |r| r.get::<_, rusqlite::types::Value>(0))
                };
                Ok((
                    q("journal_mode")?,
                    q("foreign_keys")?,
                    q("synchronous")?,
                    q("busy_timeout")?,
                ))
            })
            .unwrap();
        use rusqlite::types::Value::{Integer, Text};
        assert_eq!(mode, Text("wal".into()));
        assert_eq!(fk, Integer(1));
        assert_eq!(sync, Integer(1));
        assert_eq!(busy, Integer(5000));
    }

    #[test]
    fn device_id_is_stable() {
        let p = TempDb::new();
        let a = Db::open(&p.0).unwrap().device_id();
        let b = Db::open(&p.0).unwrap().device_id();
        assert_eq!(a, b);
        assert_eq!(a.get_version_num(), 7);
    }

    #[tokio::test]
    async fn hlc_survives_restart() {
        let p = TempDb::new();
        let stamp = |db: Db| async move { db.write(|tx| Ok(tx.stamp.updated_at)).await.unwrap() };
        let first = stamp(Db::init(Connection::open(&p.0).unwrap(), || 5000).unwrap()).await;
        // Wall clock went back 4 s across the restart.
        let second = stamp(Db::init(Connection::open(&p.0).unwrap(), || 1000).unwrap()).await;
        assert!(second > first);
    }

    #[test]
    fn one_stamp_per_transaction_and_rollback_on_error() {
        let db = Db::open_in_memory().unwrap();
        let (a, b) = db
            .write_blocking(|tx| Ok((tx.stamp.updated_at, tx.stamp.updated_at)))
            .unwrap();
        assert_eq!(a, b);
        let id = ItemId::new();
        let err = db.write_blocking(|tx| {
            tx.tx.execute(
                "INSERT INTO items (id, kind, title, updated_at, device_id) VALUES (?1, 'track', 't', ?2, ?3)",
                rusqlite::params![id, tx.stamp.updated_at, tx.stamp.device_id.as_bytes().as_slice()],
            )?;
            Err::<(), _>(rusqlite::Error::QueryReturnedNoRows)
        });
        assert!(err.is_err());
        let n: i64 = db
            .read_blocking(|c| c.query_row("SELECT count(*) FROM items", [], |r| r.get(0)))
            .unwrap();
        assert_eq!(n, 0);
    }
}
