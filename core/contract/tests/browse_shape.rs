use contract::music::browse::{Category, CategoryPage, Release, Shelf};
use contract::music::entity::Entity;
use contract::types::{Album, Artist};

#[test]
fn browse_bindings_have_the_spec_shape() {
    let category = Category {
        id: "0".into(),
        title: "Top 50".into(),
        artwork: vec![],
        featured: true,
    };
    let artist = Artist {
        id: "1".into(),
        name: "A".into(),
        artwork: vec![],
    };
    let page = CategoryPage {
        title: category.title.clone(),
        shelves: vec![Shelf {
            title: "Artists".into(),
            items: vec![Entity::Artist(artist)],
        }],
        next: None,
    };
    let album = Album {
        id: "2".into(),
        title: "B".into(),
        artists: vec![],
        year: None,
        track_count: None,
        artwork: vec![],
    };
    let release = Release {
        album,
        date: "2026-10-23".into(),
    };
    assert!(category.featured);
    assert_eq!(page.shelves[0].items.len(), 1);
    assert_eq!(release.date, "2026-10-23");
}
