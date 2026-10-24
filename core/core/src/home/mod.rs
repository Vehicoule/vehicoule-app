//! The home feed (spec UI 6.1, 7.2): seeds read from the library, a discovery list merged
//! from their radios, shelves assembled in a fixed order and stored in kv `@core`/`home_feed`.
//! The core produces no text: a shelf is a kind and, for some, a seed's name.
//!
//! Read by pages of 4 shelves; a "because you listened" shelf loads on its first read.
//! Rebuilt in the background when over 24 h old (first page, back online), or on demand.

mod assemble;
mod seeds;

use std::collections::HashSet;

use rusqlite::Connection;
use serde::{Deserialize, Serialize};

use assemble::assemble;
use seeds::TRACK_SEEDS;

use crate::api::browse::CategoryPageView;
use crate::api::library::{HomeFeedPage, ShelfView};
use crate::api::settings::DISCOVER;
use crate::app::app;
use crate::browse;
use crate::catalog::{self as views, CardView, parse_id};
use crate::error::CoreError;
use crate::events::LibraryChanged;
use crate::library::catalog;
use crate::library::{ItemId, kv, plays, settings};
use crate::logs;
use crate::player;
use crate::plugins::now_ms;

/// The core's kv namespace, as in `browse`.
const NS: &str = "@core";
const KEY: &str = "home_feed";
/// New releases: out less than 30 days ago.
const RELEASES_MS: i64 = 30 * 86_400_000;
/// The featured chart (Deezer's Top 50); else the first featured category.
const CHART: &str = "chart:0";
/// Shelves per page.
const PAGE: usize = 4;
/// Older, the doc is rebuilt in the background.
const STALE_MS: i64 = 24 * 3600 * 1000;
/// "Because you listened": albums and artists.
const BECAUSE_ITEMS: usize = 12;

/// Held by the running build: one at a time.
static BUILD: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

/// Stored as is: the bridge's kind is the doc's.
pub(crate) use crate::api::library::ShelfKindView as ShelfKind;

#[derive(Debug, PartialEq, Serialize, Deserialize)]
pub(crate) struct StoredItem {
    pub id: String,
    /// Discovery: the seed's title.
    pub reason: Option<String>,
}

#[derive(Debug, PartialEq, Serialize, Deserialize)]
pub(crate) struct StoredShelf {
    pub kind: ShelfKind,
    /// "Because you listened": the artist's name and id.
    pub seed: Option<String>,
    pub seed_id: Option<String>,
    /// Built from (or, for mixes, played through) a plugin: hidden when `discover` is off.
    pub network: bool,
    /// `false`: to load on demand (Task 7), `items` empty until then.
    pub loaded: bool,
    pub items: Vec<StoredItem>,
}

#[derive(Debug, PartialEq, Serialize, Deserialize)]
pub(crate) struct FeedDoc {
    pub built_at_ms: i64,
    /// Built without asking the plugins (offline, `discover` off, or the local first doc).
    #[serde(default)]
    pub offline: bool,
    pub shelves: Vec<StoredShelf>,
}

/// Reads the seeds, asks the plugins when `discover` is on and online (a failing source is
/// left empty and logged), assembles the shelves and stores the doc.
pub(crate) async fn build(now_ms: i64) -> Result<FeedDoc, CoreError> {
    build_doc(now_ms, true).await
}

/// `build`; without `ask`, as if offline.
async fn build_doc(now_ms: i64, ask: bool) -> Result<FeedDoc, CoreError> {
    let app = app();
    let discover = app.db.read(discover_on).await?;
    let mut local = app.db.read(move |c| seeds::read(c, now_ms)).await?;
    let ask = ask && discover && app.is_online();
    if ask {
        network(&mut local, now_ms).await?;
    }
    let doc = FeedDoc {
        built_at_ms: now_ms,
        offline: !ask,
        shelves: assemble(local.inputs, discover),
    };
    let bytes = serde_json::to_vec(&doc).map_err(|e| CoreError::Internal(e.to_string()))?;
    app.db.write(move |tx| kv::set(tx, NS, KEY, &bytes)).await?;
    Ok(doc)
}

/// The `discover` device setting: on unless `false`.
fn discover_on(c: &Connection) -> rusqlite::Result<bool> {
    Ok(settings::device_get(c, DISCOVER)?.as_deref() != Some("false"))
}

/// `build`, then `LibraryChanged::Home`. Offline: `Offline`, so the last copy built with
/// the network is kept.
async fn rebuild() -> Result<(), CoreError> {
    views::online()?;
    build(now_ms()).await?;
    let _ = app().events.library.send(LibraryChanged::Home);
    Ok(())
}

/// `rebuild` now; when a build is already running, waits for it instead (it sends `Home`).
pub(crate) async fn refresh() -> Result<(), CoreError> {
    views::online()?;
    match BUILD.try_lock() {
        Ok(_one) => rebuild().await,
        Err(_) => {
            drop(BUILD.lock().await);
            Ok(())
        }
    }
}

/// `rebuild` on the app's runtime, unless one is running already.
fn in_background() {
    let Ok(one) = BUILD.try_lock() else {
        return;
    };
    app().rt.spawn(async move {
        let _one = one;
        logged("build", rebuild().await);
    });
}

/// The stored doc; an unreadable one counts as none.
async fn read_doc() -> Result<Option<FeedDoc>, CoreError> {
    let bytes = app().db.read(|c| kv::get(c, NS, KEY)).await?;
    Ok(bytes.and_then(|b| {
        let doc = serde_json::from_slice(&b);
        logged("doc", doc.map_err(|e| CoreError::Internal(e.to_string())))
    }))
}

/// Missing, over 24 h old, or built without the network while it could now be asked
/// (`network`: online with `discover` on).
fn stale(doc: Option<&FeedDoc>, now_ms: i64, network: bool) -> bool {
    doc.is_none_or(|d| now_ms - d.built_at_ms >= STALE_MS || (d.offline && network))
}

/// Back online: a stale doc is rebuilt in the background.
pub(crate) async fn on_online() {
    let Some(doc) = logged("doc", read_doc().await) else {
        return;
    };
    let Some(discover) = logged("doc", app().db.read(discover_on).await.map_err(Into::into)) else {
        return;
    };
    if stale(doc.as_ref(), now_ms(), discover && app().is_online()) {
        in_background();
    }
}

/// Up to `PAGE` shelves from the shelf index `cursor`. Online, the first page of a stale doc
/// starts a background build (offline, the last copy is kept: `on_online` rebuilds it). A
/// missing doc is first built locally (no plugin call).
pub(crate) async fn page(cursor: Option<String>) -> Result<HomeFeedPage, CoreError> {
    let start = match &cursor {
        Some(c) => c.parse::<usize>().map_err(|_| CoreError::NotFound)?,
        None => 0,
    };
    let now = now_ms();
    let discover = app().db.read(discover_on).await?;
    let online = app().is_online();
    let ask = discover && online;
    let doc = read_doc().await?;
    let rebuild = cursor.is_none() && online && stale(doc.as_ref(), now, ask);
    let doc = match doc {
        Some(d) => d,
        None => build_doc(now, false).await?,
    };
    if rebuild {
        in_background();
    }
    let mut out = HomeFeedPage {
        shelves: vec![],
        next: None,
    };
    let mut loaded = vec![];
    for (i, shelf) in doc.shelves.iter().enumerate().skip(start) {
        if out.shelves.len() == PAGE {
            out.next = Some(i.to_string());
            break;
        }
        if shelf.network && !discover {
            continue;
        }
        let items = match (&shelf.seed_id, shelf.loaded) {
            (Some(artist), false) if ask => {
                let Some(items) = logged("because", load_because(artist).await) else {
                    continue;
                };
                loaded.push((i, items));
                &loaded[loaded.len() - 1].1
            }
            (_, false) => continue,
            (_, true) => &shelf.items,
        };
        let view = view_of(shelf, items).await?;
        if view.kind == ShelfKind::End {
            out.shelves.push(view);
            break;
        }
        if !view.items.is_empty() {
            out.shelves.push(view);
        }
    }
    if !loaded.is_empty() {
        // Not stored: loaded again on a later read.
        logged("because", store_loaded(doc.built_at_ms, loaded).await);
    }
    Ok(out)
}

/// The shelf as cards; items gone from the catalogue left out.
async fn view_of(shelf: &StoredShelf, items: &[StoredItem]) -> Result<ShelfView, CoreError> {
    let ids: Vec<_> = items
        .iter()
        .filter_map(|i| Some((parse_id(&i.id).ok()?, i.reason.clone())))
        .collect();
    let cards = app()
        .db
        .read(move |c| {
            let mut out = Vec::with_capacity(ids.len());
            for (id, reason) in ids {
                out.extend(card(c, id, reason)?);
            }
            Ok(out)
        })
        .await?;
    Ok(ShelfView {
        kind: shelf.kind,
        seed: shelf.seed.clone(),
        items: cards,
    })
}

fn card(c: &Connection, id: ItemId, why: Option<String>) -> rusqlite::Result<Option<CardView>> {
    Ok(browse::card(c, id)?.map(|card| match card {
        CardView::Track { track, .. } => CardView::Track { track, reason: why },
        other => other,
    }))
}

/// Writes the shelves loaded into the doc, unless a build replaced it meanwhile.
async fn store_loaded(
    built_at_ms: i64,
    loaded: Vec<(usize, Vec<StoredItem>)>,
) -> Result<(), CoreError> {
    app()
        .db
        .write(move |tx| {
            let Some(bytes) = kv::get(&tx.tx, NS, KEY)? else {
                return Ok(());
            };
            let Ok(mut doc) = serde_json::from_slice::<FeedDoc>(&bytes) else {
                return Ok(());
            };
            if doc.built_at_ms != built_at_ms {
                return Ok(());
            }
            for (i, items) in loaded {
                if let Some(s) = doc.shelves.get_mut(i) {
                    s.loaded = true;
                    s.items = items;
                }
            }
            let bytes = serde_json::to_vec(&doc)
                .map_err(|e| rusqlite::Error::ToSqlConversionFailure(e.into()))?;
            kv::set(tx, NS, KEY, &bytes)
        })
        .await?;
    Ok(())
}

/// The artist's radio (from `seed_track`) as its distinct albums and artists, the artist
/// left out: at most 12.
async fn load_because(artist: &str) -> Result<Vec<StoredItem>, CoreError> {
    let artist = parse_id(artist)?;
    let seed = seed_track(artist).await?.ok_or(CoreError::NotFound)?;
    let found = player::radio_tracks(seed).await?;
    let tracks = app().db.read(move |c| catalog::tracks(c, &found)).await?;
    let mut ids = vec![];
    for t in tracks {
        let album = t.album.map(|a| a.0);
        for id in album.into_iter().chain(t.artists.into_iter().map(|a| a.0)) {
            if id != artist && !ids.contains(&id) {
                ids.push(id);
            }
        }
    }
    ids.truncate(BECAUSE_ITEMS);
    Ok(ids
        .into_iter()
        .map(|id| StoredItem {
            id: id.to_string(),
            reason: None,
        })
        .collect())
}

/// The artist's most played track (all time), else the first of its `entity` page.
pub(crate) async fn seed_track(artist: ItemId) -> Result<Option<ItemId>, CoreError> {
    let top = app()
        .db
        .read(move |c| plays::top_track_of(c, artist))
        .await?;
    Ok(match top {
        Some(t) => Some(t),
        None => first_track(artist).await,
    })
}

/// Fills the network inputs: discovery, releases, chart.
async fn network(local: &mut seeds::Local, now_ms: i64) -> Result<(), CoreError> {
    let mut picked = std::mem::take(&mut local.track_seeds);
    for &(artist, top) in &local.liked_artists {
        if picked.len() >= TRACK_SEEDS {
            break;
        }
        let track = match top {
            Some(t) => Some(t),
            None => first_track(artist).await,
        };
        seeds::push_new(&mut picked, track, TRACK_SEEDS);
    }
    let chart = logged("chart", chart().await).unwrap_or_default();
    if picked.is_empty() {
        picked = chart.iter().copied().take(TRACK_SEEDS).collect();
    }
    let inputs = &mut local.inputs;
    inputs.excluded.extend(picked.iter().copied());
    // Another edition of a seed (other id, same title and artist) stays out too.
    let ids = picked.clone();
    let keys = app().db.read(move |c| seeds::candidates(c, &ids)).await?;
    inputs
        .folded_excluded
        .extend(keys.into_iter().map(|k| k.folded));
    for seed in picked {
        let Some(found) = logged("radio", player::radio_tracks(seed).await) else {
            continue;
        };
        let (title, candidates) = app()
            .db
            .read(move |c| {
                let title = catalog::track(c, seed)?.map(|t| t.title);
                Ok((title.unwrap_or_default(), seeds::candidates(c, &found)?))
            })
            .await?;
        inputs.discovery.push((title, candidates));
    }
    let since = date(now_ms - RELEASES_MS);
    let mut releases = Vec::new();
    for &(artist, _) in &local.liked_artists {
        let found = logged("releases", browse::releases(artist).await).unwrap_or_default();
        releases.extend(found.into_iter().filter(|r| r.1 >= since));
    }
    releases.sort_by(|a, b| b.1.cmp(&a.1));
    let mut seen = HashSet::new();
    inputs.releases = releases
        .into_iter()
        .map(|r| r.0)
        .filter(|&id| seen.insert(id))
        .take(seeds::ROWS as usize)
        .collect();
    inputs.chart = chart;
    Ok(())
}

/// The first track of the artist's `entity` page.
async fn first_track(artist: ItemId) -> Option<ItemId> {
    let page = logged("entity", views::entity(&artist.to_string(), None).await)?;
    parse_id(&page.tracks.first()?.id).ok()
}

/// The first track shelf of the featured chart: `chart:0`, else (failing, or without tracks)
/// the first other featured category.
async fn chart() -> Result<Vec<ItemId>, CoreError> {
    let main = browse::category(CHART.into(), None).await.map(tracks_of);
    match main {
        Ok(ids) if !ids.is_empty() => return Ok(ids),
        Err(e @ (CoreError::NoPlugin(_) | CoreError::Offline)) => return Err(e),
        _ => {}
    }
    let mut featured = browse::categories().await?.into_iter();
    match featured.find(|c| c.featured && c.id != CHART) {
        Some(c) => browse::category(c.id, None).await.map(tracks_of),
        None => main,
    }
}

/// The track ids of the page's first `tracks` shelf.
fn tracks_of(page: CategoryPageView) -> Vec<ItemId> {
    let Some(shelf) = page.shelves.into_iter().find(|s| s.title == "tracks") else {
        return vec![];
    };
    shelf
        .items
        .iter()
        .filter_map(|c| match c {
            CardView::Track { track, .. } => parse_id(&track.id).ok(),
            CardView::Collection(_) => None,
        })
        .collect()
}

/// `r`'s value; its error logged, unless no plugin has the capability (nothing went wrong).
fn logged<T>(source: &str, r: Result<T, CoreError>) -> Option<T> {
    r.inspect_err(|e| {
        if !matches!(e, CoreError::NoPlugin(_)) {
            logs::push("warn", "home", &format!("{source}: {e:?}"));
        }
    })
    .ok()
}

/// The UTC `YYYY-MM-DD` of a unix ms time (days to civil date, H. Hinnant).
fn date(ms: i64) -> String {
    let z = ms.div_euclid(86_400_000) + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + i64::from(m <= 2);
    format!("{y:04}-{m:02}-{d:02}")
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use crate::app::test_app;
    use crate::catalog;
    use crate::catalog::tests::{calls, set_mode, setup};
    use crate::library::{likes, plays};
    use crate::plugins::now_ms;

    const DAY_MS: i64 = 86_400_000;
    /// 2026-10-25T00:00Z: 30 days back is 2026-09-25.
    const OCT_25: i64 = 1_792_886_400_000;

    /// An empty library: no plays, likes, downloads nor user playlists; no `@core` copy;
    /// `discover` unset.
    pub(crate) async fn wipe() {
        test_app()
            .db
            .write(|tx| {
                tx.tx.execute_batch(
                    "DELETE FROM plays; DELETE FROM likes; DELETE FROM downloads;
                     UPDATE playlists SET deleted_at = 1 WHERE deleted_at IS NULL;
                     DELETE FROM plugin_kv WHERE plugin_id = '@core';
                     DELETE FROM settings_device WHERE key = 'discover';",
                )
            })
            .await
            .unwrap();
    }

    /// The track a search for `q` stores: (track, its album, its artist).
    pub(crate) async fn song(q: &str) -> (ItemId, ItemId, ItemId) {
        let t = catalog::search(q).await.unwrap().tracks.remove(0);
        (
            parse_id(&t.id).unwrap(),
            parse_id(&t.album.unwrap().id).unwrap(),
            parse_id(&t.artists[0].id).unwrap(),
        )
    }

    /// A one-minute play of `t` a day ago, from `ctx`.
    pub(crate) async fn play(t: ItemId, ctx: Option<ItemId>) {
        let at = now_ms() - DAY_MS;
        test_app()
            .db
            .write(move |tx| {
                let p = plays::start(tx, t, "test", ctx)?;
                tx.tx.execute(
                    "UPDATE plays SET started_at = ?2, listened_ms = 60000 WHERE id = ?1",
                    rusqlite::params![p.as_bytes().as_slice(), at],
                )?;
                Ok(())
            })
            .await
            .unwrap();
    }

    async fn like(item: ItemId) {
        test_app()
            .db
            .write(move |tx| likes::set(tx, item, true))
            .await
            .unwrap();
    }

    fn kinds(doc: &FeedDoc) -> Vec<ShelfKind> {
        doc.shelves.iter().map(|s| s.kind).collect()
    }

    fn items(doc: &FeedDoc, kind: ShelfKind) -> Vec<String> {
        doc.shelves
            .iter()
            .find(|s| s.kind == kind)
            .map(|s| s.items.iter().map(|i| i.id.clone()).collect())
            .unwrap_or_default()
    }

    fn reasons(doc: &FeedDoc) -> HashSet<String> {
        doc.shelves
            .iter()
            .filter(|s| s.kind == ShelfKind::Discovery)
            .flat_map(|s| s.items.iter().map(|i| i.reason.clone().unwrap()))
            .collect()
    }

    #[test]
    fn date_is_the_utc_day() {
        assert_eq!(date(0), "1970-01-01");
        assert_eq!(date(951_782_400_000), "2000-02-29");
        assert_eq!(date(951_782_400_000 - 1), "2000-02-28");
        assert_eq!(date(-1), "1969-12-31");
    }

    #[test]
    fn build_future_is_send() {
        fn send<T: Send>(_: T) {}
        send(build(0));
    }

    #[tokio::test]
    async fn feed_offline_keeps_local_shelves() {
        use ShelfKind::*;
        let (_lock, app) = setup().await;
        wipe().await;
        let (t, album, _) = song("home offline a").await;
        let (u, _, _) = song("home offline b").await;
        play(t, Some(album)).await;
        like(u).await;
        app.set_online(false);
        let before = calls().await;
        let doc = build(now_ms()).await.unwrap();
        assert_eq!(calls().await, before);
        assert_eq!(
            kinds(&doc),
            [
                Shortcuts,
                Mixes,
                BecauseYouListened,
                Rediscover,
                Recent,
                End
            ]
        );
        assert_eq!(items(&doc, Shortcuts), [album.to_string()]);
        assert_eq!(items(&doc, Recent), [t.to_string()]);
        assert_eq!(items(&doc, Rediscover), [u.to_string()]);
    }

    #[tokio::test]
    async fn feed_first_launch_seeds_from_chart() {
        let (_lock, app) = setup().await;
        wipe().await;
        let doc = build(now_ms()).await.unwrap();
        assert_eq!(items(&doc, ShelfKind::Discovery).len(), 30);
        let chart = HashSet::from(["t-chart-0-p0 1".to_string(), "t-chart-0-p0 2".into()]);
        assert_eq!(reasons(&doc), chart);
        assert_eq!(items(&doc, ShelfKind::Chart).len(), 2);
        // Without a browse plugin (nor any other): only the end.
        wipe().await;
        app.plugins.replace_loaded(vec![]);
        let doc = build(now_ms()).await.unwrap();
        assert_eq!(kinds(&doc), [ShelfKind::End]);
    }

    #[tokio::test]
    async fn liked_artists_seed_the_feed_without_plays() {
        let (_lock, _) = setup().await;
        wipe().await;
        let mut artists = HashSet::new();
        for k in ["a", "b", "c"] {
            let (_, _, artist) = song(&format!("seedart {k}")).await;
            like(artist).await;
            artists.insert(artist.to_string());
        }
        let doc = build(now_ms()).await.unwrap();
        let want: HashSet<String> = ["a", "b", "c"].map(|k| format!("ar-seedart-{k} 1")).into();
        assert_eq!(reasons(&doc), want);
        assert_eq!(items(&doc, ShelfKind::Discovery).len(), 30);
        let mixes: HashSet<String> = items(&doc, ShelfKind::Mixes).into_iter().collect();
        assert_eq!(mixes, artists);
    }

    #[tokio::test]
    async fn discover_off_makes_no_network_call() {
        use ShelfKind::*;
        let (_lock, app) = setup().await;
        wipe().await;
        let (t, album, _) = song("home private a").await;
        let (u, _, artist) = song("home private b").await;
        play(t, Some(album)).await;
        like(u).await;
        like(artist).await;
        app.db
            .write(|tx| settings::device_set(tx, "discover", "false"))
            .await
            .unwrap();
        let before = calls().await;
        let doc = build(now_ms()).await.unwrap();
        assert_eq!(calls().await, before);
        assert_eq!(kinds(&doc), [Shortcuts, Rediscover, Recent, End]);
        assert!(doc.shelves.iter().all(|s| !s.network));
        wipe().await;
    }

    #[tokio::test]
    async fn build_writes_the_feed_doc() {
        let (_lock, app) = setup().await;
        wipe().await;
        let (t, album, _) = song("home doc a").await;
        play(t, Some(album)).await;
        let now = now_ms();
        let doc = build(now).await.unwrap();
        assert_eq!(doc.built_at_ms, now);
        let bytes = app
            .db
            .read(|c| kv::get(c, "@core", "home_feed"))
            .await
            .unwrap()
            .unwrap();
        let stored: FeedDoc = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(stored, doc);
    }

    /// Likes the artist of the track a search for `q` stores.
    async fn liked_artist(q: &str) -> ItemId {
        let (_, _, artist) = song(q).await;
        like(artist).await;
        artist
    }

    #[tokio::test]
    async fn new_releases_are_recent_newest_first_and_distinct() {
        let (_lock, _) = setup().await;
        wipe().await;
        let mut dates = std::collections::HashMap::new();
        for q in ["dup a", "dup b"] {
            let artist = liked_artist(q).await;
            for (id, date) in browse::releases(artist).await.unwrap() {
                dates.insert(id.to_string(), date);
            }
        }
        let doc = build(OCT_25).await.unwrap();
        let ids = items(&doc, ShelfKind::NewReleases);
        let got: Vec<&str> = ids.iter().map(|id| dates[id].as_str()).collect();
        // 2026-09-25 is in (exactly 30 days), 2026-09-24 out; the shared album once.
        assert_eq!(
            got,
            [
                "2026-10-20",
                "2026-10-20",
                "2026-10-01",
                "2026-10-01",
                "2026-09-25"
            ]
        );
        assert_eq!(ids.iter().collect::<HashSet<_>>().len(), ids.len());
    }

    #[tokio::test]
    async fn new_releases_are_capped_at_20() {
        let (_lock, _) = setup().await;
        wipe().await;
        // 2 recent releases each, plus the shared one: 21.
        for k in 0..10 {
            liked_artist(&format!("dup cap {k}")).await;
        }
        let doc = build(OCT_25).await.unwrap();
        assert_eq!(items(&doc, ShelfKind::NewReleases).len(), 20);
    }

    #[tokio::test]
    async fn no_plugin_logs_no_warning() {
        let (_lock, app) = setup().await;
        wipe().await;
        liked_artist("home noplugin").await;
        app.plugins.replace_loaded(vec![]);
        let start = now_ms();
        build(now_ms()).await.unwrap();
        let home: Vec<String> = logs::recent()
            .into_iter()
            .filter(|l| l.at_ms >= start && l.source == "home")
            .map(|l| l.message)
            .collect();
        assert_eq!(home, Vec::<String>::new());
    }

    #[tokio::test]
    async fn chart_without_tracks_falls_back_to_the_next_featured() {
        let (_lock, app) = setup().await;
        wipe().await;
        app.db
            .write(|tx| kv::set(tx, "fake", "chart", b"no-tracks"))
            .await
            .unwrap();
        let doc = build(now_ms()).await.unwrap();
        assert_eq!(items(&doc, ShelfKind::Chart).len(), 2);
        let chart = HashSet::from(["t-chart-2-p0 1".to_string(), "t-chart-2-p0 2".into()]);
        assert_eq!(reasons(&doc), chart);
    }

    #[tokio::test]
    async fn another_edition_of_a_seed_is_not_discovered() {
        let (_lock, app) = setup().await;
        wipe().await;
        // The seed is the artist's first track, "ar-echo-a 1"; its radio starts with another
        // edition of it.
        liked_artist("echo a").await;
        let doc = build(now_ms()).await.unwrap();
        assert_eq!(reasons(&doc), HashSet::from(["ar-echo-a 1".to_string()]));
        let ids: Vec<ItemId> = items(&doc, ShelfKind::Discovery)
            .iter()
            .map(|id| parse_id(id).unwrap())
            .collect();
        let titles: Vec<String> = app
            .db
            .read(move |c| crate::library::catalog::tracks(c, &ids))
            .await
            .unwrap()
            .into_iter()
            .map(|t| t.title)
            .collect();
        assert!(!titles.contains(&"ar-echo-a 1".to_string()), "{titles:?}");
        assert_eq!(titles.len(), 25);
    }

    #[tokio::test]
    async fn a_failing_radio_empties_only_discovery() {
        let (_lock, _) = setup().await;
        wipe().await;
        // The first build keeps a copy of the chart for 24 h.
        build(now_ms()).await.unwrap();
        set_mode("fake", "network").await;
        set_mode("fake-b", "network").await;
        let doc = build(now_ms()).await.unwrap();
        assert_eq!(items(&doc, ShelfKind::Discovery), Vec::<String>::new());
        assert_eq!(items(&doc, ShelfKind::Chart).len(), 2);
    }

    /// A loaded shelf of `ids`.
    fn stored(kind: ShelfKind, network: bool, ids: &[ItemId]) -> StoredShelf {
        StoredShelf {
            kind,
            seed: None,
            seed_id: None,
            network,
            loaded: true,
            items: ids
                .iter()
                .map(|id| StoredItem {
                    id: id.to_string(),
                    reason: None,
                })
                .collect(),
        }
    }

    /// A "because you listened" shelf of `artist`, not loaded yet.
    fn because(artist: ItemId, name: &str) -> StoredShelf {
        StoredShelf {
            kind: ShelfKind::BecauseYouListened,
            seed: Some(name.into()),
            seed_id: Some(artist.to_string()),
            network: true,
            loaded: false,
            items: vec![],
        }
    }

    /// Stores a doc of these shelves, built at `at`.
    async fn store(at: i64, shelves: Vec<StoredShelf>) {
        store_doc(FeedDoc {
            built_at_ms: at,
            offline: false,
            shelves,
        })
        .await;
    }

    async fn store_doc(doc: FeedDoc) {
        let bytes = serde_json::to_vec(&doc).unwrap();
        test_app()
            .db
            .write(move |tx| kv::set(tx, NS, KEY, &bytes))
            .await
            .unwrap();
    }

    async fn raw_doc() -> Vec<u8> {
        let db = &test_app().db;
        db.read(|c| kv::get(c, NS, KEY)).await.unwrap().unwrap()
    }

    async fn stored_doc() -> FeedDoc {
        serde_json::from_slice(&raw_doc().await).unwrap()
    }

    fn page_kinds(p: &HomeFeedPage) -> Vec<ShelfKind> {
        p.shelves.iter().map(|s| s.kind).collect()
    }

    fn card_ids(s: &ShelfView) -> Vec<String> {
        s.items
            .iter()
            .map(|c| match c {
                CardView::Track { track, .. } => track.id.clone(),
                CardView::Collection(c) => c.id.clone(),
            })
            .collect()
    }

    /// Waits for a background build to end.
    async fn settle() {
        let wait = tokio::time::timeout(std::time::Duration::from_secs(10), BUILD.lock());
        drop(wait.await.expect("background build still running"));
    }

    /// The `Home` events received so far.
    fn homes(rx: &mut tokio::sync::broadcast::Receiver<LibraryChanged>) -> usize {
        let mut n = 0;
        while let Ok(c) = rx.try_recv() {
            n += usize::from(c == LibraryChanged::Home);
        }
        n
    }

    #[tokio::test]
    async fn feed_pages_by_four_and_ends() {
        use ShelfKind::*;
        let (_lock, _) = setup().await;
        wipe().await;
        let (t, _, _) = song("home page a").await;
        let mut shelves: Vec<_> = (0..9).map(|_| stored(Recent, false, &[t])).collect();
        shelves.push(stored(End, false, &[]));
        store(now_ms(), shelves).await;
        let first = page(None).await.unwrap();
        assert_eq!(page_kinds(&first), [Recent; 4]);
        assert_eq!(card_ids(&first.shelves[0]), [t.to_string()]);
        assert_eq!(first.next.as_deref(), Some("4"));
        let second = page(first.next).await.unwrap();
        assert_eq!(page_kinds(&second), [Recent; 4]);
        assert_eq!(second.next.as_deref(), Some("8"));
        let last = page(second.next).await.unwrap();
        assert_eq!(page_kinds(&last), [Recent, End]);
        assert_eq!(last.next, None);
        assert!(page(Some("x".into())).await.is_err());
    }

    #[tokio::test]
    async fn unloaded_because_shelf_is_skipped_offline() {
        use ShelfKind::*;
        let (_lock, app) = setup().await;
        wipe().await;
        let (t, _, artist) = song("home byl offline").await;
        play(t, None).await;
        let shelves = vec![
            stored(Recent, false, &[t]),
            because(artist, "Artist home-byl-offline"),
            stored(End, false, &[]),
        ];
        store(now_ms(), shelves).await;
        app.set_online(false);
        let before = calls().await;
        let p = page(None).await.unwrap();
        assert_eq!(page_kinds(&p), [Recent, End]);
        assert_eq!(calls().await, before);
        assert!(!stored_doc().await.shelves[1].loaded);
        app.set_online(true);
    }

    #[tokio::test]
    async fn because_shelf_loads_once_and_is_stored() {
        use ShelfKind::*;
        let (_lock, _) = setup().await;
        wipe().await;
        // The radio of "home byl a" is by its own artist, on its own album.
        let (t, album, artist) = song("home byl a").await;
        play(t, None).await;
        let name = "Artist home-byl-a";
        store(
            now_ms(),
            vec![because(artist, name), stored(End, false, &[])],
        )
        .await;
        let p = page(None).await.unwrap();
        assert_eq!(page_kinds(&p), [BecauseYouListened, End]);
        assert_eq!(p.shelves[0].seed.as_deref(), Some(name));
        assert_eq!(card_ids(&p.shelves[0]), [album.to_string()]);
        let doc = stored_doc().await;
        assert!(doc.shelves[0].loaded);
        assert_eq!(items(&doc, BecauseYouListened), [album.to_string()]);
        let before = calls().await;
        let again = page(None).await.unwrap();
        assert_eq!(calls().await, before);
        assert_eq!(card_ids(&again.shelves[0]), [album.to_string()]);
    }

    #[tokio::test]
    async fn discover_off_hides_cached_network_shelves() {
        use ShelfKind::*;
        let (_lock, app) = setup().await;
        wipe().await;
        let (t, _, artist) = song("home private cached").await;
        let shelves = vec![
            stored(Recent, false, &[t]),
            stored(Mixes, true, &[artist]),
            stored(End, false, &[]),
        ];
        store(now_ms(), shelves).await;
        let on = page(None).await.unwrap();
        assert_eq!(page_kinds(&on), [Recent, Mixes, End]);
        let CardView::Collection(mix) = &on.shelves[1].items[0] else {
            panic!("{on:?}");
        };
        assert_eq!(mix.kind, views::ItemKind::Artist);
        app.db
            .write(|tx| settings::device_set(tx, "discover", "false"))
            .await
            .unwrap();
        let bytes = raw_doc().await;
        let off = page(None).await.unwrap();
        assert_eq!(page_kinds(&off), [Recent, End]);
        assert_eq!(raw_doc().await, bytes);
        wipe().await;
    }

    #[tokio::test]
    async fn stale_feed_rebuilds_in_background_once() {
        use ShelfKind::*;
        let (_lock, app) = setup().await;
        wipe().await;
        let (t, _, _) = song("home stale").await;
        let old = now_ms() - 25 * 3600 * 1000;
        store(
            old,
            vec![stored(Recent, false, &[t]), stored(End, false, &[])],
        )
        .await;
        let mut rx = app.events.library.subscribe();
        // Both served the stale doc; only the first starts a build.
        let (a, b) = (page(None).await.unwrap(), page(None).await.unwrap());
        assert_eq!(page_kinds(&a), [Recent, End]);
        assert_eq!(page_kinds(&b), [Recent, End]);
        settle().await;
        assert_eq!(homes(&mut rx), 1);
        assert!(stored_doc().await.built_at_ms > old);
    }

    #[tokio::test]
    async fn missing_feed_serves_a_local_doc() {
        use ShelfKind::*;
        let (_lock, app) = setup().await;
        wipe().await;
        app.plugins.replace_loaded(vec![]);
        let p = page(None).await.unwrap();
        assert_eq!(page_kinds(&p), [End]);
        assert_eq!(p.next, None);
        settle().await;
    }

    #[tokio::test]
    async fn offline_doc_is_rebuilt_back_online() {
        use ShelfKind::*;
        let (_lock, app) = setup().await;
        wipe().await;
        let (t, _, _) = song("home offline doc").await;
        store_doc(FeedDoc {
            built_at_ms: now_ms(),
            offline: true,
            shelves: vec![stored(Recent, false, &[t]), stored(End, false, &[])],
        })
        .await;
        let mut rx = app.events.library.subscribe();
        on_online().await;
        settle().await;
        assert_eq!(homes(&mut rx), 1);
        assert!(!stored_doc().await.offline);
        // Built offline: marked so.
        app.set_online(false);
        build(now_ms()).await.unwrap();
        app.set_online(true);
        assert!(stored_doc().await.offline);
        wipe().await;
    }

    #[tokio::test]
    async fn offline_keeps_the_last_network_copy() {
        use ShelfKind::*;
        let (_lock, app) = setup().await;
        wipe().await;
        let (t, _, _) = song("home keep chart").await;
        let old = now_ms() - 25 * 3600 * 1000;
        let shelves = vec![stored(Chart, true, &[t]), stored(End, false, &[])];
        store(old, shelves).await;
        let bytes = raw_doc().await;
        app.set_online(false);
        let p = page(None).await.unwrap();
        settle().await;
        assert_eq!(page_kinds(&p), [Chart, End]);
        assert_eq!(raw_doc().await, bytes);
        let refresh = crate::api::library::refresh_home().await;
        app.set_online(true);
        assert_eq!(refresh, Err(CoreError::Offline));
        assert_eq!(raw_doc().await, bytes);
    }

    #[tokio::test]
    async fn refresh_waits_for_a_running_build() {
        let (_lock, app) = setup().await;
        wipe().await;
        store(now_ms(), vec![stored(ShelfKind::End, false, &[])]).await;
        let mut rx = app.events.library.subscribe();
        let running = BUILD.try_lock().unwrap();
        let refresh = tokio::spawn(crate::api::library::refresh_home());
        tokio::time::sleep(std::time::Duration::from_millis(100)).await;
        assert!(!refresh.is_finished());
        drop(running);
        refresh.await.unwrap().unwrap();
        // The running build's own event, not a second build.
        assert_eq!(homes(&mut rx), 0);
    }

    #[tokio::test]
    async fn a_failed_write_back_still_serves_the_page() {
        use ShelfKind::*;
        let (_lock, app) = setup().await;
        wipe().await;
        let (t, album, artist) = song("home byl nowrite").await;
        play(t, None).await;
        let name = "Artist home-byl-nowrite";
        store(
            now_ms(),
            vec![because(artist, name), stored(End, false, &[])],
        )
        .await;
        let block = "CREATE TEMP TRIGGER no_feed BEFORE INSERT ON plugin_kv
                     WHEN NEW.key = 'home_feed' BEGIN SELECT RAISE(ABORT, 'disk full'); END;";
        app.db
            .write(move |tx| tx.tx.execute_batch(block))
            .await
            .unwrap();
        let p = page(None).await;
        app.db
            .write(|tx| tx.tx.execute_batch("DROP TRIGGER no_feed;"))
            .await
            .unwrap();
        let p = p.unwrap();
        assert_eq!(page_kinds(&p), [BecauseYouListened, End]);
        assert_eq!(card_ids(&p.shelves[0]), [album.to_string()]);
        assert!(!stored_doc().await.shelves[0].loaded);
    }
}
