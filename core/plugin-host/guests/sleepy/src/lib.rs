//! Blocks 5 s inside a host call (WASI poll), where epoch checks never run.
wit_bindgen::generate!({ path: "../../../contract/wit", world: "probe" });

struct Sleepy;

impl Guest for Sleepy {
    fn run(_: String) -> Result<String, String> {
        std::thread::sleep(std::time::Duration::from_secs(5));
        Ok("woke".into())
    }
}

export!(Sleepy);
