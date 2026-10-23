use std::path::Path;
use std::process::Command;

use sha2::{Digest, Sha256};

fn sha256_hex(text: &str) -> String {
    Sha256::digest(text.as_bytes())
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

#[test]
fn wit_is_frozen() {
    // A published package never changes: update a hash only with a new version (and its tag).
    assert_eq!(
        sha256_hex(contract::HOST_WIT),
        "33d578d40b088073fddf5d879819dad3b62bf6cfe0409620db4661e9e1a1314b"
    );
    assert_eq!(
        sha256_hex(contract::MUSIC_WIT),
        "17957ee74e7dd2464ae3dcbeba7f7a3aa45b9dcbf9238eadb9eeecae24f422e1"
    );
}

fn wasm_tools_wit(dir: &Path) {
    let out = Command::new("wasm-tools")
        .args(["component", "wit"])
        .arg(dir)
        .output()
        .expect("wasm-tools not found: `cargo install wasm-tools`");
    assert!(
        out.status.success(),
        "{}: {}",
        dir.display(),
        String::from_utf8_lossy(&out.stderr)
    );
}

#[test]
fn wit_parses_with_wasm_tools() {
    let wit = Path::new(env!("CARGO_MANIFEST_DIR")).join("wit");
    wasm_tools_wit(&wit.join("host"));

    // wasm-tools resolves foreign packages from `deps/` next to the package.
    let tmp = std::env::temp_dir().join(format!("vehicoule-wit-{}", std::process::id()));
    std::fs::create_dir_all(tmp.join("deps/host")).unwrap();
    std::fs::copy(wit.join("music/music.wit"), tmp.join("music.wit")).unwrap();
    std::fs::copy(wit.join("host/host.wit"), tmp.join("deps/host/host.wit")).unwrap();
    wasm_tools_wit(&tmp);
    std::fs::remove_dir_all(&tmp).unwrap();
}

#[test]
fn music_wit_is_1_1_with_browse() {
    assert!(contract::MUSIC_WIT.starts_with("package vehicoule:music@1.1.0;"));
    assert!(contract::MUSIC_WIT.contains("interface browse {"));
    assert!(contract::MUSIC_WIT.contains("export browse;"));
    assert!(contract::HOST_WIT.contains("package vehicoule:host@1.0.0;"));
}
