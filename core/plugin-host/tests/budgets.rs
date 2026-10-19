mod common;

use common::{TestHost, api, c_echo, manifest, query};
use plugin_host::{Budget, CallError, Limits};
use wiremock::matchers::method;
use wiremock::{Mock, MockServer, ResponseTemplate};

/// Title of the first track `name` returns for `input`.
async fn run(name: &str, input: &str, limits: Limits) -> Result<String, CallError> {
    let t = TestHost::new(limits);
    let plugin = t.load(name);
    t.host.search(&plugin, query(input)).await.map(|r| r.tracks[0].title.clone())
}

#[tokio::test]
async fn probe_returns_status_through_async_http() {
    let server = MockServer::start().await;
    Mock::given(method("GET")).respond_with(ResponseTemplate::new(204)).mount(&server).await;
    let r = run("probe", &format!("get {}/", api(&server)), Limits::default()).await;
    assert_eq!(r, Ok("204".to_string()));
}

#[tokio::test]
async fn spin_runs_out_of_fuel() {
    let r = run("spin", "", Limits { fuel: 10_000_000, ..Limits::default() }).await;
    assert_eq!(r, Err(CallError::BudgetExceeded(Budget::Fuel)));
}

#[tokio::test]
async fn spin_hits_epoch_deadline_with_unlimited_fuel() {
    let r = run("spin", "", Limits { fuel: u64::MAX, epoch_ticks: 2, ..Limits::default() }).await;
    assert_eq!(r, Err(CallError::BudgetExceeded(Budget::Time)));
}

#[tokio::test]
async fn deadline_holds_while_the_guest_waits_on_the_host() {
    let host = TestHost::new(Limits { epoch_ticks: 2, ..Limits::default() });
    let plugin = host.load("sleepy");
    // Timed from here: guest build and compile are not part of the call's deadline.
    let t = std::time::Instant::now();
    let r = host.host.search(&plugin, query("")).await.map(|r| r.tracks[0].title.clone());
    assert_eq!(r, Err(CallError::BudgetExceeded(Budget::Time)));
    assert!(t.elapsed() < std::time::Duration::from_secs(2), "{:?}", t.elapsed());
}

#[tokio::test]
async fn hog_hits_memory_limit() {
    let r = run("hog", "", Limits::default()).await;
    assert_eq!(r, Err(CallError::BudgetExceeded(Budget::Memory)));
}

#[tokio::test]
async fn hog_fits_with_a_larger_memory_limit() {
    let r = run("hog", "", Limits { memory_bytes: 256 << 20, ..Limits::default() }).await;
    assert_eq!(r, Ok((100 << 20).to_string()));
}

#[tokio::test]
async fn oversized_response_is_rejected() {
    let server = MockServer::start().await;
    let body = vec![b'x'; 9 << 20];
    Mock::given(method("GET")).respond_with(ResponseTemplate::new(200).set_body_bytes(body)).mount(&server).await;
    let r = run("probe", &format!("get {}/", api(&server)), Limits::default()).await;
    assert_eq!(r, Err(CallError::Internal("response too large".into())));
}

/// No Content-Length: the cap must trip while streaming.
#[tokio::test]
async fn oversized_chunked_response_is_rejected() {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let sent = tokio::spawn(async move {
        let (mut sock, _) = listener.accept().await.unwrap();
        let mut buf = [0u8; 4096];
        let _ = sock.read(&mut buf).await.unwrap();
        sock.write_all(b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n").await.unwrap();
        let chunk = vec![b'x'; 1 << 20];
        let mut sent = 0;
        for _ in 0..16 {
            let head = format!("{:x}\r\n", chunk.len());
            if sock.write_all(head.as_bytes()).await.is_err()
                || sock.write_all(&chunk).await.is_err()
                || sock.write_all(b"\r\n").await.is_err()
            {
                break;
            }
            sent += 1;
        }
        sent
    });
    let r = run("probe", &format!("get http://api.test:{port}/"), Limits::default()).await;
    assert_eq!(r, Err(CallError::Internal("response too large".into())));
    assert!(sent.await.unwrap() < 16, "host kept reading past the cap");
}

/// Proof that a non-Rust guest works too: the committed fixture, built by
/// `guests/c-echo/build.sh`, GETs the query URL like the Rust probe's `get`.
#[tokio::test]
async fn c_component_runs_like_a_rust_one() {
    let server = MockServer::start().await;
    Mock::given(method("GET")).respond_with(ResponseTemplate::new(204)).mount(&server).await;
    let t = TestHost::new(Limits::default());
    let plugin = t.host.load(&manifest("c-echo", "1.0"), &c_echo()).unwrap();
    let r = t.host.search(&plugin, query(&format!("{}/", api(&server)))).await.unwrap();
    assert_eq!(r.tracks[0].title, "204");
}

#[test]
fn engine_targets_pulley() {
    assert!(TestHost::new(Limits::default()).host.is_pulley());
}

#[test]
fn default_limits_match_the_spec() {
    let l = Limits::default();
    assert_eq!((l.fuel, l.epoch_ticks, l.memory_bytes, l.max_response_bytes), (200_000_000, 300, 64 << 20, 8 << 20));
    assert_eq!((l.max_http_calls, l.max_http_bytes), (24, 16 << 20));
}
