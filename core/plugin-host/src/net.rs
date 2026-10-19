//! Locked-down network for plugin HTTP and for URLs plugins return: https on the default
//! port, domain hosts in the manifest allowlist, public addresses only (checked on the address
//! actually connected to), redirects followed by hand and re-checked at every hop.

use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use contract::http::{HttpError, Method, Request, Response};
use reqwest::Url;
use reqwest::header::{HeaderMap, LOCATION, USER_AGENT};
use tokio::time::Instant;

use crate::manifest::{Allowlist, ends_in_number};
use crate::rate::RateLimiter;
use crate::storage::{CachedResponse, Storage};
use crate::Capability;

const MAX_REDIRECTS: u32 = 5;

/// Per-call HTTP budget: `max_http_calls` requests (every redirect hop counts as one) and
/// `max_http_bytes` of request-plus-response bodies. Lives in `State`, one per capability call,
/// shared (behind a `Mutex`) by every sequential `send` and every member of a concurrent batch.
pub(crate) struct HttpBudget {
    pub calls: u32,
    pub bytes: usize,
    pub hit: bool,
    max_calls: u32,
    max_bytes: usize,
}

impl HttpBudget {
    pub fn new(max_calls: u32, max_bytes: usize) -> Self {
        HttpBudget { calls: 0, bytes: 0, hit: false, max_calls, max_bytes }
    }

    /// Reserves one call and `body_len` request bytes, charged together so a request refused
    /// for its body size spends neither: a call slot and its body are only taken once the
    /// request is actually about to be sent.
    fn reserve_request(&mut self, body_len: usize) -> Result<(), HttpError> {
        if self.calls >= self.max_calls || self.bytes.saturating_add(body_len) > self.max_bytes {
            self.hit = true;
            return Err(HttpError::BudgetExceeded);
        }
        self.calls += 1;
        self.bytes += body_len;
        Ok(())
    }

    /// Response bytes, charged as they stream in (see `read`): the chunk that trips this is
    /// still counted, so the running total is accurate even for a response that errors out
    /// mid-body — no bytes a plugin actually received ever go uncounted.
    fn add_response_bytes(&mut self, n: usize) -> Result<(), HttpError> {
        self.bytes += n;
        if self.bytes > self.max_bytes {
            self.hit = true;
            return Err(HttpError::BudgetExceeded);
        }
        Ok(())
    }
}

#[derive(Clone)]
pub struct NetPolicy {
    /// For plugin `fetch`: no automatic redirects, `fetch` follows and checks them.
    client: reqwest::Client,
    resolver: Resolver,
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
        let client = builder(resolver).redirect(reqwest::redirect::Policy::none()).build().expect("http client");
        NetPolicy {
            client,
            resolver,
            strict_urls,
            #[cfg(any(test, feature = "test-util"))]
            replay: None,
        }
    }

    /// Safe by construction for the core's own fetches of URLs a plugin returned: every
    /// connection and every redirect (max 5) goes through `check` with `allow`, and DNS
    /// answers through the filtering resolver.
    pub(crate) fn client_for(&self, allow: Arc<Allowlist>) -> reqwest::Client {
        let (policy, list) = (self.clone(), allow.clone());
        let redirect = reqwest::redirect::Policy::custom(move |attempt| {
            // `previous` starts with the initial URL.
            if attempt.previous().len() > MAX_REDIRECTS as usize {
                return attempt.error("too many redirects");
            }
            match policy.check(&list, attempt.url()) {
                Ok(()) => attempt.follow(),
                Err(e) => attempt.error(DeniedAddress(e)),
            }
        });
        let gate = tower::filter::FilterLayer::new(gate(self.clone(), allow));
        builder(self.resolver).redirect(redirect).connector_layer(gate).build().expect("http client")
    }

    /// http and any port allowed; `rebind.test` resolves to 10.0.0.1 (refused), any other
    /// `*.test` to 127.0.0.1 (loopback allowed in this policy only), anything else fails.
    #[cfg(any(test, feature = "test-util"))]
    pub fn for_tests() -> NetPolicy {
        NetPolicy::new(Resolver { lookup: Lookup::Test, allow_loopback: true }, false)
    }

    /// Serves `dir/index.json` recordings, never the network; URL checks as strict as `default()`.
    #[cfg(any(test, feature = "test-util"))]
    pub fn replay(dir: &std::path::Path) -> NetPolicy {
        let mut policy = NetPolicy::new(Resolver { lookup: Lookup::Nothing, allow_loopback: false }, true);
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

fn builder(resolver: Resolver) -> reqwest::ClientBuilder {
    reqwest::Client::builder().no_proxy().timeout(Duration::from_secs(20)).dns_resolver(Arc::new(resolver))
}

type BoxError = Box<dyn std::error::Error + Send + Sync>;

/// Connector predicate: `check` on every new connection's destination. reqwest hides that
/// destination in a sealed type whose only accessor is `Debug` (`Unnameable(<uri>)`), so it is
/// parsed from there; an unexpected shape refuses the connection.
fn gate<R: std::fmt::Debug>(policy: NetPolicy, allow: Arc<Allowlist>) -> impl Fn(R) -> Result<R, BoxError> + Clone {
    move |dst| {
        let debug = format!("{dst:?}");
        let uri = debug.split_once('(').and_then(|(_, rest)| rest.strip_suffix(')'));
        let url = uri
            .and_then(|u| Url::parse(u).ok())
            .ok_or_else(|| DeniedAddress(format!("unreadable destination {debug}")))?;
        policy.check(&allow, &url).map_err(DeniedAddress)?;
        Ok(dst)
    }
}

/// Keeps only public addresses (plus loopback when allowed); none left → `Denied`.
#[derive(Clone, Copy)]
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

/// Context for the per-call HTTP cache: only passed for a plugin's own `send`/`send_batch`,
/// never for the core's own fetches of URLs a plugin returned (`Host::http_client`).
#[derive(Clone, Copy)]
pub(crate) struct CacheCtx<'a> {
    pub(crate) storage: &'a dyn Storage,
    pub(crate) plugin: &'a str,
    pub(crate) capability: Capability,
}

/// 2 MiB: bodies larger than this are never cached (but can still be fetched, up to the call's
/// own response-size budget).
const MAX_CACHED_BODY: usize = 2 << 20;

/// Same as `fetch_uncached`, but for a `GET` outside the `resolve` capability, first consults
/// `cache`: a hit (not expired) is returned with no network call, no budget or rate-limit token
/// spent. A miss falls through to the network; a 2xx response within `MAX_CACHED_BODY` and a
/// non-`None` `cache::ttl_ms` is then stored. On a network error (not an HTTP error status, not
/// `Denied`), an expired entry — if one exists — is served instead of the error (offline).
#[allow(clippy::too_many_arguments)] // one more than `fetch_uncached`: the cache context.
pub(crate) async fn fetch(
    policy: &NetPolicy,
    allow: &Allowlist,
    req: Request,
    max_body: usize,
    budget: &Mutex<HttpBudget>,
    rate_limiter: Option<(&RateLimiter, Instant)>,
    user_agent: Option<&str>,
    cache: Option<CacheCtx<'_>>,
) -> Result<Response, HttpError> {
    let cache = cache.filter(|c| matches!(req.method, Method::Get) && c.capability != Capability::Resolve);
    let key = cache.map(|c| crate::cache::cache_key(c.plugin, &req));
    let cached = match (cache, key) {
        (Some(c), Some(key)) => c.storage.cache_get(&key),
        _ => None,
    };
    if let Some(entry) = &cached
        && entry.expires_at_ms > now_ms()
    {
        return Ok(cached_response(entry));
    }

    match fetch_uncached(policy, allow, req, max_body, budget, rate_limiter, user_agent).await {
        Ok(response) => {
            if let (Some(c), Some(key)) = (cache, key) {
                store_if_cacheable(c, &key, &response);
            }
            Ok(response)
        }
        Err(e @ (HttpError::Network(_) | HttpError::Timeout)) => {
            cached.map_or(Err(e), |entry| Ok(cached_response(&entry)))
        }
        Err(e) => Err(e),
    }
}

fn cached_response(entry: &CachedResponse) -> Response {
    Response { status: entry.status, url: entry.url.clone(), headers: entry.headers.clone(), body: entry.body.clone() }
}

fn store_if_cacheable(cache: CacheCtx<'_>, key: &[u8; 32], response: &Response) {
    if !(200..300).contains(&response.status) || response.body.len() > MAX_CACHED_BODY {
        return;
    }
    let Some(ttl) = crate::cache::ttl_ms(&response.headers, cache.capability) else { return };
    let now = now_ms();
    cache.storage.cache_put(
        key,
        &CachedResponse {
            plugin: cache.plugin.to_string(),
            status: response.status,
            url: response.url.clone(),
            headers: response.headers.clone(),
            body: response.body.clone(),
            stored_at_ms: now,
            expires_at_ms: now + ttl,
        },
    );
}

fn now_ms() -> u64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_millis() as u64)
}

/// Sends `req` under `policy` and `allow`, following up to 5 redirects by hand. Every hop is
/// charged to `budget` (one call, plus the request bytes it sends; the response's bytes are
/// charged inside `read` as they arrive) and, when `rate_limiter` is set, waits for a slot
/// first — or fails fast if that wait would run past the paired deadline. `user_agent`, when
/// set, overrides any plugin-set `User-Agent` for every hop; when `None` the plugin's own
/// header (if any) is left alone.
async fn fetch_uncached(
    policy: &NetPolicy,
    allow: &Allowlist,
    req: Request,
    max_body: usize,
    budget: &Mutex<HttpBudget>,
    rate_limiter: Option<(&RateLimiter, Instant)>,
    user_agent: Option<&str>,
) -> Result<Response, HttpError> {
    let mut url = Url::parse(&req.url).map_err(|e| HttpError::Denied(format!("{}: {e}", req.url)))?;
    let mut method = req.method;
    let mut headers = req.headers;
    // A plugin never sets framing or routing headers: `Host` would front past the allowlist.
    headers.retain(|(k, _)| {
        let k = k.to_ascii_lowercase();
        !matches!(k.as_str(), "host" | "connection" | "transfer-encoding" | "te" | "upgrade" | "content-length")
            && !k.starts_with("proxy-")
    });
    if let Some(ua) = user_agent {
        headers.retain(|(k, _)| !k.eq_ignore_ascii_case(USER_AGENT.as_str()));
        headers.push((USER_AGENT.as_str().to_string(), ua.to_string()));
    }
    let mut body = req.body;
    let mut redirects = 0;
    loop {
        policy.check(allow, &url).map_err(HttpError::Denied)?;
        budget.lock().unwrap().reserve_request(body.as_ref().map_or(0, Vec::len))?;
        if let Some((rate_limiter, deadline)) = rate_limiter
            && rate_limiter.acquire(deadline).await.is_err()
        {
            budget.lock().unwrap().hit = true;
            return Err(HttpError::BudgetExceeded);
        }
        let hop = send(policy, method, &url, &headers, body.clone()).await?;
        let redirect = matches!(hop.status, 301..=303 | 307 | 308);
        let location = redirect.then(|| header(&hop.headers, LOCATION.as_str())).flatten();
        let Some(location) = location else {
            return read(hop, url, max_body, budget).await;
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

/// Reads the body as a stream and stops at `max` for this response. Every chunk received is
/// also charged to the call's cumulative `budget` as it arrives — including the chunk that
/// trips `TooLarge` or a mid-body network error — so a response that fails partway through
/// still pays for what it actually transferred (no byte a plugin received goes uncounted).
async fn read(hop: Hop, url: Url, max: usize, budget: &Mutex<HttpBudget>) -> Result<Response, HttpError> {
    let body = match hop.body {
        Body::Live(mut resp) => {
            if resp.content_length().is_some_and(|n| n > max as u64) {
                return Err(HttpError::TooLarge);
            }
            let mut body = Vec::new();
            while let Some(chunk) = resp.chunk().await.map_err(net_error)? {
                // Charged before the size check: the chunk that trips `TooLarge` was still
                // received over the wire and must count, even though it's then discarded.
                budget.lock().unwrap().add_response_bytes(chunk.len())?;
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
        Body::Recorded(body) => {
            budget.lock().unwrap().add_response_bytes(body.len())?;
            body
        }
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
    use crate::storage::MemoryStorage;

    fn allow(domains: &[&str]) -> Allowlist {
        Allowlist::new(&domains.iter().map(|d| d.to_string()).collect::<Vec<_>>()).unwrap()
    }

    fn req(m: Method, url: &str) -> Request {
        Request { method: m, url: url.into(), headers: vec![], body: None }
    }

    async fn run(policy: &NetPolicy, allow: &Allowlist, req: Request) -> (Result<Response, HttpError>, u32) {
        let budget = Mutex::new(HttpBudget::new(u32::MAX, usize::MAX));
        let r = fetch(policy, allow, req, 8 << 20, &budget, None, None, None).await;
        (r, budget.into_inner().unwrap().calls)
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
    async fn plugin_host_header_is_ignored() {
        let server = MockServer::start().await;
        Mock::given(path("/")).respond_with(ResponseTemplate::new(200)).mount(&server).await;
        let headers = ["Host", "Connection", "Transfer-Encoding", "TE", "Upgrade", "Proxy-Foo"]
            .map(|k| (k.to_string(), "exfil.example".to_string()))
            .to_vec();
        let r = Request { headers, ..req(Method::Get, &format!("{}/", base(&server, "api.test"))) };
        let (r, _) = run(&NetPolicy::for_tests(), &allow(&["api.test"]), r).await;
        assert_eq!(r.unwrap().status, 200);
        let got = server.received_requests().await.unwrap();
        let h = &got[0].headers;
        assert_eq!(h.get("host").unwrap(), &format!("api.test:{}", server.address().port()));
        for k in ["connection", "transfer-encoding", "te", "upgrade", "proxy-foo"] {
            assert!(h.get(k).is_none_or(|v| v != "exfil.example"), "{k} forwarded");
        }
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
        let (r, _) = run(&policy, &list, req(Method::Get, "http://api.deezer.com/search?q=x")).await;
        assert_eq!(denied(r), "scheme not allowed: http");
        let (r, _) = run(&policy, &list, req(Method::Get, "https://api.deezer.com:8443/search?q=x")).await;
        assert_eq!(denied(r), "port not allowed: 8443");
    }

    #[tokio::test]
    async fn request_body_is_charged_only_when_sent() {
        let server = MockServer::start().await;
        Mock::given(method("POST")).respond_with(ResponseTemplate::new(200)).mount(&server).await;
        let (policy, list) = (NetPolicy::for_tests(), allow(&["api.test"]));
        let budget = Mutex::new(HttpBudget::new(10, 5));
        let url = base(&server, "api.test");
        let big = Request { body: Some(vec![b'x'; 6]), ..req(Method::Post, &url) };
        match fetch(&policy, &list, big, 8 << 20, &budget, None, None, None).await {
            Err(HttpError::BudgetExceeded) => {}
            other => panic!("{:?}", other.map(|r| r.status)),
        }
        {
            let b = budget.lock().unwrap();
            assert_eq!((b.calls, b.bytes), (0, 0), "a request refused for its body size spends no call and no bytes");
        }
        let small = Request { body: Some(vec![b'x'; 5]), ..req(Method::Post, &url) };
        let r = fetch(&policy, &list, small, 8 << 20, &budget, None, None, None).await;
        assert_eq!(r.unwrap().status, 200);
        assert_eq!(budget.lock().unwrap().calls, 1);
        assert_eq!(server.received_requests().await.unwrap().len(), 1, "only the fitting request was ever sent");
    }

    #[tokio::test]
    async fn each_redirect_hop_charges_one_call_and_its_bytes() {
        let server = MockServer::start().await;
        let api = base(&server, "api.test");
        // 307/308 keep the method and body across the hop, unlike 301-303.
        redirect(&server, "/a", 307, &format!("{api}/b")).await;
        redirect(&server, "/b", 307, &format!("{api}/c")).await;
        let body = vec![b'y'; 100];
        Mock::given(path("/c")).respond_with(ResponseTemplate::new(200).set_body_bytes(body)).mount(&server).await;
        let (policy, list) = (NetPolicy::for_tests(), allow(&["api.test"]));
        let budget = Mutex::new(HttpBudget::new(10, 1 << 20));
        let post = Request { body: Some(vec![b'x'; 10]), ..req(Method::Post, &format!("{api}/a")) };
        let r = fetch(&policy, &list, post, 8 << 20, &budget, None, None, None).await;
        assert_eq!(r.unwrap().status, 200);
        let b = budget.lock().unwrap();
        assert_eq!(b.calls, 3, "one call per hop, redirects included");
        assert_eq!(b.bytes, 10 * 3 + 100, "the resent 10-byte body is charged on every hop, the response once");
    }

    /// Writes `n` 1 MiB chunked-encoding frames on `sock`, stopping early if the peer has
    /// already gone away (the client aborting mid-stream once a cap trips).
    async fn write_chunks(sock: &mut tokio::net::TcpStream, n: usize) {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        let mut buf = [0u8; 4096];
        let _ = sock.read(&mut buf).await;
        if sock.write_all(b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n").await.is_err() {
            return;
        }
        let chunk = vec![b'x'; 1 << 20];
        for _ in 0..n {
            let head = format!("{:x}\r\n", chunk.len());
            if sock.write_all(head.as_bytes()).await.is_err()
                || sock.write_all(&chunk).await.is_err()
                || sock.write_all(b"\r\n").await.is_err()
            {
                break;
            }
        }
    }

    /// Previously, bytes streamed before a `TooLarge`/network error were never charged, so a
    /// chunked response (no `Content-Length`, so the cap can only be enforced while streaming)
    /// that fails partway through left the budget untouched no matter how much it had already
    /// transferred. Charging each chunk as it arrives — even the one that trips the error —
    /// fixes that.
    #[tokio::test]
    async fn byte_budget_counts_partial_bodies() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let server = tokio::spawn(async move {
            let (mut sock, _) = listener.accept().await.unwrap();
            write_chunks(&mut sock, 16).await;
        });
        let (policy, list) = (NetPolicy::for_tests(), allow(&["api.test"]));
        let budget = Mutex::new(HttpBudget::new(10, 1 << 30));
        let url = format!("http://api.test:{port}/");
        match fetch(&policy, &list, req(Method::Get, &url), 8 << 20, &budget, None, None, None).await {
            Err(HttpError::TooLarge) => {}
            other => panic!("{:?}", other.map(|r| r.status)),
        }
        let charged = budget.lock().unwrap().bytes;
        assert!(charged >= 8 << 20, "{charged}: the ~9 MiB streamed before TooLarge must still be charged");
        let _ = server.await;
    }

    /// With most of the call's 16 MiB budget already spent (simulating earlier calls in the
    /// same capability call), a chunked response that would otherwise run to its own 8 MiB cap
    /// is cut off as soon as the cumulative total passes 16 MiB — within about one more chunk,
    /// not after streaming far beyond it.
    #[tokio::test]
    async fn cumulative_budget_cuts_a_chunked_response_short() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let server = tokio::spawn(async move {
            let (mut sock, _) = listener.accept().await.unwrap();
            write_chunks(&mut sock, 16).await;
        });
        let (policy, list) = (NetPolicy::for_tests(), allow(&["api.test"]));
        let budget = Mutex::new(HttpBudget { calls: 2, bytes: 15 << 20, hit: false, max_calls: 24, max_bytes: 16 << 20 });
        let url = format!("http://api.test:{port}/");
        match fetch(&policy, &list, req(Method::Get, &url), 8 << 20, &budget, None, None, None).await {
            Err(HttpError::BudgetExceeded) => {}
            other => panic!("{:?}", other.map(|r| r.status)),
        }
        let bytes = budget.lock().unwrap().bytes;
        assert!(bytes < (16 << 20) + (2 << 20), "{bytes}: should stop within about one chunk past the 16 MiB cap");
        let _ = server.await;
    }

    async fn run_cached(
        policy: &NetPolicy,
        allow: &Allowlist,
        req: Request,
        cache: CacheCtx<'_>,
    ) -> Result<Response, HttpError> {
        let budget = Mutex::new(HttpBudget::new(u32::MAX, usize::MAX));
        fetch(policy, allow, req, 8 << 20, &budget, None, None, Some(cache)).await
    }

    #[tokio::test]
    async fn get_is_served_from_cache() {
        let server = MockServer::start().await;
        let resp = ResponseTemplate::new(200).insert_header("cache-control", "max-age=60");
        Mock::given(method("GET")).respond_with(resp).mount(&server).await;
        let (policy, list) = (NetPolicy::for_tests(), allow(&["api.test"]));
        let storage = MemoryStorage::default();
        let cache = CacheCtx { storage: &storage, plugin: "p", capability: Capability::Search };
        let url = format!("{}/x", base(&server, "api.test"));

        assert_eq!(run_cached(&policy, &list, req(Method::Get, &url), cache).await.unwrap().status, 200);
        assert_eq!(run_cached(&policy, &list, req(Method::Get, &url), cache).await.unwrap().status, 200);
        assert_eq!(server.received_requests().await.unwrap().len(), 1, "the second GET must be served from cache");
    }

    #[tokio::test]
    async fn resolve_never_hits_cache() {
        let server = MockServer::start().await;
        let resp = ResponseTemplate::new(200).insert_header("cache-control", "max-age=60");
        Mock::given(method("GET")).respond_with(resp).mount(&server).await;
        let (policy, list) = (NetPolicy::for_tests(), allow(&["api.test"]));
        let storage = MemoryStorage::default();
        let cache = CacheCtx { storage: &storage, plugin: "p", capability: Capability::Resolve };
        let url = format!("{}/x", base(&server, "api.test"));

        run_cached(&policy, &list, req(Method::Get, &url), cache).await.unwrap();
        run_cached(&policy, &list, req(Method::Get, &url), cache).await.unwrap();
        assert_eq!(server.received_requests().await.unwrap().len(), 2, "resolve always goes to the network");
    }

    /// An expired entry, seeded directly through `Storage` (24h is the catalogue's own minimum
    /// TTL, so a test cannot wait for a real one to expire), is served once nothing answers on
    /// that port any more — a network error, not an HTTP error status or a `Denied`.
    #[tokio::test]
    async fn stale_cache_served_when_offline() {
        // Bound, then immediately dropped: the port is free but nothing is listening, so a
        // connection attempt gets a prompt `ECONNREFUSED` instead of racing a server's shutdown.
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        drop(listener);
        let url = format!("http://api.test:{port}/x");

        let (policy, list) = (NetPolicy::for_tests(), allow(&["api.test"]));
        let storage = MemoryStorage::default();
        let key = crate::cache::cache_key("p", &req(Method::Get, &url));
        storage.cache_put(
            &key,
            &CachedResponse {
                plugin: "p".into(),
                status: 200,
                url: url.clone(),
                headers: vec![],
                body: b"stale-ok".to_vec(),
                stored_at_ms: 0,
                expires_at_ms: 1,
            },
        );

        let cache = CacheCtx { storage: &storage, plugin: "p", capability: Capability::Search };
        let resp = run_cached(&policy, &list, req(Method::Get, &url), cache).await.unwrap();
        assert_eq!(resp.body, b"stale-ok");
    }

    #[tokio::test]
    async fn fresh_responses_above_2mib_are_not_cached() {
        let server = MockServer::start().await;
        let body = vec![b'x'; (2 << 20) + 1];
        let resp = ResponseTemplate::new(200).insert_header("cache-control", "max-age=60").set_body_bytes(body);
        Mock::given(method("GET")).respond_with(resp).mount(&server).await;
        let (policy, list) = (NetPolicy::for_tests(), allow(&["api.test"]));
        let storage = MemoryStorage::default();
        let cache = CacheCtx { storage: &storage, plugin: "p", capability: Capability::Search };
        let url = format!("{}/x", base(&server, "api.test"));

        run_cached(&policy, &list, req(Method::Get, &url), cache).await.unwrap();
        run_cached(&policy, &list, req(Method::Get, &url), cache).await.unwrap();
        assert_eq!(server.received_requests().await.unwrap().len(), 2, "too large to cache: every GET hits the network");
    }
}
