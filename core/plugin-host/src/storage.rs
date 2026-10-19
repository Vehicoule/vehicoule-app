//! Persistence the core provides (SQLite there). The host enforces the kv limits; the HTTP
//! cache (keyed by `cache::cache_key`, ttl from `cache::ttl_ms`) is just a blob store here.

use contract::kv::KvError;

pub trait Storage: Send + Sync {
    fn kv_get(&self, plugin: &str, key: &str) -> Option<Vec<u8>>;
    fn kv_set(&self, plugin: &str, key: &str, value: &[u8]);
    fn kv_delete(&self, plugin: &str, key: &str);
    /// Bytes of all keys and values of `plugin`.
    fn kv_usage(&self, plugin: &str) -> u64;
    fn cache_get(&self, key: &[u8; 32]) -> Option<CachedResponse>;
    fn cache_put(&self, key: &[u8; 32], entry: &CachedResponse);
}

/// A cached `GET` response, keyed by `cache::cache_key`. The host decides whether to store (2xx,
/// body size) and for how long (`cache::ttl_ms`); this struct is just what gets stored.
#[derive(Debug, Clone)]
pub struct CachedResponse {
    pub plugin: String,
    pub status: u16,
    /// Final URL (after any redirects the host followed).
    pub url: String,
    pub headers: Vec<(String, String)>,
    pub body: Vec<u8>,
    pub stored_at_ms: u64,
    pub expires_at_ms: u64,
}

const KV_MAX_KEY: usize = 128;
const KV_MAX_VALUE: usize = 64 << 10;
const KV_MAX_TOTAL: u64 = 1 << 20;

/// `kv.set` with the per-key, per-value and per-plugin caps.
// ponytail: check-then-set, two concurrent calls of one plugin can overshoot the total by one
// value; a transactional `Storage::kv_set_capped` if that ever matters.
pub(crate) fn kv_set(storage: &dyn Storage, plugin: &str, key: &str, value: &[u8]) -> Result<(), KvError> {
    if key.len() > KV_MAX_KEY || value.len() > KV_MAX_VALUE {
        return Err(KvError::TooLarge);
    }
    let old = storage.kv_get(plugin, key).map_or(0, |v| key.len() + v.len()) as u64;
    let total = storage.kv_usage(plugin).saturating_sub(old) + (key.len() + value.len()) as u64;
    if total > KV_MAX_TOTAL {
        return Err(KvError::QuotaExceeded);
    }
    storage.kv_set(plugin, key, value);
    Ok(())
}

#[cfg(any(test, feature = "test-util"))]
#[derive(Default)]
pub struct MemoryStorage {
    kv: std::sync::Mutex<std::collections::HashMap<(String, String), Vec<u8>>>,
    cache: std::sync::Mutex<std::collections::HashMap<[u8; 32], CachedResponse>>,
}

#[cfg(any(test, feature = "test-util"))]
impl Storage for MemoryStorage {
    fn kv_get(&self, plugin: &str, key: &str) -> Option<Vec<u8>> {
        self.kv.lock().unwrap().get(&(plugin.into(), key.into())).cloned()
    }

    fn kv_set(&self, plugin: &str, key: &str, value: &[u8]) {
        self.kv.lock().unwrap().insert((plugin.into(), key.into()), value.to_vec());
    }

    fn kv_delete(&self, plugin: &str, key: &str) {
        self.kv.lock().unwrap().remove(&(plugin.into(), key.into()));
    }

    fn kv_usage(&self, plugin: &str) -> u64 {
        let kv = self.kv.lock().unwrap();
        kv.iter().filter(|((p, _), _)| p == plugin).map(|((_, k), v)| (k.len() + v.len()) as u64).sum()
    }

    fn cache_get(&self, key: &[u8; 32]) -> Option<CachedResponse> {
        self.cache.lock().unwrap().get(key).cloned()
    }

    fn cache_put(&self, key: &[u8; 32], entry: &CachedResponse) {
        self.cache.lock().unwrap().insert(*key, entry.clone());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn kv_enforces_key_value_and_total_caps() {
        let s = MemoryStorage::default();
        let set = |key: &str, len: usize| kv_set(&s, "p", key, &vec![0; len]);
        assert!(matches!(set(&"k".repeat(129), 0), Err(KvError::TooLarge)));
        assert!(matches!(set("k", (64 << 10) + 1), Err(KvError::TooLarge)));

        // 15 entries of 1 + 64 KiB fit in 1 MiB; the 16th does not.
        for i in 0..15 {
            set(&format!("{i:x}"), 64 << 10).unwrap();
        }
        assert!(matches!(set("f", 64 << 10), Err(KvError::QuotaExceeded)));
        // Another plugin has its own quota.
        kv_set(&s, "q", "f", &vec![0; 64 << 10]).unwrap();
        // Overwriting frees the old value, deleting frees the entry.
        set("0", 64 << 10).unwrap();
        s.kv_delete("p", "0");
        set("f", 64 << 10).unwrap();
        assert_eq!(s.kv_get("p", "f").map(|v| v.len()), Some(64 << 10));
    }
}
