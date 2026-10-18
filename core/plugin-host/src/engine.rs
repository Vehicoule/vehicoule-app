use std::time::Duration;

use contract::Probe;
use wasmtime::component::{Component, HasSelf, Linker, ResourceTable};
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
    component: Component,
}

pub(crate) struct State {
    wasi: WasiCtx,
    table: ResourceTable,
    limits: Budget,
    pub(crate) http: reqwest::Client,
    pub(crate) max_response_bytes: usize,
}

/// `StoreLimits` plus a flag telling a memory denial apart from other traps.
struct Budget {
    inner: StoreLimits,
    memory_denied: bool,
}

impl ResourceLimiter for Budget {
    fn memory_growing(&mut self, current: usize, desired: usize, maximum: Option<usize>) -> wasmtime::Result<bool> {
        let ok = self.inner.memory_growing(current, desired, maximum)?;
        self.memory_denied |= !ok;
        Ok(ok)
    }

    fn table_growing(&mut self, current: usize, desired: usize, maximum: Option<usize>) -> wasmtime::Result<bool> {
        self.inner.table_growing(current, desired, maximum)
    }
}

impl WasiView for State {
    fn ctx(&mut self) -> WasiCtxView<'_> {
        WasiCtxView { ctx: &mut self.wasi, table: &mut self.table }
    }
}

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
        Probe::add_to_linker::<_, HasSelf<State>>(&mut linker, |s| s)?;

        let http = reqwest::Client::builder().timeout(Duration::from_secs(20)).build()?;
        Ok(Host { engine, linker, http })
    }

    pub fn is_pulley(&self) -> bool {
        self.engine.is_pulley()
    }

    /// Compiles on this device; precompiled artifacts are never loaded.
    pub fn compile(&self, wasm: &[u8]) -> anyhow::Result<Plugin> {
        Ok(Plugin { component: Component::new(&self.engine, wasm)? })
    }

    /// One fresh instance per call.
    pub async fn run(&self, p: &Plugin, input: &str, limits: Limits) -> Result<String, RunError> {
        let wasi = WasiCtx::builder().allow_tcp(false).allow_udp(false).allow_ip_name_lookup(false).build();
        let state = State {
            wasi,
            table: ResourceTable::new(),
            limits: Budget {
                inner: StoreLimitsBuilder::new().memory_size(limits.memory_bytes).build(),
                memory_denied: false,
            },
            http: self.http.clone(),
            max_response_bytes: limits.max_response_bytes,
        };
        let mut store = Store::new(&self.engine, state);
        store.limiter(|s| &mut s.limits);
        store.set_fuel(limits.fuel).map_err(|e| RunError::Internal(e.to_string()))?;
        store.set_epoch_deadline(limits.epoch_ticks);

        let result = async {
            let probe = Probe::instantiate_async(&mut store, &p.component, &self.linker).await?;
            probe.call_run(&mut store, input).await
        }
        .await;
        match result {
            Ok(Ok(out)) => Ok(out),
            Ok(Err(msg)) => Err(RunError::Guest(msg)),
            Err(e) if store.data().limits.memory_denied => {
                let _ = e;
                Err(RunError::Memory)
            }
            Err(e) => Err(match e.downcast_ref::<Trap>() {
                Some(Trap::OutOfFuel) => RunError::OutOfFuel,
                Some(Trap::Interrupt) => RunError::Deadline,
                _ => RunError::Internal(format!("{e:?}")),
            }),
        }
    }
}
