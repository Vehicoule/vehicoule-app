//! Installed plugin feeds and plugins, and the per-capability plugin order.

use base64::Engine;
use base64::engine::general_purpose::STANDARD;
use rusqlite::{Connection, Row, params};

use super::Tx;
use super::items::invalid;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FeedRow {
    pub url: String,
    pub name: String,
    /// Ed25519 keys, stored as a JSON array of base64 strings.
    pub public_keys: Vec<[u8; 32]>,
    pub official: bool,
    pub last_sequence: Option<u64>,
    pub fetched_at: Option<i64>,
    pub feed: Option<Vec<u8>>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PluginRow {
    pub id: String,
    pub feed_url: String,
    pub version: String,
    pub manifest: Vec<u8>,
    pub wasm_sha256: String,
    pub enabled: bool,
}

/// Sorted by url.
pub fn feeds(c: &Connection) -> rusqlite::Result<Vec<FeedRow>> {
    let mut st = c.prepare(
        "SELECT url, name, public_keys, official, last_sequence, fetched_at, feed FROM feeds ORDER BY url",
    )?;
    st.query_map([], feed_row)?.collect()
}

fn feed_row(r: &Row) -> rusqlite::Result<FeedRow> {
    let bad = |e: String| invalid(format!("feeds.public_keys: {e}"));
    let keys: Vec<String> =
        serde_json::from_str(&r.get::<_, String>(2)?).map_err(|e| bad(e.to_string()))?;
    let public_keys = keys
        .iter()
        .map(|k| {
            let bytes = STANDARD.decode(k).map_err(|e| bad(e.to_string()))?;
            <[u8; 32]>::try_from(bytes).map_err(|b| bad(format!("{} bytes, expected 32", b.len())))
        })
        .collect::<rusqlite::Result<_>>()?;
    Ok(FeedRow {
        url: r.get(0)?,
        name: r.get(1)?,
        public_keys,
        official: r.get(3)?,
        last_sequence: r
            .get::<_, Option<i64>>(4)?
            .map(|n| u64::try_from(n).map_err(|e| invalid(format!("feeds.last_sequence: {e}"))))
            .transpose()?,
        fetched_at: r.get(5)?,
        feed: r.get(6)?,
    })
}

/// Upserts in place (the feed's plugins stay).
pub fn put_feed(tx: &Tx, f: &FeedRow) -> rusqlite::Result<()> {
    let keys: Vec<String> = f.public_keys.iter().map(|k| STANDARD.encode(k)).collect();
    let keys =
        serde_json::to_string(&keys).map_err(|e| invalid(format!("feeds.public_keys: {e}")))?;
    // SQLite integers are i64: a sequence past i64::MAX is refused, never wrapped.
    let last_sequence = f
        .last_sequence
        .map(|n| i64::try_from(n).map_err(|e| invalid(format!("feeds.last_sequence: {e}"))))
        .transpose()?;
    tx.tx.execute(
        "INSERT INTO feeds (url, name, public_keys, official, last_sequence, fetched_at, feed)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
         ON CONFLICT (url) DO UPDATE SET name = excluded.name, public_keys = excluded.public_keys,
           official = excluded.official, last_sequence = excluded.last_sequence,
           fetched_at = excluded.fetched_at, feed = excluded.feed",
        params![
            f.url,
            f.name,
            keys,
            f.official,
            last_sequence,
            f.fetched_at,
            f.feed
        ],
    )?;
    Ok(())
}

/// Uninstalls the feed's plugins with everything keyed by their id: capability order
/// entries, kv data and cached HTTP responses.
pub fn remove_feed(tx: &Tx, url: &str) -> rusqlite::Result<()> {
    for table in ["capability_order", "plugin_kv", "http_cache"] {
        tx.tx.execute(
            &format!("DELETE FROM {table} WHERE plugin_id IN (SELECT id FROM plugins WHERE feed_url = ?1)"),
            [url],
        )?;
    }
    tx.tx
        .execute("DELETE FROM plugins WHERE feed_url = ?1", [url])?;
    tx.tx.execute("DELETE FROM feeds WHERE url = ?1", [url])?;
    Ok(())
}

/// Sorted by id.
pub fn plugins(c: &Connection) -> rusqlite::Result<Vec<PluginRow>> {
    let mut st = c.prepare(
        "SELECT id, feed_url, version, manifest, wasm_sha256, enabled FROM plugins ORDER BY id",
    )?;
    st.query_map([], |r| {
        Ok(PluginRow {
            id: r.get(0)?,
            feed_url: r.get(1)?,
            version: r.get(2)?,
            manifest: r.get(3)?,
            wasm_sha256: r.get(4)?,
            enabled: r.get(5)?,
        })
    })?
    .collect()
}

/// Upserts; `installed_at` is set on first install only. The feed must exist.
pub fn put_plugin(tx: &Tx, p: &PluginRow) -> rusqlite::Result<()> {
    tx.tx.execute(
        "INSERT INTO plugins (id, feed_url, version, manifest, wasm_sha256, enabled, installed_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
         ON CONFLICT (id) DO UPDATE SET feed_url = excluded.feed_url, version = excluded.version,
           manifest = excluded.manifest, wasm_sha256 = excluded.wasm_sha256, enabled = excluded.enabled",
        params![p.id, p.feed_url, p.version, p.manifest, p.wasm_sha256, p.enabled, tx.now_ms],
    )?;
    Ok(())
}

pub fn capability_order(c: &Connection, capability: &str) -> rusqlite::Result<Vec<String>> {
    let mut st = c.prepare(
        "SELECT plugin_id FROM capability_order WHERE capability = ?1 ORDER BY position",
    )?;
    st.query_map([capability], |r| r.get(0))?.collect()
}

/// Replaces the whole order; a duplicate id fails (primary key).
pub fn set_capability_order(
    tx: &Tx,
    capability: &str,
    plugin_ids: &[String],
) -> rusqlite::Result<()> {
    tx.tx.execute(
        "DELETE FROM capability_order WHERE capability = ?1",
        [capability],
    )?;
    let mut st = tx.tx.prepare(
        "INSERT INTO capability_order (capability, plugin_id, position) VALUES (?1, ?2, ?3)",
    )?;
    for (i, id) in plugin_ids.iter().enumerate() {
        st.execute(params![capability, id, i as i64])?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::library::{Db, http_cache, kv};

    fn feed(url: &str, keys: Vec<[u8; 32]>) -> FeedRow {
        FeedRow {
            url: url.into(),
            name: format!("feed {url}"),
            public_keys: keys,
            official: url == "https://a",
            last_sequence: Some(u64::MAX >> 1),
            fetched_at: Some(1_700_000_000_000),
            feed: Some(vec![1, 2, 3]),
        }
    }

    fn plugin(id: &str, feed_url: &str) -> PluginRow {
        PluginRow {
            id: id.into(),
            feed_url: feed_url.into(),
            version: "1.0.0".into(),
            manifest: id.as_bytes().to_vec(),
            wasm_sha256: "ab".repeat(32),
            enabled: true,
        }
    }

    fn ids(v: &[PluginRow]) -> Vec<&str> {
        v.iter().map(|p| p.id.as_str()).collect()
    }

    #[test]
    fn removing_a_feed_removes_its_plugins() {
        let db = Db::open_in_memory().unwrap();
        let (a, b) = (
            feed("https://a", vec![[1; 32], [2; 32]]),
            feed("https://b", vec![]),
        );
        let (a2, b2) = (a.clone(), b.clone());
        db.write_blocking(move |tx| {
            put_feed(tx, &b2)?;
            put_feed(tx, &a2)?;
            put_plugin(tx, &plugin("p1", "https://a"))?;
            put_plugin(tx, &plugin("p2", "https://a"))?;
            put_plugin(tx, &plugin("q1", "https://b"))?;
            set_capability_order(tx, "lyrics", &["p1".into(), "q1".into()])?;
            kv::set(tx, "p1", "token", b"t")?;
            kv::set(tx, "q1", "token", b"t")?;
            http_cache::put(
                tx,
                &[1; 32],
                &http_cache::CacheRow {
                    plugin: "p2".into(),
                    status: 200,
                    url: "https://x".into(),
                    headers: vec![],
                    body: vec![],
                    stored_at: 0,
                    expires_at: i64::MAX,
                },
            )
        })
        .unwrap();
        assert_eq!(db.read_blocking(feeds).unwrap(), vec![a.clone(), b.clone()]);
        // Re-putting a feed that has plugins updates it in place.
        let mut a3 = a.clone();
        a3.last_sequence = Some(8);
        let a4 = a3.clone();
        db.write_blocking(move |tx| put_feed(tx, &a4)).unwrap();
        assert_eq!(db.read_blocking(feeds).unwrap(), vec![a3, b.clone()]);

        db.write_blocking(|tx| remove_feed(tx, "https://a"))
            .unwrap();
        let (fs, ps, order, kv_p1, kv_q1, cached) = db
            .read_blocking(|c| {
                Ok((
                    feeds(c)?,
                    plugins(c)?,
                    capability_order(c, "lyrics")?,
                    kv::get(c, "p1", "token")?,
                    kv::get(c, "q1", "token")?,
                    http_cache::get(c, &[1; 32])?,
                ))
            })
            .unwrap();
        assert_eq!(fs, vec![b]);
        assert_eq!(ids(&ps), vec!["q1"]);
        assert_eq!(order, vec!["q1".to_string()]);
        assert_eq!((kv_p1, kv_q1), (None, Some(b"t".to_vec())));
        assert_eq!(cached, None);
    }

    #[test]
    fn capability_order_roundtrip() {
        let db = Db::open_in_memory().unwrap();
        let order = |db: &Db, cap: &'static str| {
            db.read_blocking(move |c| capability_order(c, cap)).unwrap()
        };
        db.write_blocking(|tx| {
            put_feed(tx, &feed("https://a", vec![[7; 32]]))?;
            for id in ["a", "b", "c"] {
                put_plugin(tx, &plugin(id, "https://a"))?;
            }
            set_capability_order(tx, "search", &["b".into(), "c".into(), "a".into()])
        })
        .unwrap();
        assert_eq!(order(&db, "search"), vec!["b", "c", "a"]);
        assert!(order(&db, "lyrics").is_empty());
        db.write_blocking(|tx| set_capability_order(tx, "search", &["c".into()]))
            .unwrap();
        assert_eq!(order(&db, "search"), vec!["c"]);

        // put_plugin upserts.
        let mut b = plugin("b", "https://a");
        b.enabled = false;
        b.version = "2.0.0".into();
        let b2 = b.clone();
        db.write_blocking(move |tx| put_plugin(tx, &b2)).unwrap();
        let ps = db.read_blocking(plugins).unwrap();
        assert_eq!(ids(&ps), vec!["a", "b", "c"]);
        assert_eq!(ps[1], b);
    }
}
