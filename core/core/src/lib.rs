//! Vehicoule's core: owns app state. `library` is the generic SQLite store for every domain.

#[cfg(not(panic = "unwind"))]
compile_error!("vehicoule-core needs panic = \"unwind\": the bridge turns panics into Dart errors");

#[allow(dead_code, reason = "reached from api/ (task 8)")]
mod app;
#[allow(dead_code, reason = "reached from api/ (task 8)")]
mod catalog;
mod convert;
pub mod error;
pub mod keys;
pub mod library;
pub mod logs;
#[allow(dead_code, reason = "reached from api/ (task 8)")]
mod plugins;
pub mod queue;
mod router;
mod storage;

/// Logs every panic (masked) before the previous hook runs. Installed once, by `app::init`.
fn install_panic_hook() {
    let previous = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        logs::push("error", "panic", &info.to_string());
        previous(info);
    }));
}
