# Socle 6 — Plugins (ytmusic, deezer, itunes, lrclib) : plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** les quatre plugins de la v1 en composants WASM sur le contrat 1.0 : ytmusic
(lecture, catalogue de dernier recours) qui enveloppe `ytmusic-resolve`, et le feed
officiel deezer / itunes / lrclib ; feeds signés publiables ; fuel calibré sur téléphone.

**Architecture :** chaque plugin est une crate `cdylib` pour `wasm32-wasip2` qui déclare son
propre monde (`include vehicoule:host/imports` + ses exports) et réutilise les types du
SDK (`with`). La logique est dans des fonctions natives testables (parsing des réponses,
liens) ; la colle WIT est mince. Les tests de bout en bout chargent le vrai `.wasm` dans
`plugin-host` avec le rejeu de réponses enregistrées : aucun réseau en CI.

**Tech Stack :** Rust 2024, wit-bindgen 0.63, `vehicoule-sdk` (tag `contract-v1.0.0`),
`plugin-host` en dev-dependency (tag `plugin-host-v1.0.0`, feature `test-util`),
serde / serde_json, strsim (ytmusic), `wasm32-wasip2`.

**Spec :** `docs/superpowers/specs/2026-10-18-socle-musique-design.md` (v4), sections 2
(dépôts), 3.2, 3.3, 4.1–4.4, 4.7, 8, 9. Rapport : correspondance, flux plafonnés,
constats 3 et 4, décision « YouTube classique en repli ». Prérequis : plans 1 et 2 ; la
tâche 7 demande aussi les plans 4 et 5 (app sur le téléphone).

## Global Constraints

- Dépôts : `/Users/btw/Documents/repo/vehicoule-ytmusic` (existant, branche
  `socle-plugin`) et `/Users/btw/Documents/repo/vehicoule-plugins` (créé ici, `git init -b main`
  puis branche `socle-plugins`). Licence **MIT OR Apache-2.0**. Commit =
  `git commit -s -m "<msg>" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"`.
- Dépendances Git sur `vehicoule` tant qu'il n'a pas de remote :
  `git = "file:///Users/btw/Documents/repo/Vehicoule"` ; `vehicoule-sdk` au tag
  `contract-v1.0.0`, `plugin-host` (dev, `features = ["test-util"]`) au tag
  `plugin-host-v1.0.0`. Les plugins consomment le SDK exactement comme un tiers.
- WIT vendorisé à la racine de chaque dépôt : `wit/host/host.wit`, `wit/music/music.wit`
  (un dossier par paquet, comme dans `contract`), identiques à `vehicoule_sdk::HOST_WIT` /
  `MUSIC_WIT` ; contrôlé par le test `wit_deps_match_sdk` (`UPDATE_WIT=1` réécrit les
  fichiers).
- Profil release des plugins : `opt-level = "s"`, `lto = true`, `strip = true`,
  `panic = "abort"` (côté guest ; une panique devient un trap → `internal`).
- Le trait `Http` de `ytmusic-resolve` n'est pas `Send` (async fn dans un trait) : dans le
  plugin, l'adaptateur appelle l'import synchrone `http.send` et le futur est conduit par
  `vehicoule_sdk::block_on` ; ces futurs ne passent jamais par `tokio::spawn`. La CLI
  garde son runtime sans `spawn`.
- ytmusic, profils `/player` dans l'ordre **VISIONOS, IOS, ANDROID_VR** ; `visitorData`
  rejoué (en-tête `X-Goog-Visitor-Id` et `context.client.visitorData`) et **persisté dans
  `kv`** sous la clé `visitor_data` ; sonde du dernier octet avant de rendre une URL ;
  YouTube Music d'abord (filtres Songs puis Videos), **YouTube classique en repli** sous
  le seuil.
- Score (inchangé, réglé à l'étape 1) : titre 0,45, artistes 0,3, durée 0,25 ; seuil 0,75.
- Manifestes (domaines, débit) :

| Plugin | Domaines | Débit | UA descriptif |
|---|---|---|---|
| ytmusic | `music.youtube.com`, `www.youtube.com`, `*.googlevideo.com`, `i.ytimg.com` | 40 / 60 s | non |
| deezer | `api.deezer.com`, `www.deezer.com`, `link.deezer.com`, `deezer.page.link`, `*.dzcdn.net` | 45 / 5 s | non |
| itunes | `itunes.apple.com`, `music.apple.com`, `*.mzstatic.com` | 20 / 60 s | non |
| lrclib | `lrclib.net` | aucune | oui |

- Capacités exportées : ytmusic = `resolve`, `search`, `suggest`, `entity` (playlists),
  `radio` ; deezer = `search`, `entity`, `radio` ; itunes = `search`, `entity` ; lrclib =
  `lyrics`.
- Feeds : officiel signé avec `~/.config/vehicoule/feed-keys/official-1.key` (créée au
  plan 4) ; ytmusic signé avec sa propre clé `~/.config/vehicoule/feed-keys/ytmusic.key`,
  jamais dans le feed officiel. Clés hors des dépôts.

## Review Focus

1. **Visiteur perdu ou expiré** (kv vide au premier lancement, ou `visitorData` refusé) :
   la résolution repart sans visiteur, réessaie une fois après le mur et enregistre le
   nouveau. → tests `visitor_is_loaded_and_saved`, `first_call_without_visitor_still_resolves`
   (tâche 2).
2. **Titre absent de YouTube Music mais présent en clip sur YouTube** (*Au DD*, Jay Chou) :
   le repli classique le trouve. → test `falls_back_to_classic_youtube` (tâche 2).
3. **Deezer renvoie 200 avec un objet `error`** (quota, id inconnu) au lieu d'un statut
   HTTP : `rate-limited` / `not-found`, pas `internal`. → test `deezer_json_errors_are_typed`
   (tâche 4).
4. **iTunes signale son débit par un 403** (et non 429) : `rate-limited`, pour que le
   routage passe au suivant sans croire à un mur. → test `itunes_403_is_rate_limited` (tâche 5).
5. **Paroles synchronisées mal formées ou titre instrumental** : lignes illisibles ignorées,
   instrumental = `not-found`, jamais de panique. → test `lrc_parser_skips_bad_lines`,
   `instrumental_is_not_found` (tâche 6).

---

### Task 1 : `ytmusic-resolve` — visiteur persistant, candidats classés, nouvelles requêtes InnerTube

**Files (dépôt vehicoule-ytmusic) :**
- Modify : `crates/resolve/src/player.rs`, `src/search.rs`, `src/matching.rs`, `src/lib.rs`
- Create : `crates/resolve/src/browse.rs` (suggestions, playlist, « à suivre »)
- Create : `crates/resolve/tests/fixtures/{suggest,playlist_page1,playlist_continuation,next}.json`
  (réponses réelles enregistrées une fois avec `crates/cli`, puis rejouées)
- Modify : `crates/cli/src/main.rs` (visiteur gardé en mémoire entre les titres du corpus)
- Test : `crates/resolve/tests/{player,find,browse}.rs`

**Interfaces :**
- Produces :
  ```rust
  pub async fn resolve(http: &impl Http, video_id: &str, quality: Quality, region: &str,
                       visitor: &mut Option<String>) -> Result<Resolved, ResolveError>;   // visiteur lu ET mis à jour
  pub fn ranked<'a>(q: &TrackQuery, cs: &'a [Candidate]) -> Vec<(&'a Candidate, f32)>;   // tri décroissant, départage inchangé ; best_match l'utilise
  pub async fn find_ranked(http: &impl Http, q: &TrackQuery, region: &str) -> Result<Vec<(Candidate, f32)>, ResolveError>; // music puis repli YouTube ; vide si rien ≥ seuil
  pub async fn suggest(http: &impl Http, prefix: &str, region: &str) -> Result<Vec<String>, ResolveError>;
  pub struct PlaylistPage { pub title: String, pub owner: Option<String>, pub tracks: Vec<Candidate>, pub continuation: Option<String> }
  pub async fn playlist(http: &impl Http, playlist_id: &str, continuation: Option<&str>, region: &str) -> Result<PlaylistPage, ResolveError>;
  pub async fn up_next(http: &impl Http, video_id: &str, region: &str) -> Result<Vec<Candidate>, ResolveError>; // playlistId "RDAMVM"+videoId
  pub fn parse_playlist_link(url: &str) -> Option<String>; // music.youtube.com/playlist?list=… et www.youtube.com/playlist?list=…
  ```
  `find` reste (`find_ranked` + premier élément).

- [ ] **Step 1 : tests qui échouent**

```rust
#[tokio::test] async fn given_visitor_is_sent_on_first_request()  // visitor = Some("V1") → 1re requête a X-Goog-Visitor-Id: V1
#[tokio::test] async fn visitor_is_updated_from_response()        // après l'appel, visitor == responseContext.visitorData de la fixture
#[tokio::test] async fn ranked_is_sorted_and_keeps_ties_order()
#[tokio::test] async fn find_ranked_falls_back_to_youtube()       // fixtures existantes de find.rs
#[tokio::test] async fn suggestions_are_parsed()
#[tokio::test] async fn playlist_pages_follow_continuation()
#[tokio::test] async fn up_next_skips_the_seed()
#[test] fn playlist_links_are_recognised()                       // list=PL…, list=OLAK5uy_… ; watch?v= sans list → None
```
- [ ] **Step 2 : vérifier l'échec** — `cargo test -p ytmusic-resolve` → FAIL.
- [ ] **Step 3 : implémenter.** Enregistrer les nouvelles fixtures avec la CLI (une requête
  par fixture, 1,5 s d'écart, comme à l'étape 1).
- [ ] **Step 4 : vérifier** — PASS ; `cargo run -p ytm -- check corpus/corpus.json` → toujours
  ≥ 95 % (96 attendu).
- [ ] **Step 5 : commit** — `feat(resolve): visiteur persistant, candidats classés, suggestions, playlists, à suivre`.

### Task 2 : composant ytmusic

**Files (dépôt vehicoule-ytmusic) :**
- Create : `crates/plugin/Cargo.toml` (`crate-type = ["cdylib"]`), `crates/plugin/src/lib.rs`
  (colle WIT), `crates/plugin/src/host_http.rs`, `crates/plugin/src/map.rs`,
  `crates/plugin/wit/world.wit`, `wit/host/host.wit` et `wit/music/music.wit` (vendorisés),
  `crates/plugin/manifest.json` ; bindings avec `path: ["../../wit/host", "../../wit/music", "wit"]`
- Create : `crates/plugin-tests/` (natif : construit le `.wasm` comme
  `core/plugin-host/tests/budgets.rs` et le charge dans `plugin-host`),
  `crates/plugin-tests/fixtures/<cas>/index.json` + corps
- Modify : `Cargo.toml` (membres ; `crates/plugin` exclu de la compilation native par défaut :
  `default-members` sans lui)
- Test : `crates/plugin-tests/tests/{wit,plugin}.rs`, `crates/plugin/src/map.rs`

**Interfaces :**
- Consumes : tâche 1, `vehicoule_sdk::{block_on, kv, types}`, `plugin_host::{Host, NetPolicy::replay, MemoryStorage}`.
- Produces :
  ```wit
  package vehicoule:ytmusic;
  world ytmusic {
      include vehicoule:host/imports@1.0.0;
      export vehicoule:music/resolve@1.0.0;
      export vehicoule:music/search@1.0.0;
      export vehicoule:music/suggest@1.0.0;
      export vehicoule:music/entity@1.0.0;
      export vehicoule:music/radio@1.0.0;
  }
  ```
  ```rust
  struct HostHttp;  impl ytmusic_resolve::Http for HostHttp { async fn send(&self, req) -> … } // import sync, pas de Send
  fn to_error(e: ResolveError) -> types::Error;  // Network→network, ProviderWall→provider-wall, RateLimited→rate-limited,
                                                 // NotFound→not-found, NeedsJs→internal("needs js"), Parse(m)→internal(m)
  fn to_track(c: &Candidate) -> types::Track;    // id = videoId, artwork = https://i.ytimg.com/vi/<id>/hqdefault.jpg
  fn to_query(q: &types::TrackQuery) -> TrackQuery;
  ```
- Règles de `resolve` : visiteur lu dans `kv` (`visitor_data`) puis réécrit s'il a changé ;
  `req.track.id` présent et absent de `tried` → résolution directe ; sinon `find_ranked`,
  premier candidat hors `tried` ; `candidates` = les 5 suivants (score inclus) ;
  `source.expires-at-ms` = `expires_at_unix × 1000`. `entity` : `playlist` seulement
  (autres kinds → `not-found`) ; `parse-link` → `parse_playlist_link`. `radio` : graine =
  `seed.id`, sinon `find` ; `up_next` limité à `limit`. `search` : candidats YouTube Music
  en `tracks` ; autres kinds vides.

- [ ] **Step 1 : tests qui échouent**

```rust
#[test] fn wit_deps_match_sdk()                                   // compare wit/host/host.wit et wit/music/music.wit aux constantes du SDK ; UPDATE_WIT=1 réécrit
#[tokio::test] async fn manifest_and_exports_match()              // capabilities == {Resolve, Search, Suggest, Entity, Radio}
#[tokio::test] async fn resolves_through_the_host()               // rejeu : search songs + player VISIONOS + sonde Range → Resolved.id, URL googlevideo
#[tokio::test] async fn visitor_is_loaded_and_saved()             // MemoryStorage : kv visitor_data == visitorData de la fixture après l'appel
#[tokio::test] async fn first_call_without_visitor_still_resolves() // fixture : mur sans visiteur, puis OK avec → Ok
#[tokio::test] async fn falls_back_to_classic_youtube()           // fixtures yt_search_jaychou
#[tokio::test] async fn capped_stream_moves_to_next_profile()     // sonde 403 sur VISIONOS → IOS essayé
#[tokio::test] async fn tried_ids_are_skipped()
#[tokio::test] async fn candidates_are_returned_for_manual_fix()  // ≤ 5, scores décroissants
#[tokio::test] async fn playlist_import_pages()
#[test] fn resolve_errors_map_to_contract_errors()
```
- [ ] **Step 2 : vérifier l'échec** — `cargo test -p plugin-tests` → FAIL.
- [ ] **Step 3 : implémenter.**
- [ ] **Step 4 : vérifier** — PASS ; taille du `.wasm` release notée dans le commit.
- [ ] **Step 5 : test réel manuel** : `cargo test -p plugin-tests -- --ignored corpus_through_wasm`
  (hôte avec `NetPolicy::default()`, vrai réseau, 1,5 s entre titres) → ≥ 95 % sur le corpus,
  et fuel p50 / p95 / max par `resolve` affichés (base Mac de la calibration).
- [ ] **Step 6 : commit** — `feat: plugin ytmusic en composant WASM`.

### Task 3 : dépôt `vehicoule-plugins` et outillage de feed

**Files (nouveau dépôt) :**
- Create : `Cargo.toml` (workspace : `plugins/deezer`, `plugins/itunes`, `plugins/lrclib`,
  `tests` ; `default-members = ["tests"]`), `LICENSE-MIT`, `LICENSE-APACHE`, `README.md`,
  `.gitignore`, `wit/host/host.wit` et `wit/music/music.wit` (vendorisés), `scripts/publish.sh`,
  `feed/sequence` (contient `0`)
- Create : `tests/Cargo.toml`, `tests/src/lib.rs` (construction des `.wasm`, hôte de rejeu),
  `tests/tests/wit.rs`
- Same in vehicoule-ytmusic : `scripts/publish.sh`, `feed/sequence`

**Interfaces :**
- Produces : `pub fn load(plugin: &str, fixtures: &str) -> (plugin_host::Host, plugin_host::Plugin, Arc<MemoryStorage>);`
  (dans `tests/src/lib.rs`). Chaque plugin génère ses bindings avec
  `path: ["../../wit/host", "../../wit/music", "wit"]` et
  l'option `with` du README du SDK.
- `publish.sh <dossier-de-sortie>` : build release `wasm32-wasip2` de chaque plugin, copie
  `<id>-<version>.wasm` et `<id>-<version>.manifest.json`, calcule les sha256, incrémente
  `feed/sequence`, écrit le payload, puis
  `cargo run --manifest-path …/Vehicoule/core/Cargo.toml -p plugin-host --bin vehicoule-feed -- sign payload.json "$VEHICOULE_FEED_KEY" > feed.json`.
  URLs relatives au feed. L'hébergement (GitHub Pages derrière
  `feeds.vehicoule.app/official/`) est une étape manuelle hors plan.

- [ ] **Step 1 : test qui échoue** — `wit_deps_match_sdk` (même test qu'en tâche 2).
- [ ] **Step 2 : vérifier l'échec** → FAIL (dossier absent).
- [ ] **Step 3 : implémenter** (`UPDATE_WIT=1 cargo test` pour vendoriser).
- [ ] **Step 4 : vérifier** → PASS ; `scripts/publish.sh /tmp/feed-test` avec une clé de test
  produit un `feed.json` que `verify_feed` accepte (test `published_feed_verifies` dans
  `tests/tests/wit.rs`, clé générée dans un dossier temporaire).
- [ ] **Step 5 : commit** — `chore: dépôt des plugins officiels et publication du feed`.

### Task 4 : plugin deezer

**Files :**
- Create : `plugins/deezer/{Cargo.toml,manifest.json,wit/world.wit}`,
  `plugins/deezer/src/{lib.rs,api.rs,links.rs}`
- Create : `tests/fixtures/deezer/<cas>/…` (réponses réelles enregistrées une fois au `curl`)
- Test : `plugins/deezer/src/{api,links}.rs` (natifs), `tests/tests/deezer.rs` (rejeu)

**Interfaces :**
- Produces (natif, testable) :
  ```rust
  pub fn parse_tracks(body: &[u8]) -> Result<(Vec<types::Track>, Option<String>), types::Error>; // `next` → index suivant en curseur
  pub fn parse_albums / parse_artists / parse_playlists (même forme)
  pub fn deezer_error(body: &[u8]) -> Option<types::Error>; // {"error":{"code":4}} → RateLimited ; 800 → NotFound ; autre code → Internal("deezer <code>")
  pub fn parse_link(url: &str) -> Option<types::EntityRef>;   // www.deezer.com/(xx/)?(track|album|artist|playlist)/<id>
  pub fn is_short_link(url: &str) -> bool;                     // link.deezer.com/s/…, deezer.page.link/…
  ```
- Requêtes : `search` = `api.deezer.com/search/{track|album|artist|playlist}?q=…&limit=…&index=<curseur>` ;
  `entity` : `track/<id>` ; `album/<id>` + `album/<id>/tracks?index&limit=100` ;
  `artist/<id>` + `artist/<id>/top?limit=20` + `artist/<id>/albums?limit=50` ;
  `playlist/<id>` + `playlist/<id>/tracks?index&limit=100`. `parse-link` sur lien court :
  `GET`, puis `parse_link(response.url)`. `radio` : `track/<seed.id>` → artiste →
  `artist/<id>/radio?limit=<limit>` ; sans `seed.id` : `search/track?q=<artiste titre>`
  premier résultat. Pochettes : `cover_xl` / `picture_xl` (1000 px) et `_medium` (250 px).

- [ ] **Step 1 : tests qui échouent**

```rust
#[test] fn search_results_parse_with_cursor()
#[test] fn album_tracks_carry_isrc_when_present()
#[test] fn deezer_json_errors_are_typed()
#[test] fn links_are_recognised()                        // https://www.deezer.com/fr/playlist/908622995 → Playlist "908622995" ; /album/302127 ; autre domaine → None
#[tokio::test] async fn short_link_follows_redirect()     // rejeu : link.deezer.com/s/… 302 → www.deezer.com/fr/playlist/…
#[tokio::test] async fn playlist_import_pages_by_100()
#[tokio::test] async fn radio_from_seed_track()
#[tokio::test] async fn empty_search_is_empty_not_error() // {"data":[],"total":0} → Ok vide (le cœur passe au suivant)
```
- [ ] **Step 2 : vérifier l'échec** → FAIL.
- [ ] **Step 3 : implémenter** (`serde` avec structs partielles : seuls les champs utilisés).
- [ ] **Step 4 : vérifier** → PASS.
- [ ] **Step 5 : commit** — `feat: plugin deezer`.

### Task 5 : plugin itunes

**Files :**
- Create : `plugins/itunes/{Cargo.toml,manifest.json,wit/world.wit}`, `plugins/itunes/src/{lib.rs,api.rs}`
- Create : `tests/fixtures/itunes/<cas>/…`
- Test : `plugins/itunes/src/api.rs`, `tests/tests/itunes.rs`

**Interfaces :**
- Produces :
  ```rust
  pub fn parse_results(body: &[u8]) -> Result<SearchParts, types::Error>; // wrapperType track/collection/artist triés
  pub fn big_artwork(url100: &str) -> String;     // "…/100x100bb.jpg" → "…/1000x1000bb.jpg"
  pub fn status_error(status: u16) -> Option<types::Error>; // 403 → RateLimited (iTunes), puis vehicoule_sdk::status_error
  pub fn parse_link(url: &str) -> Option<types::EntityRef>; // music.apple.com/<cc>/album/<slug>/<id>[?i=<track>] ; /artist/<slug>/<id> ; /playlist → None (non servi par l'API)
  ```
- Requêtes : `itunes.apple.com/search?term=…&entity=song|album|musicArtist&country=<region>&limit=…`
  (curseur = `offset`), `itunes.apple.com/lookup?id=<id>&entity=song|album&country=<region>`.

- [ ] **Step 1 : tests qui échouent**

```rust
#[test] fn songs_albums_artists_are_split()
#[test] fn artwork_is_upscaled_to_1000()
#[test] fn itunes_403_is_rate_limited()
#[test] fn album_and_track_links_are_recognised()
#[tokio::test] async fn album_entity_lists_tracks_in_order() // rejeu lookup ; ordre par trackNumber puis discNumber
```
- [ ] **Step 2 : vérifier l'échec** → FAIL.
- [ ] **Step 3 : implémenter.**
- [ ] **Step 4 : vérifier** → PASS.
- [ ] **Step 5 : commit** — `feat: plugin itunes`.

### Task 6 : plugin lrclib

**Files :**
- Create : `plugins/lrclib/{Cargo.toml,manifest.json,wit/world.wit}`, `plugins/lrclib/src/{lib.rs,lrc.rs}`
- Create : `tests/fixtures/lrclib/<cas>/…`
- Test : `plugins/lrclib/src/lrc.rs`, `tests/tests/lrclib.rs`

**Interfaces :**
- Produces :
  ```rust
  pub fn parse_lrc(text: &str) -> Vec<(u32, String)>;   // "[mm:ss.xx] texte" et "[mm:ss.xxx]", plusieurs horodatages par ligne, tri par temps ; lignes de métadonnées ([ar:], [ti:]) et illisibles ignorées
  ```
- Requêtes : `lrclib.net/api/get?track_name&artist_name&album_name&duration=<s arrondies>` ;
  404 → `lrclib.net/api/search?track_name&artist_name`, premier résultat dont la durée est
  à ±2 s ; aucun → `not-found`. `instrumental: true` → `not-found`.

- [ ] **Step 1 : tests qui échouent**

```rust
#[test] fn lrc_parser_reads_timestamps()               // "[01:02.50] a" → (62500, "a") ; "[00:01.123]" → 1123
#[test] fn lrc_parser_skips_bad_lines()                // "[ar: X]", "[xx:yy] z", "" ignorées ; "[00:01.00][00:05.00] chœur" → 2 lignes
#[tokio::test] async fn get_returns_plain_and_synced()
#[tokio::test] async fn search_fallback_matches_duration()
#[tokio::test] async fn instrumental_is_not_found()
#[test] fn manifest_asks_for_descriptive_user_agent()       // manifest.json : descriptive_user_agent == true (l'en-tête lui-même est testé au plan 2)
```
- [ ] **Step 2 : vérifier l'échec** → FAIL.
- [ ] **Step 3 : implémenter.**
- [ ] **Step 4 : vérifier** — `cargo test` (workspace) → PASS.
- [ ] **Step 5 : commit** — `feat: plugin lrclib`.

### Task 7 : publication et calibration du fuel sur téléphone (manuelle, après les plans 4 et 5)

**Files :**
- Modify : `Vehicoule/core/plugin-host/src/lib.rs` (`Limits::default().fuel`),
  `Vehicoule/core/plugin-host/tests/budgets.rs` (`default_limits_match_the_spec`)
- Create : `Vehicoule/docs/superpowers/reports/2026-xx-calibration-fuel.md`

- [ ] **Step 1 : publier** les deux feeds dans un dossier local servi en HTTPS de test, ou
  directement sur `feeds.vehicoule.app` si l'hébergement existe ; ajouter le feed ytmusic
  dans l'app par « Ajouter un dépôt » (empreinte vérifiée à l'œil).
- [ ] **Step 2 : sur le téléphone de l'utilisateur** (build `--profile`), 30 lectures de
  titres non résolus + 30 recherches + 20 pages + 20 paroles ; exporter les journaux
  (`exportLogs`) et extraire les lignes `call <capacité> fuel=… wall=…`.
- [ ] **Step 3 : fixer le fuel** : nouvelle valeur = **4 × le p95** le plus élevé parmi les
  capacités, arrondie à la dizaine de millions supérieure ; vérifier qu'elle tient en temps
  CPU sous le budget de 30 s sur ce téléphone (fuel/s mesuré = fuel ÷ `wall` hors attente
  réseau, donné par les appels sans HTTP).
- [ ] **Step 4 : reporter** la valeur dans `Limits::default()` et le test, `cargo test -p plugin-host` → PASS,
  rapport (modèle du téléphone, p50/p95/max par capacité, valeur retenue).
- [ ] **Step 5 : commit** (dépôt Vehicoule) — `chore(plugin-host): fuel calibré sur téléphone`.
