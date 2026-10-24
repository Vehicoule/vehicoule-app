//! Explore: the routed `browse` capability, cached 24 h, the last copy offline.

use serde::{Deserialize, Serialize};

use crate::browse;
use crate::catalog::CardView;
use crate::error::CoreError;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CategoryView {
    /// The provider's id, for `browse_category`.
    pub id: String,
    /// A provider name (a genre, "Top 50"), not interface text.
    pub title: String,
    /// An item id for `artwork_file`; `None` without a picture.
    pub artwork: Option<String>,
    /// A big card at the top of Explore.
    pub featured: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BrowseShelfView {
    /// A key Dart translates: `tracks`, `albums`, `artists` or `playlists`.
    pub title: String,
    pub items: Vec<CardView>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct CategoryPageView {
    pub title: String,
    pub shelves: Vec<BrowseShelfView>,
    pub next: Option<String>,
    /// The last stored copy, served because the call failed or the app is offline (a copy
    /// still fresh is not flagged).
    pub from_cache: bool,
}

/// Featured cards first, then the browse grid.
pub async fn browse_categories() -> Result<Vec<CategoryView>, CoreError> {
    browse::categories().await
}

/// `cursor`: the `next` of the previous page. Only the first page has a copy.
pub async fn browse_category(
    id: String,
    cursor: Option<String>,
) -> Result<CategoryPageView, CoreError> {
    browse::category(id, cursor).await
}
