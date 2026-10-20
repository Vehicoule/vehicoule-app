//! Artwork files on disk, one per URL, the oldest (mtime) pruned past `max_bytes`.

use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::SystemTime;

use sha2::{Digest, Sha256};

use crate::StreamError;

/// Over this, a URL a plugin returned is not an image we want.
const MAX_IMAGE_BYTES: usize = 16 << 20;

#[derive(Debug, Clone)]
pub struct ArtworkCache {
    dir: PathBuf,
    max_bytes: u64,
}

impl ArtworkCache {
    pub fn new(dir: PathBuf, max_bytes: u64) -> Self {
        ArtworkCache { dir, max_bytes }
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
            return Err(StreamError::Status(resp.status().as_u16()));
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
        let me = self.clone();
        // Best effort: an unpruned cache only grows until the next download.
        let _ = tokio::task::spawn_blocking(move || me.prune()).await;
        Ok(path)
    }

    /// Deletes the oldest files (mtime) until the directory fits in `max_bytes`.
    pub fn prune(&self) -> std::io::Result<()> {
        let mut files = Vec::new();
        for entry in std::fs::read_dir(&self.dir)? {
            let entry = entry?;
            let meta = entry.metadata()?;
            if meta.is_file() && entry.path().extension().is_none_or(|e| e != "tmp") {
                files.push((meta.modified()?, meta.len(), entry.path()));
            }
        }
        let mut total: u64 = files.iter().map(|f| f.1).sum();
        files.sort();
        for (_, len, path) in files {
            if total <= self.max_bytes {
                break;
            }
            std::fs::remove_file(path)?;
            total -= len;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use std::time::{Duration, SystemTime};

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
            Err(StreamError::Status(404))
        );
        assert_eq!(std::fs::read_dir(&dir).unwrap().count(), 1);
        server.verify().await;
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn artwork_cache_prunes_oldest() {
        let dir = temp_dir("prune");
        std::fs::create_dir_all(&dir).unwrap();
        let now = SystemTime::now();
        for (name, age_s) in [("new", 0), ("old", 300), ("mid", 100)] {
            let p = dir.join(name);
            std::fs::write(&p, [0u8; 10]).unwrap();
            let f = std::fs::File::options().write(true).open(&p).unwrap();
            f.set_modified(now - Duration::from_secs(age_s)).unwrap();
        }
        // 30 bytes over a 25-byte cap: only the oldest goes.
        ArtworkCache::new(dir.clone(), 25).prune().unwrap();
        let mut left: Vec<String> = std::fs::read_dir(&dir)
            .unwrap()
            .map(|e| e.unwrap().file_name().into_string().unwrap())
            .collect();
        left.sort();
        assert_eq!(left, ["mid", "new"]);
        // Under the cap: nothing goes.
        ArtworkCache::new(dir.clone(), 25).prune().unwrap();
        assert_eq!(std::fs::read_dir(&dir).unwrap().count(), 2);
        let _ = std::fs::remove_dir_all(dir);
    }
}
