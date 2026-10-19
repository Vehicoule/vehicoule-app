//! Plugin contract: the WIT 1.0 packages and their host-side bindings.

wasmtime::component::bindgen!({
    path: ["wit/host", "wit/music"],
    world: "vehicoule:music/plugin",
    imports: { default: async },
    exports: { default: async },
});

pub use vehicoule::host::{clock, http, kv, log};
pub use vehicoule::music::types;

/// Plugin capabilities, one module per exported interface.
pub mod music {
    pub use crate::exports::vehicoule::music::{entity, lyrics, radio, resolve, search, suggest};
}

/// `vehicoule:host@1.0.0`, imported by plugins.
pub const HOST_WIT: &str = include_str!("../wit/host/host.wit");
/// `vehicoule:music@1.0.0`, exported by plugins.
pub const MUSIC_WIT: &str = include_str!("../wit/music/music.wit");
