//! Recorded responses for tests: `dir/index.json` lists `{method, url, status, headers,
//! body_file}`; a request matches on method and exact URL.

use std::path::Path;

use contract::http::HttpError;
use serde::Deserialize;

use crate::net::{Body, Hop};

#[derive(Deserialize)]
struct Entry {
    method: String,
    url: String,
    status: u16,
    headers: Vec<(String, String)>,
    body_file: String,
}

pub(crate) struct Replay {
    entries: Vec<(Entry, Vec<u8>)>,
}

impl Replay {
    /// Panics on a missing or malformed recording: test setup error.
    pub(crate) fn load(dir: &Path) -> Replay {
        let index = std::fs::read(dir.join("index.json")).expect("replay index.json");
        let entries: Vec<Entry> = serde_json::from_slice(&index).expect("replay index.json format");
        let entries = entries
            .into_iter()
            .map(|e| {
                let body = std::fs::read(dir.join(&e.body_file))
                    .unwrap_or_else(|err| panic!("{}: {err}", e.body_file));
                (e, body)
            })
            .collect();
        Replay { entries }
    }

    pub(crate) fn find(&self, method: &str, url: &str) -> Result<Hop, HttpError> {
        let (e, body) = self
            .entries
            .iter()
            .find(|(e, _)| e.method.eq_ignore_ascii_case(method) && e.url == url)
            .ok_or_else(|| HttpError::Network(format!("no recording for {method} {url}")))?;
        Ok(Hop {
            status: e.status,
            headers: e.headers.clone(),
            body: Body::Recorded(body.clone()),
        })
    }
}
