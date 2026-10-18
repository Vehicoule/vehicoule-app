//! Never returns.
wit_bindgen::generate!({ path: "../../../contract/wit", world: "probe" });

struct Spin;

impl Guest for Spin {
    fn run(_: String) -> Result<String, String> {
        loop {
            std::hint::black_box(());
        }
    }
}

export!(Spin);
