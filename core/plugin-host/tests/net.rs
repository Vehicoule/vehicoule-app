mod common;

use common::{TestHost, query};
use plugin_host::{CallError, Limits};

#[tokio::test]
async fn plugin_requests_go_through_the_allowlist() {
    let t = TestHost::new(Limits::default());
    let p = t.load("probe");
    let r = t.host.search(&p, query("get http://evil.test/")).await;
    assert_eq!(r.unwrap_err(), CallError::Internal("evil.test not allowed".into()));
    assert_eq!(t.reports()[0].http_calls, 0);
}
