//! Fetches the URL it is given and returns the HTTP status.
wit_bindgen::generate!({ path: "../../../contract/wit", world: "probe" });

use vehicoule::host::http::{Request, send};

struct Echo;

impl Guest for Echo {
    fn run(url: String) -> Result<String, String> {
        let req = Request { method: "GET".into(), url, headers: vec![], body: None };
        send(&req).map(|r| r.status.to_string()).map_err(|e| format!("{e:?}"))
    }
}

export!(Echo);
