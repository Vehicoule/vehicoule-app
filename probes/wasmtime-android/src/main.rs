//! Usage: wasmtime-android-probe <dir with echo.wasm, spin.wasm, hog.wasm>
use std::time::Instant;

use plugin_host::{Host, Limits};

#[tokio::main]
async fn main() {
    let dir = std::env::args().nth(1).unwrap_or_else(|| ".".into());
    let host = Host::new().expect("host");
    println!("pulley: {}", host.is_pulley());

    let mut plugins = Vec::new();
    for name in ["echo", "spin", "hog"] {
        let wasm = std::fs::read(format!("{dir}/{name}.wasm")).expect("read component");
        let t = Instant::now();
        let p = host.compile(&wasm).expect("compile");
        println!("compile {name}: {} ms ({} KiB)", t.elapsed().as_millis(), wasm.len() / 1024);
        plugins.push(p);
    }
    let [echo, spin, hog] = &plugins[..] else { unreachable!() };

    let cases = [
        ("echo http://example.com", echo, "http://example.com/", Limits::default()),
        ("spin, default fuel", spin, "", Limits::default()),
        ("spin, unlimited fuel", spin, "", Limits { fuel: u64::MAX, ..Limits::default() }),
        ("hog, 64 MiB", hog, "", Limits::default()),
        // Last: without JNI init, rustls-platform-verifier panics on Android.
        ("echo https://example.com", echo, "https://example.com/", Limits::default()),
    ];
    for (label, p, input, limits) in cases {
        let t = Instant::now();
        let r = host.run(p, input, limits).await;
        println!("{label}: {r:?} in {} ms", t.elapsed().as_millis());
    }
}
