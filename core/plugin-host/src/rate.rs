//! Per-plugin HTTP rate limiting: `acquire` waits for a slot instead of ever failing outright,
//! unless that wait would run past the call's own wall-clock deadline.

use std::collections::VecDeque;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use tokio::time::Instant;

use crate::manifest::RateLimit;

/// Kept clear of the call's wall-clock deadline: a wait that would finish closer than this to
/// it fails fast instead, so the call ends as `BudgetExceeded(Http)` rather than running out
/// the clock and ending as `BudgetExceeded(Time)` while still holding the instance.
const DEADLINE_MARGIN: Duration = Duration::from_secs(1);

/// Sliding-log limiter: at most `requests` sends in any trailing `per_seconds` window (unlike a
/// fixed window, this can never let `2 * requests` through around a window edge). Cheap to
/// clone (an `Arc` inside): one instance lives in the plugin's loaded state and is shared,
/// unchanged, by every call the plugin makes.
#[derive(Clone)]
pub struct RateLimiter {
    /// Send times still inside the trailing window, oldest first.
    log: Arc<Mutex<VecDeque<Instant>>>,
    capacity: usize,
    window: Duration,
}

impl RateLimiter {
    pub fn new(limit: RateLimit) -> Self {
        RateLimiter {
            log: Arc::new(Mutex::new(VecDeque::with_capacity(limit.requests as usize))),
            capacity: limit.requests as usize,
            window: Duration::from_secs(u64::from(limit.per_seconds)),
        }
    }

    /// Waits for, then takes, one slot. Returns `Err(())` instead of waiting past
    /// `deadline - DEADLINE_MARGIN`; never otherwise fails. Uses `tokio::time::Instant`
    /// throughout so a `#[tokio::test(start_paused = true)]` can drive it without real sleeps.
    pub async fn acquire(&self, deadline: Instant) -> Result<(), ()> {
        loop {
            let wait_until = {
                let mut log = self.log.lock().unwrap();
                let now = Instant::now();
                while log.front().is_some_and(|&t| now.duration_since(t) >= self.window) {
                    log.pop_front();
                }
                if log.len() < self.capacity {
                    log.push_back(now);
                    None
                } else {
                    Some(*log.front().unwrap() + self.window)
                }
            };
            match wait_until {
                None => return Ok(()),
                Some(until) => {
                    if until + DEADLINE_MARGIN > deadline {
                        return Err(());
                    }
                    tokio::time::sleep_until(until).await;
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const FAR: Duration = Duration::from_secs(3600);

    #[tokio::test(start_paused = true)]
    async fn first_capacity_tokens_are_free() {
        let rl = RateLimiter::new(RateLimit { requests: 3, per_seconds: 60 });
        let deadline = Instant::now() + FAR;
        let start = Instant::now();
        for _ in 0..3 {
            rl.acquire(deadline).await.unwrap();
        }
        assert!(start.elapsed() < Duration::from_millis(50), "{:?}", start.elapsed());
    }

    #[tokio::test(start_paused = true)]
    async fn fourth_token_waits_for_the_next_window() {
        let rl = RateLimiter::new(RateLimit { requests: 1, per_seconds: 1 });
        let deadline = Instant::now() + FAR;
        rl.acquire(deadline).await.unwrap();
        let start = Instant::now();
        rl.acquire(deadline).await.unwrap();
        assert!(start.elapsed() >= Duration::from_millis(900), "{:?}", start.elapsed());
    }

    #[tokio::test(start_paused = true)]
    async fn shared_clone_sees_the_same_bucket() {
        let rl = RateLimiter::new(RateLimit { requests: 1, per_seconds: 60 });
        let other = rl.clone();
        let now = Instant::now();
        rl.acquire(now + FAR).await.unwrap();
        // A separate bucket would have its own free slot and succeed immediately; the shared
        // one needs the 60 s window, which a deadline this close can't afford.
        assert!(other.acquire(now + Duration::from_millis(500)).await.is_err());
    }

    /// Sliding log, not a fixed window: no run of acquisitions may put more than `capacity`
    /// timestamps inside any trailing `window`-long span.
    #[tokio::test(start_paused = true)]
    async fn never_more_than_n_in_any_window() {
        let rl = RateLimiter::new(RateLimit { requests: 3, per_seconds: 1 });
        let deadline = Instant::now() + Duration::from_secs(120);
        let mut times = Vec::new();
        for _ in 0..10 {
            rl.acquire(deadline).await.unwrap();
            times.push(Instant::now());
        }
        for win_start in &times {
            let in_window =
                times.iter().filter(|t| **t >= *win_start && **t < *win_start + Duration::from_secs(1)).count();
            assert!(in_window <= 3, "{times:?}");
        }
    }

    #[tokio::test(start_paused = true)]
    async fn rate_wait_past_deadline_fails_fast() {
        let rl = RateLimiter::new(RateLimit { requests: 1, per_seconds: 60 });
        let now = Instant::now();
        rl.acquire(now + FAR).await.unwrap();
        // The next slot is 60 s away; a deadline only 500 ms out leaves no room for it.
        assert!(rl.acquire(now + Duration::from_millis(500)).await.is_err());
    }

    /// Companion to the previous test: a wait that comfortably fits before the deadline still
    /// waits rather than failing fast.
    #[tokio::test(start_paused = true)]
    async fn rate_wait_within_deadline_still_waits() {
        let rl = RateLimiter::new(RateLimit { requests: 1, per_seconds: 1 });
        let now = Instant::now();
        rl.acquire(now + Duration::from_secs(60)).await.unwrap();
        let start = Instant::now();
        rl.acquire(now + Duration::from_secs(60)).await.unwrap();
        assert!(start.elapsed() >= Duration::from_millis(900), "{:?}", start.elapsed());
    }
}
