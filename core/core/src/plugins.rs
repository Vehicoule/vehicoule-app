//! Installed plugins and their feeds: the only module that loads plugins.

use std::path::{Path, PathBuf};
use std::sync::{Arc, PoisonError, RwLock};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use base64::Engine;
use base64::engine::general_purpose::STANDARD;
use plugin_host::{
    CallError, FeedEntry, FeedError, Host, HostConfig, HostEvent, Limits, LogLevel, Manifest,
    NetPolicy, Plugin, fingerprint, parse_manifest, sha256_matches, verify_feed,
};
use reqwest::Url;

use crate::app::AppConfig;
use crate::error::CoreError;
use crate::keys::{OFFICIAL_FEED_URL, OFFICIAL_KEYS};
use crate::library::Db;
use crate::library::plugins::{self as rows, FeedRow, PluginRow};
use crate::logs;
use crate::router::cap_name;
use crate::storage::DbStorage;

const MAX_FEED_BYTES: usize = 1 << 20;
const MAX_MANIFEST_BYTES: usize = 64 << 10;
const MAX_WASM_BYTES: usize = 32 << 20;

pub(crate) struct Plugins {
    /// Shared with `spawn_blocking` for the synchronous compilation in `Host::load`.
    host: Arc<Host>,
    /// Enabled plugins only.
    loaded: RwLock<Vec<Plugin>>,
    /// `<data_dir>/plugins`: the installed `.wasm`, read at startup without network.
    dir: PathBuf,
    /// Feeds, manifests and `.wasm`.
    http: reqwest::Client,
}

#[derive(Debug, Clone, PartialEq)]
pub struct FeedPreview {
    pub name: String,
    pub fingerprint: String,
    pub plugins: Vec<PluginPreview>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct PluginPreview {
    pub id: String,
    pub version: String,
    pub domains: Vec<String>,
    pub capabilities: Vec<String>,
}

impl Plugins {
    pub fn new(cfg: &AppConfig, db: &Db, net: NetPolicy) -> anyhow::Result<Plugins> {
        let host = Host::new(HostConfig {
            cache_dir: Path::new(&cfg.cache_dir).join("plugins"),
            storage: Arc::new(DbStorage(db.clone())),
            events: Arc::new(on_event),
            limits: Limits::default(),
            app_version: cfg.app_version.clone(),
            net,
        })?;
        let dir = Path::new(&cfg.data_dir).join("plugins");
        std::fs::create_dir_all(&dir)?;
        // ponytail: plain http only in debug builds (local test feeds); the signature and the sha256s guard integrity either way
        let http = reqwest::Client::builder()
            .https_only(!cfg!(debug_assertions))
            .timeout(Duration::from_secs(60))
            .build()?;
        Ok(Plugins {
            host: Arc::new(host),
            loaded: RwLock::new(Vec::new()),
            dir,
            http,
        })
    }

    pub fn host(&self) -> &Host {
        &self.host
    }

    /// Enabled plugins, in no particular order (see `router::ordered`).
    pub(crate) fn loaded(&self) -> Vec<Plugin> {
        self.loaded
            .read()
            .unwrap_or_else(PoisonError::into_inner)
            .clone()
    }

    #[cfg(test)]
    pub(crate) fn replace_loaded(&self, plugins: Vec<Plugin>) {
        *self.loaded.write().unwrap_or_else(PoisonError::into_inner) = plugins;
    }

    /// Replaces (or with `None` removes) plugin `id` in `loaded`.
    fn set_loaded(&self, id: &str, plugin: Option<Plugin>) {
        let mut loaded = self.loaded.write().unwrap_or_else(PoisonError::into_inner);
        loaded.retain(|p| p.id() != id);
        loaded.extend(plugin);
    }

    fn is_loaded(&self, id: &str) -> bool {
        self.loaded().iter().any(|p| p.id() == id)
    }

    fn wasm_path(&self, id: &str, sha256: &str) -> PathBuf {
        let sha = sha256.to_ascii_lowercase();
        let short = sha.get(..8).unwrap_or(&sha);
        self.dir.join(format!("{id}-{short}.wasm"))
    }

    /// At startup: every enabled plugin from its installed file, no network. A plugin that
    /// fails is logged and left out (the next refresh reinstalls it).
    pub async fn load_installed(&self, db: &Db) -> Result<(), CoreError> {
        let mut loaded = Vec::new();
        for row in db.read(rows::plugins).await? {
            if !row.enabled {
                continue;
            }
            let (host, path) = (self.host.clone(), self.wasm_path(&row.id, &row.wasm_sha256));
            let (manifest, sha) = (row.manifest, row.wasm_sha256);
            let plugin = blocking(move || {
                let wasm = std::fs::read(&path).map_err(|e| e.to_string())?;
                if !sha256_matches(&wasm, &sha) {
                    return Err("installed wasm sha256 mismatch".into());
                }
                host.load(&manifest, &wasm).map_err(|e| format!("{e:?}"))
            })
            .await;
            match plugin {
                Ok(p) => loaded.push(p),
                Err(e) => logs::push("error", &row.id, &e),
            }
        }
        *self.loaded.write().unwrap_or_else(PoisonError::into_inner) = loaded;
        Ok(())
    }

    /// Every feed in turn; a feed or plugin that fails is logged and the rest goes on.
    /// Returns the ids installed or updated.
    // ponytail: two concurrent refreshes may both install the same plugin (same bytes, atomic writes); add a lock if it shows in logs
    pub async fn refresh_feeds(&self, db: &Db) -> Result<Vec<String>, CoreError> {
        let mut installed = Vec::new();
        for feed in db.read(rows::feeds).await? {
            // Logged by name: a URL would be masked to `<url>`.
            let (url, name) = (feed.url.clone(), feed.name.clone());
            let bytes = match parse_url(&url) {
                Ok(u) => self.get(&u, MAX_FEED_BYTES).await,
                Err(e) => Err(e),
            };
            let applied = match bytes {
                Ok(bytes) => self.apply_feed(db, feed, bytes).await,
                Err(e) => Err(format!("{e:?}")),
            };
            match applied {
                Ok(ids) => installed.extend(ids),
                Err(e) => logs::push("error", "feeds", &format!("{name}: {e}")),
            }
        }
        Ok(installed)
    }

    /// Verifies `bytes` against the feed's keys and last sequence, stores it, then installs
    /// what is new or changed and disables what left the feed.
    async fn apply_feed(
        &self,
        db: &Db,
        mut row: FeedRow,
        bytes: Vec<u8>,
    ) -> Result<Vec<String>, String> {
        let feed = verify_feed(&bytes, &row.public_keys, row.last_sequence)
            .map_err(|e| format!("{e:?}"))?;
        let base = parse_url(&row.url).map_err(|e| format!("{e:?}"))?;
        let official = row.official;
        row.name = sanitize(&feed.name);
        row.last_sequence = Some(feed.sequence);
        row.fetched_at = Some(now_ms());
        row.feed = Some(bytes);
        let feed_url = row.url.clone();
        db.write(move |tx| rows::put_feed(tx, &row))
            .await
            .map_err(|e| e.to_string())?;

        let installed = db.read(rows::plugins).await.map_err(|e| e.to_string())?;
        let mut ids = Vec::new();
        for entry in feed.plugins.iter().filter(|e| e.contract.starts_with("1.")) {
            let current = installed.iter().find(|r| r.id == entry.id);
            // An id belongs to the official feed first, else to the feed where it is enabled.
            if let Some(r) = current
                && r.feed_url != feed_url
            {
                if official {
                    logs::push(
                        "warn",
                        &entry.id,
                        "the official feed replaces the plugin of another feed",
                    );
                } else if r.enabled {
                    logs::push("error", &entry.id, "refused: enabled in another feed");
                    continue;
                }
            }
            let up_to_date = current.is_some_and(|r| {
                r.feed_url == feed_url
                    && r.enabled
                    && r.version == entry.version
                    && r.wasm_sha256.eq_ignore_ascii_case(&entry.wasm_sha256)
            }) && self.is_loaded(&entry.id);
            if up_to_date {
                continue;
            }
            match self.install(db, &base, &feed_url, entry, current).await {
                Ok(()) => ids.push(entry.id.clone()),
                Err(e) => logs::push("error", &entry.id, &e),
            }
        }

        // Left the feed: disabled, not removed.
        let gone = installed.into_iter().filter(|r| {
            r.feed_url == feed_url && r.enabled && !feed.plugins.iter().any(|e| e.id == r.id)
        });
        for mut r in gone {
            self.set_loaded(&r.id, None);
            r.enabled = false;
            let id = r.id.clone();
            if let Err(e) = db.write(move |tx| rows::put_plugin(tx, &r)).await {
                logs::push("error", &id, &e.to_string());
            }
        }
        Ok(ids)
    }

    async fn install(
        &self,
        db: &Db,
        base: &Url,
        feed_url: &str,
        entry: &FeedEntry,
        old: Option<&PluginRow>,
    ) -> Result<(), String> {
        let (manifest, _, wasm) = self.fetch_entry(base, entry).await?;
        let path = self.wasm_path(&entry.id, &entry.wasm_sha256);
        let (host, m) = (self.host.clone(), manifest.clone());
        let plugin = blocking(move || {
            let plugin = host.load(&m, &wasm).map_err(|e| format!("{e:?}"))?;
            write_atomic(&path, &wasm).map_err(|e| e.to_string())?;
            Ok(plugin)
        })
        .await?;
        let row = PluginRow {
            id: entry.id.clone(),
            feed_url: feed_url.into(),
            version: entry.version.clone(),
            manifest,
            wasm_sha256: entry.wasm_sha256.to_ascii_lowercase(),
            enabled: true,
        };
        db.write(move |tx| rows::put_plugin(tx, &row))
            .await
            .map_err(|e| e.to_string())?;
        self.set_loaded(&entry.id, Some(plugin));
        if let Some(old) = old {
            let old_path = self.wasm_path(&old.id, &old.wasm_sha256);
            if old_path != self.wasm_path(&entry.id, &entry.wasm_sha256) {
                let _ = std::fs::remove_file(old_path);
            }
        }
        Ok(())
    }

    /// Manifest (raw and parsed) and `.wasm`, each checked against the entry's sha256; the
    /// manifest's id must be the entry's.
    async fn fetch_entry(
        &self,
        base: &Url,
        entry: &FeedEntry,
    ) -> Result<(Vec<u8>, Manifest, Vec<u8>), String> {
        let join = |u: &str| base.join(u).map_err(|e| e.to_string());
        let fetched = |e: CoreError| format!("{e:?}");
        let manifest = self
            .get(&join(&entry.manifest_url)?, MAX_MANIFEST_BYTES)
            .await
            .map_err(fetched)?;
        if !sha256_matches(&manifest, &entry.manifest_sha256) {
            return Err("manifest sha256 mismatch".into());
        }
        let parsed = parse_manifest(&manifest)?;
        if parsed.id != entry.id {
            return Err(format!("manifest id {:?} is not the feed's", parsed.id));
        }
        let wasm = self
            .get(&join(&entry.wasm_url)?, MAX_WASM_BYTES)
            .await
            .map_err(fetched)?;
        if !sha256_matches(&wasm, &entry.wasm_sha256) {
            return Err("wasm sha256 mismatch".into());
        }
        Ok((manifest, parsed, wasm))
    }

    /// Downloads, verifies and compiles every plugin of the feed, installs nothing. An entry
    /// that fails is logged and left out.
    pub async fn preview_feed(
        &self,
        url: &str,
        public_key_b64: &str,
    ) -> Result<FeedPreview, CoreError> {
        let key = decode_key(public_key_b64)?;
        let base = parse_url(url)?;
        let bytes = self.get(&base, MAX_FEED_BYTES).await?;
        let feed = verify_feed(&bytes, &[key], None).map_err(feed_error)?;
        let mut plugins = Vec::new();
        for entry in feed.plugins.iter().filter(|e| e.contract.starts_with("1.")) {
            match self.preview_entry(&base, entry).await {
                Ok(p) => plugins.push(p),
                Err(e) => logs::push("error", &entry.id, &e),
            }
        }
        Ok(FeedPreview {
            name: sanitize(&feed.name),
            fingerprint: fingerprint(&key),
            plugins,
        })
    }

    async fn preview_entry(&self, base: &Url, entry: &FeedEntry) -> Result<PluginPreview, String> {
        let (manifest, parsed, wasm) = self.fetch_entry(base, entry).await?;
        let host = self.host.clone();
        let plugin =
            blocking(move || host.load(&manifest, &wasm).map_err(|e| format!("{e:?}"))).await?;
        Ok(PluginPreview {
            id: entry.id.clone(),
            version: entry.version.clone(),
            domains: parsed.domains,
            capabilities: plugin
                .capabilities()
                .iter()
                .map(|c| cap_name(*c).to_string())
                .collect(),
        })
    }

    /// Verifies the feed with `public_key_b64`, stores it, installs its plugins (failures are
    /// logged).
    pub async fn add_feed(
        &self,
        db: &Db,
        url: &str,
        public_key_b64: &str,
    ) -> Result<(), CoreError> {
        if url == OFFICIAL_FEED_URL {
            return Err(CoreError::InvalidFeed);
        }
        let key = decode_key(public_key_b64)?;
        let bytes = self.get(&parse_url(url)?, MAX_FEED_BYTES).await?;
        // Re-adding with the same key keeps the rollback protection.
        let kept = db
            .read(rows::feeds)
            .await?
            .into_iter()
            .find(|f| f.url == url && f.public_keys == [key])
            .and_then(|f| f.last_sequence);
        let feed = verify_feed(&bytes, &[key], kept).map_err(feed_error)?;
        let name = sanitize(&feed.name);
        let row = FeedRow {
            url: url.into(),
            name: name.clone(),
            public_keys: vec![key],
            official: false,
            last_sequence: kept,
            fetched_at: None,
            feed: None,
        };
        let stored = row.clone();
        db.write(move |tx| rows::put_feed(tx, &stored)).await?;
        if let Err(e) = self.apply_feed(db, row, bytes).await {
            logs::push("error", "feeds", &format!("{name}: {e}"));
        }
        Ok(())
    }

    /// GET with a size cap (over it: `InvalidFeed`); 404/410 → `NotFound`, any other
    /// failure → `Network`.
    async fn get(&self, url: &Url, max: usize) -> Result<Vec<u8>, CoreError> {
        let network = |e: reqwest::Error| {
            logs::push("warn", "feeds", &e.to_string());
            CoreError::Network
        };
        let mut resp = self.http.get(url.clone()).send().await.map_err(network)?;
        match resp.status().as_u16() {
            200..=299 => {}
            404 | 410 => return Err(CoreError::NotFound),
            _ => return Err(CoreError::Network),
        }
        let mut body = Vec::new();
        while let Some(chunk) = resp.chunk().await.map_err(network)? {
            if body.len() + chunk.len() > max {
                return Err(CoreError::InvalidFeed);
            }
            body.extend_from_slice(&chunk);
        }
        Ok(body)
    }
}

/// The official feed's row, with the keys this build trusts (a new app version may rotate
/// them); its last sequence and contents are kept.
pub(crate) fn seed_official(db: &Db) -> Result<(), CoreError> {
    db.write_blocking(|tx| {
        let existing = rows::feeds(&tx.tx)?
            .into_iter()
            .find(|f| f.url == OFFICIAL_FEED_URL);
        let row = FeedRow {
            public_keys: OFFICIAL_KEYS.to_vec(),
            official: true,
            ..existing.unwrap_or(FeedRow {
                url: OFFICIAL_FEED_URL.into(),
                name: "Vehicoule".into(),
                public_keys: Vec::new(),
                official: true,
                last_sequence: None,
                fetched_at: None,
                feed: None,
            })
        };
        rows::put_feed(tx, &row)
    })?;
    Ok(())
}

/// Plugin logs and call reports go to the diagnostics log, source = plugin id. Call reports
/// are what the fuel calibration reads (plan 6).
fn on_event(e: HostEvent) {
    match e {
        HostEvent::Log {
            plugin,
            level,
            message,
        } => {
            let level = match level {
                LogLevel::Debug => "debug",
                LogLevel::Info => "info",
                LogLevel::Warn => "warn",
                LogLevel::Error => "error",
            };
            logs::push(level, &plugin, &message);
        }
        HostEvent::Call(r) => {
            let outcome = match &r.outcome {
                Ok(()) => "ok".to_string(),
                Err(e) => error_name(e),
            };
            let line = format!(
                "call {} fuel={} http={} wall={} {outcome}",
                cap_name(r.capability),
                r.fuel_used,
                r.http_calls,
                r.wall_ms
            );
            // Ids, numbers and fixed names only: masking would hide fuel counts over 6 digits.
            logs::push_unmasked("info", &r.plugin, &line);
            crate::telemetry::on_call(&r);
        }
    }
}

/// Never the error's message: it may carry a title or a URL.
fn error_name(e: &CallError) -> String {
    match e {
        CallError::Network(_) => "network".into(),
        CallError::ProviderWall(_) => "provider-wall".into(),
        CallError::RateLimited => "rate-limited".into(),
        CallError::NotFound => "not-found".into(),
        CallError::Expired => "expired".into(),
        CallError::Internal(_) => "internal".into(),
        CallError::Unsupported => "unsupported".into(),
        CallError::BudgetExceeded(b) => format!("budget-exceeded-{b:?}").to_ascii_lowercase(),
    }
}

/// Shown to the user: no control or bidi-override characters, trimmed, 64 chars at most.
fn sanitize(name: &str) -> String {
    let clean: String = name
        .chars()
        .filter(|c| {
            !c.is_control() && !matches!(c, '\u{202a}'..='\u{202e}' | '\u{2066}'..='\u{2069}')
        })
        .collect();
    let capped: String = clean.trim().chars().take(64).collect();
    capped.trim_end().into()
}

fn decode_key(b64: &str) -> Result<[u8; 32], CoreError> {
    STANDARD
        .decode(b64.trim())
        .ok()
        .and_then(|k| <[u8; 32]>::try_from(k).ok())
        .ok_or(CoreError::InvalidFeed)
}

fn parse_url(url: &str) -> Result<Url, CoreError> {
    Url::parse(url).map_err(|_| CoreError::InvalidFeed)
}

fn feed_error(e: FeedError) -> CoreError {
    logs::push("warn", "feeds", &format!("{e:?}"));
    CoreError::InvalidFeed
}

pub(crate) fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_millis() as i64)
}

async fn blocking<R: Send + 'static>(
    f: impl FnOnce() -> Result<R, String> + Send + 'static,
) -> Result<R, String> {
    tokio::task::spawn_blocking(f)
        .await
        .map_err(|e| e.to_string())?
}

/// Whole file or nothing: written next to `path`, synced, then renamed over it.
fn write_atomic(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    use std::io::Write;
    let tmp = path.with_extension("wasm.tmp");
    let mut f = std::fs::File::create(&tmp)?;
    f.write_all(bytes)?;
    f.sync_all()?;
    std::fs::rename(&tmp, path)
}

#[cfg(test)]
mod tests;
