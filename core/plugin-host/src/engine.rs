use std::hash::{DefaultHasher, Hash, Hasher};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use contract::music::{entity, lyrics, radio, resolve, search, suggest};
use contract::{clock, kv, log, types};
use sha2::{Digest, Sha256};
use wasmtime::component::{Component, HasSelf, Instance, InstancePre, Linker, ResourceTable};
use wasmtime::{Config, Engine, ResourceLimiter, Store, StoreLimits, StoreLimitsBuilder, Trap};
use wasmtime_wasi::{WasiCtx, WasiCtxView, WasiView};

use crate::calls::Returned;
use crate::manifest::{Allowlist, Manifest, parse_manifest, validate_contract};
use crate::net::NetPolicy;
use crate::storage::{self, Storage};
use crate::{Budget, CallError, CallReport, Capability, HostConfig, HostEvent, LoadError};

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
    plugin: String,
    storage: Arc<dyn Storage>,
    pub(crate) net: NetPolicy,
    pub(crate) allowlist: Arc<Allowlist>,
    pub(crate) max_response_bytes: usize,
    /// Requests sent during this call, batch members included.
    pub(crate) http_calls: u32,
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
        MemoryBudget { memory_limit, memory_total: 0, memory_denied: false, inner }
    }
}

impl ResourceLimiter for MemoryBudget {
    fn memory_growing(&mut self, current: usize, desired: usize, _maximum: Option<usize>) -> wasmtime::Result<bool> {
        let total = self.memory_total + desired.saturating_sub(current);
        if total > self.memory_limit {
            self.memory_denied = true;
            return Ok(false);
        }
        self.memory_total = total;
        Ok(true)
    }

    fn table_growing(&mut self, current: usize, desired: usize, maximum: Option<usize>) -> wasmtime::Result<bool> {
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
        WasiCtxView { ctx: &mut self.wasi, table: &mut self.table }
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
        SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_millis() as u64)
    }
}

// ponytail: logs and stdout are dropped; task 5 turns them into capped `HostEvent::Log`.
impl log::Host for State {
    async fn log(&mut self, _level: log::Level, _message: String) {}
}

impl types::Host for State {}

impl Host {
    pub fn new(cfg: HostConfig) -> anyhow::Result<Host> {
        let mut config = Config::new();
        config.target("pulley64")?;
        config.consume_fuel(true);
        config.epoch_interruption(true);
        let engine = Engine::new(&config)?;
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
        Ok(Host { engine, engine_hash, linker, cfg })
    }

    pub fn is_pulley(&self) -> bool {
        self.engine.is_pulley()
    }

    /// Validates the manifest, then compiles on this device (or reuses this device's cache).
    pub fn load(&self, manifest_json: &[u8], wasm: &[u8]) -> Result<Plugin, LoadError> {
        let raw: Manifest = serde_json::from_slice(manifest_json).map_err(|e| LoadError::Manifest(e.to_string()))?;
        validate_contract(&raw.contract).map_err(LoadError::Contract)?;
        let manifest = parse_manifest(manifest_json).map_err(LoadError::Manifest)?;
        let allowlist = Arc::new(Allowlist::new(&manifest.domains).map_err(LoadError::Manifest)?);
        let component = self.compile(wasm).map_err(|e| LoadError::Compile(format!("{e:#}")))?;
        let pre = self.linker.instantiate_pre(&component).map_err(|e| LoadError::Contract(format!("{e:#}")))?;
        let capabilities = [
            (Capability::Search, search::GuestIndices::new(&pre).is_ok()),
            (Capability::Suggest, suggest::GuestIndices::new(&pre).is_ok()),
            (Capability::Entity, entity::GuestIndices::new(&pre).is_ok()),
            (Capability::Resolve, resolve::GuestIndices::new(&pre).is_ok()),
            (Capability::Lyrics, lyrics::GuestIndices::new(&pre).is_ok()),
            (Capability::Radio, radio::GuestIndices::new(&pre).is_ok()),
        ];
        let capabilities = capabilities.into_iter().filter_map(|(c, ok)| ok.then_some(c)).collect();
        Ok(Plugin(Arc::new(Loaded { manifest, allowlist, pre, capabilities })))
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
        // later one: a file-backed component uses less fuel per call than an in-memory one
        // (probe: ~5k vs ~71k, likely its copy-on-write memory image). A failed write only
        // costs a recompile on the next load.
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
        let wasi = WasiCtx::builder().allow_tcp(false).allow_udp(false).allow_ip_name_lookup(false).build();
        let state = State {
            wasi,
            table: ResourceTable::new(),
            memory: MemoryBudget::new(limits.memory_bytes),
            plugin: p.id().into(),
            storage: self.cfg.storage.clone(),
            net: self.cfg.net.clone(),
            allowlist: p.0.allowlist.clone(),
            max_response_bytes: limits.max_response_bytes,
            http_calls: 0,
        };
        let mut store = Store::new(&self.engine, state);
        store.limiter(|s| &mut s.memory);
        store.set_epoch_deadline(limits.epoch_ticks);

        let outcome = if let Err(e) = store.set_fuel(limits.fuel) {
            Err(CallError::Internal(e.to_string()))
        } else if !p.capabilities().contains(&capability) {
            Err(CallError::Unsupported)
        } else {
            // Epochs only interrupt running wasm; a guest blocked in a host call (WASI poll,
            // slow HTTP) is cut by this wall-clock timeout instead.
            let wall = EPOCH_TICK.saturating_mul(u32::try_from(limits.epoch_ticks).unwrap_or(u32::MAX));
            let call = async {
                let instance = p.pre().instantiate_async(&mut store).await?;
                f(&mut store, &instance).await
            };
            match tokio::time::timeout(wall, call).await {
                Err(_) => Err(CallError::BudgetExceeded(Budget::Time)),
                Ok(Ok(Ok(found))) => found.checked(self, p),
                Ok(Ok(Err(e))) => Err(e.into()),
                Ok(Err(_)) if store.data().memory.memory_denied => Err(CallError::BudgetExceeded(Budget::Memory)),
                Ok(Err(e)) => Err(match e.downcast_ref::<Trap>() {
                    Some(Trap::OutOfFuel) => CallError::BudgetExceeded(Budget::Fuel),
                    Some(Trap::Interrupt) => CallError::BudgetExceeded(Budget::Time),
                    _ => CallError::Internal(format!("{e:#}")),
                }),
            }
        };

        let report = CallReport {
            plugin: p.id().into(),
            capability,
            fuel_used: limits.fuel.saturating_sub(store.get_fuel().unwrap_or(limits.fuel)),
            http_calls: store.data().http_calls,
            wall_ms: start.elapsed().as_millis() as u64,
            outcome: outcome.as_ref().map(|_| ()).map_err(Clone::clone),
        };
        (self.cfg.events)(HostEvent::Call(report));
        outcome
    }
}

/// Temp file then rename: readers never see a partial file.
fn write_atomic(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    static N: AtomicU64 = AtomicU64::new(0);
    let tmp: PathBuf = path.with_extension(format!("{}.{}.tmp", std::process::id(), N.fetch_add(1, Ordering::Relaxed)));
    let r = std::fs::write(&tmp, bytes).and_then(|()| std::fs::rename(&tmp, path));
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
        assert!(!b.memory_growing(0, 40 << 20, None).unwrap(), "second memory pushed the total past 64 MiB");
        assert!(b.memory_denied);
        assert!(b.memory_growing(0, 20 << 20, None).unwrap());
    }
}
