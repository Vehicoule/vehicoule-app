//! Local fuzzy search over `library_fts` (trigram FTS5) and the search history.
//!
//! Queries of 3+ folded chars run as an FTS5 trigram `MATCH` (OR of the query's distinct
//! char-trigrams, 200 candidates, ranked by `bm25`); shorter queries run a `LIKE` scan using
//! the `fold` SQL function registered on every connection (see `db.rs`). Either way, results
//! are restricted to items "in the library" (liked, in a live user playlist entry,
//! downloaded, or played) and re-scored: 1.0 for a folded-title substring match, else
//! Jaro-Winkler against the folded title.

use rusqlite::{Connection, Row, params};
use strsim::jaro_winkler;

use super::items::invalid;
use super::{ItemId, Kind, Tx, fold};

pub struct LocalHit {
    pub item: ItemId,
    pub kind: Kind,
    pub score: f32,
}

/// `r` is the candidate's root item (`items r`, joined via `COALESCE(merged_into, id)`).
const IN_LIBRARY: &str = "(
    EXISTS (SELECT 1 FROM likes WHERE likes.item_id = r.id AND likes.deleted_at IS NULL)
    OR EXISTS (SELECT 1 FROM playlist_items pi JOIN playlists p ON p.item_id = pi.playlist_id
        WHERE pi.item_id = r.id AND pi.deleted_at IS NULL AND p.deleted_at IS NULL)
    OR EXISTS (SELECT 1 FROM downloads WHERE downloads.item_id = r.id)
    OR EXISTS (SELECT 1 FROM plays WHERE plays.item_id = r.id AND plays.deleted_at IS NULL)
)";

/// Items in the user's library only: liked, in a user playlist, downloaded or played.
pub fn local(c: &Connection, query: &str, limit: u32) -> rusqlite::Result<Vec<LocalHit>> {
    let q = fold(query);
    let candidates = if q.chars().count() >= 3 {
        trigram_candidates(c, &q)?
    } else {
        like_candidates(c, query)?
    };
    let mut hits: Vec<LocalHit> = candidates
        .into_iter()
        .map(|(item, kind, title)| {
            let score = if title.contains(&q) {
                1.0
            } else {
                jaro_winkler(&q, &title) as f32
            };
            LocalHit { item, kind, score }
        })
        .collect();
    hits.sort_by(|a, b| b.score.partial_cmp(&a.score).unwrap_or(std::cmp::Ordering::Equal));
    hits.truncate(limit as usize);
    Ok(hits)
}

/// Stores the query (trimmed) with `now`, bumping `used_at` if it was already recorded, then
/// keeps only the 200 most recently used. Blank queries are not recorded.
pub fn record_query(tx: &Tx, query: &str) -> rusqlite::Result<()> {
    let q = query.trim();
    if q.is_empty() {
        return Ok(());
    }
    tx.tx.execute(
        "INSERT INTO search_history (query, used_at) VALUES (?1, ?2)
         ON CONFLICT (query) DO UPDATE SET used_at = excluded.used_at",
        params![q, tx.now_ms],
    )?;
    tx.tx.execute(
        "DELETE FROM search_history WHERE rowid NOT IN
           (SELECT rowid FROM search_history ORDER BY used_at DESC, rowid DESC LIMIT 200)",
        [],
    )?;
    Ok(())
}

/// Recorded queries whose folded text starts with the folded prefix, most recent first.
pub fn history(c: &Connection, prefix: &str, limit: u32) -> rusqlite::Result<Vec<String>> {
    let mut st = c.prepare(
        "SELECT query FROM search_history WHERE fold(query) LIKE fold(?1) || '%'
         ORDER BY used_at DESC, rowid DESC LIMIT ?2",
    )?;
    st.query_map(params![prefix, limit], |r| r.get(0))?
        .collect()
}

fn row(r: &Row) -> rusqlite::Result<(ItemId, Kind, String)> {
    let kind: String = r.get(1)?;
    let kind = Kind::parse(&kind).ok_or_else(|| invalid(format!("search: unknown kind {kind}")))?;
    Ok((r.get(0)?, kind, r.get(2)?))
}

fn trigram_candidates(c: &Connection, q: &str) -> rusqlite::Result<Vec<(ItemId, Kind, String)>> {
    let m = match_expr(q);
    let mut st = c.prepare(&format!(
        "SELECT library_fts.item_id, i.kind, library_fts.title FROM library_fts
         JOIN items i ON i.id = library_fts.item_id
         JOIN items r ON r.id = COALESCE(i.merged_into, i.id)
         WHERE library_fts MATCH ?1 AND r.deleted_at IS NULL AND {IN_LIBRARY}
         ORDER BY bm25(library_fts) LIMIT 200"
    ))?;
    st.query_map(params![m], row)?.collect()
}

fn like_candidates(c: &Connection, query: &str) -> rusqlite::Result<Vec<(ItemId, Kind, String)>> {
    let mut st = c.prepare(&format!(
        "SELECT library_fts.item_id, i.kind, library_fts.title FROM library_fts
         JOIN items i ON i.id = library_fts.item_id
         JOIN items r ON r.id = COALESCE(i.merged_into, i.id)
         WHERE (library_fts.title LIKE '%' || fold(?1) || '%'
                OR library_fts.subtitle LIKE '%' || fold(?1) || '%')
           AND r.deleted_at IS NULL AND {IN_LIBRARY}"
    ))?;
    st.query_map(params![query], row)?.collect()
}

/// `q`'s distinct char-trigrams (sliding window of 3), each a quoted FTS5 MATCH term with any
/// embedded `"` doubled: operators in user input (`AND`, `NEAR(`, bare `"`...) never parse as
/// FTS5 syntax, only as literal substrings.
fn match_expr(q: &str) -> String {
    let chars: Vec<char> = q.chars().collect();
    let mut seen = std::collections::HashSet::new();
    let mut terms = Vec::new();
    for w in chars.windows(3) {
        let t: String = w.iter().collect();
        if seen.insert(t.clone()) {
            terms.push(format!("\"{}\"", t.replace('"', "\"\"")));
        }
    }
    terms.join(" OR ")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::library::catalog::{self, ArtistData, TrackData};
    use crate::library::{Db, likes};

    fn track(title: &str, ext: &str) -> TrackData {
        TrackData {
            ext_id: ext.into(),
            title: title.into(),
            artists: vec![ArtistData {
                ext_id: None,
                name: "Artist".into(),
                artwork: vec![],
            }],
            album: None,
            duration_ms: None,
            isrc: None,
            explicit: false,
            artwork: vec![],
        }
    }

    fn liked_track(tx: &Tx, title: &str, ext: &str) -> rusqlite::Result<ItemId> {
        let id = catalog::upsert_track(tx, "deezer", &track(title, ext))?;
        likes::set(tx, id, true)?;
        Ok(id)
    }

    #[test]
    fn fuzzy_search_absorbs_typos_and_accents() {
        let db = Db::open_in_memory().unwrap();
        let (halo, hymne, tnt, yoasobi) = db
            .write_blocking(|tx| {
                Ok((
                    liked_track(tx, "Beyoncé - Halo", "1")?,
                    liked_track(tx, "Édith Piaf - Hymne", "2")?,
                    liked_track(tx, "AC/DC - T.N.T.", "3")?,
                    liked_track(tx, "YOASOBI - 夜に駆ける", "4")?,
                ))
            })
            .unwrap();
        db.read_blocking(|c| {
            let first = |q: &str| local(c, q, 10).unwrap().first().map(|h| h.item);
            assert_eq!(first("beyonse"), Some(halo));
            assert_eq!(first("edith"), Some(hymne));
            assert_eq!(first("ac dc"), Some(tnt));
            assert_eq!(first("夜に"), Some(yoasobi));
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn search_is_limited_to_the_library() {
        let db = Db::open_in_memory().unwrap();
        db.write_blocking(|tx| {
            // Only in the catalogue cache: never liked, played, downloaded or playlisted.
            catalog::upsert_track(tx, "deezer", &track("Halo Cached Only", "1"))?;
            Ok(())
        })
        .unwrap();
        let hits = db.read_blocking(|c| local(c, "halo", 10)).unwrap();
        assert!(hits.is_empty());
    }

    #[test]
    fn exact_substring_ranks_first() {
        let db = Db::open_in_memory().unwrap();
        let (halo, hallo) = db
            .write_blocking(|tx| {
                Ok((
                    liked_track(tx, "Halo", "1")?,
                    liked_track(tx, "Hallo Hallo", "2")?,
                ))
            })
            .unwrap();
        let hits = db.read_blocking(|c| local(c, "halo", 10)).unwrap();
        let ids: Vec<_> = hits.iter().map(|h| h.item).collect();
        assert_eq!(ids[0], halo);
        assert!(ids.contains(&hallo));
        assert_eq!(hits[0].score, 1.0);
    }

    #[test]
    fn fts_operators_are_inert() {
        let db = Db::open_in_memory().unwrap();
        db.write_blocking(|tx| liked_track(tx, "Halo", "1")).unwrap();
        db.read_blocking(|c| {
            for q in ["AND", "\"", "a*", "NEAR("] {
                local(c, q, 10)?;
            }
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn history_keeps_200_most_recent() {
        let db = Db::open_in_memory().unwrap();
        // Pin `used_at` to the insertion index, not the wall clock: a tight loop can tie on
        // the same millisecond, and recency here must be unambiguous regardless.
        for i in 0..205 {
            db.write_blocking(move |tx| {
                record_query(tx, &format!("query {i}"))?;
                tx.tx.execute(
                    "UPDATE search_history SET used_at = ?1 WHERE query = ?2",
                    params![i, format!("query {i}")],
                )?;
                Ok(())
            })
            .unwrap();
        }
        let count = db
            .read_blocking(|c| c.query_row("SELECT count(*) FROM search_history", [], |r| r.get::<_, i64>(0)))
            .unwrap();
        assert_eq!(count, 200);
        // Oldest 5 are gone, newest kept, most recent first.
        let top = db.read_blocking(|c| history(c, "query", 3)).unwrap();
        assert_eq!(top, vec!["query 204", "query 203", "query 202"]);
        assert!(
            db.read_blocking(|c| history(c, "query 0", 1))
                .unwrap()
                .is_empty()
        );

        // Blank queries are never recorded.
        db.write_blocking(|tx| record_query(tx, "   ")).unwrap();
        let count = db
            .read_blocking(|c| c.query_row("SELECT count(*) FROM search_history", [], |r| r.get::<_, i64>(0)))
            .unwrap();
        assert_eq!(count, 200);

        // Re-recording an existing query bumps it to the front instead of duplicating it.
        db.write_blocking(|tx| {
            record_query(tx, "query 100")?;
            tx.tx
                .execute("UPDATE search_history SET used_at = 1000 WHERE query = 'query 100'", [])?;
            Ok(())
        })
        .unwrap();
        let top = db.read_blocking(|c| history(c, "query", 1)).unwrap();
        assert_eq!(top, vec!["query 100"]);
        let count = db
            .read_blocking(|c| c.query_row("SELECT count(*) FROM search_history", [], |r| r.get::<_, i64>(0)))
            .unwrap();
        assert_eq!(count, 200);

        // Prefix matching folds accents/case on both sides.
        db.write_blocking(|tx| record_query(tx, "Édith Piaf")).unwrap();
        let hits = db.read_blocking(|c| history(c, "edith", 10)).unwrap();
        assert_eq!(hits, vec!["Édith Piaf"]);
    }
}
