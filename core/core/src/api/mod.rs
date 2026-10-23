//! The only module flutter_rust_bridge reads (`app/flutter_rust_bridge.yaml`): thin wrappers
//! over the core, ids as strings. Everything but `init_app` needs `init_app` first.

pub mod app;
pub mod catalog;
pub mod library;
pub mod playback;
pub mod plugins;
pub mod settings;
pub mod system;

use tokio::sync::broadcast::{Sender, error::RecvError};

use crate::app::app;

/// Forwards a broadcast to Dart until Dart stops listening (`add` fails). A lagging stream
/// skips what it missed: the next message carries the current state.
fn forward<T: Clone + Send + 'static>(tx: &Sender<T>, add: impl Fn(T) -> bool + Send + 'static) {
    let mut rx = tx.subscribe();
    app().rt.spawn(async move {
        loop {
            match rx.recv().await {
                Ok(v) => {
                    if !add(v) {
                        break;
                    }
                }
                Err(RecvError::Closed) => break,
                Err(RecvError::Lagged(_)) => {}
            }
        }
    });
}
