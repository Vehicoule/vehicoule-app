//! Fetches the core makes itself, with a client from plugin-host (`Host::http_client`):
//! artwork cache now, chunked downloads with resume later (task 6).

pub mod artwork;

/// Never carries a URL: reqwest errors are stripped of theirs.
#[derive(Debug, Clone, PartialEq)]
pub enum StreamError {
    Network(String),
    Status(u16),
    TooLarge,
    Io(String),
}

impl From<reqwest::Error> for StreamError {
    fn from(e: reqwest::Error) -> Self {
        StreamError::Network(e.without_url().to_string())
    }
}

impl From<std::io::Error> for StreamError {
    fn from(e: std::io::Error) -> Self {
        StreamError::Io(e.to_string())
    }
}
