use std::hash::{DefaultHasher, Hash, Hasher};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use bytes::Bytes;
use contract::music::{browse, entity, lyrics, radio, resolve, search, suggest};
use contract::{clock, kv, log, types};
use sha2::{Digest, Sha256};
use wasmtime::component::{Component, HasSelf, Instance, InstancePre, Linker, ResourceTable};
use wasmtime::{Config, Engine, ResourceLimiter, Store, StoreLimits, StoreLimitsBuilder, Trap};
use wasmtime_wasi::async_trait;
use wasmtime_wasi::cli::{IsTerminal, StdoutStream};
use wasmtime_wasi::p2::{OutputStream, Pollable, StreamResult};
use wasmtime_wasi::{WasiCtx, WasiCtxView, WasiView};

use crate::calls::Returned;
use crate::manifest::{Allowlist, Manifest, parse_manifest, validate_contract};
use crate::net::{HttpBudget, NetPolicy};
use crate::rate::RateLimiter;
use crate::storage::{self, Storage};
use crate::{
    Budget, CallError, CallReport, Capability, HostConfig, HostEvent, LoadError, LogLevel,
};

const EPOCH_TICK: Duration = Duration::from_millis(100);

pub struct Host {
    engine: Engine,
    /// `Engine::precompile_compatibility_hash`, folded to name cache files.
    engine_hash: u64,
    linker: Linker<State>,
    cfg: HostConfig,
}

/// A loaded plugin; cheap to clone.
#[derive(Clone)]
pub struct Plugin(Arc<Loaded>);

struct Loaded {
    manifest: Manifest,
    allowlist: Arc<Allowlist>,
    pre: InstancePre<State>,
    capabilities: Vec<Capability>,
    /// One per plugin, shared by every call it makes; `None` when the manifest asks for none.
    rate_limiter: Option<RateLimiter>,
}

impl Plugin {
    pub fn id(&self) -> &str {
        &self.0.manifest.id
    }

    pub fn manifest(&self) -> &Manifest {
        &self.0.manifest
    }

    /// Capabilities the component exports, in contract order.
    pub fn capabilities(&self) -> &[Capability] {
        &self.0.capabilities
    }

    pub(crate) fn pre(&self) -> &InstancePre<State> {
        &self.0.pre
    }
}

pub(crate) struct State {
    wasi: WasiCtx,
    table: ResourceTable,
    memory: MemoryBudget,
    pub(crate) plugin: String,
    pub(crate) storage: Arc<dyn Storage>,
    pub(crate) net: NetPolicy,
    pub(crate) allowlist: Arc<Allowlist>,
    pub(crate) max_response_bytes: usize,
    /// Shared by every sequential `send` and every member of a concurrent `send_batch`.
    pub(crate) http_budget: Mutex<HttpBudget>,
    pub(crate) rate_limiter: Option<RateLimiter>,
    /// Forces every outgoing request's `User-Agent` when the manifest asks for it.
    pub(crate) user_agent: Option<String>,
    /// This call's own wall-clock cutoff (`tokio::time::timeout` below); a rate-limit wait
    /// that would run past it fails fast instead (see `rate::RateLimiter::acquire`).
    pub(crate) deadline: tokio::time::Instant,
    /// The capability this call is running: the HTTP cache (`net::fetch`) only applies outside
    /// `resolve`.
    pub(crate) capability: Capability,
    call_log: Arc<CallLog>,
}

/// Caps `HostEvent::Log` at 200 per call, message truncated to 2 KiB at a UTF-8 boundary. Fed
/// by `log::Host::log` directly, and by `LogStream` (the WASI stdout/stderr capture) as lines
/// complete.
struct CallLog {
    plugin: String,
    events: Arc<dyn Fn(HostEvent) + Send + Sync>,
    remaining: AtomicU32,
}

const LOG_CAP_EVENTS: u32 = 200;
const LOG_MAX_MESSAGE: usize = 2 << 10;

impl CallLog {
    fn new(plugin: String, events: Arc<dyn Fn(HostEvent) + Send + Sync>) -> Self {
        CallLog {
            plugin,
            events,
            remaining: AtomicU32::new(LOG_CAP_EVENTS),
        }
    }

    /// `true` once the 200-event cap has been spent: `LogStream` uses this to stop buffering
    /// and processing bytes at all, instead of doing that work only to have `emit` drop it.
    fn exhausted(&self) -> bool {
        self.remaining.load(Ordering::Relaxed) == 0
    }

    fn emit(&self, level: LogLevel, message: &str) {
        if self
            .remaining
            .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |r| r.checked_sub(1))
            .is_err()
        {
            return;
        }
        (self.events)(HostEvent::Log {
            plugin: self.plugin.clone(),
            level,
            message: truncate_utf8(message).into(),
        });
    }
}

fn truncate_utf8(s: &str) -> &str {
    if s.len() <= LOG_MAX_MESSAGE {
        return s;
    }
    let mut end = LOG_MAX_MESSAGE;
    while !s.is_char_boundary(end) {
        end -= 1;
    }
    &s[..end]
}

/// The largest valid-UTF-8 prefix of `buf` (at most `buf.len()`). `buf` may end mid-character
/// (the partial-line buffer below is capped at `LOG_MAX_MESSAGE` *bytes*, which can land inside
/// a multi-byte character); unlike `String::from_utf8_lossy`, this drops that trailing
/// incomplete sequence instead of replacing it with U+FFFD. Guest stdout is a `list<u8>`, not a
/// WIT string, so it can carry any bytes: a non-trailing invalid byte is handled the same way,
/// everything from that byte on is dropped.
fn valid_utf8_prefix(buf: &[u8]) -> &str {
    match std::str::from_utf8(buf) {
        Ok(s) => s,
        // `valid_up_to()` is exactly the length of the valid prefix `from_utf8` found, so this
        // always succeeds; a rare error path, not worth an `unsafe` skip of the recheck.
        Err(e) => {
            std::str::from_utf8(&buf[..e.valid_up_to()]).expect("valid_up_to ends a valid prefix")
        }
    }
}

/// WASI stdout/stderr, wired to feed a call's `CallLog` one line at a time as bytes arrive —
/// rather than buffering the whole call's output and splitting it at the end — so a plugin
/// cannot make a call fail just by printing a lot: `write` never errors, and once the log's
/// 200-event cap is spent, bytes are dropped instead of accumulated. Cheap to clone (an `Arc`
/// inside); `Host::call` keeps one clone to flush the trailing partial line once the instance
/// has run, while another is installed as the WASI stream.
#[derive(Clone)]
struct LogStream {
    log: Arc<CallLog>,
    level: LogLevel,
    /// The current line, not yet terminated by `\n`; capped at `LOG_MAX_MESSAGE` bytes (extra
    /// bytes of an over-long line are dropped, but scanning continues so the next `\n` still
    /// starts a fresh line).
    partial: Arc<Mutex<Vec<u8>>>,
}

impl LogStream {
    fn new(log: Arc<CallLog>, level: LogLevel) -> Self {
        LogStream {
            log,
            level,
            partial: Arc::new(Mutex::new(Vec::new())),
        }
    }

    fn feed(&self, bytes: &[u8]) {
        if self.log.exhausted() {
            return;
        }
        let mut partial = self
            .partial
            .lock()
            .expect("log line poisoned: a thread panicked while holding it");
        for &b in bytes {
            if b == b'\n' {
                if partial.last() == Some(&b'\r') {
                    partial.pop();
                }
                self.log.emit(self.level, valid_utf8_prefix(&partial));
                partial.clear();
                if self.log.exhausted() {
                    partial.clear();
                    return;
                }
            } else if partial.len() < LOG_MAX_MESSAGE {
                partial.push(b);
            }
        }
    }

    /// Flushes a trailing partial line (no final `\n`) once the call's instance has run.
    fn flush_partial(&self) {
        let mut partial = self
            .partial
            .lock()
            .expect("log line poisoned: a thread panicked while holding it");
        if !partial.is_empty() {
            self.log.emit(self.level, valid_utf8_prefix(&partial));
            partial.clear();
        }
    }
}

impl IsTerminal for LogStream {
    fn is_terminal(&self) -> bool {
        false
    }
}

impl StdoutStream for LogStream {
    fn p2_stream(&self) -> Box<dyn OutputStream> {
        Box::new(self.clone())
    }

    /// Unreachable in practice: this host only ever runs under `wasmtime_wasi::p2`, which calls
    /// `p2_stream` above for `wasi:cli/stdout` and `stderr` (never this wasip1-oriented path).
    fn async_stream(&self) -> Box<dyn tokio::io::AsyncWrite + Send + Sync> {
        Box::new(tokio::io::sink())
    }
}

/// The permit `check_write` hands out: a plugin's actual write size is bounded by its own
/// output buffering (e.g. libc's stdio), not by this value, and `write` never errors — there is
/// nothing here for a permit to protect against.
const LOG_STREAM_PERMIT: usize = 64 << 10;

#[async_trait]
impl Pollable for LogStream {
    async fn ready(&mut self) {}
}

#[async_trait]
impl OutputStream for LogStream {
    fn write(&mut self, bytes: Bytes) -> StreamResult<()> {
        self.feed(&bytes);
        Ok(())
    }

    fn flush(&mut self) -> StreamResult<()> {
        Ok(())
    }

    fn check_write(&mut self) -> StreamResult<usize> {
        Ok(LOG_STREAM_PERMIT)
    }
}

/// One memory budget for the whole plugin (`StoreLimits::memory_size` would apply it to
/// each linear memory), plus `StoreLimits` for tables and instance counts, plus a flag
/// telling a memory denial apart from other traps.
struct MemoryBudget {
    memory_limit: usize,
    memory_total: usize,
    memory_denied: bool,
    inner: StoreLimits,
}

impl MemoryBudget {
    fn new(memory_limit: usize) -> Self {
        let inner = StoreLimitsBuilder::new()
            .table_elements(100_000)
            .instances(64)
            .tables(64)
            .memories(16)
            .build();
        MemoryBudget {
            memory_limit,
            memory_total: 0,
            memory_denied: false,
            inner,
        }
    }
}

impl ResourceLimiter for MemoryBudget {
    fn memory_growing(
        &mut self,
        current: usize,
        desired: usize,
        _maximum: Option<usize>,
    ) -> wasmtime::Result<bool> {
        let total = self.memory_total + desired.saturating_sub(current);
        if total > self.memory_limit {
            self.memory_denied = true;
            return Ok(false);
        }
        self.memory_total = total;
        Ok(true)
    }

    fn table_growing(
        &mut self,
        current: usize,
        desired: usize,
        maximum: Option<usize>,
    ) -> wasmtime::Result<bool> {
        self.inner.table_growing(current, desired, maximum)
    }

    fn instances(&self) -> usize {
        self.inner.instances()
    }

    fn tables(&self) -> usize {
        self.inner.tables()
    }

    fn memories(&self) -> usize {
        self.inner.memories()
    }
}

impl WasiView for State {
    fn ctx(&mut self) -> WasiCtxView<'_> {
        WasiCtxView {
            ctx: &mut self.wasi,
            table: &mut self.table,
        }
    }
}

impl kv::Host for State {
    async fn get(&mut self, key: String) -> Option<Vec<u8>> {
        self.storage.kv_get(&self.plugin, &key)
    }

    async fn set(&mut self, key: String, value: Vec<u8>) -> Result<(), kv::KvError> {
        storage::kv_set(&*self.storage, &self.plugin, &key, &value)
    }

    async fn delete(&mut self, key: String) {
        self.storage.kv_delete(&self.plugin, &key);
    }
}

impl clock::Host for State {
    async fn now_ms(&mut self) -> u64 {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_or(0, |d| d.as_millis() as u64)
    }
}

impl log::Host for State {
    async fn log(&mut self, level: log::Level, message: String) {
        let level = match level {
            log::Level::Debug => LogLevel::Debug,
            log::Level::Info => LogLevel::Info,
            log::Level::Warn => LogLevel::Warn,
            log::Level::Error => LogLevel::Error,
        };
        self.call_log.emit(level, &message);
    }
}

impl types::Host for State {}

impl Host {
    pub fn new(cfg: HostConfig) -> anyhow::Result<Host> {
        let mut config = Config::new();
        config.target("pulley64")?;
        config.consume_fuel(true);
        config.epoch_interruption(true);
        let engine = Engine::new(&config)?;
        // DefaultHasher is not stable across toolchains: a new one only invalidates the cache.
        let mut hasher = DefaultHasher::new();
        engine.precompile_compatibility_hash().hash(&mut hasher);
        let engine_hash = hasher.finish();

        let weak = engine.weak();
        std::thread::spawn(move || {
            while let Some(engine) = weak.upgrade() {
                engine.increment_epoch();
                drop(engine);
                std::thread::sleep(EPOCH_TICK);
            }
        });

        let mut linker = Linker::new(&engine);
        // WASI subset: no preopened directories, no sockets.
        wasmtime_wasi::p2::add_to_linker_async(&mut linker)?;
        contract::Plugin::add_to_linker::<_, HasSelf<State>>(&mut linker, |s| s)?;

        std::fs::create_dir_all(&cfg.cache_dir)?;
        Ok(Host {
            engine,
            engine_hash,
            linker,
            cfg,
        })
    }

    pub fn is_pulley(&self) -> bool {
        self.engine.is_pulley()
    }

    /// Validates the manifest, then compiles on this device (or reuses this device's cache).
    pub fn load(&self, manifest_json: &[u8], wasm: &[u8]) -> Result<Plugin, LoadError> {
        let raw: Manifest = serde_json::from_slice(manifest_json)
            .map_err(|e| LoadError::Manifest(e.to_string()))?;
        validate_contract(&raw.contract).map_err(LoadError::Contract)?;
        let manifest = parse_manifest(manifest_json).map_err(LoadError::Manifest)?;
        let allowlist = Arc::new(Allowlist::new(&manifest.domains).map_err(LoadError::Manifest)?);
        let component = self
            .compile(wasm)
            .map_err(|e| LoadError::Compile(format!("{e:#}")))?;
        let pre = self
            .linker
            .instantiate_pre(&component)
            .map_err(|e| LoadError::Contract(format!("{e:#}")))?;
        let capabilities = [
            (Capability::Search, search::GuestIndices::new(&pre).is_ok()),
            (
                Capability::Suggest,
                suggest::GuestIndices::new(&pre).is_ok(),
            ),
            (Capability::Entity, entity::GuestIndices::new(&pre).is_ok()),
            (
                Capability::Resolve,
                resolve::GuestIndices::new(&pre).is_ok(),
            ),
            (Capability::Lyrics, lyrics::GuestIndices::new(&pre).is_ok()),
            (Capability::Radio, radio::GuestIndices::new(&pre).is_ok()),
            (Capability::Browse, browse::GuestIndices::new(&pre).is_ok()),
        ];
        let capabilities = capabilities
            .into_iter()
            .filter_map(|(c, ok)| ok.then_some(c))
            .collect();
        let rate_limiter = manifest.rate_limit.map(RateLimiter::new);
        Ok(Plugin(Arc::new(Loaded {
            manifest,
            allowlist,
            pre,
            capabilities,
            rate_limiter,
        })))
    }

    /// `cache_dir/<sha256(wasm)>-<engine hash>.cwasm`, else compile and write it.
    fn compile(&self, wasm: &[u8]) -> wasmtime::Result<Component> {
        let name = format!("{:x}-{:016x}.cwasm", Sha256::digest(wasm), self.engine_hash);
        let path = self.cfg.cache_dir.join(name);
        // SAFETY: the cache dir is private to the app and only this function writes it, with
        // whole files (rename), from `Component::serialize` on this device. A truncated file
        // or one from another Wasmtime build fails the header checks and is rebuilt.
        let cached = || unsafe { Component::deserialize_file(&self.engine, &path) };
        if let Ok(component) = cached() {
            return Ok(component);
        }
        let component = Component::new(&self.engine, wasm)?;
        // Reloaded from the file when the write succeeds, so the first load behaves like every
        // later one: measured, a non-file-backed component costs a fixed +65,537 fuel per
        // instantiation (negligible against the 200M default, but it would make the first load
        // differ from every later one). A failed write only costs a recompile on the next load.
        match write_atomic(&path, &component.serialize()?) {
            Ok(()) => cached().or(Ok(component)),
            Err(_) => Ok(component),
        }
    }

    /// For URLs a plugin returns (stream, artwork): the same checks as plugin requests.
    pub fn check_url(&self, p: &Plugin, url: &str) -> Result<reqwest::Url, String> {
        let parsed = reqwest::Url::parse(url).map_err(|e| format!("{url}: {e}"))?;
        self.cfg.net.check(&p.0.allowlist, &parsed)?;
        Ok(parsed)
    }

    /// For the core's own fetches of URLs `p` returned (stream, artwork): refuses literal IPs,
    /// non-public addresses, and hosts or redirects outside `p`'s allowlist.
    // ponytail: one client (and connection pool) per call; cache per plugin if it shows up.
    pub fn http_client(&self, p: &Plugin) -> reqwest::Client {
        self.cfg.net.client_for(p.0.allowlist.clone())
    }

    /// One fresh instance per call, under every budget; reports the call as a `HostEvent`.
    pub(crate) async fn call<T: Returned>(
        &self,
        p: &Plugin,
        capability: Capability,
        f: impl AsyncFnOnce(&mut Store<State>, &Instance) -> wasmtime::Result<Result<T, types::Error>>,
    ) -> Result<T, CallError> {
        let start = Instant::now();
        let limits = self.cfg.limits;
        let call_log = Arc::new(CallLog::new(p.id().into(), self.cfg.events.clone()));
        let stdout = LogStream::new(call_log.clone(), LogLevel::Info);
        let stderr = LogStream::new(call_log.clone(), LogLevel::Warn);
        let wasi = WasiCtx::builder()
            .allow_tcp(false)
            .allow_udp(false)
            .allow_ip_name_lookup(false)
            .stdout(stdout.clone())
            .stderr(stderr.clone())
            .build();
        let user_agent = p.manifest().descriptive_user_agent.then(|| {
            format!(
                "Vehicoule/{} (+https://vehicoule.app)",
                self.cfg.app_version
            )
        });
        // Epochs only interrupt running wasm; a guest blocked in a host call (WASI poll, slow
        // HTTP) is cut by this wall-clock timeout instead. Computed up front so a rate-limit
        // wait inside the call can tell whether it would run past it.
        let wall = EPOCH_TICK.saturating_mul(u32::try_from(limits.epoch_ticks).unwrap_or(u32::MAX));
        let deadline = tokio::time::Instant::now() + wall;
        let state = State {
            wasi,
            table: ResourceTable::new(),
            memory: MemoryBudget::new(limits.memory_bytes),
            plugin: p.id().into(),
            storage: self.cfg.storage.clone(),
            net: self.cfg.net.clone(),
            allowlist: p.0.allowlist.clone(),
            max_response_bytes: limits.max_response_bytes,
            http_budget: Mutex::new(HttpBudget::new(
                limits.max_http_calls,
                limits.max_http_bytes,
            )),
            rate_limiter: p.0.rate_limiter.clone(),
            user_agent,
            deadline,
            capability,
            call_log: call_log.clone(),
        };
        let mut store = Store::new(&self.engine, state);
        store.limiter(|s| &mut s.memory);
        store.set_epoch_deadline(limits.epoch_ticks);

        let outcome = if let Err(e) = store.set_fuel(limits.fuel) {
            Err(CallError::Internal(e.to_string()))
        } else if !p.capabilities().contains(&capability) {
            Err(CallError::Unsupported)
        } else {
            let call = async {
                let instance = p.pre().instantiate_async(&mut store).await?;
                f(&mut store, &instance).await
            };
            match tokio::time::timeout(wall, call).await {
                Err(_) => Err(CallError::BudgetExceeded(Budget::Time)),
                Ok(Ok(Ok(found))) => found.checked(self, p),
                // A guest that caught `budget-exceeded` itself and returned `Ok` took the
                // branch above and keeps that `Ok`; only an `Err` reaching here while the
                // budget was hit is turned into the typed `BudgetExceeded(Http)`.
                Ok(Ok(Err(_)))
                    if store
                        .data()
                        .http_budget
                        .lock()
                        .expect("http budget poisoned: a thread panicked while holding it")
                        .hit =>
                {
                    Err(CallError::BudgetExceeded(Budget::Http))
                }
                Ok(Ok(Err(e))) => Err(e.into()),
                Ok(Err(_)) if store.data().memory.memory_denied => {
                    Err(CallError::BudgetExceeded(Budget::Memory))
                }
                Ok(Err(e)) => Err(match e.downcast_ref::<Trap>() {
                    Some(Trap::OutOfFuel) => CallError::BudgetExceeded(Budget::Fuel),
                    Some(Trap::Interrupt) => CallError::BudgetExceeded(Budget::Time),
                    _ => CallError::Internal(format!("{e:#}")),
                }),
            }
        };

        // Lines are emitted as bytes arrive (`LogStream::feed`); only the trailing partial line
        // (no final `\n`) is left to flush once the instance has run.
        stdout.flush_partial();
        stderr.flush_partial();

        let report = CallReport {
            plugin: p.id().into(),
            capability,
            fuel_used: limits
                .fuel
                .saturating_sub(store.get_fuel().unwrap_or(limits.fuel)),
            http_calls: store
                .data()
                .http_budget
                .lock()
                .expect("http budget poisoned: a thread panicked while holding it")
                .calls,
            wall_ms: start.elapsed().as_millis() as u64,
            outcome: outcome.as_ref().map(|_| ()).map_err(Clone::clone),
        };
        (self.cfg.events)(HostEvent::Call(report));
        outcome
    }
}

/// Temp file, fsync, then rename: readers never see a partial file, even after a power loss
/// (the rename cannot reach disk ahead of the data it points at).
fn write_atomic(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    static N: AtomicU64 = AtomicU64::new(0);
    let tmp: PathBuf = path.with_extension(format!(
        "{}.{}.tmp",
        std::process::id(),
        N.fetch_add(1, Ordering::Relaxed)
    ));
    let write = || {
        let mut file = std::fs::File::create(&tmp)?;
        std::io::Write::write_all(&mut file, bytes)?;
        file.sync_all()
    };
    let r = write().and_then(|()| std::fs::rename(&tmp, path));
    if r.is_err() {
        let _ = std::fs::remove_file(&tmp);
    }
    r
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn memory_budget_is_shared_by_all_memories() {
        let mut b = MemoryBudget::new(64 << 20);
        assert!(b.memory_growing(0, 40 << 20, None).unwrap());
        assert!(
            !b.memory_growing(0, 40 << 20, None).unwrap(),
            "second memory pushed the total past 64 MiB"
        );
        assert!(b.memory_denied);
        assert!(b.memory_growing(0, 20 << 20, None).unwrap());
    }
}
