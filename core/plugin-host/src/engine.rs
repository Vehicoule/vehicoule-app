use std::collections::HashMap;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use contract::music::{entity, lyrics, radio, resolve, search, suggest};
use contract::{clock, kv, log, types};
use wasmtime::component::{Component, HasSelf, InstancePre, Linker, ResourceTable};
use wasmtime::{Config, Engine, ResourceLimiter, Store, StoreLimits, StoreLimitsBuilder, Trap};
use wasmtime_wasi::{WasiCtx, WasiCtxView, WasiView};

use crate::{Limits, RunError};

const EPOCH_TICK: Duration = Duration::from_millis(100);

pub struct Host {
    engine: Engine,
    linker: Linker<State>,
    http: reqwest::Client,
}

pub struct Plugin {
    pre: InstancePre<State>,
}

impl Plugin {
    /// Capabilities this component exports, e.g. `["search", "lyrics"]`.
    pub fn exports(&self) -> Vec<&'static str> {
        let found = [
            ("search", search::GuestIndices::new(&self.pre).is_ok()),
            ("suggest", suggest::GuestIndices::new(&self.pre).is_ok()),
            ("entity", entity::GuestIndices::new(&self.pre).is_ok()),
            ("resolve", resolve::GuestIndices::new(&self.pre).is_ok()),
            ("lyrics", lyrics::GuestIndices::new(&self.pre).is_ok()),
            ("radio", radio::GuestIndices::new(&self.pre).is_ok()),
        ];
        found.into_iter().filter_map(|(name, ok)| ok.then_some(name)).collect()
    }
}

pub(crate) struct State {
    wasi: WasiCtx,
    table: ResourceTable,
    limits: Budget,
    kv: Kv,
    pub(crate) http: reqwest::Client,
    pub(crate) max_response_bytes: usize,
}

/// One memory budget for the whole plugin (`StoreLimits::memory_size` would apply it to
/// each linear memory), plus `StoreLimits` for tables and instance counts, plus a flag
/// telling a memory denial apart from other traps.
struct Budget {
    memory_limit: usize,
    memory_total: usize,
    memory_denied: bool,
    inner: StoreLimits,
}

impl Budget {
    fn new(memory_limit: usize) -> Self {
        let inner = StoreLimitsBuilder::new()
            .table_elements(100_000)
            .instances(64)
            .tables(64)
            .memories(16)
            .build();
        Budget { memory_limit, memory_total: 0, memory_denied: false, inner }
    }
}

impl ResourceLimiter for Budget {
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

const KV_MAX_KEY: usize = 128;
const KV_MAX_VALUE: usize = 64 << 10;
const KV_MAX_TOTAL: usize = 1 << 20;

/// In-memory kv, capped: it lives outside the guest's memory budget.
#[derive(Default)]
struct Kv {
    entries: HashMap<String, Vec<u8>>,
    /// Bytes of all keys and values.
    total: usize,
}

impl Kv {
    fn get(&self, key: &str) -> Option<Vec<u8>> {
        self.entries.get(key).cloned()
    }

    fn set(&mut self, key: String, value: Vec<u8>) -> Result<(), kv::KvError> {
        if key.len() > KV_MAX_KEY || value.len() > KV_MAX_VALUE {
            return Err(kv::KvError::TooLarge);
        }
        let old = self.entries.get(&key).map_or(0, |v| key.len() + v.len());
        let total = self.total - old + key.len() + value.len();
        if total > KV_MAX_TOTAL {
            return Err(kv::KvError::QuotaExceeded);
        }
        self.total = total;
        self.entries.insert(key, value);
        Ok(())
    }

    fn delete(&mut self, key: &str) {
        if let Some(v) = self.entries.remove(key) {
            self.total -= key.len() + v.len();
        }
    }
}

// ponytail: kv is per call and not persisted, clock and log are minimal; plan 2 replaces them.
impl kv::Host for State {
    async fn get(&mut self, key: String) -> Option<Vec<u8>> {
        self.kv.get(&key)
    }

    async fn set(&mut self, key: String, value: Vec<u8>) -> Result<(), kv::KvError> {
        self.kv.set(key, value)
    }

    async fn delete(&mut self, key: String) {
        self.kv.delete(&key);
    }
}

impl clock::Host for State {
    async fn now_ms(&mut self) -> u64 {
        SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_millis() as u64)
    }
}

impl log::Host for State {
    async fn log(&mut self, _level: log::Level, _message: String) {}
}

impl types::Host for State {}

impl Host {
    pub fn new() -> anyhow::Result<Host> {
        let mut config = Config::new();
        config.target("pulley64")?;
        config.consume_fuel(true);
        config.epoch_interruption(true);
        let engine = Engine::new(&config)?;

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

        let http = reqwest::Client::builder().timeout(Duration::from_secs(20)).build()?;
        Ok(Host { engine, linker, http })
    }

    pub fn is_pulley(&self) -> bool {
        self.engine.is_pulley()
    }

    /// Compiles on this device; precompiled artifacts are never loaded.
    pub fn compile(&self, wasm: &[u8]) -> anyhow::Result<Plugin> {
        let component = Component::new(&self.engine, wasm)?;
        Ok(Plugin { pre: self.linker.instantiate_pre(&component)? })
    }

    /// One fresh instance per call. Returns the title of the first track found.
    pub async fn search(&self, p: &Plugin, query: &str, limits: Limits) -> Result<String, RunError> {
        let wasi = WasiCtx::builder().allow_tcp(false).allow_udp(false).allow_ip_name_lookup(false).build();
        let state = State {
            wasi,
            table: ResourceTable::new(),
            limits: Budget::new(limits.memory_bytes),
            kv: Kv::default(),
            http: self.http.clone(),
            max_response_bytes: limits.max_response_bytes,
        };
        let mut store = Store::new(&self.engine, state);
        store.limiter(|s| &mut s.limits);
        store.set_fuel(limits.fuel).map_err(|e| RunError::Internal(e.to_string()))?;
        store.set_epoch_deadline(limits.epoch_ticks);

        // Epochs only interrupt running wasm; a guest blocked in a host call (WASI poll,
        // slow HTTP) is cut by this wall-clock timeout instead.
        let wall = EPOCH_TICK.saturating_mul(u32::try_from(limits.epoch_ticks).unwrap_or(u32::MAX));
        let req = search::SearchRequest {
            query: query.into(),
            kinds: vec![types::EntityKind::Track],
            region: String::new(),
            limit: 1,
            cursor: None,
        };
        let call = async {
            let instance = p.pre.instantiate_async(&mut store).await?;
            let guest = search::GuestIndices::new(&p.pre)?.load(&mut store, &instance)?;
            guest.call_search(&mut store, &req).await
        };
        let Ok(result) = tokio::time::timeout(wall, call).await else {
            return Err(RunError::Deadline);
        };
        match result {
            Ok(Ok(found)) => {
                found.tracks.into_iter().next().map(|t| t.title).ok_or_else(|| RunError::Internal("no track".into()))
            }
            Ok(Err(e)) => Err(RunError::Guest(format!("{e:?}"))),
            Err(_) if store.data().limits.memory_denied => Err(RunError::Memory),
            Err(e) => Err(match e.downcast_ref::<Trap>() {
                Some(Trap::OutOfFuel) => RunError::OutOfFuel,
                Some(Trap::Interrupt) => RunError::Deadline,
                _ => RunError::Internal(format!("{e:?}")),
            }),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn kv_enforces_key_value_and_total_caps() {
        let mut kv = Kv::default();
        assert!(matches!(kv.set("k".repeat(129), vec![]), Err(kv::KvError::TooLarge)));
        assert!(matches!(kv.set("k".into(), vec![0; (64 << 10) + 1]), Err(kv::KvError::TooLarge)));

        // 15 entries of 1 + 64 KiB fit in 1 MiB; the 16th does not.
        for i in 0..15 {
            kv.set(format!("{i:x}"), vec![0; 64 << 10]).unwrap();
        }
        assert!(matches!(kv.set("f".into(), vec![0; 64 << 10]), Err(kv::KvError::QuotaExceeded)));
        // Overwriting frees the old value, deleting frees the entry.
        kv.set("0".into(), vec![0; 64 << 10]).unwrap();
        kv.delete("0");
        kv.set("f".into(), vec![0; 64 << 10]).unwrap();
        assert_eq!(kv.get("f").map(|v| v.len()), Some(64 << 10));
    }

    #[test]
    fn memory_budget_is_shared_by_all_memories() {
        let mut b = Budget::new(64 << 20);
        assert!(b.memory_growing(0, 40 << 20, None).unwrap());
        assert!(!b.memory_growing(0, 40 << 20, None).unwrap(), "second memory pushed the total past 64 MiB");
        assert!(b.memory_denied);
        assert!(b.memory_growing(0, 20 << 20, None).unwrap());
    }
}
