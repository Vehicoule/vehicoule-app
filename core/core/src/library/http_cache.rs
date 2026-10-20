//! HTTP response cache for plugins, keyed by plugin-host's 32-byte `cache::cache_key`.
//! Capped at 64 MiB, pruned on every `put`; an entry's size is its body + url + headers JSON
//! bytes (row overhead and the key are not counted).

use rusqlite::{Connection, OptionalExtension, params};

use super::Tx;
use super::items::invalid;

const CAP_BYTES: i64 = 64 << 20;

/// `stored_at` / `expires_at` are unix ms. plugin-host's `expires_at_ms` is a `u64` that may
/// saturate to `u64::MAX`; callers clamp it to `i64::MAX` before storing.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CacheRow {
    pub plugin: String,
    pub status: u16,
    pub url: String,
    pub headers: Vec<(String, String)>,
    pub body: Vec<u8>,
    pub stored_at: i64,
    pub expires_at: i64,
}

/// Returns the row even when expired: freshness is the caller's call.
pub fn get(c: &Connection, key: &[u8; 32]) -> rusqlite::Result<Option<CacheRow>> {
    c.query_row(
        "SELECT plugin_id, status, url, headers, body, stored_at, expires_at FROM http_cache WHERE key = ?1",
        [key.as_slice()],
        |r| {
            let headers: String = r.get(3)?;
            Ok(CacheRow {
                plugin: r.get(0)?,
                status: r.get(1)?,
                url: r.get(2)?,
                headers: serde_json::from_str(&headers)
                    .map_err(|e| invalid(format!("http_cache.headers: {e}")))?,
                body: r.get(4)?,
                stored_at: r.get(5)?,
                expires_at: r.get(6)?,
            })
        },
    )
    .optional()
}

/// Upserts, then prunes back under 64 MiB: expired entries first (`expires_at <= now`), then
/// the oldest `stored_at`. The new entry is not spared.
// ponytail: full-table window scan per put; an index on (expires_at, stored_at) if it shows
pub fn put(tx: &Tx, key: &[u8; 32], row: &CacheRow) -> rusqlite::Result<()> {
    let headers = serde_json::to_string(&row.headers)
        .map_err(|e| invalid(format!("http_cache.headers: {e}")))?;
    tx.tx.execute(
        "INSERT INTO http_cache (key, plugin_id, status, url, headers, body, stored_at, expires_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
         ON CONFLICT (key) DO UPDATE SET plugin_id = excluded.plugin_id, status = excluded.status,
           url = excluded.url, headers = excluded.headers, body = excluded.body,
           stored_at = excluded.stored_at, expires_at = excluded.expires_at",
        params![
            key.as_slice(),
            row.plugin,
            row.status,
            row.url,
            headers,
            row.body,
            row.stored_at,
            row.expires_at
        ],
    )?;
    // Drop rows, in eviction order, while the bytes before them have not covered the excess.
    tx.tx.execute(
        "WITH s AS (SELECT key, length(body) + octet_length(headers) + octet_length(url) AS size,
                      expires_at > ?1 AS live, stored_at FROM http_cache),
              r AS (SELECT key, sum(size) OVER (ORDER BY live, stored_at, key) - size AS before FROM s)
         DELETE FROM http_cache WHERE key IN
           (SELECT key FROM r WHERE before < (SELECT sum(size) FROM s) - ?2)",
        params![tx.now_ms, CAP_BYTES],
    )?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::library::Db;

    #[test]
    fn http_cache_is_pruned_to_64_mib() {
        let db = Db::open_in_memory().unwrap();
        for i in 0..70u8 {
            let row = CacheRow {
                plugin: "p".into(),
                status: 200,
                url: format!("https://x/{i}"),
                headers: vec![("content-type".into(), "text/plain".into())],
                body: vec![i; 1 << 20],
                stored_at: i as i64,
                // The newest entry is already expired: it goes before any older live one.
                expires_at: if i == 69 { 0 } else { i64::MAX },
            };
            db.write_blocking(move |tx| put(tx, &[i; 32], &row))
                .unwrap();
        }
        let (total, kept, first, last) = db
            .read_blocking(|c| {
                let (total, kept): (i64, Vec<bool>) = (
                    c.query_row(
                        "SELECT sum(length(body) + octet_length(headers) + octet_length(url)) FROM http_cache",
                        [],
                        |r| r.get(0),
                    )?,
                    (0..70u8).map(|i| get(c, &[i; 32]).map(|r| r.is_some())).collect::<Result<_, _>>()?,
                );
                Ok((total, kept, get(c, &[6; 32])?, get(c, &[68; 32])?))
            })
            .unwrap();
        assert!(total <= CAP_BYTES, "{total}");
        // 63 entries of 1 MiB + overhead fit: 0..=5 (oldest) and 69 (expired) are gone.
        let expected: Vec<bool> = (0..70).map(|i| (6..=68).contains(&i)).collect();
        assert_eq!(kept, expected);
        let first = first.unwrap();
        assert_eq!(
            first.headers,
            vec![("content-type".into(), "text/plain".into())]
        );
        assert_eq!(
            (first.status, first.url.as_str(), first.body[0]),
            (200, "https://x/6", 6)
        );
        assert_eq!(last.unwrap().stored_at, 68);
    }
}
