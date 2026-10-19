//! Blocks 5 s inside a host call (WASI poll), where epoch checks never run.
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
use vehicoule_sdk::types::{Error, Track};

include!("../../found.rs");

struct Sleepy;

impl Guest for Sleepy {
    fn search(_: SearchRequest) -> Result<SearchResults, Error> {
        std::thread::sleep(std::time::Duration::from_secs(5));
        Ok(found("woke".into()))
    }
}

export!(Sleepy);
