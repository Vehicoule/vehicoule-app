//! Shared by the integration tests: test components, manifests, a host that records events.
// Helpers, not `#[test]` fns: clippy's `allow-unwrap-in-tests` does not reach them.
#![allow(dead_code, clippy::unwrap_used)]

use std::path::PathBuf;
use std::process::Command;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

use plugin_host::music::search::SearchRequest;
use plugin_host::{CallReport, Host, HostConfig, HostEvent, Limits, MemoryStorage, NetPolicy, Plugin};

/// Builds the test components once per test binary.
pub fn guest(name: &str) -> Vec<u8> {
    static BUILT: OnceLock<PathBuf> = OnceLock::new();
    let dir = BUILT.get_or_init(|| {
        let guests = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("guests");
        let status = Command::new(env!("CARGO"))
            .args(["build", "--release", "--target", "wasm32-wasip2"])
            .current_dir(&guests)
            .env_remove("CARGO_TARGET_DIR")
            .status()
            .expect("cargo build guests");
        assert!(status.success(), "guest build failed");
        guests.join("target/wasm32-wasip2/release")
    });
    std::fs::read(dir.join(format!("{name}.wasm"))).unwrap()
}

pub fn c_echo() -> Vec<u8> {
    std::fs::read(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/c-echo.wasm"))
        .expect("c-echo.wasm fixture missing; run guests/c-echo/build.sh")
}

pub fn manifest(id: &str, contract: &str) -> Vec<u8> {
    format!(r#"{{"id":"{id}","name":"{id}","version":"1.0.0","contract":"{contract}","domains":["api.test"]}}"#)
        .into_bytes()
}

/// Like `manifest`, with an optional rate limit and a descriptive-User-Agent flag.
pub fn manifest_ex(id: &str, rate_limit: Option<(u32, u32)>, descriptive_user_agent: bool) -> Vec<u8> {
    let rl = rate_limit
        .map(|(requests, per_seconds)| format!(r#","rate_limit":{{"requests":{requests},"per_seconds":{per_seconds}}}"#))
        .unwrap_or_default();
    format!(
        r#"{{"id":"{id}","name":"{id}","version":"1.0.0","contract":"1.0","domains":["api.test"],"descriptive_user_agent":{descriptive_user_agent}{rl}}}"#
    )
    .into_bytes()
}

/// A fresh, empty directory under the system temp dir.
pub fn temp_dir() -> PathBuf {
    static N: AtomicU32 = AtomicU32::new(0);
    let dir = std::env::temp_dir()
        .join(format!("plugin-host-test-{}-{}", std::process::id(), N.fetch_add(1, Ordering::Relaxed)));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

pub struct TestHost {
    pub host: Host,
    pub events: Arc<Mutex<Vec<HostEvent>>>,
    pub cache_dir: PathBuf,
}

impl TestHost {
    pub fn new(limits: Limits) -> TestHost {
        TestHost::in_dir(limits, temp_dir())
    }

    pub fn in_dir(limits: Limits, cache_dir: PathBuf) -> TestHost {
        let events = Arc::new(Mutex::new(Vec::new()));
        let sink = events.clone();
        let host = Host::new(HostConfig {
            cache_dir: cache_dir.clone(),
            storage: Arc::new(MemoryStorage::default()),
            events: Arc::new(move |e| sink.lock().unwrap().push(e)),
            limits,
            app_version: "0.0.0-test".into(),
            net: NetPolicy::for_tests(),
        })
        .unwrap();
        TestHost { host, events, cache_dir }
    }

    pub fn load(&self, name: &str) -> Plugin {
        self.host.load(&manifest(name.replace('_', "-").as_str(), "1.0"), &guest(name)).unwrap()
    }

    pub fn reports(&self) -> Vec<CallReport> {
        let events = self.events.lock().unwrap();
        events.iter().filter_map(|e| if let HostEvent::Call(r) = e { Some(r.clone()) } else { None }).collect()
    }
}

pub fn query(q: &str) -> SearchRequest {
    SearchRequest { query: q.into(), kinds: vec![], region: "FR".into(), limit: 1, cursor: None }
}

/// `http://api.test:<port>`, the mock server's address under the test resolver.
pub fn api(server: &wiremock::MockServer) -> String {
    format!("http://api.test:{}", server.address().port())
}
