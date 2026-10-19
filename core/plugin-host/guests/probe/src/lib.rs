//! Host probe: runs the command in `search-request.query`, reports in the tracks' titles.
//! `get <url>` (status), `count <url> <n>` (n sequential GETs), `batch <url> <n>` (one
//! `send-batch`, one track per result), `kv-set <k> <v>`, `kv-get <k>`, `print <text>`,
//! `log <text>`, `art <url>` (a track with that artwork). `resolve` streams `track.title`.
wit_bindgen::generate!({
    path: ["../../../contract/wit/host", "../../../contract/wit/music", "../wit"],
    world: "vehicoule:test-guests/test-probe",
    with: {
        "vehicoule:host/http@1.0.0": vehicoule_sdk::host_http,
        "vehicoule:host/kv@1.0.0": vehicoule_sdk::kv,
        "vehicoule:host/clock@1.0.0": vehicoule_sdk::clock,
        "vehicoule:host/log@1.0.0": vehicoule_sdk::log,
        "vehicoule:music/types@1.0.0": vehicoule_sdk::types,
    },
});

use exports::vehicoule::music::resolve::{self, ResolveRequest, Resolved, Source};
use exports::vehicoule::music::search::{self, SearchRequest, SearchResults};
use vehicoule_sdk::host_http::{self, Method, Request};
use vehicoule_sdk::types::{Error, Image, Track};
use vehicoule_sdk::{from_http_error, kv, log, status_error};

include!("../../found.rs");

struct Probe;

fn get(url: &str) -> Request {
    Request { method: Method::Get, url: url.into(), headers: vec![], body: None }
}

fn count(n: &str) -> Result<usize, Error> {
    n.parse().map_err(|_| Error::Internal(format!("bad count {n:?}")))
}

impl search::Guest for Probe {
    fn search(req: SearchRequest) -> Result<SearchResults, Error> {
        let mut words = req.query.splitn(3, ' ');
        let (cmd, a, b) = (words.next().unwrap_or(""), words.next().unwrap_or(""), words.next().unwrap_or(""));
        let title = match cmd {
            "get" => {
                let resp = host_http::send(&get(a)).map_err(from_http_error)?;
                if let Some(e) = status_error(resp.status) {
                    return Err(e);
                }
                resp.status.to_string()
            }
            "count" => {
                let n = count(b)?;
                for _ in 0..n {
                    host_http::send(&get(a)).map_err(from_http_error)?;
                }
                n.to_string()
            }
            "batch" => {
                let reqs: Vec<Request> = (0..count(b)?).map(|_| get(a)).collect();
                let mut out = found(String::new());
                out.tracks = host_http::send_batch(&reqs)
                    .into_iter()
                    .map(|r| track(r.map_or_else(|e| format!("{e:?}"), |resp| resp.status.to_string())))
                    .collect();
                return Ok(out);
            }
            "kv-set" => kv::set(a, b.as_bytes()).map_or_else(|e| format!("{e:?}"), |()| "ok".into()),
            "kv-get" => String::from_utf8_lossy(&kv::get(a).ok_or(Error::NotFound)?).into_owned(),
            "print" => {
                let text = format!("{a} {b}").trim_end().to_string();
                println!("{text}");
                text
            }
            "log" => {
                let text = format!("{a} {b}").trim_end().to_string();
                log::log(log::Level::Info, &text);
                text
            }
            "art" => {
                let mut out = found("art".into());
                out.tracks[0].artwork = vec![Image { url: a.into(), width: None, height: None }];
                return Ok(out);
            }
            _ => return Err(Error::Internal(format!("unknown command {cmd:?}"))),
        };
        Ok(found(title))
    }
}

impl resolve::Guest for Probe {
    fn resolve(req: ResolveRequest) -> Result<Resolved, Error> {
        let source = Source {
            url: req.track.title,
            headers: vec![],
            expires_at_ms: None,
            mime: "audio/mpeg".into(),
            bitrate: 128_000,
            content_length: None,
            loudness_db: None,
        };
        Ok(Resolved { id: "probe".into(), source, candidates: vec![] })
    }
}

export!(Probe);
