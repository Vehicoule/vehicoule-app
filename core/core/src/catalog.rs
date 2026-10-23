//! Catalogue: provider search, suggestions, entity pages and playlist import, written to the
//! library as they arrive (an upsert error aborts the whole write); artwork files from the cache.

use plugin_host::music::entity::{Entity, EntityPage};
use plugin_host::music::search::SearchRequest;
use plugin_host::types::{EntityKind, EntityRef};
use plugin_host::{CallError, Capability};
use rusqlite::Connection;
use vehicoule_stream::StreamError;

use crate::app::app;
use crate::convert;
use crate::error::CoreError;
use crate::library::catalog::{self, CollectionRow, Image, TrackRow};
use crate::library::playlists::{self, Place};
use crate::library::{ItemId, Kind, Page, fold, refs, search};
use crate::logs;
use crate::router;

#[derive(Debug, Clone, PartialEq)]
pub struct TrackView {
    pub id: String,
    pub title: String,
    pub artists: Vec<ArtistRefView>,
    pub album: Option<AlbumRefView>,
    pub duration_ms: Option<u32>,
    pub explicit: bool,
    pub liked: bool,
    pub downloaded: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ArtistRefView {
    pub id: String,
    pub name: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct AlbumRefView {
    pub id: String,
    pub title: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct CollectionView {
    pub id: String,
    pub kind: ItemKind,
    pub title: String,
    pub subtitle: Option<String>,
    pub track_count: Option<u32>,
    pub liked: bool,
    pub is_user_playlist: bool,
}

/// A card of a shelf (Explore, home): a track, with why it is there, or a collection.
#[derive(Debug, Clone, PartialEq)]
pub enum CardView {
    Track {
        track: TrackView,
        reason: Option<String>,
    },
    Collection(CollectionView),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ItemKind {
    Track,
    Album,
    Artist,
    Playlist,
}

impl From<Kind> for ItemKind {
    fn from(k: Kind) -> Self {
        match k {
            Kind::Track => ItemKind::Track,
            Kind::Album => ItemKind::Album,
            Kind::Artist => ItemKind::Artist,
            Kind::Playlist => ItemKind::Playlist,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct SearchView {
    pub tracks: Vec<TrackView>,
    pub albums: Vec<CollectionView>,
    pub artists: Vec<CollectionView>,
    pub playlists: Vec<CollectionView>,
    /// The plugin that answered.
    pub source: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct EntityView {
    pub header: CollectionView,
    pub tracks: Vec<TrackView>,
    pub albums: Vec<CollectionView>,
    pub next: Option<String>,
    pub from_cache: bool,
}

/// Results per kind and per search.
const SEARCH_LIMIT: u32 = 20;
const SUGGESTIONS: usize = 10;
/// Import cap: a playlist of thousands of tracks stops here.
const MAX_IMPORT_PAGES: usize = 50;
// ponytail: a cached page shows its first 1000 tracks; page the cache if longer ones matter
const CACHED_TRACKS: u32 = 1000;

pub(crate) fn online() -> Result<(), CoreError> {
    if app().is_online() {
        Ok(())
    } else {
        Err(CoreError::Offline)
    }
}

/// Ids come from our own views: a malformed one is a caller bug.
pub(crate) fn parse_id(id: &str) -> Result<ItemId, CoreError> {
    uuid::Uuid::parse_str(id)
        .map(ItemId)
        .map_err(|_| CoreError::Internal("malformed item id".into()))
}

pub(crate) fn track_view(t: TrackRow) -> TrackView {
    TrackView {
        id: t.id.to_string(),
        title: t.title,
        artists: t
            .artists
            .into_iter()
            .map(|(id, name)| ArtistRefView {
                id: id.to_string(),
                name,
            })
            .collect(),
        album: t.album.map(|(id, title)| AlbumRefView {
            id: id.to_string(),
            title,
        }),
        duration_ms: t.duration_ms,
        explicit: t.explicit,
        liked: t.liked,
        downloaded: t.downloaded,
    }
}

pub(crate) fn collection_view(c: CollectionRow) -> CollectionView {
    CollectionView {
        id: c.id.to_string(),
        kind: c.kind.into(),
        title: c.title,
        subtitle: c.subtitle,
        track_count: c.track_count,
        liked: c.liked,
        is_user_playlist: c.user,
    }
}

pub(crate) fn track_views(c: &Connection, ids: &[ItemId]) -> rusqlite::Result<Vec<TrackView>> {
    Ok(catalog::tracks(c, ids)?
        .into_iter()
        .map(track_view)
        .collect())
}

pub(crate) fn collection_views(
    c: &Connection,
    ids: &[ItemId],
) -> rusqlite::Result<Vec<CollectionView>> {
    ids.iter()
        .filter_map(|&id| catalog::collection(c, id).transpose())
        .map(|r| r.map(collection_view))
        .collect()
}

/// Routed search; empty results count as not-found (next plugin). Stores the results and
/// the query.
pub(crate) async fn search(query: &str) -> Result<SearchView, CoreError> {
    online()?;
    let app = app();
    let req = SearchRequest {
        query: query.into(),
        kinds: vec![],
        region: app.cfg.region.clone(),
        limit: SEARCH_LIMIT,
        cursor: None,
    };
    let (plugin, found) = router::first_ok(Capability::Search, |p| {
        let req = req.clone();
        async move {
            let r = app.plugins.host().search(&p, req).await?;
            let empty = r.tracks.is_empty()
                && r.albums.is_empty()
                && r.artists.is_empty()
                && r.playlists.is_empty();
            if empty {
                Err(CallError::NotFound)
            } else {
                Ok(r)
            }
        }
    })
    .await?;
    let (source, query) = (plugin.id().to_string(), query.to_string());
    Ok(app
        .db
        .write(move |tx| {
            let p = source.as_str();
            search::record_query(tx, &query)?;
            let tracks = found
                .tracks
                .into_iter()
                .map(|t| catalog::upsert_track(tx, p, &convert::track(t)))
                .collect::<rusqlite::Result<Vec<_>>>()?;
            let albums = found
                .albums
                .into_iter()
                .map(|a| catalog::upsert_album(tx, p, &convert::album(a)))
                .collect::<rusqlite::Result<Vec<_>>>()?;
            let artists = found
                .artists
                .into_iter()
                .map(|a| catalog::upsert_artist(tx, p, &convert::artist(a)))
                .collect::<rusqlite::Result<Vec<_>>>()?;
            let playlists = found
                .playlists
                .into_iter()
                .map(|pl| catalog::upsert_playlist(tx, p, &convert::playlist(pl)))
                .collect::<rusqlite::Result<Vec<_>>>()?;
            let c = &tx.tx;
            Ok(SearchView {
                tracks: track_views(c, &tracks)?,
                albums: collection_views(c, &albums)?,
                artists: collection_views(c, &artists)?,
                playlists: collection_views(c, &playlists)?,
                source,
            })
        })
        .await?)
}

/// Local history first, then the routed `suggest` (online only); never fails.
pub(crate) async fn suggest(prefix: &str) -> Result<Vec<String>, CoreError> {
    let app = app();
    let p = prefix.to_string();
    let mut out = app
        .db
        .read(move |c| search::history(c, &p, SUGGESTIONS as u32))
        .await
        .unwrap_or_else(|e| {
            logs::push("error", "suggest", &e.to_string());
            vec![]
        });
    if app.is_online() && !prefix.trim().is_empty() {
        let found = router::first_ok(Capability::Suggest, |p| {
            let prefix = prefix.to_string();
            async move {
                app.plugins
                    .host()
                    .suggest(&p, &prefix, &app.cfg.region)
                    .await
            }
        })
        .await;
        match found {
            Ok((_, more)) => {
                for s in more {
                    if !out.iter().any(|o| fold(o) == fold(&s)) {
                        out.push(s);
                    }
                }
            }
            Err(e) => logs::push("warn", "suggest", &format!("{e:?}")),
        }
    }
    out.truncate(SUGGESTIONS);
    Ok(out)
}

/// An album, artist or playlist page from the plugins that know it; on failure (or
/// offline), the stored page, `from_cache = true`. User playlists are always local, and
/// never `from_cache` (they are the user's own data).
pub(crate) async fn entity(id: &str, cursor: Option<String>) -> Result<EntityView, CoreError> {
    let item = parse_id(id)?;
    let app = app();
    let (header, refs) = app
        .db
        .read(move |c| Ok((catalog::collection(c, item)?, refs::all(c, item)?)))
        .await?;
    let Some(header) = header else {
        return Err(CoreError::NotFound);
    };
    if header.user {
        return cached(header.id, cursor, CoreError::NotFound).await;
    }
    if !app.is_online() {
        return cached(header.id, cursor, CoreError::Offline).await;
    }
    let kind = match header.kind {
        Kind::Album => EntityKind::Album,
        Kind::Artist => EntityKind::Artist,
        _ => EntityKind::Playlist,
    };
    let fetched = router::first_ok(Capability::Entity, |p| {
        let ext = refs
            .iter()
            .find(|(provider, _)| provider == p.id())
            .map(|(_, r)| r.external_id.clone());
        let cursor = cursor.clone();
        async move {
            let Some(id) = ext else {
                return Err(CallError::Unsupported);
            };
            let target = EntityRef { kind, id };
            let host = app.plugins.host();
            host.fetch_entity(&p, target, &app.cfg.region, cursor).await
        }
    })
    .await;
    match fetched {
        Ok((p, page)) => store_page(header.id, p.id().to_string(), page, cursor.is_some()).await,
        Err(e) => cached(header.id, cursor, e).await,
    }
}

/// The stored header and tracks, or `err` when nothing was stored (or for a later page).
async fn cached(
    item: ItemId,
    cursor: Option<String>,
    err: CoreError,
) -> Result<EntityView, CoreError> {
    if cursor.is_some() {
        return Err(err);
    }
    let page = Page {
        offset: 0,
        limit: CACHED_TRACKS,
    };
    let view = app()
        .db
        .read(move |c| {
            let Some(header) = catalog::collection(c, item)? else {
                return Ok(None);
            };
            let ids = if header.user {
                let entries = playlists::entries(c, item, page)?;
                entries.into_iter().map(|(_, track)| track).collect()
            } else {
                catalog::children(c, item, page)?
            };
            if ids.is_empty() && !header.user {
                return Ok(None);
            }
            let user = header.user;
            Ok(Some(EntityView {
                header: collection_view(header),
                tracks: track_views(c, &ids)?,
                albums: vec![],
                next: None,
                // A user playlist is the user's own data, not a stale copy.
                from_cache: !user,
            }))
        })
        .await?;
    view.ok_or(err)
}

/// The header comes from the first page only: later ones (ytmusic) have a blank title and
/// no owner. Their tracks are appended to the stored ones.
async fn store_page(
    item: ItemId,
    provider: String,
    page: EntityPage,
    later: bool,
) -> Result<EntityView, CoreError> {
    if let Entity::Track(_) = page.entity {
        return Err(CoreError::Internal(
            "entity page: a track for a collection".into(),
        ));
    }
    Ok(app()
        .db
        .write(move |tx| {
            let p = provider.as_str();
            let has_children = !matches!(page.entity, Entity::Artist(_));
            let header = match page.entity {
                _ if later => item,
                Entity::Album(a) => catalog::upsert_album(tx, p, &convert::album(a))?,
                Entity::Artist(a) => catalog::upsert_artist(tx, p, &convert::artist(a))?,
                Entity::Playlist(pl) => catalog::upsert_playlist(tx, p, &convert::playlist(pl))?,
                Entity::Track(_) => unreachable!("refused above"),
            };
            let tracks = page
                .tracks
                .into_iter()
                .map(|t| catalog::upsert_track(tx, p, &convert::track(t)))
                .collect::<rusqlite::Result<Vec<_>>>()?;
            let albums = page
                .albums
                .into_iter()
                .map(|a| catalog::upsert_album(tx, p, &convert::album(a)))
                .collect::<rusqlite::Result<Vec<_>>>()?;
            if has_children {
                catalog::set_children(tx, header, &tracks, later)?;
            }
            let c = &tx.tx;
            let header =
                catalog::collection(c, header)?.ok_or(rusqlite::Error::QueryReturnedNoRows)?;
            Ok(EntityView {
                header: collection_view(header),
                tracks: track_views(c, &tracks)?,
                albums: collection_views(c, &albums)?,
                next: page.next,
                from_cache: false,
            })
        })
        .await?)
}

#[derive(Debug, Clone, PartialEq)]
pub struct ImportResult {
    /// The new user playlist.
    pub id: String,
    /// The source had more than the 50 pages copied.
    pub truncated: bool,
}

/// Copies a public playlist (or album) into a new user playlist: the plugin that recognises
/// the link, at most 50 pages, all or nothing.
pub(crate) async fn import_playlist(link: &str) -> Result<ImportResult, CoreError> {
    online()?;
    let app = app();
    let (plugin, target) = router::first_ok(Capability::Entity, |p| {
        let link = link.to_string();
        async move {
            match app.plugins.host().parse_link(&p, &link).await? {
                Some(r) if matches!(r.kind, EntityKind::Playlist | EntityKind::Album) => Ok(r),
                _ => Err(CallError::NotFound),
            }
        }
    })
    .await?;
    let mut header = None;
    let (mut tracks, mut cursor) = (Vec::new(), None);
    for _ in 0..MAX_IMPORT_PAGES {
        let page = app
            .plugins
            .host()
            .fetch_entity(&plugin, target.clone(), &app.cfg.region, cursor.take())
            .await
            .map_err(|e| CoreError::from_call(e, Capability::Entity))?;
        header.get_or_insert(page.entity);
        tracks.extend(page.tracks);
        match page.next {
            Some(next) => cursor = Some(next),
            None => break,
        }
    }
    let truncated = cursor.is_some();
    let (title, description) = match header {
        Some(Entity::Playlist(p)) => (p.title, p.description),
        Some(Entity::Album(a)) => (a.title, None),
        _ => return Err(CoreError::Internal("import: not a playlist page".into())),
    };
    let provider = plugin.id().to_string();
    let id = app
        .db
        .write(move |tx| {
            let ids = tracks
                .into_iter()
                .map(|t| catalog::upsert_track(tx, &provider, &convert::track(t)))
                .collect::<rusqlite::Result<Vec<_>>>()?;
            let playlist = playlists::create(tx, &title, description.as_deref())?;
            playlists::add(tx, playlist, &ids, Place::End)?;
            Ok(playlist)
        })
        .await?;
    Ok(ImportResult {
        id: id.to_string(),
        truncated,
    })
}

/// A local file for the item's artwork (a track without any: its album's). Providers in the
/// artwork order; the URL passes the plugin's own checks before any download.
pub(crate) async fn artwork_file(id: &str, size: u32) -> Result<Option<String>, CoreError> {
    let item = parse_id(id)?;
    let app = app();
    let images = app
        .db
        .read(move |c| {
            let mut images = catalog::artwork_by_provider(c, item)?;
            if images.is_empty()
                && let Some((album, _)) = catalog::track(c, item)?.and_then(|t| t.album)
            {
                images = catalog::artwork_by_provider(c, album)?;
            }
            Ok(images)
        })
        .await?;
    if images.is_empty() {
        return Ok(None);
    }
    let mut failed = None;
    for p in router::ordered_artwork().await {
        let mine: Vec<Image> = images
            .iter()
            .filter(|(provider, _)| provider == p.id())
            .map(|(_, i)| i.clone())
            .collect();
        let Some(image) = pick(&mine, size) else {
            continue;
        };
        let host = app.plugins.host();
        let Ok(url) = host.check_url(&p, &image.url) else {
            logs::push("warn", p.id(), "artwork url refused");
            continue;
        };
        match app.artwork.file(&host.http_client(&p), &url).await {
            Ok(path) => return Ok(Some(path.display().to_string())),
            Err(e) => failed = Some(e),
        }
    }
    match failed {
        Some(StreamError::Network(_)) => Err(CoreError::Network),
        Some(StreamError::Io(e)) => Err(CoreError::Internal(e)),
        // Refused, missing at the provider or not an image: no artwork.
        _ => Ok(None),
    }
}

/// The smallest width >= `size`, else the largest.
fn pick(images: &[Image], size: u32) -> Option<&Image> {
    images
        .iter()
        .filter(|i| i.width.is_some_and(|w| w >= size))
        .min_by_key(|i| i.width)
        .or_else(|| images.iter().max_by_key(|i| i.width))
}

#[cfg(test)]
pub(crate) mod tests;
