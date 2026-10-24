//! Installed plugins, their feeds, and the per-capability order.

use crate::app::app;
use crate::error::CoreError;
use crate::events::LibraryChanged;
use crate::home;
use crate::library::plugins as rows;
use crate::plugins::FeedPreview;
pub use crate::plugins::{FeedView, PluginView};
use crate::router;

fn changed() {
    let _ = app().events.library.send(LibraryChanged::Plugins);
}

pub async fn installed_plugins() -> Result<Vec<PluginView>, CoreError> {
    app().plugins.installed(&app().db).await
}

/// Every feed, the official one included, with its plugin count and key fingerprint.
pub async fn feeds() -> Result<Vec<FeedView>, CoreError> {
    app().plugins.feeds(&app().db).await
}

/// Without one, nothing plays.
pub async fn has_resolver() -> bool {
    router::order_of("resolve")
        .await
        .is_ok_and(|ids| !ids.is_empty())
}

/// Downloads and checks the feed's plugins, installs nothing.
pub async fn preview_feed(url: String, public_key: String) -> Result<FeedPreview, CoreError> {
    app().plugins.preview_feed(&url, &public_key).await
}

/// Online with `discover` on, the home is rebuilt in the background (`LibraryChanged::Home`
/// follows).
pub async fn add_feed(url: String, public_key: String) -> Result<(), CoreError> {
    app().plugins.add_feed(&app().db, &url, &public_key).await?;
    changed();
    home::on_plugins_changed().await;
    Ok(())
}

/// Online with `discover` on, the home is rebuilt in the background (`LibraryChanged::Home`
/// follows).
pub async fn remove_feed(url: String) -> Result<(), CoreError> {
    app().plugins.remove_feed(&app().db, &url).await?;
    changed();
    home::on_plugins_changed().await;
    Ok(())
}

/// When a plugin is installed or updated, the home is rebuilt as after `add_feed`.
pub async fn refresh_feeds() -> Result<(), CoreError> {
    let installed = app().plugins.refresh_feeds(&app().db).await?;
    changed();
    if !installed.is_empty() {
        home::on_plugins_changed().await;
    }
    Ok(())
}

/// `capability`: `search`, `suggest`, `entity`, `resolve`, `lyrics`, `radio`, `browse` or
/// `artwork`.
/// The loaded plugins it routes to, in order.
pub async fn capability_order(capability: String) -> Result<Vec<String>, CoreError> {
    router::order_of(&capability).await
}

pub async fn set_capability_order(
    capability: String,
    plugin_ids: Vec<String>,
) -> Result<(), CoreError> {
    if capability != "artwork" {
        router::capability(&capability)?;
    }
    app()
        .db
        .write(move |tx| rows::set_capability_order(tx, &capability, &plugin_ids))
        .await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::home::tests::{homes, settle, wipe};
    use crate::library::settings;

    #[tokio::test]
    async fn a_plugin_change_rebuilds_the_home() {
        let (_lock, app) = crate::catalog::tests::setup().await;
        wipe().await;
        crate::home::build(crate::plugins::now_ms()).await.unwrap();
        let mut rx = app.events.library.subscribe();
        remove_feed("https://feed.fake.test/feed.json".into())
            .await
            .unwrap();
        settle().await;
        assert_eq!(homes(&mut rx), 1);
        // Not with `discover` off.
        app.db
            .write(|tx| settings::device_set(tx, "discover", "false"))
            .await
            .unwrap();
        remove_feed("https://feed.fake.test/feed.json".into())
            .await
            .unwrap();
        settle().await;
        assert_eq!(homes(&mut rx), 0);
        wipe().await;
    }
}
