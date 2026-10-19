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
    /// "1.0": the only value this host accepts (major 1, minor 0).
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

/// Parses and validates a manifest: id shape, contract version, domain syntax.
pub fn parse_manifest(json: &[u8]) -> Result<Manifest, String> {
    let manifest: Manifest = serde_json::from_slice(json).map_err(|e| e.to_string())?;
    validate_id(&manifest.id)?;
    validate_contract(&manifest.contract)?;
    Allowlist::new(&manifest.domains)?;
    Ok(manifest)
}

fn validate_id(id: &str) -> Result<(), String> {
    let bytes = id.as_bytes();
    let ok = (2..=40).contains(&bytes.len())
        && matches!(bytes[0], b'a'..=b'z' | b'0'..=b'9')
        && bytes.iter().all(|&b| matches!(b, b'a'..=b'z' | b'0'..=b'9' | b'-'));
    if ok { Ok(()) } else { Err(format!("invalid plugin id: {id:?}")) }
}

/// Only major 1, minor 0 is accepted by this host.
fn validate_contract(contract: &str) -> Result<(), String> {
    let (major, minor) = contract.split_once('.').ok_or_else(|| format!("invalid contract: {contract:?}"))?;
    let major: u32 = major.parse().map_err(|_| format!("invalid contract: {contract:?}"))?;
    let minor: u32 = minor.parse().map_err(|_| format!("invalid contract: {contract:?}"))?;
    if major == 1 && minor == 0 { Ok(()) } else { Err(format!("unsupported contract: {contract:?}")) }
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

/// Lowercase labels, letters/digits/hyphen only, no literal IP, no port.
fn validate_host(host: &str) -> Result<(), String> {
    if host.parse::<IpAddr>().is_ok() {
        return Err(format!("domain must not be a literal IP: {host:?}"));
    }
    let valid = !host.is_empty()
        && host
            .split('.')
            .all(|label| !label.is_empty() && label.bytes().all(|b| matches!(b, b'a'..=b'z' | b'0'..=b'9' | b'-')));
    if valid { Ok(()) } else { Err(format!("invalid domain: {host:?}")) }
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
        for domain in ["*", "*.com", "a.*.com", "127.0.0.1", "[::1]", "x.com:443", ""] {
            assert!(Allowlist::new(&[domain.into()]).is_err(), "{domain:?} should be rejected");
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
        assert!(bad("deezer", "1.1").is_err());
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
}
