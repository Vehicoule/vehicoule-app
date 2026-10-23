//! Feeds served by wiremock, plan 2's `probe` guest compiled by the test.

use std::path::PathBuf;
use std::process::Command;
use std::sync::OnceLock;

use base64::Engine;
use base64::engine::general_purpose::STANDARD;
use ed25519_dalek::SigningKey;
use plugin_host::{
    Budget, CallError, CallReport, Capability, Feed, FeedEntry, HostEvent, NetPolicy, fingerprint,
    sign_feed,
};
use sha2::{Digest, Sha256};
use wiremock::matchers::path;
use wiremock::{Mock, MockServer, ResponseTemplate};

use super::*;
use crate::app::{AppConfig, Platform};
use crate::error::CoreError;
use crate::library::{Db, plugins as rows};
use crate::logs;

const MANIFEST: &[u8] = br#"{"id":"probe","name":"Probe","version":"1.0.0","contract":"1.0","domains":["api.probe.example"]}"#;

/// Built once per test binary, like plugin-host's own tests.
fn probe() -> Vec<u8> {
    static BUILT: OnceLock<PathBuf> = OnceLock::new();
    let dir = BUILT.get_or_init(|| {
        let guests = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../plugin-host/guests");
        let status = Command::new(env!("CARGO"))
            .args(["build", "--release", "--target", "wasm32-wasip2"])
            .current_dir(&guests)
            .env_remove("CARGO_TARGET_DIR")
            .status()
            .expect("cargo build guests");
        assert!(status.success(), "guest build failed");
        guests.join("target/wasm32-wasip2/release")
    });
    std::fs::read(dir.join("probe.wasm")).unwrap()
}

fn key() -> SigningKey {
    SigningKey::from_bytes(&[9; 32])
}

fn hex(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

fn entry(id: &str, wasm_sha256: String) -> FeedEntry {
    FeedEntry {
        id: id.into(),
        version: "1.0.0".into(),
        contract: "1.0".into(),
        wasm_url: "probe.wasm".into(),
        wasm_sha256,
        manifest_url: "probe.json".into(),
        manifest_sha256: hex(MANIFEST),
    }
}

fn good() -> FeedEntry {
    entry("probe", hex(&probe()))
}

fn feed(sequence: u64, plugins: Vec<FeedEntry>) -> Vec<u8> {
    let name = "  Test\u{7} feed \n".into();
    sign_feed(
        &Feed {
            name,
            sequence,
            plugins,
        },
        &key(),
    )
}

async fn mount_feed(server: &MockServer, at: &str, feed: Vec<u8>) {
    Mock::given(path(at))
        .respond_with(ResponseTemplate::new(200).set_body_bytes(feed))
        .mount(server)
        .await;
}

async fn mount(server: &MockServer, feed: Vec<u8>) {
    let files = [
        ("/feed.json", feed),
        ("/probe.wasm", probe()),
        ("/probe.json", MANIFEST.to_vec()),
    ];
    for (p, body) in files {
        Mock::given(path(p))
            .respond_with(ResponseTemplate::new(200).set_body_bytes(body))
            .mount(server)
            .await;
    }
}

async fn serve(feed: Vec<u8>) -> (MockServer, String) {
    let server = MockServer::start().await;
    mount(&server, feed).await;
    let url = format!("{}/feed.json", server.uri());
    (server, url)
}

struct Env {
    dir: PathBuf,
    cfg: AppConfig,
    db: Db,
}

impl Env {
    fn new() -> Env {
        let dir = std::env::temp_dir().join(format!("vehicoule-plugins-{}", uuid::Uuid::now_v7()));
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
        std::fs::create_dir_all(&cfg.data_dir).unwrap();
        let db = Db::open(&dir.join("data/vehicoule.db")).unwrap();
        Env { dir, cfg, db }
    }

    fn plugins(&self) -> Plugins {
        Plugins::new(&self.cfg, &self.db, NetPolicy::default()).unwrap()
    }

    async fn add_feed_row(&self, url: &str, last_sequence: Option<u64>) {
        self.add_row(url, last_sequence, false).await
    }

    async fn add_row(&self, url: &str, last_sequence: Option<u64>, official: bool) {
        let row = rows::FeedRow {
            url: url.into(),
            name: "test".into(),
            public_keys: vec![key().verifying_key().to_bytes()],
            official,
            last_sequence,
            fetched_at: None,
            feed: None,
        };
        self.db
            .write(move |tx| rows::put_feed(tx, &row))
            .await
            .unwrap();
    }

    async fn rows(&self) -> Vec<rows::PluginRow> {
        self.db.read(rows::plugins).await.unwrap()
    }

    async fn feeds(&self) -> Vec<rows::FeedRow> {
        self.db.read(rows::feeds).await.unwrap()
    }
}

impl Drop for Env {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

fn ids(p: &Plugins) -> Vec<String> {
    p.loaded().iter().map(|p| p.id().to_string()).collect()
}

fn logged(source: &str, needle: &str) -> bool {
    logs::recent()
        .iter()
        .any(|l| l.source == source && l.message.contains(needle))
}

#[tokio::test]
async fn feed_installs_and_loads_plugin() {
    let env = Env::new();
    let (_server, url) = serve(feed(1, vec![good()])).await;
    env.add_feed_row(&url, None).await;
    let p = env.plugins();

    assert_eq!(p.refresh_feeds(&env.db).await.unwrap(), ["probe"]);
    let loaded = p.loaded();
    assert_eq!(ids(&p), ["probe"]);
    assert_eq!(
        loaded[0].capabilities(),
        [Capability::Search, Capability::Resolve]
    );

    let sha = hex(&probe());
    let rows = env.rows().await;
    assert_eq!(rows.len(), 1);
    let row = &rows[0];
    assert_eq!(
        (
            &*row.id,
            &*row.feed_url,
            &*row.version,
            &*row.wasm_sha256,
            row.enabled
        ),
        ("probe", &*url, "1.0.0", &*sha, true)
    );
    assert_eq!(row.manifest, MANIFEST);
    let file = env
        .dir
        .join(format!("data/plugins/probe-{}.wasm", &sha[..8]));
    assert_eq!(std::fs::read(file).unwrap(), probe());
    let feeds = env.feeds().await;
    assert_eq!(
        (&*feeds[0].name, feeds[0].last_sequence),
        ("Test feed", Some(1))
    );

    // Same version and hash: nothing to install, nothing reloaded.
    assert!(p.refresh_feeds(&env.db).await.unwrap().is_empty());
    assert_eq!(ids(&p), ["probe"]);
}

#[tokio::test]
async fn wrong_wasm_hash_is_not_installed() {
    let env = Env::new();
    // A bad hash, and an entry whose id is not its manifest's.
    let bad = entry("probe", "0".repeat(64));
    let other = entry("other", hex(&probe()));
    let (_server, url) = serve(feed(1, vec![bad, other])).await;
    env.add_feed_row(&url, None).await;
    let p = env.plugins();

    assert!(p.refresh_feeds(&env.db).await.unwrap().is_empty());
    assert!(ids(&p).is_empty());
    assert!(env.rows().await.is_empty());
    assert!(logged("probe", "sha256"));
    assert!(logged("other", "manifest id"));
}

#[tokio::test]
async fn rollback_feed_is_refused() {
    let env = Env::new();
    let (_server, url) = serve(feed(2, vec![good()])).await;
    env.add_feed_row(&url, Some(3)).await;
    let p = env.plugins();

    assert!(p.refresh_feeds(&env.db).await.unwrap().is_empty());
    assert!(ids(&p).is_empty());
    assert!(env.rows().await.is_empty());
    assert_eq!(env.feeds().await[0].last_sequence, Some(3));
    // Logged under the feed's name, not its (masked) URL.
    assert!(logged("feeds", "test: Rollback { seen: 3, got: 2 }"));
}

#[tokio::test]
async fn installed_plugins_load_offline() {
    let env = Env::new();
    let (server, url) = serve(feed(1, vec![good()])).await;
    env.add_feed_row(&url, None).await;
    assert_eq!(
        env.plugins().refresh_feeds(&env.db).await.unwrap(),
        ["probe"]
    );
    drop(server);

    // A restart: new store connection, new host, no network.
    let db = Db::open(&env.dir.join("data/vehicoule.db")).unwrap();
    let p = Plugins::new(&env.cfg, &db, NetPolicy::default()).unwrap();
    assert!(ids(&p).is_empty());
    p.load_installed(&db).await.unwrap();
    assert_eq!(ids(&p), ["probe"]);
}

#[tokio::test]
async fn plugin_missing_from_feed_is_disabled() {
    let env = Env::new();
    let (server, url) = serve(feed(1, vec![good()])).await;
    env.add_feed_row(&url, None).await;
    let p = env.plugins();
    assert_eq!(p.refresh_feeds(&env.db).await.unwrap(), ["probe"]);

    server.reset().await;
    mount(&server, feed(2, vec![])).await;
    assert!(p.refresh_feeds(&env.db).await.unwrap().is_empty());
    assert!(ids(&p).is_empty());
    let rows = env.rows().await;
    assert_eq!((&*rows[0].id, rows[0].enabled), ("probe", false));

    // Back in the feed: enabled and loaded again.
    server.reset().await;
    mount(&server, feed(3, vec![good()])).await;
    assert_eq!(p.refresh_feeds(&env.db).await.unwrap(), ["probe"]);
    assert_eq!(ids(&p), ["probe"]);
    assert!(env.rows().await[0].enabled);
}

#[tokio::test]
async fn preview_shows_fingerprint_and_domains() {
    let env = Env::new();
    let (_server, url) = serve(feed(1, vec![good()])).await;
    let p = env.plugins();
    let public = key().verifying_key().to_bytes();

    let preview = p
        .preview_feed(&url, &STANDARD.encode(public))
        .await
        .unwrap();
    assert_eq!(
        preview,
        FeedPreview {
            name: "Test feed".into(),
            fingerprint: fingerprint(&public),
            plugins: vec![PluginPreview {
                id: "probe".into(),
                version: "1.0.0".into(),
                domains: vec!["api.probe.example".into()],
                capabilities: vec!["search".into(), "resolve".into()],
            }],
        }
    );
    // A preview installs nothing; another key is refused.
    assert!(env.rows().await.is_empty());
    let other = STANDARD.encode(SigningKey::from_bytes(&[1; 32]).verifying_key().to_bytes());
    for bad_key in [other.as_str(), "not base64!", "AAAA"] {
        let r = p.preview_feed(&url, bad_key).await;
        assert_eq!(r, Err(CoreError::InvalidFeed), "{bad_key}");
        let r = p.add_feed(&env.db, &url, bad_key).await;
        assert_eq!(r, Err(CoreError::InvalidFeed), "{bad_key}");
    }
    let good_key = STANDARD.encode(public);
    for bad_url in ["not a url", crate::keys::OFFICIAL_FEED_URL] {
        let r = p.add_feed(&env.db, bad_url, &good_key).await;
        assert_eq!(r, Err(CoreError::InvalidFeed), "{bad_url}");
    }
    assert!(env.feeds().await.is_empty());

    // Adding it installs its plugins.
    p.add_feed(&env.db, &url, &STANDARD.encode(public))
        .await
        .unwrap();
    assert_eq!(ids(&p), ["probe"]);
    assert_eq!(env.feeds().await[0].name, "Test feed");
}

#[tokio::test]
async fn official_feed_takes_over_a_squatted_id() {
    let env = Env::new();
    let (server, third_party) = serve(feed(1, vec![good()])).await;
    mount_feed(&server, "/official.json", feed(1, vec![good()])).await;
    let official = format!("{}/official.json", server.uri());
    env.add_feed_row(&third_party, None).await;
    env.add_row(&official, None, true).await;
    let p = env.plugins();

    // Feeds go by url: the third party installs first, then the official feed replaces it.
    p.refresh_feeds(&env.db).await.unwrap();
    let rows = env.rows().await;
    assert_eq!((&*rows[0].feed_url, rows[0].enabled), (&*official, true));
    assert!(logged("probe", "replaces the plugin of another feed"));
    assert_eq!(ids(&p), ["probe"]);

    // While the official row is enabled, the third party is refused the id.
    assert!(p.refresh_feeds(&env.db).await.unwrap().is_empty());
    assert_eq!(env.rows().await[0].feed_url, official);
    assert!(logged("probe", "enabled in another feed"));
}

#[tokio::test]
async fn disabled_id_of_another_feed_can_be_taken() {
    let env = Env::new();
    let server = MockServer::start().await;
    mount(&server, feed(1, vec![])).await;
    mount_feed(&server, "/a.json", feed(1, vec![good()])).await;
    let (a, b) = (
        format!("{}/a.json", server.uri()),
        format!("{}/b.json", server.uri()),
    );
    env.add_feed_row(&a, None).await;
    let p = env.plugins();
    assert_eq!(p.refresh_feeds(&env.db).await.unwrap(), ["probe"]);

    // `a` drops the plugin (disabled), `b` lists it: `b` takes it.
    server.reset().await;
    mount(&server, feed(1, vec![])).await;
    mount_feed(&server, "/a.json", feed(2, vec![])).await;
    mount_feed(&server, "/b.json", feed(1, vec![good()])).await;
    env.add_feed_row(&b, None).await;
    assert_eq!(p.refresh_feeds(&env.db).await.unwrap(), ["probe"]);
    let rows = env.rows().await;
    assert_eq!((&*rows[0].feed_url, rows[0].enabled), (&*b, true));
    assert_eq!(ids(&p), ["probe"]);
}

#[tokio::test]
async fn readding_a_feed_keeps_rollback_protection() {
    let env = Env::new();
    let (server, url) = serve(feed(3, vec![good()])).await;
    let p = env.plugins();
    let public = STANDARD.encode(key().verifying_key().to_bytes());
    p.add_feed(&env.db, &url, &public).await.unwrap();
    assert_eq!(env.feeds().await[0].last_sequence, Some(3));

    server.reset().await;
    mount(&server, feed(2, vec![])).await;
    let r = p.add_feed(&env.db, &url, &public).await;
    assert_eq!(r, Err(CoreError::InvalidFeed));
    assert_eq!(env.feeds().await[0].last_sequence, Some(3));
    assert_eq!(ids(&p), ["probe"]);
}

#[test]
fn call_reports_keep_full_numbers() {
    on_event(HostEvent::Call(CallReport {
        plugin: "probe-calls".into(),
        capability: Capability::Search,
        fuel_used: 123_456_789,
        http_calls: 2,
        wall_ms: 1500,
        outcome: Err(CallError::BudgetExceeded(Budget::Fuel)),
    }));
    assert!(logged(
        "probe-calls",
        "call search fuel=123456789 http=2 wall=1500 budget-exceeded-fuel"
    ));
}

#[tokio::test]
async fn removed_feed_unloads_and_deletes_its_plugins() {
    let env = Env::new();
    let (_server, url) = serve(feed(1, vec![good()])).await;
    env.add_feed_row(&url, None).await;
    let p = env.plugins();
    p.refresh_feeds(&env.db).await.unwrap();
    assert_eq!(
        p.installed(&env.db).await.unwrap(),
        [PluginView {
            id: "probe".into(),
            name: "Probe".into(),
            version: "1.0.0".into(),
            feed: url.clone(),
            capabilities: vec!["search".into(), "resolve".into()],
            enabled: true,
        }]
    );

    assert_eq!(
        p.remove_feed(&env.db, OFFICIAL_FEED_URL).await,
        Err(CoreError::InvalidFeed)
    );
    p.remove_feed(&env.db, &url).await.unwrap();
    assert!(ids(&p).is_empty());
    assert!(env.rows().await.is_empty());
    assert!(env.feeds().await.iter().all(|f| f.url != url));
    let dir = std::path::Path::new(&env.cfg.data_dir).join("plugins");
    assert_eq!(std::fs::read_dir(dir).unwrap().count(), 0, "wasm deleted");
}

#[tokio::test]
async fn remove_during_refresh_stays_removed() {
    let env = Env::new();
    let server = MockServer::start().await;
    // A slow feed: the remove lands while the refresh waits for it.
    Mock::given(path("/feed.json"))
        .respond_with(
            ResponseTemplate::new(200)
                .set_body_bytes(feed(1, vec![good()]))
                .set_delay(std::time::Duration::from_millis(300)),
        )
        .mount(&server)
        .await;
    mount(&server, feed(1, vec![good()])).await;
    let url = format!("{}/feed.json", server.uri());
    env.add_feed_row(&url, None).await;
    let p = env.plugins();
    let remove = async {
        tokio::time::sleep(std::time::Duration::from_millis(100)).await;
        p.remove_feed(&env.db, &url).await
    };
    let (refreshed, removed) = tokio::join!(p.refresh_feeds(&env.db), remove);
    refreshed.unwrap();
    removed.unwrap();
    assert!(env.feeds().await.iter().all(|f| f.url != url));
    assert!(env.rows().await.is_empty());
    assert!(ids(&p).is_empty());
}

#[tokio::test]
async fn concurrent_refreshes_install_once() {
    let env = Env::new();
    let (server, url) = serve(feed(1, vec![good()])).await;
    env.add_feed_row(&url, None).await;
    let p = env.plugins();
    // Onboarding's refresh and the background one: the second finds it up to date.
    let (a, b) = tokio::join!(p.refresh_feeds(&env.db), p.refresh_feeds(&env.db));
    let mut all = a.unwrap();
    all.extend(b.unwrap());
    assert_eq!(all, ["probe"]);
    let wasm = server.received_requests().await.unwrap();
    let wasm = wasm.iter().filter(|r| r.url.path() == "/probe.wasm");
    assert_eq!(wasm.count(), 1, "downloaded and compiled once");
}

#[tokio::test]
async fn feeds_list_their_plugin_counts() {
    let env = Env::new();
    let (_server, url) = serve(feed(1, vec![good()])).await;
    env.add_feed_row(&url, None).await;
    let p = env.plugins();
    p.refresh_feeds(&env.db).await.unwrap();
    assert_eq!(
        p.feeds(&env.db).await.unwrap(),
        [FeedView {
            url,
            name: "Test feed".into(),
            official: false,
            plugin_count: 1,
            fingerprint: fingerprint(&key().verifying_key().to_bytes()),
        }]
    );
}
