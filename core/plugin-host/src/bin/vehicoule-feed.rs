//! Feed signing tool: `keygen <secret-file>` generates an ed25519 key pair, `sign
//! <payload.json> <secret-file>` produces the signed `feed.json` envelope on stdout.

use std::io::Write;

use base64::Engine as _;
use base64::engine::general_purpose::STANDARD as BASE64;
use ed25519_dalek::SigningKey;
use plugin_host::{Feed, fingerprint, sign_feed, verify_feed};

fn main() {
    let args: Vec<String> = std::env::args().collect();
    match (args.get(1).map(String::as_str), args.len()) {
        (Some("keygen"), 3) => keygen(&args[2]),
        (Some("sign"), 4) => sign(&args[2], &args[3]),
        _ => usage(),
    }
}

fn usage() -> ! {
    eprintln!("usage: vehicoule-feed keygen <secret-file>");
    eprintln!("       vehicoule-feed sign <payload.json> <secret-file>");
    std::process::exit(2);
}

fn fail(msg: impl std::fmt::Display) -> ! {
    eprintln!("error: {msg}");
    std::process::exit(1);
}

fn keygen(secret_path: &str) {
    let mut secret = [0u8; 32];
    if let Err(e) = getrandom::fill(&mut secret) {
        fail(format!("generating secret key: {e}"));
    }

    let mut file = open_new_secret_file(secret_path).unwrap_or_else(|e| {
        if e.kind() == std::io::ErrorKind::AlreadyExists {
            fail(format!(
                "{secret_path:?} already exists, refusing to overwrite"
            ));
        }
        fail(format!("creating {secret_path:?}: {e}"));
    });
    writeln!(file, "{}", to_hex(&secret))
        .unwrap_or_else(|e| fail(format!("writing {secret_path:?}: {e}")));

    let key = SigningKey::from_bytes(&secret);
    let public_key = key.verifying_key().to_bytes();
    println!("public key: {}", BASE64.encode(public_key));
    println!("fingerprint: {}", fingerprint(&public_key));
}

/// Fails if `secret_path` already exists; mode 0600 on unix.
fn open_new_secret_file(secret_path: &str) -> std::io::Result<std::fs::File> {
    let mut options = std::fs::OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    options.open(secret_path)
}

fn sign(payload_path: &str, secret_path: &str) {
    let secret_hex = std::fs::read_to_string(secret_path)
        .unwrap_or_else(|e| fail(format!("reading {secret_path:?}: {e}")));
    let secret =
        from_hex(secret_hex.trim()).unwrap_or_else(|e| fail(format!("{secret_path:?}: {e}")));
    let key = SigningKey::from_bytes(&secret);

    let payload_bytes = std::fs::read(payload_path)
        .unwrap_or_else(|e| fail(format!("reading {payload_path:?}: {e}")));
    let feed: Feed = serde_json::from_slice(&payload_bytes)
        .unwrap_or_else(|e| fail(format!("{payload_path:?}: {e}")));

    let envelope = sign_feed(&feed, &key);

    let public_key = key.verifying_key().to_bytes();
    if let Err(e) = verify_feed(&envelope, &[public_key], None) {
        fail(format!("signed feed failed self-verification: {e:?}"));
    }

    std::io::stdout()
        .write_all(&envelope)
        .unwrap_or_else(|e| fail(format!("writing stdout: {e}")));
}

fn to_hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn from_hex(s: &str) -> Result<[u8; 32], String> {
    if s.len() != 64 {
        return Err(format!("expected 64 hex chars, got {}", s.len()));
    }
    let mut out = [0u8; 32];
    for (i, chunk) in s.as_bytes().chunks(2).enumerate() {
        let byte_str = std::str::from_utf8(chunk).map_err(|_| "invalid hex".to_string())?;
        out[i] = u8::from_str_radix(byte_str, 16).map_err(|_| "invalid hex".to_string())?;
    }
    Ok(out)
}
