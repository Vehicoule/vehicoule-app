//! Pieces of provider links and ids, before they reach a URL.

/// Whether `s` is a non-empty run of ASCII digits: the shape of a decimal provider id (Deezer,
/// iTunes). Anything else must never be put in a URL.
pub fn is_decimal_id(s: &str) -> bool {
    !s.is_empty() && s.bytes().all(|b| b.is_ascii_digit())
}

/// An `http://` or `https://` URL (scheme in any case) as its host, lowercased, and its path
/// as given, without the leading `/` (query and fragment included). `None` for any other
/// scheme or no `://`.
pub fn split_url(url: &str) -> Option<(String, &str)> {
    let (scheme, rest) = url.split_once("://")?;
    if !scheme.eq_ignore_ascii_case("https") && !scheme.eq_ignore_ascii_case("http") {
        return None;
    }
    let (host, path) = rest.split_once('/').unwrap_or((rest, ""));
    Some((host.to_ascii_lowercase(), path))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decimal_ids_only() {
        for id in ["0", "302127", "00123"] {
            assert!(is_decimal_id(id), "{id}");
        }
        for id in ["", "12a", "-1", "1.0", " 1", "١٢", "id123"] {
            assert!(!is_decimal_id(id), "{id:?}");
        }
    }

    #[test]
    fn split_url_lowercases_the_host_only() {
        assert_eq!(
            split_url("HTTPS://WWW.Deezer.COM/FR/playlist/9?x=Y#Z"),
            Some(("www.deezer.com".to_string(), "FR/playlist/9?x=Y#Z"))
        );
        assert_eq!(split_url("Http://music.apple.com"), Some(("music.apple.com".to_string(), "")));
        assert_eq!(split_url("https://h/"), Some(("h".to_string(), "")));
        for url in ["ftp://h/p", "h/p", "", "https:/h/p", "file:///etc"] {
            assert_eq!(split_url(url), None, "{url:?}");
        }
    }
}
