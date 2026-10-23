//! Search, pages, imports, artwork, lyrics: routed to plugins (online) or read from the cache.

use crate::catalog::{self as core, EntityView, ImportResult, SearchView};
use crate::error::CoreError;
use crate::lyrics::LyricsView;

pub async fn search(query: String) -> Result<SearchView, CoreError> {
    core::search(&query).await
}

pub async fn suggest(prefix: String) -> Result<Vec<String>, CoreError> {
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
