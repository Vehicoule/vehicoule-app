//! The feed's local reads: seeds, local shelves, what discovery leaves out.

use rusqlite::Connection;

use super::assemble::{Inputs, Pick, folded};
use crate::library::catalog::{self, TrackRow};
use crate::library::plays::{self, TOP_WINDOW_MS};
use crate::library::{CollectionSort, ItemId, Kind, Page, TrackSort, downloads, likes, playlists};

pub(super) const TRACK_SEEDS: usize = 5;
const ARTISTS: usize = 10;
const MIXES: usize = 6;
const SHORTCUTS: u32 = 6;
/// Local shelves' length.
pub(super) const ROWS: u32 = 20;
const REDISCOVER_MS: i64 = 60 * 86_400_000;

pub(super) struct Local {
    /// The local inputs; the network ones empty.
    pub inputs: Inputs,
    /// Liked tracks (most recent first), then the 90-day top: up to 5.
    pub track_seeds: Vec<ItemId>,
    /// The 10 most recently liked artists, each with its most played track.
    pub liked_artists: Vec<(ItemId, Option<ItemId>)>,
}

pub(super) fn read(c: &Connection, now_ms: i64) -> rusqlite::Result<Local> {
    let since = now_ms - TOP_WINDOW_MS;
    let first = |limit| Page { offset: 0, limit };
    let mut track_seeds = likes::list(c, Kind::Track, first(TRACK_SEEDS as u32))?;
    let top = plays::top_items(c, Kind::Track, since, TRACK_SEEDS as u32)?;
    push_new(&mut track_seeds, top, TRACK_SEEDS);
    let liked = likes::list(c, Kind::Artist, first(ARTISTS as u32))?;
    let mut artists = plays::top_items(c, Kind::Artist, since, ARTISTS as u32)?;
    push_new(&mut artists, liked.iter().copied(), ARTISTS);
    let mut top_artists = Vec::new();
    for &a in &artists {
        if let Some(row) = catalog::collection(c, a)? {
            top_artists.push((row.id, row.title));
        }
    }
    let liked_artists = liked
        .into_iter()
        .map(|a| Ok((a, plays::top_track_of(c, a)?)))
        .collect::<rusqlite::Result<_>>()?;
    let mut mine = playlists::list(c, CollectionSort::Recent)?;
    mine.truncate(ROWS as usize);
    let excluded = plays::played_or_liked(c)?;
    // ponytail: reads every played or liked track in full; a SQL fold() query if it gets slow
    let all: Vec<ItemId> = excluded.iter().copied().collect();
    let folded_excluded = catalog::tracks(c, &all)?.iter().map(key).collect();
    artists.truncate(MIXES);
    let inputs = Inputs {
        shortcuts: plays::top_contexts(c, since, SHORTCUTS)?,
        top_artists,
        mixes: artists,
        rediscover: plays::liked_not_played_since(c, now_ms - REDISCOVER_MS, ROWS)?,
        recent: plays::recent_items(c, Kind::Track, first(ROWS))?,
        playlists: mine,
        downloads: downloads::done(c, TrackSort::Added, first(ROWS))?,
        excluded,
        folded_excluded,
        ..Inputs::default()
    };
    Ok(Local {
        inputs,
        track_seeds,
        liked_artists,
    })
}

/// The tracks `ids` as discovery candidates; unknown ids skipped.
pub(super) fn candidates(c: &Connection, ids: &[ItemId]) -> rusqlite::Result<Vec<Pick>> {
    Ok(catalog::tracks(c, ids)?
        .into_iter()
        .map(|t| Pick {
            folded: key(&t),
            id: t.id,
            isrc: t.isrc,
        })
        .collect())
}

fn key(t: &TrackRow) -> String {
    folded(&t.title, t.artists.first().map_or("", |a| a.1.as_str()))
}

/// Appends the ids of `more` not already in `to`, up to `cap` in all.
pub(super) fn push_new(to: &mut Vec<ItemId>, more: impl IntoIterator<Item = ItemId>, cap: usize) {
    for id in more {
        if to.len() >= cap {
            break;
        }
        if !to.contains(&id) {
            to.push(id);
        }
    }
}
