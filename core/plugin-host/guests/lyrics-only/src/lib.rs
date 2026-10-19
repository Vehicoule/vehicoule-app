//! Exports only `lyrics`, like an lrclib plugin.
wit_bindgen::generate!({
    path: ["../../../contract/wit/host", "../../../contract/wit/music", "../wit"],
    world: "vehicoule:test-guests/test-lyrics",
    with: {
        "vehicoule:host/http@1.0.0": vehicoule_sdk::host_http,
        "vehicoule:host/kv@1.0.0": vehicoule_sdk::kv,
        "vehicoule:host/clock@1.0.0": vehicoule_sdk::clock,
        "vehicoule:host/log@1.0.0": vehicoule_sdk::log,
        "vehicoule:music/types@1.0.0": vehicoule_sdk::types,
    },
});

use exports::vehicoule::music::lyrics::{Guest, Lyrics};
use vehicoule_sdk::types::{Error, TrackQuery};

struct LyricsOnly;

impl Guest for LyricsOnly {
    fn fetch(track: TrackQuery) -> Result<Lyrics, Error> {
        Ok(Lyrics { plain: Some(track.title), synced: vec![] })
    }
}

export!(LyricsOnly);
