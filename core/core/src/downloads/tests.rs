//! Downloads from the `fake` plugin, its stream URL pointed (kv `stream`) at a wiremock server
//! on `fake.test` (the test App's net policy resolves `*.test` to 127.0.0.1).

use std::sync::Arc;

use tokio::sync::broadcast::Receiver;
use wiremock::matchers::{header, path_regex};
use wiremock::{Mock, MockServer, Request, Respond, ResponseTemplate};

use super::*;
use crate::app::test_app;
use crate::catalog::tests::{calls, setup};
use crate::catalog::{self, parse_id};
use crate::library::kv;

/// Serves `body` by ranges; ranges past the first chunk wait `stall`.
struct Ranges {
    body: Arc<Vec<u8>>,
    stall: Duration,
}

impl Respond for Ranges {
    fn respond(&self, req: &Request) -> ResponseTemplate {
        let range = req.headers.get("range").unwrap().to_str().unwrap();
        let (a, b) = range
            .strip_prefix("bytes=")
            .unwrap()
            .split_once('-')
            .unwrap();
        let a: usize = a.parse().unwrap();
        let b = b.parse::<usize>().unwrap().min(self.body.len() - 1);
        let r = ResponseTemplate::new(206)
            .insert_header(
                "content-range",
                format!("bytes {a}-{b}/{}", self.body.len()),
            )
            .set_body_bytes(self.body[a..=b].to_vec());
        if a > 0 { r.set_delay(self.stall) } else { r }
    }
}

fn body(len: usize) -> Arc<Vec<u8>> {
    Arc::new((0..len).map(|i| (i % 251) as u8).collect())
}

/// `fake` resolves to `http://fake.test:<port>/stream/<id>`.
async fn stream_at(server: &MockServer) {
    let base = format!("http://fake.test:{}", server.address().port());
    test_app()
        .db
        .write(move |tx| kv::set(tx, "fake", "stream", base.as_bytes()))
        .await
        .unwrap();
}

async fn track(title: &str) -> String {
    catalog::search(title).await.unwrap().tracks[0].id.clone()
}

/// Progress of `id` until `until` holds.
async fn wait(
    rx: &mut Receiver<DownloadProgress>,
    id: &str,
    until: impl Fn(&DownloadProgress) -> bool,
) -> DownloadProgress {
    let wait = async {
        loop {
            let p = rx.recv().await.unwrap();
            if p.id == id && until(&p) {
                return p;
            }
        }
    };
    tokio::time::timeout(Duration::from_secs(30), wait)
        .await
        .expect("download progress")
}

fn finished(p: &DownloadProgress) -> bool {
    matches!(p.state, DownloadStateView::Done | DownloadStateView::Failed)
}

#[test]
fn download_futures_are_send() {
    fn send<T: Send>(_: T) {}
    send(enqueue(vec![]));
    send(cancel("x"));
    send(resume_pending());
}

#[tokio::test]
async fn expired_url_mid_download_resolves_again() {
    let (_lock, app) = setup().await;
    let body = body(5 << 20);
    let server = MockServer::start().await;
    // The URL expires at the second chunk, once.
    Mock::given(header("range", "bytes=2097152-4194303"))
        .respond_with(ResponseTemplate::new(403))
        .up_to_n_times(1)
        .with_priority(1)
        .mount(&server)
        .await;
    Mock::given(path_regex("^/stream/"))
        .respond_with(Ranges {
            body: body.clone(),
            stall: Duration::ZERO,
        })
        .mount(&server)
        .await;
    stream_at(&server).await;
    let id = track("expiring song").await;
    let mut rx = app.events.downloads.subscribe();
    let mut library = app.events.library.subscribe();
    let before = calls().await;

    enqueue(vec![id.clone()]).await.unwrap();
    let done = wait(&mut rx, &id, finished).await;
    assert_eq!(done.state, DownloadStateView::Done);
    assert_eq!(
        (done.bytes_done, done.bytes_total),
        (5 << 20, Some(5 << 20))
    );
    // Resolved twice; the second chunk asked again, never the first.
    assert_eq!(calls().await - before, 2);
    let ranges: Vec<String> = server
        .received_requests()
        .await
        .unwrap()
        .iter()
        .filter(|r| r.url.path().starts_with("/stream/"))
        .map(|r| r.headers.get("range").unwrap().to_str().unwrap().into())
        .collect();
    assert_eq!(
        ranges,
        [
            "bytes=0-2097151",
            "bytes=2097152-4194303",
            "bytes=2097152-4194303",
            "bytes=4194304-6291455"
        ]
    );
    let item = parse_id(&id).unwrap();
    let row = app
        .db
        .read(move |c| rows::get(c, item))
        .await
        .unwrap()
        .unwrap();
    let file = Path::new(&app.cfg.downloads_dir).join(format!("{id}.webm"));
    assert_eq!(row.path.as_deref(), Some(file.to_str().unwrap()));
    assert_eq!(
        (
            row.state,
            row.quality.as_str(),
            row.mime.as_deref(),
            row.loudness_db
        ),
        (DownloadState::Done, "high", Some("audio/webm"), Some(4.2))
    );
    assert_eq!(std::fs::read(&file).unwrap(), *body);
    assert!(!part_path(&file).exists());
    // Queued, running, done: each one told to the library.
    let mut told = 0;
    while let Ok(c) = library.try_recv() {
        told += usize::from(c == LibraryChanged::Downloads);
    }
    assert!(told >= 3, "{told}");

    // Queued again once done: nothing to do.
    enqueue(vec![id.clone()]).await.unwrap();
    assert!(rx.try_recv().is_err());
    // A finished download's cancel deletes its file.
    cancel(&id).await.unwrap();
    assert!(!file.exists());
}

#[tokio::test]
async fn cancel_removes_files() {
    let (_lock, app) = setup().await;
    let server = MockServer::start().await;
    Mock::given(path_regex("^/stream/"))
        .respond_with(Ranges {
            body: body(5 << 20),
            stall: Duration::from_secs(60),
        })
        .mount(&server)
        .await;
    stream_at(&server).await;
    let id = track("cancelled song").await;
    let mut rx = app.events.downloads.subscribe();
    enqueue(vec![id.clone()]).await.unwrap();
    // Bytes on disk, the next chunk stalled.
    wait(&mut rx, &id, |p| p.bytes_done > 0).await;
    let file = Path::new(&app.cfg.downloads_dir).join(format!("{id}.webm"));
    assert!(part_path(&file).exists());

    let mut library = app.events.library.subscribe();
    cancel(&id).await.unwrap();
    assert!(!part_path(&file).exists());
    assert!(!file.exists());
    let item = parse_id(&id).unwrap();
    assert_eq!(
        app.db.read(move |c| rows::get(c, item)).await.unwrap(),
        None
    );
    assert_eq!(library.try_recv(), Ok(LibraryChanged::Downloads));
    // The task is gone: nothing more for this id.
    tokio::time::sleep(Duration::from_millis(100)).await;
    assert!(!part_path(&file).exists());
    while let Ok(p) = rx.try_recv() {
        assert!(p.id != id || p.state == DownloadStateView::Running, "{p:?}");
    }
}

#[tokio::test(start_paused = true)]
async fn progress_is_throttled_to_2_per_second() {
    let app = test_app();
    let mut rx = app.events.downloads.subscribe();
    let id = "throttled".to_string();
    let mut p = Progress::new(id.clone());
    let start = Instant::now();
    let mut sent = Vec::new();
    // A write every 10 ms for 3 s.
    for i in 0..300 {
        p.on(i * 1000, Some(300_000));
        while let Ok(e) = rx.try_recv() {
            if e.id == id {
                sent.push((start.elapsed(), e));
            }
        }
        tokio::time::advance(Duration::from_millis(10)).await;
    }
    let at: Vec<u128> = sent.iter().map(|(t, _)| t.as_millis()).collect();
    assert_eq!(at, [0, 500, 1000, 1500, 2000, 2500]);
    let (_, last) = sent.last().unwrap();
    assert_eq!(
        last,
        &DownloadProgress {
            id,
            bytes_done: 250_000,
            bytes_total: Some(300_000),
            state: DownloadStateView::Running,
        }
    );
}
