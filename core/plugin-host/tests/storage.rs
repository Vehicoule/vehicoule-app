mod common;

use common::{TestHost, guest, manifest, query};
use plugin_host::{CallError, HostEvent, Limits, LogLevel};

#[tokio::test]
async fn kv_survives_between_calls() {
    let t = TestHost::new(Limits::default());
    let p = t.load("probe");
    t.host
        .search(&p, query("kv-set visitor abc"))
        .await
        .unwrap();
    let r = t.host.search(&p, query("kv-get visitor")).await.unwrap();
    assert_eq!(r.tracks[0].title, "abc");
}

#[tokio::test]
async fn kv_is_isolated_per_plugin() {
    let t = TestHost::new(Limits::default());
    let a = t
        .host
        .load(&manifest("probe-a", "1.0"), &guest("probe"))
        .unwrap();
    let b = t
        .host
        .load(&manifest("probe-b", "1.0"), &guest("probe"))
        .unwrap();
    t.host
        .search(&a, query("kv-set visitor abc"))
        .await
        .unwrap();
    assert_eq!(
        t.host
            .search(&b, query("kv-get visitor"))
            .await
            .unwrap_err(),
        CallError::NotFound
    );
}

#[tokio::test]
async fn kv_limits_are_enforced() {
    let t = TestHost::new(Limits::default());
    let p = t.load("probe");

    let big_key = "k".repeat(129);
    let r = t
        .host
        .search(&p, query(&format!("kv-set {big_key} v")))
        .await
        .unwrap();
    assert_eq!(r.tracks[0].title, "KvError::TooLarge");

    let big_value = "v".repeat((64 << 10) + 1);
    let r = t
        .host
        .search(&p, query(&format!("kv-set k {big_value}")))
        .await
        .unwrap();
    assert_eq!(r.tracks[0].title, "KvError::TooLarge");

    let value = "v".repeat(64 << 10);
    for i in 0..15 {
        let r = t
            .host
            .search(&p, query(&format!("kv-set {i:x} {value}")))
            .await
            .unwrap();
        assert_eq!(r.tracks[0].title, "ok");
    }
    let r = t
        .host
        .search(&p, query(&format!("kv-set f {value}")))
        .await
        .unwrap();
    assert_eq!(r.tracks[0].title, "KvError::QuotaExceeded");
}

fn logs(events: &[HostEvent]) -> Vec<(String, LogLevel, String)> {
    events
        .iter()
        .filter_map(|e| match e {
            HostEvent::Log {
                plugin,
                level,
                message,
            } => Some((plugin.clone(), *level, message.clone())),
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

/// ~3 MiB of stdout (500 lines of ~6 KiB each — `probe`'s `lines` command) must not make the
/// call fail: the streaming capture (`engine::LogStream`) never errors, it just stops buffering
/// once the 200-event cap is spent.
#[tokio::test]
async fn log_lines_are_capped() {
    let t = TestHost::new(Limits::default());
    let p = t.load("probe");

    let r = t.host.search(&p, query("lines 500")).await;
    assert!(r.is_ok(), "{r:?}");
    assert_eq!(
        logs(&t.events.lock().unwrap()).len(),
        200,
        "500 lines, capped at 200 events"
    );

    t.events.lock().unwrap().clear();
    let long = "x".repeat(5000);
    t.host
        .search(&p, query(&format!("print {long}")))
        .await
        .unwrap();
    let got = logs(&t.events.lock().unwrap());
    assert_eq!(got.len(), 1);
    assert!(got[0].2.len() <= 2048, "{}", got[0].2.len());
    assert_eq!(got[0].2, &long[..got[0].2.len()], "truncated, not replaced");
}

#[tokio::test]
async fn stderr_lines_map_to_warn() {
    let t = TestHost::new(Limits::default());
    let p = t.load("probe");
    t.host.search(&p, query("eprint oops")).await.unwrap();
    let got = logs(&t.events.lock().unwrap());
    assert_eq!(
        got,
        vec![("probe".to_string(), LogLevel::Warn, "oops".to_string())]
    );
}

/// A trailing partial line (no final `\n`) is only flushed once the instance has finished
/// running (`LogStream::flush_partial`, called from `Host::call`).
#[tokio::test]
async fn trailing_partial_line_is_flushed() {
    let t = TestHost::new(Limits::default());
    let p = t.load("probe");
    t.host
        .search(&p, query("partial no-newline"))
        .await
        .unwrap();
    let got = logs(&t.events.lock().unwrap());
    assert_eq!(
        got,
        vec![(
            "probe".to_string(),
            LogLevel::Info,
            "no-newline".to_string()
        )]
    );
}

/// `\r\n` is a single line break: the `\r` must not leak into the message.
#[tokio::test]
async fn crlf_line_has_no_trailing_cr() {
    let t = TestHost::new(Limits::default());
    let p = t.load("probe");
    t.host.search(&p, query("crlf hi")).await.unwrap();
    let got = logs(&t.events.lock().unwrap());
    assert_eq!(
        got,
        vec![("probe".to_string(), LogLevel::Info, "hi".to_string())]
    );
}

/// A line of exactly 2047 ASCII bytes followed by the 2-byte `é`: the 2048-byte cap lands right
/// on `é`'s lead byte, which must be dropped whole, not replaced with U+FFFD.
#[tokio::test]
async fn truncation_drops_an_incomplete_trailing_char_cleanly() {
    let t = TestHost::new(Limits::default());
    let p = t.load("probe");
    let text = format!("{}é", "x".repeat(2047));
    t.host
        .search(&p, query(&format!("print {text}")))
        .await
        .unwrap();
    let got = logs(&t.events.lock().unwrap());
    assert_eq!(
        got,
        vec![("probe".to_string(), LogLevel::Info, "x".repeat(2047))]
    );
}
