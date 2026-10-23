//! Playback: Rust decides, the Dart player executes `PlayerCommand`s and reports
//! `PlayerEvent`s (play, pause and seek go straight to the Dart player).

use crate::api::forward;
use crate::app::app;
use crate::error::CoreError;
use crate::events::{Notice, NowPlaying, QueueView};
use crate::frb_generated::StreamSink;
pub use crate::player::QueueOp;
use crate::player::{self, Candidate, PlayerCommand, PlayerEvent};
use crate::queue::PlayContext;

/// Replaces the queue with `items` and plays `items[start]`.
pub async fn play(
    items: Vec<String>,
    start: u32,
    context: Option<PlayContext>,
) -> Result<(), CoreError> {
    player::play(items, start as usize, context).await
}

pub async fn player_event(e: PlayerEvent) {
    player::on_event(e).await
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

pub async fn fix_match(id: String) -> Result<Vec<Candidate>, CoreError> {
    player::fix_match(&id).await
}

pub async fn choose_match(id: String, candidate_id: String) -> Result<(), CoreError> {
    player::choose_match(&id, &candidate_id).await
}

pub fn player_commands(sink: StreamSink<PlayerCommand>) {
    forward(&app().events.commands, move |v| sink.add(v).is_ok());
}

pub fn queue_states(sink: StreamSink<QueueView>) {
    forward(&app().events.queue, move |v| sink.add(v).is_ok());
}

pub fn now_playing(sink: StreamSink<NowPlaying>) {
    forward(&app().events.now_playing, move |v| sink.add(v).is_ok());
}

pub fn notices(sink: StreamSink<Notice>) {
    forward(&app().events.notices, move |v| sink.add(v).is_ok());
}
