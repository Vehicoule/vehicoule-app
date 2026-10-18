use contract::vehicoule::host::http::{Host, HttpError, Request, Response};

use crate::engine::State;

impl Host for State {
    /// Reads the body as a stream and stops at `max_response_bytes`.
    async fn send(&mut self, req: Request) -> Result<Response, HttpError> {
        let method = reqwest::Method::from_bytes(req.method.as_bytes()).map_err(|e| HttpError::Network(e.to_string()))?;
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
        Ok(Response { status, headers, body })
    }
}

fn net(e: reqwest::Error) -> HttpError {
    if e.is_timeout() { HttpError::Timeout } else { HttpError::Network(e.to_string()) }
}
