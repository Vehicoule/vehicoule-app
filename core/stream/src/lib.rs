//! Fetches the core makes itself, with a client from plugin-host (`Host::http_client`):
//! artwork cache, chunked downloads with resume.

pub mod artwork;
pub mod download;

/// Never carries a URL: reqwest errors are stripped of theirs.
#[derive(Debug, Clone, PartialEq)]
pub enum StreamError {
    Network(String),
    /// A status other than 2xx (and the 416 that ends a complete download).
    Http(u16),
    /// The final size, or the size the server announced, is not the expected one.
    SizeMismatch {
        expected: u64,
        got: u64,
    },
    /// Artwork over its cap.
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
