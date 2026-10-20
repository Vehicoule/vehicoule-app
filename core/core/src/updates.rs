//! App updates, from the GitHub releases behind `updates.vehicoule.app`.

use std::io::Write;
use std::path::Path;

use reqwest::{Client, Response};
use semver::Version;
use serde::Deserialize;
use sha2::{Digest, Sha256};

use crate::app::{Platform, app};
use crate::error::CoreError;
use crate::events::Notice;
use crate::library::settings;
use crate::logs;

/// Redirects to `https://api.github.com/repos/Vehicoule/vehicoule/releases`.
pub(crate) const UPDATES_URL: &str = "https://updates.vehicoule.app/releases";
/// `settings_device` key: when the last check succeeded, unix ms.
const CHECKED_AT: &str = "updates_checked_at";
const CHECK_EVERY_MS: i64 = 24 * 3600 * 1000;
const MAX_APK_BYTES: u64 = 512 << 20;

#[derive(Debug, Clone, PartialEq)]
pub struct UpdateInfo {
    pub version: String,
    pub notes: String,
    pub page_url: String,
    /// The current platform's asset; only Android has one (macOS gets `page_url` only).
    pub asset_url: Option<String>,
    pub sha256_url: Option<String>,
}

#[derive(Deserialize)]
struct Release {
    tag_name: String,
    #[serde(default)]
    body: Option<String>,
    html_url: String,
    #[serde(default)]
    draft: bool,
    #[serde(default)]
    prerelease: bool,
    #[serde(default)]
    assets: Vec<Asset>,
}

#[derive(Deserialize)]
struct Asset {
    name: String,
    browser_download_url: String,
}

fn parse(v: &str) -> Option<Version> {
    Version::parse(v.trim().trim_start_matches('v')).ok()
}

fn apk_name(version: &Version) -> String {
    format!("vehicoule-{version}-android-arm64-v8a.apk")
}

/// The newest release above `current`: no drafts, and pre-releases (flagged, or with a
/// pre-release version) only when `current` is one.
pub(crate) fn pick_release(
    releases_json: &[u8],
    current: &str,
    platform: Platform,
) -> Option<UpdateInfo> {
    let current = parse(current)?;
    let releases: Vec<Release> = serde_json::from_slice(releases_json).ok()?;
    let (version, release) = releases
        .into_iter()
        .filter(|r| !r.draft)
        .filter_map(|r| Some((parse(&r.tag_name)?, r)))
        .filter(|(v, r)| (!r.prerelease && v.pre.is_empty()) || !current.pre.is_empty())
        .filter(|(v, _)| *v > current)
        .max_by(|a, b| a.0.cmp(&b.0))?;
    let url = |name: &str| {
        let asset = release.assets.iter().find(|a| a.name == name);
        asset.map(|a| a.browser_download_url.clone())
    };
    // Never an asset without its checksum.
    let (asset_url, sha256_url) = match platform {
        Platform::Android => {
            let apk = apk_name(&version);
            match (url(&apk), url(&format!("{apk}.sha256"))) {
                (Some(a), Some(s)) => (Some(a), Some(s)),
                _ => (None, None),
            }
        }
        _ => (None, None),
    };
    Some(UpdateInfo {
        version: version.to_string(),
        notes: release.body.unwrap_or_default(),
        page_url: release.html_url,
        asset_url,
        sha256_url,
    })
}

/// Follows the redirect to GitHub; https only outside tests (wiremock).
fn client() -> Result<Client, CoreError> {
    Client::builder()
        .https_only(!cfg!(test))
        // GitHub's API refuses requests without one.
        .user_agent("vehicoule-updates")
        .connect_timeout(std::time::Duration::from_secs(15))
        .read_timeout(std::time::Duration::from_secs(30))
        .build()
        .map_err(|_| CoreError::Network)
}

fn checked(resp: Response) -> Result<Response, CoreError> {
    match resp.status().as_u16() {
        200..=299 => Ok(resp),
        404 | 410 => Err(CoreError::NotFound),
        // GitHub answers 403 when its rate limit is hit.
        403 | 429 => Err(CoreError::RateLimited),
        _ => Err(CoreError::Network),
    }
}

async fn get(client: &Client, url: &str) -> Result<Response, CoreError> {
    let resp = client
        .get(url)
        .header(reqwest::header::ACCEPT, "application/vnd.github+json")
        .send()
        .await
        .map_err(|_| CoreError::Network)?;
    checked(resp)
}

pub(crate) async fn check_updates(
    current: &str,
    platform: Platform,
) -> Result<Option<UpdateInfo>, CoreError> {
    check_at(UPDATES_URL, current, platform).await
}

async fn check_at(
    url: &str,
    current: &str,
    platform: Platform,
) -> Result<Option<UpdateInfo>, CoreError> {
    let body = get(&client()?, url).await?.bytes().await;
    Ok(pick_release(
        &body.map_err(|_| CoreError::Network)?,
        current,
        platform,
    ))
}

/// At most once per 24 h (after a successful check), never offline. Called by Dart after the
/// first frame, then by `App`'s timer; a newer version is also sent as a `Notice`.
pub(crate) async fn check_if_due() -> Result<Option<UpdateInfo>, CoreError> {
    let app = app();
    if !app.is_online() {
        return Ok(None);
    }
    let last = app.db.read(|c| settings::device_get(c, CHECKED_AT)).await?;
    let last = last.and_then(|v| v.parse::<i64>().ok()).unwrap_or(0);
    let now = crate::plugins::now_ms();
    if (now - last).abs() < CHECK_EVERY_MS {
        return Ok(None);
    }
    let info = check_updates(&app.cfg.app_version, app.cfg.platform).await?;
    app.db
        .write(move |tx| settings::device_set(tx, CHECKED_AT, &now.to_string()))
        .await?;
    if let Some(i) = &info {
        let _ = app.events.notices.send(Notice::UpdateAvailable {
            version: i.version.clone(),
        });
    }
    Ok(info)
}

/// Downloads the APK into `<cache_dir>/updates` (earlier ones removed) and returns its path
/// once its sha256 matches; on any failure nothing is left behind.
pub(crate) async fn download_update(info: &UpdateInfo) -> Result<String, CoreError> {
    let (Some(asset), Some(sha_url)) = (&info.asset_url, &info.sha256_url) else {
        return Err(CoreError::NotFound);
    };
    // `info` comes back from Dart: the file name is rebuilt from a parsed version only.
    let version = parse(&info.version).ok_or(CoreError::NotFound)?;
    let dir = Path::new(&app().cfg.cache_dir).join("updates");
    let io = |e: std::io::Error| CoreError::Internal(e.to_string());
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).map_err(io)?;
    let dest = dir.join(apk_name(&version));
    let part = dir.join(format!("{}.part", apk_name(&version)));
    let client = client()?;
    let result = async {
        let want = get(&client, sha_url).await?.text().await;
        let want = want.map_err(|_| CoreError::Network)?;
        let want = want
            .split_whitespace()
            .next()
            .unwrap_or("")
            .to_ascii_lowercase();
        let got = fetch(&client, asset, &part).await?;
        if got != want {
            logs::push("warn", "updates", "sha256 mismatch: download refused");
            return Err(CoreError::Network);
        }
        std::fs::rename(&part, &dest).map_err(io)
    }
    .await;
    if result.is_err() {
        let _ = std::fs::remove_file(&part);
    }
    result.map(|()| dest.display().to_string())
}

/// Writes the body to `part` and returns its sha256 (lowercase hex).
// ponytail: std writes of each chunk on the runtime's worker; tokio::fs if APKs grow big
async fn fetch(client: &Client, url: &str, part: &Path) -> Result<String, CoreError> {
    let mut resp = get(client, url).await?;
    let mut file = std::fs::File::create(part).map_err(|e| CoreError::Internal(e.to_string()))?;
    let mut hash = Sha256::new();
    let mut len = 0u64;
    while let Some(chunk) = resp.chunk().await.map_err(|_| CoreError::Network)? {
        len += chunk.len() as u64;
        if len > MAX_APK_BYTES {
            return Err(CoreError::Network);
        }
        hash.update(&chunk);
        file.write_all(&chunk)
            .map_err(|e| CoreError::Internal(e.to_string()))?;
    }
    file.sync_all()
        .map_err(|e| CoreError::Internal(e.to_string()))?;
    Ok(format!("{:x}", hash.finalize()))
}

#[cfg(test)]
mod tests {
    use wiremock::matchers::{method, path};
    use wiremock::{Mock, MockServer, ResponseTemplate};

    use super::*;

    fn fixture(base: &str) -> Vec<u8> {
        let assets = |v: &str| {
            let apk = format!("vehicoule-{v}-android-arm64-v8a.apk");
            let dmg = format!("vehicoule-{v}-macos.dmg");
            serde_json::json!([
                { "name": apk, "browser_download_url": format!("{base}/{apk}") },
                { "name": format!("{apk}.sha256"), "browser_download_url": format!("{base}/{apk}.sha256") },
                { "name": dmg, "browser_download_url": format!("{base}/{dmg}") },
                { "name": format!("{dmg}.sha256"), "browser_download_url": format!("{base}/{dmg}.sha256") },
            ])
        };
        let release = |tag: &str, draft: bool, pre: bool| {
            serde_json::json!({
                "tag_name": tag, "name": tag, "body": format!("notes {tag}"),
                "html_url": format!("https://github.com/Vehicoule/vehicoule/releases/tag/{tag}"),
                "draft": draft, "prerelease": pre,
                "assets": assets(tag.trim_start_matches('v')),
            })
        };
        serde_json::to_vec(&serde_json::json!([
            release("v0.3.0", true, false),
            release("v0.2.1-beta.1", false, true),
            release("v0.2.0", false, false),
            release("v0.1.0", false, false),
        ]))
        .unwrap()
    }

    #[test]
    fn newer_stable_release_is_picked() {
        let json = fixture("https://dl.test");
        let info = pick_release(&json, "0.1.0", Platform::Android).unwrap();
        assert_eq!(
            info,
            UpdateInfo {
                version: "0.2.0".into(),
                notes: "notes v0.2.0".into(),
                page_url: "https://github.com/Vehicoule/vehicoule/releases/tag/v0.2.0".into(),
                asset_url: Some("https://dl.test/vehicoule-0.2.0-android-arm64-v8a.apk".into()),
                sha256_url: Some(
                    "https://dl.test/vehicoule-0.2.0-android-arm64-v8a.apk.sha256".into()
                ),
            }
        );
        assert_eq!(pick_release(&json, "0.2.0", Platform::Android), None);
        assert_eq!(
            pick_release(&json, "not a version", Platform::Android),
            None
        );
        assert_eq!(pick_release(b"{oops", "0.1.0", Platform::Android), None);
    }

    #[test]
    fn prerelease_offered_only_to_prerelease_users() {
        let json = fixture("https://dl.test");
        let pick = |current| pick_release(&json, current, Platform::Android).map(|i| i.version);
        assert_eq!(pick("0.2.0-beta.0").as_deref(), Some("0.2.1-beta.1"));
        assert_eq!(pick("0.1.0").as_deref(), Some("0.2.0"));
        // A pre-release tag not flagged as one is still a pre-release.
        let unflagged = br#"[{"tag_name":"v0.9.0-rc.1","html_url":"https://p","draft":false,"prerelease":false}]"#;
        assert_eq!(pick_release(unflagged, "0.1.0", Platform::Android), None);
    }

    #[test]
    fn macos_gets_page_url_only() {
        let json = fixture("https://dl.test");
        let info = pick_release(&json, "0.1.0", Platform::MacOs).unwrap();
        assert_eq!(info.version, "0.2.0");
        assert_eq!(info.asset_url, None);
        assert_eq!(info.sha256_url, None);
        assert!(info.page_url.ends_with("/tag/v0.2.0"));
    }

    #[tokio::test]
    async fn check_follows_the_redirect() {
        let server = MockServer::start().await;
        let base = server.uri();
        Mock::given(method("GET"))
            .and(path("/releases"))
            .respond_with(
                ResponseTemplate::new(302).insert_header("location", format!("{base}/api")),
            )
            .mount(&server)
            .await;
        Mock::given(method("GET"))
            .and(path("/api"))
            .respond_with(ResponseTemplate::new(200).set_body_bytes(fixture(&base)))
            .mount(&server)
            .await;
        let info = check_at(&format!("{base}/releases"), "0.1.0", Platform::Android)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(info.version, "0.2.0");
        let missing = check_at(&format!("{base}/nothing"), "0.1.0", Platform::Android).await;
        assert_eq!(missing, Err(CoreError::NotFound));
    }

    #[tokio::test]
    async fn update_with_bad_sha256_is_refused() {
        crate::app::test_app();
        let server = MockServer::start().await;
        let base = server.uri();
        let apk = vec![7u8; 300_000];
        let apk_path = "/vehicoule-0.2.0-android-arm64-v8a.apk";
        Mock::given(method("GET"))
            .and(path(apk_path))
            .respond_with(ResponseTemplate::new(200).set_body_bytes(apk.clone()))
            .mount(&server)
            .await;
        let sha = |body: String| {
            Mock::given(method("GET"))
                .and(path(format!("{apk_path}.sha256")))
                .respond_with(ResponseTemplate::new(200).set_body_string(body))
        };
        sha(format!(
            "{}  vehicoule-0.2.0-android-arm64-v8a.apk\n",
            "0".repeat(64)
        ))
        .up_to_n_times(1)
        .mount(&server)
        .await;
        let info = pick_release(&fixture(&base), "0.1.0", Platform::Android).unwrap();
        let dir = Path::new(&app().cfg.cache_dir).join("updates");

        assert_eq!(download_update(&info).await, Err(CoreError::Network));
        let left: Vec<_> = std::fs::read_dir(&dir).unwrap().collect();
        assert!(left.is_empty(), "unverified file left behind: {left:?}");

        let good = format!("{:x}", Sha256::digest(&apk));
        sha(format!(
            "{}  vehicoule-0.2.0-android-arm64-v8a.apk\n",
            good.to_uppercase()
        ))
        .mount(&server)
        .await;
        let path = download_update(&info).await.unwrap();
        assert_eq!(
            Path::new(&path),
            dir.join("vehicoule-0.2.0-android-arm64-v8a.apk")
        );
        assert_eq!(std::fs::read(&path).unwrap(), apk);
        assert_eq!(std::fs::read_dir(&dir).unwrap().count(), 1);

        // No asset (macOS), or a version that is not one: nothing is fetched.
        let mac = UpdateInfo {
            asset_url: None,
            ..info.clone()
        };
        assert_eq!(download_update(&mac).await, Err(CoreError::NotFound));
        let bad = UpdateInfo {
            version: "../../x".into(),
            ..info
        };
        assert_eq!(download_update(&bad).await, Err(CoreError::NotFound));
    }
}
