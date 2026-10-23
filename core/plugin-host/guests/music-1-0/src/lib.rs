//! A plugin built against `vehicoule:music@1.0.0` (vendored in `../wit-1.0`): exports `search`
//! and `lyrics`, knows nothing of `browse`.
wit_bindgen::generate!({
    path: ["../../../contract/wit/host", "../wit-1.0"],
    inline: "
        package vehicoule:test-guests-1-0;
        world test-1-0 {
            include vehicoule:host/imports@1.0.0;
            export vehicoule:music/search@1.0.0;
            export vehicoule:music/lyrics@1.0.0;
        }
    ",
    world: "vehicoule:test-guests-1-0/test-1-0",
    generate_all,
});

use exports::vehicoule::music::lyrics::{self, Lyrics};
use exports::vehicoule::music::search::{self, SearchRequest, SearchResults};
use vehicoule::music::types::{Error, Track, TrackQuery};

include!("../../found.rs");

struct Music10;

impl search::Guest for Music10 {
    fn search(req: SearchRequest) -> Result<SearchResults, Error> {
        Ok(found(req.query))
    }
}

impl lyrics::Guest for Music10 {
    fn fetch(track: TrackQuery) -> Result<Lyrics, Error> {
        Ok(Lyrics {
            plain: Some(track.title),
            synced: vec![],
        })
    }
}

export!(Music10);
