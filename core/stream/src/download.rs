//! Whole-file downloads in `Range` chunks, resumable: bytes land in `<dest>.part`, which is
//! renamed to `dest` once its size is checked. A restart (app killed, URL expired) picks up
//! at the end of the `.part`.

use std::path::{Path, PathBuf};

use reqwest::StatusCode;
use reqwest::header::{CONTENT_RANGE, RANGE};
use tokio::io::AsyncWriteExt;

use crate::StreamError;

/// Bytes asked per request.
pub const CHUNK: u64 = 2 << 20;

pub struct Fetch {
    /// `url::Url` (reqwest re-exports it).
    pub url: reqwest::Url,
    pub headers: Vec<(String, String)>,
    /// The file's size when known: a server announcing another one is a different file.
    pub expected_len: Option<u64>,
}

/// `<dest>.part`.
pub fn part_path(dest: &Path) -> PathBuf {
    let mut p = dest.as_os_str().to_owned();
    p.push(".part");
    PathBuf::from(p)
}

/// Resumes from `<dest>.part`, fetches by `Range` chunks, checks the final size, then renames.
/// `progress(done, total)` follows every write. A size mismatch deletes the `.part`: its bytes
/// can't be trusted for a later resume.
pub async fn download(
    client: &reqwest::Client,
    f: &Fetch,
    dest: &Path,
    progress: &mut (dyn FnMut(u64, Option<u64>) + Send),
) -> Result<u64, StreamError> {
    let part = part_path(dest);
    let mut file = tokio::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&part)
        .await?;
    let mut done = file.metadata().await?.len();
    let mut total = f.expected_len;
    let result = async {
        loop {
            if total.is_some_and(|t| done >= t) {
                break;
            }
            let end = done + CHUNK - 1;
            let mut req = client
                .get(f.url.clone())
                .header(RANGE, format!("bytes={done}-{end}"));
            for (k, v) in &f.headers {
                req = req.header(k, v);
            }
            let mut resp = req.send().await?;
            let range = resp
                .headers()
                .get(CONTENT_RANGE)
                .and_then(|v| v.to_str().ok())
                .and_then(content_range);
            match resp.status() {
                StatusCode::PARTIAL_CONTENT => {
                    let (start, len) = range.ok_or(StreamError::Http(206))?;
                    if start != Some(done) {
                        return Err(StreamError::Http(206));
                    }
                    if let (Some(e), Some(l)) = (total, len)
                        && e != l
                    {
                        return Err(StreamError::SizeMismatch {
                            expected: e,
                            got: l,
                        });
                    }
                    total = total.or(len);
                }
                // Range ignored: the whole file, from the start.
                StatusCode::OK => {
                    file.set_len(0).await?;
                    done = 0;
                    total = total.or(resp.content_length());
                }
                // Nothing left to send: the `.part` was already whole (killed before the rename).
                StatusCode::RANGE_NOT_SATISFIABLE
                    if range.and_then(|(_, len)| len) == Some(done) =>
                {
                    total = Some(done);
                    break;
                }
                s => return Err(StreamError::Http(s.as_u16())),
            }
            let whole = resp.status() == StatusCode::OK;
            let mut got = 0;
            while let Some(bytes) = resp.chunk().await? {
                file.write_all(&bytes).await?;
                got += bytes.len() as u64;
                done += bytes.len() as u64;
                progress(done, total);
            }
            file.flush().await?;
            // A short chunk is the end of the file.
            if whole || got < CHUNK {
                break;
            }
        }
        file.sync_all().await?;
        Ok(())
    }
    .await;
    drop(file);
    if let Err(e) = result {
        if matches!(e, StreamError::SizeMismatch { .. }) {
            let _ = tokio::fs::remove_file(&part).await;
        }
        return Err(e);
    }
    if let Some(expected) = total.filter(|t| *t != done) {
        let _ = tokio::fs::remove_file(&part).await;
        return Err(StreamError::SizeMismatch {
            expected,
            got: done,
        });
    }
    tokio::fs::rename(&part, dest).await?;
    Ok(done)
}

/// `bytes a-b/len`, `bytes */len`, `bytes a-b/*` → (a, len).
fn content_range(v: &str) -> Option<(Option<u64>, Option<u64>)> {
    let (range, len) = v.strip_prefix("bytes ")?.split_once('/')?;
    let start = match range {
        "*" => None,
        r => Some(r.split_once('-')?.0.parse().ok()?),
    };
    Some((start, len.parse().ok()))
}

#[cfg(test)]
mod tests {
    use std::sync::{Arc, Mutex};
    use std::time::SystemTime;

    use wiremock::matchers::path;
    use wiremock::{Mock, MockServer, Request, Respond, ResponseTemplate};

    use super::*;

    /// Serves `body` by ranges, announcing `claimed` as the file's size; records the `Range`
    /// headers it got.
    struct Ranges {
        body: Arc<Vec<u8>>,
        claimed: u64,
        seen: Arc<Mutex<Vec<String>>>,
    }

    impl Respond for Ranges {
        fn respond(&self, req: &Request) -> ResponseTemplate {
            let range = req
                .headers
                .get("range")
                .unwrap()
                .to_str()
                .unwrap()
                .to_string();
            self.seen.lock().unwrap().push(range.clone());
            let (a, b) = range
                .strip_prefix("bytes=")
                .unwrap()
                .split_once('-')
                .unwrap();
            let a: usize = a.parse().unwrap();
            let b = b.parse::<usize>().unwrap().min(self.body.len() - 1);
            ResponseTemplate::new(206)
                .insert_header("content-range", format!("bytes {a}-{b}/{}", self.claimed))
                .set_body_bytes(self.body[a..=b].to_vec())
        }
    }

    fn body(len: usize) -> Arc<Vec<u8>> {
        Arc::new((0..len).map(|i| (i % 251) as u8).collect())
    }

    fn temp_dir(name: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("vehicoule-{name}-{nanos}"));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    async fn serve(body: Arc<Vec<u8>>, claimed: u64) -> (MockServer, Arc<Mutex<Vec<String>>>) {
        let server = MockServer::start().await;
        let seen = Arc::new(Mutex::new(Vec::new()));
        Mock::given(path("/song"))
            .respond_with(Ranges {
                body,
                claimed,
                seen: seen.clone(),
            })
            .mount(&server)
            .await;
        (server, seen)
    }

    fn fetch(server: &MockServer) -> Fetch {
        Fetch {
            url: format!("{}/song", server.uri()).parse().unwrap(),
            headers: vec![("x-token".into(), "t".into())],
            expected_len: None,
        }
    }

    #[tokio::test]
    async fn download_fetches_in_range_chunks() {
        let body = body(5 << 20);
        let (server, seen) = serve(body.clone(), 5 << 20).await;
        let dir = temp_dir("dl-chunks");
        let dest = dir.join("a.webm");
        let mut last = (0, None);
        let n = download(
            &reqwest::Client::new(),
            &fetch(&server),
            &dest,
            &mut |d, t| last = (d, t),
        )
        .await
        .unwrap();
        assert_eq!(n, 5 << 20);
        assert_eq!(last, (5 << 20, Some(5 << 20)));
        assert_eq!(
            *seen.lock().unwrap(),
            [
                "bytes=0-2097151",
                "bytes=2097152-4194303",
                "bytes=4194304-6291455"
            ]
        );
        assert_eq!(std::fs::read(&dest).unwrap(), *body);
        assert!(!part_path(&dest).exists());
        // The plugin's headers go with every request.
        let reqs = server.received_requests().await.unwrap();
        assert!(
            reqs.iter()
                .all(|r| r.headers.get("x-token").unwrap() == "t")
        );
        let _ = std::fs::remove_dir_all(dir);
    }

    #[tokio::test]
    async fn download_resumes_from_part_file() {
        let body = body(5 << 20);
        let (server, seen) = serve(body.clone(), 5 << 20).await;
        let dir = temp_dir("dl-resume");
        let dest = dir.join("a.m4a");
        std::fs::write(part_path(&dest), &body[..3 << 20]).unwrap();
        let n = download(
            &reqwest::Client::new(),
            &fetch(&server),
            &dest,
            &mut |_, _| {},
        )
        .await
        .unwrap();
        assert_eq!(n, 5 << 20);
        let seen = seen.lock().unwrap().clone();
        assert_eq!(seen.len(), 1);
        assert!(seen[0].starts_with("bytes=3145728-"), "{seen:?}");
        assert_eq!(std::fs::read(&dest).unwrap(), *body);

        // A `.part` already whole (killed before the rename): a 416 finishes it.
        let dest = dir.join("b.m4a");
        std::fs::write(part_path(&dest), &body[..]).unwrap();
        let server = MockServer::start().await;
        Mock::given(path("/song"))
            .respond_with(
                ResponseTemplate::new(416).insert_header("content-range", "bytes */5242880"),
            )
            .mount(&server)
            .await;
        let n = download(
            &reqwest::Client::new(),
            &fetch(&server),
            &dest,
            &mut |_, _| {},
        )
        .await
        .unwrap();
        assert_eq!(n, 5 << 20);
        assert_eq!(std::fs::read(&dest).unwrap(), *body);
        let _ = std::fs::remove_dir_all(dir);
    }

    #[tokio::test]
    async fn short_body_is_size_mismatch() {
        // The server announces 6 MiB and ends at 5.
        let (server, _) = serve(body(5 << 20), 6 << 20).await;
        let dir = temp_dir("dl-short");
        let dest = dir.join("a.webm");
        let client = reqwest::Client::new();
        let r = download(&client, &fetch(&server), &dest, &mut |_, _| {}).await;
        assert_eq!(
            r,
            Err(StreamError::SizeMismatch {
                expected: 6 << 20,
                got: 5 << 20
            })
        );
        assert!(!dest.exists());
        assert!(!part_path(&dest).exists());
        // A file of another size than the one expected: refused before any byte is written.
        let (server, _) = serve(body(5 << 20), 5 << 20).await;
        let f = Fetch {
            expected_len: Some(4 << 20),
            ..fetch(&server)
        };
        let r = download(&client, &f, &dest, &mut |_, _| {}).await;
        assert!(matches!(r, Err(StreamError::SizeMismatch { .. })), "{r:?}");
        assert!(!part_path(&dest).exists());
        // An error status is kept as such, the `.part` left for a resume.
        let server = MockServer::start().await;
        Mock::given(path("/song"))
            .respond_with(ResponseTemplate::new(403))
            .mount(&server)
            .await;
        std::fs::write(part_path(&dest), b"abc").unwrap();
        let r = download(&client, &fetch(&server), &dest, &mut |_, _| {}).await;
        assert_eq!(r, Err(StreamError::Http(403)));
        assert_eq!(std::fs::read(part_path(&dest)).unwrap(), b"abc");
        let _ = std::fs::remove_dir_all(dir);
    }
}
