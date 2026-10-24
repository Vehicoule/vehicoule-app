//! Settings: `quality`, `normalize_volume`, telemetry, `discover` on this device; `radio`
//! shared with the user's other devices. Stored as text: booleans are on unless `false`.
//! Interface preferences (`ui.*`) live on this device too, never read by the core.

use crate::api::app::{TELEMETRY, set_telemetry};
use crate::app::app;
use crate::error::CoreError;
use crate::library::settings as rows;

/// Device setting, on unless `false`: the home feed reads it too.
pub(crate) const DISCOVER: &str = "discover";

#[derive(Debug, Clone, PartialEq)]
pub struct Settings {
    pub quality: Quality,
    pub normalize_volume: bool,
    pub radio: bool,
    /// `false` until chosen (onboarding).
    pub telemetry: bool,
    /// The home feed asks the plugins (discovery, mixes, releases, chart).
    pub discover: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Quality {
    Low,
    Normal,
    High,
}

impl Quality {
    fn as_str(self) -> &'static str {
        match self {
            Quality::Low => "low",
            Quality::Normal => "normal",
            Quality::High => "high",
        }
    }
}

/// Defaults: normal quality, normalisation, radio and discover on, telemetry off.
fn stored(
    quality: Option<String>,
    normalize: Option<String>,
    radio: Option<String>,
    telemetry: Option<String>,
    discover: Option<String>,
) -> Settings {
    let on = |v: Option<String>| v.as_deref() != Some("false");
    Settings {
        quality: [Quality::Low, Quality::High]
            .into_iter()
            .find(|q| quality.as_deref() == Some(q.as_str()))
            .unwrap_or(Quality::Normal),
        normalize_volume: on(normalize),
        radio: on(radio),
        telemetry: telemetry.as_deref() == Some("true"),
        discover: on(discover),
    }
}

pub async fn settings() -> Result<Settings, CoreError> {
    Ok(app()
        .db
        .read(|c| {
            Ok(stored(
                rows::device_get(c, "quality")?,
                rows::device_get(c, "normalize_volume")?,
                rows::shared_get(c, "radio")?,
                rows::device_get(c, TELEMETRY)?,
                rows::device_get(c, DISCOVER)?,
            ))
        })
        .await?)
}

/// Telemetry is stored, and starts or stops, only when it changes: an unchosen one stays
/// unchosen (`onboarding().telemetry == None`) until turned on or onboarding chooses.
pub async fn set_settings(s: Settings) -> Result<(), CoreError> {
    let was = settings().await?.telemetry;
    let on = s.telemetry;
    app()
        .db
        .write(move |tx| {
            rows::device_set(tx, "quality", s.quality.as_str())?;
            rows::device_set(tx, "normalize_volume", &s.normalize_volume.to_string())?;
            rows::shared_set(tx, "radio", &s.radio.to_string())?;
            rows::device_set(tx, DISCOVER, &s.discover.to_string())?;
            match on != was {
                true => rows::device_set(tx, TELEMETRY, &on.to_string()),
                false => Ok(()),
            }
        })
        .await?;
    if on != was {
        set_telemetry(on);
    }
    Ok(())
}

/// Only `ui.*` keys: any other is `NotFound`.
fn ui_key(key: &str) -> Result<(), CoreError> {
    match key.starts_with("ui.") {
        true => Ok(()),
        false => Err(CoreError::NotFound),
    }
}

/// An interface preference (`ui.theme`, `ui.sort.<list>`...), stored for Dart as given.
pub async fn ui_pref(key: String) -> Result<Option<String>, CoreError> {
    ui_key(&key)?;
    Ok(app().db.read(move |c| rows::device_get(c, &key)).await?)
}

/// `None` removes it.
pub async fn set_ui_pref(key: String, value: Option<String>) -> Result<(), CoreError> {
    ui_key(&key)?;
    app()
        .db
        .write(move |tx| match &value {
            Some(v) => rows::device_set(tx, &key, v),
            None => rows::device_delete(tx, &key),
        })
        .await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unset_settings_take_the_defaults() {
        let want = Settings {
            quality: Quality::Normal,
            normalize_volume: true,
            radio: true,
            telemetry: false,
            discover: true,
        };
        assert_eq!(stored(None, None, None, None, None), want);
        let s = |v: &str| Some(v.to_string());
        assert_eq!(stored(s("bogus"), s("x"), None, s("x"), s("x")), want);
    }

    #[tokio::test]
    async fn settings_roundtrip_in_the_formats_the_player_reads() {
        // Shared App and settings: take turns with the player tests.
        let (_turn, app) = crate::catalog::tests::setup().await;
        let s = Settings {
            quality: Quality::Low,
            normalize_volume: false,
            radio: false,
            telemetry: false,
            discover: false,
        };
        set_settings(s.clone()).await.unwrap();
        assert_eq!(settings().await.unwrap(), s);
        let quality = app.db.read(|c| rows::device_get(c, "quality")).await;
        assert_eq!(quality.unwrap().as_deref(), Some("low"));
        let defaults = stored(None, None, None, None, None);
        set_settings(defaults.clone()).await.unwrap();
        assert_eq!(settings().await.unwrap(), defaults);
    }

    #[tokio::test]
    async fn an_unchosen_telemetry_stays_unchosen() {
        let (_turn, app) = crate::catalog::tests::setup().await;
        let forget = |app: &'static crate::app::App| {
            app.db.write(|tx| {
                tx.tx
                    .execute("DELETE FROM settings_device WHERE key = ?1", [TELEMETRY])?;
                Ok(())
            })
        };
        forget(app).await.unwrap();
        set_settings(stored(None, None, None, None, None))
            .await
            .unwrap();
        assert_eq!(crate::api::app::onboarding().unwrap().telemetry, None);
        forget(app).await.unwrap();
    }

    #[test]
    fn settings_discover_defaults_on() {
        assert!(stored(None, None, None, None, None).discover);
        let off = stored(None, None, None, None, Some("false".into()));
        assert!(!off.discover);
    }

    #[tokio::test]
    async fn ui_pref_round_trips_and_rejects_other_keys() {
        let (_turn, _) = crate::catalog::tests::setup().await;
        set_ui_pref("ui.theme".into(), Some("dark".into()))
            .await
            .unwrap();
        assert_eq!(
            ui_pref("ui.theme".into()).await.unwrap().as_deref(),
            Some("dark")
        );
        set_ui_pref("ui.theme".into(), None).await.unwrap();
        assert_eq!(ui_pref("ui.theme".into()).await.unwrap(), None);
        assert_eq!(ui_pref("quality".into()).await, Err(CoreError::NotFound));
        let set = set_ui_pref("quality".into(), Some("low".into())).await;
        assert_eq!(set, Err(CoreError::NotFound));
        assert_eq!(
            set_ui_pref("quality".into(), None).await,
            Err(CoreError::NotFound)
        );
    }
}
