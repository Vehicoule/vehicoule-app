use contract::http::{Host, HttpError, Request, Response};
use futures::future::join_all;

use crate::engine::State;
use crate::net::{CacheCtx, fetch};

const MAX_BATCH: usize = 8;

impl Host for State {
    async fn send(&mut self, req: Request) -> Result<Response, HttpError> {
        let cache = CacheCtx {
            storage: &*self.storage,
            plugin: &self.plugin,
            capability: self.capability,
        };
        fetch(
            &self.net,
            &self.allowlist,
            req,
            self.max_response_bytes,
            &self.http_budget,
            self.rate_limiter.as_ref().map(|rl| (rl, self.deadline)),
            self.user_agent.as_deref(),
            Some(cache),
        )
        .await
    }

    /// At most 8 requests, run concurrently: the shared `http_budget` (behind a `Mutex`) and
    /// `rate_limiter` make every member safe no matter how their hops interleave.
    async fn send_batch(&mut self, reqs: Vec<Request>) -> Vec<Result<Response, HttpError>> {
        if reqs.len() > MAX_BATCH {
            let denied = HttpError::Denied(format!("more than {MAX_BATCH} requests in a batch"));
            return vec![Err(denied); reqs.len()];
        }
        let (net, allow, max_body) = (&self.net, &self.allowlist, self.max_response_bytes);
        let (budget, ua) = (&self.http_budget, self.user_agent.as_deref());
        let rate_limiter = self.rate_limiter.as_ref().map(|rl| (rl, self.deadline));
        let cache = CacheCtx {
            storage: &*self.storage,
            plugin: &self.plugin,
            capability: self.capability,
        };
        join_all(reqs.into_iter().map(|req| {
            fetch(
                net,
                allow,
                req,
                max_body,
                budget,
                rate_limiter,
                ua,
                Some(cache),
            )
        }))
        .await
    }
}
