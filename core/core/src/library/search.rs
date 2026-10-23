//! Local fuzzy search over `library_fts` (trigram FTS5) and the search history.
//!
//! Queries of 3+ folded chars run as an FTS5 trigram `MATCH` (OR of the query's distinct
//! char-trigrams, 200 candidates, ranked by `bm25`); shorter queries run a `LIKE` scan using
//! the `fold` SQL function registered on every connection (see `db.rs`). Either way, results
//! are restricted to items "in the library" (liked, in a live user playlist entry or a user
//! playlist itself, downloaded, or played) and re-scored: for each of the folded title and
//! folded subtitle (artists/album, or playlist owner), 1.0 if it contains `q` as a substring,
//! else Jaro-Winkler against it — the higher of the two wins, so a query matching the artist
//! ranks the track same as one matching its title.

use rusqlite::{Connection, Row, params};
use strsim::jaro_winkler;

use super::items::corrupt;
use super::{ItemId, Kind, Tx, fold};

pub struct LocalHit {
    pub item: ItemId,
    pub kind: Kind,
    pub score: f32,
}

/// `r` is the candidate's root item (`items r`, joined via `COALESCE(merged_into, id)`).
/// User data is not rewritten on merge, so those checks match `r`'s whole merge group.
const IN_LIBRARY: &str = "(
    EXISTS (SELECT 1 FROM likes WHERE likes.item_id IN (SELECT id FROM items WHERE id = r.id OR merged_into = r.id)
        AND likes.deleted_at IS NULL)
    OR EXISTS (SELECT 1 FROM playlist_items pi JOIN playlists p ON p.item_id = pi.playlist_id
        WHERE pi.item_id IN (SELECT id FROM items WHERE id = r.id OR merged_into = r.id)
        AND pi.deleted_at IS NULL AND p.deleted_at IS NULL)
    OR EXISTS (SELECT 1 FROM playlists WHERE playlists.item_id = r.id AND playlists.deleted_at IS NULL)
    OR EXISTS (SELECT 1 FROM downloads
        WHERE downloads.item_id IN (SELECT id FROM items WHERE id = r.id OR merged_into = r.id))
    OR EXISTS (SELECT 1 FROM plays WHERE plays.item_id IN (SELECT id FROM items WHERE id = r.id OR merged_into = r.id)
        AND plays.deleted_at IS NULL)
)";

/// Items in the user's library only: liked, in a user playlist (as an entry, or the
/// playlist itself), downloaded or played.
pub fn local(c: &Connection, query: &str, limit: u32) -> rusqlite::Result<Vec<LocalHit>> {
    let q = fold(query);
    if q.is_empty() {
        return Ok(vec![]);
    }
    let candidates = if q.chars().count() >= 3 {
        trigram_candidates(c, &q)?
    } else {
        like_candidates(c, query)?
    };
    let mut hits: Vec<LocalHit> = candidates
        .into_iter()
        .map(|(item, kind, title, subtitle)| {
            let score = score_text(&q, &title).max(score_text(&q, &subtitle));
            LocalHit { item, kind, score }
        })
        .collect();
    hits.sort_by(|a, b| b.score.total_cmp(&a.score));
    hits.truncate(limit as usize);
    Ok(hits)
}

/// 1.0 if `q` is a substring of `text`, else Jaro-Winkler similarity.
fn score_text(q: &str, text: &str) -> f32 {
    if text.contains(q) {
        1.0
    } else {
        jaro_winkler(q, text) as f32
    }
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

fn row(r: &Row) -> rusqlite::Result<(ItemId, Kind, String, String)> {
    let kind: String = r.get(1)?;
    let kind =
        Kind::parse(&kind).ok_or_else(|| corrupt("search.kind", format!("unknown kind {kind}")))?;
    Ok((r.get(0)?, kind, r.get(2)?, r.get(3)?))
}

fn trigram_candidates(
    c: &Connection,
    q: &str,
) -> rusqlite::Result<Vec<(ItemId, Kind, String, String)>> {
    let m = match_expr(q);
    let mut st = c.prepare(&format!(
        "SELECT r.id, r.kind, library_fts.title, library_fts.subtitle FROM library_fts
         JOIN items i ON i.id = library_fts.item_id
         JOIN items r ON r.id = COALESCE(i.merged_into, i.id)
         WHERE library_fts MATCH ?1 AND r.deleted_at IS NULL AND {IN_LIBRARY}
         ORDER BY bm25(library_fts) LIMIT 200"
    ))?;
    st.query_map(params![m], row)?.collect()
}

fn like_candidates(
    c: &Connection,
    query: &str,
) -> rusqlite::Result<Vec<(ItemId, Kind, String, String)>> {
    let mut st = c.prepare(&format!(
        "SELECT r.id, r.kind, library_fts.title, library_fts.subtitle FROM library_fts
         JOIN items i ON i.id = library_fts.item_id
         JOIN items r ON r.id = COALESCE(i.merged_into, i.id)
         WHERE (library_fts.title LIKE '%' || fold(?1) || '%'
                OR library_fts.subtitle LIKE '%' || fold(?1) || '%')
           AND r.deleted_at IS NULL AND {IN_LIBRARY}
         ORDER BY r.id"
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
    use crate::library::{Db, downloads, likes, playlists, plays};

    fn track(title: &str, artist: &str, ext: &str) -> TrackData {
        TrackData {
            ext_id: ext.into(),
            title: title.into(),
            artists: vec![ArtistData {
                ext_id: None,
                name: artist.into(),
                artwork: vec![],
            }],
            album: None,
            duration_ms: None,
            isrc: None,
            explicit: false,
            artwork: vec![],
        }
    }

    fn liked_track(tx: &Tx, title: &str, artist: &str, ext: &str) -> rusqlite::Result<ItemId> {
        let id = catalog::upsert_track(tx, "deezer", &track(title, artist, ext))?;
        likes::set(tx, id, true)?;
        Ok(id)
    }

    #[test]
    fn fuzzy_search_absorbs_typos_and_accents() {
        let db = Db::open_in_memory().unwrap();
        let (halo, hymne, tnt, yoasobi) = db
            .write_blocking(|tx| {
                let halo = liked_track(tx, "Halo", "Beyoncé", "1")?;
                let hymne = liked_track(tx, "Hymne à l'amour", "Édith Piaf", "2")?;
                let tnt = liked_track(tx, "T.N.T.", "AC/DC", "3")?;
                let yoasobi = liked_track(tx, "夜に駆ける", "YOASOBI", "4")?;
                // Look-alike competitors: close enough to pull in via trigrams, not close
                // enough to outrank the real match's exact substring (title or artist) hit.
                liked_track(tx, "Edit", "DJ Someone", "5")?;
                liked_track(tx, "Beyond", "Someone Else", "6")?;
                Ok((halo, hymne, tnt, yoasobi))
            })
            .unwrap();
        db.read_blocking(|c| {
            let first = |q: &str| local(c, q, 10).unwrap().first().map(|h| h.item);
            // "beyonse" is close to the artist "Beyoncé" (folded "beyonce") but not a
            // substring of it; "Beyond" is also close but less so — Halo still wins.
            assert_eq!(first("beyonse"), Some(halo));
            // "edith" is a literal substring of the artist "Édith Piaf" (folded "edith
            // piaf"), beating "Edit" which is merely similar.
            assert_eq!(first("edith"), Some(hymne));
            // "ac dc" is a literal substring of the folded artist "ac dc".
            assert_eq!(first("ac dc"), Some(tnt));
            // Short (< 3 chars) CJK query: LIKE path, substring of the folded title.
            assert_eq!(first("夜に"), Some(yoasobi));
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn search_is_limited_to_the_library() {
        let db = Db::open_in_memory().unwrap();
        let ids = db
            .write_blocking(|tx| {
                let cached_only =
                    catalog::upsert_track(tx, "deezer", &track("Zephyr Cached", "Artist", "1"))?;
                let played =
                    catalog::upsert_track(tx, "deezer", &track("Zephyr Played", "Artist", "2"))?;
                plays::start(tx, played, "test", None)?;
                let downloaded = catalog::upsert_track(
                    tx,
                    "deezer",
                    &track("Zephyr Downloaded", "Artist", "3"),
                )?;
                downloads::enqueue(tx, downloaded, "mp3")?;
                let listed =
                    catalog::upsert_track(tx, "deezer", &track("Zephyr Listed", "Artist", "4"))?;
                let mix = playlists::create(tx, "Mix", None)?;
                playlists::add(tx, mix, &[listed], playlists::Place::End)?;
                let user_playlist = playlists::create(tx, "Zephyr Mix", None)?;
                let unliked =
                    catalog::upsert_track(tx, "deezer", &track("Zephyr Unliked", "Artist", "5"))?;
                likes::set(tx, unliked, true)?;
                likes::set(tx, unliked, false)?;
                let gone_playlist = playlists::create(tx, "Zephyr Gone", None)?;
                playlists::delete(tx, gone_playlist)?;
                Ok((
                    cached_only,
                    played,
                    downloaded,
                    listed,
                    user_playlist,
                    unliked,
                    gone_playlist,
                ))
            })
            .unwrap();
        let (cached_only, played, downloaded, listed, user_playlist, unliked, gone_playlist) = ids;
        let found: Vec<ItemId> = db
            .read_blocking(|c| local(c, "zephyr", 50))
            .unwrap()
            .into_iter()
            .map(|h| h.item)
            .collect();
        for present in [played, downloaded, listed, user_playlist] {
            assert!(found.contains(&present), "{present} should be found");
        }
        for absent in [cached_only, unliked, gone_playlist] {
            assert!(!found.contains(&absent), "{absent} should not be found");
        }
    }

    #[test]
    fn user_data_on_a_merged_item_counts_for_its_root() {
        let db = Db::open_in_memory().unwrap();
        let (liked_root, played_root, listed_root) = db
            .write_blocking(|tx| {
                let mut roots = vec![];
                for (n, title) in ["Quasar Liked", "Quasar Played", "Quasar Listed"]
                    .iter()
                    .enumerate()
                {
                    // Root first (older UUIDv7 wins the merge), then the duplicate that carries
                    // the user data and is merged into it.
                    let root = catalog::upsert_track(
                        tx,
                        "deezer",
                        &track(title, "Artist", &format!("r{n}")),
                    )?;
                    let dup = catalog::upsert_track(
                        tx,
                        "qobuz",
                        &track(title, "Artist", &format!("d{n}")),
                    )?;
                    match n {
                        0 => likes::set(tx, dup, true)?,
                        1 => {
                            plays::start(tx, dup, "test", None)?;
                        }
                        _ => {
                            let mix = playlists::create(tx, "Mix", None)?;
                            playlists::add(tx, mix, &[dup], playlists::Place::End)?;
                        }
                    }
                    assert_eq!(crate::library::items::merge(tx, dup, root)?, root);
                    roots.push(root);
                }
                Ok((roots[0], roots[1], roots[2]))
            })
            .unwrap();
        let found: Vec<ItemId> = db
            .read_blocking(|c| local(c, "quasar", 50))
            .unwrap()
            .into_iter()
            .map(|h| h.item)
            .collect();
        for root in [liked_root, played_root, listed_root] {
            assert_eq!(
                found.iter().filter(|&&f| f == root).count(),
                1,
                "{root} found once"
            );
        }
        assert_eq!(found.len(), 3);
    }

    #[test]
    fn exact_substring_ranks_first() {
        let db = Db::open_in_memory().unwrap();
        let (halo, hallo) = db
            .write_blocking(|tx| {
                Ok((
                    liked_track(tx, "Halo", "Artist", "1")?,
                    liked_track(tx, "Hallo Hallo", "Artist", "2")?,
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
        db.write_blocking(|tx| liked_track(tx, "Halo", "Artist", "1"))
            .unwrap();
        db.read_blocking(|c| {
            // Fold to empty (pure punctuation): no error, no crash into "match everything".
            for q in ["", "\"", "-", "!!!"] {
                assert!(local(c, q, 10)?.is_empty(), "{q:?} should find nothing");
            }
            // Fold to a real (trigram-path) query: FTS5 operators in the input are never
            // parsed as such, only matched as literal substrings — just needs to not error.
            for q in ["AND", "a*", "NEAR("] {
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
            .read_blocking(|c| {
                c.query_row("SELECT count(*) FROM search_history", [], |r| {
                    r.get::<_, i64>(0)
                })
            })
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
            .read_blocking(|c| {
                c.query_row("SELECT count(*) FROM search_history", [], |r| {
                    r.get::<_, i64>(0)
                })
            })
            .unwrap();
        assert_eq!(count, 200);

        // Re-recording an existing query bumps it to the front instead of duplicating it.
        db.write_blocking(|tx| {
            record_query(tx, "query 100")?;
            tx.tx.execute(
                "UPDATE search_history SET used_at = 1000 WHERE query = 'query 100'",
                [],
            )?;
            Ok(())
        })
        .unwrap();
        let top = db.read_blocking(|c| history(c, "query", 1)).unwrap();
        assert_eq!(top, vec!["query 100"]);
        let count = db
            .read_blocking(|c| {
                c.query_row("SELECT count(*) FROM search_history", [], |r| {
                    r.get::<_, i64>(0)
                })
            })
            .unwrap();
        assert_eq!(count, 200);

        // Prefix matching folds accents/case on both sides.
        db.write_blocking(|tx| record_query(tx, "Édith Piaf"))
            .unwrap();
        let hits = db.read_blocking(|c| history(c, "edith", 10)).unwrap();
        assert_eq!(hits, vec!["Édith Piaf"]);
    }

    /// `%` and `_` typed by the user never act as LIKE wildcards: `fold` turns every
    /// non-alphanumeric into a space before the pattern is built, so no escaping is needed.
    /// (`50%` folds to `50`, which does match `500 Days` as a plain substring.)
    #[test]
    fn typed_wildcards_never_widen_a_search() {
        let db = Db::open_in_memory().unwrap();
        db.write_blocking(|tx| {
            liked_track(tx, "axb", "Someone", "1")?;
            liked_track(tx, "axxb", "Someone", "2")?;
            record_query(tx, "axb")?;
            record_query(tx, "axxb")
        })
        .unwrap();
        for q in ["a_b", "a%b", "a__b"] {
            let hits = db.read_blocking(|c| local(c, q, 10)).unwrap();
            assert!(
                hits.iter().all(|h| h.score < 1.0),
                "local {q:?} matched as a pattern"
            );
            let past = db.read_blocking(|c| history(c, q, 10)).unwrap();
            assert!(past.is_empty(), "history {q:?}: {past:?}");
        }
    }
}
