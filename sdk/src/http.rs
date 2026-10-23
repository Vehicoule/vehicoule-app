use serde::de::DeserializeOwned;

use crate::host_http::{self, HttpError, Method, Request, Response};
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
    json(&resp.body)
}

/// Parses a JSON body into `T`; unknown fields are ignored. A body that does not parse is
/// `Error::Internal` with serde's message (which names a missing field).
pub fn json<T: DeserializeOwned>(body: &[u8]) -> Result<T, Error> {
    serde_json::from_slice(body).map_err(|e| Error::Internal(e.to_string()))
}

/// Sends `reqs` in one host batch (at most 8): each body in order, or its error. A transport
/// error goes through `from_http_error`, a status through `status`: `status_error`, or the
/// plugin's own mapping built on it.
pub fn send_batch_bodies(
    reqs: &[Request],
    status: fn(u16) -> Option<Error>,
) -> Vec<Result<Vec<u8>, Error>> {
    bodies(host_http::send_batch(reqs), status)
}

fn bodies(
    results: Vec<Result<Response, HttpError>>,
    status: fn(u16) -> Option<Error>,
) -> Vec<Result<Vec<u8>, Error>> {
    results
        .into_iter()
        .map(|r| {
            let resp = r.map_err(from_http_error)?;
            status(resp.status).map_or(Ok(resp.body), Err)
        })
        .collect()
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
    fn json_reports_missing_field() {
        match json::<Ab>(br#"{"a":1}"#) {
            Err(Error::Internal(msg)) => assert!(msg.contains('b'), "{msg}"),
            other => panic!("{other:?}"),
        }
    }

    #[test]
    fn parse_ignores_unknown_fields() {
        let v: Ab = json(br#"{"a":1,"b":2,"c":[3]}"#).unwrap();
        assert_eq!((v.a, v.b), (1, 2));
    }

    #[test]
    fn json_reports_bad_syntax_as_internal() {
        match json::<Ab>(b"<html>") {
            Err(Error::Internal(msg)) => assert!(msg.contains("expected value"), "{msg}"),
            other => panic!("{other:?}"),
        }
    }

    fn response(status: u16, body: &[u8]) -> Result<Response, HttpError> {
        Ok(Response { status, url: String::new(), headers: vec![], body: body.to_vec() })
    }

    #[test]
    fn batch_bodies_keep_order_and_map_errors() {
        let results = vec![
            response(200, b"a"),
            response(404, b"gone"),
            Err(HttpError::Timeout),
            response(204, b""),
            response(403, b"wall"),
        ];
        let want = [
            Ok(b"a".to_vec()),
            Err(Error::NotFound),
            Err(Error::Network("timeout".into())),
            Ok(vec![]),
            Err(Error::ProviderWall("HTTP 403".into())),
        ];
        assert_eq!(dbg(bodies(results, status_error)), dbg(want));
    }

    #[test]
    fn batch_bodies_take_the_plugin_status_mapping() {
        // As iTunes does: its 403 is a rate limit.
        fn itunes(status: u16) -> Option<Error> {
            if status == 403 { Some(Error::RateLimited) } else { status_error(status) }
        }
        let results = vec![response(403, b""), response(500, b"")];
        let want: [Result<Vec<u8>, Error>; 2] =
            [Err(Error::RateLimited), Err(Error::Network("HTTP 500".into()))];
        assert_eq!(dbg(bodies(results, itunes)), dbg(want));
    }

    #[test]
    fn query_encodes_reserved_chars() {
        assert_eq!(query(&[("q", "AC/DC & Queen")]), "q=AC%2FDC+%26+Queen");
    }
}
