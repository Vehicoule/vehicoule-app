mod common;

use common::{TestHost, guest, manifest, query};
use plugin_host::{CallError, HostEvent, Limits, LogLevel};

#[tokio::test]
async fn kv_survives_between_calls() {
    let t = TestHost::new(Limits::default());
    let p = t.load("probe");
    t.host.search(&p, query("kv-set visitor abc")).await.unwrap();
    let r = t.host.search(&p, query("kv-get visitor")).await.unwrap();
    assert_eq!(r.tracks[0].title, "abc");
}

#[tokio::test]
async fn kv_is_isolated_per_plugin() {
    let t = TestHost::new(Limits::default());
    let a = t.host.load(&manifest("probe-a", "1.0"), &guest("probe")).unwrap();
    let b = t.host.load(&manifest("probe-b", "1.0"), &guest("probe")).unwrap();
    t.host.search(&a, query("kv-set visitor abc")).await.unwrap();
    assert_eq!(t.host.search(&b, query("kv-get visitor")).await.unwrap_err(), CallError::NotFound);
}

#[tokio::test]
async fn kv_limits_are_enforced() {
    let t = TestHost::new(Limits::default());
    let p = t.load("probe");

    let big_key = "k".repeat(129);
    let r = t.host.search(&p, query(&format!("kv-set {big_key} v"))).await.unwrap();
    assert_eq!(r.tracks[0].title, "KvError::TooLarge");

    let big_value = "v".repeat((64 << 10) + 1);
    let r = t.host.search(&p, query(&format!("kv-set k {big_value}"))).await.unwrap();
    assert_eq!(r.tracks[0].title, "KvError::TooLarge");

    let value = "v".repeat(64 << 10);
    for i in 0..15 {
        let r = t.host.search(&p, query(&format!("kv-set {i:x} {value}"))).await.unwrap();
        assert_eq!(r.tracks[0].title, "ok");
    }
    let r = t.host.search(&p, query(&format!("kv-set f {value}"))).await.unwrap();
    assert_eq!(r.tracks[0].title, "KvError::QuotaExceeded");
}

fn logs(events: &[HostEvent]) -> Vec<(String, LogLevel, String)> {
    events
        .iter()
        .filter_map(|e| match e {
            HostEvent::Log { plugin, level, message } => Some((plugin.clone(), *level, message.clone())),
            HostEvent::Call(_) => None,
        })
        .collect()
}

#[tokio::test]
async fn stdout_and_log_reach_events() {
    let t = TestHost::new(Limits::default());
    let p = t.load("probe");
    t.host.search(&p, query("print hé")).await.unwrap();
    t.host.search(&p, query("log hé")).await.unwrap();
    let got = logs(&t.events.lock().unwrap());
    assert_eq!(
        got,
        vec![
            ("probe".to_string(), LogLevel::Info, "hé".to_string()),
            ("probe".to_string(), LogLevel::Info, "hé".to_string()),
        ]
    );
}

#[tokio::test]
async fn log_lines_are_capped() {
    let t = TestHost::new(Limits::default());
    let p = t.load("probe");

    t.host.search(&p, query("lines 500")).await.unwrap();
    assert_eq!(logs(&t.events.lock().unwrap()).len(), 200, "500 lines, capped at 200 events");

    t.events.lock().unwrap().clear();
    let long = "x".repeat(5000);
    t.host.search(&p, query(&format!("print {long}"))).await.unwrap();
    let got = logs(&t.events.lock().unwrap());
    assert_eq!(got.len(), 1);
    assert!(got[0].2.len() <= 2048, "{}", got[0].2.len());
    assert_eq!(got[0].2, &long[..got[0].2.len()], "truncated, not replaced");
}
