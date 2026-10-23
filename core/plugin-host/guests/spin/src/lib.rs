//! Never returns.
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
use vehicoule_sdk::types::Error;

struct Spin;

impl Guest for Spin {
    fn search(_: SearchRequest) -> Result<SearchResults, Error> {
        loop {
            std::hint::black_box(());
        }
    }
}

export!(Spin);
