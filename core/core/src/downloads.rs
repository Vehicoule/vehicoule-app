//! Downloads. The `downloads` table is the queue: at most 2 run at once, each resolved at
//! quality `high` and fetched with the resolving plugin's client into
//! `<downloads_dir>/<item-id>.<webm|m4a>` (bytes in a `.part` next to it until complete).
//! An expired URL (403) is resolved once more and the download picks up at the same byte.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{LazyLock, Mutex, PoisonError};
use std::time::Duration;

use tokio::sync::Semaphore;
use tokio::task::JoinHandle;
use tokio::time::Instant;
use vehicoule_stream::StreamError;
use vehicoule_stream::download::{self as stream, Fetch, part_path};

use crate::app::app;
use crate::catalog::{artwork_file, parse_id};
use crate::error::CoreError;
use crate::events::LibraryChanged;
use crate::library::ItemId;
use crate::library::downloads::{self as rows, DownloadRow, DownloadState};
use crate::logs;
use crate::player::{self, Resolution};

const PARALLEL: usize = 2;
/// Progress events per download: at most 2 per second.
const PROGRESS_EVERY: Duration = Duration::from_millis(500);
const QUALITY: &str = "high";
const ARTWORK_SIZE: u32 = 600;

#[derive(Debug, Clone, PartialEq)]
pub struct DownloadProgress {
    pub id: String,
    pub bytes_done: u64,
    pub bytes_total: Option<u64>,
    pub state: DownloadStateView,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DownloadStateView {
    Queued,
    Running,
    Done,
    Failed,
}

impl From<DownloadState> for DownloadStateView {
    fn from(s: DownloadState) -> Self {
        match s {
            DownloadState::Queued => DownloadStateView::Queued,
            DownloadState::Running => DownloadStateView::Running,
            DownloadState::Done => DownloadStateView::Done,
            DownloadState::Failed => DownloadStateView::Failed,
        }
    }
}

static SLOTS: Semaphore = Semaphore::const_new(PARALLEL);
/// The task of each download started, by root item.
static TASKS: LazyLock<Mutex<HashMap<ItemId, JoinHandle<()>>>> = LazyLock::new(Mutex::default);

/// Queues the items (no-op for one already queued, running or done) and starts them.
pub(crate) async fn enqueue(ids: Vec<String>) -> Result<(), CoreError> {
    let items = ids
        .iter()
        .map(|id| parse_id(id))
        .collect::<Result<Vec<_>, _>>()?;
    let queued = app()
        .db
        .write(move |tx| {
            let mut out = Vec::new();
            for item in items {
                rows::enqueue(tx, item, QUALITY)?;
                out.extend(rows::get(&tx.tx, item)?.filter(|r| r.state == DownloadState::Queued));
            }
            Ok(out)
        })
        .await?;
    for row in queued {
        changed(&row);
        start(row.item);
    }
    Ok(())
}

/// Stops the download if it runs, forgets it, and deletes its file and `.part`.
pub(crate) async fn cancel(id: &str) -> Result<(), CoreError> {
    let item = parse_id(id)?;
    let Some(row) = app().db.read(move |c| rows::get(c, item)).await? else {
        return Ok(());
    };
    let task = lock().remove(&row.item);
    if let Some(task) = task {
        task.abort();
        let _ = task.await;
    }
    let root = row.item;
    if let Some(path) = app().db.write(move |tx| rows::remove(tx, root)).await? {
        let path = PathBuf::from(path);
        remove(&part_path(&path)).await;
        remove(&path).await;
    }
    let _ = app().events.library.send(LibraryChanged::Downloads);
    Ok(())
}

/// At startup: queued downloads, and those an exit interrupted, start again.
pub(crate) async fn resume_pending() {
    match app().db.read(|c| rows::list(c, None)).await {
        Ok(rows) => rows
            .into_iter()
            .filter(|r| matches!(r.state, DownloadState::Queued | DownloadState::Running))
            .for_each(|r| start(r.item)),
        Err(e) => logs::push("error", "downloads", &e.to_string()),
    }
}

fn lock() -> std::sync::MutexGuard<'static, HashMap<ItemId, JoinHandle<()>>> {
    TASKS.lock().unwrap_or_else(PoisonError::into_inner)
}

/// One task per item, waiting for a slot.
// ponytail: an item re-queued in the instant its task ends waits for the next resume_pending
fn start(item: ItemId) {
    let mut tasks = lock();
    tasks.retain(|_, t| !t.is_finished());
    if tasks.contains_key(&item) {
        return;
    }
    // Tests: on the test's own runtime (and clock).
    #[cfg(test)]
    let task = tokio::spawn(run(item));
    #[cfg(not(test))]
    let task = app().rt.spawn(run(item));
    tasks.insert(item, task);
}

async fn run(item: ItemId) {
    let _slot = SLOTS.acquire().await.expect("never closed");
    let app = app();
    // Offline, it stays queued for the next resume.
    if !app.is_online() {
        return;
    }
    let mut row = match app.db.read(move |c| rows::get(c, item)).await {
        Ok(Some(row)) if matches!(row.state, DownloadState::Queued | DownloadState::Running) => row,
        Ok(_) => return,
        Err(e) => return logs::push("error", "downloads", &e.to_string()),
    };
    match fetch(&mut row).await {
        Ok(n) => {
            row.state = DownloadState::Done;
            (row.bytes_done, row.bytes_total, row.error) = (n, Some(n), None);
        }
        // Connection lost: queued again, the `.part` kept.
        Err(_) if !app.is_online() => row.state = DownloadState::Queued,
        Err(e) => {
            row.state = DownloadState::Failed;
            row.error = Some(format!("{e:?}"));
        }
    }
    if let Err(e) = save(&row).await {
        logs::push("error", "downloads", &format!("{e:?}"));
    }
    if row.state == DownloadState::Done {
        player::refresh(); // the playing track's `downloaded` flag
    }
}

/// Resolves, marks the row running, downloads: once more after a 403 (resolved again), once
/// more from 0 after a size mismatch (the `.part` was not that file's start).
async fn fetch(row: &mut DownloadRow) -> Result<u64, CoreError> {
    let item = row.item;
    let mut res = player::resolve_for_download(item).await?;
    let mut dest = set_source(row, &res).await?;
    // Best effort: the artwork is there offline too.
    let _ = artwork_file(&item.to_string(), ARTWORK_SIZE).await;
    let mut progress = Progress::new(item.to_string());
    let (mut renewed, mut restarted) = (false, false);
    loop {
        // The size stored with the `.part` is the file it belongs to.
        let (client, f) = prepare(&res, row.bytes_total)?;
        progress.start(row);
        let r = stream::download(&client, &f, &dest, &mut |done, total| {
            progress.on(done, total)
        })
        .await;
        progress.settle(row).await;
        match r {
            Err(StreamError::Http(403)) if !renewed => {
                renewed = true;
                res = player::resolve_for_download(item).await?;
                dest = set_source(row, &res).await?;
            }
            // The stream deleted the `.part`: its size goes with it.
            Err(StreamError::SizeMismatch { .. }) => {
                row.bytes_total = None;
                if restarted {
                    return Err(CoreError::Network);
                }
                restarted = true;
            }
            r => return r.map_err(core_error),
        }
    }
}

/// The row running from `res`, and its file. Another format than last time starts over: the
/// old `.part` and its size go.
async fn set_source(row: &mut DownloadRow, res: &Resolution) -> Result<PathBuf, CoreError> {
    let dest = dest(row.item, res.mime.as_deref());
    if let Some(old) = row.path.as_deref().filter(|p| Path::new(p) != dest) {
        remove(&part_path(Path::new(old))).await;
        row.bytes_total = None;
    }
    tokio::fs::create_dir_all(&app().cfg.downloads_dir)
        .await
        .map_err(|e| CoreError::Internal(e.to_string()))?;
    row.state = DownloadState::Running;
    row.path = Some(dest.display().to_string());
    (row.mime, row.loudness_db) = (res.mime.clone(), res.loudness_db);
    save(row).await?;
    Ok(dest)
}

/// The resolving plugin's client, after its URL check.
fn prepare(res: &Resolution, expected: Option<u64>) -> Result<(reqwest::Client, Fetch), CoreError> {
    let plugins = &app().plugins;
    let plugin = plugins
        .loaded()
        .into_iter()
        .find(|p| Some(p.id()) == res.plugin.as_deref())
        .ok_or_else(|| CoreError::Internal("resolving plugin unloaded".into()))?;
    let url = plugins
        .host()
        .check_url(&plugin, &res.source.uri)
        .map_err(|_| CoreError::Internal("stream url refused".into()))?;
    let f = Fetch {
        url,
        headers: res.source.headers.clone(),
        expected_len: expected,
    };
    Ok((plugins.host().http_client(&plugin), f))
}

fn dest(item: ItemId, mime: Option<&str>) -> PathBuf {
    let ext = if mime.is_some_and(|m| m.contains("webm")) {
        "webm"
    } else {
        "m4a"
    };
    Path::new(&app().cfg.downloads_dir).join(format!("{item}.{ext}"))
}

fn core_error(e: StreamError) -> CoreError {
    match e {
        StreamError::Http(403) => CoreError::Expired,
        StreamError::Http(404 | 410) => CoreError::NotFound,
        StreamError::Http(429) => CoreError::RateLimited,
        StreamError::Io(e) => CoreError::Internal(e),
        StreamError::Network(_)
        | StreamError::Http(_)
        | StreamError::SizeMismatch { .. }
        | StreamError::TooLarge => CoreError::Network,
    }
}

async fn save(row: &DownloadRow) -> Result<(), CoreError> {
    let r = row.clone();
    app().db.write(move |tx| rows::update(tx, &r)).await?;
    changed(row);
    Ok(())
}

/// A state change: its progress, and the library.
fn changed(row: &DownloadRow) {
    let events = &app().events;
    let _ = events.downloads.send(DownloadProgress {
        id: row.item.to_string(),
        bytes_done: row.bytes_done,
        bytes_total: row.bytes_total,
        state: row.state.into(),
    });
    let _ = events.library.send(LibraryChanged::Downloads);
}

async fn remove(path: &Path) {
    match tokio::fs::remove_file(path).await {
        Err(e) if e.kind() != std::io::ErrorKind::NotFound => {
            logs::push("error", "downloads", &e.to_string())
        }
        _ => {}
    }
}

/// Bytes written so far, sent at most every `PROGRESS_EVERY`. The file's size, once the
/// server announces it, is stored on the row at once (in the background: `settle` waits).
struct Progress {
    id: String,
    last: Option<Instant>,
    total: Option<u64>,
    /// The row as stored, while an attempt runs.
    row: Option<DownloadRow>,
    persist: Option<JoinHandle<()>>,
}

impl Progress {
    fn new(id: String) -> Progress {
        Progress {
            id,
            last: None,
            total: None,
            row: None,
            persist: None,
        }
    }

    /// Before an attempt on `row` (as stored).
    fn start(&mut self, row: &DownloadRow) {
        self.total = row.bytes_total;
        self.row = Some(row.clone());
    }

    /// After it: the size stored meanwhile is written, and in `row` too.
    async fn settle(&mut self, row: &mut DownloadRow) {
        if let Some(task) = self.persist.take() {
            let _ = task.await;
        }
        if let Some(stored) = self.row.take() {
            row.bytes_total = stored.bytes_total;
        }
    }

    fn on(&mut self, done: u64, total: Option<u64>) {
        self.total = total.or(self.total);
        if let (Some(t), Some(row)) = (self.total, self.row.as_mut())
            && row.bytes_total != Some(t)
        {
            row.bytes_total = Some(t);
            let r = row.clone();
            self.persist = Some(tokio::spawn(async move {
                if let Err(e) = app().db.write(move |tx| rows::update(tx, &r)).await {
                    logs::push("error", "downloads", &format!("{e:?}"));
                }
            }));
        }
        let now = Instant::now();
        if self.last.is_some_and(|l| now - l < PROGRESS_EVERY) {
            return;
        }
        self.last = Some(now);
        let _ = app().events.downloads.send(DownloadProgress {
            id: self.id.clone(),
            bytes_done: done,
            bytes_total: self.total,
            state: DownloadStateView::Running,
        });
    }
}

#[cfg(test)]
mod tests;
