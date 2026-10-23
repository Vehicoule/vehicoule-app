//! Exports only `browse`. Echoes its arguments into the records; every artwork list holds one
//! image inside the test allowlist (`api.test`) and one outside it (`evil.test`).
wit_bindgen::generate!({
    path: ["../../../contract/wit/host", "../../../contract/wit/music", "../wit"],
    world: "vehicoule:test-guests/test-browse",
    with: {
        "vehicoule:host/http@1.0.0": vehicoule_sdk::host_http,
        "vehicoule:host/kv@1.0.0": vehicoule_sdk::kv,
        "vehicoule:host/clock@1.0.0": vehicoule_sdk::clock,
        "vehicoule:host/log@1.0.0": vehicoule_sdk::log,
        "vehicoule:music/types@1.1.0": vehicoule_sdk::types,
    },
    generate_all,
});

use exports::vehicoule::music::browse::{Category, CategoryPage, Guest, Release, Shelf};
use vehicoule::music::entity::Entity;
use vehicoule_sdk::types::{Album, Error, Image};

fn artwork() -> Vec<Image> {
    ["http://api.test/a.jpg", "https://evil.test/a.jpg"]
        .map(|url| Image {
            url: url.into(),
            width: None,
            height: None,
        })
        .into()
}

fn album(id: String) -> Album {
    Album {
        id,
        title: String::new(),
        artists: vec![],
        year: None,
        track_count: None,
        artwork: artwork(),
    }
}

struct BrowseOnly;

impl Guest for BrowseOnly {
    fn categories(region: String) -> Result<Vec<Category>, Error> {
        Ok(vec![Category {
            id: "c".into(),
            title: region,
            artwork: artwork(),
            featured: true,
        }])
    }

    fn fetch_category(
        id: String,
        region: String,
        cursor: Option<String>,
    ) -> Result<CategoryPage, Error> {
        let shelf = Shelf {
            title: region,
            items: vec![Entity::Album(album(id.clone()))],
        };
        Ok(CategoryPage {
            title: id,
            shelves: vec![shelf],
            next: cursor,
        })
    }

    fn releases(artist_id: String, region: String) -> Result<Vec<Release>, Error> {
        Ok(vec![Release {
            album: album(artist_id),
            date: region,
        }])
    }
}

export!(BrowseOnly);
