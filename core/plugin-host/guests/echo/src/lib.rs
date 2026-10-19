//! Fetches the URL given as the query and returns the HTTP status.
wit_bindgen::generate!({
    path: ["../../../contract/wit/host", "../../../contract/wit/music", "../wit"],
    world: "vehicoule:test-guests/test-search",
    with: {
        "vehicoule:host/http@1.0.0": vehicoule_sdk::host_http,
        "vehicoule:host/kv@1.0.0": vehicoule_sdk::kv,
        "vehicoule:host/clock@1.0.0": vehicoule_sdk::clock,
        "vehicoule:host/log@1.0.0": vehicoule_sdk::log,
        "vehicoule:music/types@1.0.0": vehicoule_sdk::types,
    },
});

use exports::vehicoule::music::search::{Guest, SearchRequest, SearchResults};
use vehicoule_sdk::host_http::{self, Method, Request};
use vehicoule_sdk::types::{Error, Track};

include!("../../found.rs");

struct Echo;

impl Guest for Echo {
    fn search(req: SearchRequest) -> Result<SearchResults, Error> {
        let req = Request { method: Method::Get, url: req.query, headers: vec![], body: None };
        let resp = host_http::send(&req).map_err(vehicoule_sdk::from_http_error)?;
        Ok(found(resp.status.to_string()))
    }
}

export!(Echo);
