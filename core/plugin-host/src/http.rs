use contract::http::{Host, HttpError, Method, Request, Response};

use crate::engine::State;

const MAX_BATCH: usize = 8;

impl Host for State {
    /// Reads the body as a stream and stops at `max_response_bytes`.
    async fn send(&mut self, req: Request) -> Result<Response, HttpError> {
        let method = match req.method {
            Method::Get => reqwest::Method::GET,
            Method::Head => reqwest::Method::HEAD,
            Method::Post => reqwest::Method::POST,
        };
        let mut builder = self.http.request(method, &req.url);
        for (k, v) in &req.headers {
            builder = builder.header(k, v);
        }
        if let Some(body) = req.body {
            builder = builder.body(body);
        }
        let mut resp = builder.send().await.map_err(net)?;
        let max = self.max_response_bytes;
        if resp.content_length().is_some_and(|n| n > max as u64) {
            return Err(HttpError::TooLarge);
        }
        let status = resp.status().as_u16();
        let url = resp.url().to_string();
        let headers = resp
            .headers()
            .iter()
            .map(|(k, v)| (k.to_string(), String::from_utf8_lossy(v.as_bytes()).into_owned()))
            .collect();
        let mut body = Vec::new();
        while let Some(chunk) = resp.chunk().await.map_err(net)? {
            if body.len() + chunk.len() > max {
                return Err(HttpError::TooLarge);
            }
            body.extend_from_slice(&chunk);
        }
        Ok(Response { status, url, headers, body })
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

fn net(e: reqwest::Error) -> HttpError {
    if e.is_timeout() { HttpError::Timeout } else { HttpError::Network(e.to_string()) }
}
