//! The global `App`, built once by `init`.

use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Mutex, OnceLock, PoisonError};

use vehicoule_stream::artwork::ArtworkCache;

use crate::error::CoreError;
use crate::events::Events;
use crate::library::Db;
use crate::plugins::{self, Plugins};

#[derive(Debug, Clone)]
pub struct AppConfig {
    pub data_dir: String,
    /// Must be excluded from backups (Android `cacheDir`/`noBackupFilesDir`, macOS
    /// `~/Library/Caches/app.vehicoule`): plugin-host keeps compiled `.cwasm` under
    /// `<cache_dir>/plugins`, and a restored file must never come from another device.
    pub cache_dir: String,
    pub downloads_dir: String,
    pub app_version: String,
    /// Country of the device locale, sent to plugins; `US` when unknown.
    pub region: String,
    pub platform: Platform,
    /// For telemetry only, like `device_model`.
    pub os_version: String,
    pub device_model: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Platform {
    Android,
    MacOs,
    Ios,
    Windows,
    Linux,
}

pub(crate) struct App {
    pub db: Db,
    /// Background work; never block on it from one of its own workers.
    pub rt: tokio::runtime::Runtime,
    pub cfg: AppConfig,
    pub plugins: Plugins,
    /// `<cache_dir>/artwork`, 256 MiB.
    pub artwork: ArtworkCache,
    /// Set through `player::set_online`; offline, no plugin call is made.
    online: AtomicBool,
    pub events: Events,
}

impl App {
    pub fn is_online(&self) -> bool {
        self.online.load(Ordering::Relaxed)
    }

    pub fn set_online(&self, online: bool) {
        self.online.store(online, Ordering::Relaxed);
    }
}

static APP: OnceLock<App> = OnceLock::new();

pub(crate) fn app() -> &'static App {
    APP.get()
        .expect("vehicoule-core: init_app must be called before anything else")
}

/// Idempotent: a second call returns `Ok` and keeps the first `App` (and its config).
pub(crate) fn init(cfg: AppConfig) -> Result<(), CoreError> {
    static INIT: Mutex<()> = Mutex::new(());
    let _guard = INIT.lock().unwrap_or_else(PoisonError::into_inner);
    if APP.get().is_some() {
        return Ok(());
    }
    let internal = |e: std::io::Error| CoreError::Internal(e.to_string());
    std::fs::create_dir_all(&cfg.data_dir).map_err(internal)?;
    let db = Db::open(&Path::new(&cfg.data_dir).join("vehicoule.db"))?;
    let rt = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .enable_all()
        .thread_name("vehicoule-core")
        .build()
        .map_err(internal)?;
    // Tests: http, any port, `*.test` resolved to 127.0.0.1 (wiremock).
    #[cfg(test)]
    let net = plugin_host::NetPolicy::for_tests();
    #[cfg(not(test))]
    let net = Default::default();
    let plugins =
        Plugins::new(&cfg, &db, net).map_err(|e| CoreError::Internal(format!("{e:#}")))?;
    plugins::seed_official(&db)?;
    rt.block_on(plugins.load_installed(&db))?;
    crate::install_panic_hook();
    let artwork = ArtworkCache::new(Path::new(&cfg.cache_dir).join("artwork"), 256 << 20);
    let _ = APP.set(App {
        db,
        rt,
        cfg,
        plugins,
        artwork,
        online: AtomicBool::new(true),
        events: Events::new(),
    });
    // Never during init: 10 s after startup, then every 24 h. Not in unit tests (network).
    #[cfg(not(test))]
    app().rt.spawn(async {
        tokio::time::sleep(std::time::Duration::from_secs(10)).await;
        loop {
            if let Err(e) = app().plugins.refresh_feeds(&app().db).await {
                crate::logs::push("error", "feeds", &format!("{e:?}"));
            }
            tokio::time::sleep(std::time::Duration::from_secs(24 * 3600)).await;
        }
    });
    // Dart asks once after the first frame; then hourly, `check_if_due` keeps it to once a day.
    #[cfg(not(test))]
    app().rt.spawn(async {
        loop {
            tokio::time::sleep(std::time::Duration::from_secs(3600)).await;
            if let Err(e) = crate::updates::check_if_due().await {
                crate::logs::push("warn", "updates", &format!("{e:?}"));
            }
        }
    });
    Ok(())
}

/// The one `App` of a test binary (FR region). Initialised from a plain thread: `init`
/// blocks on its own runtime, which a `#[tokio::test]` thread cannot do.
///
/// Its dirs live under `$TMPDIR/vehicoule-test-app/<pid>`. A static is never dropped, so a
/// run cannot remove its own: each run removes those of earlier runs (over an hour old, so
/// never a binary still running).
#[cfg(test)]
pub(crate) fn test_app() -> &'static App {
    if let Some(app) = APP.get() {
        return app;
    }
    let root = std::env::temp_dir().join("vehicoule-test-app");
    for old in std::fs::read_dir(&root).into_iter().flatten().flatten() {
        let age = old.metadata().and_then(|m| m.modified()).ok();
        let age = age.and_then(|t| t.elapsed().ok()).unwrap_or_default();
        if age > std::time::Duration::from_secs(3600) {
            let _ = std::fs::remove_dir_all(old.path());
        }
    }
    let dir = root.join(std::process::id().to_string());
    let cfg = AppConfig {
        data_dir: dir.join("data").display().to_string(),
        cache_dir: dir.join("cache").display().to_string(),
        downloads_dir: dir.join("downloads").display().to_string(),
        app_version: "0.1.0".into(),
        region: "FR".into(),
        platform: Platform::MacOs,
        os_version: "15.0".into(),
        device_model: "test".into(),
    };
    std::thread::spawn(move || init(cfg).unwrap())
        .join()
        .unwrap();
    app()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn init_is_idempotent() {
        let first = test_app();
        let mut other = first.cfg.clone();
        other.region = "US".into();
        init(other).unwrap();
        assert!(std::ptr::eq(first, app()));
        assert_eq!(app().cfg.region, "FR");
        assert_eq!(app().rt.block_on(async { 1 + 1 }), 2);
    }
}
