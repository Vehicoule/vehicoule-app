//! Per-plugin HTTP rate limiting: `acquire` waits for a token instead of ever failing.

use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use crate::manifest::RateLimit;

struct Inner {
    remaining: u32,
    window_start: Instant,
}

/// Fixed-window limiter: up to `requests` calls per `per_seconds` window; once the window's
/// tokens are spent, `acquire` sleeps until the next window instead of returning an error.
/// Cheap to clone (an `Arc` inside): one instance lives in the plugin's loaded state and is
/// shared, unchanged, by every call the plugin makes.
// ponytail: fixed window, not a sliding one, so a burst can straddle a window edge (e.g. 2
// requests at t=0.99s, 2 more at t=1.00s); move to a real token bucket if that bursting matters.
#[derive(Clone)]
pub struct RateLimiter {
    inner: Arc<Mutex<Inner>>,
    capacity: u32,
    window: Duration,
}

impl RateLimiter {
    pub fn new(limit: RateLimit) -> Self {
        let inner = Inner { remaining: limit.requests, window_start: Instant::now() };
        RateLimiter {
            inner: Arc::new(Mutex::new(inner)),
            capacity: limit.requests,
            window: Duration::from_secs(u64::from(limit.per_seconds)),
        }
    }

    /// Waits for, then takes, one token. Never returns an error.
    pub async fn acquire(&self) {
        loop {
            let wait = {
                let mut inner = self.inner.lock().unwrap();
                let now = Instant::now();
                if now.duration_since(inner.window_start) >= self.window {
                    inner.window_start = now;
                    inner.remaining = self.capacity;
                }
                if inner.remaining > 0 {
                    inner.remaining -= 1;
                    None
                } else {
                    Some(self.window.saturating_sub(now.duration_since(inner.window_start)))
                }
            };
            match wait {
                None => return,
                Some(d) => tokio::time::sleep(d).await,
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn first_capacity_tokens_are_free() {
        let rl = RateLimiter::new(RateLimit { requests: 3, per_seconds: 60 });
        let start = Instant::now();
        for _ in 0..3 {
            rl.acquire().await;
        }
        assert!(start.elapsed() < Duration::from_millis(50), "{:?}", start.elapsed());
    }

    #[tokio::test]
    async fn fourth_token_waits_for_the_next_window() {
        let rl = RateLimiter::new(RateLimit { requests: 1, per_seconds: 1 });
        rl.acquire().await;
        let start = Instant::now();
        rl.acquire().await;
        let elapsed = start.elapsed();
        assert!(elapsed >= Duration::from_millis(900), "{elapsed:?}");
    }

    #[tokio::test]
    async fn shared_clone_sees_the_same_bucket() {
        let rl = RateLimiter::new(RateLimit { requests: 1, per_seconds: 60 });
        let other = rl.clone();
        rl.acquire().await;
        let start = Instant::now();
        // Only 60s would free a second token; bound the wait so a regression fails fast.
        tokio::time::timeout(Duration::from_millis(200), other.acquire()).await.unwrap_err();
        assert!(start.elapsed() >= Duration::from_millis(200));
    }
}
