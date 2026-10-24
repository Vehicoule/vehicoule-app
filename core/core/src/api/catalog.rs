//! Search, pages, imports, artwork, lyrics: routed to plugins (online) or read from the cache.

use crate::catalog::{
    self as core, CollectionView, EntityView, ImportResult, SearchView, SuggestionView,
};
use crate::error::CoreError;
use crate::lyrics::LyricsView;

/// An artist's latest release: the "Latest release" card.
#[derive(Debug, Clone, PartialEq)]
pub struct ReleaseView {
    pub album: CollectionView,
    /// `YYYY-MM-DD`.
    pub date: String,
}

pub async fn search(query: String) -> Result<SearchView, CoreError> {
    core::search(&query).await
}

/// Past searches first (`from_history`), then the plugin's.
pub async fn suggest(prefix: String) -> Result<Vec<SuggestionView>, CoreError> {
    core::suggest(&prefix).await
}

/// `cursor`: the `next` of the previous page.
pub async fn entity(id: String, cursor: Option<String>) -> Result<EntityView, CoreError> {
    core::entity(&id, cursor).await
}

/// The new user playlist, and whether the 50-page cap cut it.
pub async fn import_playlist(link: String) -> Result<ImportResult, CoreError> {
    core::import_playlist(&link).await
}

/// A local file path, `None` when no plugin has a picture.
pub async fn artwork_file(id: String, size: u32) -> Result<Option<String>, CoreError> {
    core::artwork_file(&id, size).await
}

pub async fn lyrics(id: String) -> Result<Option<LyricsView>, CoreError> {
    crate::lyrics::lyrics(&id).await
}

/// The artist's newest release, from the 24 h copy of its releases; `None` when older than
/// 90 days, without a `browse` plugin, or on an error (logged, never raised).
pub async fn artist_latest_release(artist_id: String) -> Result<Option<ReleaseView>, CoreError> {
    let Ok(artist) = core::parse_id(&artist_id) else {
        crate::logs::push("warn", "browse", "latest release: malformed artist id");
        return Ok(None);
    };
    Ok(crate::browse::latest_release(artist, crate::plugins::now_ms()).await)
}
