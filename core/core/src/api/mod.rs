//! The only module flutter_rust_bridge reads (`app/flutter_rust_bridge.yaml`): thin wrappers
//! over the core, ids as strings. Everything but `init_app` needs `init_app` first.

pub mod app;
pub mod browse;
pub mod catalog;
pub mod library;
pub mod playback;
pub mod plugins;
pub mod settings;
pub mod system;

use tokio::sync::broadcast::{Receiver, error::RecvError};

use crate::app::app;
use crate::logs;

/// Forwards a broadcast to Dart until Dart stops listening (`add` fails). A lagging stream
/// skips what it missed, logged: the next state message carries the current state, but a
/// dropped `PlayerCommand` is lost.
fn forward<T: Clone + Send + 'static>(
    mut rx: Receiver<T>,
    add: impl Fn(T) -> bool + Send + 'static,
) {
    app().rt.spawn(async move {
        loop {
            match rx.recv().await {
                Ok(v) => {
                    if !add(v) {
                        break;
                    }
                }
                Err(RecvError::Closed) => break,
                Err(RecvError::Lagged(n)) => {
                    logs::push("warn", "bridge", &format!("{n} messages dropped"));
                }
            }
        }
    });
}

#[cfg(test)]
mod tests {
    use std::sync::Mutex;
    use std::sync::mpsc;
    use std::time::Duration;

    use tokio::sync::broadcast;

    use super::forward;
    use crate::app::test_app;

    #[test]
    fn a_lagging_stream_logs_what_it_dropped() {
        test_app();
        let (tx, _) = broadcast::channel::<u32>(4);
        let (open, gate) = mpsc::channel::<()>();
        let (seen, got) = mpsc::channel::<u32>();
        let gate = Mutex::new(Some(gate));
        forward(tx.subscribe(), move |v| {
            // Held on the first message while 10 more are sent.
            if let Some(g) = gate.lock().unwrap().take() {
                let _ = g.recv();
            }
            seen.send(v).is_ok()
        });
        for i in 0..=10 {
            tx.send(i).unwrap();
        }
        open.send(()).unwrap();
        while got.recv_timeout(Duration::from_secs(5)).unwrap() != 10 {}
        let logged = crate::logs::recent();
        assert!(
            logged.iter().any(|l| l.level == "warn"
                && l.source == "bridge"
                && l.message.contains("dropped")),
            "{logged:?}"
        );
    }
}
