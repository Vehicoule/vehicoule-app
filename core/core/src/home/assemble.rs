//! The feed's shelves from its inputs: no database, no network.

use std::collections::HashSet;

use super::{ShelfKind, StoredItem, StoredShelf};
use crate::library::{ItemId, fold};

/// The discovery list's length.
const DISCOVERY: usize = 30;

/// What `assemble` works from. Local: read from the library. Network: left empty when
/// `discover` is off or offline. The local shelves (shortcuts, rediscover, recent,
/// playlists, downloads) take no input: they are read when served.
#[derive(Default)]
pub(crate) struct Inputs {
    /// The top artists (id, name): one "because you listened" shelf each.
    pub top_artists: Vec<(ItemId, String)>,
    /// The first top artist's "because you listened" items, when the build loaded them.
    pub because: Option<Vec<StoredItem>>,
    pub mixes: Vec<ItemId>,
    /// Played or liked: never in discovery.
    pub excluded: HashSet<ItemId>,
    /// The `folded` keys of the played or liked tracks.
    pub folded_excluded: HashSet<String>,
    /// Per seed: its title and its radio's tracks.
    pub discovery: Vec<(String, Vec<Pick>)>,
    pub releases: Vec<ItemId>,
    pub chart: Vec<ItemId>,
}

/// A discovery candidate.
pub(crate) struct Pick {
    pub id: ItemId,
    pub isrc: Option<String>,
    /// `folded(title, first artist)`.
    pub folded: String,
}

/// The dedup key of a track: its folded title and first artist.
pub(crate) fn folded(title: &str, artist: &str) -> String {
    format!("{}\u{1f}{}", fold(title), fold(artist))
}

/// The shelves in the spec's order, `End` last. The local ones are kept empty (read when
/// served); an empty loaded network shelf is left out, and without `discover` so is every
/// network shelf.
pub(crate) fn assemble(inputs: Inputs, discover: bool) -> Vec<StoredShelf> {
    let discovery = discovery(inputs.discovery, &inputs.excluded, &inputs.folded_excluded);
    let mut because = inputs.because;
    let mut byl = inputs.top_artists.into_iter().map(|(id, name)| {
        let items = because.take();
        StoredShelf {
            kind: ShelfKind::BecauseYouListened,
            seed: Some(name),
            seed_id: Some(id.to_string()),
            network: true,
            loaded: items.is_some(),
            items: items.unwrap_or_default(),
        }
    });
    let mut out = vec![
        shelf(ShelfKind::Shortcuts, false, vec![]),
        StoredShelf {
            items: discovery,
            ..shelf(ShelfKind::Discovery, true, vec![])
        },
        shelf(ShelfKind::Mixes, true, inputs.mixes),
    ];
    out.extend(byl.next());
    out.extend([
        shelf(ShelfKind::NewReleases, true, inputs.releases),
        shelf(ShelfKind::Rediscover, false, vec![]),
        shelf(ShelfKind::Chart, true, inputs.chart),
    ]);
    out.extend(byl.next());
    out.push(shelf(ShelfKind::Recent, false, vec![]));
    out.extend(byl.next());
    out.push(shelf(ShelfKind::Playlists, false, vec![]));
    out.extend(byl.next());
    out.push(shelf(ShelfKind::Downloads, false, vec![]));
    out.extend(byl);
    out.push(shelf(ShelfKind::End, false, vec![]));
    out.retain(|s| !s.network || (discover && (!s.loaded || !s.items.is_empty())));
    out
}

fn shelf(kind: ShelfKind, network: bool, ids: Vec<ItemId>) -> StoredShelf {
    StoredShelf {
        kind,
        seed: None,
        seed_id: None,
        network,
        loaded: true,
        items: ids
            .into_iter()
            .map(|id| StoredItem {
                id: id.to_string(),
                reason: None,
            })
            .collect(),
    }
}

/// The seeds' candidates in turn (each one's first, then each one's second...), without
/// duplicates by id, ISRC or folded key, nor anything excluded; at most 30.
fn discovery(
    seeds: Vec<(String, Vec<Pick>)>,
    excluded: &HashSet<ItemId>,
    folded_excluded: &HashSet<String>,
) -> Vec<StoredItem> {
    let (mut ids, mut isrcs, mut keys) = (HashSet::new(), HashSet::new(), HashSet::new());
    let mut lists: Vec<_> = seeds
        .into_iter()
        .map(|(title, c)| (title, c.into_iter()))
        .collect();
    let mut out = Vec::new();
    while out.len() < DISCOVERY && !lists.is_empty() {
        lists.retain_mut(|(title, list)| {
            let Some(c) = list.next() else {
                return false;
            };
            let fresh = !excluded.contains(&c.id)
                && !folded_excluded.contains(&c.folded)
                && ids.insert(c.id)
                && c.isrc.is_none_or(|i| isrcs.insert(i))
                && keys.insert(c.folded);
            if fresh && out.len() < DISCOVERY {
                out.push(StoredItem {
                    id: c.id.to_string(),
                    reason: Some(title.clone()),
                });
            }
            true
        });
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cand(title: &str, artist: &str, isrc: Option<&str>) -> Pick {
        Pick {
            id: ItemId::new(),
            isrc: isrc.map(Into::into),
            folded: folded(title, artist),
        }
    }

    /// `n` candidates of distinct titles by `artist`.
    fn cands(artist: &str, n: usize) -> Vec<Pick> {
        (0..n)
            .map(|i| cand(&format!("{artist} {i}"), artist, None))
            .collect()
    }

    fn ids(c: &[Pick]) -> Vec<String> {
        c.iter().map(|c| c.id.to_string()).collect()
    }

    fn found(shelves: &[StoredShelf]) -> Vec<(String, String)> {
        shelves
            .iter()
            .find(|s| s.kind == ShelfKind::Discovery)
            .map(|s| {
                s.items
                    .iter()
                    .map(|i| (i.id.clone(), i.reason.clone().unwrap()))
                    .collect()
            })
            .unwrap_or_default()
    }

    fn kinds(shelves: &[StoredShelf]) -> Vec<ShelfKind> {
        shelves.iter().map(|s| s.kind).collect()
    }

    fn one() -> Vec<ItemId> {
        vec![ItemId::new()]
    }

    /// Every network input set; `n` top artists.
    fn full(n: usize) -> Inputs {
        Inputs {
            top_artists: (1..=n).map(|i| (ItemId::new(), format!("a{i}"))).collect(),
            mixes: one(),
            discovery: vec![("Halo".into(), cands("x", 1))],
            releases: one(),
            chart: one(),
            ..Inputs::default()
        }
    }

    #[test]
    fn discovery_round_robins_seeds_and_caps_at_30() {
        let (a, b, c) = (cands("a", 20), cands("b", 20), cands("c", 1));
        let mut want = vec![];
        for i in 0..20 {
            want.push((ids(&a)[i].clone(), "A".to_string()));
            want.push((ids(&b)[i].clone(), "B".to_string()));
            if i == 0 {
                want.push((ids(&c)[0].clone(), "C".to_string()));
            }
        }
        want.truncate(30);
        let inputs = Inputs {
            discovery: vec![("A".into(), a), ("B".into(), b), ("C".into(), c)],
            ..Inputs::default()
        };
        assert_eq!(found(&assemble(inputs, true)), want);
    }

    #[test]
    fn discovery_dedupes_by_folded_title_and_artist() {
        let a = vec![cand("Halo", "Beyoncé", Some("US1"))];
        let b = vec![cand("HALO!", "beyonce", Some("US2"))];
        let first = ids(&a)[0].clone();
        let inputs = Inputs {
            discovery: vec![("A".into(), a), ("B".into(), b)],
            ..Inputs::default()
        };
        assert_eq!(found(&assemble(inputs, true)), [(first, "A".into())]);
    }

    #[test]
    fn discovery_dedupes_by_isrc() {
        let a = vec![cand("X", "a", Some("US1"))];
        let mut b = vec![cand("Y", "b", Some("US1"))];
        // The same id from another seed too.
        b.push(Pick {
            id: a[0].id,
            isrc: None,
            folded: folded("Z", "c"),
        });
        let first = ids(&a)[0].clone();
        let inputs = Inputs {
            discovery: vec![("A".into(), a), ("B".into(), b)],
            ..Inputs::default()
        };
        assert_eq!(found(&assemble(inputs, true)), [(first, "A".into())]);
    }

    #[test]
    fn discovery_excludes_played_or_liked() {
        let list = vec![
            cand("Played", "a", None),
            cand("Liked", "a", None),
            cand("New", "a", None),
        ];
        let new = ids(&list)[2].clone();
        let inputs = Inputs {
            excluded: HashSet::from([list[0].id]),
            // The liked one under another id: same title and artist.
            folded_excluded: HashSet::from([folded("liked", "A")]),
            discovery: vec![("S".into(), list)],
            ..Inputs::default()
        };
        assert_eq!(found(&assemble(inputs, true)), [(new, "S".into())]);
    }

    #[test]
    fn shelves_follow_the_spec_order_and_end_last() {
        use ShelfKind::{BecauseYouListened as Byl, *};
        let shelves = assemble(full(7), true);
        assert_eq!(
            kinds(&shelves),
            [
                Shortcuts,
                Discovery,
                Mixes,
                Byl,
                NewReleases,
                Rediscover,
                Chart,
                Byl,
                Recent,
                Byl,
                Playlists,
                Byl,
                Downloads,
                Byl,
                Byl,
                Byl,
                End
            ]
        );
        let byl: Vec<_> = shelves
            .iter()
            .filter(|s| s.kind == Byl)
            .map(|s| (s.seed.as_deref().unwrap(), s.loaded, s.items.len()))
            .collect();
        let want: Vec<_> = (1..=7).map(|i| (format!("a{i}"), false, 0)).collect();
        let want: Vec<_> = want.iter().map(|(s, l, n)| (s.as_str(), *l, *n)).collect();
        assert_eq!(byl, want);
        assert!(shelves.iter().all(|s| s.kind != Byl || s.seed_id.is_some()));
        let network: Vec<_> = shelves
            .iter()
            .filter(|s| s.network)
            .map(|s| s.kind)
            .collect();
        assert_eq!(
            network,
            [
                Discovery,
                Mixes,
                Byl,
                NewReleases,
                Chart,
                Byl,
                Byl,
                Byl,
                Byl,
                Byl,
                Byl
            ]
        );
    }

    #[test]
    fn empty_network_shelves_are_omitted_local_ones_kept() {
        use ShelfKind::*;
        let local = [Shortcuts, Rediscover, Recent, Playlists, Downloads, End];
        assert_eq!(kinds(&assemble(Inputs::default(), true)), local);
        let inputs = Inputs {
            top_artists: vec![(ItemId::new(), "a1".into())],
            chart: one(),
            ..Inputs::default()
        };
        let shelves = assemble(inputs, true);
        assert_eq!(
            kinds(&shelves),
            [
                Shortcuts,
                BecauseYouListened,
                Rediscover,
                Chart,
                Recent,
                Playlists,
                Downloads,
                End
            ]
        );
        assert!(shelves.iter().all(|s| s.network || s.items.is_empty()));
    }

    #[test]
    fn the_first_because_shelf_takes_the_items_loaded() {
        let loaded = vec![StoredItem {
            id: ItemId::new().to_string(),
            reason: None,
        }];
        let want = loaded[0].id.clone();
        let inputs = Inputs {
            because: Some(loaded),
            ..full(2)
        };
        let byl: Vec<_> = assemble(inputs, true)
            .into_iter()
            .filter(|s| s.kind == ShelfKind::BecauseYouListened)
            .map(|s| {
                (
                    s.loaded,
                    s.items.into_iter().map(|i| i.id).collect::<Vec<_>>(),
                )
            })
            .collect();
        assert_eq!(byl, [(true, vec![want]), (false, vec![])]);
    }

    #[test]
    fn discover_off_has_only_local_shelves() {
        use ShelfKind::*;
        let shelves = assemble(full(3), false);
        assert_eq!(
            kinds(&shelves),
            [Shortcuts, Rediscover, Recent, Playlists, Downloads, End]
        );
        assert!(shelves.iter().all(|s| !s.network));
    }
}
