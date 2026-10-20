//! A simulated Dart player: the test reads `PlayerCommand`s and sends `PlayerEvent`s. The
//! `fake` plugin (catalog tests' guest) also resolves and makes radios. Every public call
//! returns once the actor has handled it, so commands it causes are already sent; only the
//! preload timer needs time (paused clock).

use std::time::Duration;

use plugin_host::Capability;
use tokio::sync::MutexGuard;
use tokio::sync::broadcast::Receiver;
use tokio::sync::broadcast::error::TryRecvError;
use tokio::time::{Instant, timeout};

use super::*;
use crate::app::test_app;
use crate::catalog::{self, parse_id};
use crate::events::{Notice, QueueView};
use crate::library::downloads::{self, DownloadRow, DownloadState};
use crate::library::{kv, queue as saved, refs, settings};

struct T {
    _lock: MutexGuard<'static, ()>,
    cmds: Receiver<PlayerCommand>,
    notices: Receiver<Notice>,
    queue: Receiver<QueueView>,
}

/// The catalogue lock, a fresh actor, radio off, normalisation on.
async fn setup() -> T {
    let (lock, app) = catalog::tests::setup().await;
    reset();
    set_radio(false).await;
    app.db
        .write(|tx| settings::device_set(tx, "normalize_volume", "true"))
        .await
        .unwrap();
    T {
        _lock: lock,
        cmds: app.events.commands.subscribe(),
        notices: app.events.notices.subscribe(),
        queue: app.events.queue.subscribe(),
    }
}

async fn set_radio(on: bool) {
    let v = if on { "true" } else { "false" };
    test_app()
        .db
        .write(move |tx| settings::shared_set(tx, "radio", v))
        .await
        .unwrap();
}

/// A track item from the fake catalogue (ref `t-<key>` at `fake`).
async fn track(title: &str) -> String {
    catalog::search(title).await.unwrap().tracks[0].id.clone()
}

async fn downloaded(id: &str, path: &str) {
    let (item, path) = (parse_id(id).unwrap(), path.to_string());
    test_app()
        .db
        .write(move |tx| {
            downloads::enqueue(tx, item, "normal")?;
            downloads::update(
                tx,
                &DownloadRow {
                    item,
                    state: DownloadState::Done,
                    path: Some(path),
                    quality: "normal".into(),
                    mime: Some("audio/mpeg".into()),
                    loudness_db: Some(4.2),
                    bytes_total: Some(1),
                    bytes_done: 1,
                    error: None,
                },
            )
        })
        .await
        .unwrap();
}

fn now(rx: &mut Receiver<PlayerCommand>) -> PlayerCommand {
    rx.try_recv().expect("a command right away")
}

fn nothing(rx: &mut Receiver<PlayerCommand>) {
    assert_eq!(
        rx.try_recv().map_err(|_| ()),
        Err(()),
        "no command expected"
    );
}

/// `(entry, uri, position, autoplay)` of a `Play`.
fn played(c: PlayerCommand) -> (String, String, u64, bool) {
    match c {
        PlayerCommand::Play {
            entry,
            source,
            position_ms,
            autoplay,
            ..
        } => (entry, source.uri, position_ms, autoplay),
        c => panic!("expected Play, got {c:?}"),
    }
}

fn enqueued(c: PlayerCommand) -> (String, String) {
    match c {
        PlayerCommand::EnqueueNext { entry, source, .. } => (entry, source.uri),
        c => panic!("expected EnqueueNext, got {c:?}"),
    }
}

fn replaced(c: PlayerCommand) -> String {
    match c {
        PlayerCommand::ReplaceNext { entry, .. } => entry,
        c => panic!("expected ReplaceNext, got {c:?}"),
    }
}

fn last_queue(rx: &mut Receiver<QueueView>) -> QueueView {
    let mut last = None;
    loop {
        match rx.try_recv() {
            Ok(v) => last = Some(v),
            Err(TryRecvError::Lagged(_)) => {}
            Err(_) => return last.expect("a queue view"),
        }
    }
}

fn skipped(rx: &mut Receiver<Notice>) -> Vec<(String, CoreError)> {
    std::iter::from_fn(|| rx.try_recv().ok())
        .filter_map(|n| match n {
            Notice::Skipped { title, reason } => Some((title, reason)),
            _ => None,
        })
        .collect()
}

async fn started(entry: &str, duration_ms: u64) {
    let entry = entry.to_string();
    on_event(PlayerEvent::TrackStarted {
        entry: entry.clone(),
    })
    .await;
    on_event(PlayerEvent::Duration {
        entry,
        ms: duration_ms,
    })
    .await;
}

fn ev_pos(entry: &str, ms: u64) -> PlayerEvent {
    PlayerEvent::Position {
        entry: entry.into(),
        ms,
    }
}

fn forbidden(entry: &str) -> PlayerEvent {
    PlayerEvent::Error {
        entry: entry.into(),
        kind: PlayerErrorKind::Forbidden,
        message: "HTTP 403".into(),
    }
}

#[test]
fn player_futures_are_send() {
    fn send<T: Send>(_: T) {}
    send(play(vec![], 0, None));
    send(on_event(PlayerEvent::Ended { entry: "x".into() }));
    send(skip_next());
    send(previous(0));
    send(edit(QueueOp::Shuffle(true)));
    send(fix_match("x"));
    send(choose_match("x", "y"));
    send(restore());
}

#[tokio::test(start_paused = true)]
async fn preload_fires_20s_before_end() {
    let mut t = setup().await;
    let (a, b) = (track("preload a").await, track("preload b").await);
    play(vec![a, b], 0, None).await.unwrap();
    let (entry, uri, ..) = played(now(&mut t.cmds));
    assert_eq!(uri, "https://fake.test/stream/t-preload-a");
    let t0 = Instant::now();
    started(&entry, 180_000).await;
    assert!(
        timeout(Duration::from_millis(159_000), t.cmds.recv())
            .await
            .is_err(),
        "nothing before 159 s"
    );
    let (next, uri) = enqueued(t.cmds.recv().await.unwrap());
    let at = t0.elapsed();
    assert!(
        at >= Duration::from_millis(159_900) && at <= Duration::from_millis(160_100),
        "{at:?}"
    );
    assert_ne!(next, entry);
    assert_eq!(uri, "https://fake.test/stream/t-preload-b");
}

#[tokio::test(start_paused = true)]
async fn pause_suspends_preload() {
    let mut t = setup().await;
    let (a, b) = (track("pause a").await, track("pause b").await);
    play(vec![a, b], 0, None).await.unwrap();
    let (entry, ..) = played(now(&mut t.cmds));
    started(&entry, 180_000).await;
    assert!(
        timeout(Duration::from_secs(100), t.cmds.recv())
            .await
            .is_err()
    );
    on_event(PlayerEvent::Paused {
        entry: entry.clone(),
        ms: 100_000,
    })
    .await;
    assert!(
        timeout(Duration::from_secs(500), t.cmds.recv())
            .await
            .is_err(),
        "paused: no preload"
    );
    let t1 = Instant::now();
    on_event(PlayerEvent::Resumed {
        entry: entry.clone(),
    })
    .await;
    enqueued(t.cmds.recv().await.unwrap());
    let at = t1.elapsed();
    assert!(
        at >= Duration::from_millis(59_900) && at <= Duration::from_millis(60_100),
        "{at:?}"
    );
}

#[tokio::test(start_paused = true)]
async fn queue_edit_after_preload_replaces_next() {
    let mut t = setup().await;
    let ids = [
        track("edit a").await,
        track("edit b").await,
        track("edit c").await,
    ];
    play(ids.to_vec(), 0, None).await.unwrap();
    let (entry, ..) = played(now(&mut t.cmds));
    started(&entry, 30_000).await;
    let (b, _) = enqueued(t.cmds.recv().await.unwrap());

    // "Play next" during the last 20 s: the player must not keep the old next.
    let x = track("edit x").await;
    edit(QueueOp::EnqueueNext(vec![x])).await.unwrap();
    let x = replaced(now(&mut t.cmds));
    assert_ne!(x, b);
    edit(QueueOp::Remove(x)).await.unwrap();
    assert_eq!(replaced(now(&mut t.cmds)), b);
    // An edit that leaves the next one alone sends nothing.
    edit(QueueOp::Repeat(Repeat::Off)).await.unwrap();
    nothing(&mut t.cmds);
    edit(QueueOp::Remove(b)).await.unwrap();
    let c = replaced(now(&mut t.cmds));
    edit(QueueOp::Remove(c)).await.unwrap();
    assert_eq!(now(&mut t.cmds), PlayerCommand::ClearNext);
    on_event(PlayerEvent::Ended { entry }).await;
    assert_eq!(now(&mut t.cmds), PlayerCommand::Stop);
}

#[tokio::test(start_paused = true)]
async fn radio_extends_the_queue_at_its_end() {
    let mut t = setup().await;
    set_radio(true).await;
    play(vec![track("radio seed").await], 0, None)
        .await
        .unwrap();
    let (entry, ..) = played(now(&mut t.cmds));
    started(&entry, 30_000).await;
    let (next, uri) = enqueued(t.cmds.recv().await.unwrap());
    assert_ne!(next, entry);
    assert_eq!(uri, "https://fake.test/stream/radio-radio-seed-1");
    // The view follows the command.
    let view = loop {
        let v = t.queue.recv().await.unwrap();
        if !v.upcoming.is_empty() {
            break v;
        }
    };
    assert_eq!(view.upcoming.len(), 25);
    assert_eq!(view.upcoming[0].title, "radio radio-seed 1");
}

#[tokio::test(start_paused = true)]
async fn radio_disabled_stops_at_end() {
    let mut t = setup().await;
    play(vec![track("no radio").await], 0, None).await.unwrap();
    let (entry, ..) = played(now(&mut t.cmds));
    started(&entry, 30_000).await;
    assert!(
        timeout(Duration::from_secs(60), t.cmds.recv())
            .await
            .is_err()
    );
    on_event(PlayerEvent::Ended { entry }).await;
    assert_eq!(now(&mut t.cmds), PlayerCommand::Stop);
    assert!(last_queue(&mut t.queue).upcoming.is_empty());
}

#[tokio::test]
async fn downloaded_file_wins_over_network() {
    let mut t = setup().await;
    let a = track("downloaded song").await;
    downloaded(&a, "/music/downloaded.mp3").await;
    let before = catalog::tests::calls().await;
    play(vec![a], 0, None).await.unwrap();
    match now(&mut t.cmds) {
        PlayerCommand::Play {
            source, gain_db, ..
        } => {
            assert_eq!(source.uri, "/music/downloaded.mp3");
            assert!(source.headers.is_empty());
            assert!((gain_db + 4.2).abs() < 1e-6, "{gain_db}");
        }
        c => panic!("{c:?}"),
    }
    assert_eq!(catalog::tests::calls().await, before, "no resolve call");
}

#[tokio::test]
async fn offline_skips_undownloaded_tracks() {
    let mut t = setup().await;
    let [a, b, c, x] = [
        track("offline a").await,
        track("offline b").await,
        track("offline c").await,
        track("offline x").await,
    ];
    downloaded(&a, "/music/a.mp3").await;
    downloaded(&c, "/music/c.mp3").await;
    set_online(false);
    let before = catalog::tests::calls().await;
    play(vec![b, a, x, c], 0, None).await.unwrap();
    let (entry, uri, ..) = played(now(&mut t.cmds));
    assert_eq!(uri, "/music/a.mp3");
    assert_eq!(
        skipped(&mut t.notices),
        [("offline b".to_string(), CoreError::Offline)]
    );
    // Less than 20 s left: the preload runs at once and skips `x`.
    started(&entry, 15_000).await;
    let (_, uri) = enqueued(
        timeout(Duration::from_secs(5), t.cmds.recv())
            .await
            .unwrap()
            .unwrap(),
    );
    assert_eq!(uri, "/music/c.mp3");
    assert_eq!(
        skipped(&mut t.notices),
        [("offline x".to_string(), CoreError::Offline)]
    );
    assert_eq!(catalog::tests::calls().await, before, "offline: no call");
    set_online(true);
}

#[tokio::test]
async fn expired_url_is_resolved_once_then_resumes() {
    let mut t = setup().await;
    play(vec![track("expired").await], 0, None).await.unwrap();
    let (entry, ..) = played(now(&mut t.cmds));
    started(&entry, 180_000).await;
    on_event(ev_pos(&entry, 42_000)).await;
    let before = catalog::tests::calls().await;
    on_event(forbidden(&entry)).await;
    let (e, uri, position, autoplay) = played(now(&mut t.cmds));
    assert_eq!((e, position, autoplay), (entry, 42_000, true));
    assert_eq!(uri, "https://fake.test/stream/t-expired");
    assert_eq!(catalog::tests::calls().await, before + 1, "one resolve");
    assert!(skipped(&mut t.notices).is_empty());
}

#[tokio::test]
async fn second_forbidden_tries_next_candidate() {
    let mut t = setup().await;
    let ids = vec![track("twice").await, track("twice next").await];
    play(ids, 0, None).await.unwrap();
    let (entry, ..) = played(now(&mut t.cmds));
    started(&entry, 180_000).await;
    on_event(ev_pos(&entry, 10_000)).await;
    on_event(forbidden(&entry)).await;
    played(now(&mut t.cmds));
    on_event(PlayerEvent::TrackStarted {
        entry: entry.clone(),
    })
    .await;
    on_event(forbidden(&entry)).await;
    let (e, uri, position, _) = played(now(&mut t.cmds));
    assert_eq!((e.as_str(), position), (entry.as_str(), 10_000));
    assert_eq!(uri, "https://fake.test/stream/r-twice-1");
    let tried = test_app()
        .db
        .read(|c| kv::get(c, "fake", "tried"))
        .await
        .unwrap()
        .unwrap();
    assert_eq!(String::from_utf8(tried).unwrap(), "t-twice");
    // A third failure: next track, and the user is told.
    on_event(forbidden(&entry)).await;
    let (next, uri, ..) = played(now(&mut t.cmds));
    assert_ne!(next, entry);
    assert_eq!(uri, "https://fake.test/stream/t-twice-next");
    assert_eq!(skipped(&mut t.notices).len(), 1);
}

#[tokio::test]
async fn no_resolver_reports_no_plugin() {
    let mut t = setup().await;
    let a = track("no resolver").await;
    test_app().plugins.replace_loaded(vec![]);
    assert_eq!(
        play(vec![a], 0, None).await,
        Err(CoreError::NoPlugin(Capability::Resolve))
    );
    // The queue was replaced: whatever played stops. No per-track notice for a missing plugin.
    assert_eq!(now(&mut t.cmds), PlayerCommand::Stop);
    assert!(skipped(&mut t.notices).is_empty());
}

#[tokio::test]
async fn history_records_listened_time() {
    let mut t = setup().await;
    let (a, b) = (track("history a").await, track("history b").await);
    play(vec![a.clone(), b.clone()], 0, None).await.unwrap();
    let (entry, ..) = played(now(&mut t.cmds));
    started(&entry, 180_000).await;
    for e in [
        ev_pos(&entry, 10_000),
        ev_pos(&entry, 20_000),
        PlayerEvent::Paused {
            entry: entry.clone(),
            ms: 25_000,
        },
        PlayerEvent::Resumed {
            entry: entry.clone(),
        },
        PlayerEvent::Seeked {
            entry: entry.clone(),
            ms: 100_000,
        },
        ev_pos(&entry, 110_000),
    ] {
        on_event(e).await;
    }
    // Nothing preloaded (no time passed): at the end, the core plays `b`, and the rest of `a`
    // counts as listened.
    on_event(PlayerEvent::Ended {
        entry: entry.clone(),
    })
    .await;
    let (next, ..) = played(now(&mut t.cmds));
    on_event(PlayerEvent::TrackStarted { entry: next }).await;
    let plays = |id: String| async move {
        let item = parse_id(&id).unwrap();
        test_app()
            .db
            .read(move |c| {
                c.query_row(
                    "SELECT listened_ms, source FROM plays WHERE item_id = ?1
                     ORDER BY started_at DESC, id DESC LIMIT 1",
                    [item],
                    |r| Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?)),
                )
            })
            .await
            .unwrap()
    };
    // 0→10, 10→20, 20→25 (paused), seek to 100, 100→110, then 110→180 at the end.
    assert_eq!(plays(a).await, (105_000, "fake".into()));
    assert_eq!(plays(b).await, (0, "fake".into()));
}

#[tokio::test]
async fn restore_resumes_paused_at_saved_position() {
    let mut t = setup().await;
    let ids = vec![track("restore a").await, track("restore b").await];
    play(ids, 1, None).await.unwrap();
    let (entry, ..) = played(now(&mut t.cmds));
    started(&entry, 180_000).await;
    on_event(ev_pos(&entry, 73_000)).await;

    reset(); // the app restarts
    restore().await;
    let (e, uri, position, autoplay) = played(now(&mut t.cmds));
    assert_eq!((e, position, autoplay), (entry, 73_000, false));
    assert_eq!(uri, "https://fake.test/stream/t-restore-b");
    let view = last_queue(&mut t.queue);
    assert_eq!(view.index, 1);
    assert_eq!(view.current.unwrap().title, "restore b");

    // Undecodable or inconsistent state: an empty queue and a log line, never a panic.
    let mut bad: crate::queue::QueueState = {
        let json = test_app().db.read(saved::load).await.unwrap().unwrap();
        serde_json::from_str(&json).unwrap()
    };
    bad.order = vec![7, 7];
    for json in ["{".to_string(), serde_json::to_string(&bad).unwrap()] {
        test_app()
            .db
            .write(move |tx| saved::save(tx, &json))
            .await
            .unwrap();
        reset();
        restore().await;
        nothing(&mut t.cmds);
        let view = last_queue(&mut t.queue);
        assert_eq!((view.current, view.upcoming.len()), (None, 0));
        let logged = crate::logs::recent();
        assert!(logged.iter().rev().any(|l| l.source == "player"));
    }
}

#[tokio::test]
async fn choose_match_pins_and_replays() {
    let mut t = setup().await;
    let a = track("match me").await;
    play(vec![a.clone()], 0, None).await.unwrap();
    let (entry, uri, ..) = played(now(&mut t.cmds));
    assert_eq!(uri, "https://fake.test/stream/t-match-me");
    started(&entry, 180_000).await;
    on_event(ev_pos(&entry, 5_000)).await;
    let ids = |c: Vec<Candidate>| c.into_iter().map(|c| c.id).collect::<Vec<_>>();
    assert_eq!(
        ids(fix_match(&a).await.unwrap()),
        ["r-match-me-1", "r-match-me-2", "r-match-me-3"]
    );
    choose_match(&a, "r-match-me-2").await.unwrap();
    let (e, uri, position, autoplay) = played(now(&mut t.cmds));
    assert_eq!((e, position, autoplay), (entry, 5_000, true));
    assert_eq!(uri, "https://fake.test/stream/r-match-me-2");
    let item = parse_id(&a).unwrap();
    let pinned = test_app()
        .db
        .read(move |c| refs::get(c, item, "fake"))
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        (pinned.external_id.as_str(), pinned.pinned),
        ("r-match-me-2", true)
    );
    // Nothing in memory (restart): a resolve that skips the current match finds others.
    reset();
    let others = ids(fix_match(&a).await.unwrap());
    assert!(!others.is_empty());
    assert!(!others.contains(&"r-match-me-2".to_string()), "{others:?}");
}

#[test]
fn gain_only_turns_down() {
    assert!((gain_db(4.2) + 4.2).abs() < 1e-6);
    assert_eq!(gain_db(-3.0), 0.0);
    assert_eq!(gain_db(30.0), -15.0);
}
