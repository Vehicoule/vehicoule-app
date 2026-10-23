//! The `fake-catalog` guest (core/core/tests/guests) loaded twice in the test binary's one
//! `App`: `fake` (routed first) and `fake-b`. Tests share that App, so they run one at a
//! time (`setup`) and use their own queries and ids.

use std::path::PathBuf;
use std::process::Command;
use std::sync::OnceLock;

use plugin_host::{Capability, Plugin};
use tokio::sync::{Mutex, MutexGuard};

use super::*;
use crate::app::{App, test_app};
use crate::library::catalog::{Image, collection};
use crate::library::{ItemId, Kind, Page, kv, playlists, refs, search as history};

const IDS: [&str; 2] = ["fake", "fake-b"];

/// Built once per test binary, like plugin-host's guests.
fn fake_wasm() -> Vec<u8> {
    static BUILT: OnceLock<PathBuf> = OnceLock::new();
    let dir = BUILT.get_or_init(|| {
        let guests = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/guests");
        let status = Command::new(env!("CARGO"))
            .args(["build", "--release", "--target", "wasm32-wasip2"])
            .current_dir(&guests)
            .env_remove("CARGO_TARGET_DIR")
            .status()
            .expect("cargo build guests");
        assert!(status.success(), "guest build failed");
        guests.join("target/wasm32-wasip2/release")
    });
    std::fs::read(dir.join("fake_catalog.wasm")).unwrap()
}

/// `fake` may fetch from fake.test; `fake-b` only from b.fake.test.
fn manifest(id: &str) -> String {
    let domain = if id == "fake" {
        "fake.test"
    } else {
        "b.fake.test"
    };
    format!(
        r#"{{"id":"{id}","name":"{id}","version":"1.0.0","contract":"1.0","domains":["{domain}"]}}"#
    )
}

/// Takes the catalogue lock; both plugins loaded, online, no `mode`, default stream URL and mime.
pub(crate) async fn setup() -> (MutexGuard<'static, ()>, &'static App) {
    static LOCK: Mutex<()> = Mutex::const_new(());
    static PLUGINS: OnceLock<Vec<Plugin>> = OnceLock::new();
    let guard = LOCK.lock().await;
    let app = test_app();
    let plugins = PLUGINS.get_or_init(|| {
        let wasm = fake_wasm();
        IDS.iter()
            .map(|id| {
                app.plugins
                    .host()
                    .load(manifest(id).as_bytes(), &wasm)
                    .unwrap()
            })
            .collect()
    });
    app.plugins.replace_loaded(plugins.clone());
    app.set_online(true);
    for id in IDS {
        set_mode(id, "").await;
        app.db
            .write(move |tx| {
                kv::delete(tx, id, "stream")?;
                kv::delete(tx, id, "mime")
            })
            .await
            .unwrap();
    }
    (guard, app)
}

/// kv `mode` of a fake plugin; empty = normal.
pub(crate) async fn set_mode(plugin: &'static str, mode: &'static str) {
    test_app()
        .db
        .write(move |tx| match mode {
            "" => kv::delete(tx, plugin, "mode"),
            m => kv::set(tx, plugin, "mode", m.as_bytes()),
        })
        .await
        .unwrap();
}

/// Capability calls the fake plugins have answered so far (the guest counts them in kv).
pub(crate) async fn calls() -> u64 {
    let mut n = 0;
    for id in IDS {
        let v = test_app()
            .db
            .read(move |c| kv::get(c, id, "calls"))
            .await
            .unwrap();
        n += v.map_or(0, |v| String::from_utf8(v).unwrap().parse::<u64>().unwrap());
    }
    n
}

fn item(id: &str) -> ItemId {
    ItemId(uuid::Uuid::parse_str(id).unwrap())
}

fn texts(s: Vec<SuggestionView>) -> Vec<String> {
    s.into_iter().map(|s| s.text).collect()
}

fn titles(tracks: &[TrackView]) -> Vec<&str> {
    tracks.iter().map(|t| t.title.as_str()).collect()
}

#[test]
fn catalogue_futures_are_send() {
    fn send<T: Send>(_: T) {}
    send(search("x"));
    send(suggest("x"));
    send(entity("x", None));
    send(import_playlist("x"));
    send(artwork_file("x", 1));
}

#[tokio::test]
async fn search_falls_back_when_first_plugin_finds_nothing() {
    let (_lock, _) = setup().await;
    set_mode("fake", "empty").await;
    let r = search("fallback song").await.unwrap();
    assert_eq!(r.source, "fake-b");
    assert_eq!(titles(&r.tracks), ["fallback song"]);
    // Both empty: not found.
    set_mode("fake-b", "empty").await;
    assert_eq!(search("fallback song").await, Err(CoreError::NotFound));
    // A network failure stops the routing at once.
    set_mode("fake", "network").await;
    set_mode("fake-b", "").await;
    assert_eq!(search("fallback song").await, Err(CoreError::Network));
    // No plugin with the capability at all.
    test_app().plugins.replace_loaded(vec![]);
    assert_eq!(
        search("fallback song").await,
        Err(CoreError::NoPlugin(Capability::Search))
    );
}

#[tokio::test]
async fn search_results_are_stored_with_refs() {
    let (_lock, app) = setup().await;
    let r = search("Stored Halo").await.unwrap();
    assert_eq!(r.source, "fake");
    let t = &r.tracks[0];
    assert_eq!(t.title, "Stored Halo");
    assert_eq!(t.artists[0].name, "Artist stored-halo");
    assert_eq!(t.album.as_ref().unwrap().title, "Album stored-halo");
    assert_eq!(t.duration_ms, Some(180_000));
    let (album, artist, playlist) = (&r.albums[0], &r.artists[0], &r.playlists[0]);
    assert_eq!(
        (album.kind, artist.kind, playlist.kind),
        (ItemKind::Album, ItemKind::Artist, ItemKind::Playlist)
    );
    assert_eq!(playlist.subtitle.as_deref(), Some("Owner"));
    assert!(!playlist.is_user_playlist);
    let ids = [&t.id, &album.id, &artist.id, &playlist.id].map(|id| item(id));
    let (found, recorded) = app
        .db
        .read(|c| {
            let found = [
                (Kind::Track, "t-stored-halo"),
                (Kind::Album, "a-stored-halo"),
                (Kind::Artist, "ar-stored-halo"),
                (Kind::Playlist, "p-stored-halo"),
            ]
            .map(|(kind, ext)| refs::item_for(c, "fake", kind, ext).unwrap());
            Ok((found, history::history(c, "stored", 5)?))
        })
        .await
        .unwrap();
    assert_eq!(found, ids.map(Some));
    // The album of the track is the album of the results.
    assert_eq!(t.album.as_ref().unwrap().id, album.id);
    assert_eq!(recorded, ["Stored Halo"]);
}

#[tokio::test]
async fn suggestions_start_with_local_history() {
    let (_lock, _) = setup().await;
    search("sugg halo").await.unwrap();
    assert_eq!(
        texts(suggest("Sugg").await.unwrap()),
        ["sugg halo", "Sugg live", "Sugg remix"]
    );
    // A failing plugin never blocks the suggestions.
    for id in IDS {
        set_mode(id, "network").await;
    }
    assert_eq!(texts(suggest("sugg").await.unwrap()), ["sugg halo"]);
}

#[tokio::test]
async fn suggest_marks_history_entries() {
    let (_lock, app) = setup().await;
    app.db
        .write(|tx| history::record_query(tx, "YOASOBI Live"))
        .await
        .unwrap();
    // The plugin answers "yoasobi live" and "yoasobi remix": the first is folded into the
    // history entry.
    let got: Vec<_> = suggest("yoasobi")
        .await
        .unwrap()
        .into_iter()
        .map(|s| (s.text, s.from_history))
        .collect();
    assert_eq!(
        got,
        [
            ("YOASOBI Live".to_string(), true),
            ("yoasobi remix".to_string(), false)
        ]
    );
}

#[tokio::test]
async fn entity_serves_cache_when_network_fails() {
    let (_lock, _) = setup().await;
    let r = search("cached").await.unwrap();
    let album = r.albums[0].id.clone();
    let page = entity(&album, None).await.unwrap();
    assert!(!page.from_cache);
    assert_eq!(page.header.title, "Album cached");
    assert_eq!(page.header.id, album);
    assert_eq!(titles(&page.tracks), ["a-cached 1", "a-cached 2"]);
    assert_eq!(page.next, None);

    // Pages after the first keep the first page's header (title, owner).
    let playlist = r.playlists[0].id.clone();
    let first = entity(&playlist, None).await.unwrap();
    assert_eq!(first.next.as_deref(), Some("1"));
    let second = entity(&playlist, first.next.clone()).await.unwrap();
    assert_eq!(second.header.title, "Playlist cached");
    assert_eq!(second.header.subtitle.as_deref(), Some("Owner"));
    assert_eq!(titles(&second.tracks), ["p-cached-p1 1", "p-cached-p1 2"]);

    set_mode("fake", "network").await;
    let cached = entity(&album, None).await.unwrap();
    assert!(cached.from_cache);
    assert_eq!(cached.header, page.header);
    assert_eq!(cached.tracks, page.tracks);
    assert_eq!(cached.next, None);
    // Both pages were kept.
    let cached = entity(&playlist, None).await.unwrap();
    assert_eq!(cached.tracks.len(), 4);
    // Nothing cached (never fetched), or a later page: the error.
    assert_eq!(
        entity(&r.artists[0].id, None).await,
        Err(CoreError::Network)
    );
    assert_eq!(
        entity(&playlist, Some("2".into())).await,
        Err(CoreError::Network)
    );
    // Unknown or malformed ids.
    assert_eq!(
        entity(&ItemId::new().to_string(), None).await,
        Err(CoreError::NotFound)
    );
    assert!(matches!(
        entity("not-a-uuid", None).await,
        Err(CoreError::Internal(_))
    ));
}

#[tokio::test]
async fn user_playlist_entity_is_not_from_cache() {
    let (_lock, app) = setup().await;
    let track = item(&search("mine").await.unwrap().tracks[0].id);
    let id = app
        .db
        .write(move |tx| {
            let id = playlists::create(tx, "Mine", None)?;
            playlists::add(tx, id, &[track], playlists::Place::End)?;
            Ok(id)
        })
        .await
        .unwrap();
    let page = entity(&id.to_string(), None).await.unwrap();
    assert!(page.header.is_user_playlist);
    assert!(!page.from_cache);
    assert_eq!(titles(&page.tracks), ["mine"]);
}

#[tokio::test]
async fn unknown_link_is_not_found() {
    let (_lock, _) = setup().await;
    assert_eq!(
        import_playlist("https://unknown.example/playlist/1").await,
        Err(CoreError::NotFound)
    );
    // A provider link to something that is not a list of tracks.
    assert_eq!(
        import_playlist("https://fake.test/artist/ar-x").await,
        Err(CoreError::NotFound)
    );
}

#[tokio::test]
async fn import_follows_pages_up_to_50() {
    let (_lock, app) = setup().await;
    let before = calls().await;
    let imported = import_playlist("https://fake.test/playlist/p-big")
        .await
        .unwrap();
    let id = item(&imported.id);
    // One parse-link, then 50 pages and no more: the UI says it was cut.
    assert_eq!(calls().await - before, 51);
    assert!(imported.truncated);
    let album = import_playlist("https://fake.test/album/al-whole")
        .await
        .unwrap();
    assert!(!album.truncated);
    let (row, entries) = app
        .db
        .read(move |c| {
            let entries = playlists::entries(
                c,
                id,
                Page {
                    offset: 0,
                    limit: 1000,
                },
            )?;
            Ok((collection(c, id)?.unwrap(), entries))
        })
        .await
        .unwrap();
    assert!(row.user);
    assert_eq!(row.title, "Playlist big");
    assert_eq!(row.track_count, Some(100));
    let first = entries.first().unwrap().1;
    let last = entries.last().unwrap().1;
    let titles = app
        .db
        .read(move |c| {
            let t = |i| crate::library::catalog::track(c, i).map(|t| t.unwrap().title);
            Ok((t(first)?, t(last)?))
        })
        .await
        .unwrap();
    assert_eq!(titles, ("p-big-p0 1".into(), "p-big-p49 2".into()));
}

#[tokio::test]
async fn offline_search_is_refused_without_calls() {
    let (_lock, app) = setup().await;
    let r = search("offline seed").await.unwrap();
    let album = r.albums[0].id.clone();
    entity(&album, None).await.unwrap();
    let before = calls().await;
    app.set_online(false);
    assert_eq!(search("offline seed").await, Err(CoreError::Offline));
    assert_eq!(
        import_playlist("https://fake.test/playlist/p-x").await,
        Err(CoreError::Offline)
    );
    assert_eq!(
        entity(&r.playlists[0].id, None).await,
        Err(CoreError::Offline)
    );
    // Local only: the history, and pages already cached.
    assert_eq!(texts(suggest("offline").await.unwrap()), ["offline seed"]);
    assert!(entity(&album, None).await.unwrap().from_cache);
    assert_eq!(calls().await, before);
    app.set_online(true);
}

#[tokio::test]
async fn artwork_outside_the_allowlist_is_never_fetched() {
    let (_lock, _) = setup().await;
    // `fake-b` answers with fake.test artwork, outside its own allowlist (b.fake.test).
    set_mode("fake", "empty").await;
    let r = search("foreign art").await.unwrap();
    assert_eq!(r.source, "fake-b");
    assert_eq!(artwork_file(&r.tracks[0].id, 300).await, Ok(None));
    assert_eq!(
        artwork_file(&ItemId::new().to_string(), 300).await,
        Ok(None)
    );
}

#[test]
fn artwork_picks_smallest_width_at_least_size() {
    let img = |w: Option<u32>| Image {
        url: format!("{w:?}"),
        width: w,
    };
    let list = [img(Some(1000)), img(None), img(Some(250)), img(Some(500))];
    let width = |size| pick(&list, size).and_then(|i| i.width);
    assert_eq!(width(200), Some(250));
    assert_eq!(width(251), Some(500));
    assert_eq!(width(500), Some(500));
    // None large enough: the largest.
    assert_eq!(width(2000), Some(1000));
    assert_eq!(pick(&[], 10), None);
    assert_eq!(pick(&[img(None)], 10).map(|i| i.width), Some(None));
}
