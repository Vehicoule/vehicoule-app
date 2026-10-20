# Socle 4 — Cœur et pont flutter_rust_bridge : plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** le cœur Rust qui possède l'état et les règles (plugins, routage, catalogue, file,
lecture décidée côté Rust, téléchargements, paroles, mises à jour, télémétrie) et sa façade
Dart générée par flutter_rust_bridge, prouvée par un test d'intégration sur macOS et un
appel HTTPS réel sur Android.

**Architecture :** `vehicoule-core` (créée au plan 3) gagne un objet `App` global initialisé
par `init_app`, un runtime tokio à lui pour le travail de fond, et un module `api/`, seul
module lu par flutter_rust_bridge. Dart n'appelle que `api/`. Le lecteur Dart exécute des
`PlayerCommand` et renvoie des `PlayerEvent` ; c'est Rust qui choisit la piste suivante et
la pousse ~20 s avant la fin. La crate `stream` fait les téléchargements par morceaux et le
cache des pochettes avec le client réseau gardé de `plugin-host`.

**Tech Stack :** Rust 2024, tokio, flutter_rust_bridge **2.13.0** (crate et paquet Dart à la
même version exacte), plugin-host (plan 2), bibliothèque (plan 3), reqwest 0.13 + rustls +
rustls-platform-verifier 0.7, sentry 0.49, semver, sha2, Flutter 3.47 (squelette de l'app).

**Spec :** `docs/superpowers/specs/2026-10-18-socle-musique-design.md` (v4), sections 1
(périmètre), 3 (flux), 4.4, 4.6, 4.7, 6, 7, 11, 12. Rapport : constats 1, 4, 5 et décision
« YouTube classique en repli ». Prérequis : plans 1, 2, 3.

## Global Constraints

- Dépôt `/Users/btw/Documents/repo/Vehicoule`, branche `socle-4-core`. Licence MPL-2.0.
  Commit = `git commit -s -m "<msg>" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"`.
- **Rust décide, Dart exécute.** Dart ne choisit jamais la piste suivante. Lecture / pause /
  seek vont directement au lecteur Dart, qui les signale en `PlayerEvent` ; tout ce qui
  change de piste ou la file passe par Rust.
- **Préchargement à 20 s de la fin** (`PRELOAD_LEAD_MS = 20_000`) : sans lui, le rapport
  mesure 1,5 s de silence en moyenne entre deux titres (2,5 s au pire).
- Position reçue toutes les **~10 s** ; file écrite en base à chaque changement et à chaque
  position reçue.
- URL expirée (403) → **une seule** nouvelle résolution, reprise à la même position.
- Routage : on passe au plugin suivant sur `not-found`, `rate-limited`, `provider-wall`,
  `budget-exceeded` (et capacité absente) ; on s'arrête sur `network`, `expired`,
  `internal`. Ordre par défaut : catalogue `deezer`, `itunes`, `ytmusic` ; pochettes
  `deezer`, `itunes` ; les autres plugins ensuite, par id.
- Cover Art Archive : pas en v1. Sans identifiant MusicBrainz il n'y a rien à demander ; il
  arrivera avec le plugin MusicBrainz (spec 9). Le repli des pochettes est Deezer → iTunes.
- Profil release du workspace : `opt-level = "s"`, `lto = true`, `codegen-units = 1`,
  `strip = true`, **`panic = "unwind"`** (flutter_rust_bridge transforme alors une panique
  en exception Dart ; +6,46 Mio mesurés pour Wasmtime dans ce profil). Un
  `compile_error!` interdit toute compilation de `vehicoule-core` en `panic = "abort"`.
- **Android :** `rustls-platform-verifier` doit être initialisé par JNI avant toute requête
  HTTPS, sinon reqwest panique (constat 1).
- Futures de l'API publique : `Send` (flutter_rust_bridge et runtime multi-thread).
- `plugin-host` n'est vu que par `core/core/src/plugins.rs` ; un seul point à retirer pour la
  version stores.
- Adresses embarquées : feed officiel `https://feeds.vehicoule.app/official/feed.json`,
  mises à jour `https://updates.vehicoule.app/releases` (redirige vers
  `https://api.github.com/repos/Vehicoule/vehicoule/releases`), télémétrie : DSN lu à la
  compilation dans `VEHICOULE_SENTRY_DSN` (absent = télémétrie impossible).
- Noms d'artefacts de release (stables, compatibles Obtainium) :
  `vehicoule-<version>-android-arm64-v8a.apk`, `vehicoule-<version>-macos.dmg`, chacun avec
  un `<nom>.sha256` à côté.
- Région envoyée aux plugins = pays de la locale de l'appareil (`AppConfig.region`), `US`
  à défaut.
- Télémétrie : rien ne part sans opt-in ; jamais de titre, artiste, recherche, URL, contenu
  de playlist ou identifiant de compte ; filtrage dans l'app avant l'envoi.
- Identité de l'app : `app.vehicoule`.

## Review Focus

1. **La file change après le préchargement** (l'utilisateur ajoute « lire ensuite » ou
   supprime la piste suivante pendant les 20 dernières secondes) : le lecteur ne doit pas
   jouer l'ancienne suivante. → test `queue_edit_after_preload_replaces_next` (tâche 5).
2. **Hors ligne avec des titres non téléchargés dans la file** : ils sont sautés et
   signalés, la lecture continue sur le prochain téléchargé.
   → test `offline_skips_undownloaded_tracks` (tâche 5).
3. **Lien de playlist collé d'un fournisseur inconnu, ou playlist de plusieurs milliers de
   titres** : erreur `not-found` claire dans le premier cas ; import paginé plafonné à
   50 pages sans bloquer l'UI dans le second. → tests `unknown_link_is_not_found`,
   `import_follows_pages_up_to_50` (tâche 3).
4. **Panique dans un message ou une pile qui contient un titre, une recherche ou une URL** :
   rien de tout ça ne part. → test `telemetry_scrubs_titles_urls_queries` (tâche 7).
5. **Fichier de téléchargement interrompu (app tuée) ou URL expirée au milieu** : la reprise
   repart du dernier octet écrit, sans tout retélécharger, et vérifie la taille finale.
   → tests `download_resumes_from_part_file`, `expired_url_mid_download_resolves_again`
   (tâche 6).

---

### Task 1 : socle de la crate (`App`, erreurs, journaux, stockage des plugins)

**Files :**
- Modify : `core/Cargo.toml` (`[profile.release]` ci-dessus, membre `stream`),
  `core/core/Cargo.toml` (`crate-type = ["lib", "cdylib", "staticlib"]`, dépendances
  `plugin-host`, `stream`, `tokio` multi-thread, `flutter_rust_bridge = "=2.13.0"`)
- Create : `core/core/src/app.rs`, `src/error.rs`, `src/logs.rs`, `src/storage.rs`
- Modify : `core/core/src/lib.rs`
- Test : modules `#[cfg(test)]`

**Interfaces :**
- Consumes : `Db` (plan 3), `plugin_host::{Storage, CachedResponse, CallError, HostEvent}` (plan 2).
- Produces :
  ```rust
  pub struct AppConfig { pub data_dir: String, pub cache_dir: String, pub downloads_dir: String,
                         pub app_version: String, pub region: String, pub platform: Platform }
  pub enum Platform { Android, MacOs, Ios, Windows, Linux }
  #[derive(Debug, Clone, PartialEq)]
  pub enum CoreError { Network, ProviderWall, RateLimited, BudgetExceeded, NotFound, Expired,
                       Internal(String), Offline, InvalidFeed, NoPlugin(Capability) }
  // InvalidFeed : feed refusé (clé publique ou URL invalide, signature, feed malformé,
  // retour en arrière de séquence, taille dépassée, feed officiel ajouté à la main) ; sans URL.
  impl From<plugin_host::CallError> for CoreError; impl From<library::DbError> for CoreError;
  // DbError::Invalid(_) → NotFound (argument inconnu ou refusé : playlist, entrée, clé réservée…, pas un bug) ;
  // DbError::Sqlite(_) | Migration(_) → Internal(message).
  pub(crate) struct App { pub db: Db, pub rt: tokio::runtime::Runtime, pub cfg: AppConfig,
                          pub plugins: Plugins, /* tâche 2 */ pub events: Events /* tâche 5 */ }
  pub(crate) fn app() -> &'static App;                     // OnceLock ; panique claire si init_app n'a pas eu lieu
  pub(crate) fn init(cfg: AppConfig) -> Result<(), CoreError>; // idempotent (2e appel = Ok sans rien refaire)
  // logs.rs
  pub struct LogLine { pub at_ms: i64, pub level: String, pub source: String, pub message: String }
  pub fn redact(s: &str) -> String;     // contenu entre guillemets → "…", tout mot contenant "://" → <url>, chiffres > 6 → <n>
  pub(crate) fn push(level: &str, source: &str, message: &str); // tampon circulaire de 2000 lignes, déjà masquées
  pub fn recent() -> Vec<LogLine>;
  // storage.rs
  pub(crate) struct DbStorage(pub Db);  // impl plugin_host::Storage via read_blocking / write_blocking
  ```
- `lib.rs` : `#[cfg(not(panic = "unwind"))] compile_error!("vehicoule-core needs panic = \"unwind\": the bridge turns panics into Dart errors");`
  et un hook de panique qui appelle `logs::push("error", "panic", …)` puis le hook
  précédent.

- [ ] **Step 1 : tests qui échouent**

```rust
#[test] fn init_is_idempotent()                 // init(cfg) deux fois → Ok, même Db
#[test] fn call_errors_map_to_core_errors()     // chaque CallError → variante attendue ; BudgetExceeded(_) → BudgetExceeded ; Unsupported → NoPlugin(cap)
#[test] fn db_errors_map_to_core_errors()       // DbError::Invalid → NotFound ; Sqlite, Migration → Internal
#[test] fn redact_masks_sensitive_parts()       // redact("play \"Halo\" from https://x.y/z?q=a id 12345678") == "play \"…\" from <url> id <n>"
#[test] fn log_buffer_keeps_2000_lines()
#[test] fn db_storage_roundtrips_kv_and_cache()
```
- [ ] **Step 2 : vérifier l'échec** — `cargo test -p vehicoule-core` → FAIL.
- [ ] **Step 3 : implémenter.** Runtime : `tokio::runtime::Builder::new_multi_thread().worker_threads(2).enable_all()`.
  `DbStorage` appelle la base de façon bloquante depuis un appel hôte :
  `// ponytail: short blocking SQLite calls on a tokio worker; move to spawn_blocking if traces show stalls`.
- [ ] **Step 4 : vérifier** → PASS.
- [ ] **Step 5 : commit** — `feat(core): socle du cœur (App, erreurs, journaux masqués)`.

### Task 2 : plugins installés, feeds et routage

**Files :**
- Create : `core/core/src/plugins.rs`, `core/core/src/router.rs`, `core/core/src/keys.rs`
- Test : `core/core/tests/plugins.rs` (feed servi par wiremock, plugin de test `probe` du
  plan 2 compilé par le test), modules `#[cfg(test)]`

**Interfaces :**
- Consumes : `plugin_host::{Host, HostConfig, Plugin, verify_feed, sha256_matches, fingerprint, NetPolicy}`,
  `library::plugins::*`.
- Produces :
  ```rust
  // keys.rs : deux clés publiques du feed officiel (principale + rotation)
  pub const OFFICIAL_FEED_URL: &str = "https://feeds.vehicoule.app/official/feed.json";
  pub const OFFICIAL_KEYS: [[u8; 32]; 2];
  // plugins.rs
  pub(crate) struct Plugins { host: plugin_host::Host, loaded: RwLock<Vec<plugin_host::Plugin>> }
  impl Plugins {
      pub fn new(cfg: &AppConfig, db: &Db, net: NetPolicy) -> anyhow::Result<Plugins>;
      pub async fn load_installed(&self, db: &Db) -> Result<(), CoreError>;     // au démarrage, depuis le disque, sans réseau
      pub async fn refresh_feeds(&self, db: &Db) -> Result<Vec<String>, CoreError>; // ids installés ou mis à jour
      pub async fn preview_feed(&self, url: &str, public_key_b64: &str) -> Result<FeedPreview, CoreError>;
      pub async fn add_feed(&self, db: &Db, url: &str, public_key_b64: &str) -> Result<(), CoreError>;
      pub fn host(&self) -> &plugin_host::Host;
  }
  pub struct FeedPreview { pub name: String, pub fingerprint: String,
                           pub plugins: Vec<PluginPreview> }
  pub struct PluginPreview { pub id: String, pub version: String, pub domains: Vec<String>, pub capabilities: Vec<String> }
  // router.rs
  pub(crate) async fn ordered(cap: Capability) -> Vec<plugin_host::Plugin>;   // ordre utilisateur, sinon défaut
  pub(crate) fn falls_through(e: &plugin_host::CallError) -> bool;
  pub(crate) async fn first_ok<T, F, Fut>(cap: Capability, f: F) -> Result<(plugin_host::Plugin, T), CoreError>
      where F: FnMut(plugin_host::Plugin) -> Fut, Fut: Future<Output = Result<T, plugin_host::CallError>>;
  ```
- Règles : `refresh_feeds` télécharge chaque feed, `verify_feed` avec la dernière séquence
  vue, puis pour chaque entrée de contrat `1.x` nouvelle ou de version différente :
  manifeste + `.wasm`, contrôle sha256, `host.load` (validation), écriture atomique dans
  `<data_dir>/plugins/<id>-<8 premiers hex du sha>.wasm`, ligne `plugins`. Un plugin absent
  du nouveau feed est désactivé, pas supprimé. Échec d'un plugin = journal + on continue.
  L'id d'une entrée de feed doit être égal à l'id de son manifeste (sinon l'entrée est
  ignorée) ; `host.load` (compilation synchrone) est appelé dans `spawn_blocking`.
  `refresh_feeds` n'est jamais appelé pendant `init` ; `App` le lance en tâche de fond
  10 s après le démarrage puis toutes les 24 h.
  Chaque `HostEvent::Log` est versé dans `logs::push` (source = id du plugin) ; chaque
  `HostEvent::Call` aussi, sous la forme `call <capacité> fuel=<n> http=<n> wall=<ms> <issue>` :
  c'est ce que lit la calibration du fuel sur téléphone (plan 6).

- [ ] **Step 1 : tests qui échouent**

```rust
#[tokio::test] async fn feed_installs_and_loads_plugin()      // feed signé (clé de test) → plugin chargé, capabilities lues
#[tokio::test] async fn wrong_wasm_hash_is_not_installed()
#[tokio::test] async fn rollback_feed_is_refused()             // séquence 3 vue, feed 2 servi → rien ne change, erreur journalisée
#[tokio::test] async fn installed_plugins_load_offline()       // après installation, serveur arrêté, nouvel App → plugin chargé
#[tokio::test] async fn preview_shows_fingerprint_and_domains()
#[test] fn default_order_puts_deezer_first()                   // plugins {ytmusic, itunes, deezer, zz} → [deezer, itunes, ytmusic, zz]
#[test] fn routing_falls_through_on_the_four_soft_errors()     // NotFound, RateLimited, ProviderWall, BudgetExceeded(_), Unsupported → true ; Network, Expired, Internal → false
#[tokio::test] async fn first_ok_tries_next_plugin()           // 1er NotFound, 2e Ok → Ok(2e) ; 1er Network → Err(Network) sans essayer le 2e
```
- [ ] **Step 2 : vérifier l'échec** → FAIL.
- [ ] **Step 3 : générer les clés officielles** : deux fois
  `cargo run -p plugin-host --bin vehicoule-feed -- keygen ~/.config/vehicoule/feed-keys/official-N.key`
  (N = 1, 2 ; **hors du dépôt**), recopier les clés publiques dans `keys.rs`. Dire à
  l'utilisateur de sauvegarder ces deux fichiers : sans eux, plus de publication possible.
- [ ] **Step 4 : implémenter.**
- [ ] **Step 5 : vérifier** → PASS.
- [ ] **Step 6 : commit** — `feat(core): feeds, plugins installés, routage par priorité`.

### Task 3 : catalogue (recherche, suggestions, pages, import, pochettes)

**Files :**
- Create : `core/core/src/catalog.rs`, `core/core/src/convert.rs` (WIT → `library::*Data`)
- Create : `core/stream/Cargo.toml` (package `vehicoule-stream`), `core/stream/src/lib.rs`,
  `core/stream/src/artwork.rs`
- Test : `core/core/tests/catalog.rs` (plugin de test « catalogue » : nouveau guest
  `core/core/tests/guests/fake-catalog` qui sert des données fixes et des `not-found`
  configurables par requête), `core/stream/src/artwork.rs`

**Interfaces :**
- Consumes : `router::first_ok`, `library::{catalog, refs, search, likes}`.
- Produces :
  ```rust
  pub struct TrackView { pub id: String, pub title: String, pub artists: Vec<ArtistRefView>,
                         pub album: Option<AlbumRefView>, pub duration_ms: Option<u32>, pub explicit: bool,
                         pub liked: bool, pub downloaded: bool }
  pub struct ArtistRefView { pub id: String, pub name: String }
  pub struct AlbumRefView { pub id: String, pub title: String }
  pub struct CollectionView { pub id: String, pub kind: ItemKind, pub title: String, pub subtitle: Option<String>,
                              pub track_count: Option<u32>, pub liked: bool, pub is_user_playlist: bool } // is_user_playlist ← CollectionRow.user
  pub enum ItemKind { Track, Album, Artist, Playlist }
  pub struct SearchView { pub tracks: Vec<TrackView>, pub albums: Vec<CollectionView>,
                          pub artists: Vec<CollectionView>, pub playlists: Vec<CollectionView>, pub source: String }
  pub struct EntityView { pub header: CollectionView, pub tracks: Vec<TrackView>, pub albums: Vec<CollectionView>,
                          pub next: Option<String>, pub from_cache: bool }
  pub(crate) async fn search(query: &str) -> Result<SearchView, CoreError>;      // résultats vides = not-found → plugin suivant ; enregistre la requête
  pub(crate) async fn suggest(prefix: &str) -> Result<Vec<String>, CoreError>;   // historique local d'abord, puis capacité suggest ; jamais d'erreur bloquante
  pub(crate) async fn entity(id: &str, cursor: Option<String>) -> Result<EntityView, CoreError>; // réseau KO → cache local, from_cache = true
  pub(crate) async fn import_playlist(link: &str) -> Result<String, CoreError>;  // id de la playlist perso créée
  pub(crate) async fn artwork_file(id: &str, size: u32) -> Result<Option<String>, CoreError>; // chemin local
  // stream::artwork
  pub struct ArtworkCache { /* dir, max_bytes = 256 Mio */ }
  impl ArtworkCache { pub fn new(dir: PathBuf, max_bytes: u64) -> Self;
                      pub async fn file(&self, client: &reqwest::Client, url: &url::Url) -> Result<PathBuf, StreamError>;
                      pub fn prune(&self) -> std::io::Result<()>; }                 // plus anciens (mtime) d'abord
  ```
- Pages d'entité : l'en-tête (titre, propriétaire) vient de la première page seulement ; les
  pages suivantes (ytmusic) ont un titre vide.
- Écriture des résultats du catalogue : une erreur d'upsert (`upsert_*`, `set_children`) annule
  tout le `write` et remonte (pas de « journaliser et passer » : il n'y a pas de savepoint par
  upsert, la transaction est déjà dans un état partiel). Vaut pour toute tâche qui écrit des
  résultats du catalogue.
- Pochette choisie : fournisseurs dans l'ordre de la capacité pochettes, la plus petite
  largeur ≥ `size` (sinon la plus grande) ; URL contrôlée par `host.check_url` du plugin
  d'origine avant tout téléchargement, avec le client `host.http_client(&plugin)` (plugin-host : IP littérales refusées, chaque redirection re-vérifiée).
- Hors ligne (`App` sait qu'on est hors ligne, tâche 5) : `search`, `suggest` réseau,
  `entity` non caché, `import` → `CoreError::Offline` sans appel.

- [ ] **Step 1 : tests qui échouent**

```rust
#[tokio::test] async fn search_falls_back_when_first_plugin_finds_nothing()
#[tokio::test] async fn search_results_are_stored_with_refs()   // les ids renvoyés sont des ItemId ; refs (fake, ext) présentes
#[tokio::test] async fn suggestions_start_with_local_history()
#[tokio::test] async fn entity_serves_cache_when_network_fails()
#[tokio::test] async fn unknown_link_is_not_found()
#[tokio::test] async fn import_follows_pages_up_to_50()         // le fake renvoie toujours un `next` → 50 pages, playlist créée
#[tokio::test] async fn offline_search_is_refused_without_calls()
#[tokio::test] async fn artwork_is_downloaded_once()            // stream : 2 appels → 1 requête, même chemin
#[test] fn artwork_cache_prunes_oldest()
```
- [ ] **Step 2 : vérifier l'échec** → FAIL.
- [ ] **Step 3 : implémenter.**
- [ ] **Step 4 : vérifier** → PASS.
- [ ] **Step 5 : commit** — `feat(core): catalogue, import de playlists, pochettes en cache`.

### Task 4 : la file (logique pure)

**Files :**
- Create : `core/core/src/queue.rs`
- Test : même fichier

**Interfaces :**
- Produces :
  ```rust
  #[derive(Clone, Serialize, Deserialize, PartialEq, Debug)]
  pub struct QueueState { pub entries: Vec<QueueEntry>, pub order: Vec<usize>, pub index: usize,
                          pub position_ms: u64, pub shuffle: bool, pub repeat: Repeat, pub context: Option<PlayContext> }
  #[derive(Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Debug)]
  pub struct EntryId(pub uuid::Uuid);
  #[derive(Clone, Serialize, Deserialize, PartialEq, Debug)]
  pub struct QueueEntry { pub id: EntryId, pub item: String, pub from_radio: bool }
  #[derive(Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Debug)] pub enum Repeat { Off, All, One }
  #[derive(Clone, Serialize, Deserialize, PartialEq, Debug)]
  pub struct PlayContext { pub kind: String, pub id: Option<String>, pub title: String } // "album", "playlist", "search", "radio"…
  impl QueueState {
      pub fn play(items: Vec<String>, start: usize, context: Option<PlayContext>, shuffle: bool, seed: u64) -> QueueState;
      pub fn current(&self) -> Option<&QueueEntry>;
      pub fn next(&self) -> Option<&QueueEntry>;                   // ce qui jouera après, selon repeat
      pub fn advance(&mut self) -> Option<&QueueEntry>;            // fin de piste
      pub fn skip_next(&mut self) -> Option<&QueueEntry>;          // bouton suivant (Repeat::One ignoré)
      pub fn previous(&mut self) -> Option<&QueueEntry>;           // > 3 s écoutées : recommence la piste
      pub fn jump_to(&mut self, entry: EntryId) -> bool;           // TrackStarted d'une entrée préchargée
      pub fn enqueue_next(&mut self, items: Vec<String>);
      pub fn enqueue_last(&mut self, items: Vec<String>);
      pub fn append_radio(&mut self, items: Vec<String>);
      pub fn remove(&mut self, entry: EntryId);
      pub fn move_entry(&mut self, entry: EntryId, to: usize);     // position dans l'ordre de lecture
      pub fn set_shuffle(&mut self, on: bool, seed: u64);          // la piste courante reste courante
      pub fn set_repeat(&mut self, r: Repeat);
      pub fn upcoming(&self) -> Vec<&QueueEntry>;                  // ordre de lecture après la courante
  }
  ```

- [ ] **Step 1 : tests qui échouent**

```rust
#[test] fn play_starts_at_index()
#[test] fn next_respects_repeat_modes()               // Off : None en fin ; All : revient au début ; One : même entrée
#[test] fn skip_next_ignores_repeat_one()
#[test] fn previous_restarts_after_3s()               // position 4000 → même entrée, position 0 ; 2000 → entrée précédente
#[test] fn shuffle_keeps_current_and_is_a_permutation()
#[test] fn unshuffle_returns_to_natural_order_at_current()
#[test] fn enqueue_next_goes_right_after_current_even_shuffled()
#[test] fn remove_current_moves_to_next()
#[test] fn duplicates_are_distinct_entries()          // même item deux fois → deux EntryId
#[test] fn state_roundtrips_through_json()
```
- [ ] **Step 2 : vérifier l'échec** → FAIL.
- [ ] **Step 3 : implémenter** (mélange : Fisher-Yates avec un LCG initialisé par `seed`,
  pas de dépendance).
- [ ] **Step 4 : vérifier** → PASS.
- [ ] **Step 5 : commit** — `feat(core): file de lecture`.

### Task 5 : orchestration de la lecture (préchargement, résolution, radio, hors ligne)

**Files :**
- Create : `core/core/src/player.rs`, `core/core/src/events.rs`
- Test : `core/core/tests/player.rs` (lecteur Dart simulé : le test lit les
  `PlayerCommand` et envoie des `PlayerEvent` ; plugin `fake-catalog` exporte aussi
  `resolve` et `radio`), `#[tokio::test(start_paused = true)]` pour le temps

**Interfaces :**
- Consumes : `QueueState`, `router::first_ok`, `library::{refs, plays, downloads, queue, settings}`.
- Produces :
  ```rust
  pub struct Source { pub uri: String, pub headers: Vec<(String, String)> }   // URL http(s) ou chemin de fichier
  pub enum PlayerCommand {
      Play { entry: String, source: Source, position_ms: u64, autoplay: bool, gain_db: f32 },
      EnqueueNext { entry: String, source: Source, gain_db: f32 },
      ReplaceNext { entry: String, source: Source, gain_db: f32 },
      ClearNext,
      Stop,
  }
  pub enum PlayerEvent {
      TrackStarted { entry: String }, Duration { entry: String, ms: u64 },
      Position { entry: String, ms: u64 }, Paused { entry: String, ms: u64 }, Resumed { entry: String },
      Seeked { entry: String, ms: u64 }, Ended { entry: String },
      Error { entry: String, kind: PlayerErrorKind, message: String },
  }
  pub enum PlayerErrorKind { Forbidden, Network, Decode, Other }   // Forbidden = HTTP 403
  pub struct QueueView { pub current: Option<TrackView>, pub upcoming: Vec<TrackView>, pub index: u32,
                         pub shuffle: bool, pub repeat: Repeat, pub context: Option<PlayContext> }
  pub struct NowPlaying { pub track: Option<TrackView>, pub artwork_path: Option<String>, pub duration_ms: Option<u64> }
  pub enum Notice { Skipped { title: String, reason: CoreError }, UpdateAvailable { version: String }, Error(CoreError) }
  pub enum LibraryChanged { Likes, Playlists, Playlist { id: String }, Downloads, History, Plugins }
  // events.rs : diffusions vers Dart (tokio::sync::broadcast, abonnées par les StreamSink de api/)
  pub(crate) struct Events { pub commands, pub queue, pub now_playing, pub library, pub notices, pub downloads }
  // player.rs
  pub(crate) async fn play(items: Vec<String>, start: usize, context: Option<PlayContext>) -> Result<(), CoreError>;
  pub(crate) async fn on_event(e: PlayerEvent);
  pub(crate) async fn skip_next(); pub(crate) async fn previous(position_ms: u64);
  pub(crate) async fn edit(op: QueueOp) -> Result<(), CoreError>;  // enqueue next/last, remove, move, shuffle, repeat, jump
  pub(crate) async fn fix_match(item: &str) -> Result<Vec<Candidate>, CoreError>; // candidats de la dernière résolution ; s'il n'y en a pas (référence déjà connue), `resolve` avec `tried = [id courant]` pour en obtenir
  pub(crate) async fn choose_match(item: &str, candidate_id: &str) -> Result<(), CoreError>; // refs::pin, puis rejoue si c'est la piste courante
  pub(crate) async fn restore();                      // au démarrage : file restaurée, Play { autoplay: false } à la position sauvée
  pub(crate) fn set_online(online: bool);
  pub struct Candidate { pub id: String, pub title: String, pub artists: Vec<String>, pub duration_ms: Option<u32>, pub score: f32 }
  pub const PRELOAD_LEAD_MS: u64 = 20_000;
  ```
- Règles (non déterminées par les signatures) :
  - **Source d'une entrée** : téléchargement terminé → chemin local (+ `loudness_db` stocké) ;
    sinon hors ligne → saut ; sinon `resolve` routé avec `track-query` (titre, artistes,
    album, durée, ISRC ; `id` = référence du plugin, épinglée d'abord), qualité réglée,
    région ; `resolved.id` enregistré par `refs::record` ; URL vérifiée par
    `host.check_url` ; candidats gardés en mémoire pour `fix_match`.
  - **Gain** : normalisation activée → `gain_db = clamp(-loudness_db, -15.0, 0.0)` (on
    baisse seulement, jamais de saturation) ; sinon 0.
  - **Minuteur de préchargement** : réarmé sur `TrackStarted`, `Duration`, `Position`,
    `Seeked`, `Resumed` ; suspendu sur `Paused`. Échéance = durée − position − 20 s (durée :
    `Duration` du lecteur, sinon celle du catalogue). À l'échéance : `next()` ; si aucune
    et radio activée et en ligne → `radio` routée (graine = piste courante, limite 25,
    sans les 50 dernières écoutées) puis `append_radio` ; résoudre la suivante →
    `EnqueueNext`. Une suivante non résoluble est sautée (`Notice::Skipped`), 3 sauts au
    plus par échéance.
  - **Édition de la file après préchargement** : si `next()` change, `ReplaceNext` (ou
    `ClearNext` s'il n'y en a plus) immédiatement.
  - **`TrackStarted`** : `jump_to`, clôture de l'écoute précédente (`plays::set_listened`),
    `plays::start` (source = id du plugin ou `download`), `NowPlaying`, file sauvée.
  - **`Position`** : écoute cumulée mise à jour, file sauvée avec la position.
  - **`Error { Forbidden }`** : une seule nouvelle résolution sans cache, `Play` à la
    dernière position connue ; second échec → candidat suivant (`tried` += id) ; échec
    final → piste suivante + `Notice::Skipped`. `Error { Network }` → pause + `Notice`.
  - **`Ended`** (fin de la dernière piste) : `Repeat::Off` sans radio → `Stop`.

- [ ] **Step 1 : tests qui échouent**

```rust
#[tokio::test(start_paused = true)] async fn preload_fires_20s_before_end()          // durée 180 s : EnqueueNext reçu à t ≈ 160 s, pas avant 159 s
#[tokio::test(start_paused = true)] async fn pause_suspends_preload()
#[tokio::test(start_paused = true)] async fn queue_edit_after_preload_replaces_next()
#[tokio::test(start_paused = true)] async fn radio_extends_the_queue_at_its_end()     // radio activée : EnqueueNext d'un titre radio, QueueView.upcoming non vide
#[tokio::test(start_paused = true)] async fn radio_disabled_stops_at_end()
#[tokio::test] async fn downloaded_file_wins_over_network()                           // Play.source.uri == chemin local, aucun appel resolve
#[tokio::test] async fn offline_skips_undownloaded_tracks()
#[tokio::test] async fn expired_url_is_resolved_once_then_resumes()                   // Error{Forbidden} → 1 resolve → Play{position_ms = dernière position}
#[tokio::test] async fn second_forbidden_tries_next_candidate()                       // tried contient le 1er id
#[tokio::test] async fn no_resolver_reports_no_plugin()                               // aucun plugin `resolve` → Err(NoPlugin(Resolve))
#[tokio::test] async fn history_records_listened_time()
#[tokio::test] async fn restore_resumes_paused_at_saved_position()
#[tokio::test] async fn choose_match_pins_and_replays()
#[test] fn gain_only_turns_down()                                                     // loudness 4.2 → -4.2 ; -3.0 → 0.0 ; 30 → -15
```
- [ ] **Step 2 : vérifier l'échec** → FAIL.
- [ ] **Step 3 : implémenter.** Un seul acteur (tâche tokio + `mpsc`) possède `QueueState`
  et le minuteur ; les fonctions publiques lui envoient des messages : pas de verrou
  partagé sur la file.
- [ ] **Step 4 : vérifier** → PASS.
- [ ] **Step 5 : commit** — `feat(core): lecture décidée par Rust, préchargement à 20 s, radio`.

### Task 6 : téléchargements et paroles

**Files :**
- Create : `core/stream/src/download.rs`, `core/core/src/downloads.rs`, `core/core/src/lyrics.rs`
- Test : `core/stream/src/download.rs` (wiremock), `core/core/tests/downloads.rs`,
  `core/core/tests/lyrics.rs`

**Interfaces :**
- Produces :
  ```rust
  // stream
  pub struct Fetch { pub url: url::Url, pub headers: Vec<(String, String)>, pub expected_len: Option<u64> }
  pub enum StreamError { Network(String), Http(u16), SizeMismatch { expected: u64, got: u64 }, Io(String) }
  pub const CHUNK: u64 = 2 << 20;
  /// Resumes from `<dest>.part`, fetches by `Range` chunks, checks the final size, then renames.
  pub async fn download(client: &reqwest::Client, f: &Fetch, dest: &Path, progress: &mut dyn FnMut(u64, Option<u64>)) -> Result<u64, StreamError>;
  // core
  pub struct DownloadProgress { pub id: String, pub bytes_done: u64, pub bytes_total: Option<u64>, pub state: DownloadStateView }
  pub enum DownloadStateView { Queued, Running, Done, Failed }
  pub(crate) async fn enqueue(ids: Vec<String>) -> Result<(), CoreError>;
  pub(crate) async fn cancel(id: &str) -> Result<(), CoreError>;   // supprime fichier et .part
  pub(crate) async fn resume_pending();                             // au démarrage : Queued et Running repris
  pub struct LyricsView { pub plain: Option<String>, pub synced: Vec<LyricLine> }
  pub struct LyricLine { pub start_ms: u32, pub text: String }
  pub(crate) async fn lyrics(id: &str) -> Result<Option<LyricsView>, CoreError>;
  ```
- Règles : client réseau = `host.http_client(&plugin)` du plugin qui a résolu le titre, après
  `host.check_url` ; 2 téléchargements en parallèle ; qualité `high` ; fichier
  `<downloads_dir>/<item-id>.<webm|m4a selon mime>` ; pochette mise en cache au passage ;
  `Http(403)` en cours de route → nouvelle résolution puis reprise au même octet ;
  progression envoyée au plus **2 fois par seconde** par téléchargement ; `LibraryChanged::Downloads`
  à chaque changement d'état. Paroles : base d'abord ; sinon capacité `lyrics` routée,
  stockée ; aucune trouvée → ligne vide stockée, nouvel essai après 7 jours (âge = `LyricsRow.fetched_at`) ; hors ligne →
  base seulement.

- [ ] **Step 1 : tests qui échouent**

```rust
#[tokio::test] async fn download_fetches_in_range_chunks()          // fichier de 5 Mio → 3 requêtes Range, taille vérifiée
#[tokio::test] async fn download_resumes_from_part_file()           // .part de 3 Mio présent → première requête "bytes=3145728-"
#[tokio::test] async fn short_body_is_size_mismatch()
#[tokio::test] async fn expired_url_mid_download_resolves_again()   // 403 au 2e morceau → resolve rappelé, fichier complet
#[tokio::test(start_paused = true)] async fn progress_is_throttled_to_2_per_second()
#[tokio::test] async fn cancel_removes_files()
#[tokio::test] async fn lyrics_are_fetched_once_and_stored()
#[tokio::test] async fn missing_lyrics_are_not_refetched_for_7_days()
```
- [ ] **Step 2 : vérifier l'échec** → FAIL.
- [ ] **Step 3 : implémenter.**
- [ ] **Step 4 : vérifier** → PASS.
- [ ] **Step 5 : commit** — `feat(core): téléchargements avec reprise, paroles`.

### Task 7 : mises à jour, télémétrie, rapport de bug

**Files :**
- Create : `core/core/src/updates.rs`, `core/core/src/telemetry.rs`
- Test : modules `#[cfg(test)]`, `core/core/tests/updates.rs` (wiremock)

**Interfaces :**
- Produces :
  ```rust
  pub struct UpdateInfo { pub version: String, pub notes: String, pub page_url: String,
                          pub asset_url: Option<String>, pub sha256_url: Option<String> } // asset pour la plateforme courante
  pub(crate) async fn check_updates(current: &str, platform: Platform) -> Result<Option<UpdateInfo>, CoreError>;
  pub(crate) async fn download_update(info: &UpdateInfo) -> Result<String, CoreError>; // chemin de l'APK vérifié (sha256)
  pub(crate) fn pick_release(releases_json: &[u8], current: &str, platform: Platform) -> Option<UpdateInfo>;
  // telemetry
  pub enum PerfMetric { TapToFirstSoundMs, ResolveMs, StartupMs }
  pub(crate) fn set_enabled(on: bool);                       // opt-in ; false = rien ne part, client Sentry fermé
  pub(crate) fn report_error(e: &CoreError, plugin: Option<(&str, &str)>, capability: Option<Capability>);
  pub(crate) fn report_perf(m: PerfMetric, value_ms: u64);
  pub(crate) fn scrub(event: sentry::protocol::Event<'static>) -> Option<sentry::protocol::Event<'static>>; // before_send
  pub(crate) fn export_logs(dest: &str) -> Result<(), CoreError>;  // logs::recent() en texte, déjà masqués
  ```
- Règles : `pick_release` ignore brouillons, et préversions sauf si la version courante en
  est une ; compare en `semver`. Vérification au plus une fois par 24 h (horodatage dans
  `settings_device`), déclenchée par Dart après le premier affichage puis par un minuteur
  de `App`. `scrub` garde seulement : type d'erreur (nom de variante, jamais sa chaîne),
  id et version du plugin, capacité, version de l'app, OS, modèle d'appareil, cadres de
  pile ; vide `request`, `user`, `breadcrumbs`, `extra` ; passe les messages d'exception
  par `logs::redact`. `CallReport` du plugin-host alimente `ResolveMs` et les erreurs typées.

- [ ] **Step 1 : tests qui échouent**

```rust
#[test] fn newer_stable_release_is_picked()             // fixture de 3 releases (une brouillon, une pré) ; courant 0.1.0 → 0.2.0 avec l'APK arm64-v8a
#[test] fn prerelease_offered_only_to_prerelease_users()
#[test] fn macos_gets_page_url_only()                   // asset_url = None sur MacOs
#[tokio::test] async fn update_with_bad_sha256_is_refused()
#[test] fn telemetry_scrubs_titles_urls_queries()       // événement avec message "\"Halo\" https://x/y?q=beyonce", tag query, breadcrumb, user → aucun de ces textes dans le JSON sérialisé
#[test] fn typed_error_sends_variant_name_only()         // Internal("track Halo failed") → tag error_kind = "internal", "Halo" absent
#[test] fn disabled_telemetry_sends_nothing()           // transport de test : 0 envoi
```
- [ ] **Step 2 : vérifier l'échec** → FAIL.
- [ ] **Step 3 : implémenter.**
- [ ] **Step 4 : vérifier** → PASS.
- [ ] **Step 5 : commit** — `feat(core): mises à jour, télémétrie filtrée, export des journaux`.

### Task 8 : façade `api/`, squelette Flutter, pont, init JNI Android

**Files :**
- Create : `core/core/src/api/{mod,app,catalog,playback,library,plugins,settings,system}.rs`
- Create : `core/core/src/android.rs` (`#[cfg(target_os = "android")]`)
- Create : `app/` par `flutter create --org app --project-name vehicoule --platforms android,ios,macos,windows,linux app`
  puis : `app/flutter_rust_bridge.yaml`, `app/rust_builder/` (généré par
  `flutter_rust_bridge_codegen integrate`, pointant sur `../core/core`), `app/lib/bridge/`
  (généré), `app/android/app/src/main/kotlin/app/vehicoule/RustInit.kt`,
  `app/android/app/src/main/kotlin/app/vehicoule/VehicouleApplication.kt`,
  `app/android/app/build.gradle.kts`, `app/android/settings.gradle.kts`
- Test : `app/integration_test/bridge_test.dart`

**Interfaces :**
- Produces (Dart, généré dans `app/lib/bridge/`) — les noms Rust de `api/` en snake_case
  deviennent du camelCase :
  ```rust
  // api/app.rs
  pub async fn init_app(cfg: AppConfig) -> Result<(), CoreError>;
  pub async fn set_online(online: bool);
  pub fn onboarding() -> Result<Onboarding, CoreError>;  pub struct Onboarding { pub done: bool, pub telemetry: Option<bool> }
  pub async fn finish_onboarding(telemetry: bool) -> Result<(), CoreError>;
  // api/catalog.rs
  pub async fn search(query: String) -> Result<SearchView, CoreError>;
  pub async fn suggest(prefix: String) -> Result<Vec<String>, CoreError>;
  pub async fn entity(id: String, cursor: Option<String>) -> Result<EntityView, CoreError>;
  pub async fn import_playlist(link: String) -> Result<String, CoreError>;
  pub async fn artwork_file(id: String, size: u32) -> Result<Option<String>, CoreError>;
  pub async fn lyrics(id: String) -> Result<Option<LyricsView>, CoreError>;
  // api/playback.rs
  pub async fn play(items: Vec<String>, start: u32, context: Option<PlayContext>) -> Result<(), CoreError>;
  pub async fn player_event(e: PlayerEvent);
  pub async fn skip_next();  pub async fn previous(position_ms: u64);
  pub async fn queue_op(op: QueueOp) -> Result<(), CoreError>;
  pub enum QueueOp { EnqueueNext(Vec<String>), EnqueueLast(Vec<String>), Remove(String), Move { entry: String, to: u32 },
                     Shuffle(bool), Repeat(Repeat), JumpTo(String) }
  pub async fn fix_match(id: String) -> Result<Vec<Candidate>, CoreError>;
  pub async fn choose_match(id: String, candidate_id: String) -> Result<(), CoreError>;
  pub fn player_commands(sink: StreamSink<PlayerCommand>);  pub fn queue_states(sink: StreamSink<QueueView>);
  pub fn now_playing(sink: StreamSink<NowPlaying>);         pub fn notices(sink: StreamSink<Notice>);
  // api/library.rs
  pub async fn home() -> Result<HomeView, CoreError>;
  pub struct HomeView { pub recent: Vec<TrackView>, pub liked: Vec<TrackView>, pub playlists: Vec<CollectionView>, pub downloads: Vec<TrackView> } // 20 de chaque
  pub async fn set_liked(id: String, liked: bool) -> Result<(), CoreError>;
  pub async fn liked(kind: ItemKind, offset: u32, limit: u32) -> Result<Vec<CollectionView>, CoreError>;
  pub async fn liked_tracks(offset: u32, limit: u32) -> Result<Vec<TrackView>, CoreError>;
  pub async fn history(offset: u32, limit: u32) -> Result<Vec<TrackView>, CoreError>;
  pub async fn playlists() -> Result<Vec<CollectionView>, CoreError>;
  pub async fn create_playlist(title: String) -> Result<String, CoreError>;
  pub async fn rename_playlist(id: String, title: String) -> Result<(), CoreError>;
  pub async fn delete_playlist(id: String) -> Result<(), CoreError>;
  pub async fn playlist_entries(id: String, offset: u32, limit: u32) -> Result<Vec<PlaylistEntryView>, CoreError>;
  pub struct PlaylistEntryView { pub entry: String, pub track: TrackView }
  pub async fn add_to_playlist(id: String, items: Vec<String>) -> Result<(), CoreError>;
  pub async fn move_in_playlist(entry: String, after: Option<String>) -> Result<(), CoreError>;
  pub async fn remove_from_playlist(entry: String) -> Result<(), CoreError>;
  pub async fn search_library(query: String) -> Result<Vec<TrackView>, CoreError>;   // + collections dans un 2e champ si besoin plus tard
  pub async fn download(ids: Vec<String>) -> Result<(), CoreError>;
  pub async fn cancel_download(id: String) -> Result<(), CoreError>;
  pub async fn downloads() -> Result<Vec<DownloadProgress>, CoreError>;
  pub fn library_changes(sink: StreamSink<LibraryChanged>);  pub fn download_progress(sink: StreamSink<DownloadProgress>);
  // api/plugins.rs
  pub async fn installed_plugins() -> Result<Vec<PluginView>, CoreError>;
  pub struct PluginView { pub id: String, pub name: String, pub version: String, pub feed: String, pub capabilities: Vec<String>, pub enabled: bool }
  pub async fn has_resolver() -> bool;
  pub async fn preview_feed(url: String, public_key: String) -> Result<FeedPreview, CoreError>;
  pub async fn add_feed(url: String, public_key: String) -> Result<(), CoreError>;
  pub async fn remove_feed(url: String) -> Result<(), CoreError>;
  pub async fn refresh_feeds() -> Result<(), CoreError>;
  pub async fn capability_order(capability: String) -> Result<Vec<String>, CoreError>;
  pub async fn set_capability_order(capability: String, plugin_ids: Vec<String>) -> Result<(), CoreError>;
  // api/settings.rs
  pub struct Settings { pub quality: Quality, pub normalize_volume: bool, pub radio: bool, pub telemetry: bool }
  pub enum Quality { Low, Normal, High }
  pub async fn settings() -> Result<Settings, CoreError>;  pub async fn set_settings(s: Settings) -> Result<(), CoreError>;
  // api/system.rs
  pub async fn check_updates() -> Result<Option<UpdateInfo>, CoreError>;
  pub async fn download_update(info: UpdateInfo) -> Result<String, CoreError>;
  pub fn report_perf(metric: PerfMetric, value_ms: u64);
  pub fn report_dart_error(kind: String, stack: String);            // passe par scrub
  pub fn diagnostics() -> Vec<LogLine>;
  pub fn export_logs(dest: String) -> Result<(), CoreError>;
  ```
  Réglages : `quality`, `normalize_volume` dans `settings_device` ; `radio` dans
  `settings_shared` ; défauts `Normal`, `true`, `true`, télémétrie `false` tant que non choisie.
- Android : `RustInit.kt` déclare `external fun initVerifier(context: Context)` et charge la
  lib (`System.loadLibrary("vehicoule_core")`) ; `VehicouleApplication.onCreate` l'appelle
  avant tout (déclarée dans le manifeste par `android:name`). Côté Rust,
  `Java_app_vehicoule_RustInit_initVerifier(env, _class, context)` appelle
  `rustls_platform_verifier::android::init_with_env(&mut env, context)` (crate `jni` à la
  version qu'utilise rustls-platform-verifier 0.7.1, vérifiée par `cargo tree -i jni`).
  Gradle : dépôt Maven local trouvé via `cargo metadata` (chemin du paquet
  `rustls-platform-verifier-android`) et dépendance `rustls:rustls-platform-verifier:latest.release`,
  comme le décrit le README de la crate. `applicationId = "app.vehicoule"`.

- [ ] **Step 1 : écrire le test d'intégration qui échoue** `bridge_test.dart` :

```dart
testWidgets('core boots and searches through a local feed', (t) async {
  await RustLib.init();
  await initApp(cfg: AppConfig(/* dossiers temporaires, région FR */));
  // feed de test servi par un HttpServer Dart local, plugin fake-catalog du plan 4 tâche 3
  // (signé par une clé de test passée via la variable VEHICOULE_TEST_FEED_KEY en debug)
  final r = await search(query: 'halo');
  expect(r.tracks, isNotEmpty);
});
testWidgets('bad input is a typed error, not a crash', (t) async {
  await expectLater(entity(id: 'not-a-uuid'), throwsA(isA<CoreError_Internal>()));
});
testWidgets('https works', (t) async { expect(await checkUpdates(), anything); }); // aucune exception TLS
```
  Le feed de test n'est accepté qu'en build debug (`cfg(debug_assertions)`), par une clé
  lue dans `VEHICOULE_TEST_FEED_KEY` et ajoutée aux clés de confiance.
- [ ] **Step 2 : vérifier l'échec** — `cd app && flutter test integration_test -d macos` → FAIL.
- [ ] **Step 3 : implémenter `api/`** (fines enveloppes des modules des tâches 1 à 7 ;
  conversions de `ItemId` en chaîne), lancer `flutter_rust_bridge_codegen generate`,
  Kotlin et Gradle.
- [ ] **Step 4 : vérifier** — `flutter test integration_test -d macos` → PASS ;
  `flutter test integration_test -d <émulateur Android arm64>` → PASS (le test `https works`
  prouve l'init JNI ; sans elle il panique).
- [ ] **Step 5 : vérifier la taille** — `flutter build apk --release --target-platform android-arm64` ;
  noter la taille du `libvehicoule_core.so` dans le message de commit (repère pour la suite).
- [ ] **Step 6 : commit** — `feat: façade Dart (flutter_rust_bridge), squelette de l'app, init TLS Android`.
