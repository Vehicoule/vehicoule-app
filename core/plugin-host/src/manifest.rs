//! Plugin manifest: parsed and validated once at install/load time, before the plugin ever
//! runs. `domains` feeds `Allowlist`, checked on every outgoing HTTP request (task 3).

use std::collections::HashSet;
use std::net::IpAddr;

use serde::Deserialize;

#[derive(Debug, Clone, Deserialize)]
pub struct Manifest {
    pub id: String,
    pub name: String,
    pub version: String,
    /// "1.0" or "1.1": the values this host accepts (major 1, minor 0 or 1).
    pub contract: String,
    pub domains: Vec<String>,
    pub rate_limit: Option<RateLimit>,
    #[serde(default)]
    pub descriptive_user_agent: bool,
}

#[derive(Debug, Clone, Copy, Deserialize)]
pub struct RateLimit {
    pub requests: u32,
    pub per_seconds: u32,
}

/// Upper bound on `rate_limit.requests`: the limiter keeps one timestamp per request in the
/// window, so an unbounded manifest value is an unbounded allocation.
const MAX_RATE_REQUESTS: u32 = 10_000;

/// Parses and validates a manifest: id shape, contract version, domain syntax, rate limit.
pub fn parse_manifest(json: &[u8]) -> Result<Manifest, String> {
    let manifest: Manifest = serde_json::from_slice(json).map_err(|e| e.to_string())?;
    validate_id(&manifest.id)?;
    validate_contract(&manifest.contract)?;
    Allowlist::new(&manifest.domains)?;
    if let Some(rl) = manifest.rate_limit
        && (rl.requests == 0 || rl.per_seconds == 0)
    {
        return Err(format!("rate_limit requests and per_seconds must both be nonzero: {rl:?}"));
    }
    if let Some(rl) = manifest.rate_limit
        && rl.requests > MAX_RATE_REQUESTS
    {
        return Err(format!("rate_limit requests must be at most {MAX_RATE_REQUESTS}: {rl:?}"));
    }
    Ok(manifest)
}

pub(crate) fn validate_id(id: &str) -> Result<(), String> {
    let bytes = id.as_bytes();
    let ok = (2..=40).contains(&bytes.len())
        && matches!(bytes[0], b'a'..=b'z' | b'0'..=b'9')
        && bytes.iter().all(|&b| matches!(b, b'a'..=b'z' | b'0'..=b'9' | b'-'));
    if ok { Ok(()) } else { Err(format!("invalid plugin id: {id:?}")) }
}

/// Major 1, minor 0 or 1: a 1.0 plugin loads under the 1.1 contract (1.1 only adds `browse`).
pub(crate) fn validate_contract(contract: &str) -> Result<(), String> {
    let (major, minor) = contract.split_once('.').ok_or_else(|| format!("invalid contract: {contract:?}"))?;
    let major: u32 = major.parse().map_err(|_| format!("invalid contract: {contract:?}"))?;
    let minor: u32 = minor.parse().map_err(|_| format!("invalid contract: {contract:?}"))?;
    if major == 1 && minor <= 1 {
        Ok(())
    } else {
        Err(format!("unsupported contract: {contract:?}"))
    }
}

/// Domains an installed plugin may reach over HTTP: exact hosts or `*.`-prefixed suffixes.
pub struct Allowlist {
    exact: HashSet<String>,
    suffixes: Vec<String>,
}

impl Allowlist {
    pub fn new(domains: &[String]) -> Result<Allowlist, String> {
        let mut exact = HashSet::new();
        let mut suffixes = Vec::new();
        for domain in domains {
            let lower = domain.to_ascii_lowercase();
            match lower.strip_prefix("*.") {
                Some(suffix) => {
                    validate_host(suffix)?;
                    if suffix.split('.').count() < 2 {
                        return Err(format!("wildcard needs at least two labels: {domain:?}"));
                    }
                    suffixes.push(suffix.to_string());
                }
                None => {
                    validate_host(&lower)?;
                    exact.insert(lower);
                }
            }
        }
        Ok(Allowlist { exact, suffixes })
    }

    /// Case-insensitive, ignores a trailing dot.
    pub fn allows(&self, host: &str) -> bool {
        let host = host.trim_end_matches('.').to_ascii_lowercase();
        if self.exact.contains(&host) {
            return true;
        }
        self.suffixes.iter().any(|suffix| {
            host.len() > suffix.len()
                && host.ends_with(suffix.as_str())
                && host.as_bytes()[host.len() - suffix.len() - 1] == b'.'
        })
    }
}

/// Lowercase labels, letters/digits/hyphen only, no literal IP, no port, no disguised IP.
fn validate_host(host: &str) -> Result<(), String> {
    if host.parse::<IpAddr>().is_ok() {
        return Err(format!("domain must not be a literal IP: {host:?}"));
    }
    let valid = !host.is_empty()
        && host
            .split('.')
            .all(|label| !label.is_empty() && label.bytes().all(|b| matches!(b, b'a'..=b'z' | b'0'..=b'9' | b'-')));
    if !valid {
        return Err(format!("invalid domain: {host:?}"));
    }
    if ends_in_number(host) {
        return Err(format!("domain must not end in a number (disguised IP): {host:?}"));
    }
    Ok(())
}

/// WHATWG URL's "ends in a number" rule: the last label is all decimal digits, or `0x`/`0X`
/// followed by zero or more hex digits (octal, e.g. `017`, is covered by the all-digits case).
/// This is exactly what the `url` crate would fold into a literal IPv4, e.g. `1.2.3.4`,
/// `2130706433`, `017.0.0.1`, `0x7f.0x0.0x0.0x1`. Reused by task 3 for request hosts.
pub(crate) fn ends_in_number(host: &str) -> bool {
    let last = host.rsplit('.').next().unwrap_or("");
    if let Some(hex) = last.strip_prefix("0x").or_else(|| last.strip_prefix("0X")) {
        return hex.bytes().all(|b| b.is_ascii_hexdigit());
    }
    !last.is_empty() && last.bytes().all(|b| b.is_ascii_digit())
}

#[cfg(test)]
mod tests {
    use super::*;

    const EXAMPLE: &[u8] = br#"{"id":"deezer","name":"Deezer","version":"1.0.0","contract":"1.0","domains":["api.deezer.com","*.dzcdn.net"],"rate_limit":{"requests":45,"per_seconds":5}}"#;

    #[test]
    fn wildcard_matches_subdomains_only() {
        let list = Allowlist::new(&["*.googlevideo.com".into()]).unwrap();
        assert!(list.allows("rr1---sn-x.googlevideo.com"));
        assert!(list.allows("a.b.googlevideo.com"));
        assert!(!list.allows("googlevideo.com"));
        assert!(!list.allows("evilgooglevideo.com"));
    }

    #[test]
    fn exact_domain_is_case_insensitive() {
        let list = Allowlist::new(&["api.deezer.com".into()]).unwrap();
        assert!(list.allows("API.Deezer.com."));
    }

    #[test]
    fn invalid_domains_are_rejected() {
        for domain in [
            "*",
            "*.com",
            "a.*.com",
            "127.0.0.1",
            "[::1]",
            "x.com:443",
            "",
            "0x7f.1",
            "2130706433",
            "017.0.0.1",
            "0x7f.0x0.0x0.0x1",
            "1.2.3.4",
        ] {
            assert!(Allowlist::new(&[domain.into()]).is_err(), "{domain:?} should be rejected");
        }
    }

    #[test]
    fn hosts_that_merely_contain_digits_are_accepted() {
        for domain in ["123.example.com", "x0.example.com"] {
            assert!(Allowlist::new(&[domain.into()]).is_ok(), "{domain:?} should be accepted");
        }
    }

    #[test]
    fn manifest_rejects_bad_id_and_contract() {
        let bad = |id: &str, contract: &str| {
            let json = format!(
                r#"{{"id":"{id}","name":"x","version":"1.0.0","contract":"{contract}","domains":["x.com"]}}"#
            );
            parse_manifest(json.as_bytes())
        };
        assert!(bad("Deezer", "1.0").is_err());
        assert!(bad("-x", "1.0").is_err());
        assert!(bad("deezer", "2.0").is_err());
        assert!(bad("deezer", "1.2").is_err());
        assert!(bad("deezer", "1.1").is_ok());
        assert!(bad("deezer", "1.0").is_ok());
    }

    #[test]
    fn manifest_parses_example() {
        let manifest = parse_manifest(EXAMPLE).unwrap();
        assert_eq!(manifest.id, "deezer");
        assert_eq!(manifest.domains, vec!["api.deezer.com", "*.dzcdn.net"]);
        assert_eq!(manifest.rate_limit.unwrap().requests, 45);
        assert_eq!(manifest.rate_limit.unwrap().per_seconds, 5);
        assert!(!manifest.descriptive_user_agent);
    }

    #[test]
    fn rate_limit_zero_values_are_rejected() {
        let with = |requests: u32, per_seconds: u32| {
            format!(
                r#"{{"id":"xx","name":"x","version":"1.0.0","contract":"1.0","domains":["x.com"],"rate_limit":{{"requests":{requests},"per_seconds":{per_seconds}}}}}"#
            )
        };
        assert!(parse_manifest(with(0, 5).as_bytes()).is_err());
        assert!(parse_manifest(with(5, 0).as_bytes()).is_err());
        assert!(parse_manifest(with(0, 0).as_bytes()).is_err());
        assert!(parse_manifest(with(5, 5).as_bytes()).is_ok());
    }

    #[test]
    fn rate_limit_requests_are_bounded() {
        let with = |requests: u32| {
            format!(
                r#"{{"id":"xx","name":"x","version":"1.0.0","contract":"1.0","domains":["x.com"],"rate_limit":{{"requests":{requests},"per_seconds":5}}}}"#
            )
        };
        assert!(parse_manifest(with(10_000).as_bytes()).is_ok());
        assert!(parse_manifest(with(10_001).as_bytes()).is_err());
        assert!(parse_manifest(with(u32::MAX).as_bytes()).is_err());
    }
}
