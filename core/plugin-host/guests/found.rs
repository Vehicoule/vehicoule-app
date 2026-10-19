// Shared by the search test components (`include!`): the output travels in the first track's title.
fn found(title: String) -> SearchResults {
    let track = Track {
        id: String::new(),
        title,
        artists: vec![],
        album: None,
        duration_ms: None,
        isrc: None,
        explicit: false,
        artwork: vec![],
    };
    SearchResults { tracks: vec![track], albums: vec![], artists: vec![], playlists: vec![], next: None }
}
