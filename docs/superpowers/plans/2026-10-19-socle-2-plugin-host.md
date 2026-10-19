# Socle 2 — Plugin-host durci : plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** transformer l'hôte minimal de l'étape 1 en hôte de production : manifeste,
appels typés par capacité, réseau verrouillé (domaines, IP privées, redirections), budgets
HTTP, limite de débit, cache HTTP, `kv` persistant, journaux, cache de compilation, feeds
signés.

**Architecture :** `plugin-host` reste une crate séparée que seul `core` voit. Il ne connaît
pas SQLite : la persistance (`plugin_kv`, `http_cache`) passe par un trait `Storage` que
`core` implémente (plan 3/4). Tout l'accès réseau des plugins passe par l'implémentation
hôte de `vehicoule:host/http` ; les vérifications y vivent toutes, et le même client gardé
sert au cœur pour les URLs renvoyées par les plugins (téléchargements, pochettes).

**Tech Stack :** Wasmtime 48.0.6 (Pulley, async, fuel, epoch), wasmtime-wasi p2, reqwest
0.13 (rustls), tokio, `url`, serde / serde_json, sha2, ed25519-dalek 3, base64, wiremock.

**Spec :** `docs/superpowers/specs/2026-10-18-socle-musique-design.md` (v4), sections 4.1,
4.3, 4.4, 6, 8. Rapport : `docs/superpowers/reports/2026-10-etape-1-faisabilite.md`
(constats 2, 3, 4). Prérequis : plan 1 (`contract-v1.0.0`).

## Global Constraints

- Dépôt `/Users/btw/Documents/repo/Vehicoule`, branche `socle-2-plugin-host`. Licence
  MPL-2.0. Commit = `git commit -s -m "<msg>" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"`.
- Wasmtime **48.0.6** (LTS), cible **`pulley64`** partout, compilation sur l'appareil. Seul
  artefact compilé jamais chargé : celui que l'hôte a lui-même produit sur cet appareil.
- Budgets par appel (`Limits::default()`) : fuel **200 000 000** (à calibrer sur téléphone,
  plan 6), epoch **300 ticks de 100 ms (30 s)**, aussi en délai mural, mémoire **64 Mio**
  cumulée sur toutes les mémoires, réponse **8 Mio**, **24 requêtes HTTP** et **16 Mio**
  échangés (corps envoyés + reçus) par appel, **5 redirections** par requête, lot de
  **8**.
- `kv` : clé ≤ **128 octets**, valeur ≤ **64 Kio**, **1 Mio** par plugin.
- Journaux : message tronqué à **2 Kio**, **200 lignes** par appel au plus.
- Réseau : `https` seulement ; hôte = nom de domaine (jamais une IP littérale), port par
  défaut, pas d'identifiants dans l'URL, aucun proxy système. Toute adresse non publique
  après résolution DNS est refusée, même pour un domaine autorisé.
- Cache HTTP : `GET` 2xx seulement ; capacités catalogue (`search`, `suggest`, `entity`,
  `lyrics`, `radio`) = durée `max(max-age, 24 h)` sauf `no-store` ; **jamais** pendant
  `resolve` ; en cas d'erreur réseau, une entrée périmée est servie (hors ligne).
- User-Agent descriptif quand le manifeste le demande :
  `Vehicoule/<version> (+https://vehicoule.app)`.
- Le futur de chaque appel de capacité est **`Send`** : `core` les lance sur un runtime
  tokio multi-thread et derrière flutter_rust_bridge.
- Feeds : ed25519, séquence croissante (égale acceptée, plus petite refusée), sha256 du
  `.wasm` et du manifeste.
- Fonctions réservées aux tests derrière la feature **`test-util`** ; jamais activée par
  `core`.

## Review Focus

1. **URL avec une IP littérale** (`https://127.0.0.1/`, `https://[::1]/`,
   `https://2130706433/`) : reqwest n'appelle pas le résolveur DNS pour une IP, donc le
   filtre DNS ne la voit pas ; elle doit être refusée avant l'envoi.
   → test `ip_literal_hosts_are_denied` (tâche 3).
2. **Redirection d'un domaine autorisé vers un domaine non autorisé ou vers une IP privée**
   → refusée, et les en-têtes `Authorization` / `Cookie` ne suivent jamais un changement
   d'hôte. → tests `redirect_to_foreign_domain_is_denied`,
   `credentials_dropped_on_cross_host_redirect` (tâche 3).
3. **Adresse IPv6 qui cache une IPv4 privée** (`::ffff:10.0.0.1`, `64:ff9b::a00:1`) →
   refusée. → cas dans `private_addresses_are_refused` (tâche 3).
4. **Fichier du cache de compilation corrompu ou d'une autre version de Wasmtime** → l'hôte
   recompile au lieu de planter. → test `corrupt_compile_cache_is_rebuilt` (tâche 2).
5. **Plugin qui renvoie une URL de flux ou de pochette hors de ses domaines** : le flux est
   refusé (`internal`), la pochette est retirée de la réponse.
   → test `returned_urls_are_checked` (tâche 2).

---

### Task 1 : manifeste et liste de domaines

**Files :**
- Create : `core/plugin-host/src/manifest.rs`
- Modify : `core/plugin-host/src/lib.rs`, `Cargo.toml` (`serde`, `serde_json`, `url`)
- Test : `core/plugin-host/src/manifest.rs` (module `#[cfg(test)]`)

**Interfaces :**
- Produces :
  ```rust
  #[derive(Debug, Clone, Deserialize)]
  pub struct Manifest {
      pub id: String,               // ^[a-z0-9][a-z0-9-]{1,39}$
      pub name: String,
      pub version: String,          // semver, informatif
      pub contract: String,         // "1.0" : majeure 1, mineure ≤ 0 acceptée par cet hôte
      pub domains: Vec<String>,     // "api.deezer.com", "*.googlevideo.com"
      pub rate_limit: Option<RateLimit>,
      #[serde(default)] pub descriptive_user_agent: bool,
  }
  #[derive(Debug, Clone, Copy, Deserialize)]
  pub struct RateLimit { pub requests: u32, pub per_seconds: u32 }
  pub fn parse_manifest(json: &[u8]) -> Result<Manifest, String>;   // valide tout ce qui suit
  pub struct Allowlist { /* exact: HashSet<String>, suffixes: Vec<String> */ }
  impl Allowlist {
      pub fn new(domains: &[String]) -> Result<Allowlist, String>;
      pub fn allows(&self, host: &str) -> bool;  // insensible à la casse, point final ignoré
  }
  ```

- [ ] **Step 1 : tests qui échouent**

```rust
#[test] fn wildcard_matches_subdomains_only()   // "*.googlevideo.com" : "rr1---sn-x.googlevideo.com" oui, "a.b.googlevideo.com" oui, "googlevideo.com" non, "evilgooglevideo.com" non
#[test] fn exact_domain_is_case_insensitive()   // "API.Deezer.com." autorisé par "api.deezer.com"
#[test] fn invalid_domains_are_rejected()       // "*", "*.com", "a.*.com", "127.0.0.1", "[::1]", "x.com:443", "" → Err
#[test] fn manifest_rejects_bad_id_and_contract()// id "Deezer" ou "-x" → Err ; contract "2.0" ou "1.1" → Err ; "1.0" → Ok
#[test] fn manifest_parses_example()            // l'exemple deezer ci-dessous → rate_limit Some(45/5)
```
  Exemple :
  `{"id":"deezer","name":"Deezer","version":"1.0.0","contract":"1.0","domains":["api.deezer.com","*.dzcdn.net"],"rate_limit":{"requests":45,"per_seconds":5}}`
- [ ] **Step 2 : vérifier l'échec** — `cargo test -p plugin-host manifest` → FAIL.
- [ ] **Step 3 : implémenter.** Un joker = `*.` suivi d'au moins deux labels ; pas d'IP ni de
  port ; tout en minuscules.
- [ ] **Step 4 : vérifier** — PASS.
- [ ] **Step 5 : commit** — `feat(plugin-host): manifeste et domaines autorisés`.

### Task 2 : API par capacité, erreurs typées, cache de compilation

Remplace l'API provisoire du plan 1 (`compile`, `search(&str)`, `exports()`).

**Files :**
- Modify : `core/plugin-host/src/engine.rs`, `src/lib.rs`
- Create : `core/plugin-host/src/calls.rs` (une fonction publique par capacité)
- Modify : `core/Cargo.toml` (commentaire sur la feature `cache` : « compiled code only
  comes from this device: plugin-host's own compile cache »)
- Modify : `core/plugin-host/guests/` : remplacer `echo` par `probe` (commandes ci-dessous),
  garder `spin`, `hog`, `sleepy`, `lyrics-only`
- Test : `core/plugin-host/tests/calls.rs`, `tests/budgets.rs` (migré)

**Interfaces :**
- Consumes : `contract::{types, music::*}` (plan 1), `Manifest`, `Allowlist` (tâche 1).
- Produces :
  ```rust
  pub struct HostConfig {
      pub cache_dir: PathBuf,                              // composants compilés
      pub storage: Arc<dyn Storage>,                       // tâche 5
      pub events: Arc<dyn Fn(HostEvent) + Send + Sync>,
      pub limits: Limits,
      pub app_version: String,
      pub net: NetPolicy,                                  // tâche 3 ; NetPolicy::default() dans l'app
  }
  pub enum HostEvent {
      Log { plugin: String, level: LogLevel, message: String },
      Call(CallReport),
  }
  pub struct CallReport { pub plugin: String, pub capability: Capability, pub fuel_used: u64,
                          pub http_calls: u32, pub wall_ms: u64, pub outcome: Result<(), CallError> }
  #[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
  pub enum Capability { Search, Suggest, Entity, Resolve, Lyrics, Radio }
  #[derive(Debug, Clone, PartialEq)]
  pub enum CallError { Network(String), ProviderWall(String), RateLimited, NotFound, Expired,
                       Internal(String), BudgetExceeded(Budget), Unsupported }
  #[derive(Debug, Clone, Copy, PartialEq, Eq)]
  pub enum Budget { Fuel, Time, Memory, Http }
  pub enum LoadError { Manifest(String), Contract(String), Compile(String) }
  pub struct Limits { pub fuel: u64, pub epoch_ticks: u64, pub memory_bytes: usize,
                      pub max_response_bytes: usize, pub max_http_calls: u32, pub max_http_bytes: usize }

  impl Host {
      pub fn new(cfg: HostConfig) -> anyhow::Result<Host>;
      pub fn load(&self, manifest_json: &[u8], wasm: &[u8]) -> Result<Plugin, LoadError>;
      pub fn check_url(&self, p: &Plugin, url: &str) -> Result<url::Url, String>; // schéma, hôte, allowlist
      pub async fn search(&self, p: &Plugin, req: SearchRequest) -> Result<SearchResults, CallError>;
      pub async fn suggest(&self, p: &Plugin, prefix: &str, region: &str) -> Result<Vec<String>, CallError>;
      pub async fn fetch_entity(&self, p: &Plugin, target: EntityRef, region: &str, cursor: Option<String>) -> Result<EntityPage, CallError>;
      pub async fn parse_link(&self, p: &Plugin, url: &str) -> Result<Option<EntityRef>, CallError>;
      pub async fn resolve(&self, p: &Plugin, req: ResolveRequest) -> Result<Resolved, CallError>;
      pub async fn lyrics(&self, p: &Plugin, track: TrackQuery) -> Result<Lyrics, CallError>;
      pub async fn radio(&self, p: &Plugin, seed: TrackQuery, region: &str, limit: u32) -> Result<Vec<Track>, CallError>;
  }
  impl Plugin {   // Clone (Arc interne), Send + Sync
      pub fn id(&self) -> &str;  pub fn manifest(&self) -> &Manifest;
      pub fn capabilities(&self) -> &[Capability];
  }
  pub use contract::{types, music};   // types WIT pour core
  ```
- Commandes du guest `probe` (dans `search-request.query`, résultat dans les titres des
  tracks) : `get <url>` (statut), `count <url> <n>` (n GET séquentiels, renvoie le nombre de
  succès), `batch <url> <n>` (un `send-batch` de n), `kv-set <k> <v>`, `kv-get <k>`,
  `print <texte>` (stdout), `log <texte>`, `art <url>` (renvoie un track dont `artwork` =
  `[url]`). Pour `resolve`, le monde de `probe` exporte aussi `resolve` : l'URL du flux =
  `req.track.title`.

- [ ] **Step 1 : tests qui échouent** (`tests/calls.rs`, hôte construit avec
  `NetPolicy::for_tests()` et `MemoryStorage`). Cette tâche crée ces deux types sous leur
  forme finale de signature : `NetPolicy` avec `Default` et `for_tests()` (pas encore de
  filtrage), `Storage` avec les seules méthodes `kv_*` ; la tâche 3 ajoute le filtrage, la
  tâche 5 les méthodes `cache_*`.

```rust
#[tokio::test] async fn search_roundtrips_typed_records()    // probe "get <mock>" → tracks[0].title == "200"
#[tokio::test] async fn missing_capability_is_unsupported()  // lyrics-only.search(...) → Err(Unsupported) ; capabilities() == [Lyrics]
#[tokio::test] async fn guest_errors_keep_their_type()       // probe "get <mock 429>" côté guest → Err(RateLimited) via sdk::status_error
#[tokio::test] async fn returned_urls_are_checked()          // resolve vers un domaine hors manifeste → Err(Internal(_)) ; "art https://evil.test/a.jpg" → artwork vide
#[tokio::test] async fn compile_cache_is_reused()            // 2e load du même wasm : fichier .cwasm présent, CallReport identique
#[tokio::test] async fn corrupt_compile_cache_is_rebuilt()   // écraser le .cwasm avec des octets aléatoires → load Ok, appel Ok
#[tokio::test] async fn call_report_counts_fuel_and_http()   // probe "count <mock> 3" → report.http_calls == 3, fuel_used > 0
#[test] fn calls_are_send()                                 // fn assert_send<T: Send>(_: &T) {} sur le futur de host.search(&p, req)
#[test] fn contract_major_mismatch_is_refused()             // manifeste "contract":"2.0" → LoadError::Contract
```
  Migrer `budgets.rs` : `OutOfFuel` → `Err(BudgetExceeded(Fuel))`, `Deadline` →
  `BudgetExceeded(Time)`, `Memory` → `BudgetExceeded(Memory)` ; le test du composant C du
  plan 1 garde son entrée `get <url>`.
- [ ] **Step 2 : vérifier l'échec** — `cargo test -p plugin-host` → FAIL.
- [ ] **Step 3 : implémenter.**
  - `load` : `parse_manifest`, contrôle du contrat, puis cache disque
    `cache_dir/<sha256(wasm)>-<hash de Engine::precompile_compatibility_hash()>.cwasm` :
    `Component::deserialize_file` (unsafe, commentaire : seul l'hôte écrit ce dossier
    privé de l'app), échec → `Component::new` + `serialize` + écriture atomique (fichier
    temporaire + `rename`). `InstancePre` construit une fois ; capacités = modules dont
    `GuestIndices::new(&pre)` réussit.
  - Un appel = `Store` neuf, mêmes budgets que l'étape 1 (fuel, epoch, délai mural,
    `Budget` mémoire cumulée), `instantiate_async`, `GuestIndices::load`, appel.
  - Correspondance des erreurs : trap `OutOfFuel` → `Fuel` ; `Interrupt` ou délai mural →
    `Time` ; mémoire refusée → `Memory` ; budget HTTP touché pendant l'appel **et** résultat
    `Err` du guest → `Http` ; autre trap → `Internal` ; `Err(types::Error)` → variante du
    même nom.
  - Contrôle des URLs renvoyées : `source.url` hors `check_url` → `Internal("stream url outside allowlist")` ;
    images hors `check_url` retirées des `artwork` de tous les records renvoyés.
  - Émettre `HostEvent::Call` à la fin de chaque appel (fuel consommé = fuel initial −
    `store.get_fuel()`).
- [ ] **Step 4 : vérifier** — `cargo test --manifest-path core/Cargo.toml` → PASS.
- [ ] **Step 5 : commit** — `feat(plugin-host): appels par capacité, erreurs typées, cache de compilation`.

### Task 3 : réseau verrouillé (domaines, IP privées, redirections) et rejeu pour les tests

**Files :**
- Create : `core/plugin-host/src/net.rs`
- Modify : `core/plugin-host/src/http.rs`, `Cargo.toml` (feature `test-util`)
- Create : `core/plugin-host/src/replay.rs` (`#[cfg(feature = "test-util")]`)
- Test : `core/plugin-host/src/net.rs` (unitaires), `tests/net.rs`

**Interfaces :**
- Produces :
  ```rust
  pub fn is_public(ip: IpAddr) -> bool;
  #[derive(Clone)] pub struct NetPolicy { /* client gardé, https_only, allow_loopback, replay */ }
  impl Default for NetPolicy;                         // https seulement, IP publiques seulement
  impl NetPolicy {
      pub fn client(&self) -> reqwest::Client;        // même résolveur filtrant, .no_proxy(), redirections désactivées ; sert aussi à core/stream
      #[cfg(feature = "test-util")] pub fn for_tests() -> NetPolicy;          // http permis, bouclage permis
      #[cfg(feature = "test-util")] pub fn replay(dir: &Path) -> NetPolicy;   // réponses enregistrées, aucun réseau
  }
  pub(crate) async fn fetch(policy: &NetPolicy, allow: &Allowlist, req: Request, budget: &mut HttpBudget) -> Result<Response, HttpError>;
  ```
- Format du rejeu : `dir/index.json` = liste de `{ "method": "GET", "url": "…", "status": 200,
  "headers": [["content-type","application/json"]], "body_file": "deezer_search.json" }` ;
  une requête absente de l'index → `HttpError::Network("no recording for GET <url>")`. Les
  contrôles d'allowlist s'appliquent aussi en rejeu.

- [ ] **Step 1 : tests qui échouent**

```rust
#[test] fn private_addresses_are_refused()  // false pour : 0.0.0.0, 10.1.2.3, 100.64.0.1, 127.0.0.1, 169.254.1.1, 172.16.0.1, 192.0.0.1, 192.0.2.1, 192.168.1.1, 198.18.0.1, 198.51.100.1, 203.0.113.1, 224.0.0.1, 240.0.0.1, 255.255.255.255, ::, ::1, fc00::1, fe80::1, ff02::1, 2001:db8::1, ::ffff:10.0.0.1, 64:ff9b::a00:1 ; true pour 1.1.1.1, 2606:4700::1111, ::ffff:1.1.1.1
#[tokio::test] async fn ip_literal_hosts_are_denied()          // https://127.0.0.1/, https://[::1]/, https://2130706433/ → Denied, même avec NetPolicy::default()
#[tokio::test] async fn non_https_and_userinfo_are_denied()    // http:// (policy par défaut), https://u:p@api.deezer.com/ → Denied
#[tokio::test] async fn domain_outside_manifest_is_denied()    // Denied("example.org not allowed"), aucune requête émise
#[tokio::test] async fn dns_to_private_ip_is_denied()          // résolveur de test : "rebind.test" → 10.0.0.1 → Denied
#[tokio::test] async fn redirect_to_foreign_domain_is_denied()
#[tokio::test] async fn redirect_hops_are_capped_at_5()        // 6 redirections → Network("too many redirects")
#[tokio::test] async fn see_other_becomes_get_without_body()   // 303 après POST → GET sans corps ; 307 garde POST et corps
#[tokio::test] async fn credentials_dropped_on_cross_host_redirect()
#[tokio::test] async fn final_url_is_reported()                // response.url == URL après redirections
#[tokio::test] async fn replay_serves_recordings_without_network()
```
  Les tests à domaines utilisent `for_tests()` + un serveur wiremock et un résolveur de test
  qui fait pointer `*.test` vers `127.0.0.1` ; ce résolveur n'existe qu'avec `test-util`.
- [ ] **Step 2 : vérifier l'échec** — `cargo test -p plugin-host --features test-util net` → FAIL.
- [ ] **Step 3 : implémenter.** Résolveur `reqwest::dns::Resolve` qui appelle
  `tokio::net::lookup_host` puis ne garde que les adresses `is_public` (aucune → erreur
  `denied`) : l'adresse contrôlée est celle à laquelle on se connecte, pas de fenêtre de
  rebinding. Redirections suivies à la main dans `fetch` : `Location` résolue contre l'URL
  courante, contrôle complet (schéma, IP littérale, allowlist) à chaque saut, 301/302/303 →
  `GET` sans corps, 307/308 inchangés, `Authorization` et `Cookie` retirés si l'hôte change.
  Chaque saut compte dans le budget HTTP (tâche 4).
- [ ] **Step 4 : vérifier** — PASS.
- [ ] **Step 5 : commit** — `feat(plugin-host): réseau verrouillé et rejeu des réponses`.

### Task 4 : budgets HTTP, lots, limite de débit, User-Agent

**Files :**
- Modify : `core/plugin-host/src/http.rs`, `src/net.rs`
- Create : `core/plugin-host/src/rate.rs`
- Test : `core/plugin-host/tests/net.rs`, `src/rate.rs` (unitaires)

**Interfaces :**
- Produces :
  ```rust
  pub(crate) struct HttpBudget { pub calls: u32, pub bytes: usize, pub hit: bool }  // par appel de capacité
  pub(crate) struct RateLimiter { /* seau à jetons par plugin, partagé entre appels */ }
  impl RateLimiter { pub fn new(limit: RateLimit) -> Self; pub async fn acquire(&self); }
  ```

- [ ] **Step 1 : tests qui échouent**

```rust
#[tokio::test] async fn http_call_cap_is_enforced()      // probe "count <mock> 30" → 24 succès puis BudgetExceeded ; résultat du guest Err → CallError::BudgetExceeded(Http)
#[tokio::test] async fn http_byte_cap_is_enforced()      // 3 réponses de 7 Mio → la 3e refusée (16 Mio)
#[tokio::test] async fn batch_runs_concurrently()         // batch de 8 vers un mock qui répond en 500 ms → < 1,5 s au total
#[tokio::test] async fn batch_over_8_is_denied()          // 9 requêtes → 9 × Denied("batch over 8")
#[tokio::test(start_paused = true)] async fn rate_limit_waits_instead_of_failing() // 2 req / 1 s, 5 requêtes → toutes OK, ≥ 2 s de temps simulé
#[tokio::test] async fn descriptive_user_agent_is_set()   // manifeste descriptive_user_agent: true → "Vehicoule/<app_version> (+https://vehicoule.app)" ; false → User-Agent du plugin conservé
```
- [ ] **Step 2 : vérifier l'échec** → FAIL.
- [ ] **Step 3 : implémenter.** `HttpBudget` vit dans `State` (un par appel) ; le dépasser
  renvoie `http-error::budget-exceeded` et met `hit = true`. Lot : `futures::future::join_all`
  sur les `fetch`, budget partagé sous `Mutex`. `RateLimiter` : seau de capacité `requests`,
  rechargé de `requests` tous les `per_seconds`, `acquire` dort jusqu'au prochain jeton ; un
  par plugin, conservé dans `Plugin`.
- [ ] **Step 4 : vérifier** → PASS.
- [ ] **Step 5 : commit** — `feat(plugin-host): budgets HTTP, lots, limite de débit`.

### Task 5 : `Storage` (kv persistant, cache HTTP), journaux, horloge

`kv` persistant est ce qui permet au plugin ytmusic de garder son `visitorData` d'un appel à
l'autre (constat 4 du rapport).

**Files :**
- Create : `core/plugin-host/src/storage.rs`, `src/cache.rs`
- Modify : `core/plugin-host/src/engine.rs` (imports `kv`, `clock`, `log`, stdout/stderr WASI)
- Test : `core/plugin-host/tests/storage.rs`, `src/cache.rs` (unitaires)

**Interfaces :**
- Produces :
  ```rust
  pub trait Storage: Send + Sync {
      fn kv_get(&self, plugin: &str, key: &str) -> Option<Vec<u8>>;
      fn kv_set(&self, plugin: &str, key: &str, value: &[u8]);
      fn kv_delete(&self, plugin: &str, key: &str);
      fn kv_usage(&self, plugin: &str) -> u64;                  // octets clés + valeurs
      fn cache_get(&self, key: &[u8; 32]) -> Option<CachedResponse>;
      fn cache_put(&self, key: &[u8; 32], entry: &CachedResponse);
  }
  pub struct CachedResponse { pub plugin: String, pub status: u16, pub url: String,
                              pub headers: Vec<(String, String)>, pub body: Vec<u8>,
                              pub stored_at_ms: u64, pub expires_at_ms: u64 }
  #[cfg(feature = "test-util")] pub struct MemoryStorage;     // impl Storage, Default
  pub(crate) fn cache_key(plugin: &str, req: &Request) -> [u8; 32]; // sha256(plugin, méthode, URL, en-têtes triés)
  pub(crate) fn ttl_ms(headers: &[(String, String)], capability: Capability) -> Option<u64>; // None = ne pas garder
  pub enum LogLevel { Debug, Info, Warn, Error }
  ```

- [ ] **Step 1 : tests qui échouent**

```rust
#[tokio::test] async fn kv_survives_between_calls()        // probe "kv-set visitor abc" puis, appel suivant, "kv-get visitor" → "abc"
#[tokio::test] async fn kv_is_isolated_per_plugin()         // même wasm chargé sous deux ids → le 2e ne voit rien
#[tokio::test] async fn kv_limits_are_enforced()            // clé de 129 o → TooLarge ; valeur 64 Kio + 1 → TooLarge ; cumul > 1 Mio → QuotaExceeded
#[test] fn catalog_ttl_is_at_least_24h()                    // ttl_ms([("cache-control","max-age=60")], Search) == 86_400_000 ; max-age=172800 → 172_800_000
#[test] fn no_store_and_resolve_are_never_cached()          // no-store → None ; ttl_ms(_, Resolve) → None
#[tokio::test] async fn get_is_served_from_cache()          // 2e search identique : le mock n'a reçu qu'une requête
#[tokio::test] async fn stale_cache_served_when_offline()   // entrée expirée + serveur arrêté → réponse en cache
#[tokio::test] async fn resolve_never_hits_cache()
#[tokio::test] async fn stdout_and_log_reach_events()       // "print hé" et "log hé" → HostEvent::Log { plugin, message: "hé" }
#[tokio::test] async fn log_lines_are_capped()              // 500 lignes → 200 événements, message > 2 Kio tronqué
```
- [ ] **Step 2 : vérifier l'échec** → FAIL.
- [ ] **Step 3 : implémenter.** stdout/stderr WASI : `WasiCtxBuilder::stdout` avec un flux
  qui découpe par ligne et émet `HostEvent::Log` (niveau `Info` pour stdout, `Warn` pour
  stderr). `clock.now-ms` = `SystemTime`. Le cache n'est consulté que pour les `GET` hors
  `resolve` ; entrées > 2 Mio non gardées.
- [ ] **Step 4 : vérifier** → PASS.
- [ ] **Step 5 : commit** — `feat(plugin-host): kv persistant, cache HTTP, journaux`.

### Task 6 : feeds signés

**Files :**
- Create : `core/plugin-host/src/feed.rs`, `core/plugin-host/src/bin/vehicoule-feed.rs`
- Modify : `Cargo.toml` (`ed25519-dalek = { version = "3", features = ["rand_core"] }`, `base64`, `sha2`)
- Test : `core/plugin-host/src/feed.rs` (unitaires)

**Interfaces :**
- Produces :
  ```rust
  #[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
  pub struct Feed { pub name: String, pub sequence: u64, pub plugins: Vec<FeedEntry> }
  #[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
  pub struct FeedEntry { pub id: String, pub version: String, pub contract: String,
                         pub wasm_url: String, pub wasm_sha256: String,       // URLs relatives au feed permises
                         pub manifest_url: String, pub manifest_sha256: String }
  #[derive(Debug, PartialEq)]
  pub enum FeedError { Malformed(String), BadSignature, Rollback { seen: u64, got: u64 } }
  pub fn verify_feed(bytes: &[u8], trusted: &[[u8; 32]], last_sequence: Option<u64>) -> Result<Feed, FeedError>;
  pub fn sign_feed(feed: &Feed, key: &ed25519_dalek::SigningKey) -> Vec<u8>;
  pub fn fingerprint(public_key: &[u8; 32]) -> String;   // 16 premiers octets du sha256, hex, groupes de 4 : "ab12 cd34 …"
  pub fn sha256_matches(bytes: &[u8], hex: &str) -> bool;
  ```
- Fichier `feed.json` : `{"payload":"<base64 du JSON de Feed>","signatures":[{"key":"<base64 32 o>","sig":"<base64 64 o>"}]}` ;
  la signature porte sur les octets exacts du payload (pas de canonisation). Valide si une
  signature d'une clé de confiance est correcte.
- Binaire : `vehicoule-feed keygen <fichier-secret>` (écrit la clé secrète en hex, affiche
  la clé publique en base64 et l'empreinte) ; `vehicoule-feed sign <payload.json> <fichier-secret>`
  (écrit `feed.json` sur stdout).

- [ ] **Step 1 : tests qui échouent**

```rust
#[test] fn signed_feed_verifies()
#[test] fn second_trusted_key_also_verifies()     // clé de rotation : trusted = [k1, k2], signé par k2 → Ok
#[test] fn tampered_payload_is_rejected()         // 1 octet modifié → BadSignature
#[test] fn unknown_key_is_rejected()
#[test] fn older_sequence_is_rejected()           // last 7, feed 6 → Rollback { seen: 7, got: 6 } ; feed 7 → Ok
#[test] fn fingerprint_is_stable()                // clé fixe → chaîne attendue écrite en dur
#[test] fn sha256_check_is_case_insensitive()
```
- [ ] **Step 2 : vérifier l'échec** → FAIL.
- [ ] **Step 3 : implémenter.**
- [ ] **Step 4 : vérifier** — `cargo test --manifest-path core/Cargo.toml --all-features` → PASS ;
  `cargo clippy --manifest-path core/Cargo.toml --all-targets --all-features -- -D warnings` → OK.
- [ ] **Step 5 : commit** — `feat(plugin-host): feeds signés et outil vehicoule-feed`.
