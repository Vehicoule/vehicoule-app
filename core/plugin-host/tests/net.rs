mod common;

use common::{TestHost, query};
use plugin_host::{CallError, Limits};
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
