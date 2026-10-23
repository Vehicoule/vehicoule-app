//! Host probe: runs the command in `search-request.query`, reports in the tracks' titles.
//! `get <url>` (status), `count <url> <n>` (n sequential GETs), `count-ok <url> <n>` (n
//! sequential GETs, errors counted but swallowed), `batch <url> <n>` (one `send-batch`, one
//! track per result), `cap-batch <url>` (three batches of 8 then one more send, reports how
//! many of the 24 batched sends and the extra one succeeded), `ua <url> <value>` (one GET with
//! that `User-Agent` header), `kv-set <k> <v>`, `kv-get <k>`, `print <text>` (stdout),
//! `eprint <text>` (stderr), `log <text>`, `lines <n>` (n ~6 KiB lines to stdout), `crlf <text>`
//! (one `<text>\r\n` line), `partial <text>` (no trailing newline, explicitly flushed),
//! `art <url>` (a track with that artwork). `resolve` streams `track.title`, with `Host`,
//! `Connection`, `Proxy-Authorization` and `Referer` headers (the host must strip all but the last).
wit_bindgen::generate!({
    path: ["../../../contract/wit/host", "../../../contract/wit/music", "../wit"],
    world: "vehicoule:test-guests/test-probe",
    with: {
        "vehicoule:host/http@1.0.0": vehicoule_sdk::host_http,
        "vehicoule:host/kv@1.0.0": vehicoule_sdk::kv,
        "vehicoule:host/clock@1.0.0": vehicoule_sdk::clock,
        "vehicoule:host/log@1.0.0": vehicoule_sdk::log,
        "vehicoule:music/types@1.1.0": vehicoule_sdk::types,
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
            "count-ok" => {
                let n = count(b)?;
                let mut errs = 0u32;
                for _ in 0..n {
                    if host_http::send(&get(a)).is_err() {
                        errs += 1;
                    }
                }
                format!("errs={errs}")
            }
            "ua" => {
                let req = Request { headers: vec![("User-Agent".into(), b.into())], ..get(a) };
                let resp = host_http::send(&req).map_err(from_http_error)?;
                resp.status.to_string()
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
            "cap-batch" => {
                let mut ok = 0usize;
                for _ in 0..3 {
                    let reqs: Vec<Request> = (0..8).map(|_| get(a)).collect();
                    ok += host_http::send_batch(&reqs).into_iter().filter(Result::is_ok).count();
                }
                let extra_ok = host_http::send(&get(a)).is_ok();
                format!("ok={ok} extra_ok={extra_ok}")
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
            "lines" => {
                let n = count(a)?;
                // ~6 KiB/line: `n=500` is ~3 MiB total, over any one-call buffer a host might
                // (no longer) keep.
                let padding = "x".repeat(6000);
                for i in 0..n {
                    println!("l{i}:{padding}");
                }
                n.to_string()
            }
            "eprint" => {
                let text = format!("{a} {b}").trim_end().to_string();
                eprintln!("{text}");
                text
            }
            "crlf" => {
                // An explicit `\r` right before `println!`'s own `\n`: the host must drop it,
                // not just the final `\n`.
                println!("{a}\r");
                a.to_string()
            }
            "partial" => {
                // No trailing newline: Rust's stdout line-buffers, so this needs an explicit
                // flush to actually reach the host before the call returns.
                let text = format!("{a} {b}").trim_end().to_string();
                print!("{text}");
                use std::io::Write;
                let _ = std::io::stdout().flush();
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
            headers: [("Host", "evil.test"), ("Connection", "close"), ("Proxy-Authorization", "x"), ("Referer", "r")]
                .map(|(k, v)| (k.to_string(), v.to_string()))
                .into(),
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
