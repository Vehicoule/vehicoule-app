// Helpers, not `#[test]` fns: clippy's `allow-unwrap-in-tests` does not reach them.
#![allow(clippy::unwrap_used)]

mod common;

use common::{TestHost, api, guest, manifest, query, temp_dir};
use plugin_host::music::resolve::{Quality, ResolveRequest};
use plugin_host::types::{EntityKind, EntityRef, TrackQuery};
use plugin_host::{CallError, CallReport, Capability, Limits, LoadError, Plugin};
use wiremock::matchers::method;
use wiremock::{Mock, MockServer, ResponseTemplate};

async fn mock(status: u16) -> MockServer {
    let server = MockServer::start().await;
    // no-store: these tests count real calls/report fields, not cache hits.
    let resp = ResponseTemplate::new(status).insert_header("cache-control", "no-store");
    Mock::given(method("GET")).respond_with(resp).mount(&server).await;
    server
}

fn track(title: &str) -> TrackQuery {
    TrackQuery { id: None, title: title.into(), artists: vec![], album: None, duration_ms: None, isrc: None }
}

#[tokio::test]
async fn search_roundtrips_typed_records() {
    let server = mock(200).await;
    let t = TestHost::new(Limits::default());
    let p = t.load("probe");
    let found = t.host.search(&p, query(&format!("get {}/x", api(&server)))).await.unwrap();
    assert_eq!(found.tracks[0].title, "200");
}

#[tokio::test]
async fn missing_capability_is_unsupported() {
    let t = TestHost::new(Limits::default());
    let lyrics = t.load("lyrics_only");
    assert_eq!(lyrics.capabilities(), [Capability::Lyrics]);
    assert_eq!(t.host.search(&lyrics, query("")).await.unwrap_err(), CallError::Unsupported);
    assert_eq!(t.host.lyrics(&lyrics, track("x")).await.unwrap().plain.as_deref(), Some("x"));
    assert_eq!(t.load("probe").capabilities(), [Capability::Search, Capability::Resolve]);
}

#[tokio::test]
async fn guest_errors_keep_their_type() {
    let server = mock(429).await;
    let t = TestHost::new(Limits::default());
    let p = t.load("probe");
    let r = t.host.search(&p, query(&format!("get {}/x", api(&server)))).await;
    assert_eq!(r.unwrap_err(), CallError::RateLimited);
    assert_eq!(t.reports()[0].outcome, Err(CallError::RateLimited));
}

#[tokio::test]
async fn returned_urls_are_checked() {
    let t = TestHost::new(Limits::default());
    let p = t.load("probe");
    let resolve = |url: &str| ResolveRequest { track: track(url), quality: Quality::Normal, region: "FR".into(), tried: vec![] };

    let r = t.host.resolve(&p, resolve("https://evil.test/a.mp3")).await;
    assert_eq!(r.unwrap_err(), CallError::Internal("stream url outside allowlist".into()));
    let ok = t.host.resolve(&p, resolve("http://api.test/a.mp3")).await.unwrap();
    assert_eq!(ok.source.url, "http://api.test/a.mp3");
    assert_eq!(ok.source.headers, [("Referer".to_string(), "r".to_string())], "routing headers stripped");

    let evil = t.host.search(&p, query("art https://evil.test/a.jpg")).await.unwrap();
    assert!(evil.tracks[0].artwork.is_empty());
    let kept = t.host.search(&p, query("art http://api.test/a.jpg")).await.unwrap();
    assert_eq!(kept.tracks[0].artwork[0].url, "http://api.test/a.jpg");
}

#[test]
fn check_url_applies_scheme_host_and_allowlist() {
    let t = TestHost::new(Limits::default());
    let p = t.load("probe");
    assert!(t.host.check_url(&p, "http://API.test/x").is_ok());
    for bad in ["https://evil.test/", "ftp://api.test/", "http://127.0.0.1/", "not a url"] {
        assert!(t.host.check_url(&p, bad).is_err(), "{bad}");
    }
}

fn cwasm_files(dir: &std::path::Path) -> Vec<std::path::PathBuf> {
    let files = std::fs::read_dir(dir).unwrap().map(|e| e.unwrap().path());
    files.filter(|p| p.extension().is_some_and(|e| e == "cwasm")).collect()
}

/// Same call twice, the second through a component deserialized from the cache.
fn same_report(mut a: CallReport, mut b: CallReport) {
    (a.wall_ms, b.wall_ms) = (0, 0);
    assert_eq!(a, b);
}

#[tokio::test]
async fn compile_cache_is_reused() {
    let dir = temp_dir();
    let first = TestHost::in_dir(Limits::default(), dir.clone());
    let p = first.load("probe");
    let [cwasm] = &cwasm_files(&dir)[..] else { panic!("expected one .cwasm in {dir:?}") };
    let written = std::fs::metadata(cwasm).unwrap().modified().unwrap();
    first.host.search(&p, query("log x")).await.unwrap();

    let second = TestHost::in_dir(Limits::default(), dir.clone());
    let p = second.load("probe");
    assert_eq!(std::fs::metadata(cwasm).unwrap().modified().unwrap(), written, "cache file was rewritten");
    assert_eq!(cwasm_files(&dir).len(), 1);
    second.host.search(&p, query("log x")).await.unwrap();
    same_report(first.reports().remove(0), second.reports().remove(0));
}

#[tokio::test]
async fn corrupt_compile_cache_is_rebuilt() {
    let dir = temp_dir();
    let t = TestHost::in_dir(Limits::default(), dir.clone());
    t.load("probe");
    let [cwasm] = &cwasm_files(&dir)[..] else { panic!("expected one .cwasm in {dir:?}") };
    let garbage: Vec<u8> = (0u32..8192).map(|i| (i.wrapping_mul(2_654_435_761) >> 24) as u8).collect();
    std::fs::write(cwasm, &garbage).unwrap();

    let p = t.load("probe");
    assert_eq!(t.host.search(&p, query("log x")).await.unwrap().tracks[0].title, "x");
    assert_ne!(std::fs::read(cwasm).unwrap(), garbage, "cache was not rebuilt");
}

#[tokio::test]
async fn call_report_counts_fuel_and_http() {
    let server = mock(200).await;
    let t = TestHost::new(Limits::default());
    let p = t.load("probe");
    t.host.search(&p, query(&format!("count {}/x 3", api(&server)))).await.unwrap();
    let [report] = &t.reports()[..] else { panic!("expected one report") };
    assert_eq!((report.plugin.as_str(), report.capability), ("probe", Capability::Search));
    assert_eq!(report.http_calls, 3);
    assert!(report.fuel_used > 0);
    assert_eq!(report.outcome, Ok(()));
}

#[test]
fn calls_are_send() {
    fn assert_send<T: Send>(_: &T) {}
    fn assert_plugin<T: Clone + Send + Sync>() {}
    assert_plugin::<Plugin>();
    let t = TestHost::new(Limits::default());
    let p = t.load("probe");
    assert_send(&t.host.search(&p, query("")));
    assert_send(&t.host.suggest(&p, "", "FR"));
    assert_send(&t.host.fetch_entity(&p, EntityRef { kind: EntityKind::Track, id: String::new() }, "FR", None));
    assert_send(&t.host.parse_link(&p, ""));
    let req = ResolveRequest { track: track(""), quality: Quality::Normal, region: "FR".into(), tried: vec![] };
    assert_send(&t.host.resolve(&p, req));
    assert_send(&t.host.lyrics(&p, track("")));
    assert_send(&t.host.radio(&p, track(""), "FR", 1));
}

#[test]
fn contract_major_mismatch_is_refused() {
    let t = TestHost::new(Limits::default());
    let r = t.host.load(&manifest("probe", "2.0"), &guest("probe"));
    assert!(matches!(r, Err(LoadError::Contract(_))), "{:?}", r.err());
    let r = t.host.load(b"{}", &guest("probe"));
    assert!(matches!(r, Err(LoadError::Manifest(_))), "{:?}", r.err());
    let r = t.host.load(&manifest("probe", "1.0"), b"not wasm");
    assert!(matches!(r, Err(LoadError::Compile(_))), "{:?}", r.err());
}
