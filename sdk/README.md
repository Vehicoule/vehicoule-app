# vehicoule-sdk

Aides côté plugin (guest) pour le contrat `vehicoule:music@1.1.0` : bindings des imports de
l'hôte (`http`, `kv`, `clock`, `log`), types partagés (`types::Track`, `types::Error`…),
JSON typé sur HTTP et traduction des statuts fournisseur en erreurs typées.

Le SDK dépend du **WIT** de `core/contract` (`wit/host/host.wit`, `wit/music/music.wit`),
pas de la crate `contract`, qui tire Wasmtime.

## Dépendance

```toml
[dependencies]
vehicoule-sdk = { git = "file:///Users/btw/Documents/repo/Vehicoule", tag = "contract-v1.1.0" }
wit-bindgen = "0.63"
```

## Monde d'un plugin

Un plugin n'exporte que les capacités qu'il implémente. Dans `wit/world.wit` :

```wit
package exemple:paroles;

world plugin {
    include vehicoule:host/imports@1.0.0;
    export vehicoule:music/lyrics@1.1.0;
}
```

Les paquets du contrat sont vendorisés un dossier par paquet (`wit/host/host.wit`,
`wit/music/music.wit`) ; le macro reçoit la liste `[wit/host, wit/music, wit]`, dans cet
ordre. L'option `with` réutilise les bindings du SDK au lieu de les regénérer :

```rust
wit_bindgen::generate!({
    path: ["wit/host", "wit/music", "wit"],
    world: "exemple:paroles/plugin",
    with: {
        "vehicoule:host/http@1.0.0": vehicoule_sdk::host_http,
        "vehicoule:host/kv@1.0.0": vehicoule_sdk::kv,
        "vehicoule:host/clock@1.0.0": vehicoule_sdk::clock,
        "vehicoule:host/log@1.0.0": vehicoule_sdk::log,
        "vehicoule:music/types@1.1.0": vehicoule_sdk::types,
    },
});

use exports::vehicoule::music::lyrics::{Guest, Lyrics};
use vehicoule_sdk::serde::Deserialize;
use vehicoule_sdk::types::{Error, TrackQuery};

#[derive(Deserialize)]
#[serde(crate = "vehicoule_sdk::serde")]
struct Found {
    #[serde(rename = "plainLyrics")]
    plain: Option<String>,
}

struct Paroles;

impl Guest for Paroles {
    fn fetch(track: TrackQuery) -> Result<Lyrics, Error> {
        let q = vehicoule_sdk::query(&[("track_name", &track.title)]);
        // Statut 429 → rate-limited, 403 → provider-wall, 404 → not-found, 5xx → network ;
        // champ requis absent → internal("…champ…"), champs inconnus ignorés.
        let found: Found = vehicoule_sdk::get_json(&format!("https://exemple.org/get?{q}"), &[])?;
        Ok(Lyrics { plain: found.plain, synced: vec![] })
    }
}

export!(Paroles);
```

Les imports de l'hôte sont synchrones côté plugin : `vehicoule_sdk::block_on` conduit un
futur qui n'attend jamais (il panique sur `Pending`).

## Limites de l'hôte

- `http.send-batch` : **8** requêtes au plus par lot.
- `kv` : clé ≤ **128 octets** et valeur ≤ **64 Kio**, sinon `too-large` ; **1 Mio** par plugin
  (clés et valeurs cumulées), sinon `quota-exceeded`.

## Vendorisation vérifiée

Un dépôt de plugin qui dérive du tag compilerait contre un autre contrat que l'hôte. Il
garde donc un test qui compare ses fichiers vendorisés aux constantes du SDK, et
`UPDATE_WIT=1` les réécrit :

```rust
#[test]
fn wit_deps_match_sdk() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
    for (path, text) in [("wit/host/host.wit", vehicoule_sdk::HOST_WIT), ("wit/music/music.wit", vehicoule_sdk::MUSIC_WIT)] {
        let path = root.join(path);
        if std::env::var_os("UPDATE_WIT").is_some() {
            std::fs::create_dir_all(path.parent().unwrap()).unwrap();
            std::fs::write(&path, text).unwrap();
        }
        assert_eq!(std::fs::read_to_string(&path).unwrap(), text, "{} differs from the SDK: UPDATE_WIT=1", path.display());
    }
}
```
