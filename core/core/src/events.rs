//! Broadcasts to Dart (each one subscribed by a `StreamSink` in api/). A slow subscriber lags
//! and loses old messages; the next one carries the current state anyway.

use tokio::sync::broadcast;

use crate::catalog::TrackView;
use crate::downloads::DownloadProgress;
use crate::error::CoreError;
use crate::player::PlayerCommand;
use crate::queue::{PlayContext, Repeat};

#[derive(Debug, Clone, PartialEq)]
pub struct QueueView {
    pub current_entry: Option<String>,
    /// `None` when nothing is current, or its track is missing from the catalogue.
    pub current: Option<TrackView>,
    /// Entries whose track is missing from the catalogue are left out.
    pub upcoming: Vec<QueueItemView>,
    pub index: u32,
    pub shuffle: bool,
    pub repeat: Repeat,
    pub context: Option<PlayContext>,
}

/// One queue entry: its id is what `QueueOp::Remove`, `Move` and `JumpTo` take.
#[derive(Debug, Clone, PartialEq)]
pub struct QueueItemView {
    pub entry: String,
    pub track: TrackView,
    pub from_radio: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct NowPlaying {
    pub track: Option<TrackView>,
    pub artwork_path: Option<String>,
    pub duration_ms: Option<u64>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Notice {
    /// `title` is for the UI only: never logged.
    Skipped {
        title: String,
        reason: CoreError,
    },
    UpdateAvailable {
        version: String,
    },
    Error(CoreError),
}

#[derive(Debug, Clone, PartialEq)]
pub enum LibraryChanged {
    Likes,
    Playlists,
    Playlist { id: String },
    Downloads,
    History,
    Plugins,
}

pub(crate) struct Events {
    pub commands: broadcast::Sender<PlayerCommand>,
    pub queue: broadcast::Sender<QueueView>,
    pub now_playing: broadcast::Sender<NowPlaying>,
    pub library: broadcast::Sender<LibraryChanged>,
    pub notices: broadcast::Sender<Notice>,
    pub downloads: broadcast::Sender<DownloadProgress>,
}

impl Events {
    pub fn new() -> Events {
        const CAP: usize = 256;
        Events {
            commands: broadcast::channel(CAP).0,
            queue: broadcast::channel(CAP).0,
            now_playing: broadcast::channel(CAP).0,
            library: broadcast::channel(CAP).0,
            notices: broadcast::channel(CAP).0,
            downloads: broadcast::channel(CAP).0,
        }
    }
}
