//! Artwork files on disk, one per URL, the oldest (mtime) pruned past `max_bytes`.

use std::io::ErrorKind;
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::{Duration, SystemTime};

use sha2::{Digest, Sha256};

use crate::StreamError;

/// Over this, a URL a plugin returned is not an image we want.
const MAX_IMAGE_BYTES: usize = 16 << 20;
/// A `.tmp` older than this was left by a crash, not a download in progress.
const ORPHAN_TMP_AGE: Duration = Duration::from_secs(60);

#[derive(Debug, Clone)]
pub struct ArtworkCache {
    dir: PathBuf,
    max_bytes: u64,
    /// A background prune is running (shared by clones).
    pruning: Arc<AtomicBool>,
}

impl ArtworkCache {
    pub fn new(dir: PathBuf, max_bytes: u64) -> Self {
        ArtworkCache {
            dir,
            max_bytes,
            pruning: Arc::default(),
        }
    }

    /// The cached file for `url`, downloaded with `client` on a miss. A hit refreshes the
    /// file's mtime, so `prune` drops the least recently used first.
    // ponytail: two concurrent misses of one URL both download it (atomic rename, same bytes)
    pub async fn file(
        &self,
        client: &reqwest::Client,
        url: &reqwest::Url,
    ) -> Result<PathBuf, StreamError> {
        let name: String = Sha256::digest(url.as_str().as_bytes())
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect();
        let path = self.dir.join(&name);
        if let Ok(f) = std::fs::File::options().write(true).open(&path) {
            let _ = f.set_modified(SystemTime::now());
            return Ok(path);
        }
        let mut resp = client.get(url.clone()).send().await?;
        if !resp.status().is_success() {
            return Err(StreamError::Http(resp.status().as_u16()));
        }
        if resp.content_length().unwrap_or(0) > MAX_IMAGE_BYTES as u64 {
            return Err(StreamError::TooLarge);
        }
        let mut body = Vec::new();
        while let Some(chunk) = resp.chunk().await? {
            body.extend_from_slice(&chunk);
            if body.len() > MAX_IMAGE_BYTES {
                return Err(StreamError::TooLarge);
            }
        }
        tokio::fs::create_dir_all(&self.dir).await?;
        static NEXT: AtomicU64 = AtomicU64::new(0);
        let tmp = self.dir.join(format!(
            "{name}.{}.tmp",
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        tokio::fs::write(&tmp, &body).await?;
        tokio::fs::rename(&tmp, &path).await?;
        // In the background, one at a time; best effort: an unpruned cache only grows until
        // the next miss.
        if !self.pruning.swap(true, Ordering::AcqRel) {
            let me = self.clone();
            tokio::task::spawn_blocking(move || {
                let _ = me.prune();
                me.pruning.store(false, Ordering::Release);
            });
        }
        Ok(path)
    }

    /// Deletes the oldest files (mtime) until the directory fits in `max_bytes`. A `.tmp`
    /// (download being written) counts but stays, unless a crash left it: over a minute old,
    /// it goes. Files another prune removed meanwhile are skipped.
    pub fn prune(&self) -> std::io::Result<()> {
        let gone = |r: std::io::Result<()>| match r {
            Err(e) if e.kind() != ErrorKind::NotFound => Err(e),
            _ => Ok(()),
        };
        let now = SystemTime::now();
        let mut files = Vec::new();
        let mut total = 0;
        for entry in std::fs::read_dir(&self.dir)? {
            let entry = entry?;
            let path = entry.path();
            let meta = match entry.metadata() {
                Ok(m) if m.is_file() => m,
                Ok(_) => continue,
                Err(e) if e.kind() == ErrorKind::NotFound => continue,
                Err(e) => return Err(e),
            };
            let modified = meta.modified()?;
            if path.extension().is_some_and(|e| e == "tmp") {
                let age = now.duration_since(modified).unwrap_or_default();
                if age > ORPHAN_TMP_AGE {
                    gone(std::fs::remove_file(&path))?;
                } else {
                    total += meta.len();
                }
                continue;
            }
            total += meta.len();
            files.push((modified, meta.len(), path));
        }
        files.sort();
        for (_, len, path) in files {
            if total <= self.max_bytes {
                break;
            }
            gone(std::fs::remove_file(path))?;
            total -= len;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use wiremock::matchers::path;
    use wiremock::{Mock, MockServer, ResponseTemplate};

    use super::*;

    fn temp_dir(name: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir().join(format!("vehicoule-{name}-{nanos}"))
    }

    #[tokio::test]
    async fn artwork_is_downloaded_once() {
        let server = MockServer::start().await;
        Mock::given(path("/cover.jpg"))
            .respond_with(ResponseTemplate::new(200).set_body_bytes(b"jpeg".to_vec()))
            .expect(1)
            .mount(&server)
            .await;
        let dir = temp_dir("artwork");
        let cache = ArtworkCache::new(dir.clone(), 256 << 20);
        let (client, url) = (
            reqwest::Client::new(),
            reqwest::Url::parse(&format!("{}/cover.jpg", server.uri())).unwrap(),
        );
        let first = cache.file(&client, &url).await.unwrap();
        let second = cache.file(&client, &url).await.unwrap();
        assert_eq!(first, second);
        assert!(first.starts_with(&dir));
        assert_eq!(std::fs::read(&first).unwrap(), b"jpeg");
        // A failed download leaves nothing behind.
        Mock::given(path("/gone.jpg"))
            .respond_with(ResponseTemplate::new(404))
            .mount(&server)
            .await;
        let gone = reqwest::Url::parse(&format!("{}/gone.jpg", server.uri())).unwrap();
        assert_eq!(
            cache.file(&client, &gone).await,
            Err(StreamError::Http(404))
        );
        assert_eq!(std::fs::read_dir(&dir).unwrap().count(), 1);
        server.verify().await;
        let _ = std::fs::remove_dir_all(dir);
    }

    #[tokio::test]
    async fn a_miss_never_waits_for_a_running_prune() {
        let server = MockServer::start().await;
        Mock::given(path("/cover.jpg"))
            .respond_with(ResponseTemplate::new(200).set_body_bytes(b"jpeg".to_vec()))
            .mount(&server)
            .await;
        let dir = temp_dir("busy");
        // A 0-byte cap prunes everything; a prune already running means none is started.
        let cache = ArtworkCache::new(dir.clone(), 0);
        cache.pruning.store(true, Ordering::SeqCst);
        let url = reqwest::Url::parse(&format!("{}/cover.jpg", server.uri())).unwrap();
        let file = cache.file(&reqwest::Client::new(), &url).await.unwrap();
        tokio::time::sleep(Duration::from_millis(200)).await;
        assert!(file.exists());
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn artwork_cache_prunes_oldest() {
        let dir = temp_dir("prune");
        std::fs::create_dir_all(&dir).unwrap();
        let now = SystemTime::now();
        let files = [
            ("new", 0, 10),
            ("old", 300, 10),
            ("mid", 100, 10),
            // A crash left this one: removed. A download is writing that one: kept, counted.
            ("orphan.1.tmp", 120, 10),
            ("writing.2.tmp", 0, 5),
        ];
        for (name, age_s, len) in files {
            let p = dir.join(name);
            std::fs::write(&p, vec![0u8; len]).unwrap();
            let f = std::fs::File::options().write(true).open(&p).unwrap();
            f.set_modified(now - Duration::from_secs(age_s)).unwrap();
        }
        // 35 bytes counted over a 22-byte cap: the two oldest go.
        ArtworkCache::new(dir.clone(), 22).prune().unwrap();
        let mut left: Vec<String> = std::fs::read_dir(&dir)
            .unwrap()
            .map(|e| e.unwrap().file_name().into_string().unwrap())
            .collect();
        left.sort();
        assert_eq!(left, ["new", "writing.2.tmp"]);
        // Under the cap: nothing goes.
        ArtworkCache::new(dir.clone(), 22).prune().unwrap();
        assert_eq!(std::fs::read_dir(&dir).unwrap().count(), 2);
        let _ = std::fs::remove_dir_all(dir);
    }
}
