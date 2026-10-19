use serde::de::DeserializeOwned;

use crate::host_http::{self, HttpError, Method, Request};
use crate::types::Error;

/// GET `url` and parse the JSON body into `T`; unknown fields are ignored.
pub fn get_json<T: DeserializeOwned>(url: &str, headers: &[(&str, &str)]) -> Result<T, Error> {
    let req = Request {
        method: Method::Get,
        url: url.into(),
        headers: headers.iter().map(|&(k, v)| (k.into(), v.into())).collect(),
        body: None,
    };
    let resp = host_http::send(&req).map_err(from_http_error)?;
    if let Some(e) = status_error(resp.status) {
        return Err(e);
    }
    parse_json(&resp.body)
}

fn parse_json<T: DeserializeOwned>(body: &[u8]) -> Result<T, Error> {
    serde_json::from_slice(body).map_err(|e| Error::Internal(e.to_string()))
}

/// Typed error for a provider status, so the core can move on to the next plugin.
/// `None` for 2xx.
pub fn status_error(status: u16) -> Option<Error> {
    let http = || format!("HTTP {status}");
    Some(match status {
        200..=299 => return None,
        429 => Error::RateLimited,
        401 | 403 => Error::ProviderWall(http()),
        404 => Error::NotFound,
        500..=599 => Error::Network(http()),
        _ => Error::Internal(http()),
    })
}

/// `BudgetExceeded` becomes `internal`: the host itself reports `budget-exceeded`.
pub fn from_http_error(e: HttpError) -> Error {
    match e {
        HttpError::Network(m) => Error::Network(m),
        HttpError::Timeout => Error::Network("timeout".into()),
        HttpError::TooLarge => Error::Internal("response too large".into()),
        HttpError::Denied(m) => Error::Internal(m),
        HttpError::BudgetExceeded => Error::Internal("http budget".into()),
    }
}

/// `application/x-www-form-urlencoded` query string.
pub fn query(pairs: &[(&str, &str)]) -> String {
    form_urlencoded::Serializer::new(String::new()).extend_pairs(pairs).finish()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dbg<T: std::fmt::Debug>(v: T) -> String {
        format!("{v:?}")
    }

    #[test]
    fn status_maps_to_typed_errors() {
        assert!(status_error(200).is_none());
        assert!(status_error(204).is_none());
        assert_eq!(dbg(status_error(429)), dbg(Some(Error::RateLimited)));
        assert_eq!(dbg(status_error(401)), dbg(Some(Error::ProviderWall("HTTP 401".into()))));
        assert_eq!(dbg(status_error(403)), dbg(Some(Error::ProviderWall("HTTP 403".into()))));
        assert_eq!(dbg(status_error(404)), dbg(Some(Error::NotFound)));
        assert_eq!(dbg(status_error(500)), dbg(Some(Error::Network("HTTP 500".into()))));
        assert_eq!(dbg(status_error(503)), dbg(Some(Error::Network("HTTP 503".into()))));
    }

    #[test]
    fn http_error_maps_to_typed_errors() {
        let cases = [
            (HttpError::Network("dns".into()), Error::Network("dns".into())),
            (HttpError::Timeout, Error::Network("timeout".into())),
            (HttpError::TooLarge, Error::Internal("response too large".into())),
            (HttpError::Denied("evil.example".into()), Error::Internal("evil.example".into())),
            (HttpError::BudgetExceeded, Error::Internal("http budget".into())),
        ];
        for (from, to) in cases {
            assert_eq!(dbg(from_http_error(from)), dbg(to));
        }
    }

    #[derive(serde::Deserialize, Debug)]
    #[allow(dead_code)]
    struct Ab {
        a: u32,
        b: u32,
    }

    #[test]
    fn get_json_reports_missing_field() {
        match parse_json::<Ab>(br#"{"a":1}"#) {
            Err(Error::Internal(msg)) => assert!(msg.contains('b'), "{msg}"),
            other => panic!("{other:?}"),
        }
    }

    #[test]
    fn parse_ignores_unknown_fields() {
        let v: Ab = parse_json(br#"{"a":1,"b":2,"c":[3]}"#).unwrap();
        assert_eq!((v.a, v.b), (1, 2));
    }

    #[test]
    fn query_encodes_reserved_chars() {
        assert_eq!(query(&[("q", "AC/DC & Queen")]), "q=AC%2FDC+%26+Queen");
    }
}
