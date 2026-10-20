//! The global `App`, built once by `init`.

use std::path::Path;
use std::sync::{Mutex, OnceLock, PoisonError};
use std::time::Duration;

use crate::error::CoreError;
use crate::library::Db;
use crate::logs;
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
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Platform {
    Android,
    MacOs,
    Ios,
    Windows,
    Linux,
}

// `events` (task 5) joins here with its type.
pub(crate) struct App {
    pub db: Db,
    /// Background work; never block on it from one of its own workers.
    pub rt: tokio::runtime::Runtime,
    pub cfg: AppConfig,
    pub plugins: Plugins,
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
    let plugins = Plugins::new(&cfg, &db, Default::default())
        .map_err(|e| CoreError::Internal(format!("{e:#}")))?;
    plugins::seed_official(&db)?;
    rt.block_on(plugins.load_installed(&db))?;
    crate::install_panic_hook();
    let _ = APP.set(App {
        db,
        rt,
        cfg,
        plugins,
    });
    // Never during init: 10 s after startup, then every 24 h.
    app().rt.spawn(async {
        tokio::time::sleep(Duration::from_secs(10)).await;
        loop {
            if let Err(e) = app().plugins.refresh_feeds(&app().db).await {
                logs::push("error", "feeds", &format!("{e:?}"));
            }
            tokio::time::sleep(Duration::from_secs(24 * 3600)).await;
        }
    });
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn init_is_idempotent() {
        let dir = std::env::temp_dir().join(format!("vehicoule-app-{}", uuid::Uuid::now_v7()));
        let cfg = AppConfig {
            data_dir: dir.join("data").display().to_string(),
            cache_dir: dir.join("cache").display().to_string(),
            downloads_dir: dir.join("downloads").display().to_string(),
            app_version: "0.1.0".into(),
            region: "FR".into(),
            platform: Platform::MacOs,
        };
        init(cfg.clone()).unwrap();
        let db = &app().db;
        let mut other = cfg;
        other.region = "US".into();
        init(other).unwrap();
        assert!(std::ptr::eq(db, &app().db));
        assert_eq!(app().cfg.region, "FR");
        assert_eq!(app().rt.block_on(async { 1 + 1 }), 2);
        let _ = std::fs::remove_dir_all(dir);
    }
}
