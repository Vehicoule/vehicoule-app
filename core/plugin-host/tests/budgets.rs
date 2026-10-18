use std::path::PathBuf;
use std::process::Command;
use std::sync::OnceLock;

use plugin_host::{Host, Limits, RunError};
use wiremock::matchers::method;
use wiremock::{Mock, MockServer, ResponseTemplate};

/// Builds the test components once per test binary.
fn guest(name: &str) -> Vec<u8> {
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

async fn run(name: &str, input: &str, limits: Limits) -> Result<String, RunError> {
    let host = Host::new().unwrap();
    let plugin = host.compile(&guest(name)).unwrap();
    host.run(&plugin, input, limits).await
}

#[tokio::test]
async fn echo_returns_status_through_async_http() {
    let server = MockServer::start().await;
    Mock::given(method("GET")).respond_with(ResponseTemplate::new(204)).mount(&server).await;
    let r = run("echo", &server.uri(), Limits::default()).await;
    assert_eq!(r, Ok("204".to_string()));
}

#[tokio::test]
async fn spin_runs_out_of_fuel() {
    let r = run("spin", "", Limits { fuel: 10_000_000, ..Limits::default() }).await;
    assert_eq!(r, Err(RunError::OutOfFuel));
}

#[tokio::test]
async fn spin_hits_epoch_deadline_with_unlimited_fuel() {
    let r = run("spin", "", Limits { fuel: u64::MAX, epoch_ticks: 2, ..Limits::default() }).await;
    assert_eq!(r, Err(RunError::Deadline));
}

#[tokio::test]
async fn hog_hits_memory_limit() {
    let r = run("hog", "", Limits::default()).await;
    assert_eq!(r, Err(RunError::Memory));
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
    let r = run("echo", &server.uri(), Limits::default()).await;
    assert_eq!(r, Err(RunError::Guest("HttpError::TooLarge".into())));
}

/// No Content-Length: the cap must trip while streaming.
#[tokio::test]
async fn oversized_chunked_response_is_rejected() {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
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
    let r = run("echo", &format!("http://{addr}/"), Limits::default()).await;
    assert_eq!(r, Err(RunError::Guest("HttpError::TooLarge".into())));
    assert!(sent.await.unwrap() < 16, "host kept reading past the cap");
}

#[test]
fn engine_targets_pulley() {
    assert!(Host::new().unwrap().is_pulley());
}

#[test]
fn default_limits_match_the_spec() {
    let l = Limits::default();
    assert_eq!((l.fuel, l.epoch_ticks, l.memory_bytes, l.max_response_bytes), (200_000_000, 300, 64 << 20, 8 << 20));
}
