mod common;

use std::time::{Duration, Instant};

use common::{TestHost, api, guest, manifest_ex, query};
use plugin_host::{Budget, CallError, Limits};
use wiremock::matchers::{method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};

#[tokio::test]
async fn plugin_requests_go_through_the_allowlist() {
    let t = TestHost::new(Limits::default());
    let p = t.load("probe");
    let r = t.host.search(&p, query("get http://evil.test/")).await;
    assert_eq!(r.unwrap_err(), CallError::Internal("evil.test not allowed".into()));
    assert_eq!(t.reports()[0].http_calls, 0);
}

#[tokio::test]
async fn http_client_refuses_ip_literals() {
    let server = MockServer::start().await;
    Mock::given(method("GET")).respond_with(ResponseTemplate::new(200)).mount(&server).await;
    let t = TestHost::new(Limits::default());
    let client = t.host.http_client(&t.load("probe"));
    let port = server.address().port();
    assert_eq!(client.get(format!("http://api.test:{port}/")).send().await.unwrap().status(), 200);
    for url in
        [format!("http://127.0.0.1:{port}/"), format!("http://[::1]:{port}/"), format!("http://2130706433:{port}/")]
    {
        let err = client.get(&url).send().await.unwrap_err();
        assert!(format!("{err:?}").contains("literal IP host"), "{url}: {err:?}");
    }
    assert_eq!(server.received_requests().await.unwrap().len(), 1);
}

#[tokio::test]
async fn http_client_rechecks_redirects() {
    let server = MockServer::start().await;
    let port = server.address().port();
    let to = |host: &str| ResponseTemplate::new(302).insert_header("location", format!("http://{host}:{port}/x"));
    Mock::given(path("/evil")).respond_with(to("evil.test")).mount(&server).await;
    Mock::given(path("/ip")).respond_with(to("127.0.0.1")).mount(&server).await;
    let t = TestHost::new(Limits::default());
    let client = t.host.http_client(&t.load("probe"));
    for p in ["/evil", "/ip"] {
        let err = client.get(format!("http://api.test:{port}{p}")).send().await.unwrap_err();
        assert!(err.is_redirect(), "{p}: {err:?}");
    }
    assert!(client.get(format!("http://evil.test:{port}/x")).send().await.is_err(), "first request checked too");
    let paths: Vec<String> = server.received_requests().await.unwrap().iter().map(|r| r.url.path().into()).collect();
    assert_eq!(paths, ["/evil", "/ip"]);
}

#[tokio::test]
async fn http_call_cap_is_enforced() {
    let server = MockServer::start().await;
    // no-store: this test counts real network calls against the budget, not cache hits.
    let resp = ResponseTemplate::new(200).insert_header("cache-control", "no-store");
    Mock::given(method("GET")).respond_with(resp).mount(&server).await;
    let t = TestHost::new(Limits::default());
    let p = t.load("probe");
    let r = t.host.search(&p, query(&format!("count {}/ 30", api(&server)))).await;
    assert_eq!(r.unwrap_err(), CallError::BudgetExceeded(Budget::Http));
    assert_eq!(server.received_requests().await.unwrap().len(), 24, "24 requests go through before the budget trips");
}

#[tokio::test]
async fn guest_ok_after_http_budget_stays_ok() {
    let server = MockServer::start().await;
    let resp = ResponseTemplate::new(200).insert_header("cache-control", "no-store");
    Mock::given(method("GET")).respond_with(resp).mount(&server).await;
    let t = TestHost::new(Limits::default());
    let p = t.load("probe");
    let r = t.host.search(&p, query(&format!("count-ok {}/ 30", api(&server)))).await;
    assert_eq!(r.unwrap().tracks[0].title, "errs=6", "6 of the 30 calls hit the 24-call budget");
    assert_eq!(t.reports()[0].outcome, Ok(()), "the guest handled the budget error, so the call stays Ok");
}

#[tokio::test]
async fn http_byte_cap_is_enforced() {
    let server = MockServer::start().await;
    let body = vec![b'x'; 7 << 20];
    Mock::given(method("GET")).respond_with(ResponseTemplate::new(200).set_body_bytes(body)).mount(&server).await;
    let t = TestHost::new(Limits::default());
    let p = t.load("probe");
    let r = t.host.search(&p, query(&format!("count {}/ 3", api(&server)))).await;
    assert_eq!(r.unwrap_err(), CallError::BudgetExceeded(Budget::Http));
    assert_eq!(server.received_requests().await.unwrap().len(), 3, "the 3rd 7 MiB response is fetched, then refused");
}

#[tokio::test]
async fn batch_runs_concurrently() {
    let server = MockServer::start().await;
    let resp = ResponseTemplate::new(200).set_delay(Duration::from_millis(500));
    Mock::given(method("GET")).respond_with(resp).mount(&server).await;
    let t = TestHost::new(Limits::default());
    let p = t.load("probe");
    let start = Instant::now();
    let r = t.host.search(&p, query(&format!("batch {}/ 8", api(&server)))).await.unwrap();
    let titles: Vec<&str> = r.tracks.iter().map(|t| t.title.as_str()).collect();
    assert_eq!(titles, ["200"; 8], "all 8 must actually have succeeded, not just returned a result");
    assert_eq!(server.received_requests().await.unwrap().len(), 8);
    assert!(start.elapsed() < Duration::from_millis(1500), "{:?}", start.elapsed());
}

#[tokio::test]
async fn concurrent_batches_share_the_call_cap() {
    let server = MockServer::start().await;
    // no-store: 3 sequential batches to the same URL must all be real requests, not the 2nd
    // and 3rd served from the 1st's cache entry.
    let resp = ResponseTemplate::new(200).insert_header("cache-control", "no-store");
    Mock::given(method("GET")).respond_with(resp).mount(&server).await;
    let t = TestHost::new(Limits::default());
    let p = t.load("probe");
    let r = t.host.search(&p, query(&format!("cap-batch {}/", api(&server)))).await.unwrap();
    assert_eq!(r.tracks[0].title, "ok=24 extra_ok=false", "3 batches of 8 exactly spend the 24-call budget");
    assert_eq!(server.received_requests().await.unwrap().len(), 24, "the 25th (extra) request is never sent");
}

#[tokio::test]
async fn batch_over_8_is_denied() {
    let server = MockServer::start().await;
    Mock::given(method("GET")).respond_with(ResponseTemplate::new(200)).mount(&server).await;
    let t = TestHost::new(Limits::default());
    let p = t.load("probe");
    let r = t.host.search(&p, query(&format!("batch {}/ 9", api(&server)))).await.unwrap();
    assert_eq!(r.tracks.len(), 9);
    for track in &r.tracks {
        assert!(track.title.contains("more than 8"), "{}", track.title);
    }
    assert_eq!(server.received_requests().await.unwrap().len(), 0, "an over-sized batch sends nothing");
}

#[tokio::test]
async fn rate_limit_waits_instead_of_failing() {
    // Real time, not `#[tokio::test(start_paused = true)]`: wiremock listens on a real TCP
    // socket, and the virtual clock does not advance in step with that real I/O.
    let server = MockServer::start().await;
    // no-store: this test times 5 real, rate-limited requests, not cache hits after the 1st.
    let resp = ResponseTemplate::new(200).insert_header("cache-control", "no-store");
    Mock::given(method("GET")).respond_with(resp).mount(&server).await;
    let t = TestHost::new(Limits::default());
    let p = t.host.load(&manifest_ex("probe", Some((2, 1)), false), &guest("probe")).unwrap();
    let start = Instant::now();
    let r = t.host.search(&p, query(&format!("count {}/ 5", api(&server)))).await;
    assert!(r.is_ok(), "{r:?}");
    let elapsed = start.elapsed();
    assert!(elapsed >= Duration::from_secs(2) && elapsed < Duration::from_secs(4), "{elapsed:?}");
}

#[tokio::test]
async fn descriptive_user_agent_is_set() {
    let server = MockServer::start().await;
    // no-store: the cache key ignores `user-agent` by design (ruling 3), so without this the
    // 2nd request (different UA, same URL otherwise) would be served from the 1st's cache entry
    // and never reach the server.
    let resp = ResponseTemplate::new(200).insert_header("cache-control", "no-store");
    Mock::given(method("GET")).respond_with(resp).mount(&server).await;
    let t = TestHost::new(Limits::default());
    let url = format!("{}/ plugin-agent/1", api(&server));

    let on = t.host.load(&manifest_ex("probe", None, true), &guest("probe")).unwrap();
    t.host.search(&on, query(&format!("ua {url}"))).await.unwrap();
    let off = t.host.load(&manifest_ex("probe", None, false), &guest("probe")).unwrap();
    t.host.search(&off, query(&format!("ua {url}"))).await.unwrap();

    let got = server.received_requests().await.unwrap();
    assert_eq!(got.len(), 2);
    assert_eq!(got[0].headers.get("user-agent").unwrap(), &"Vehicoule/0.0.0-test (+https://vehicoule.app)".to_string());
    assert_eq!(got[1].headers.get("user-agent").unwrap(), &"plugin-agent/1".to_string());
}
