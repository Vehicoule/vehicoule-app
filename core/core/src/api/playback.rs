//! Playback: Rust decides, the Dart player executes `PlayerCommand`s and reports
//! `PlayerEvent`s (play, pause and seek go straight to the Dart player).

use std::sync::PoisonError;

use crate::api::forward;
use crate::app::app;
use crate::error::CoreError;
use crate::events::{Notice, NowPlaying, QueueView};
use crate::frb_generated::StreamSink;
pub use crate::player::QueueOp;
use crate::player::{self, Candidate, PlayerCommand, PlayerEvent, SleepTimer};
use crate::queue::PlayContext;

/// Replaces the queue with `items` and plays `items[start]`.
pub async fn play(
    items: Vec<String>,
    start: u32,
    context: Option<PlayContext>,
) -> Result<(), CoreError> {
    player::play(items, start as usize, context).await
}

/// Sync and fire-and-forget: queued for the player actor in call order, never blocks the UI.
#[flutter_rust_bridge::frb(sync)]
pub fn player_event(e: PlayerEvent) {
    player::send_event(e)
}

pub async fn skip_next() {
    player::skip_next().await
}

/// Past 3 s into the track (`position_ms`), restarts it; else goes back one.
pub async fn previous(position_ms: u64) {
    player::previous(position_ms).await
}

pub async fn queue_op(op: QueueOp) -> Result<(), CoreError> {
    player::edit(op).await
}

/// Stops and empties the queue (the mini-player hides); `undo_stop` brings it back.
pub async fn stop() {
    player::stop().await
}

/// The queue `stop` emptied, playing where it was; forgotten by any other queue change.
pub async fn undo_stop() {
    player::undo_stop().await
}

/// At its end the player pauses, the volume faded over 5 s; `EndOfTrack`: the next entry is
/// loaded paused. A restart or `stop` cancels it; `NowPlaying.sleep` tells it.
pub async fn set_sleep_timer(timer: SleepTimer) -> Result<(), CoreError> {
    player::set_sleep_timer(timer).await
}

pub async fn fix_match(id: String) -> Result<Vec<Candidate>, CoreError> {
    player::fix_match(&id).await
}

pub async fn choose_match(id: String, candidate_id: String) -> Result<(), CoreError> {
    player::choose_match(&id, &candidate_id).await
}

pub fn player_commands(sink: StreamSink<PlayerCommand>) {
    forward(commands_rx(), move |v| sink.add(v).is_ok());
}

/// The first call gets the receiver `init_app` made: whatever `start` sent before is there.
pub(crate) fn commands_rx() -> tokio::sync::broadcast::Receiver<PlayerCommand> {
    let events = &app().events;
    let first = events
        .first_commands
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .take();
    first.unwrap_or_else(|| events.commands.subscribe())
}

/// The current state first, then each change (`queue_states` and `now_playing`).
pub fn queue_states(sink: StreamSink<QueueView>) {
    forward(app().events.queue.subscribe(), move |v| sink.add(v).is_ok());
    player::send_state();
}

pub fn now_playing(sink: StreamSink<NowPlaying>) {
    forward(app().events.now_playing.subscribe(), move |v| {
        sink.add(v).is_ok()
    });
    player::send_state();
}

pub fn notices(sink: StreamSink<Notice>) {
    forward(app().events.notices.subscribe(), move |v| {
        sink.add(v).is_ok()
    });
}
