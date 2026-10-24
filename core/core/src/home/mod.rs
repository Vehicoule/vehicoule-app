//! The home feed (spec UI 6.1, 7.2): seeds read from the library, a discovery list merged
//! from their radios, shelves assembled in a fixed order and stored in kv `@core`/`home_feed`.
//! The core produces no text: a shelf is a kind and, for some, a seed's name.

mod assemble;
mod seeds;

use std::collections::HashSet;

use serde::{Deserialize, Serialize};

use assemble::assemble;
use seeds::TRACK_SEEDS;

use crate::app::app;
use crate::browse;
use crate::catalog::{self as views, CardView, parse_id};
use crate::error::CoreError;
use crate::library::catalog;
use crate::library::{ItemId, kv, settings};
use crate::logs;
use crate::player;

/// The core's kv namespace, as in `browse`.
const NS: &str = "@core";
const KEY: &str = "home_feed";
/// New releases: out less than 30 days ago.
const RELEASES_MS: i64 = 30 * 86_400_000;
/// The featured chart (Deezer's Top 50); else the first featured category.
const CHART: &str = "chart:0";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) enum ShelfKind {
    Shortcuts,
    Discovery,
    Mixes,
    BecauseYouListened,
    NewReleases,
    Rediscover,
    Chart,
    Recent,
    Playlists,
    Downloads,
    End,
}

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
    pub shelves: Vec<StoredShelf>,
}

/// Reads the seeds, asks the plugins when `discover` is on and online (a failing source is
/// left empty and logged), assembles the shelves and stores the doc.
pub(crate) async fn build(now_ms: i64) -> Result<FeedDoc, CoreError> {
    let app = app();
    let discover = app.db.read(|c| settings::device_get(c, "discover")).await?;
    let discover = discover.as_deref() != Some("false");
    let mut local = app.db.read(move |c| seeds::read(c, now_ms)).await?;
    if discover && app.is_online() {
        network(&mut local, now_ms).await?;
    }
    let doc = FeedDoc {
        built_at_ms: now_ms,
        shelves: assemble(local.inputs, discover),
    };
    let bytes = serde_json::to_vec(&doc).map_err(|e| CoreError::Internal(e.to_string()))?;
    app.db.write(move |tx| kv::set(tx, NS, KEY, &bytes)).await?;
    Ok(doc)
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
        .collect();
    inputs.chart = chart;
    Ok(())
}

/// The first track of the artist's `entity` page.
async fn first_track(artist: ItemId) -> Option<ItemId> {
    let page = logged("entity", views::entity(&artist.to_string(), None).await)?;
    parse_id(&page.tracks.first()?.id).ok()
}

/// The first track shelf of the featured chart.
async fn chart() -> Result<Vec<ItemId>, CoreError> {
    let page = match browse::category(CHART.into(), None).await {
        Err(e) if !matches!(e, CoreError::NoPlugin(_) | CoreError::Offline) => {
            let mut featured = browse::categories().await?.into_iter();
            match featured.find(|c| c.featured && c.id != CHART) {
                Some(c) => browse::category(c.id, None).await?,
                None => return Err(e),
            }
        }
        page => page?,
    };
    let Some(shelf) = page.shelves.into_iter().find(|s| s.title == "tracks") else {
        return Ok(vec![]);
    };
    shelf
        .items
        .iter()
        .filter_map(|c| match c {
            CardView::Track { track, .. } => Some(parse_id(&track.id)),
            CardView::Collection(_) => None,
        })
        .collect()
}

/// `r`'s value; its error logged.
fn logged<T>(source: &str, r: Result<T, CoreError>) -> Option<T> {
    r.inspect_err(|e| logs::push("warn", "home", &format!("{source}: {e:?}")))
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
mod tests {
    use super::*;
    use crate::app::test_app;
    use crate::catalog;
    use crate::catalog::tests::{calls, setup};
    use crate::library::{likes, plays};
    use crate::plugins::now_ms;

    const DAY_MS: i64 = 86_400_000;

    /// An empty library: no plays, likes, downloads nor user playlists; no `@core` copy;
    /// `discover` unset.
    async fn wipe() {
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
    async fn song(q: &str) -> (ItemId, ItemId, ItemId) {
        let t = catalog::search(q).await.unwrap().tracks.remove(0);
        (
            parse_id(&t.id).unwrap(),
            parse_id(&t.album.unwrap().id).unwrap(),
            parse_id(&t.artists[0].id).unwrap(),
        )
    }

    /// A one-minute play of `t` a day ago, from `ctx`.
    async fn play(t: ItemId, ctx: Option<ItemId>) {
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
}
