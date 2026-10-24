//! Explore's categories and pages, and an artist's releases: the routed `browse` capability.
//! Every entity received is stored in the catalogue, so the ids handed out are the core's.
//! The categories, a category's first page and an artist's releases are kept in kv `@core`
//! for 24 h; offline, or when the call fails, the last copy is served whatever its age.

use std::future::Future;

use plugin_host::music::browse::Category;
use plugin_host::music::entity::Entity;
use plugin_host::types::Playlist;
use plugin_host::{CallError, Capability};
use rusqlite::Connection;
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::api::browse::{BrowseShelfView, CategoryPageView, CategoryView};
use crate::api::catalog::ReleaseView;
use crate::app::app;
use crate::catalog::{CardView, collection_view, online, track_view};
use crate::convert;
use crate::error::CoreError;
use crate::library::catalog;
use crate::library::{ItemId, Tx, kv, refs};
use crate::logs;
use crate::plugins::now_ms;
use crate::router;

/// The core's kv namespace: not a valid plugin id, so no plugin can read it.
const NS: &str = "@core";
const TTL_MS: i64 = 24 * 3600 * 1000;
/// An artist's latest release shows up to 90 days after it came out.
const LATEST_MS: i64 = 90 * TTL_MS;

#[derive(Serialize, Deserialize)]
struct Copy<T> {
    built_at_ms: i64,
    data: T,
}

/// A category page as stored: shelves of item ids, read back as cards.
#[derive(Serialize, Deserialize)]
struct PageDoc {
    title: String,
    shelves: Vec<(String, Vec<Uuid>)>,
    next: Option<String>,
}

/// The copy under `key` while younger than 24 h; else `fetch`'s answer, stored (a failed
/// write is logged); else (offline, or the call failed) the copy whatever its age. `true`:
/// that fallback copy was served.
async fn cached<T, Fut>(key: String, fetch: impl FnOnce() -> Fut) -> Result<(T, bool), CoreError>
where
    T: Serialize + DeserializeOwned + Send + 'static,
    Fut: Future<Output = Result<T, CoreError>>,
{
    let db = &app().db;
    let k = key.clone();
    let mut copy = db.read(move |c| kv::get(c, NS, &k)).await?.and_then(|b| {
        serde_json::from_slice::<Copy<T>>(&b)
            .inspect_err(|e| logs::push("warn", "browse", &format!("{key}: {e}")))
            .ok()
    });
    if let Some(c) = copy.take_if(|c| now_ms() - c.built_at_ms < TTL_MS) {
        return Ok((c.data, false));
    }
    let fetched = match online() {
        Ok(()) => fetch().await,
        Err(e) => Err(e),
    };
    match fetched {
        Ok(data) => {
            let doc = Copy {
                built_at_ms: now_ms(),
                data: &data,
            };
            let stored = match serde_json::to_vec(&doc) {
                Ok(bytes) => {
                    let k = key.clone();
                    db.write(move |tx| kv::set(tx, NS, &k, &bytes))
                        .await
                        .map_err(|e| e.to_string())
                }
                Err(e) => Err(e.to_string()),
            };
            if let Err(e) = stored {
                logs::push("warn", "browse", &format!("{key}: {e}"));
            }
            Ok((data, false))
        }
        Err(e) => copy.map(|c| (c.data, true)).ok_or(e),
    }
}

/// Featured cards first, then the grid.
pub(crate) async fn categories() -> Result<Vec<CategoryView>, CoreError> {
    Ok(cached("browse_categories".into(), fetch_categories)
        .await?
        .0)
}

async fn fetch_categories() -> Result<Vec<CategoryView>, CoreError> {
    let app = app();
    let (p, found) = router::first_ok(Capability::Browse, |p| async move {
        app.plugins
            .host()
            .browse_categories(&p, &app.cfg.region)
            .await
    })
    .await?;
    let provider = p.id().to_string();
    Ok(app
        .db
        .write(move |tx| {
            found
                .into_iter()
                .map(|c| category_view(tx, &provider, c))
                .collect()
        })
        .await?)
}

/// The artwork goes through a provider playlist item without children (its ref: the
/// category's id), so `artwork_file` serves it. Never liked nor in a user playlist, it stays
/// out of the library.
fn category_view(tx: &Tx, provider: &str, c: Category) -> rusqlite::Result<CategoryView> {
    let artwork = if c.artwork.is_empty() {
        None
    } else {
        let item = convert::playlist(Playlist {
            id: c.id.clone(),
            title: c.title.clone(),
            owner: None,
            description: None,
            track_count: None,
            artwork: c.artwork,
        });
        Some(catalog::upsert_playlist(tx, provider, &item)?.to_string())
    };
    Ok(CategoryView {
        id: c.id,
        title: c.title,
        artwork,
        featured: c.featured,
    })
}

/// A category's page; only the first one (`cursor` = None) has a copy.
pub(crate) async fn category(
    id: String,
    cursor: Option<String>,
) -> Result<CategoryPageView, CoreError> {
    let (doc, from_cache) = match cursor {
        Some(cursor) => {
            online()?;
            (fetch_page(id, Some(cursor)).await?, false)
        }
        None => {
            cached(format!("browse_category:{id}"), || {
                fetch_page(id.clone(), None)
            })
            .await?
        }
    };
    Ok(app()
        .db
        .read(move |c| {
            let shelves = doc
                .shelves
                .into_iter()
                .map(|(title, ids)| {
                    let items = ids
                        .into_iter()
                        .filter_map(|id| card(c, ItemId(id)).transpose());
                    Ok(BrowseShelfView {
                        title,
                        items: items.collect::<rusqlite::Result<_>>()?,
                    })
                })
                .collect::<rusqlite::Result<_>>()?;
            Ok(CategoryPageView {
                title: doc.title,
                shelves,
                next: doc.next,
                from_cache,
            })
        })
        .await?)
}

async fn fetch_page(id: String, cursor: Option<String>) -> Result<PageDoc, CoreError> {
    let app = app();
    let (p, page) = router::first_ok(Capability::Browse, |p| {
        let (id, cursor) = (id.clone(), cursor.clone());
        async move {
            let host = app.plugins.host();
            host.browse_category(&p, &id, &app.cfg.region, cursor).await
        }
    })
    .await?;
    let provider = p.id().to_string();
    Ok(app
        .db
        .write(move |tx| {
            let shelves = page
                .shelves
                .into_iter()
                .map(|s| {
                    let ids = s
                        .items
                        .into_iter()
                        .map(|e| upsert(tx, &provider, e).map(|i| i.0));
                    Ok((s.title, ids.collect::<rusqlite::Result<_>>()?))
                })
                .collect::<rusqlite::Result<_>>()?;
            Ok(PageDoc {
                title: page.title,
                shelves,
                next: page.next,
            })
        })
        .await?)
}

fn upsert(tx: &Tx, provider: &str, e: Entity) -> rusqlite::Result<ItemId> {
    match e {
        Entity::Track(t) => catalog::upsert_track(tx, provider, &convert::track(t)),
        Entity::Album(a) => catalog::upsert_album(tx, provider, &convert::album(a)),
        Entity::Artist(a) => catalog::upsert_artist(tx, provider, &convert::artist(a)),
        Entity::Playlist(p) => catalog::upsert_playlist(tx, provider, &convert::playlist(p)),
    }
}

/// A track or a collection; `None` for an item gone since the copy was made.
pub(crate) fn card(c: &Connection, id: ItemId) -> rusqlite::Result<Option<CardView>> {
    if let Some(t) = catalog::track(c, id)? {
        return Ok(Some(CardView::Track {
            track: track_view(t),
            reason: None,
        }));
    }
    Ok(catalog::collection(c, id)?.map(|r| CardView::Collection(collection_view(r))))
}

/// An artist's releases, newest first: the album items and their `YYYY-MM-DD` dates (a
/// release dated otherwise is left out). The plugins asked are those holding a ref of the
/// artist.
pub(crate) async fn releases(artist: ItemId) -> Result<Vec<(ItemId, String)>, CoreError> {
    let key = format!("browse_releases:{artist}");
    let (found, _) = cached(key, || fetch_releases(artist)).await?;
    Ok(found
        .into_iter()
        .map(|(id, date)| (ItemId(id), date))
        .collect())
}

async fn fetch_releases(artist: ItemId) -> Result<Vec<(Uuid, String)>, CoreError> {
    let app = app();
    let refs = app.db.read(move |c| refs::all(c, artist)).await?;
    let (p, found) = router::first_ok(Capability::Browse, |p| {
        let ext = refs
            .iter()
            .find(|(provider, _)| provider == p.id())
            .map(|(_, r)| r.external_id.clone());
        async move {
            let Some(id) = ext else {
                return Err(CallError::Unsupported);
            };
            let host = app.plugins.host();
            host.browse_releases(&p, &id, &app.cfg.region).await
        }
    })
    .await?;
    let provider = p.id().to_string();
    Ok(app
        .db
        .write(move |tx| {
            found
                .into_iter()
                .filter(|r| is_date(&r.date))
                .map(|r| {
                    let album = catalog::upsert_album(tx, &provider, &convert::album(r.album))?;
                    Ok((album.0, r.date))
                })
                .collect()
        })
        .await?)
}

/// `YYYY-MM-DD`, as the contract says: compared as strings, so nothing else gets in.
fn is_date(s: &str) -> bool {
    s.len() == 10
        && s.bytes().enumerate().all(|(i, b)| match i {
            4 | 7 => b == b'-',
            _ => b.is_ascii_digit(),
        })
}

/// The newest of `releases(artist)`, unless older than 90 days at `now_ms`; errors are
/// logged (no `browse` plugin is not one) and give `None`.
pub(crate) async fn latest_release(artist: ItemId, now_ms: i64) -> Option<ReleaseView> {
    let found = async {
        let since = crate::home::date(now_ms - LATEST_MS);
        let newest = releases(artist)
            .await?
            .into_iter()
            .max_by(|a, b| a.1.cmp(&b.1));
        let Some((album, date)) = newest.filter(|r| r.1 >= since) else {
            return Ok(None);
        };
        let row = app()
            .db
            .read(move |c| catalog::collection(c, album))
            .await?;
        Ok(row.map(|r| ReleaseView {
            album: collection_view(r),
            date,
        }))
    };
    found.await.unwrap_or_else(|e: CoreError| {
        if !matches!(e, CoreError::NoPlugin(_)) {
            logs::push("warn", "browse", &format!("latest release: {e:?}"));
        }
        None
    })
}

#[cfg(test)]
mod tests {
    use plugin_host::Capability;

    use super::*;
    use crate::api::browse::{CategoryPageView, browse_categories, browse_category};
    use crate::api::library::search_library;
    use crate::app::test_app;
    use crate::catalog::tests::{calls, set_mode, setup};
    use crate::catalog::{self, CardView, ItemKind, parse_id};
    use crate::library::catalog::{artwork_by_provider, collection, track};
    use crate::library::{Kind, kv, search};

    const DAY_MS: i64 = 24 * 3600 * 1000;

    /// Forgets every browse copy.
    async fn clear() {
        test_app()
            .db
            .write(|tx| {
                tx.tx
                    .execute("DELETE FROM plugin_kv WHERE plugin_id = '@core'", [])
                    .map(drop)
            })
            .await
            .unwrap();
    }

    /// Moves the copy under `key` `ms` into the past.
    async fn age(key: &'static str, ms: i64) {
        let db = &test_app().db;
        let v = db.read(move |c| kv::get(c, "@core", key)).await.unwrap();
        let mut doc: serde_json::Value = serde_json::from_slice(&v.unwrap()).unwrap();
        let built = doc["built_at_ms"].as_i64().unwrap();
        doc["built_at_ms"] = (built - ms).into();
        let bytes = serde_json::to_vec(&doc).unwrap();
        db.write(move |tx| kv::set(tx, "@core", key, &bytes))
            .await
            .unwrap();
    }

    fn ids(page: &CategoryPageView) -> Vec<String> {
        let id = |c: &CardView| match c {
            CardView::Track { track, .. } => track.id.clone(),
            CardView::Collection(c) => c.id.clone(),
        };
        page.shelves
            .iter()
            .flat_map(|s| s.items.iter().map(id))
            .collect()
    }

    #[test]
    fn browse_futures_are_send() {
        fn send<T: Send>(_: T) {}
        send(browse_categories());
        send(browse_category("x".into(), None));
        send(releases(ItemId(uuid::Uuid::nil())));
    }

    #[tokio::test]
    async fn categories_are_cached_24h() {
        let (_lock, _) = setup().await;
        clear().await;
        let before = calls().await;
        let first = browse_categories().await.unwrap();
        assert_eq!(calls().await, before + 1);
        let featured: Vec<_> = first.iter().map(|c| (c.id.as_str(), c.featured)).collect();
        assert_eq!(featured, [("chart:0", true), ("genre:1", false)]);
        age("browse_categories", DAY_MS - 60_000).await;
        assert_eq!(browse_categories().await.unwrap(), first);
        assert_eq!(calls().await, before + 1);
        // The first page of a category too.
        let page = browse_category("chart:0".into(), None).await.unwrap();
        assert!(!page.from_cache);
        let again = browse_category("chart:0".into(), None).await.unwrap();
        assert_eq!(calls().await, before + 2);
        // A fresh copy is not a fallback: not flagged.
        assert!(!again.from_cache);
        assert_eq!(ids(&again), ids(&page));
        assert_eq!(again.next.as_deref(), Some("1"));
    }

    #[tokio::test]
    async fn stale_categories_refetch() {
        let (_lock, _) = setup().await;
        clear().await;
        browse_categories().await.unwrap();
        age("browse_categories", DAY_MS + 1).await;
        let before = calls().await;
        browse_categories().await.unwrap();
        assert_eq!(calls().await, before + 1);
        // Fresh again.
        browse_categories().await.unwrap();
        assert_eq!(calls().await, before + 1);
    }

    #[tokio::test]
    async fn offline_serves_last_copy() {
        let (_lock, app) = setup().await;
        clear().await;
        let cats = browse_categories().await.unwrap();
        let page = browse_category("chart:0".into(), None).await.unwrap();
        age("browse_categories", 3 * DAY_MS).await;
        age("browse_category:chart:0", 3 * DAY_MS).await;
        app.set_online(false);
        let before = calls().await;
        assert_eq!(browse_categories().await.unwrap(), cats);
        let copy = browse_category("chart:0".into(), None).await.unwrap();
        assert!(copy.from_cache);
        assert_eq!(ids(&copy), ids(&page));
        // A later page is never served from the copy; nothing stored: offline.
        assert_eq!(
            browse_category("chart:0".into(), Some("1".into())).await,
            Err(CoreError::Offline)
        );
        assert_eq!(
            browse_category("genre:1".into(), None).await,
            Err(CoreError::Offline)
        );
        assert_eq!(calls().await, before);
        // Online but failing: the copy as well.
        app.set_online(true);
        set_mode("fake", "network").await;
        assert!(
            browse_category("chart:0".into(), None)
                .await
                .unwrap()
                .from_cache
        );
        assert_eq!(browse_categories().await.unwrap(), cats);
        assert_eq!(
            browse_category("genre:1".into(), None).await,
            Err(CoreError::Network)
        );
    }

    #[tokio::test]
    async fn no_browse_plugin_is_no_plugin() {
        let (_lock, app) = setup().await;
        clear().await;
        app.plugins.replace_loaded(vec![]);
        let no = CoreError::NoPlugin(Capability::Browse);
        assert_eq!(browse_categories().await.unwrap_err(), no);
        let page = browse_category("chart:0".into(), None).await;
        assert_eq!(page.unwrap_err(), no);
        let found = releases(ItemId(uuid::Uuid::nil())).await;
        assert_eq!(found.unwrap_err(), no);
    }

    #[tokio::test]
    async fn category_items_are_catalogued() {
        let (_lock, app) = setup().await;
        clear().await;
        let page = browse_category("genre:1".into(), None).await.unwrap();
        assert_eq!(page.title, "Category genre:1");
        let shelves: Vec<_> = page.shelves.iter().map(|s| s.title.as_str()).collect();
        assert_eq!(shelves, ["tracks", "albums", "artists", "playlists"]);
        assert_eq!(page.next.as_deref(), Some("1"));
        let CardView::Track { track: t, reason } = &page.shelves[0].items[0] else {
            panic!("{page:?}");
        };
        assert_eq!((t.title.as_str(), reason), ("t-genre-1-p0 1", &None));
        let CardView::Collection(album) = &page.shelves[1].items[0] else {
            panic!("{page:?}");
        };
        assert_eq!(album.kind, ItemKind::Album);
        let ids = ids(&page);
        assert_eq!(ids.len(), 5);
        let rows = app
            .db
            .read(move |c| {
                ids.iter()
                    .map(|id| {
                        let id = parse_id(id).unwrap();
                        let t = track(c, id)?.map(catalog::track_view);
                        Ok((t.map(|t| t.title), collection(c, id)?.map(|c| c.kind)))
                    })
                    .collect::<rusqlite::Result<Vec<_>>>()
            })
            .await
            .unwrap();
        let tracks: Vec<_> = rows.iter().filter_map(|r| r.0.as_deref()).collect();
        assert_eq!(tracks, ["t-genre-1-p0 1", "t-genre-1-p0 2"]);
        let kinds: Vec<_> = rows.iter().filter_map(|r| r.1).collect();
        assert_eq!(kinds, [Kind::Album, Kind::Artist, Kind::Playlist]);
        // A later page: the plugin each time, never stored.
        let before = calls().await;
        for _ in 0..2 {
            let more = browse_category("genre:1".into(), Some("1".into()))
                .await
                .unwrap();
            assert!(!more.from_cache && more.next.is_none());
        }
        assert_eq!(calls().await, before + 2);
    }

    #[tokio::test]
    async fn releases_map_to_items_with_dates() {
        let (_lock, app) = setup().await;
        clear().await;
        let artist = catalog::search("relartist").await.unwrap().artists[0]
            .id
            .clone();
        let artist = parse_id(&artist).unwrap();
        let found = releases(artist).await.unwrap();
        let dates: Vec<_> = found.iter().map(|r| r.1.as_str()).collect();
        assert_eq!(dates, ["2026-10-20", "2026-09-01"]);
        let ids: Vec<ItemId> = found.iter().map(|r| r.0).collect();
        let albums: Vec<_> = app
            .db
            .read(move |c| ids.iter().map(|&id| collection(c, id)).collect())
            .await
            .unwrap();
        let albums: Vec<_> = albums
            .into_iter()
            .map(|a: Option<_>| a.unwrap())
            .map(|a| (a.kind, a.title, a.subtitle))
            .collect();
        let by = Some("Artist relartist".to_string());
        assert_eq!(
            albums,
            [
                (Kind::Album, "Release relartist 1".into(), by.clone()),
                (Kind::Album, "Release relartist 2".into(), by),
            ]
        );
        // Cached 24 h, then served offline whatever its age.
        let before = calls().await;
        assert_eq!(releases(artist).await.unwrap(), found);
        assert_eq!(calls().await, before);
        let key: &'static str = format!("browse_releases:{artist}").leak();
        age(key, 3 * DAY_MS).await;
        app.set_online(false);
        assert_eq!(releases(artist).await.unwrap(), found);
        // An artist no plugin knows.
        app.set_online(true);
        assert_eq!(
            releases(ItemId(uuid::Uuid::nil())).await,
            Err(CoreError::NoPlugin(Capability::Browse))
        );
    }

    #[tokio::test]
    async fn releases_without_a_plain_date_are_left_out() {
        let (_lock, _) = setup().await;
        clear().await;
        let artist = catalog::search("baddate").await.unwrap().artists[0]
            .id
            .clone();
        let found = releases(parse_id(&artist).unwrap()).await.unwrap();
        let dates: Vec<_> = found.iter().map(|r| r.1.as_str()).collect();
        assert_eq!(dates, ["2026-10-05"]);
    }

    #[tokio::test]
    async fn latest_release_within_90_days_or_none() {
        let (_lock, app) = setup().await;
        clear().await;
        let artist = catalog::search("relartist").await.unwrap().artists[0]
            .id
            .clone();
        let artist = parse_id(&artist).unwrap();
        // Its newest release is out on 2026-10-20 (midnight UTC).
        const OCT_20: i64 = 1_792_454_400_000;
        let before = calls().await;
        let latest = latest_release(artist, OCT_20 + 10 * DAY_MS).await.unwrap();
        assert_eq!(latest.date, "2026-10-20");
        assert_eq!(
            (latest.album.kind, latest.album.title.as_str()),
            (ItemKind::Album, "Release relartist 1")
        );
        // From the 24 h copy; exactly 90 days is in, 91 out.
        let at_90 = latest_release(artist, OCT_20 + 90 * DAY_MS).await;
        assert_eq!(at_90.map(|r| r.date).as_deref(), Some("2026-10-20"));
        assert_eq!(latest_release(artist, OCT_20 + 91 * DAY_MS).await, None);
        assert_eq!(latest_release(artist, OCT_20 + 120 * DAY_MS).await, None);
        assert_eq!(calls().await, before + 1);
        // No browse plugin, or an error: none, never an error.
        assert_eq!(
            latest_release(ItemId(uuid::Uuid::nil()), OCT_20).await,
            None
        );
        clear().await;
        app.plugins.replace_loaded(vec![]);
        assert_eq!(latest_release(artist, OCT_20).await, None);
    }

    #[tokio::test]
    async fn category_artwork_item_not_in_library_search() {
        let (_lock, app) = setup().await;
        clear().await;
        let cats = browse_categories().await.unwrap();
        assert_eq!(cats[1].artwork, None);
        let art = parse_id(cats[0].artwork.as_ref().unwrap()).unwrap();
        let (row, images, hits) = app
            .db
            .read(move |c| {
                Ok((
                    collection(c, art)?.unwrap(),
                    artwork_by_provider(c, art)?,
                    search::local(c, "Top fake", 10)?,
                ))
            })
            .await
            .unwrap();
        assert_eq!((row.kind, row.title.as_str()), (Kind::Playlist, "Top fake"));
        assert!(!row.liked && !row.user);
        assert_eq!(images.len(), 2);
        assert!(hits.is_empty());
        assert_eq!(search_library("Top fake".into()).await.unwrap(), []);
    }

    #[tokio::test]
    async fn a_failed_copy_write_still_serves_the_data() {
        let (_lock, app) = setup().await;
        clear().await;
        let block = "CREATE TEMP TRIGGER no_copy BEFORE INSERT ON plugin_kv
                     WHEN NEW.plugin_id = '@core' BEGIN SELECT RAISE(ABORT, 'disk full'); END;";
        app.db
            .write(move |tx| tx.tx.execute_batch(block))
            .await
            .unwrap();
        let cats = browse_categories().await;
        let page = browse_category("chart:0".into(), None).await;
        app.db
            .write(|tx| tx.tx.execute_batch("DROP TRIGGER no_copy;"))
            .await
            .unwrap();
        assert_eq!(cats.unwrap().len(), 2);
        assert!(!page.unwrap().from_cache);
        let copy = app
            .db
            .read(|c| kv::get(c, "@core", "browse_categories"))
            .await;
        assert_eq!(copy.unwrap(), None);
        let logged = crate::logs::recent();
        assert!(
            logged
                .iter()
                .any(|l| l.source == "browse" && l.message.contains("browse_categories")),
            "{logged:?}"
        );
    }
}
