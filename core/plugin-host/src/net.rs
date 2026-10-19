//! Network policy for plugin HTTP and for URLs plugins return. Task 3 adds the filtering
//! resolver, manual redirects and the replay policy.

use std::time::Duration;

#[derive(Clone)]
pub struct NetPolicy {
    client: reqwest::Client,
    pub(crate) https_only: bool,
}

impl Default for NetPolicy {
    /// https only.
    fn default() -> Self {
        NetPolicy { client: builder().build().expect("http client"), https_only: true }
    }
}

fn builder() -> reqwest::ClientBuilder {
    reqwest::Client::builder().no_proxy().timeout(Duration::from_secs(20))
}

impl NetPolicy {
    /// The client plugin requests go through; also for the core's own fetches of returned URLs.
    pub fn client(&self) -> reqwest::Client {
        self.client.clone()
    }

    /// Plain http allowed; any `*.test` host resolves to 127.0.0.1, any other host fails.
    #[cfg(any(test, feature = "test-util"))]
    pub fn for_tests() -> NetPolicy {
        let client = builder().dns_resolver(std::sync::Arc::new(TestResolver)).build().expect("http client");
        NetPolicy { client, https_only: false }
    }
}

#[cfg(any(test, feature = "test-util"))]
struct TestResolver;

#[cfg(any(test, feature = "test-util"))]
impl reqwest::dns::Resolve for TestResolver {
    fn resolve(&self, name: reqwest::dns::Name) -> reqwest::dns::Resolving {
        let host = name.as_str().trim_end_matches('.').to_ascii_lowercase();
        Box::pin(async move {
            if !host.ends_with(".test") {
                return Err(format!("test resolver only knows *.test, not {host}").into());
            }
            let addr = std::net::SocketAddr::from(([127, 0, 0, 1], 0));
            Ok(Box::new(std::iter::once(addr)) as reqwest::dns::Addrs)
        })
    }
}
