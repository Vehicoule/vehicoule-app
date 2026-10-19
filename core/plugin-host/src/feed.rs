//! Signed plugin feeds: ed25519 signature over the exact JSON payload bytes (no
//! canonicalisation), monotonic `sequence` (equal accepted, lower refused), and sha256
//! checks for the `.wasm` and manifest a feed entry points at.

use std::collections::HashSet;

use base64::Engine as _;
use base64::engine::general_purpose::STANDARD as BASE64;
use ed25519_dalek::{Signature, Signer, SigningKey, VerifyingKey};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Feed {
    pub name: String,
    pub sequence: u64,
    pub plugins: Vec<FeedEntry>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct FeedEntry {
    pub id: String,
    pub version: String,
    pub contract: String,
    /// Relative to the feed are allowed; resolved by `core` later.
    pub wasm_url: String,
    pub wasm_sha256: String,
    pub manifest_url: String,
    pub manifest_sha256: String,
}

#[derive(Debug, PartialEq)]
pub enum FeedError {
    Malformed(String),
    BadSignature,
    Rollback { seen: u64, got: u64 },
}

/// On-disk/wire envelope: `payload` is base64 of the exact `Feed` JSON bytes that were
/// signed; each signature covers those bytes verbatim.
#[derive(Serialize, Deserialize)]
struct Envelope {
    payload: String,
    signatures: Vec<SigEntry>,
}

#[derive(Serialize, Deserialize)]
struct SigEntry {
    key: String,
    sig: String,
}

/// Parses and validates a signed feed: envelope shape, a signature from a trusted key over
/// the exact payload bytes (`verify_strict`, rejects malleable/small-order signatures), no
/// duplicate plugin ids, no absolute non-https URL, and sequence not older than `last_sequence`.
pub fn verify_feed(bytes: &[u8], trusted: &[[u8; 32]], last_sequence: Option<u64>) -> Result<Feed, FeedError> {
    let envelope: Envelope = serde_json::from_slice(bytes).map_err(|e| FeedError::Malformed(e.to_string()))?;
    let payload = BASE64.decode(&envelope.payload).map_err(|e| FeedError::Malformed(e.to_string()))?;

    let signed_by_trusted_key = envelope.signatures.iter().any(|entry| {
        let Ok(key_bytes) = BASE64.decode(&entry.key) else { return false };
        let Ok(key_bytes): Result<[u8; 32], _> = key_bytes.try_into() else { return false };
        if !trusted.contains(&key_bytes) {
            return false;
        }
        let Ok(sig_bytes) = BASE64.decode(&entry.sig) else { return false };
        let Ok(signature) = Signature::try_from(sig_bytes.as_slice()) else { return false };
        let Ok(verifying_key) = VerifyingKey::from_bytes(&key_bytes) else { return false };
        verifying_key.verify_strict(&payload, &signature).is_ok()
    });
    if !signed_by_trusted_key {
        return Err(FeedError::BadSignature);
    }

    let feed: Feed = serde_json::from_slice(&payload).map_err(|e| FeedError::Malformed(e.to_string()))?;

    let mut seen_ids = HashSet::new();
    for plugin in &feed.plugins {
        if !seen_ids.insert(plugin.id.as_str()) {
            return Err(FeedError::Malformed(format!("duplicate plugin id: {}", plugin.id)));
        }
        for url in [&plugin.wasm_url, &plugin.manifest_url] {
            if has_disallowed_url_chars(url) {
                return Err(FeedError::Malformed(format!("control/space/backslash in url: {url:?}")));
            }
            if is_absolute_non_https(url) {
                return Err(FeedError::Malformed(format!("absolute non-https url: {url:?}")));
            }
        }
    }

    if let Some(last) = last_sequence
        && feed.sequence < last
    {
        return Err(FeedError::Rollback { seen: last, got: feed.sequence });
    }
    Ok(feed)
}

/// WHATWG URL parsing strips ASCII tabs/newlines, strips every other ASCII control
/// character and space, and normalizes `\` to `/` in `http(s)` URLs before resolving. A
/// scheme check that runs on the raw string before this would see e.g. `" http://evil/x"`
/// or `"ht\ttp://evil/x"` as having no valid `scheme:` prefix and wave it through as
/// relative, while a browser/resolver would reach `http://evil/x`. Refuse outright instead.
fn has_disallowed_url_chars(url: &str) -> bool {
    url.bytes().any(|b| b.is_ascii_control() || b == b' ' || b == b'\\')
}

/// True for an absolute URL (has a `scheme:` prefix per RFC 3986) whose scheme isn't https.
/// A relative URL (no scheme) is not absolute, so this returns false for it.
fn is_absolute_non_https(url: &str) -> bool {
    let Some(colon) = url.find(':') else { return false };
    let scheme = &url[..colon];
    let is_scheme = scheme.as_bytes().first().is_some_and(u8::is_ascii_alphabetic)
        && scheme.bytes().all(|b| b.is_ascii_alphanumeric() || matches!(b, b'+' | b'-' | b'.'));
    is_scheme && !scheme.eq_ignore_ascii_case("https")
}

/// Serialises `feed` with serde_json and signs those exact bytes; the result is the
/// `feed.json` payload+signature envelope, ready to write to disk.
pub fn sign_feed(feed: &Feed, key: &SigningKey) -> Vec<u8> {
    let payload = serde_json::to_vec(feed).expect("Feed always serialises");
    let signature = key.sign(&payload);
    let envelope = Envelope {
        payload: BASE64.encode(&payload),
        signatures: vec![SigEntry {
            key: BASE64.encode(key.verifying_key().to_bytes()),
            sig: BASE64.encode(signature.to_bytes()),
        }],
    };
    serde_json::to_vec(&envelope).expect("Envelope always serialises")
}

/// First 16 bytes of the sha256 of the public key, hex, grouped in 4 characters: "ab12 cd34 …".
pub fn fingerprint(public_key: &[u8; 32]) -> String {
    let digest = Sha256::digest(public_key);
    to_hex(&digest[..16]).as_bytes().chunks(4).map(|c| std::str::from_utf8(c).unwrap()).collect::<Vec<_>>().join(" ")
}

/// Case-insensitive sha256 check.
pub fn sha256_matches(bytes: &[u8], hex: &str) -> bool {
    to_hex(&Sha256::digest(bytes)).eq_ignore_ascii_case(hex)
}

fn to_hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_feed(sequence: u64) -> Feed {
        Feed {
            name: "vehicoule-plugins".into(),
            sequence,
            plugins: vec![FeedEntry {
                id: "deezer".into(),
                version: "1.0.0".into(),
                contract: "1.0".into(),
                wasm_url: "plugins/deezer.wasm".into(),
                wasm_sha256: "a".repeat(64),
                manifest_url: "plugins/deezer.json".into(),
                manifest_sha256: "b".repeat(64),
            }],
        }
    }

    fn tamper_payload(bytes: &[u8]) -> Vec<u8> {
        let mut value: serde_json::Value = serde_json::from_slice(bytes).unwrap();
        let mut payload = BASE64.decode(value["payload"].as_str().unwrap()).unwrap();
        payload[0] ^= 0xFF;
        value["payload"] = serde_json::Value::String(BASE64.encode(&payload));
        serde_json::to_vec(&value).unwrap()
    }

    #[test]
    fn signed_feed_verifies() {
        let key = SigningKey::from_bytes(&[1u8; 32]);
        let feed = sample_feed(1);
        let bytes = sign_feed(&feed, &key);
        let trusted = [key.verifying_key().to_bytes()];
        assert_eq!(verify_feed(&bytes, &trusted, None).unwrap(), feed);
    }

    #[test]
    fn second_trusted_key_also_verifies() {
        let k1 = SigningKey::from_bytes(&[1u8; 32]);
        let k2 = SigningKey::from_bytes(&[2u8; 32]);
        let feed = sample_feed(1);
        let bytes = sign_feed(&feed, &k2);
        let trusted = [k1.verifying_key().to_bytes(), k2.verifying_key().to_bytes()];
        assert_eq!(verify_feed(&bytes, &trusted, None).unwrap(), feed);
    }

    #[test]
    fn tampered_payload_is_rejected() {
        let key = SigningKey::from_bytes(&[1u8; 32]);
        let bytes = sign_feed(&sample_feed(1), &key);
        let tampered = tamper_payload(&bytes);
        let trusted = [key.verifying_key().to_bytes()];
        assert_eq!(verify_feed(&tampered, &trusted, None), Err(FeedError::BadSignature));
    }

    #[test]
    fn unknown_key_is_rejected() {
        let signer = SigningKey::from_bytes(&[1u8; 32]);
        let trusted_key = SigningKey::from_bytes(&[2u8; 32]);
        let bytes = sign_feed(&sample_feed(1), &signer);
        let trusted = [trusted_key.verifying_key().to_bytes()];
        assert_eq!(verify_feed(&bytes, &trusted, None), Err(FeedError::BadSignature));
    }

    #[test]
    fn older_sequence_is_rejected() {
        let key = SigningKey::from_bytes(&[1u8; 32]);
        let trusted = [key.verifying_key().to_bytes()];

        let bytes6 = sign_feed(&sample_feed(6), &key);
        assert_eq!(verify_feed(&bytes6, &trusted, Some(7)), Err(FeedError::Rollback { seen: 7, got: 6 }));

        let feed7 = sample_feed(7);
        let bytes7 = sign_feed(&feed7, &key);
        assert_eq!(verify_feed(&bytes7, &trusted, Some(7)).unwrap(), feed7);
    }

    #[test]
    fn fingerprint_is_stable() {
        let key = SigningKey::from_bytes(&[7u8; 32]);
        let public_key = key.verifying_key().to_bytes();
        assert_eq!(fingerprint(&public_key), "fe81 2c12 f3ab 4ce6 ac5d b69a c352 f906");
    }

    #[test]
    fn sha256_check_is_case_insensitive() {
        let data = b"vehicoule feed";
        let hex_lower = to_hex(&Sha256::digest(data));
        assert!(sha256_matches(data, &hex_lower));
        assert!(sha256_matches(data, &hex_lower.to_uppercase()));
        assert!(!sha256_matches(data, &"0".repeat(64)));
    }

    #[test]
    fn duplicate_plugin_ids_are_rejected() {
        let key = SigningKey::from_bytes(&[1u8; 32]);
        let mut feed = sample_feed(1);
        feed.plugins.push(feed.plugins[0].clone());
        let bytes = sign_feed(&feed, &key);
        let trusted = [key.verifying_key().to_bytes()];
        assert!(matches!(verify_feed(&bytes, &trusted, None), Err(FeedError::Malformed(_))));
    }

    #[test]
    fn non_https_absolute_url_is_rejected() {
        let key = SigningKey::from_bytes(&[1u8; 32]);
        let mut feed = sample_feed(1);
        feed.plugins[0].wasm_url = "http://example.com/p.wasm".into();
        let bytes = sign_feed(&feed, &key);
        let trusted = [key.verifying_key().to_bytes()];
        assert!(matches!(verify_feed(&bytes, &trusted, None), Err(FeedError::Malformed(_))));
    }

    /// WHATWG URL resolvers strip ASCII control characters and tabs/newlines, and treat
    /// `\` as `/`, so these would all resolve to `http://evil/...` even though the scheme
    /// check sees no valid `scheme:` prefix and would otherwise wave them through as relative.
    #[test]
    fn urls_with_control_chars_space_or_backslash_are_rejected() {
        let key = SigningKey::from_bytes(&[1u8; 32]);
        let trusted = [key.verifying_key().to_bytes()];
        for bad_url in [
            " http://evil/x.wasm",
            "ht\ttp://evil/x",
            "\nhttp://evil/x",
            "\u{1}http://evil/x",
            "http://evil/x\\y",
        ] {
            let mut feed = sample_feed(1);
            feed.plugins[0].wasm_url = bad_url.into();
            let bytes = sign_feed(&feed, &key);
            assert!(
                matches!(verify_feed(&bytes, &trusted, None), Err(FeedError::Malformed(_))),
                "{bad_url:?} should be rejected"
            );
        }
    }

    #[test]
    fn uppercase_https_scheme_is_accepted() {
        let key = SigningKey::from_bytes(&[1u8; 32]);
        let trusted = [key.verifying_key().to_bytes()];
        let mut feed = sample_feed(1);
        feed.plugins[0].wasm_url = "HTTPS://example.com/x.wasm".into();
        let bytes = sign_feed(&feed, &key);
        assert_eq!(verify_feed(&bytes, &trusted, None).unwrap(), feed);
    }

    #[test]
    fn protocol_relative_url_is_allowed() {
        let key = SigningKey::from_bytes(&[1u8; 32]);
        let trusted = [key.verifying_key().to_bytes()];
        let mut feed = sample_feed(1);
        feed.plugins[0].wasm_url = "//example.com/x.wasm".into();
        let bytes = sign_feed(&feed, &key);
        assert_eq!(verify_feed(&bytes, &trusted, None).unwrap(), feed);
    }
}
