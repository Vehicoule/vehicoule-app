//! Allocates 100 MiB.
wit_bindgen::generate!({
    path: ["../../../contract/wit/host", "../../../contract/wit/music", "../wit"],
    world: "vehicoule:test-guests/test-search",
    with: {
        "vehicoule:host/http@1.0.0": vehicoule_sdk::host_http,
        "vehicoule:host/kv@1.0.0": vehicoule_sdk::kv,
        "vehicoule:host/clock@1.0.0": vehicoule_sdk::clock,
        "vehicoule:host/log@1.0.0": vehicoule_sdk::log,
        "vehicoule:music/types@1.1.0": vehicoule_sdk::types,
    },
});

use exports::vehicoule::music::search::{Guest, SearchRequest, SearchResults};
use vehicoule_sdk::types::{Error, Track};

include!("../../found.rs");

struct Hog;

impl Guest for Hog {
    fn search(_: SearchRequest) -> Result<SearchResults, Error> {
        let v = std::hint::black_box(vec![1u8; 100 << 20]);
        Ok(found(v.len().to_string()))
    }
}

export!(Hog);
