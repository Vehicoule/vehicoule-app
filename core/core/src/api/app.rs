//! Startup, connectivity, onboarding.

use std::sync::atomic::{AtomicBool, Ordering};

use crate::app::{self as core, AppConfig, app};
use crate::error::CoreError;
use crate::library::settings as rows;
use crate::{downloads, player, telemetry};

/// Device settings: onboarding finished (`true`), telemetry opt-in (`true`/`false`, absent
/// until chosen).
pub(crate) const ONBOARDED: &str = "onboarded";
pub(crate) const TELEMETRY: &str = "telemetry";

pub struct Onboarding {
    pub done: bool,
    /// `None` until the user chooses.
    pub telemetry: Option<bool>,
}

/// First call (on Android, after `RustInit.initVerifier`). Idempotent. Only initialises:
/// Dart then subscribes to the streams, then calls `start`.
pub async fn init_app(cfg: AppConfig) -> Result<(), CoreError> {
    // `init` blocks on its own runtime: never from an async worker.
    joined(tokio::task::spawn_blocking(move || core::init(cfg)).await)
}

/// Once Dart listens (what it sends would be lost before): the saved queue comes back
/// paused, pending downloads restart, telemetry starts if opted in. Idempotent.
pub async fn start() -> Result<(), CoreError> {
    static STARTED: AtomicBool = AtomicBool::new(false);
    if STARTED.swap(true, Ordering::SeqCst) {
        return Ok(());
    }
    player::restore().await;
    downloads::resume_pending().await;
    if onboarding()?.telemetry == Some(true) {
        set_telemetry(true);
    }
    Ok(())
}

/// Offline, no plugin is called; back online, pending downloads restart.
pub async fn set_online(online: bool) {
    player::set_online(online);
    if online {
        downloads::resume_pending().await;
    }
}

pub fn onboarding() -> Result<Onboarding, CoreError> {
    let (done, telemetry) = app().db.read_blocking(|c| {
        Ok((
            rows::device_get(c, ONBOARDED)?,
            rows::device_get(c, TELEMETRY)?,
        ))
    })?;
    Ok(Onboarding {
        done: done.is_some(),
        telemetry: telemetry.map(|v| v != "false"),
    })
}

pub async fn finish_onboarding(telemetry: bool) -> Result<(), CoreError> {
    app()
        .db
        .write(move |tx| {
            rows::device_set(tx, ONBOARDED, "true")?;
            rows::device_set(tx, TELEMETRY, &telemetry.to_string())
        })
        .await?;
    set_telemetry(telemetry);
    Ok(())
}

/// Off the caller's path: closing the client waits up to 2 s for pending reports.
pub(crate) fn set_telemetry(on: bool) {
    app().rt.spawn_blocking(move || telemetry::set_enabled(on));
}

/// A panic in the task panics here too: flutter_rust_bridge turns it into a Dart error.
pub(crate) fn joined<T>(r: Result<T, tokio::task::JoinError>) -> T {
    r.unwrap_or_else(|e| std::panic::resume_unwind(e.into_panic()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::library::queue as saved;
    use crate::player::PlayerCommand;
    use crate::queue::QueueState;

    #[tokio::test]
    async fn start_restores_once_dart_listens() {
        let (_turn, app) = crate::catalog::tests::setup().await;
        // The last run's queue.
        let item = crate::catalog::search("cold start").await.unwrap().tracks[0]
            .id
            .clone();
        let mut q = QueueState::play(vec![item], 0, None, false, 0);
        q.position_ms = 5_000;
        let json = serde_json::to_string(&q).unwrap();
        app.db
            .write(move |tx| saved::save(tx, &json))
            .await
            .unwrap();
        crate::player::reset(); // a cold start

        init_app(app.cfg.clone()).await.unwrap();
        let mut cmds = app.events.commands.subscribe();
        let mut queue = app.events.queue.subscribe();
        start().await.unwrap();
        match cmds.try_recv() {
            Ok(PlayerCommand::Play {
                position_ms: 5_000,
                autoplay: false,
                ..
            }) => {}
            c => panic!("expected a paused load, got {c:?}"),
        }
        let view = queue.try_recv().unwrap();
        assert!(view.current.is_some());
        start().await.unwrap(); // idempotent
        assert!(cmds.try_recv().is_err());
    }
}
