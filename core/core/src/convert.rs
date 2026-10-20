//! WIT records (plugin answers) → library `*Data`.

use plugin_host::types::{Album, Artist, ArtistRef, Image, Playlist, Track};

use crate::library::catalog::{self as lib, AlbumData, ArtistData, PlaylistData, TrackData};

fn images(list: Vec<Image>) -> Vec<lib::Image> {
    list.into_iter()
        .map(|i| lib::Image {
            url: i.url,
            width: i.width,
        })
        .collect()
}

fn artist_ref(a: ArtistRef) -> ArtistData {
    ArtistData {
        ext_id: a.id,
        name: a.name,
        artwork: vec![],
    }
}

pub(crate) fn track(t: Track) -> TrackData {
    TrackData {
        ext_id: t.id,
        title: t.title,
        artists: t.artists.into_iter().map(artist_ref).collect(),
        album: t.album.map(|a| (a.id, a.title)),
        duration_ms: t.duration_ms,
        isrc: t.isrc,
        explicit: t.explicit,
        artwork: images(t.artwork),
    }
}

pub(crate) fn album(a: Album) -> AlbumData {
    AlbumData {
        ext_id: a.id,
        title: a.title,
        artists: a.artists.into_iter().map(artist_ref).collect(),
        year: a.year,
        track_count: a.track_count,
        artwork: images(a.artwork),
    }
}

pub(crate) fn artist(a: Artist) -> ArtistData {
    ArtistData {
        ext_id: Some(a.id),
        name: a.name,
        artwork: images(a.artwork),
    }
}

pub(crate) fn playlist(p: Playlist) -> PlaylistData {
    PlaylistData {
        ext_id: p.id,
        title: p.title,
        owner: p.owner,
        description: p.description,
        track_count: p.track_count,
        artwork: images(p.artwork),
    }
}
