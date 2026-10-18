//! Same dependencies as the wasmtime probe minus Wasmtime: the size baseline.
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let url = std::env::args().nth(1).unwrap_or_else(|| "http://example.com/".into());
    let resp = reqwest::get(&url).await?;
    println!("{}", resp.status());
    let mut body = Vec::new();
    let mut resp = resp;
    while let Some(c) = resp.chunk().await? {
        body.extend_from_slice(&c);
    }
    println!("{} bytes", body.len());
    Ok(())
}
