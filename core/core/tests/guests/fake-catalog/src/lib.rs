//! A catalogue plugin serving fixed data built from the request, for vehicoule-core's tests.
//!
//! Per request: a query or id containing `missing` is `not-found`. Per plugin: kv `mode` =
//! `network`, `not-found` or `rate-limited` fails every call with that error, `empty` makes `search` return
//! nothing. Every call adds one to kv `calls`. Links: `https://fake.test/<kind>/<id>`. Playlists have endless pages (2 tracks
//! each, `next` always set; only page 0 carries the title and owner); albums one page.
//!
//! `resolve`: the ids are `track.id` (if any) then `r-<key>-1..3`; the first one not in `tried`
//! wins, the others are the candidates. Stream `https://fake.test/stream/<id>`, loudness 4.2 dB.
//! kv `tried` keeps the last request's `tried` (comma-separated). `radio`: `limit` tracks
//! `radio-<key>-<n>`. kv `stream` replaces the stream base URL (`https://fake.test`), kv `mime`
//! its mime (`audio/webm`).
//! `lyrics`: a title containing `instrumental` has none (empty lyrics), others have plain and
//! two synced lines.
//! `browse`: categories `chart:0` (featured, with artwork) and `genre:1` (none); a category
//! has four shelves (`tracks`, `albums`, `artists`, `playlists`) and pages `next` = `1` then
//! none; `releases` of `ar-<key>`: two albums `rel-<key>-1..2` by that artist, newest first
//! (2026-10-20, 2026-09-01); a key starting with `dup` adds, between them, `rel-<key>-mid`
//! (2026-10-01), `rel-dup-shared` (2026-09-25, the same album for every such artist) and
//! `rel-<key>-old` (2026-09-24); a key starting with `baddate` gets four releases dated
//! `2026-10-20T08:00:00Z`, `2026-10-05`, `2026-10` and `2026`. kv `chart` = `no-tracks`: `chart:0` has no `tracks` shelf, and
//! the categories gain a featured `chart:2` after it. `radio` of a seed whose title contains
//! `echo`: first, another edition of the seed (id `echo-<key>`, same title and artists).
wit_bindgen::generate!({
    path: ["../../../../contract/wit/host", "../../../../contract/wit/music", "../wit"],
    world: "vehicoule:core-test-guests/fake-catalog",
    with: {
        "vehicoule:host/http@1.0.0": vehicoule_sdk::host_http,
        "vehicoule:host/kv@1.0.0": vehicoule_sdk::kv,
        "vehicoule:host/clock@1.0.0": vehicoule_sdk::clock,
        "vehicoule:host/log@1.0.0": vehicoule_sdk::log,
        "vehicoule:music/types@1.1.0": vehicoule_sdk::types,
    },
});

use exports::vehicoule::music::browse::{self, Category, CategoryPage, Release, Shelf};
use exports::vehicoule::music::entity::{self, Entity, EntityPage};
use exports::vehicoule::music::lyrics::{self, Line, Lyrics};
use exports::vehicoule::music::radio;
use exports::vehicoule::music::resolve::{self, Candidate, ResolveRequest, Resolved, Source};
use exports::vehicoule::music::search::{self, SearchRequest, SearchResults};
use exports::vehicoule::music::suggest;
use vehicoule_sdk::kv;
use vehicoule_sdk::types::{
    Album, AlbumRef, Artist, ArtistRef, EntityKind, EntityRef, Error, Image, Playlist, Track,
    TrackQuery,
};

struct Fake;

fn no_chart_tracks() -> bool {
    kv::get("chart").is_some_and(|v| v == b"no-tracks")
}

fn mode() -> String {
    kv::get("mode")
        .map(|v| String::from_utf8_lossy(&v).into_owned())
        .unwrap_or_default()
}

/// Counts the call, then the plugin-wide failure, then `missing` in `key`.
fn check(key: &str) -> Result<(), Error> {
    let calls: u64 = kv::get("calls")
        .and_then(|v| String::from_utf8(v).ok()?.parse().ok())
        .unwrap_or(0);
    let _ = kv::set("calls", (calls + 1).to_string().as_bytes());
    match mode().as_str() {
        "network" => return Err(Error::Network("down".into())),
        "not-found" => return Err(Error::NotFound),
        "rate-limited" => return Err(Error::RateLimited),
        _ => {}
    }
    if key.contains("missing") {
        Err(Error::NotFound)
    } else {
        Ok(())
    }
}

fn art(key: &str) -> Vec<Image> {
    [250, 1000]
        .map(|w| Image {
            url: format!("https://fake.test/art/{key}-{w}.jpg"),
            width: Some(w),
            height: Some(w),
        })
        .to_vec()
}

fn artist(key: &str) -> Artist {
    Artist {
        id: format!("ar-{key}"),
        name: format!("Artist {key}"),
        artwork: art(&format!("ar-{key}")),
    }
}

fn album(key: &str) -> Album {
    Album {
        id: format!("a-{key}"),
        title: format!("Album {key}"),
        artists: vec![ArtistRef {
            id: Some(format!("ar-{key}")),
            name: format!("Artist {key}"),
        }],
        year: Some(2008),
        track_count: Some(2),
        artwork: art(&format!("a-{key}")),
    }
}

fn track(id: String, title: &str, key: &str) -> Track {
    Track {
        id,
        title: title.into(),
        artists: vec![ArtistRef {
            id: Some(format!("ar-{key}")),
            name: format!("Artist {key}"),
        }],
        album: Some(AlbumRef {
            id: Some(format!("a-{key}")),
            title: format!("Album {key}"),
        }),
        duration_ms: Some(180_000),
        isrc: None,
        explicit: false,
        artwork: art(&format!("a-{key}")),
    }
}

fn tracks(prefix: &str, key: &str) -> Vec<Track> {
    (1..=2)
        .map(|i| track(format!("{prefix}-{i}"), &format!("{prefix} {i}"), key))
        .collect()
}

impl search::Guest for Fake {
    fn search(req: SearchRequest) -> Result<SearchResults, Error> {
        check(&req.query)?;
        if mode() == "empty" {
            return Ok(SearchResults {
                tracks: vec![],
                albums: vec![],
                artists: vec![],
                playlists: vec![],
                next: None,
            });
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
    fn fetch(
        target: EntityRef,
        _region: String,
        cursor: Option<String>,
    ) -> Result<EntityPage, Error> {
        check(&target.id)?;
        let id = target.id;
        let key = id
            .split_once('-')
            .map_or(id.as_str(), |(_, k)| k)
            .to_string();
        let page = |entity, tracks, albums, next| EntityPage {
            entity,
            tracks,
            albums,
            next,
        };
        Ok(match target.kind {
            EntityKind::Track => page(
                Entity::Track(track(id.clone(), &id, &key)),
                vec![],
                vec![],
                None,
            ),
            EntityKind::Album => page(
                Entity::Album(Album {
                    id: id.clone(),
                    ..album(&key)
                }),
                tracks(&id, &key),
                vec![],
                None,
            ),
            EntityKind::Artist => page(
                Entity::Artist(Artist {
                    id: id.clone(),
                    ..artist(&key)
                }),
                tracks(&id, &key),
                vec![album(&key)],
                None,
            ),
            EntityKind::Playlist => {
                let n: u32 = cursor
                    .as_deref()
                    .unwrap_or("0")
                    .parse()
                    .map_err(|_| Error::Internal("bad cursor".into()))?;
                let first = n == 0;
                let playlist = Playlist {
                    id: id.clone(),
                    title: if first {
                        format!("Playlist {key}")
                    } else {
                        String::new()
                    },
                    owner: first.then(|| "Owner".into()),
                    description: None,
                    track_count: None,
                    artwork: if first { art(&id) } else { vec![] },
                };
                page(
                    Entity::Playlist(playlist),
                    tracks(&format!("{id}-p{n}"), &key),
                    vec![],
                    Some((n + 1).to_string()),
                )
            }
        })
    }

    fn parse_link(url: String) -> Result<Option<EntityRef>, Error> {
        check(&url)?;
        let Some((kind, id)) = url
            .strip_prefix("https://fake.test/")
            .and_then(|p| p.split_once('/'))
        else {
            return Ok(None);
        };
        let kind = match kind {
            "track" => EntityKind::Track,
            "album" => EntityKind::Album,
            "artist" => EntityKind::Artist,
            "playlist" => EntityKind::Playlist,
            _ => return Ok(None),
        };
        Ok(Some(EntityRef {
            kind,
            id: id.into(),
        }))
    }
}

fn key_of(q: &TrackQuery) -> String {
    q.title.trim().to_lowercase().replace(' ', "-")
}

impl resolve::Guest for Fake {
    fn resolve(req: ResolveRequest) -> Result<Resolved, Error> {
        check(&req.track.title)?;
        let _ = kv::set("tried", req.tried.join(",").as_bytes());
        let key = key_of(&req.track);
        let mut ids: Vec<String> = req.track.id.clone().into_iter().collect();
        ids.extend((1..=3).map(|i| format!("r-{key}-{i}")));
        ids.retain(|id| !req.tried.contains(id));
        if ids.is_empty() {
            return Err(Error::NotFound);
        }
        let id = ids.remove(0);
        let candidates = ids
            .into_iter()
            .map(|id| Candidate {
                title: req.track.title.clone(),
                artists: req.track.artists.clone(),
                duration_ms: req.track.duration_ms,
                score: 0.5,
                id,
            })
            .collect();
        let base = kv::get("stream").map(|v| String::from_utf8_lossy(&v).into_owned());
        let source = Source {
            url: format!(
                "{}/stream/{id}",
                base.as_deref().unwrap_or("https://fake.test")
            ),
            headers: vec![],
            expires_at_ms: None,
            mime: kv::get("mime").map_or("audio/webm".into(), |v| {
                String::from_utf8_lossy(&v).into_owned()
            }),
            bitrate: 128_000,
            content_length: None,
            loudness_db: Some(4.2),
        };
        Ok(Resolved {
            id,
            source,
            candidates,
        })
    }
}

impl radio::Guest for Fake {
    fn radio(seed: TrackQuery, _region: String, limit: u32) -> Result<Vec<Track>, Error> {
        check(&seed.title)?;
        let key = key_of(&seed);
        let mut out: Vec<Track> = (1..=limit)
            .map(|n| {
                track(
                    format!("radio-{key}-{n}"),
                    &format!("radio {key} {n}"),
                    &key,
                )
            })
            .collect();
        if seed.title.contains("echo") {
            let artists = seed.artists.iter().map(|name| ArtistRef {
                id: None,
                name: name.clone(),
            });
            out.insert(
                0,
                Track {
                    artists: artists.collect(),
                    ..track(format!("echo-{key}"), &seed.title, &key)
                },
            );
        }
        Ok(out)
    }
}

impl lyrics::Guest for Fake {
    fn fetch(track: TrackQuery) -> Result<Lyrics, Error> {
        check(&track.title)?;
        if track.title.contains("instrumental") {
            return Ok(Lyrics {
                plain: None,
                synced: vec![],
            });
        }
        Ok(Lyrics {
            plain: Some(format!("words of {}", track.title)),
            synced: vec![
                Line {
                    start_ms: 0,
                    text: "one".into(),
                },
                Line {
                    start_ms: 1500,
                    text: "two".into(),
                },
            ],
        })
    }
}

impl browse::Guest for Fake {
    fn categories(_region: String) -> Result<Vec<Category>, Error> {
        check("categories")?;
        let mut all = vec![
            Category {
                id: "chart:0".into(),
                title: "Top fake".into(),
                artwork: art("chart"),
                featured: true,
            },
            Category {
                id: "genre:1".into(),
                title: "Genre fake".into(),
                artwork: vec![],
                featured: false,
            },
        ];
        if no_chart_tracks() {
            all.insert(
                1,
                Category {
                    id: "chart:2".into(),
                    title: "Top fake 2".into(),
                    artwork: vec![],
                    featured: true,
                },
            );
        }
        Ok(all)
    }

    fn fetch_category(
        id: String,
        _region: String,
        cursor: Option<String>,
    ) -> Result<CategoryPage, Error> {
        check(&id)?;
        let key = format!(
            "{}-p{}",
            id.replace(':', "-"),
            cursor.as_deref().unwrap_or("0")
        );
        let shelf = |title: &str, items| Shelf {
            title: title.into(),
            items,
        };
        let playlist = Playlist {
            id: format!("p-{key}"),
            title: format!("Playlist {key}"),
            owner: None,
            description: None,
            track_count: None,
            artwork: art(&key),
        };
        let mut shelves = vec![
            shelf(
                "tracks",
                tracks(&format!("t-{key}"), &key)
                    .into_iter()
                    .map(Entity::Track)
                    .collect(),
            ),
            shelf("albums", vec![Entity::Album(album(&key))]),
            shelf("artists", vec![Entity::Artist(artist(&key))]),
            shelf("playlists", vec![Entity::Playlist(playlist)]),
        ];
        if id == "chart:0" && no_chart_tracks() {
            shelves.remove(0);
        }
        Ok(CategoryPage {
            title: format!("Category {id}"),
            shelves,
            next: cursor.is_none().then(|| "1".into()),
        })
    }

    fn releases(artist_id: String, _region: String) -> Result<Vec<Release>, Error> {
        check(&artist_id)?;
        let key = artist_id.strip_prefix("ar-").unwrap_or(&artist_id);
        // `rel-<n>` is `rel-<key>-<n>`, titled `Release <key> <n>`; `shared` is `rel-dup-shared`.
        let release = |n: &str, date: &str| {
            let (id, title) = match n {
                "shared" => ("rel-dup-shared".to_string(), "Release shared".to_string()),
                n => (format!("rel-{key}-{n}"), format!("Release {key} {n}")),
            };
            Release {
                album: Album {
                    id,
                    title,
                    ..album(key)
                },
                date: date.into(),
            }
        };
        if key.starts_with("baddate") {
            return Ok(vec![
                release("iso", "2026-10-20T08:00:00Z"),
                release("ok", "2026-10-05"),
                release("month", "2026-10"),
                release("year", "2026"),
            ]);
        }
        let mut out = vec![release("1", "2026-10-20")];
        if key.starts_with("dup") {
            out.push(release("mid", "2026-10-01"));
            out.push(release("shared", "2026-09-25"));
            out.push(release("old", "2026-09-24"));
        }
        out.push(release("2", "2026-09-01"));
        Ok(out)
    }
}

export!(Fake);
