//! Vehicoule's core: owns app state. `library` is the generic SQLite store for every domain.

#[cfg(not(panic = "unwind"))]
compile_error!("vehicoule-core needs panic = \"unwind\": the bridge turns panics into Dart errors");

#[allow(dead_code, reason = "reached from api/ (task 8)")]
mod app;
pub mod error;
pub mod library;
pub mod logs;
#[allow(dead_code, reason = "handed to plugin-host by plugins.rs (task 2)")]
mod storage;

/// Logs every panic (masked) before the previous hook runs. Installed once, by `app::init`.
fn install_panic_hook() {
    let previous = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        logs::push("error", "panic", &info.to_string());
        previous(info);
    }));
}
