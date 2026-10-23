//! Playback decided in Rust, executed by the Dart player. One actor (a tokio task fed by an
//! mpsc channel) owns the queue and the preload timer; the functions below send it a message
//! and return once it has been handled, so there is no shared lock on the queue.
//!
//! The Dart player's contract (plan 5, task 3): it holds a current track and at most one
//! next. `Play` replaces both; `EnqueueNext`/`ReplaceNext` replace the held next (or set it);
//! `ClearNext` drops it. It starts the held next by itself at the end of the current one and
//! reports `TrackStarted` for it. `TrackStarted` = loaded (paused loads too), `Resumed` =
//! sound running, `Paused` = stopped: "playing" comes from those (and `Ended`/`Error`) only.

use std::collections::{HashMap, HashSet};
use std::sync::{Mutex, PoisonError};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use plugin_host::music::resolve::{self as wit, Quality, ResolveRequest};
use plugin_host::types::TrackQuery;
use plugin_host::{CallError, Capability, Plugin};
use tokio::sync::{mpsc, oneshot};
use tokio::time::Instant;

use crate::app::app;
use crate::catalog::{TrackView, parse_id, track_view};
use crate::convert;
use crate::error::CoreError;
use crate::events::{LibraryChanged, Notice, NowPlaying, QueueItemView, QueueView};
use crate::library::catalog::{self as lib, TrackRow};
use crate::library::downloads::{self, DownloadState};
use crate::library::refs::{self, ExtRef};
use crate::library::{ItemId, Kind, Page, plays, queue as saved, settings};
use crate::logs;
use crate::queue::{EntryId, PlayContext, QueueState, Repeat};
use crate::router;

/// Ahead of the end of the current track, the next one is resolved and handed to the player.
pub const PRELOAD_LEAD_MS: u64 = 20_000;
/// Unplayable next tracks skipped per attempt (offline skips cost no call: not counted); also
/// current tracks failing in a row (decode errors, the 403 ladder exhausted) before it stops.
const MAX_SKIPS: usize = 3;
const RADIO_LIMIT: u32 = 25;
/// Radio tracks among the last plays are left out.
const RADIO_EXCLUDE: u32 = 50;
// ponytail: the view lists the first 500 upcoming tracks; page it if longer queues matter
const VIEW_UPCOMING: usize = 500;
const ARTWORK_SIZE: u32 = 600;

/// An http(s) URL or a file path.
#[derive(Debug, Clone, PartialEq)]
pub struct Source {
    pub uri: String,
    pub headers: Vec<(String, String)>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum PlayerCommand {
    Play {
        entry: String,
        source: Source,
        position_ms: u64,
        autoplay: bool,
        gain_db: f32,
    },
    EnqueueNext {
        entry: String,
        source: Source,
        gain_db: f32,
    },
    ReplaceNext {
        entry: String,
        source: Source,
        gain_db: f32,
    },
    ClearNext,
    Stop,
}

#[derive(Debug, Clone, PartialEq)]
pub enum PlayerEvent {
    TrackStarted {
        entry: String,
    },
    Duration {
        entry: String,
        ms: u64,
    },
    Position {
        entry: String,
        ms: u64,
    },
    Paused {
        entry: String,
        ms: u64,
    },
    Resumed {
        entry: String,
    },
    Seeked {
        entry: String,
        ms: u64,
    },
    Ended {
        entry: String,
    },
    /// `message` is never used: it may hold a URL. `position_ms`: where it stopped (a 403
    /// resumes there).
    Error {
        entry: String,
        kind: PlayerErrorKind,
        message: String,
        position_ms: u64,
    },
}

/// `Forbidden` = HTTP 403.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PlayerErrorKind {
    Forbidden,
    Network,
    Decode,
    Other,
}

#[derive(Debug, Clone, PartialEq)]
pub enum QueueOp {
    EnqueueNext(Vec<String>),
    EnqueueLast(Vec<String>),
    Remove(String),
    /// Right after `after` (`None`: right after the current entry).
    Move {
        entry: String,
        after: Option<String>,
    },
    Shuffle(bool),
    Repeat(Repeat),
    JumpTo(String),
}

#[derive(Debug, Clone, PartialEq)]
pub struct Candidate {
    pub id: String,
    pub title: String,
    pub artists: Vec<String>,
    pub duration_ms: Option<u32>,
    pub score: f32,
}

/// Where an item plays from.
pub(crate) struct Resolution {
    /// The plugin that resolved it; `None` for a finished download.
    pub plugin: Option<String>,
    /// That plugin's id for the recording.
    pub id: Option<String>,
    pub source: Source,
    pub mime: Option<String>,
    pub loudness_db: Option<f32>,
    /// Other plausible matches, for `fix_match`.
    pub candidates: Vec<Candidate>,
}

// ---------------------------------------------------------------------------------------
// Public entry points: one message each, answered by the actor.

pub(crate) async fn play(
    items: Vec<String>,
    start: usize,
    context: Option<PlayContext>,
) -> Result<(), CoreError> {
    ask(|r| Msg::Play(items, start, context, r))
        .await
        .unwrap_or_else(stopped)
}

/// `send_event`, returning once handled: for tests.
#[cfg(test)]
pub(crate) async fn on_event(e: PlayerEvent) {
    ask(|r| Msg::Event(e, r)).await;
}

/// `on_event` without waiting: queued in call order, never blocks (the bridge's sync call).
pub(crate) fn send_event(e: PlayerEvent) {
    let _ = actor().send(Msg::Event(e, oneshot::channel().0));
}

/// The current track and the queue view read again (a like, a finished download).
pub(crate) fn refresh() {
    let _ = actor().send(Msg::Refresh);
}

pub(crate) async fn skip_next() {
    ask(Msg::SkipNext).await;
}

pub(crate) async fn previous(position_ms: u64) {
    ask(|r| Msg::Previous(position_ms, r)).await;
}

pub(crate) async fn edit(op: QueueOp) -> Result<(), CoreError> {
    ask(|r| Msg::Edit(op, r)).await.unwrap_or_else(stopped)
}

/// The candidates of the item's last resolution; none known (a ref already stored), a
/// `resolve` that skips the current match finds some.
pub(crate) async fn fix_match(item: &str) -> Result<Vec<Candidate>, CoreError> {
    let item = parse_id(item)?;
    ask(|r| Msg::FixMatch(item, r))
        .await
        .unwrap_or_else(stopped)
}

/// Pins the candidate as the item's recording at that plugin; the current track replays
/// with it, where it was.
pub(crate) async fn choose_match(item: &str, candidate_id: &str) -> Result<(), CoreError> {
    let (item, candidate) = (parse_id(item)?, candidate_id.to_string());
    ask(|r| Msg::ChooseMatch(item, candidate, r))
        .await
        .unwrap_or_else(stopped)
}

/// At startup: the saved queue, its current track loaded paused at the saved position.
pub(crate) async fn restore() {
    ask(Msg::Restore).await;
}

/// Stops and empties the queue (saved empty); the previous one is kept for `undo_stop`.
pub(crate) async fn stop() {
    ask(Msg::Stop).await;
}

/// The queue `stop` emptied, playing again where it was. Any other queue change or `play`
/// forgets it; nothing to undo, nothing happens.
pub(crate) async fn undo_stop() {
    ask(Msg::UndoStop).await;
}

/// The queue and now-playing, broadcast again: for a new subscriber.
pub(crate) fn send_state() {
    let _ = actor().send(Msg::SendState);
}

/// The app's connectivity. A preloaded next track is chosen again (offline: the next
/// downloaded one).
pub(crate) fn set_online(online: bool) {
    app().set_online(online);
    let _ = actor().send(Msg::Online);
}

/// Normalisation only turns down (never clips), by at most 15 dB.
pub(crate) fn gain_db(loudness_db: f32) -> f32 {
    (-loudness_db).clamp(-15.0, 0.0)
}

/// The routed `resolve` (online only), the resolved id recorded as the item's ref at that
/// plugin. Downloads use it too (task 6), and again when a URL expires mid-download.
pub(crate) async fn resolve(item: ItemId, tried: &[String]) -> Result<Resolution, CoreError> {
    resolve_at(item, tried, None).await
}

/// `resolve` at quality `high`, whatever the setting: downloads.
pub(crate) async fn resolve_for_download(item: ItemId) -> Result<Resolution, CoreError> {
    resolve_at(item, &[], Some(Quality::High)).await
}

/// `quality`: the device setting when `None`.
async fn resolve_at(
    item: ItemId,
    tried: &[String],
    quality: Option<Quality>,
) -> Result<Resolution, CoreError> {
    let (plugin, r) = call_resolve(item, tried, quality).await?;
    let (p, id) = (plugin.id().to_string(), r.id.clone());
    app()
        .db
        .write(move |tx| refs::record(tx, item, &p, &id))
        .await?;
    Ok(Resolution {
        plugin: Some(plugin.id().to_string()),
        id: Some(r.id),
        source: Source {
            uri: r.source.url,
            headers: r.source.headers,
        },
        mime: Some(r.source.mime),
        loudness_db: r.source.loudness_db,
        candidates: r.candidates.into_iter().map(candidate).collect(),
    })
}

// ---------------------------------------------------------------------------------------
// Resolution and settings.

fn stopped<T>() -> Result<T, CoreError> {
    Err(CoreError::Internal("player stopped".into()))
}

fn candidate(c: wit::Candidate) -> Candidate {
    Candidate {
        id: c.id,
        title: c.title,
        artists: c.artists,
        duration_ms: c.duration_ms,
        score: c.score,
    }
}

pub(crate) async fn track_and_refs(
    item: ItemId,
) -> Result<(TrackRow, Vec<(String, ExtRef)>), CoreError> {
    let (track, refs) = app()
        .db
        .read(move |c| Ok((lib::track(c, item)?, refs::all(c, item)?)))
        .await?;
    Ok((track.ok_or(CoreError::NotFound)?, refs))
}

/// What `plugin` is told about the track: its own id for it (pinned first) when it has one.
pub(crate) fn query(t: &TrackRow, refs: &[(String, ExtRef)], plugin: &str) -> TrackQuery {
    TrackQuery {
        id: refs
            .iter()
            .find(|(p, _)| p == plugin)
            .map(|(_, r)| r.external_id.clone()),
        title: t.title.clone(),
        artists: t.artists.iter().map(|(_, name)| name.clone()).collect(),
        album: t.album.as_ref().map(|(_, title)| title.clone()),
        duration_ms: t.duration_ms,
        isrc: t.isrc.clone(),
    }
}

async fn call_resolve(
    item: ItemId,
    tried: &[String],
    quality: Option<Quality>,
) -> Result<(Plugin, wit::Resolved), CoreError> {
    let app = app();
    if !app.is_online() {
        return Err(CoreError::Offline);
    }
    let (track, refs) = track_and_refs(item).await?;
    let quality = match quality {
        Some(q) => q,
        None => match setting("quality", false).await.as_deref() {
            Some("low") => Quality::Low,
            Some("high") => Quality::High,
            _ => Quality::Normal,
        },
    };
    let (plugin, resolved) = router::first_ok(Capability::Resolve, |p| {
        let req = ResolveRequest {
            track: query(&track, &refs, p.id()),
            quality,
            region: app.cfg.region.clone(),
            tried: tried.to_vec(),
        };
        async move { app.plugins.host().resolve(&p, req).await }
    })
    .await?;
    // plugin-host checks it already; the player's fetch must pass the same policy.
    if app
        .plugins
        .host()
        .check_url(&plugin, &resolved.source.url)
        .is_err()
    {
        return Err(CoreError::Internal("stream url refused".into()));
    }
    Ok((plugin, resolved))
}

/// A finished download, else the network.
async fn source_for(item: ItemId) -> Result<Resolution, CoreError> {
    let row = app().db.read(move |c| downloads::get(c, item)).await?;
    if let Some(row) = row
        && row.state == DownloadState::Done
        && let Some(path) = row.path
    {
        return Ok(Resolution {
            plugin: None,
            id: None,
            source: Source {
                uri: path,
                headers: vec![],
            },
            mime: row.mime,
            loudness_db: row.loudness_db,
            candidates: vec![],
        });
    }
    resolve(item, &[]).await
}

/// `quality`, `normalize_volume` on this device; `radio` shared. A read error counts as unset.
async fn setting(key: &'static str, shared: bool) -> Option<String> {
    let v = app()
        .db
        .read(move |c| match shared {
            true => settings::shared_get(c, key),
            false => settings::device_get(c, key),
        })
        .await;
    v.unwrap_or_else(|e| {
        logs::push("error", "player", &e.to_string());
        None
    })
}

/// On unless set to `false`.
async fn enabled(key: &'static str, shared: bool) -> bool {
    setting(key, shared).await.as_deref() != Some("false")
}

async fn gain_for(res: &Resolution) -> f32 {
    match res.loudness_db.filter(|l| l.is_finite()) {
        Some(l) if enabled("normalize_volume", false).await => gain_db(l),
        _ => 0.0,
    }
}

/// A radio seeded by `seed`: tracks stored in the catalogue, minus the last plays.
async fn radio(seed: ItemId) -> Result<Vec<String>, CoreError> {
    let app = app();
    let (track, refs) = track_and_refs(seed).await?;
    let (plugin, found) = router::first_ok(Capability::Radio, |p| {
        let seed = query(&track, &refs, p.id());
        async move {
            let tracks = app
                .plugins
                .host()
                .radio(&p, seed, &app.cfg.region, RADIO_LIMIT)
                .await?;
            if tracks.is_empty() {
                Err(CallError::NotFound)
            } else {
                Ok(tracks)
            }
        }
    })
    .await?;
    let p = plugin.id().to_string();
    let ids = app
        .db
        .write(move |tx| {
            let recent = Page {
                offset: 0,
                limit: RADIO_EXCLUDE,
            };
            let recent = plays::recent_items(&tx.tx, Kind::Track, recent)?;
            let mut out = Vec::new();
            for t in found {
                let id = lib::upsert_track(tx, &p, &convert::track(t))?;
                if !recent.contains(&id) && !out.contains(&id) {
                    out.push(id);
                }
            }
            Ok(out)
        })
        .await?;
    Ok(ids.into_iter().map(|i| i.to_string()).collect())
}

fn seed() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_nanos() as u64)
}

fn entry_id(s: &str) -> Result<EntryId, CoreError> {
    uuid::Uuid::parse_str(s)
        .map(EntryId)
        .map_err(|_| CoreError::Internal("malformed entry id".into()))
}

/// What plays after the current entry, in order: `Repeat::All` wraps around (ending on the
/// current one); with `honor_one`, `Repeat::One` repeats the current one. Its head is `next()`.
fn following(q: &QueueState, honor_one: bool) -> Vec<EntryId> {
    let n = q.order.len();
    let positions: Vec<usize> = if honor_one && q.repeat == Repeat::One && q.index < n {
        vec![q.index]
    } else {
        let mut v: Vec<usize> = (q.index + 1..n).collect();
        if q.repeat == Repeat::All && n > 0 {
            v.extend(0..=q.index.min(n - 1));
        }
        v
    };
    positions
        .into_iter()
        .map(|p| q.entries[q.order[p]].id)
        .collect()
}

// ---------------------------------------------------------------------------------------
// The actor.

type Reply<T> = oneshot::Sender<T>;

enum Msg {
    Play(
        Vec<String>,
        usize,
        Option<PlayContext>,
        Reply<Result<(), CoreError>>,
    ),
    Event(PlayerEvent, Reply<()>),
    SkipNext(Reply<()>),
    Previous(u64, Reply<()>),
    Edit(QueueOp, Reply<Result<(), CoreError>>),
    FixMatch(ItemId, Reply<Result<Vec<Candidate>, CoreError>>),
    ChooseMatch(ItemId, String, Reply<Result<(), CoreError>>),
    Restore(Reply<()>),
    Stop(Reply<()>),
    UndoStop(Reply<()>),
    SendState,
    Refresh,
    Online,
    Artwork(EntryId, String),
}

static ACTOR: Mutex<Option<mpsc::UnboundedSender<Msg>>> = Mutex::new(None);

/// The running actor; started on first use (again if it ever stopped).
fn actor() -> mpsc::UnboundedSender<Msg> {
    let mut slot = ACTOR.lock().unwrap_or_else(PoisonError::into_inner);
    if let Some(tx) = slot.as_ref().filter(|tx| !tx.is_closed()) {
        return tx.clone();
    }
    let (tx, rx) = mpsc::unbounded_channel();
    // Tests: on the test's own runtime (and paused clock); it ends with the test.
    #[cfg(test)]
    tokio::spawn(run(rx));
    #[cfg(not(test))]
    app().rt.spawn(run(rx));
    *slot = Some(tx.clone());
    tx
}

/// A fresh actor on next use: an app restart, for tests.
#[cfg(test)]
pub(crate) fn reset() {
    *ACTOR.lock().unwrap_or_else(PoisonError::into_inner) = None;
}

async fn ask<T>(msg: impl FnOnce(Reply<T>) -> Msg) -> Option<T> {
    let (tx, rx) = oneshot::channel();
    actor().send(msg(tx)).ok()?;
    rx.await.ok()
}

async fn run(mut rx: mpsc::UnboundedReceiver<Msg>) {
    let mut p = Player::new();
    loop {
        let msg = match p.deadline {
            Some(d) => match tokio::time::timeout_at(d, rx.recv()).await {
                Ok(msg) => msg,
                Err(_) => {
                    p.preload().await;
                    continue;
                }
            },
            None => rx.recv().await,
        };
        let Some(msg) = msg else { break };
        p.handle(msg).await;
    }
}

/// What the player was handed for an entry.
struct Loaded {
    entry: EntryId,
    item: ItemId,
    res: Resolution,
    gain_db: f32,
    /// Expired-URL recovery: resolutions so far, and the ids to skip.
    attempts: u8,
    tried: Vec<String>,
    /// Positions reported since it was loaded: after 2, `attempts` starts over.
    positions: u8,
}

struct Player {
    q: QueueState,
    /// What the Dart player plays, and holds as next (`None`: not known, e.g. after a
    /// `TrackStarted` that crossed a command).
    current: Option<Loaded>,
    next: Option<Loaded>,
    /// The player may hold a next track: the preload replaces it rather than enqueue.
    held: bool,
    /// Entries given up on while the current track plays: the preload passes them.
    given_up: HashSet<EntryId>,
    /// Offline skips already told, until back online.
    offline_told: HashSet<EntryId>,
    restored: bool,
    /// The preload ran for the current track, when `next()` was `preload_for`.
    preloaded: bool,
    preload_for: Option<EntryId>,
    deadline: Option<Instant>,
    playing: bool,
    /// The user's intent: the last `Play`'s autoplay, then `Resumed`/`Paused`. A 403 resumes
    /// with it.
    wants_play: bool,
    /// Current tracks that failed without playing (decode, 403 ladder), since the last that
    /// played or the last user action: at `MAX_SKIPS` it stops.
    failed_in_row: usize,
    /// Last position reported, and when.
    pos_ms: u64,
    pos_at: Instant,
    /// Reported by the player; else the catalogue's.
    duration_ms: Option<u64>,
    track: Option<TrackView>,
    artwork: Option<String>,
    play: Option<uuid::Uuid>,
    listened_ms: u64,
    /// A `Play` that resumes this entry (expired URL, restore, new match): its `TrackStarted`
    /// keeps the position and the open play.
    resume: Option<EntryId>,
    /// Per item: the plugin and candidates of its last resolution.
    candidates: HashMap<ItemId, (String, Vec<Candidate>)>,
    /// The queue `stop` emptied, until another queue change.
    undo: Option<QueueState>,
}

fn send(cmd: PlayerCommand) {
    let _ = app().events.commands.send(cmd);
}

impl Player {
    fn new() -> Player {
        Player {
            q: QueueState::play(vec![], 0, None, false, 0),
            current: None,
            next: None,
            held: false,
            given_up: HashSet::new(),
            offline_told: HashSet::new(),
            restored: false,
            preloaded: false,
            preload_for: None,
            deadline: None,
            playing: false,
            wants_play: false,
            failed_in_row: 0,
            pos_ms: 0,
            pos_at: Instant::now(),
            duration_ms: None,
            track: None,
            artwork: None,
            play: None,
            listened_ms: 0,
            resume: None,
            candidates: HashMap::new(),
            undo: None,
        }
    }

    async fn handle(&mut self, msg: Msg) {
        // Only what leaves the queue alone keeps the undo of a stop.
        if !matches!(
            msg,
            Msg::Event(..)
                | Msg::FixMatch(..)
                | Msg::UndoStop(_)
                | Msg::SendState
                | Msg::Refresh
                | Msg::Online
                | Msg::Artwork(..)
        ) {
            self.undo = None;
        }
        // The user acts: earlier failures no longer count.
        if matches!(
            msg,
            Msg::Play(..)
                | Msg::SkipNext(_)
                | Msg::Previous(..)
                | Msg::UndoStop(_)
                | Msg::ChooseMatch(..)
        ) {
            self.failed_in_row = 0;
        }
        match msg {
            Msg::Play(items, start, context, r) => {
                let _ = r.send(self.play(items, start, context).await);
            }
            Msg::Event(e, r) => {
                self.event(e).await;
                let _ = r.send(());
            }
            Msg::SkipNext(r) => {
                let entries = self.following_or_radio(false).await;
                let _ = self.start(entries, 0, true).await;
                let _ = r.send(());
            }
            Msg::Previous(position_ms, r) => {
                self.q.position_ms = position_ms;
                if let Some(e) = self.q.previous().map(|e| e.id) {
                    let _ = self.start(vec![e], 0, true).await;
                }
                let _ = r.send(());
            }
            Msg::Edit(op, r) => {
                let _ = r.send(self.edit(op).await);
            }
            Msg::FixMatch(item, r) => {
                let _ = r.send(self.fix_match(item).await);
            }
            Msg::ChooseMatch(item, candidate, r) => {
                let _ = r.send(self.choose_match(item, candidate).await);
            }
            Msg::Restore(r) => {
                self.restore().await;
                let _ = r.send(());
            }
            Msg::Stop(r) => {
                self.stop_queue().await;
                let _ = r.send(());
            }
            Msg::UndoStop(r) => {
                self.undo_stop().await;
                let _ = r.send(());
            }
            Msg::SendState => {
                self.emit_queue().await;
                self.now_playing();
            }
            Msg::Refresh => {
                if let Some(item) = self.q.current().and_then(|e| parse_id(&e.item).ok()) {
                    match app().db.read(move |c| lib::track(c, item)).await {
                        Ok(t) => self.track = t.map(track_view),
                        Err(e) => logs::push("error", "player", &e.to_string()),
                    }
                }
                self.now_playing();
                self.emit_queue().await;
            }
            Msg::Online => {
                if app().is_online() {
                    self.offline_told.clear();
                }
                if self.preloaded {
                    self.preload().await;
                }
            }
            Msg::Artwork(entry, path) => {
                if self.current_entry() == Some(entry) {
                    self.artwork = Some(path);
                    self.now_playing();
                }
            }
        }
    }

    fn current_entry(&self) -> Option<EntryId> {
        self.q.current().map(|e| e.id)
    }

    fn is_current(&self, entry: &str) -> bool {
        self.current_entry()
            .is_some_and(|e| e.0.to_string() == entry)
    }

    async fn play(
        &mut self,
        items: Vec<String>,
        start: usize,
        context: Option<PlayContext>,
    ) -> Result<(), CoreError> {
        for i in &items {
            parse_id(i)?;
        }
        // The user's shuffle and repeat carry over to the new queue.
        let (shuffle, repeat) = (self.q.shuffle, self.q.repeat);
        self.q = QueueState::play(items, start, context, shuffle, seed());
        self.q.set_repeat(repeat);
        let q = &self.q;
        self.candidates
            .retain(|item, _| q.entries.iter().any(|e| e.item == item.to_string()));
        let mut entries: Vec<EntryId> = self.current_entry().into_iter().collect();
        entries.extend(following(&self.q, false));
        self.start(entries, 0, true).await
    }

    /// Plays the first entry of `entries` that has a source (those before it are skipped,
    /// with a notice), at `position_ms` if it is the first one, else from 0; none: `Stop`,
    /// and the error if there was one.
    async fn start(
        &mut self,
        entries: Vec<EntryId>,
        position_ms: u64,
        autoplay: bool,
    ) -> Result<(), CoreError> {
        let first = entries.first().copied();
        let found = self.first_playable(entries).await;
        let result = match found {
            Ok(Some(l)) => {
                // A fallback starts from its beginning.
                let position_ms = if Some(l.entry) == first {
                    position_ms
                } else {
                    0
                };
                self.q.jump_to(l.entry);
                self.q.position_ms = position_ms;
                self.send_play(l, position_ms, autoplay);
                Ok(())
            }
            Ok(None) => {
                self.stop();
                Ok(())
            }
            Err(e) => {
                self.stop();
                Err(e)
            }
        };
        self.queue_changed().await;
        result
    }

    fn send_play(&mut self, l: Loaded, position_ms: u64, autoplay: bool) {
        send(PlayerCommand::Play {
            entry: l.entry.0.to_string(),
            source: l.res.source.clone(),
            position_ms,
            autoplay,
            gain_db: l.gain_db,
        });
        self.current = Some(l);
        self.next = None;
        self.held = false;
        self.preloaded = false;
        self.deadline = None;
        self.playing = false;
        self.wants_play = autoplay;
        self.resume = None;
        self.pos_ms = position_ms;
        self.pos_at = Instant::now();
    }

    fn stop(&mut self) {
        send(PlayerCommand::Stop);
        self.current = None;
        self.next = None;
        self.held = false;
        self.deadline = None;
        self.playing = false;
        self.resume = None;
    }

    /// The first entry with a source. A missing resolver stops everything at once; offline
    /// skips are free; other failures count, `MAX_SKIPS` at most.
    async fn first_playable(&mut self, entries: Vec<EntryId>) -> Result<Option<Loaded>, CoreError> {
        let (mut failures, mut last) = (0, None);
        for entry in entries {
            let Some(item) = self.q.entries.iter().find(|e| e.id == entry) else {
                continue;
            };
            let loaded = match parse_id(&item.item) {
                Ok(item) => self.load(entry, item).await.map_err(|e| (Some(item), e)),
                Err(e) => Err((None, e)),
            };
            match loaded {
                Ok(l) => return Ok(Some(l)),
                Err((_, e @ CoreError::NoPlugin(_))) => return Err(e),
                Err((item, e)) => {
                    self.skipped(entry, item, e.clone()).await;
                    if e != CoreError::Offline {
                        failures += 1;
                    }
                    last = Some(e);
                    if failures == MAX_SKIPS {
                        break;
                    }
                }
            }
        }
        last.map_or(Ok(None), Err)
    }

    async fn load(&mut self, entry: EntryId, item: ItemId) -> Result<Loaded, CoreError> {
        let res = source_for(item).await?;
        self.remember(item, &res);
        Ok(Loaded {
            entry,
            item,
            gain_db: gain_for(&res).await,
            res,
            attempts: 0,
            tried: vec![],
            positions: 0,
        })
    }

    fn remember(&mut self, item: ItemId, res: &Resolution) {
        match &res.plugin {
            Some(p) if !res.candidates.is_empty() => {
                self.candidates
                    .insert(item, (p.clone(), res.candidates.clone()));
            }
            Some(_) => {
                self.candidates.remove(&item);
            }
            None => {}
        }
    }

    /// Tells the user; an offline skip only once per entry until back online.
    async fn skipped(&mut self, entry: EntryId, item: Option<ItemId>, reason: CoreError) {
        if reason == CoreError::Offline && !self.offline_told.insert(entry) {
            return;
        }
        logs::push("warn", "player", &format!("skipped: {reason:?}"));
        let title = match item {
            Some(item) => app().db.read(move |c| lib::track(c, item)).await,
            None => Ok(None),
        };
        let title = title.ok().flatten().map(|t| t.title).unwrap_or_default();
        let _ = app().events.notices.send(Notice::Skipped { title, reason });
    }

    /// `following`, extended by a radio when it is empty (radio on, online).
    async fn following_or_radio(&mut self, honor_one: bool) -> Vec<EntryId> {
        let next = following(&self.q, honor_one);
        if !next.is_empty() || !app().is_online() || !enabled("radio", true).await {
            return next;
        }
        let Some(seed) = self.q.current().and_then(|e| parse_id(&e.item).ok()) else {
            return next;
        };
        match radio(seed).await {
            Ok(items) => {
                self.q.append_radio(items);
                following(&self.q, honor_one)
            }
            Err(e) => {
                logs::push("warn", "player", &format!("radio: {e:?}"));
                next
            }
        }
    }

    /// Resolves what plays next and hands it to the player (again after an edit: replaced or
    /// cleared). At the end of the queue, a radio extends it.
    async fn preload(&mut self) {
        self.deadline = None;
        self.preloaded = true;
        self.next = None;
        let held = self.held;
        let mut entries = self.following_or_radio(true).await;
        entries.retain(|e| !self.given_up.contains(e));
        self.preload_for = self.q.next().map(|e| e.id);
        match self.first_playable(entries).await {
            Ok(Some(l)) => {
                let (entry, source, gain_db) =
                    (l.entry.0.to_string(), l.res.source.clone(), l.gain_db);
                send(match held {
                    true => PlayerCommand::ReplaceNext {
                        entry,
                        source,
                        gain_db,
                    },
                    false => PlayerCommand::EnqueueNext {
                        entry,
                        source,
                        gain_db,
                    },
                });
                self.next = Some(l);
                self.held = true;
            }
            _ if held => {
                send(PlayerCommand::ClearNext);
                self.held = false;
            }
            _ => {}
        }
        self.queue_changed().await;
    }

    /// Arms the preload timer: `PRELOAD_LEAD_MS` before the end, while playing.
    fn arm(&mut self) {
        self.deadline = None;
        if self.preloaded || !self.playing {
            return;
        }
        let catalogue = self.track.as_ref().and_then(|t| t.duration_ms);
        let Some(duration) = self.duration_ms.or(catalogue.map(u64::from)) else {
            return;
        };
        let at = self.pos_ms + self.pos_at.elapsed().as_millis() as u64;
        let left = duration.saturating_sub(at).saturating_sub(PRELOAD_LEAD_MS);
        self.deadline = Some(Instant::now() + Duration::from_millis(left));
    }

    /// A new reported position: the time played since the last one counts as listened.
    fn position(&mut self, ms: u64) {
        if self.playing {
            self.listened_ms += ms.saturating_sub(self.pos_ms);
        }
        self.pos_ms = ms;
        self.pos_at = Instant::now();
        self.q.position_ms = ms;
    }

    async fn event(&mut self, e: PlayerEvent) {
        match e {
            PlayerEvent::TrackStarted { entry } => self.started(&entry).await,
            PlayerEvent::Duration { entry, ms } if self.is_current(&entry) => {
                self.duration_ms = Some(ms);
                self.now_playing();
                self.arm();
            }
            PlayerEvent::Position { entry, ms } if self.is_current(&entry) => {
                self.failed_in_row = 0; // it plays
                if let Some(l) = &mut self.current {
                    l.positions = l.positions.saturating_add(1);
                    if l.positions >= 2 {
                        l.attempts = 0;
                    }
                }
                self.position(ms);
                self.save_progress().await;
                self.arm();
            }
            PlayerEvent::Paused { entry, ms } if self.is_current(&entry) => {
                self.position(ms);
                self.playing = false;
                self.wants_play = false;
                self.deadline = None;
                self.save_progress().await;
            }
            PlayerEvent::Resumed { entry } if self.is_current(&entry) => {
                self.playing = true;
                self.wants_play = true;
                self.pos_at = Instant::now();
                self.arm();
            }
            PlayerEvent::Seeked { entry, ms } if self.is_current(&entry) => {
                self.pos_ms = ms;
                self.pos_at = Instant::now();
                self.q.position_ms = ms;
                self.arm();
            }
            PlayerEvent::Ended { entry } if self.is_current(&entry) => self.ended().await,
            PlayerEvent::Error {
                entry,
                kind,
                position_ms,
                ..
            } => self.error(&entry, kind, position_ms).await,
            // About an entry that is no longer current: late, ignored.
            _ => {}
        }
    }

    async fn started(&mut self, entry: &str) {
        let Some(id) = self
            .q
            .entries
            .iter()
            .find(|e| e.id.0.to_string() == entry)
            .map(|e| e.id)
        else {
            logs::push("warn", "player", "started an entry not in the queue");
            return;
        };
        // `playing` is left alone: only `Resumed`, `Paused`, `Ended` and `Error` say it.
        let resumed = self.resume.take() == Some(id);
        let same = self.current_entry() == Some(id);
        if !same {
            self.q.jump_to(id);
            self.given_up.clear();
        } else if !resumed {
            self.q.position_ms = 0;
        }
        if self.next.as_ref().is_some_and(|l| l.entry == id) {
            // The preloaded next, as planned: the player holds nothing after it.
            self.current = self.next.take();
            self.held = false;
        } else if !self.current.as_ref().is_some_and(|l| l.entry == id) {
            // It crossed a command (a `ReplaceNext` sent while it started): what the player
            // holds is unknown, and "play next" goes right after this one.
            if let Some(x) = self.next.take().map(|l| l.entry) {
                let pos = |q: &QueueState| q.order.iter().position(|&i| q.entries[i].id == x);
                if pos(&self.q).is_some_and(|p| p < self.q.index) {
                    self.q.move_entry(x, self.q.index);
                }
            }
            self.current = None;
            self.held = true;
        }
        self.next = None;
        self.preloaded = false;
        self.preload_for = None;
        self.pos_ms = self.q.position_ms;
        self.pos_at = Instant::now();
        if !resumed {
            self.duration_ms = None;
            self.artwork = None;
        }
        let Some(item) = self.q.current().and_then(|e| parse_id(&e.item).ok()) else {
            return;
        };

        // Closes the previous play, opens this one (a resumed one stays open), saves the queue.
        let new_play = !resumed || self.play.is_none();
        let source = match &self.current {
            Some(l) => l.res.plugin.clone().unwrap_or_else(|| "download".into()),
            None => "unknown".into(),
        };
        let (previous, listened) = (self.play, self.listened_ms);
        let json = serde_json::to_string(&self.q).unwrap_or_default();
        let written = app()
            .db
            .write(move |tx| {
                if let Some(p) = previous {
                    plays::set_listened(tx, p, listened)?;
                }
                let play = match new_play {
                    true => Some(plays::start(tx, item, &source)?),
                    false => None,
                };
                saved::save(tx, &json)?;
                Ok((play, lib::track(&tx.tx, item)?))
            })
            .await;
        match written {
            Ok((play, track)) => {
                if let Some(p) = play {
                    self.play = Some(p);
                    self.listened_ms = 0;
                    let _ = app().events.library.send(LibraryChanged::History);
                }
                self.track = track.map(track_view);
            }
            Err(e) => logs::push("error", "player", &e.to_string()),
        }
        self.now_playing();
        if self.artwork.is_none() {
            // Off the actor: a download must not hold up the queue.
            let item = item.to_string();
            tokio::spawn(async move {
                if let Ok(Some(path)) = crate::catalog::artwork_file(&item, ARTWORK_SIZE).await {
                    let _ = actor().send(Msg::Artwork(id, path));
                }
            });
        }
        self.emit_queue().await;
        self.arm();
    }

    async fn ended(&mut self) {
        self.failed_in_row = 0; // it played (a short track ends before any position)
        // Played to the end: the rest counts as listened.
        let catalogue = self.track.as_ref().and_then(|t| t.duration_ms);
        if let Some(d) = self.duration_ms.or(catalogue.map(u64::from)) {
            self.position(d.max(self.pos_ms));
        }
        self.playing = false;
        self.deadline = None;
        self.save_progress().await;
        if self.next.is_some() {
            return; // The player goes on with it.
        }
        let entries = self.following_or_radio(true).await;
        let _ = self.start(entries, 0, true).await;
    }

    /// The player stopped on an error, at `position_ms`; 0 (a player that reset it on open)
    /// keeps the last known position.
    async fn error(&mut self, entry: &str, kind: PlayerErrorKind, position_ms: u64) {
        if !self.is_current(entry) {
            self.next_failed(entry, kind).await;
            return;
        }
        if position_ms > 0 {
            self.position(position_ms);
        }
        self.playing = false;
        self.deadline = None;
        let Some(e) = self.q.current() else {
            return;
        };
        let (entry, item) = (e.id, parse_id(&e.item).ok());
        match kind {
            PlayerErrorKind::Forbidden => self.expired(entry, item).await,
            // The player stays stopped; the user resumes once the network is back.
            PlayerErrorKind::Network => {
                let _ = app().events.notices.send(Notice::Error(CoreError::Network));
            }
            PlayerErrorKind::Decode | PlayerErrorKind::Other => {
                let reason = CoreError::Internal("unplayable stream".into());
                self.skipped(entry, item, reason.clone()).await;
                self.failed_current(reason).await;
            }
        }
    }

    /// The current track failed without playing: the next one, unless `MAX_SKIPS` failed in a
    /// row (`Repeat::All` over unplayable files would loop forever): then it stops, the queue
    /// kept, and the user is told.
    async fn failed_current(&mut self, reason: CoreError) {
        self.failed_in_row += 1;
        if self.failed_in_row >= MAX_SKIPS {
            self.failed_in_row = 0;
            self.stop();
            self.queue_changed().await;
            let _ = app().events.notices.send(Notice::Error(reason));
            return;
        }
        let entries = self.following_or_radio(false).await;
        let _ = self.start(entries, 0, true).await;
    }

    /// The held next failed before it started: a 403 climbs the same ladder as the current
    /// track; anything else (or the top of the ladder) gives it up and preloads the following.
    async fn next_failed(&mut self, entry: &str, kind: PlayerErrorKind) {
        let Some(l) = self.next.take_if(|l| l.entry.0.to_string() == entry) else {
            return; // Late, about an entry no longer current or next: ignored.
        };
        let (entry, item) = (l.entry, l.item);
        let reason = match kind {
            PlayerErrorKind::Forbidden => {
                match self
                    .ladder(entry, item, l.attempts, l.tried, l.res.id)
                    .await
                {
                    Ok(l) => {
                        send(PlayerCommand::ReplaceNext {
                            entry: l.entry.0.to_string(),
                            source: l.res.source.clone(),
                            gain_db: l.gain_db,
                        });
                        self.next = Some(l);
                        return;
                    }
                    Err(e) => e,
                }
            }
            PlayerErrorKind::Network => CoreError::Network,
            PlayerErrorKind::Decode | PlayerErrorKind::Other => {
                CoreError::Internal("unplayable stream".into())
            }
        };
        self.skipped(entry, Some(item), reason).await;
        self.given_up.insert(entry);
        self.preload().await;
    }

    /// An expired URL (403) on the current track: the ladder, resuming where it stopped;
    /// at its top, the next track. Nothing held for it (a crossed `TrackStarted`): the
    /// queue's current entry, from a fresh resolution.
    async fn expired(&mut self, entry: EntryId, item: Option<ItemId>) {
        let cur = self.current.take().filter(|l| l.entry == entry);
        let (attempts, tried, last) = match cur {
            Some(l) => (l.attempts, l.tried, l.res.id),
            None => (0, vec![], None),
        };
        let result = match item {
            Some(item) => self.ladder(entry, item, attempts, tried, last).await,
            None => Err(CoreError::Internal("malformed item id".into())),
        };
        match result {
            Ok(l) => {
                // Paused stays paused.
                self.send_play(l, self.pos_ms, self.wants_play);
                self.resume = Some(entry);
            }
            Err(e) => {
                self.skipped(entry, item, e.clone()).await;
                self.failed_current(e).await;
            }
        }
    }

    /// The 403 ladder: a fresh resolution, then the next candidate (`tried` += the last id);
    /// after that, `Expired`.
    async fn ladder(
        &mut self,
        entry: EntryId,
        item: ItemId,
        attempts: u8,
        mut tried: Vec<String>,
        last: Option<String>,
    ) -> Result<Loaded, CoreError> {
        let attempts = attempts + 1;
        if attempts == 2 {
            tried.extend(last);
        }
        if attempts > 2 {
            return Err(CoreError::Expired);
        }
        let res = resolve(item, &tried).await?;
        self.remember(item, &res);
        Ok(Loaded {
            entry,
            item,
            gain_db: gain_for(&res).await,
            res,
            attempts,
            tried,
            positions: 0,
        })
    }

    async fn edit(&mut self, op: QueueOp) -> Result<(), CoreError> {
        let before = self.current_entry();
        match op {
            QueueOp::EnqueueNext(items) | QueueOp::EnqueueLast(items)
                if items.iter().any(|i| parse_id(i).is_err()) =>
            {
                return Err(CoreError::Internal("malformed item id".into()));
            }
            QueueOp::EnqueueNext(items) => self.q.enqueue_next(items),
            QueueOp::EnqueueLast(items) => self.q.enqueue_last(items),
            QueueOp::Remove(e) => self.q.remove(entry_id(&e)?),
            QueueOp::Move { entry, after } => {
                let after = after.as_deref().map(entry_id).transpose()?;
                if !self.q.move_after(entry_id(&entry)?, after) {
                    return Err(CoreError::NotFound);
                }
            }
            QueueOp::Shuffle(on) => self.q.set_shuffle(on, seed()),
            QueueOp::Repeat(r) => self.q.set_repeat(r),
            QueueOp::JumpTo(e) => {
                let id = entry_id(&e)?;
                if !self.q.jump_to(id) {
                    return Err(CoreError::NotFound);
                }
                self.failed_in_row = 0;
                let mut entries = vec![id];
                entries.extend(following(&self.q, false));
                let _ = self.start(entries, 0, true).await;
                return Ok(());
            }
        }
        let now = self.current_entry();
        if now != before {
            self.failed_in_row = 0;
            // The current entry was removed, or a stopped queue got one: play what is current
            // now (only if something was playing), else stop.
            let autoplay = self.playing;
            let mut entries: Vec<EntryId> = now.into_iter().collect();
            entries.extend(following(&self.q, false));
            let _ = self.start(entries, 0, autoplay).await;
            return Ok(());
        }
        if self.preloaded {
            let gone = self
                .next
                .as_ref()
                .is_some_and(|l| !self.q.entries.iter().any(|e| e.id == l.entry));
            if gone || self.q.next().map(|e| e.id) != self.preload_for {
                self.preload().await;
                return Ok(());
            }
        }
        self.queue_changed().await;
        Ok(())
    }

    async fn fix_match(&mut self, item: ItemId) -> Result<Vec<Candidate>, CoreError> {
        if let Some((_, c)) = self.candidates.get(&item) {
            return Ok(c.clone());
        }
        let refs = app().db.read(move |c| refs::all(c, item)).await?;
        let tried: Vec<String> = refs.into_iter().map(|(_, r)| r.external_id).collect();
        let (plugin, r) = call_resolve(item, &tried, None).await?;
        let found: Vec<Candidate> = r.candidates.into_iter().map(candidate).collect();
        self.candidates
            .insert(item, (plugin.id().to_string(), found.clone()));
        Ok(found)
    }

    async fn choose_match(&mut self, item: ItemId, candidate: String) -> Result<(), CoreError> {
        let Some((plugin, list)) = self.candidates.get(&item) else {
            return Err(CoreError::NotFound);
        };
        if !list.iter().any(|c| c.id == candidate) {
            return Err(CoreError::NotFound);
        }
        let plugin = plugin.clone();
        app()
            .db
            .write(move |tx| refs::pin(tx, item, &plugin, &candidate))
            .await?;
        self.candidates.remove(&item);
        let Some(cur) = self.current.take_if(|l| l.item == item) else {
            return Ok(());
        };
        let res = match resolve(item, &[]).await {
            Ok(res) => res,
            Err(e) => {
                self.current = Some(cur);
                return Err(e);
            }
        };
        self.remember(item, &res);
        let entry = cur.entry;
        let l = Loaded {
            gain_db: gain_for(&res).await,
            res,
            attempts: 0,
            tried: vec![],
            positions: 0,
            ..cur
        };
        let autoplay = self.playing;
        self.send_play(l, self.pos_ms, autoplay);
        self.resume = Some(entry);
        Ok(())
    }

    async fn stop_queue(&mut self) {
        if self.playing {
            self.position(self.pos_ms + self.pos_at.elapsed().as_millis() as u64);
        }
        self.save_progress().await; // the time listened
        let empty = QueueState::play(vec![], 0, None, self.q.shuffle, seed());
        let q = std::mem::replace(&mut self.q, empty);
        self.q.set_repeat(q.repeat);
        self.undo = Some(q).filter(|q| !q.entries.is_empty());
        self.stop();
        (self.play, self.listened_ms) = (None, 0);
        (self.track, self.artwork, self.duration_ms) = (None, None, None);
        self.now_playing();
        self.queue_changed().await;
    }

    async fn undo_stop(&mut self) {
        let Some(q) = self.undo.take() else { return };
        let (position, current) = (q.position_ms, q.current().map(|e| e.id));
        self.q = q;
        let mut entries: Vec<EntryId> = current.into_iter().collect();
        entries.extend(following(&self.q, false));
        let _ = self.start(entries, position, true).await;
        if self.current.is_some() && self.current_entry() == current {
            self.resume = current; // its `TrackStarted` keeps the position
        }
    }

    /// Once, and only into an empty queue.
    async fn restore(&mut self) {
        if self.restored || !self.q.entries.is_empty() {
            return;
        }
        let saved = app().db.read(saved::load).await;
        let q = match saved {
            Ok(Some(json)) => match serde_json::from_str::<QueueState>(&json) {
                Ok(q) if q.is_consistent() => Some(q),
                Ok(_) => {
                    logs::push(
                        "error",
                        "player",
                        "saved queue inconsistent: starting empty",
                    );
                    None
                }
                // The serde message may quote the blob (titles): not logged.
                Err(_) => {
                    logs::push("error", "player", "saved queue unreadable: starting empty");
                    None
                }
            },
            Ok(None) => None,
            Err(e) => {
                logs::push("error", "player", &e.to_string());
                None
            }
        };
        *self = Player {
            q: q.unwrap_or_else(|| QueueState::play(vec![], 0, None, false, 0)),
            candidates: std::mem::take(&mut self.candidates),
            restored: true,
            ..Player::new()
        };
        let position = self.q.position_ms;
        if let Some(e) = self.q.current() {
            let entry = e.id;
            let loaded = match parse_id(&e.item) {
                Ok(item) => self.load(entry, item).await,
                Err(e) => Err(e),
            };
            match loaded {
                Ok(l) => {
                    self.send_play(l, position, false);
                    self.resume = Some(entry);
                }
                Err(e) => logs::push("warn", "player", &format!("restore: {e:?}")),
            }
        }
        self.queue_changed().await;
    }

    /// Saves the queue (with its position) and the time listened.
    async fn save_progress(&self) {
        let (json, play, listened) = (
            serde_json::to_string(&self.q).unwrap_or_default(),
            self.play,
            self.listened_ms,
        );
        let r = app()
            .db
            .write(move |tx| {
                if let Some(p) = play {
                    plays::set_listened(tx, p, listened)?;
                }
                saved::save(tx, &json)
            })
            .await;
        if let Err(e) = r {
            logs::push("error", "player", &e.to_string());
        }
    }

    async fn queue_changed(&self) {
        self.save_progress().await;
        self.emit_queue().await;
    }

    async fn emit_queue(&self) {
        let mut entries: Vec<_> = self.q.current().into_iter().collect();
        entries.extend(self.q.upcoming().into_iter().take(VIEW_UPCOMING));
        let entries: Vec<(String, bool, Option<ItemId>)> = entries
            .into_iter()
            .map(|e| (e.id.0.to_string(), e.from_radio, parse_id(&e.item).ok()))
            .collect();
        let has_current = self.q.current().is_some();
        // One track per entry, in the entry's place: a missing one is left out.
        let views = app()
            .db
            .read(move |c| {
                entries
                    .into_iter()
                    .map(|(entry, from_radio, item)| {
                        let track = match item {
                            Some(item) => lib::track(c, item)?.map(track_view),
                            None => None,
                        };
                        Ok((entry, from_radio, track))
                    })
                    .collect::<rusqlite::Result<Vec<_>>>()
            })
            .await;
        let mut views = match views {
            Ok(v) => v.into_iter(),
            Err(e) => {
                logs::push("error", "player", &e.to_string());
                return;
            }
        };
        let (current_entry, current) = match has_current {
            true => views
                .next()
                .map_or((None, None), |(entry, _, track)| (Some(entry), track)),
            false => (None, None),
        };
        let upcoming = views
            .filter_map(|(entry, from_radio, track)| {
                Some(QueueItemView {
                    entry,
                    track: track?,
                    from_radio,
                })
            })
            .collect();
        let _ = app().events.queue.send(QueueView {
            current_entry,
            current,
            upcoming,
            index: self.q.index as u32,
            shuffle: self.q.shuffle,
            repeat: self.q.repeat,
            context: self.q.context.clone(),
        });
    }

    fn now_playing(&self) {
        let catalogue = self.track.as_ref().and_then(|t| t.duration_ms);
        let res = self.current.as_ref().map(|l| &l.res);
        let _ = app().events.now_playing.send(NowPlaying {
            track: self.track.clone(),
            artwork_path: self.artwork.clone(),
            duration_ms: self.duration_ms.or(catalogue.map(u64::from)),
            source: res.map(|r| r.plugin.clone().unwrap_or_else(|| "download".into())),
            mime: res.and_then(|r| r.mime.clone()),
        });
    }
}

#[cfg(test)]
mod tests;
