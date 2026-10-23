//! Runs WASM component plugins under budgets: fuel, wall-clock epochs, memory, HTTP and
//! response size. One typed call per capability; compiled components are cached on disk.

mod cache;
mod calls;
mod engine;
mod feed;
mod http;
mod manifest;
mod net;
mod rate;
#[cfg(any(test, feature = "test-util"))]
mod replay;
mod storage;

use std::path::PathBuf;
use std::sync::Arc;

pub use contract::{music, types};
pub use engine::{Host, Plugin};
pub use feed::{Feed, FeedEntry, FeedError, fingerprint, sha256_matches, sign_feed, verify_feed};
pub use manifest::{Allowlist, Manifest, RateLimit, parse_manifest};
pub use net::{NetPolicy, is_public};
#[cfg(any(test, feature = "test-util"))]
pub use storage::MemoryStorage;
pub use storage::{CachedResponse, Storage};

pub struct HostConfig {
    /// Compiled components; private to the app, only the host writes here.
    pub cache_dir: PathBuf,
    pub storage: Arc<dyn Storage>,
    pub events: Arc<dyn Fn(HostEvent) + Send + Sync>,
    pub limits: Limits,
    pub app_version: String,
    pub net: NetPolicy,
}

#[derive(Debug, Clone, Copy)]
pub struct Limits {
    /// Fuel per call (starting value, to tune).
    pub fuel: u64,
    /// Wall-clock budget in 100 ms epoch ticks.
    pub epoch_ticks: u64,
    /// Summed over every linear memory of the plugin.
    pub memory_bytes: usize,
    pub max_response_bytes: usize,
    pub max_http_calls: u32,
    /// Request plus response bodies, per call.
    pub max_http_bytes: usize,
}

impl Default for Limits {
    fn default() -> Self {
        Limits {
            fuel: 200_000_000,
            epoch_ticks: 300,
            memory_bytes: 64 << 20,
            max_response_bytes: 8 << 20,
            max_http_calls: 24,
            max_http_bytes: 16 << 20,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum HostEvent {
    Log {
        plugin: String,
        level: LogLevel,
        message: String,
    },
    Call(CallReport),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LogLevel {
    Debug,
    Info,
    Warn,
    Error,
}

/// Emitted once at the end of every capability call.
#[derive(Debug, Clone, PartialEq)]
pub struct CallReport {
    pub plugin: String,
    pub capability: Capability,
    pub fuel_used: u64,
    pub http_calls: u32,
    pub wall_ms: u64,
    pub outcome: Result<(), CallError>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Capability {
    Search,
    Suggest,
    Entity,
    Resolve,
    Lyrics,
    Radio,
    Browse,
}

#[derive(Debug, Clone, PartialEq)]
pub enum CallError {
    Network(String),
    ProviderWall(String),
    RateLimited,
    NotFound,
    Expired,
    Internal(String),
    BudgetExceeded(Budget),
    /// The plugin does not export this capability.
    Unsupported,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Budget {
    Fuel,
    Time,
    Memory,
    Http,
}

#[derive(Debug, Clone, PartialEq)]
pub enum LoadError {
    Manifest(String),
    /// Contract version refused, or the component's imports do not match the host's.
    Contract(String),
    Compile(String),
}

impl From<types::Error> for CallError {
    fn from(e: types::Error) -> Self {
        use types::Error as E;
        match e {
            E::Network(m) => CallError::Network(m),
            E::ProviderWall(m) => CallError::ProviderWall(m),
            E::RateLimited => CallError::RateLimited,
            E::NotFound => CallError::NotFound,
            E::Expired => CallError::Expired,
            E::Internal(m) => CallError::Internal(m),
        }
    }
}
