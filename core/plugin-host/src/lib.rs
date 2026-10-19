//! Runs WASM component plugins under budgets: fuel, wall-clock epochs, memory and response size.

mod engine;
mod http;

pub use engine::{Host, Plugin};

#[derive(Debug, Clone, Copy)]
pub struct Limits {
    /// Fuel per call (starting value, to tune).
    pub fuel: u64,
    /// Wall-clock budget in 100 ms epoch ticks.
    pub epoch_ticks: u64,
    pub memory_bytes: usize,
    pub max_response_bytes: usize,
}

impl Default for Limits {
    fn default() -> Self {
        Limits { fuel: 200_000_000, epoch_ticks: 300, memory_bytes: 64 << 20, max_response_bytes: 8 << 20 }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RunError {
    OutOfFuel,
    Deadline,
    Memory,
    /// The plugin returned an error: `Debug` of its `types::Error`.
    Guest(String),
    Internal(String),
}
