//! Allocates 100 MiB.
wit_bindgen::generate!({ path: "../../../contract/wit", world: "probe" });

struct Hog;

impl Guest for Hog {
    fn run(_: String) -> Result<String, String> {
        let v = std::hint::black_box(vec![1u8; 100 << 20]);
        Ok(v.len().to_string())
    }
}

export!(Hog);
