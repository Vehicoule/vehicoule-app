//! Guest-side helpers for Vehicoule plugins: host bindings, shared types, typed JSON over HTTP.

use std::future::Future;
use std::pin::pin;
use std::task::{Context, Poll, Waker};

mod http;

pub use http::{from_http_error, get_json, query, status_error};
pub use {serde, serde_json, wit_bindgen};

pub mod bindings {
    wit_bindgen::generate!({
        path: ["../core/contract/wit/host", "../core/contract/wit/music"],
        world: "vehicoule:music/sdk",
        generate_all,
    });
}

pub use bindings::vehicoule::host::{clock, http as host_http, kv, log};
pub use bindings::vehicoule::music::types;

/// `vehicoule:host@1.0.0`, the text this SDK was built against.
pub const HOST_WIT: &str = include_str!("../../core/contract/wit/host/host.wit");
/// `vehicoule:music@1.0.0`, the text this SDK was built against.
pub const MUSIC_WIT: &str = include_str!("../../core/contract/wit/music/music.wit");

/// Runs a future that never waits: host imports are synchronous.
pub fn block_on<F: Future>(f: F) -> F::Output {
    match pin!(f).poll(&mut Context::from_waker(Waker::noop())) {
        Poll::Ready(v) => v,
        Poll::Pending => panic!("host imports are synchronous"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn block_on_returns_ready_value() {
        assert_eq!(block_on(async { 7 }), 7);
    }
}
