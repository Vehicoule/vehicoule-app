use std::fmt;
use std::path::Path;
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use rusqlite::functions::FunctionFlags;
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

impl fmt::Display for DbError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            DbError::Sqlite(s) => write!(f, "sqlite error: {s}"),
            DbError::Migration(s) => write!(f, "migration error: {s}"),
        }
    }
}

impl std::error::Error for DbError {}

/// A write transaction; every row it touches carries `stamp`.
pub struct Tx<'a> {
    pub tx: Transaction<'a>,
    pub stamp: Stamp,
    /// Wall clock (unix ms) read once for this transaction, the reading `stamp` was ticked
    /// from: for wall times (`liked_at`, `deleted_at`, ...), never for ordering.
    pub now_ms: i64,
}

// ponytail: one connection behind a mutex; add a read connection if UI reads stall behind writes
/// The lock is not re-entrant: never call `read_blocking`/`write_blocking` from inside a
/// `write_blocking` (or `read_blocking`) closure — it will deadlock.
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
        // Exposed to SQL for folded-prefix history lookups and short-query LIKE search.
        conn.create_scalar_function(
            "fold",
            1,
            FunctionFlags::SQLITE_UTF8 | FunctionFlags::SQLITE_DETERMINISTIC,
            |ctx| Ok(super::fold::fold(&ctx.get::<String>(0)?)),
        )?;
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

    /// For short calls from sync code (plugin-host `Storage`). Runs under `PRAGMA query_only
    /// = ON` so a closure that tries to write fails loudly instead of silently mutating the
    /// store; reset to OFF under the same lock before returning, even if `f` errors or panics.
    pub fn read_blocking<R>(
        &self,
        f: impl FnOnce(&Connection) -> rusqlite::Result<R>,
    ) -> Result<R, DbError> {
        let guard = self.lock();
        guard.conn.pragma_update(None, "query_only", true)?;
        let _reset = QueryOnlyReset(&guard.conn);
        Ok(f(&guard.conn)?)
    }

    /// One HLC tick per transaction, persisted with it; `f` failing rolls everything back.
    pub fn write_blocking<R>(
        &self,
        f: impl FnOnce(&Tx) -> rusqlite::Result<R>,
    ) -> Result<R, DbError> {
        let mut guard = self.lock();
        let Inner { conn, hlc, now } = &mut *guard;
        let tx = conn.transaction()?;
        let wall = now();
        let stamp = Stamp {
            updated_at: hlc.tick(wall) as i64,
            device_id: self.device_id,
        };
        tx.execute(
            "INSERT INTO settings_device (key, value) VALUES ('hlc_last', ?1)
             ON CONFLICT (key) DO UPDATE SET value = excluded.value",
            [stamp.updated_at.to_string()],
        )?;
        let tx = Tx {
            tx,
            stamp,
            now_ms: wall as i64,
        };
        let r = f(&tx)?;
        tx.tx.commit()?;
        Ok(r)
    }

    /// A panic while holding the lock leaves the connection valid: recover it. If the panic
    /// left an explicit transaction open (not in autocommit mode), roll it back first, so the
    /// connection is usable again.
    fn lock(&self) -> MutexGuard<'_, Inner> {
        match self.inner.lock() {
            Ok(guard) => guard,
            Err(poisoned) => {
                let guard = poisoned.into_inner();
                if !guard.conn.is_autocommit() {
                    let _ = guard.conn.execute_batch("ROLLBACK");
                }
                self.inner.clear_poison();
                guard
            }
        }
    }
}

/// Resets `PRAGMA query_only` to OFF when dropped, including on panic/error unwind. Also
/// rolls back a transaction the closure left open (e.g. a raw `BEGIN` followed by an `Err`
/// return) — that path never poisons the mutex, so `Db::lock`'s own recovery never runs.
struct QueryOnlyReset<'c>(&'c Connection);

impl Drop for QueryOnlyReset<'_> {
    fn drop(&mut self) {
        if !self.0.is_autocommit() {
            let _ = self.0.execute_batch("ROLLBACK");
        }
        let _ = self.0.pragma_update(None, "query_only", false);
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
    fn tx_carries_the_wall_clock_read_for_its_stamp() {
        let p = TempDb::new();
        let read = |now: fn() -> u64| {
            Db::init(Connection::open(&p.0).unwrap(), now)
                .unwrap()
                .write_blocking(|tx| Ok((tx.now_ms, tx.stamp.updated_at >> 16)))
                .unwrap()
        };
        assert_eq!(read(|| 5000), (5000, 5000));
        // Clock went back: the HLC stays ahead, the wall time does not.
        assert_eq!(read(|| 1000), (1000, 5000));
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

    #[test]
    fn reads_run_query_only_and_reset_afterwards() {
        let db = Db::open_in_memory().unwrap();
        let id = ItemId::new();
        // Capture the sqlite error *code* from inside the closure: `DbError::Sqlite` only
        // keeps the formatted message, so this is the only place the structured code survives.
        let code = db
            .read_blocking(|c| {
                let result = c.execute(
                    "INSERT INTO items (id, kind, title, updated_at, device_id) VALUES (?1, 'track', 't', 0, x'00')",
                    [id],
                );
                match result {
                    Err(rusqlite::Error::SqliteFailure(e, _)) => Ok(e.code),
                    Err(other) => panic!("expected a sqlite error, got {other:?}"),
                    Ok(_) => panic!("write inside read_blocking should fail under query_only"),
                }
            })
            .unwrap();
        assert_eq!(code, rusqlite::ErrorCode::ReadOnly);
        // query_only must be reset to OFF under the same lock, even though the closure errored.
        db.write_blocking(|tx| {
            tx.tx.execute(
                "INSERT INTO items (id, kind, title, updated_at, device_id) VALUES (?1, 'track', 't', ?2, ?3)",
                rusqlite::params![id, tx.stamp.updated_at, tx.stamp.device_id.as_bytes().as_slice()],
            )
        })
        .unwrap();
        let n: i64 = db
            .read_blocking(|c| c.query_row("SELECT count(*) FROM items", [], |r| r.get(0)))
            .unwrap();
        assert_eq!(n, 1);
    }

    #[test]
    fn poisoned_mutex_rolls_back_an_open_transaction() {
        let db = Db::open_in_memory().unwrap();
        let panicking = db.clone();
        // Leave an explicit BEGIN open, then panic while holding the lock: no `Transaction`
        // wrapper is involved, so nothing auto-rolls-back on unwind.
        let result = std::panic::catch_unwind(move || {
            panicking.read_blocking(|c| {
                c.execute_batch("BEGIN")?;
                panic!("simulated panic with an open transaction");
                #[allow(unreachable_code)]
                Ok(())
            })
        });
        assert!(result.is_err(), "the closure should have panicked");
        // Either the read-reset guard's own rollback (unwinding through it) or `Db::lock`'s
        // poison recovery must have rolled this back — one of the two always runs, in that
        // order — otherwise this would fail to open its own transaction ("cannot start a
        // transaction within a transaction").
        db.write_blocking(|_tx| Ok::<(), rusqlite::Error>(()))
            .unwrap();
    }

    #[test]
    fn read_closure_erroring_after_begin_rolls_back() {
        let db = Db::open_in_memory().unwrap();
        // No panic here, so the mutex is never poisoned: only the read-reset guard's own
        // rollback-if-open-transaction check (not `Db::lock`'s poison recovery) can save this.
        let err: Result<(), DbError> = db.read_blocking(|c| {
            c.execute_batch("BEGIN")?;
            Err(rusqlite::Error::QueryReturnedNoRows)
        });
        assert!(err.is_err());
        db.write_blocking(|_tx| Ok::<(), rusqlite::Error>(()))
            .unwrap();
    }

    #[test]
    fn db_error_is_displayable_and_std_error() {
        let e = DbError::Migration("database from a newer app version".into());
        assert_eq!(
            e.to_string(),
            "migration error: database from a newer app version"
        );
        let as_error: &dyn std::error::Error = &e;
        assert_eq!(as_error.to_string(), e.to_string());
    }
}
