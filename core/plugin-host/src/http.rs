use contract::http::{Host, HttpError, Request, Response};

use crate::engine::State;
use crate::net::fetch;

const MAX_BATCH: usize = 8;

impl Host for State {
    async fn send(&mut self, req: Request) -> Result<Response, HttpError> {
        // ponytail: counted for `CallReport` only; task 4 enforces `max_http_calls`/`max_http_bytes`.
        fetch(&self.net, &self.allowlist, req, self.max_response_bytes, &mut self.http_calls).await
    }

    // ponytail: sequential, not concurrent as the WIT says; plan 2 runs the batch concurrently.
    async fn send_batch(&mut self, reqs: Vec<Request>) -> Vec<Result<Response, HttpError>> {
        if reqs.len() > MAX_BATCH {
            let denied = HttpError::Denied(format!("more than {MAX_BATCH} requests in a batch"));
            return vec![Err(denied); reqs.len()];
        }
        let mut out = Vec::with_capacity(reqs.len());
        for req in reqs {
            out.push(self.send(req).await);
        }
        out
    }
}
