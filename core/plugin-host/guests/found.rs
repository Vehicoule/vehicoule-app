// Shared by the search test components (`include!`): the output travels in the tracks' titles.
fn track(title: String) -> Track {
    Track {
        id: String::new(),
        title,
        artists: vec![],
        album: None,
        duration_ms: None,
        isrc: None,
        explicit: false,
        artwork: vec![],
    }
}

fn found(title: String) -> SearchResults {
    SearchResults { tracks: vec![track(title)], albums: vec![], artists: vec![], playlists: vec![], next: None }
}
