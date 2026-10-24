//! Broadcasts to Dart (each one subscribed by a `StreamSink` in api/). A slow subscriber lags
//! and loses old messages; the next one carries the current state anyway.

use std::sync::Mutex;

use tokio::sync::broadcast;

use crate::catalog::TrackView;
use crate::downloads::DownloadProgress;
use crate::error::CoreError;
use crate::player::{PlayerCommand, SleepState};
use crate::queue::{PlayContext, Repeat};
use crate::updates::UpdateInfo;

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
    /// The plugin id that resolved it, or `download`; `None` while nothing is loaded.
    pub source: Option<String>,
    pub mime: Option<String>,
    /// The running sleep timer.
    pub sleep: Option<SleepState>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Notice {
    /// `title` is for the UI only: never logged.
    Skipped {
        title: String,
        reason: CoreError,
    },
    /// The one UI signal for an update (background or manual check).
    UpdateAvailable(UpdateInfo),
    Error(CoreError),
}

#[derive(Debug, Clone, PartialEq)]
pub enum LibraryChanged {
    Likes,
    Playlists,
    Playlist {
        id: String,
    },
    Downloads,
    History,
    Plugins,
    /// The home feed was rebuilt: read it again from its first page.
    Home,
}

pub(crate) struct Events {
    pub commands: broadcast::Sender<PlayerCommand>,
    /// Subscribed with `commands`, for the first `player_commands`: a `PlayerCommand` is
    /// never sent again, and the bridge may run `start` before that subscription.
    pub first_commands: Mutex<Option<broadcast::Receiver<PlayerCommand>>>,
    pub queue: broadcast::Sender<QueueView>,
    pub now_playing: broadcast::Sender<NowPlaying>,
    pub library: broadcast::Sender<LibraryChanged>,
    pub notices: broadcast::Sender<Notice>,
    pub downloads: broadcast::Sender<DownloadProgress>,
}

impl Events {
    pub fn new() -> Events {
        const CAP: usize = 256;
        let (commands, first) = broadcast::channel(CAP);
        Events {
            commands,
            first_commands: Mutex::new(Some(first)),
            queue: broadcast::channel(CAP).0,
            now_playing: broadcast::channel(CAP).0,
            library: broadcast::channel(CAP).0,
            notices: broadcast::channel(CAP).0,
            downloads: broadcast::channel(CAP).0,
        }
    }
}
