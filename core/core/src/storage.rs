//! plugin-host's `Storage` on the library tables `plugin_kv` and `http_cache`.

use plugin_host::{CachedResponse, Storage};

use crate::library::{Db, DbError, http_cache, kv};
use crate::logs;

// ponytail: short blocking SQLite calls on a tokio worker; move to spawn_blocking if traces show stalls
pub(crate) struct DbStorage(pub Db);

/// `Storage` is infallible: a store error is logged and the call degrades.
fn logged<T>(r: Result<T, DbError>, fallback: T) -> T {
    r.unwrap_or_else(|e| {
        logs::push("error", "storage", &e.to_string());
        fallback
    })
}

impl Storage for DbStorage {
    fn kv_get(&self, plugin: &str, key: &str) -> Option<Vec<u8>> {
        logged(self.0.read_blocking(|c| kv::get(c, plugin, key)), None)
    }

    fn kv_set(&self, plugin: &str, key: &str, value: &[u8]) {
        logged(
            self.0.write_blocking(|tx| kv::set(tx, plugin, key, value)),
            (),
        )
    }

    fn kv_delete(&self, plugin: &str, key: &str) {
        logged(self.0.write_blocking(|tx| kv::delete(tx, plugin, key)), ())
    }

    /// On error, over any quota (the write is refused) yet far from `u64::MAX`: the host adds
    /// the new entry's size to it.
    fn kv_usage(&self, plugin: &str) -> u64 {
        logged(
            self.0.read_blocking(|c| kv::usage(c, plugin)),
            i64::MAX as u64,
        )
    }

    fn cache_get(&self, key: &[u8; 32]) -> Option<CachedResponse> {
        let row = logged(self.0.read_blocking(|c| http_cache::get(c, key)), None)?;
        // Stored from u64 values: never negative.
        Some(CachedResponse {
            plugin: row.plugin,
            status: row.status,
            url: row.url,
            headers: row.headers,
            body: row.body,
            stored_at_ms: row.stored_at.max(0) as u64,
            expires_at_ms: row.expires_at.max(0) as u64,
        })
    }

    fn cache_put(&self, key: &[u8; 32], entry: &CachedResponse) {
        // SQLite integers are i64; `expires_at_ms` may be u64::MAX ("never").
        let clamp = |ms: u64| i64::try_from(ms).unwrap_or(i64::MAX);
        let row = http_cache::CacheRow {
            plugin: entry.plugin.clone(),
            status: entry.status,
            url: entry.url.clone(),
            headers: entry.headers.clone(),
            body: entry.body.clone(),
            stored_at: clamp(entry.stored_at_ms),
            expires_at: clamp(entry.expires_at_ms),
        };
        logged(
            self.0.write_blocking(|tx| http_cache::put(tx, key, &row)),
            (),
        )
    }
}

#[cfg(test)]
mod tests {
    use plugin_host::{CachedResponse, Storage};

    use super::*;
    use crate::library::Db;

    #[test]
    fn db_storage_roundtrips_kv_and_cache() {
        let s = DbStorage(Db::open_in_memory().unwrap());
        assert_eq!(s.kv_get("p", "k"), None);
        s.kv_set("p", "k", &[1, 2, 3]);
        s.kv_set("q", "k", &[9; 10]);
        assert_eq!(s.kv_get("p", "k"), Some(vec![1, 2, 3]));
        assert_eq!(s.kv_usage("p"), 1 + 3);
        s.kv_delete("p", "k");
        assert_eq!(s.kv_get("p", "k"), None);
        assert_eq!(s.kv_usage("p"), 0);
        assert_eq!(s.kv_usage("q"), 11);

        assert!(s.cache_get(&[1; 32]).is_none());
        let entry = CachedResponse {
            plugin: "p".into(),
            status: 200,
            url: "https://x/y".into(),
            headers: vec![("etag".into(), "\"a\"".into())],
            body: b"hello".to_vec(),
            stored_at_ms: 1_700_000_000_000,
            expires_at_ms: u64::MAX,
        };
        s.cache_put(&[1; 32], &entry);
        let got = s.cache_get(&[1; 32]).unwrap();
        assert_eq!(
            (got.plugin, got.status, got.url, got.headers, got.body),
            (
                entry.plugin,
                entry.status,
                entry.url,
                entry.headers,
                entry.body
            )
        );
        assert_eq!(got.stored_at_ms, 1_700_000_000_000);
        // SQLite integers are i64: "never expires" comes back as i64::MAX, still never.
        assert_eq!(got.expires_at_ms, i64::MAX as u64);
    }
}
