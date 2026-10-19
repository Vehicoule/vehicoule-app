# Socle 1 — Contrat WIT 1.0 : plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** figer le contrat des plugins en WIT (`vehicoule:host@1.0.0`, `vehicoule:music@1.0.0`),
générer les bindings hôte dans `core/contract`, créer le SDK guest `sdk/`, et faire passer
`plugin-host` et ses composants de test sur ce contrat.

**Architecture :** `core/contract/wit/` est la seule source de vérité. Côté hôte,
`wasmtime::component::bindgen!` génère les types et un `GuestIndices` par interface exportée :
l'hôte détecte une capacité en essayant de construire l'index (absent = capacité absente).
Côté guest, chaque plugin écrit son propre monde (`include vehicoule:host/imports` + les
exports qu'il implémente) et réutilise les types du SDK via l'option `with` de wit-bindgen.

**Tech Stack :** WIT, Wasmtime 48.0.6 (bindgen async), wit-bindgen 0.63, cible
`wasm32-wasip2`, serde / serde_json, wasm-tools (vérification).

**Spec :** `docs/superpowers/specs/2026-10-18-socle-musique-design.md` (v4), sections 4.1,
4.2, 4.3 (compatibilité), 6, 12. Rapport : `docs/superpowers/reports/2026-10-etape-1-faisabilite.md`.

**Ordre des plans du socle :** 1 (ce plan) → 2 plugin-host → 3 bibliothèque → 4 core + pont
→ 5 coques Flutter ; 6 plugins dès que 1 et 2 sont faits.

## Global Constraints

- Dépôt : `/Users/btw/Documents/repo/Vehicoule`, branche `socle-1-contrat` depuis `main`.
- Licences : `core/contract` et `sdk/` = **MIT OR Apache-2.0** (fichiers `LICENSE-MIT`,
  `LICENSE-APACHE` dans chaque crate) ; le reste = MPL-2.0.
- Commits : `git commit -s` (DCO), dernière ligne du message
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Aucun code porté depuis Auqw ou Klaxon. Pas de shim de compatibilité avec le contrat 0.1
  de l'étape 1 : il est remplacé.
- Paquets : `vehicoule:host@1.0.0` (importé par les plugins), `vehicoule:music@1.0.0`
  (exporté). Les données sont des `record` / `variant` WIT, jamais du JSON.
- **Règle de compatibilité** : une mineure n'ajoute que des fonctions ou des interfaces ; tout
  changement de `record` ou de signature = majeure. Un test fige donc le texte WIT 1.0.
- Erreurs typées de la spec 6 : `network`, `provider-wall`, `rate-limited`, `not-found`,
  `expired`, `internal` côté plugin ; `budget-exceeded` est produit par l'hôte seul.
- `resolve` reçoit dès la 1.0 : référence du titre, qualité `low`/`normal`/`high`, région,
  candidats déjà essayés ; renvoie URL, en-têtes, expiration, format, candidats,
  `loudness-db` optionnel.
- Lot HTTP : **8** requêtes au plus par `send-batch`.
- Noms réservés du modèle de composants async : ne jamais nommer un type `stream` ni
  `future`.
- Le SDK et les plugins dépendent de ce dépôt par tag Git : tag **`contract-v1.0.0`** posé en
  fin de plan. Tant qu'aucun remote n'existe, les dépôts de plugins utilisent
  `git = "file:///Users/btw/Documents/repo/Vehicoule"`.

## Review Focus

1. **Plugin qui n'exporte qu'une partie des capacités** (lrclib n'exporte que `lyrics`) :
   l'hôte doit le charger et ne lister que ses exports, pas refuser le composant.
   → test `partial_exports_are_detected` (tâche 3).
2. **Modification involontaire d'un `record` après le tag** : casse tous les plugins publiés.
   → test `wit_1_0_is_frozen` (tâche 1).
3. **Réponse fournisseur avec champs inconnus ou manquants** : le parsing typé du SDK ignore
   les champs inconnus et renvoie `internal("…champ…")` sur un champ requis absent, sans
   paniquer. → test `get_json_reports_missing_field` (tâche 2).
4. **Statut HTTP fournisseur 429 / 403 / 404 / 5xx** : le SDK les traduit en erreurs typées
   (`rate-limited`, `provider-wall`, `not-found`, `network`) pour que le routage du cœur passe
   au plugin suivant. → test `status_maps_to_typed_errors` (tâche 2).
5. **Vendorisation du WIT dans un dépôt de plugins qui dérive du tag** : un plugin compilerait
   contre un contrat différent de celui de l'hôte. → constante `HOST_WIT` / `MUSIC_WIT` du SDK
   (tâche 2), contrôlée par le test `wit_deps_match_sdk` du plan 6.

---

### Task 1 : fichiers WIT 1.0 et bindings hôte

**Files :**
- Replace : `core/contract/wit/host.wit`
- Create : `core/contract/wit/music.wit`
- Modify : `core/contract/src/lib.rs`, `core/contract/Cargo.toml` (ajout `sha2` en
  dev-dependency)
- Test : `core/contract/tests/frozen.rs`

**Interfaces :**
- Produces (Rust, crate `contract`) : les modules générés par bindgen pour le monde
  `vehicoule:music/plugin@1.0.0`, ré-exportés ainsi :
  ```rust
  pub use vehicoule::host::{http, kv, clock, log};          // traits Host à implémenter
  pub use vehicoule::music::types;                          // Track, Album, Artist, Playlist, Image, Error, TrackQuery, EntityRef, EntityKind…
  pub mod music {                                            // exports, un module par capacité
      pub use crate::exports::vehicoule::music::{search, suggest, entity, resolve, lyrics, radio};
  }
  pub const HOST_WIT: &str;   // include_str!("../wit/host.wit")
  pub const MUSIC_WIT: &str;  // include_str!("../wit/music.wit")
  ```
  Chaque module de `music` expose `GuestIndices::new(&InstancePre<T>) -> wasmtime::Result<GuestIndices>`
  et `GuestIndices::load(&self, store, &Instance) -> wasmtime::Result<Guest>` (vérifié dans
  `wasmtime-internal-component-macro-48.0.6/tests/expanded/multiversion_async.rs`).

- [ ] **Step 1 : écrire `host.wit`** (texte exact, c'est le contrat) :

```wit
package vehicoule:host@1.0.0;

interface http {
    enum method { get, head, post }

    record request {
        method: method,
        url: string,
        headers: list<tuple<string, string>>,
        body: option<list<u8>>,
    }

    record response {
        status: u16,
        /// Final URL, after redirects.
        url: string,
        headers: list<tuple<string, string>>,
        body: list<u8>,
    }

    variant http-error {
        /// DNS, connection or TLS failure.
        network(string),
        timeout,
        /// Body over the per-response cap.
        too-large,
        /// Domain not in the manifest, private address, or scheme refused.
        denied(string),
        /// Request count or byte budget of this call is spent.
        budget-exceeded,
    }

    send: func(req: request) -> result<response, http-error>;
    /// At most 8 requests, run concurrently; results keep the request order.
    send-batch: func(reqs: list<request>) -> list<result<response, http-error>>;
}

/// Per-plugin key-value space, persisted by the host.
interface kv {
    variant kv-error { too-large, quota-exceeded }
    get: func(key: string) -> option<list<u8>>;
    set: func(key: string, value: list<u8>) -> result<_, kv-error>;
    delete: func(key: string);
}

interface clock {
    /// Unix time in milliseconds.
    now-ms: func() -> u64;
}

interface log {
    enum level { debug, info, warn, error }
    log: func(level: level, message: string);
}

world imports {
    import http;
    import kv;
    import clock;
    import log;
}
```

- [ ] **Step 2 : écrire `music.wit`** (texte exact) :

```wit
package vehicoule:music@1.0.0;

interface types {
    variant error {
        network(string),
        /// Bot check, captcha, blocked IP: the provider refuses the session.
        provider-wall(string),
        rate-limited,
        not-found,
        expired,
        internal(string),
    }

    record image { url: string, width: option<u32>, height: option<u32> }
    record artist-ref { id: string, name: string }
    record album-ref { id: string, title: string }

    record track {
        id: string,
        title: string,
        artists: list<artist-ref>,
        album: option<album-ref>,
        duration-ms: option<u32>,
        isrc: option<string>,
        explicit: bool,
        artwork: list<image>,
    }

    record album {
        id: string,
        title: string,
        artists: list<artist-ref>,
        year: option<u16>,
        track-count: option<u32>,
        artwork: list<image>,
    }

    record artist { id: string, name: string, artwork: list<image> }

    record playlist {
        id: string,
        title: string,
        owner: option<string>,
        description: option<string>,
        track-count: option<u32>,
        artwork: list<image>,
    }

    enum entity-kind { track, album, artist, playlist }
    record entity-ref { kind: entity-kind, id: string }

    /// What the core knows about a track, whatever its source.
    /// `id` is this plugin's own id for it, when known.
    record track-query {
        id: option<string>,
        title: string,
        artists: list<string>,
        album: option<string>,
        duration-ms: option<u32>,
        isrc: option<string>,
    }
}

interface search {
    use types.{error, track, album, artist, playlist, entity-kind};
    record search-request {
        query: string,
        kinds: list<entity-kind>,
        region: string,
        limit: u32,
        cursor: option<string>,
    }
    record search-results {
        tracks: list<track>,
        albums: list<album>,
        artists: list<artist>,
        playlists: list<playlist>,
        next: option<string>,
    }
    search: func(req: search-request) -> result<search-results, error>;
}

interface suggest {
    use types.{error};
    suggest: func(prefix: string, region: string) -> result<list<string>, error>;
}

interface entity {
    use types.{error, track, album, artist, playlist, entity-ref};
    variant entity { track(track), album(album), artist(artist), playlist(playlist) }
    record entity-page {
        entity: entity,
        /// Album or playlist tracks, or an artist's top tracks.
        tracks: list<track>,
        /// An artist's albums; empty for other kinds.
        albums: list<album>,
        /// Cursor for the next page of `tracks`.
        next: option<string>,
    }
    fetch: func(target: entity-ref, region: string, cursor: option<string>) -> result<entity-page, error>;
    /// `none` when the link does not belong to this provider.
    parse-link: func(url: string) -> result<option<entity-ref>, error>;
}

interface resolve {
    use types.{error, track-query};
    enum quality { low, normal, high }
    record resolve-request {
        track: track-query,
        quality: quality,
        region: string,
        /// Provider ids already tried for this track; skip them.
        tried: list<string>,
    }
    record source {
        url: string,
        headers: list<tuple<string, string>>,
        expires-at-ms: u64,
        mime: string,
        bitrate: u32,
        content-length: option<u64>,
        /// Loudness above the platform target, in dB (positive = turn down).
        loudness-db: option<f32>,
    }
    record candidate {
        id: string,
        title: string,
        artists: list<string>,
        duration-ms: option<u32>,
        score: f32,
    }
    record resolved {
        /// Provider id of the resolved recording; the core stores it as an external ref.
        id: string,
        source: source,
        /// Other plausible matches, best first, for manual correction.
        candidates: list<candidate>,
    }
    resolve: func(req: resolve-request) -> result<resolved, error>;
}

interface lyrics {
    use types.{error, track-query};
    record line { start-ms: u32, text: string }
    record lyrics { plain: option<string>, synced: list<line> }
    fetch: func(track: track-query) -> result<lyrics, error>;
}

interface radio {
    use types.{error, track, track-query};
    radio: func(seed: track-query, region: string, limit: u32) -> result<list<track>, error>;
}

/// Host-side view: every capability. A plugin targets its own world with only what it implements.
world plugin {
    include vehicoule:host/imports@1.0.0;
    export search;
    export suggest;
    export entity;
    export resolve;
    export lyrics;
    export radio;
}

/// Guest-side helpers (the SDK): host imports and shared types, no exports.
world sdk {
    include vehicoule:host/imports@1.0.0;
    import types;
}
```

- [ ] **Step 3 : écrire le test qui échoue** `core/contract/tests/frozen.rs` :

```rust
#[test]
fn wit_1_0_is_frozen() {
    // Update these hashes only together with a new major version of the packages.
    assert_eq!(sha256_hex(contract::HOST_WIT), "<to fill>");
    assert_eq!(sha256_hex(contract::MUSIC_WIT), "<to fill>");
}

#[test]
fn wit_parses_with_wasm_tools() // `wasm-tools component wit core/contract/wit` exits 0 (skip with a clear panic message if wasm-tools is missing)
```

- [ ] **Step 4 : vérifier l'échec** — `cargo test -p contract` → FAIL (constantes absentes).
- [ ] **Step 5 : implémenter `lib.rs`** : `bindgen!({ path: "wit", world: "vehicoule:music/plugin",
  imports: { default: async }, exports: { default: async } })`, les ré-exports ci-dessus,
  les deux constantes. Remplir les hashes avec la valeur calculée une fois le texte relu
  contre la spec.
- [ ] **Step 6 : vérifier** — `cargo test -p contract` → PASS. Le reste du workspace ne
  compile plus (plugin-host utilise `contract::Probe`) : c'est réparé en tâche 3, ne pas
  commiter avant.

### Task 2 : SDK guest `sdk/`

**Files :**
- Create : `sdk/Cargo.toml` (package `vehicoule-sdk`, lib `vehicoule_sdk`, licence MIT OR
  Apache-2.0, `LICENSE-MIT`, `LICENSE-APACHE`), `sdk/src/lib.rs`, `sdk/src/http.rs`,
  `sdk/README.md`
- Modify : `core/Cargo.toml` (rien : `sdk/` est hors du workspace `core/`, il a son propre
  `[workspace]` vide pour ne pas être capturé)
- Test : `sdk/src/http.rs` (module `#[cfg(test)]`, exécuté en natif)

**Interfaces :**
- Produces :
  ```rust
  pub use wit_bindgen;  pub use serde;  pub use serde_json;
  pub mod bindings;      // wit_bindgen::generate!({ path: "../core/contract/wit", world: "vehicoule:music/sdk", pub_export_macro: false })
  pub use bindings::vehicoule::host::{http as host_http, kv, clock, log};
  pub use bindings::vehicoule::music::types;                     // Track, Error, TrackQuery…
  pub const HOST_WIT: &str;  pub const MUSIC_WIT: &str;          // include_str! des mêmes fichiers
  pub fn block_on<F: Future>(f: F) -> F::Output;                 // host imports are sync: panics if the future is Pending
  pub fn get_json<T: serde::de::DeserializeOwned>(url: &str, headers: &[(&str, &str)]) -> Result<T, types::Error>;
  pub fn status_error(status: u16) -> Option<types::Error>;     // None for 2xx
  pub fn from_http_error(e: host_http::HttpError) -> types::Error;
  pub fn query(pairs: &[(&str, &str)]) -> String;                // application/x-www-form-urlencoded
  ```
- Un plugin génère son monde avec
  `with: { "vehicoule:host/http@1.0.0": vehicoule_sdk::host_http, "vehicoule:host/kv@1.0.0": vehicoule_sdk::kv,
  "vehicoule:host/clock@1.0.0": vehicoule_sdk::clock, "vehicoule:host/log@1.0.0": vehicoule_sdk::log,
  "vehicoule:music/types@1.0.0": vehicoule_sdk::types }` (exemple complet dans `sdk/README.md`).

- [ ] **Step 1 : écrire les tests qui échouent** (natifs, sans appel aux imports) :

```rust
#[test] fn status_maps_to_typed_errors()   // 200 → None ; 429 → RateLimited ; 401, 403 → ProviderWall("HTTP 403") ; 404 → NotFound ; 500, 503 → Network("HTTP 503")
#[test] fn http_error_maps_to_typed_errors()// Network(m) → Network(m) ; Timeout → Network("timeout") ; TooLarge → Internal("response too large") ; Denied(m) → Internal(m) ; BudgetExceeded → Internal("http budget")
#[test] fn get_json_reports_missing_field()// parse_json::<T>(br#"{"a":1}"#) où T exige `b` → Err(Internal(msg)) avec msg contenant "b"
#[test] fn parse_ignores_unknown_fields()  // champ en trop accepté
#[test] fn query_encodes_reserved_chars()  // query(&[("q","AC/DC & Queen")]) == "q=AC%2FDC+%26+Queen"
#[test] fn block_on_returns_ready_value()  // block_on(async { 7 }) == 7
```
  `get_json` = `send` + `status_error` + `parse_json` ; `parse_json<T>(body: &[u8]) -> Result<T, Error>`
  est la partie testée en natif.
- [ ] **Step 2 : vérifier l'échec** — `cargo test --manifest-path sdk/Cargo.toml` → FAIL.
- [ ] **Step 3 : implémenter.** `block_on` : `Context::from_waker(Waker::noop())`, un seul
  `poll`, `Pending` → `panic!("host imports are synchronous")` (aucune dépendance).
  `query` : crate `form_urlencoded`. `BudgetExceeded` devient `internal` : l'hôte remplace
  lui-même le résultat par `budget-exceeded` (plan 2).
- [ ] **Step 4 : vérifier** — `cargo test --manifest-path sdk/Cargo.toml` → PASS ;
  `cargo build --manifest-path sdk/Cargo.toml --target wasm32-wasip2` → OK.
- [ ] **Step 5 : README** du SDK (FR) : monde d'un plugin type, option `with`, vendorisation
  de `wit/deps/` vérifiée par test (modèle du plan 6), exemple `get_json`.

### Task 3 : `plugin-host` et ses composants de test sur le contrat 1.0

Migration minimale pour garder l'arbre vert ; l'API générique et le durcissement sont au
plan 2.

**Files :**
- Modify : `core/plugin-host/src/engine.rs`, `src/http.rs`, `src/lib.rs`
- Modify : `core/plugin-host/guests/{echo,spin,hog,sleepy}/src/lib.rs`, `guests/Cargo.toml`
  (dépendance `vehicoule-sdk = { path = "../../../sdk" }`)
- Create : `core/plugin-host/guests/wit/world.wit`, `core/plugin-host/guests/lyrics-only/`
- Test : `core/plugin-host/tests/budgets.rs`

**Interfaces :**
- Consumes : `contract::{http, music::search, music::lyrics}` (tâche 1),
  `vehicoule_sdk` (tâche 2).
- Produces (provisoire, remplacé au plan 2) :
  ```rust
  impl Host {
      pub fn compile(&self, wasm: &[u8]) -> anyhow::Result<Plugin>;
      pub async fn search(&self, p: &Plugin, query: &str, limits: Limits) -> Result<String, RunError>; // titre du 1er track
  }
  impl Plugin { pub fn exports(&self) -> Vec<&'static str>; } // "search", "lyrics"…
  ```
- Monde des composants de test : `world test-search { include vehicoule:host/imports@1.0.0; export vehicoule:music/search@1.0.0; }`
  et `world test-lyrics { include …; export vehicoule:music/lyrics@1.0.0; }`. Chaque composant
  lit son entrée dans `search-request.query` et renvoie son résultat dans le `title` du
  premier `track`.

- [ ] **Step 1 : adapter les tests** de `tests/budgets.rs` : `run(name, input, limits)` appelle
  `host.search(...)` ; `echo` renvoie le statut en titre (`Ok("204")`) ; les erreurs du
  guest arrivent en `RunError::Guest("Internal(\"response too large\")")`. Ajouter :

```rust
#[tokio::test] async fn partial_exports_are_detected() // lyrics-only: exports() == ["lyrics"] ; echo: exports() == ["search"]
```
- [ ] **Step 2 : vérifier l'échec** — `cargo test -p plugin-host` → FAIL (compilation).
- [ ] **Step 3 : implémenter.** Linker : `contract::http::add_to_linker::<_, HasSelf<State>>`
  et les trois autres interfaces hôte avec des implémentations minimales (`kv` en mémoire
  dans `State`, `clock` = `SystemTime`, `log` ignoré) ; le plan 2 les remplace. `exports()`
  essaie `GuestIndices::new` de chaque module de `contract::music` sur un `InstancePre`.
  Composants : générés avec `wit_bindgen::generate!({ path: "../wit", world: "…", with: {…sdk…} })`.
- [ ] **Step 4 : vérifier** — `cargo test --manifest-path core/Cargo.toml` → PASS (11 tests
  de l'étape 1 + `partial_exports_are_detected`).
- [ ] **Step 5 : commit** (tâches 1 à 3 ensemble, l'arbre n'était pas vert avant) :

```bash
git add core/contract sdk core/plugin-host
git commit -s -m "feat: contrat WIT 1.0, SDK guest, plugin-host sur le contrat 1.0" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 4 : composant non Rust (preuve multi-langages) et tag

**Files :**
- Create : `core/plugin-host/guests/c-echo/echo.c`, `guests/c-echo/build.sh`,
  `guests/c-echo/README.md`, `core/plugin-host/tests/fixtures/c-echo.wasm` (artefact
  commité, ~20 Kio)
- Test : `core/plugin-host/tests/budgets.rs`

**Interfaces :**
- Consumes : `Host::search` (tâche 3).

- [ ] **Step 1 : test qui échoue**

```rust
#[tokio::test] async fn c_component_runs_like_a_rust_one() // c-echo.wasm sur un MockServer 204 → Ok("204")
```
- [ ] **Step 2 : vérifier l'échec** — fixture absente.
- [ ] **Step 3 : écrire `echo.c`** (même comportement que `echo` : `http.send` GET sur la
  requête, statut en titre) et `build.sh` : `wit-bindgen c --world test-search ../wit`, puis
  `$WASI_SDK_PATH/bin/clang --target=wasm32-wasip2 -O2 -o …/fixtures/c-echo.wasm`. Le README
  dit pourquoi l'artefact est commité : le test tourne sans wasi-sdk ; `build.sh` le
  régénère.
- [ ] **Step 4 : vérifier** — `cargo test -p plugin-host c_component` → PASS.
- [ ] **Step 5 : commit puis tag**

```bash
git add core/plugin-host
git commit -s -m "test: composant C, preuve multi-langages" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git tag contract-v1.0.0
```
