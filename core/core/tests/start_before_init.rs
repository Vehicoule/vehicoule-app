//! Its own process: the `App` is not built yet.

use vehicoule_core::api::app::{AppConfig, Platform, init_app, start};
use vehicoule_core::api::system::diagnostics;
use vehicoule_core::error::CoreError;

#[tokio::test(flavor = "multi_thread")]
async fn a_start_before_init_fails_and_blocks_nothing() {
    let early = tokio::spawn(start()).await;

    let dir = std::env::temp_dir().join(format!("vehicoule-start-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    let path = |p: &str| dir.join(p).to_string_lossy().into_owned();
    init_app(AppConfig {
        data_dir: path("data"),
        cache_dir: path("cache"),
        downloads_dir: path("downloads"),
        app_version: "0.0.0".into(),
        region: "FR".into(),
        platform: Platform::MacOs,
        os_version: "test".into(),
        device_model: "test".into(),
    })
    .await
    .unwrap();
    // A saved queue `restore` cannot read: what it logs shows `start` ran.
    rusqlite::Connection::open(dir.join("data/vehicoule.db"))
        .unwrap()
        .execute(
            "INSERT INTO queue_state (id, state) VALUES (1, 'not json')",
            [],
        )
        .unwrap();
    start().await.unwrap();
    let ran = diagnostics()
        .iter()
        .any(|l| l.message.contains("saved queue unreadable"));
    let _ = std::fs::remove_dir_all(&dir);

    assert!(
        matches!(early, Ok(Err(CoreError::Internal(_)))),
        "an error, not a panic: {early:?}"
    );
    assert!(ran, "the start after init still runs");
}
