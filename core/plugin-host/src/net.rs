//! Locked-down network for plugin HTTP and for URLs plugins return: https on the default
//! port, domain hosts in the manifest allowlist, public addresses only (checked on the address
//! actually connected to), redirects followed by hand and re-checked at every hop.

use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};
use std::sync::Arc;
use std::time::Duration;

use contract::http::{HttpError, Method, Request, Response};
use reqwest::Url;
use reqwest::header::{HeaderMap, LOCATION};

use crate::manifest::{Allowlist, ends_in_number};

const MAX_REDIRECTS: u32 = 5;

#[derive(Clone)]
pub struct NetPolicy {
    client: reqwest::Client,
    /// https and the scheme's default port only; test policies lift both.
    strict_urls: bool,
    #[cfg(any(test, feature = "test-util"))]
    replay: Option<Arc<crate::replay::Replay>>,
}

impl Default for NetPolicy {
    /// https on the default port, public addresses only.
    fn default() -> Self {
        NetPolicy::new(Resolver { lookup: Lookup::System, allow_loopback: false }, true)
    }
}

impl NetPolicy {
    fn new(resolver: Resolver, strict_urls: bool) -> NetPolicy {
        let client = reqwest::Client::builder()
            .no_proxy()
            .redirect(reqwest::redirect::Policy::none())
            .timeout(Duration::from_secs(20))
            .dns_resolver(Arc::new(resolver))
            .build()
            .expect("http client");
        NetPolicy {
            client,
            strict_urls,
            #[cfg(any(test, feature = "test-util"))]
            replay: None,
        }
    }

    /// Filtering resolver, no proxy, no automatic redirects. For plugin requests and for the
    /// core's own fetches of returned URLs (which must go through `Host::check_url` first).
    pub fn client(&self) -> reqwest::Client {
        self.client.clone()
    }

    /// http and any port allowed; `rebind.test` resolves to 10.0.0.1 (refused), any other
    /// `*.test` to 127.0.0.1 (loopback allowed in this policy only), anything else fails.
    #[cfg(any(test, feature = "test-util"))]
    pub fn for_tests() -> NetPolicy {
        NetPolicy::new(Resolver { lookup: Lookup::Test, allow_loopback: true }, false)
    }

    /// Serves `dir/index.json` recordings, never the network; URL checks still apply.
    #[cfg(any(test, feature = "test-util"))]
    pub fn replay(dir: &std::path::Path) -> NetPolicy {
        let mut policy = NetPolicy::new(Resolver { lookup: Lookup::Nothing, allow_loopback: false }, false);
        policy.replay = Some(Arc::new(crate::replay::Replay::load(dir)));
        policy
    }

    /// Scheme, credentials, literal IP, port, allowlist. DNS answers are checked by the resolver.
    pub(crate) fn check(&self, allow: &Allowlist, url: &Url) -> Result<(), String> {
        let scheme = url.scheme();
        if scheme != "https" && (self.strict_urls || scheme != "http") {
            return Err(format!("scheme not allowed: {scheme}"));
        }
        if !url.username().is_empty() || url.password().is_some() {
            return Err("credentials in url".into());
        }
        // reqwest skips the resolver for an IP host, so it must never reach the client.
        // `domain()` is None for an IP host; http(s) URLs always have a host.
        let Some(host) = url.domain().filter(|d| !ends_in_number(d)) else {
            return Err(format!("literal IP host: {}", url.host_str().unwrap_or("")));
        };
        if self.strict_urls && url.port().is_some() {
            return Err(format!("port not allowed: {}", url.port().unwrap_or(0)));
        }
        if !allow.allows(host) {
            return Err(format!("{host} not allowed"));
        }
        Ok(())
    }
}

/// Globally routable unicast. IPv6 forms embedding an IPv4 (mapped, NAT64) take its verdict.
pub fn is_public(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(v4) => is_public_v4(v4),
        IpAddr::V6(v6) => is_public_v6(v6),
    }
}

fn is_public_v4(ip: Ipv4Addr) -> bool {
    let [a, b, c, _] = ip.octets();
    !(a == 0                                    // "this network"
        || a == 10
        || (a == 100 && (64..128).contains(&b)) // shared, CGNAT
        || a == 127
        || (a == 169 && b == 254)
        || (a == 172 && (16..32).contains(&b))
        || (a == 192 && b == 0 && (c == 0 || c == 2)) // IETF assignments, TEST-NET-1
        || (a == 192 && b == 88 && c == 99)     // 6to4 relay anycast
        || (a == 192 && b == 168)
        || (a == 198 && (b == 18 || b == 19))   // benchmarking
        || (a == 198 && b == 51 && c == 100)    // TEST-NET-2
        || (a == 203 && b == 0 && c == 113)     // TEST-NET-3
        || a >= 224) // multicast, reserved, broadcast
}

fn is_public_v6(ip: Ipv6Addr) -> bool {
    if let Some(v4) = ip.to_ipv4_mapped() {
        return is_public_v4(v4);
    }
    let s = ip.segments();
    if s[..6] == [0x64, 0xff9b, 0, 0, 0, 0] {
        let [a, b, c, d] = [s[6] >> 8, s[6] & 0xff, s[7] >> 8, s[7] & 0xff].map(|x| x as u8);
        return is_public_v4(Ipv4Addr::new(a, b, c, d));
    }
    // Global unicast 2000::/3, minus IETF assignments (incl. Teredo), documentation and 6to4.
    (s[0] & 0xe000) == 0x2000 && s[0] != 0x2002 && !(s[0] == 0x2001 && (s[1] < 0x200 || s[1] == 0xdb8))
}

#[derive(Clone, Copy)]
enum Lookup {
    System,
    #[cfg(any(test, feature = "test-util"))]
    Test,
    #[cfg(any(test, feature = "test-util"))]
    Nothing,
}

/// Keeps only public addresses (plus loopback when allowed); none left → `Denied`.
struct Resolver {
    lookup: Lookup,
    allow_loopback: bool,
}

/// Resolver refusal, recognised in the reqwest error chain to become `HttpError::Denied`.
#[derive(Debug)]
struct DeniedAddress(String);

impl std::fmt::Display for DeniedAddress {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for DeniedAddress {}

impl reqwest::dns::Resolve for Resolver {
    fn resolve(&self, name: reqwest::dns::Name) -> reqwest::dns::Resolving {
        let host = name.as_str().trim_end_matches('.').to_ascii_lowercase();
        let (lookup, allow_loopback) = (self.lookup, self.allow_loopback);
        Box::pin(async move {
            let addrs: Vec<std::net::SocketAddr> = match lookup {
                Lookup::System => tokio::net::lookup_host((host.as_str(), 0)).await?.collect(),
                #[cfg(any(test, feature = "test-util"))]
                Lookup::Test if host == "rebind.test" => vec![([10, 0, 0, 1], 0).into()],
                #[cfg(any(test, feature = "test-util"))]
                Lookup::Test if host.ends_with(".test") => vec![([127, 0, 0, 1], 0).into()],
                #[cfg(any(test, feature = "test-util"))]
                Lookup::Test | Lookup::Nothing => {
                    return Err(format!("test resolver does not know {host}").into());
                }
            };
            let kept: Vec<_> =
                addrs.into_iter().filter(|a| is_public(a.ip()) || (allow_loopback && a.ip().is_loopback())).collect();
            if kept.is_empty() {
                return Err(Box::new(DeniedAddress(format!("{host} resolves to no public address"))) as _);
            }
            Ok(Box::new(kept.into_iter()) as reqwest::dns::Addrs)
        })
    }
}

/// A response whose body is still to be read.
pub(crate) struct Hop {
    pub(crate) status: u16,
    pub(crate) headers: Vec<(String, String)>,
    pub(crate) body: Body,
}

pub(crate) enum Body {
    Live(reqwest::Response),
    #[cfg(any(test, feature = "test-util"))]
    Recorded(Vec<u8>),
}

/// Sends `req` under `policy` and `allow`, following up to 5 redirects by hand. Every request
/// sent (each hop) adds one to `calls`; the body is read up to `max_body` bytes.
pub(crate) async fn fetch(
    policy: &NetPolicy,
    allow: &Allowlist,
    req: Request,
    max_body: usize,
    calls: &mut u32,
) -> Result<Response, HttpError> {
    let mut url = Url::parse(&req.url).map_err(|e| HttpError::Denied(format!("{}: {e}", req.url)))?;
    let mut method = req.method;
    let mut headers = req.headers;
    let mut body = req.body;
    let mut redirects = 0;
    loop {
        policy.check(allow, &url).map_err(HttpError::Denied)?;
        // ponytail: plain counter; task 4 turns it into the per-call HTTP budget.
        *calls += 1;
        let hop = send(policy, method, &url, &headers, body.clone()).await?;
        let redirect = matches!(hop.status, 301..=303 | 307 | 308);
        let location = redirect.then(|| header(&hop.headers, LOCATION.as_str())).flatten();
        let Some(location) = location else {
            return read(hop, url, max_body).await;
        };
        if redirects == MAX_REDIRECTS {
            return Err(HttpError::Network("too many redirects".into()));
        }
        redirects += 1;
        let next = url.join(location).map_err(|e| HttpError::Network(format!("bad redirect {location:?}: {e}")))?;
        if matches!(hop.status, 301..=303) && matches!(method, Method::Post) {
            method = Method::Get;
        }
        if matches!(hop.status, 301..=303) {
            body = None;
            headers
                .retain(|(k, _)| !k.eq_ignore_ascii_case("content-type") && !k.eq_ignore_ascii_case("content-length"));
        }
        if next.origin() != url.origin() {
            headers.retain(|(k, _)| {
                !["authorization", "cookie", "proxy-authorization"].iter().any(|h| k.eq_ignore_ascii_case(h))
            });
        }
        url = next;
    }
}

fn header<'a>(headers: &'a [(String, String)], name: &str) -> Option<&'a str> {
    headers.iter().find(|(k, _)| k.eq_ignore_ascii_case(name)).map(|(_, v)| v.as_str())
}

async fn send(
    policy: &NetPolicy,
    method: Method,
    url: &Url,
    headers: &[(String, String)],
    body: Option<Vec<u8>>,
) -> Result<Hop, HttpError> {
    let m = match method {
        Method::Get => reqwest::Method::GET,
        Method::Head => reqwest::Method::HEAD,
        Method::Post => reqwest::Method::POST,
    };
    #[cfg(any(test, feature = "test-util"))]
    if let Some(replay) = &policy.replay {
        return replay.find(m.as_str(), url.as_str());
    }
    let mut builder = policy.client.request(m, url.clone());
    for (k, v) in headers {
        builder = builder.header(k, v);
    }
    if let Some(body) = body {
        builder = builder.body(body);
    }
    let resp = builder.send().await.map_err(net_error)?;
    Ok(Hop { status: resp.status().as_u16(), headers: pairs(resp.headers()), body: Body::Live(resp) })
}

fn pairs(headers: &HeaderMap) -> Vec<(String, String)> {
    headers.iter().map(|(k, v)| (k.to_string(), String::from_utf8_lossy(v.as_bytes()).into_owned())).collect()
}

/// Reads the body as a stream and stops at `max`.
async fn read(hop: Hop, url: Url, max: usize) -> Result<Response, HttpError> {
    let body = match hop.body {
        Body::Live(mut resp) => {
            if resp.content_length().is_some_and(|n| n > max as u64) {
                return Err(HttpError::TooLarge);
            }
            let mut body = Vec::new();
            while let Some(chunk) = resp.chunk().await.map_err(net_error)? {
                if body.len() + chunk.len() > max {
                    return Err(HttpError::TooLarge);
                }
                body.extend_from_slice(&chunk);
            }
            body
        }
        #[cfg(any(test, feature = "test-util"))]
        Body::Recorded(body) if body.len() > max => return Err(HttpError::TooLarge),
        #[cfg(any(test, feature = "test-util"))]
        Body::Recorded(body) => body,
    };
    Ok(Response { status: hop.status, url: url.into(), headers: hop.headers, body })
}

fn net_error(e: reqwest::Error) -> HttpError {
    let mut source: Option<&(dyn std::error::Error + 'static)> = Some(&e);
    while let Some(err) = source {
        if let Some(denied) = err.downcast_ref::<DeniedAddress>() {
            return HttpError::Denied(denied.0.clone());
        }
        source = err.source();
    }
    if e.is_timeout() { HttpError::Timeout } else { HttpError::Network(e.to_string()) }
}

#[cfg(test)]
mod tests {
    use std::net::IpAddr;

    use contract::http::{HttpError, Method, Request, Response};
    use wiremock::matchers::{method, path};
    use wiremock::{Mock, MockServer, ResponseTemplate};

    use super::*;
    use crate::manifest::Allowlist;

    fn allow(domains: &[&str]) -> Allowlist {
        Allowlist::new(&domains.iter().map(|d| d.to_string()).collect::<Vec<_>>()).unwrap()
    }

    fn req(m: Method, url: &str) -> Request {
        Request { method: m, url: url.into(), headers: vec![], body: None }
    }

    async fn run(policy: &NetPolicy, allow: &Allowlist, req: Request) -> (Result<Response, HttpError>, u32) {
        let mut calls = 0;
        let r = fetch(policy, allow, req, 8 << 20, &mut calls).await;
        (r, calls)
    }

    fn denied(r: Result<Response, HttpError>) -> String {
        match r {
            Err(HttpError::Denied(m)) => m,
            other => panic!("expected Denied, got {:?}", other.map(|r| r.status)),
        }
    }

    fn base(server: &MockServer, host: &str) -> String {
        format!("http://{host}:{}", server.address().port())
    }

    async fn redirect(server: &MockServer, from: &str, status: u16, to: &str) {
        let resp = ResponseTemplate::new(status).insert_header("location", to);
        Mock::given(path(from)).respond_with(resp).mount(server).await;
    }

    #[test]
    fn private_addresses_are_refused() {
        let refused = [
            "0.0.0.0",
            "10.1.2.3",
            "100.64.0.1",
            "127.0.0.1",
            "169.254.1.1",
            "172.16.0.1",
            "192.0.0.1",
            "192.0.2.1",
            "192.168.1.1",
            "198.18.0.1",
            "198.51.100.1",
            "203.0.113.1",
            "224.0.0.1",
            "240.0.0.1",
            "255.255.255.255",
            "::",
            "::1",
            "fc00::1",
            "fe80::1",
            "ff02::1",
            "2001:db8::1",
            "::ffff:10.0.0.1",
            "64:ff9b::a00:1",
        ];
        for ip in refused {
            assert!(!is_public(ip.parse::<IpAddr>().unwrap()), "{ip} should be refused");
        }
        for ip in ["1.1.1.1", "2606:4700::1111", "::ffff:1.1.1.1"] {
            assert!(is_public(ip.parse::<IpAddr>().unwrap()), "{ip} should be public");
        }
    }

    #[tokio::test]
    async fn ip_literal_hosts_are_denied() {
        let list = allow(&["api.test"]);
        for policy in [NetPolicy::default(), NetPolicy::for_tests()] {
            for url in ["https://127.0.0.1/", "https://[::1]/", "https://2130706433/", "https://0x7f.1/"] {
                let (r, calls) = run(&policy, &list, req(Method::Get, url)).await;
                assert!(denied(r).contains("literal IP"), "{url}");
                assert_eq!(calls, 0);
            }
        }
    }

    #[tokio::test]
    async fn non_https_and_userinfo_are_denied() {
        let list = allow(&["api.deezer.com"]);
        let policy = NetPolicy::default();
        for url in [
            "http://api.deezer.com/",
            "https://u:p@api.deezer.com/",
            "https://u@api.deezer.com/",
            "https://api.deezer.com:8443/",
        ] {
            let (r, calls) = run(&policy, &list, req(Method::Get, url)).await;
            denied(r);
            assert_eq!(calls, 0, "{url}");
        }
    }

    #[tokio::test]
    async fn domain_outside_manifest_is_denied() {
        let (r, calls) =
            run(&NetPolicy::for_tests(), &allow(&["api.test"]), req(Method::Get, "http://example.org/")).await;
        assert_eq!(denied(r), "example.org not allowed");
        assert_eq!(calls, 0);
    }

    #[tokio::test]
    async fn dns_to_private_ip_is_denied() {
        // The test resolver maps rebind.test to 10.0.0.1; `for_tests` only lets loopback through.
        let (r, calls) =
            run(&NetPolicy::for_tests(), &allow(&["rebind.test"]), req(Method::Get, "http://rebind.test/")).await;
        assert!(denied(r).contains("rebind.test"));
        assert_eq!(calls, 1);
        // System resolver: localhost answers loopback only, refused by the default policy.
        let (r, _) = run(&NetPolicy::default(), &allow(&["localhost"]), req(Method::Get, "https://localhost/")).await;
        assert_eq!(denied(r), "localhost resolves to no public address");
    }

    #[tokio::test]
    async fn redirect_to_foreign_domain_is_denied() {
        let server = MockServer::start().await;
        redirect(&server, "/a", 302, &format!("{}/x", base(&server, "evil.test"))).await;
        redirect(&server, "/b", 302, &format!("{}/x", base(&server, "127.0.0.1"))).await;
        let (policy, list) = (NetPolicy::for_tests(), allow(&["api.test"]));
        let (r, _) = run(&policy, &list, req(Method::Get, &format!("{}/a", base(&server, "api.test")))).await;
        assert_eq!(denied(r), "evil.test not allowed");
        let (r, _) = run(&policy, &list, req(Method::Get, &format!("{}/b", base(&server, "api.test")))).await;
        assert!(denied(r).contains("literal IP"));
        let paths: Vec<String> =
            server.received_requests().await.unwrap().iter().map(|r| r.url.path().to_string()).collect();
        assert_eq!(paths, ["/a", "/b"]);
    }

    #[tokio::test]
    async fn redirect_hops_are_capped_at_5() {
        let server = MockServer::start().await;
        let url = |n: u32| format!("{}/{n}", base(&server, "api.test"));
        for n in 0..6 {
            redirect(&server, &format!("/{n}"), 302, &url(n + 1)).await;
        }
        Mock::given(path("/6")).respond_with(ResponseTemplate::new(200)).mount(&server).await;
        let (policy, list) = (NetPolicy::for_tests(), allow(&["api.test"]));

        let (r, calls) = run(&policy, &list, req(Method::Get, &url(1))).await;
        assert_eq!(r.unwrap().status, 200, "5 redirects are followed");
        assert_eq!(calls, 6, "every hop counts as a request");

        let (r, calls) = run(&policy, &list, req(Method::Get, &url(0))).await;
        match r {
            Err(HttpError::Network(m)) => assert_eq!(m, "too many redirects"),
            other => panic!("{:?}", other.map(|r| r.status)),
        }
        assert_eq!(calls, 6);
    }

    #[tokio::test]
    async fn see_other_becomes_get_without_body() {
        let server = MockServer::start().await;
        let api = base(&server, "api.test");
        redirect(&server, "/see", 303, &format!("{api}/got")).await;
        redirect(&server, "/temp", 307, &format!("{api}/kept")).await;
        Mock::given(path("/got")).respond_with(ResponseTemplate::new(200)).mount(&server).await;
        Mock::given(path("/kept")).respond_with(ResponseTemplate::new(200)).mount(&server).await;
        let (policy, list) = (NetPolicy::for_tests(), allow(&["api.test"]));
        for p in ["/see", "/temp"] {
            let post = Request { body: Some(b"payload".to_vec()), ..req(Method::Post, &format!("{api}{p}")) };
            assert_eq!(run(&policy, &list, post).await.0.unwrap().status, 200);
        }
        let got = server.received_requests().await.unwrap();
        let by_path = |p: &str| got.iter().find(|r| r.url.path() == p).unwrap().clone();
        assert_eq!(by_path("/got").method.as_str(), "GET");
        assert!(by_path("/got").body.is_empty());
        assert_eq!(by_path("/kept").method.as_str(), "POST");
        assert_eq!(by_path("/kept").body, b"payload");
    }

    #[tokio::test]
    async fn credentials_dropped_on_cross_host_redirect() {
        let server = MockServer::start().await;
        redirect(&server, "/same", 302, &format!("{}/cross", base(&server, "api.test"))).await;
        redirect(&server, "/cross", 302, &format!("{}/end", base(&server, "cdn.test"))).await;
        Mock::given(path("/end")).respond_with(ResponseTemplate::new(200)).mount(&server).await;
        let headers = vec![
            ("Authorization".into(), "Bearer t".into()),
            ("Cookie".into(), "s=1".into()),
            ("X-Keep".into(), "1".into()),
        ];
        let r = Request { headers, ..req(Method::Get, &format!("{}/same", base(&server, "api.test"))) };
        let (r, _) = run(&NetPolicy::for_tests(), &allow(&["api.test", "cdn.test"]), r).await;
        assert_eq!(r.unwrap().status, 200);
        let got = server.received_requests().await.unwrap();
        let has = |p: &str, h: &str| got.iter().find(|r| r.url.path() == p).unwrap().headers.contains_key(h);
        assert!(has("/cross", "authorization") && has("/cross", "cookie"), "same host keeps credentials");
        assert!(!has("/end", "authorization") && !has("/end", "cookie"));
        assert!(has("/end", "x-keep"));
    }

    #[tokio::test]
    async fn final_url_is_reported() {
        let server = MockServer::start().await;
        let api = base(&server, "api.test");
        redirect(&server, "/a", 301, "/b?x=1").await;
        Mock::given(method("GET")).and(path("/b")).respond_with(ResponseTemplate::new(200)).mount(&server).await;
        let (r, _) = run(&NetPolicy::for_tests(), &allow(&["api.test"]), req(Method::Get, &format!("{api}/a"))).await;
        assert_eq!(r.unwrap().url, format!("{api}/b?x=1"));
    }

    #[tokio::test]
    async fn replay_serves_recordings_without_network() {
        let dir = std::env::temp_dir().join(format!("plugin-host-replay-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let index = r#"[{"method":"GET","url":"https://api.deezer.com/search?q=x","status":200,
            "headers":[["content-type","application/json"]],"body_file":"deezer_search.json"}]"#;
        std::fs::write(dir.join("index.json"), index).unwrap();
        std::fs::write(dir.join("deezer_search.json"), br#"{"data":[]}"#).unwrap();
        let (policy, list) = (NetPolicy::replay(&dir), allow(&["api.deezer.com"]));

        let (r, calls) = run(&policy, &list, req(Method::Get, "https://api.deezer.com/search?q=x")).await;
        let r = r.unwrap();
        assert_eq!((r.status, r.body.as_slice()), (200, &br#"{"data":[]}"#[..]));
        assert_eq!(r.headers, [("content-type".to_string(), "application/json".to_string())]);
        assert_eq!(calls, 1);

        let (r, _) = run(&policy, &list, req(Method::Get, "https://api.deezer.com/search?q=y")).await;
        match r {
            Err(HttpError::Network(m)) => {
                assert_eq!(m, "no recording for GET https://api.deezer.com/search?q=y")
            }
            other => panic!("{:?}", other.map(|r| r.status)),
        }
        let (r, _) = run(&policy, &list, req(Method::Get, "https://evil.com/search?q=x")).await;
        assert_eq!(denied(r), "evil.com not allowed");
    }
}
