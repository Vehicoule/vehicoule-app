// Helpers, not `#[test]` fns: clippy's `allow-unwrap-in-tests` does not reach them.
#![allow(clippy::unwrap_used)]

mod common;

use common::{TestHost, guest, manifest, query};
use plugin_host::music::browse::{Category, CategoryPage, Release, Shelf};
use plugin_host::music::entity::Entity;
use plugin_host::types::{Album, Image, TrackQuery};
use plugin_host::{CallError, Capability, Limits, Plugin, parse_manifest};

fn load(t: &TestHost, name: &str, contract: &str) -> Plugin {
    t.host
        .load(&manifest(&name.replace('_', "-"), contract), &guest(name))
        .unwrap()
}

/// Contract records derive `Debug`, not `PartialEq`.
fn same<T: std::fmt::Debug>(got: T, want: T) {
    assert_eq!(format!("{got:?}"), format!("{want:?}"));
}

fn kept() -> Vec<Image> {
    vec![Image {
        url: "http://api.test/a.jpg".into(),
        width: None,
        height: None,
    }]
}

fn album(id: &str) -> Album {
    Album {
        id: id.into(),
        title: String::new(),
        artists: vec![],
        year: None,
        track_count: None,
        artwork: kept(),
    }
}

#[tokio::test]
async fn plugin_1_0_loads_without_browse() {
    let t = TestHost::new(Limits::default());
    let p = load(&t, "music_1_0", "1.0");
    assert_eq!(p.capabilities(), [Capability::Search, Capability::Lyrics]);
    assert_eq!(
        t.host.search(&p, query("hello")).await.unwrap().tracks[0].title,
        "hello"
    );
    let track = TrackQuery {
        id: None,
        title: "x".into(),
        artists: vec![],
        album: None,
        duration_ms: None,
        isrc: None,
    };
    assert_eq!(
        t.host.lyrics(&p, track).await.unwrap().plain.as_deref(),
        Some("x")
    );
    assert_eq!(
        t.host.browse_categories(&p, "FR").await.unwrap_err(),
        CallError::Unsupported
    );
}

#[tokio::test]
async fn browse_only_guest_exposes_browse() {
    let t = TestHost::new(Limits::default());
    let p = load(&t, "browse_only", "1.1");
    assert_eq!(p.capabilities(), [Capability::Browse]);
    assert_eq!(
        t.host.search(&p, query("")).await.unwrap_err(),
        CallError::Unsupported
    );

    let categories = t.host.browse_categories(&p, "FR").await.unwrap();
    same(
        categories,
        vec![Category {
            id: "c".into(),
            title: "FR".into(),
            artwork: kept(),
            featured: true,
        }],
    );

    let page = t
        .host
        .browse_category(&p, "rock", "FR", Some("2".into()))
        .await
        .unwrap();
    let shelf = Shelf {
        title: "FR".into(),
        items: vec![Entity::Album(album("rock"))],
    };
    same(
        page,
        CategoryPage {
            title: "rock".into(),
            shelves: vec![shelf],
            next: Some("2".into()),
        },
    );

    let releases = t
        .host
        .browse_releases(&p, "artist-1", "2026-10-23")
        .await
        .unwrap();
    same(
        releases,
        vec![Release {
            album: album("artist-1"),
            date: "2026-10-23".into(),
        }],
    );
    let caps: Vec<_> = t.reports().iter().map(|r| r.capability).collect();
    assert_eq!(
        caps,
        [
            Capability::Search,
            Capability::Browse,
            Capability::Browse,
            Capability::Browse
        ]
    );
}

#[test]
fn contract_1_1_is_accepted_2_0_is_not() {
    let parse = |contract: &str| parse_manifest(&manifest("xx", contract));
    assert!(parse("1.0").is_ok());
    assert!(parse("1.1").is_ok());
    assert!(parse("1.2").is_err());
    assert!(parse("2.0").is_err());
}

#[tokio::test]
async fn browse_artwork_outside_allowlist_is_dropped() {
    let t = TestHost::new(Limits::default());
    let p = load(&t, "browse_only", "1.1");
    let urls = |images: &[Image]| images.iter().map(|i| i.url.clone()).collect::<Vec<_>>();
    let ok = ["http://api.test/a.jpg"];

    assert_eq!(
        urls(&t.host.browse_categories(&p, "FR").await.unwrap()[0].artwork),
        ok
    );
    let page = t
        .host
        .browse_category(&p, "rock", "FR", None)
        .await
        .unwrap();
    let Entity::Album(a) = &page.shelves[0].items[0] else {
        panic!("expected an album")
    };
    assert_eq!(urls(&a.artwork), ok);
    assert_eq!(
        urls(
            &t.host.browse_releases(&p, "a", "FR").await.unwrap()[0]
                .album
                .artwork
        ),
        ok
    );
}
