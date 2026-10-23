//! The user's library: likes, history, playlists, downloads, local search.

use crate::api::forward;
use crate::app::app;
use crate::catalog::{
    CollectionView, ItemKind, TrackView, collection_views, parse_id, track_view, track_views,
};
use crate::downloads::{self, DownloadProgress};
use crate::error::CoreError;
use crate::events::LibraryChanged;
use crate::frb_generated::StreamSink;
use crate::library::downloads::{self as rows, DownloadState};
use crate::library::playlists::{self, EntryId, Place};
use crate::library::{ItemId, Kind, Page, catalog, likes, plays, search};

const HOME_ROWS: u32 = 20;
const LOCAL_HITS: u32 = 50;

pub struct HomeView {
    pub recent: Vec<TrackView>,
    pub liked: Vec<TrackView>,
    pub playlists: Vec<CollectionView>,
    pub downloads: Vec<TrackView>,
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

/// 20 of each: recently played, liked, playlists, downloaded.
pub async fn home() -> Result<HomeView, CoreError> {
    Ok(app()
        .db
        .read(|c| {
            let mut done = rows::list(c, Some(DownloadState::Done))?;
            done.truncate(HOME_ROWS as usize);
            let downloaded: Vec<ItemId> = done.iter().map(|r| r.item).collect();
            let mut mine = playlists::list(c)?;
            mine.truncate(HOME_ROWS as usize);
            Ok(HomeView {
                recent: track_views(c, &plays::recent_items(c, Kind::Track, page(0, HOME_ROWS))?)?,
                liked: track_views(c, &likes::list(c, Kind::Track, page(0, HOME_ROWS))?)?,
                playlists: collection_views(c, &mine)?,
                downloads: track_views(c, &downloaded)?,
            })
        })
        .await?)
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
pub async fn tracks(ids: Vec<String>) -> Result<Vec<TrackView>, CoreError> {
    let items = ids
        .iter()
        .map(|i| parse_id(i))
        .collect::<Result<Vec<_>, _>>()?;
    Ok(app().db.read(move |c| track_views(c, &items)).await?)
}

/// Liked albums, artists or playlists, most recent first.
pub async fn liked(
    kind: ItemKind,
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
        .read(move |c| collection_views(c, &likes::list(c, kind, page(offset, limit))?))
        .await?)
}

pub async fn liked_tracks(offset: u32, limit: u32) -> Result<Vec<TrackView>, CoreError> {
    Ok(app()
        .db
        .read(move |c| track_views(c, &likes::list(c, Kind::Track, page(offset, limit))?))
        .await?)
}

/// Tracks by latest play.
pub async fn history(offset: u32, limit: u32) -> Result<Vec<TrackView>, CoreError> {
    Ok(app()
        .db
        .read(move |c| {
            track_views(
                c,
                &plays::recent_items(c, Kind::Track, page(offset, limit))?,
            )
        })
        .await?)
}

/// The user's playlists, newest first.
pub async fn playlists() -> Result<Vec<CollectionView>, CoreError> {
    Ok(app()
        .db
        .read(|c| collection_views(c, &playlists::list(c)?))
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
}
