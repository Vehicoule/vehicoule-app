//! A catalogue plugin serving fixed data built from the request, for vehicoule-core's tests.
//!
//! Per request: a query or id containing `missing` is `not-found`. Per plugin: kv `mode` =
//! `network` or `not-found` fails every call with that error, `empty` makes `search` return
//! nothing. Every call adds one to kv `calls`. Links: `https://fake.test/<kind>/<id>`. Playlists have endless pages (2 tracks
//! each, `next` always set; only page 0 carries the title and owner); albums one page.
wit_bindgen::generate!({
    path: ["../../../../contract/wit/host", "../../../../contract/wit/music", "../wit"],
    world: "vehicoule:core-test-guests/fake-catalog",
    with: {
        "vehicoule:host/http@1.0.0": vehicoule_sdk::host_http,
        "vehicoule:host/kv@1.0.0": vehicoule_sdk::kv,
        "vehicoule:host/clock@1.0.0": vehicoule_sdk::clock,
        "vehicoule:host/log@1.0.0": vehicoule_sdk::log,
        "vehicoule:music/types@1.0.0": vehicoule_sdk::types,
    },
});

use exports::vehicoule::music::entity::{self, Entity, EntityPage};
use exports::vehicoule::music::search::{self, SearchRequest, SearchResults};
use exports::vehicoule::music::suggest;
use vehicoule_sdk::kv;
use vehicoule_sdk::types::{
    Album, AlbumRef, Artist, ArtistRef, EntityKind, EntityRef, Error, Image, Playlist, Track,
};

struct Fake;

fn mode() -> String {
    kv::get("mode").map(|v| String::from_utf8_lossy(&v).into_owned()).unwrap_or_default()
}

/// Counts the call, then the plugin-wide failure, then `missing` in `key`.
fn check(key: &str) -> Result<(), Error> {
    let calls: u64 = kv::get("calls").and_then(|v| String::from_utf8(v).ok()?.parse().ok()).unwrap_or(0);
    let _ = kv::set("calls", (calls + 1).to_string().as_bytes());
    match mode().as_str() {
        "network" => return Err(Error::Network("down".into())),
        "not-found" => return Err(Error::NotFound),
        _ => {}
    }
    if key.contains("missing") { Err(Error::NotFound) } else { Ok(()) }
}

fn art(key: &str) -> Vec<Image> {
    [250, 1000]
        .map(|w| Image { url: format!("https://fake.test/art/{key}-{w}.jpg"), width: Some(w), height: Some(w) })
        .to_vec()
}

fn artist(key: &str) -> Artist {
    Artist { id: format!("ar-{key}"), name: format!("Artist {key}"), artwork: art(&format!("ar-{key}")) }
}

fn album(key: &str) -> Album {
    Album {
        id: format!("a-{key}"),
        title: format!("Album {key}"),
        artists: vec![ArtistRef { id: Some(format!("ar-{key}")), name: format!("Artist {key}") }],
        year: Some(2008),
        track_count: Some(2),
        artwork: art(&format!("a-{key}")),
    }
}

fn track(id: String, title: &str, key: &str) -> Track {
    Track {
        id,
        title: title.into(),
        artists: vec![ArtistRef { id: Some(format!("ar-{key}")), name: format!("Artist {key}") }],
        album: Some(AlbumRef { id: Some(format!("a-{key}")), title: format!("Album {key}") }),
        duration_ms: Some(180_000),
        isrc: None,
        explicit: false,
        artwork: art(&format!("a-{key}")),
    }
}

fn tracks(prefix: &str, key: &str) -> Vec<Track> {
    (1..=2).map(|i| track(format!("{prefix}-{i}"), &format!("{prefix} {i}"), key)).collect()
}

impl search::Guest for Fake {
    fn search(req: SearchRequest) -> Result<SearchResults, Error> {
        check(&req.query)?;
        if mode() == "empty" {
            return Ok(SearchResults { tracks: vec![], albums: vec![], artists: vec![], playlists: vec![], next: None });
        }
        let key = req.query.trim().to_lowercase().replace(' ', "-");
        Ok(SearchResults {
            tracks: vec![track(format!("t-{key}"), &req.query, &key)],
            albums: vec![album(&key)],
            artists: vec![artist(&key)],
            playlists: vec![Playlist {
                id: format!("p-{key}"),
                title: format!("Playlist {key}"),
                owner: Some("Owner".into()),
                description: None,
                track_count: None,
                artwork: art(&format!("p-{key}")),
            }],
            next: None,
        })
    }
}

impl suggest::Guest for Fake {
    fn suggest(prefix: String, _region: String) -> Result<Vec<String>, Error> {
        check(&prefix)?;
        Ok(vec![format!("{prefix} live"), format!("{prefix} remix")])
    }
}

impl entity::Guest for Fake {
    fn fetch(target: EntityRef, _region: String, cursor: Option<String>) -> Result<EntityPage, Error> {
        check(&target.id)?;
        let id = target.id;
        let key = id.split_once('-').map_or(id.as_str(), |(_, k)| k).to_string();
        let page = |entity, tracks, albums, next| EntityPage { entity, tracks, albums, next };
        Ok(match target.kind {
            EntityKind::Track => page(Entity::Track(track(id.clone(), &id, &key)), vec![], vec![], None),
            EntityKind::Album => page(Entity::Album(Album { id: id.clone(), ..album(&key) }), tracks(&id, &key), vec![], None),
            EntityKind::Artist => {
                page(Entity::Artist(Artist { id: id.clone(), ..artist(&key) }), tracks(&id, &key), vec![album(&key)], None)
            }
            EntityKind::Playlist => {
                let n: u32 = cursor.as_deref().unwrap_or("0").parse().map_err(|_| Error::Internal("bad cursor".into()))?;
                let first = n == 0;
                let playlist = Playlist {
                    id: id.clone(),
                    title: if first { format!("Playlist {key}") } else { String::new() },
                    owner: first.then(|| "Owner".into()),
                    description: None,
                    track_count: None,
                    artwork: if first { art(&id) } else { vec![] },
                };
                page(Entity::Playlist(playlist), tracks(&format!("{id}-p{n}"), &key), vec![], Some((n + 1).to_string()))
            }
        })
    }

    fn parse_link(url: String) -> Result<Option<EntityRef>, Error> {
        check(&url)?;
        let Some((kind, id)) = url.strip_prefix("https://fake.test/").and_then(|p| p.split_once('/')) else {
            return Ok(None);
        };
        let kind = match kind {
            "track" => EntityKind::Track,
            "album" => EntityKind::Album,
            "artist" => EntityKind::Artist,
            "playlist" => EntityKind::Playlist,
            _ => return Ok(None),
        };
        Ok(Some(EntityRef { kind, id: id.into() }))
    }
}

export!(Fake);
