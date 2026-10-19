//! HTTP cache key and TTL. Pure functions, consulted from `net::fetch`.

use contract::http::Request;
use sha2::{Digest, Sha256};

use crate::Capability;

const MIN_CATALOG_TTL_MS: u64 = 24 * 60 * 60 * 1000;

/// sha256 of plugin id, method, request URL and headers sorted by lowercase name, excluding
/// `user-agent` (a host-overridden UA must not split the cache).
pub(crate) fn cache_key(plugin: &str, req: &Request) -> [u8; 32] {
    let mut headers: Vec<(String, &str)> = req
        .headers
        .iter()
        .filter(|(k, _)| !k.eq_ignore_ascii_case("user-agent"))
        .map(|(k, v)| (k.to_ascii_lowercase(), v.as_str()))
        .collect();
    headers.sort();

    let mut hasher = Sha256::new();
    let mut field = |s: &str| {
        hasher.update((s.len() as u64).to_le_bytes());
        hasher.update(s.as_bytes());
    };
    field(plugin);
    field(format!("{:?}", req.method).as_str());
    field(&req.url);
    for (k, v) in &headers {
        field(k);
        field(v);
    }
    hasher.finalize().into()
}

/// `None` means "do not cache": `no-store`, or the `resolve` capability (streams are never
/// cached). Otherwise, for a catalogue capability (search/suggest/entity/lyrics/radio), at least
/// 24h regardless of a shorter `max-age`/`s-maxage` or a `no-cache` directive (spec: minimum 24h
/// for the catalogue).
pub(crate) fn ttl_ms(headers: &[(String, String)], capability: Capability) -> Option<u64> {
    if capability == Capability::Resolve {
        return None;
    }
    let cache_control =
        headers.iter().find(|(k, _)| k.eq_ignore_ascii_case("cache-control")).map_or("", |(_, v)| v.as_str());
    let directives: Vec<(&str, Option<&str>)> = cache_control
        .split(',')
        .map(|d| match d.trim().split_once('=') {
            Some((name, value)) => (name.trim(), Some(value.trim())),
            None => (d.trim(), None),
        })
        .collect();
    if directives.iter().any(|(name, _)| name.eq_ignore_ascii_case("no-store")) {
        return None;
    }
    let seconds = directives
        .iter()
        .find(|(name, _)| name.eq_ignore_ascii_case("s-maxage"))
        .or_else(|| directives.iter().find(|(name, _)| name.eq_ignore_ascii_case("max-age")))
        .and_then(|(_, v)| v.and_then(|v| v.parse::<u64>().ok()))
        .unwrap_or(0);
    Some((seconds * 1000).max(MIN_CATALOG_TTL_MS))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn headers(pairs: &[(&str, &str)]) -> Vec<(String, String)> {
        pairs.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect()
    }

    #[test]
    fn catalog_ttl_is_at_least_24h() {
        assert_eq!(ttl_ms(&headers(&[("cache-control", "max-age=60")]), Capability::Search), Some(86_400_000));
        assert_eq!(ttl_ms(&headers(&[("cache-control", "max-age=172800")]), Capability::Search), Some(172_800_000));
        assert_eq!(ttl_ms(&headers(&[]), Capability::Suggest), Some(86_400_000));
    }

    #[test]
    fn no_store_and_resolve_are_never_cached() {
        assert_eq!(ttl_ms(&headers(&[("cache-control", "no-store")]), Capability::Search), None);
        assert_eq!(ttl_ms(&headers(&[]), Capability::Resolve), None);
        assert_eq!(ttl_ms(&headers(&[("cache-control", "max-age=600")]), Capability::Resolve), None);
    }

    #[test]
    fn no_cache_is_ignored_for_the_catalog() {
        assert_eq!(ttl_ms(&headers(&[("cache-control", "no-cache")]), Capability::Entity), Some(86_400_000));
    }

    #[test]
    fn user_agent_is_excluded_and_header_order_does_not_matter() {
        use contract::http::Method;
        let a = Request {
            method: Method::Get,
            url: "https://api.test/x".into(),
            headers: vec![("User-Agent".into(), "a".into()), ("Accept".into(), "json".into())],
            body: None,
        };
        let b = Request {
            method: Method::Get,
            url: "https://api.test/x".into(),
            headers: vec![("Accept".into(), "json".into()), ("User-Agent".into(), "b".into())],
            body: None,
        };
        assert_eq!(cache_key("p", &a), cache_key("p", &b));
    }

    #[test]
    fn different_url_or_plugin_changes_the_key() {
        use contract::http::Method;
        let req = |url: &str| Request { method: Method::Get, url: url.into(), headers: vec![], body: None };
        assert_ne!(cache_key("p", &req("https://api.test/a")), cache_key("p", &req("https://api.test/b")));
        assert_ne!(cache_key("p", &req("https://api.test/a")), cache_key("q", &req("https://api.test/a")));
    }
}
