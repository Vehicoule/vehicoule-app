//! Lyrics: the database first, else the routed `lyrics` capability, stored. None found is
//! stored too (an empty row), asked again once 7 days old. Offline: the database only.

use std::time::{SystemTime, UNIX_EPOCH};

use plugin_host::{CallError, Capability};

use crate::app::app;
use crate::catalog::parse_id;
use crate::error::CoreError;
use crate::library::lyrics::{self as lib, LyricsRow};
use crate::player::{query, track_and_refs};
use crate::router;

/// An empty row (none found) is this old before the plugins are asked again.
const RETRY_EMPTY_MS: i64 = 7 * 24 * 3600 * 1000;

#[derive(Debug, Clone, PartialEq)]
pub struct LyricsView {
    pub plain: Option<String>,
    pub synced: Vec<LyricLine>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct LyricLine {
    pub start_ms: u32,
    pub text: String,
}

/// `None`: no lyrics known for the track.
pub(crate) async fn lyrics(id: &str) -> Result<Option<LyricsView>, CoreError> {
    let item = parse_id(id)?;
    let app = app();
    let stored = app.db.read(move |c| lib::get(c, item)).await?;
    match &stored {
        Some(row) if view(row).is_some() || now_ms() - row.fetched_at < RETRY_EMPTY_MS => {
            return Ok(view(row));
        }
        _ if !app.is_online() => return Ok(stored.as_ref().and_then(view)),
        _ => {}
    }
    let (track, refs) = track_and_refs(item).await?;
    let found = router::first_ok(Capability::Lyrics, |p| {
        let q = query(&track, &refs, p.id());
        async move {
            let l = app.plugins.host().lyrics(&p, q).await?;
            let plain = l.plain.filter(|s| !s.trim().is_empty());
            if plain.is_none() && l.synced.is_empty() {
                return Err(CallError::NotFound);
            }
            let synced = l.synced.into_iter().map(|x| (x.start_ms, x.text)).collect();
            Ok((plain, synced))
        }
    })
    .await;
    let row = match found {
        Ok((p, (plain, synced))) => LyricsRow {
            provider: p.id().into(),
            plain,
            synced,
            fetched_at: 0,
        },
        Err(CoreError::NotFound) => LyricsRow {
            provider: String::new(),
            plain: None,
            synced: vec![],
            fetched_at: 0,
        },
        Err(e) => return Err(e),
    };
    let r = row.clone();
    app.db.write(move |tx| lib::put(tx, item, &r)).await?;
    Ok(view(&row))
}

/// `None` for an empty row.
fn view(row: &LyricsRow) -> Option<LyricsView> {
    if row.plain.is_none() && row.synced.is_empty() {
        return None;
    }
    Some(LyricsView {
        plain: row.plain.clone(),
        synced: row
            .synced
            .iter()
            .map(|(start_ms, text)| LyricLine {
                start_ms: *start_ms,
                text: text.clone(),
            })
            .collect(),
    })
}

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_millis() as i64)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::catalog::tests::{calls, setup};
    use crate::catalog::{self};

    const DAY_MS: i64 = 24 * 3600 * 1000;

    async fn track(title: &str) -> String {
        catalog::search(title).await.unwrap().tracks[0].id.clone()
    }

    /// Every stored row `days` older.
    async fn age(days: i64) {
        app()
            .db
            .write(move |tx| {
                tx.tx.execute(
                    "UPDATE lyrics SET fetched_at = fetched_at - ?1",
                    [days * DAY_MS],
                )
            })
            .await
            .unwrap();
    }

    #[test]
    fn lyrics_future_is_send() {
        fn send<T: Send>(_: T) {}
        send(lyrics("x"));
    }

    #[tokio::test]
    async fn lyrics_are_fetched_once_and_stored() {
        let (_lock, app) = setup().await;
        let id = track("sung song").await;
        let other = track("unsung song").await;
        let before = calls().await;
        let want = LyricsView {
            plain: Some("words of sung song".into()),
            synced: vec![
                LyricLine {
                    start_ms: 0,
                    text: "one".into(),
                },
                LyricLine {
                    start_ms: 1500,
                    text: "two".into(),
                },
            ],
        };
        assert_eq!(lyrics(&id).await, Ok(Some(want.clone())));
        assert_eq!(calls().await - before, 1);
        // Stored: never asked again, even years later.
        age(3650).await;
        assert_eq!(lyrics(&id).await, Ok(Some(want.clone())));
        assert_eq!(calls().await - before, 1);
        let item = parse_id(&id).unwrap();
        let row = app.db.read(move |c| lib::get(c, item)).await.unwrap();
        assert_eq!(row.unwrap().provider, "fake");
        // Offline: the database only.
        app.set_online(false);
        assert_eq!(lyrics(&id).await, Ok(Some(want)));
        assert_eq!(lyrics(&other).await, Ok(None));
        assert_eq!(calls().await - before, 1);
        let item = parse_id(&other).unwrap();
        assert_eq!(app.db.read(move |c| lib::get(c, item)).await, Ok(None));
        // Malformed id: a bug, not a miss.
        assert!(matches!(lyrics("nope").await, Err(CoreError::Internal(_))));
    }

    #[tokio::test]
    async fn missing_lyrics_are_not_refetched_for_7_days() {
        let (_lock, app) = setup().await;
        let id = track("instrumental piece").await;
        let before = calls().await;
        // Both plugins asked, none has any: an empty row is stored.
        assert_eq!(lyrics(&id).await, Ok(None));
        assert_eq!(calls().await - before, 2);
        let item = parse_id(&id).unwrap();
        let row = app.db.read(move |c| lib::get(c, item)).await.unwrap();
        let row = row.unwrap();
        assert_eq!((row.plain, row.synced.len()), (None, 0));
        // Not asked again before 7 days.
        assert_eq!(lyrics(&id).await, Ok(None));
        age(6).await;
        assert_eq!(lyrics(&id).await, Ok(None));
        assert_eq!(calls().await - before, 2);
        // Older: asked again (and stamped anew).
        age(2).await;
        assert_eq!(lyrics(&id).await, Ok(None));
        assert_eq!(calls().await - before, 4);
        assert_eq!(lyrics(&id).await, Ok(None));
        assert_eq!(calls().await - before, 4);
        // Old but offline: no call.
        age(8).await;
        app.set_online(false);
        assert_eq!(lyrics(&id).await, Ok(None));
        assert_eq!(calls().await - before, 4);
        // A network failure is told, nothing stored over the old row.
        app.set_online(true);
        crate::catalog::tests::set_mode("fake", "network").await;
        assert_eq!(lyrics(&id).await, Err(CoreError::Network));
        crate::catalog::tests::set_mode("fake", "").await;
        assert_eq!(lyrics(&id).await, Ok(None));
        assert_eq!(calls().await - before, 7);
    }
}
