//! The user's library: the home feed, likes, history, playlists, downloads, local search.

use serde::{Deserialize, Serialize};

use crate::api::forward;
use crate::app::app;
use crate::catalog::{
    CardView, CollectionView, ItemKind, TrackView, collection_views, parse_id, track_view,
    track_views,
};
use crate::downloads::{self, DownloadProgress};
use crate::error::CoreError;
use crate::events::LibraryChanged;
use crate::frb_generated::StreamSink;
use crate::library::downloads as rows;
use crate::library::playlists::{self, EntryId, Place};
use crate::library::{
    CollectionSort, ItemId, Kind, Page, TrackSort, catalog, likes, plays, search,
};
use crate::{home, player};

const LOCAL_HITS: u32 = 50;

/// What a home shelf is: Dart names it (the core produces no text).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ShelfKindView {
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

#[derive(Debug, Clone, PartialEq)]
pub struct ShelfView {
    pub kind: ShelfKindView,
    /// `BecauseYouListened`: the artist's name.
    pub seed: Option<String>,
    /// `Discovery`: tracks, each with its seed's title as `reason`; `Mixes`: artists.
    pub items: Vec<CardView>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct HomeFeedPage {
    pub shelves: Vec<ShelfView>,
    /// `None` once `End` is in this page.
    pub next: Option<String>,
}

/// The downloads' storage bar.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StorageView {
    /// The finished downloads' files.
    pub music_bytes: u64,
    /// Free on the downloads folder's volume.
    pub free_bytes: u64,
}

/// A track of the history and when it was last played (unix ms), for grouping by day.
pub struct HistoryEntryView {
    pub played_at_ms: i64,
    pub track: TrackView,
}

pub struct PlaylistEntryView {
    /// What `move_in_playlist` and `remove_from_playlist` take.
    pub entry: String,
    pub track: TrackView,
}

fn page(offset: u32, limit: u32) -> Page {
    Page { offset, limit }
}

fn entry_id(s: &str) -> Result<EntryId, CoreError> {
    parse_id(s).map(|i| EntryId(i.0))
}

fn changed(c: LibraryChanged) {
    let _ = app().events.library.send(c);
}

/// Up to 4 shelves from `cursor` (`None`: the first page; else the previous `next`). A feed
/// over 24 h old (or none yet) is served as is and rebuilt in the background;
/// `LibraryChanged::Home` tells when.
pub async fn home_feed(cursor: Option<String>) -> Result<HomeFeedPage, CoreError> {
    home::page(cursor).await
}

/// Rebuilds the feed now (pull to refresh), or waits for the build running;
/// `LibraryChanged::Home` follows. Offline: `Offline` (the last feed is kept).
pub async fn refresh_home() -> Result<(), CoreError> {
    home::refresh().await
}

/// Plays a radio of the artist's most played track (else the first of its page).
pub async fn play_mix(artist_id: String) -> Result<(), CoreError> {
    player::play_mix(artist_id).await
}

pub async fn set_liked(id: String, liked: bool) -> Result<(), CoreError> {
    let item = parse_id(&id)?;
    app()
        .db
        .write(move |tx| likes::set(tx, item, liked))
        .await?;
    changed(LibraryChanged::Likes);
    crate::player::refresh();
    Ok(())
}

/// The tracks of these ids, in order (download rows, notifications); unknown ones left out.
/// Each under the id asked, a merged one included (every input resolves merges).
pub async fn tracks(ids: Vec<String>) -> Result<Vec<TrackView>, CoreError> {
    let items = ids
        .iter()
        .map(|i| parse_id(i))
        .collect::<Result<Vec<_>, _>>()?;
    Ok(app()
        .db
        .read(move |c| {
            let mut views = Vec::new();
            for (id, item) in ids.into_iter().zip(items) {
                if let Some(mut v) = catalog::track(c, item)?.map(track_view) {
                    v.id = id;
                    views.push(v);
                }
            }
            Ok(views)
        })
        .await?)
}

/// Liked albums, artists or playlists in `sort` order.
pub async fn liked(
    kind: ItemKind,
    sort: CollectionSort,
    offset: u32,
    limit: u32,
) -> Result<Vec<CollectionView>, CoreError> {
    let kind = match kind {
        ItemKind::Track => Kind::Track,
        ItemKind::Album => Kind::Album,
        ItemKind::Artist => Kind::Artist,
        ItemKind::Playlist => Kind::Playlist,
    };
    Ok(app()
        .db
        .read(move |c| {
            let ids = likes::list_collections(c, kind, sort, page(offset, limit))?;
            collection_views(c, &ids)
        })
        .await?)
}

pub async fn liked_tracks(
    sort: TrackSort,
    offset: u32,
    limit: u32,
) -> Result<Vec<TrackView>, CoreError> {
    Ok(app()
        .db
        .read(move |c| track_views(c, &likes::list_tracks(c, sort, page(offset, limit))?))
        .await?)
}

/// Finished downloads in `sort` order (`downloads` gives the progress of all of them).
pub async fn downloaded(
    sort: TrackSort,
    offset: u32,
    limit: u32,
) -> Result<Vec<TrackView>, CoreError> {
    Ok(app()
        .db
        .read(move |c| track_views(c, &rows::done(c, sort, page(offset, limit))?))
        .await?)
}

/// The 50 most played tracks (plays of 30 s or more) over 90 days, completed from all time.
pub async fn top_tracks() -> Result<Vec<TrackView>, CoreError> {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_millis() as i64);
    Ok(app()
        .db
        .read(move |c| track_views(c, &plays::top_tracks(c, now)?))
        .await?)
}

/// Tracks by latest play, each with that play's start.
pub async fn history(offset: u32, limit: u32) -> Result<Vec<HistoryEntryView>, CoreError> {
    Ok(app()
        .db
        .read(move |c| {
            let mut out = Vec::new();
            for (id, at) in plays::recent_with_time(c, Kind::Track, page(offset, limit))? {
                if let Some(t) = catalog::track(c, id)? {
                    out.push(HistoryEntryView {
                        played_at_ms: at,
                        track: track_view(t),
                    });
                }
            }
            Ok(out)
        })
        .await?)
}

/// The user's playlists in `sort` order.
pub async fn playlists(sort: CollectionSort) -> Result<Vec<CollectionView>, CoreError> {
    Ok(app()
        .db
        .read(move |c| collection_views(c, &playlists::list(c, sort)?))
        .await?)
}

pub async fn create_playlist(title: String) -> Result<String, CoreError> {
    let id = app()
        .db
        .write(move |tx| playlists::create(tx, &title, None))
        .await?;
    changed(LibraryChanged::Playlists);
    Ok(id.to_string())
}

pub async fn rename_playlist(id: String, title: String) -> Result<(), CoreError> {
    let item = parse_id(&id)?;
    app()
        .db
        .write(move |tx| playlists::rename(tx, item, &title))
        .await?;
    changed(LibraryChanged::Playlists);
    Ok(())
}

pub async fn delete_playlist(id: String) -> Result<(), CoreError> {
    let item = parse_id(&id)?;
    app()
        .db
        .write(move |tx| playlists::delete(tx, item))
        .await?;
    changed(LibraryChanged::Playlists);
    Ok(())
}

pub async fn playlist_entries(
    id: String,
    offset: u32,
    limit: u32,
) -> Result<Vec<PlaylistEntryView>, CoreError> {
    let item = parse_id(&id)?;
    Ok(app()
        .db
        .read(move |c| {
            let entries = playlists::entries(c, item, page(offset, limit))?;
            let mut out = Vec::with_capacity(entries.len());
            for (entry, track) in entries {
                if let Some(t) = catalog::track(c, track)? {
                    out.push(PlaylistEntryView {
                        entry: entry.0.to_string(),
                        track: track_view(t),
                    });
                }
            }
            Ok(out)
        })
        .await?)
}

/// At the end, in the given order.
pub async fn add_to_playlist(id: String, items: Vec<String>) -> Result<(), CoreError> {
    let playlist = parse_id(&id)?;
    let items = items
        .iter()
        .map(|i| parse_id(i))
        .collect::<Result<Vec<_>, _>>()?;
    app()
        .db
        .write(move |tx| playlists::add(tx, playlist, &items, Place::End))
        .await?;
    changed(LibraryChanged::Playlist { id });
    Ok(())
}

/// After `after`, or first when `None`.
pub async fn move_in_playlist(entry: String, after: Option<String>) -> Result<(), CoreError> {
    let entry = entry_id(&entry)?;
    let at = match after {
        Some(a) => Place::After(entry_id(&a)?),
        None => Place::Start,
    };
    let playlist = app()
        .db
        .write(move |tx| {
            playlists::move_entry(tx, entry, at)?;
            playlists::playlist_of(&tx.tx, entry)
        })
        .await?;
    playlist_changed(playlist);
    Ok(())
}

pub async fn remove_from_playlist(entry: String) -> Result<(), CoreError> {
    let entry = entry_id(&entry)?;
    let playlist = app()
        .db
        .write(move |tx| {
            playlists::remove_entry(tx, entry)?;
            playlists::playlist_of(&tx.tx, entry)
        })
        .await?;
    playlist_changed(playlist);
    Ok(())
}

fn playlist_changed(playlist: Option<ItemId>) {
    if let Some(id) = playlist {
        changed(LibraryChanged::Playlist { id: id.to_string() });
    }
}

/// Tracks of the library (liked, in a playlist, downloaded, played) matching `query`.
pub async fn search_library(query: String) -> Result<Vec<TrackView>, CoreError> {
    Ok(app()
        .db
        .read(move |c| {
            let hits = search::local(c, &query, LOCAL_HITS)?;
            let tracks: Vec<ItemId> = hits
                .into_iter()
                .filter(|h| h.kind == Kind::Track)
                .map(|h| h.item)
                .collect();
            track_views(c, &tracks)
        })
        .await?)
}

/// Queued, then two at a time.
pub async fn download(ids: Vec<String>) -> Result<(), CoreError> {
    downloads::enqueue(ids).await
}

/// Stops it and deletes its file.
pub async fn cancel_download(id: String) -> Result<(), CoreError> {
    downloads::cancel(&id).await
}

pub async fn downloads() -> Result<Vec<DownloadProgress>, CoreError> {
    Ok(app()
        .db
        .read(|c| rows::list(c, None))
        .await?
        .into_iter()
        .map(|r| DownloadProgress {
            id: r.item.to_string(),
            bytes_done: r.bytes_done,
            bytes_total: r.bytes_total,
            state: r.state.into(),
        })
        .collect())
}

/// The downloads' storage bar: the finished downloads, and the free space of their volume.
pub async fn download_storage() -> Result<StorageView, CoreError> {
    let done = app()
        .db
        .read(|c| rows::list(c, Some(rows::DownloadState::Done)))
        .await?;
    let dir = app().cfg.downloads_dir.clone();
    let free = tokio::task::spawn_blocking(move || {
        std::fs::create_dir_all(&dir)?;
        fs4::available_space(&dir)
    })
    .await
    .map_err(|e| CoreError::Internal(e.to_string()))?
    .map_err(|e| CoreError::Internal(format!("free space: {e}")))?;
    Ok(StorageView {
        music_bytes: done.iter().map(|r| r.bytes_done).sum(),
        free_bytes: free,
    })
}

pub fn library_changes(sink: StreamSink<LibraryChanged>) {
    forward(app().events.library.subscribe(), move |v| {
        sink.add(v).is_ok()
    });
}

pub fn download_progress(sink: StreamSink<DownloadProgress>) {
    forward(app().events.downloads.subscribe(), move |v| {
        sink.add(v).is_ok()
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::catalog;

    #[tokio::test]
    async fn tracks_by_id_in_order() {
        let (_lock, _) = catalog::tests::setup().await;
        let a = catalog::search("rows a").await.unwrap().tracks[0]
            .id
            .clone();
        let b = catalog::search("rows b").await.unwrap().tracks[0]
            .id
            .clone();
        let gone = ItemId::new().to_string();
        let views = tracks(vec![b, gone, a]).await.unwrap();
        let titles: Vec<_> = views.iter().map(|t| t.title.as_str()).collect();
        assert_eq!(titles, ["rows b", "rows a"], "a missing one is left out");
        assert!(tracks(vec!["nope".into()]).await.is_err());
    }

    #[tokio::test]
    async fn tracks_come_back_under_the_ids_asked() {
        let (_lock, app) = catalog::tests::setup().await;
        let old = catalog::search("merged old").await.unwrap().tracks[0]
            .id
            .clone();
        let new = catalog::search("merged new").await.unwrap().tracks[0]
            .id
            .clone();
        let (a, b) = (parse_id(&old).unwrap(), parse_id(&new).unwrap());
        app.db
            .write(move |tx| crate::library::items::merge(tx, a, b))
            .await
            .unwrap();
        let views = tracks(vec![new.clone(), old.clone()]).await.unwrap();
        let got: Vec<_> = views
            .iter()
            .map(|t| (t.id.as_str(), t.title.as_str()))
            .collect();
        // The newer one points to the older: both read the root, each under its own id.
        assert_eq!(
            got,
            [(new.as_str(), "merged old"), (old.as_str(), "merged old")]
        );
    }

    #[tokio::test]
    async fn history_entries_carry_played_at() {
        let (_lock, app) = catalog::tests::setup().await;
        let id = catalog::search("history at").await.unwrap().tracks[0]
            .id
            .clone();
        let item = parse_id(&id).unwrap();
        let at = 1_700_000_000_000_i64;
        app.db
            .write(move |tx| {
                let p = plays::start(tx, item, "test", None)?;
                tx.tx.execute(
                    "UPDATE plays SET started_at = ?2 WHERE id = ?1",
                    rusqlite::params![p.as_bytes().as_slice(), at],
                )?;
                Ok(())
            })
            .await
            .unwrap();
        let all = history(0, 10_000).await.unwrap();
        let mine = all.iter().find(|e| e.track.id == id).unwrap();
        assert_eq!(mine.played_at_ms, at);
        assert_eq!(mine.track.title, "history at");
    }

    #[tokio::test]
    async fn download_storage_sums_done_files() {
        let (_lock, app) = catalog::tests::setup().await;
        let before = download_storage().await.unwrap().music_bytes;
        let mut ids = vec![];
        for q in ["storage a", "storage b", "storage c"] {
            let id = catalog::search(q).await.unwrap().tracks[0].id.clone();
            ids.push(parse_id(&id).unwrap());
        }
        let sizes = [
            (1_000, rows::DownloadState::Done),
            (2_345, rows::DownloadState::Done),
        ];
        let sizes = sizes
            .into_iter()
            .chain([(500, rows::DownloadState::Running)]);
        let wanted: Vec<_> = ids.into_iter().zip(sizes).collect();
        app.db
            .write(move |tx| {
                for (item, (bytes, state)) in wanted {
                    rows::enqueue(tx, item, "normal")?;
                    rows::update(
                        tx,
                        &rows::DownloadRow {
                            item,
                            state,
                            path: Some(format!("/music/{item}.webm")),
                            quality: "normal".into(),
                            mime: Some("audio/webm".into()),
                            loudness_db: None,
                            bytes_total: Some(bytes),
                            bytes_done: bytes,
                            error: None,
                        },
                    )?;
                }
                Ok(())
            })
            .await
            .unwrap();
        let storage = download_storage().await.unwrap();
        assert_eq!(
            storage.music_bytes - before,
            3_345,
            "the running one left out"
        );
        assert!(storage.free_bytes > 0);
    }

    #[tokio::test]
    async fn refresh_home_emits_library_changed_home() {
        let (_lock, app) = catalog::tests::setup().await;
        crate::home::tests::wipe().await;
        let mut rx = app.events.library.subscribe();
        refresh_home().await.unwrap();
        let mut got = vec![];
        while let Ok(c) = rx.try_recv() {
            got.push(c);
        }
        assert_eq!(got, [LibraryChanged::Home]);
        let page = home_feed(None).await.unwrap();
        assert_eq!(
            page.shelves.last().map(|s| s.kind),
            Some(ShelfKindView::End)
        );
    }

    #[tokio::test]
    async fn play_mix_seeds_with_most_played_track() {
        use crate::home::tests::{play, song, wipe};
        let (_lock, app) = catalog::tests::setup().await;
        crate::player::reset();
        wipe().await;
        let (_, _, artist) = song("mix a").await;
        // The artist's page: "ar-mix-a 1" then "ar-mix-a 2", both by the artist.
        let page = catalog::entity(&artist.to_string(), None).await.unwrap();
        let ids: Vec<ItemId> = page
            .tracks
            .iter()
            .map(|t| parse_id(&t.id).unwrap())
            .collect();
        play(ids[1], None).await;
        play(ids[1], None).await;
        play(ids[0], None).await;
        let mut rx = app.events.queue.subscribe();
        play_mix(artist.to_string()).await.unwrap();
        let mut last = None;
        while let Ok(v) = rx.try_recv() {
            last = Some(v);
        }
        let q = last.unwrap();
        let context = q.context.unwrap();
        assert_eq!(
            (context.kind.as_str(), context.id, context.title.as_str()),
            ("mix", Some(artist.to_string()), "Artist mix-a")
        );
        // The radio of the most played one.
        assert_eq!(q.current.unwrap().title, "radio ar-mix-a-2 1");
        app.set_online(false);
        let offline = play_mix(artist.to_string()).await;
        app.set_online(true);
        assert_eq!(offline, Err(CoreError::Offline));
    }
}
