# Étape 1 — Faisabilité : plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** prouver, avant de construire le socle, que (1) la résolution YouTube Music atteint
≥ 95 % de bonnes correspondances, (2) `media_kit` + `audio_service` tiennent 1 h écran éteint
sur Android, (3) Wasmtime + Pulley convient sur Android arm64, (4) les bibliothèques natives
de `media_kit` ne sont pas sous GPL.

**Architecture :** la résolution est une bibliothèque Rust ordinaire (`ytmusic-resolve`)
derrière un trait `Http`, gardée ensuite par le plugin ytmusic. La preuve Wasmtime pose les
premières briques réelles de `core/contract` et `core/plugin-host` (gardées si l'étape
passe). Seuls `probes/` (app Flutter de lecture, binaires Android de mesure) sont jetables et
supprimés quand le socle les remplace.

**Tech Stack :** Rust stable (édition 2024), tokio, reqwest (rustls), serde ; Wasmtime (LTS)
+ Pulley, wit-bindgen, cible `wasm32-wasip2` ; Flutter, `media_kit`, `audio_service` ;
Android NDK + `cargo-ndk`.

**Spec :** `docs/superpowers/specs/2026-10-18-socle-musique-design.md` (v4), sections 3.3,
3.4, 4.1, 4.2 bis, 9, 10, 12.

## Global Constraints

- Deux dépôts locaux : `/Users/btw/Documents/repo/Vehicoule` (existant) et
  `/Users/btw/Documents/repo/vehicoule-ytmusic` (créé en tâche 1). Aucun remote.
- Licences : `Vehicoule` = MPL-2.0 sauf `core/contract` = MIT OR Apache-2.0 ;
  `vehicoule-ytmusic` = MIT OR Apache-2.0.
- Commits : `git commit -s` (DCO) et dernière ligne
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Aucun code porté depuis Auqw ou Klaxon. Lire l'ancien plugin YouTube d'Auqw pour savoir
  **quel client** il utilisait est permis ; copier du code ne l'est pas.
- Pas d'OAuth.
- Correspondance : durée **±3 s** ; « song » préféré à « video » ; mots pénalisés **`live`,
  `remix`, `cover`, `sped up`, `instrumental`** sauf s'ils figurent dans le titre de
  référence.
- Wasmtime : **dernière version LTS** (vérifier sur le site de Wasmtime ; probablement la
  série 48, août 2026), cible **`pulley64`** partout, compilation du `.wasm` sur l'appareil,
  jamais de chargement d'artefact précompilé.
- Budgets hôte : epoch **30 s** (tick de 100 ms, 300 ticks), `StoreLimits` **64 Mio** de
  mémoire, fuel initial **200 000 000** par appel (valeur de départ, à ajuster plus tard),
  réponse HTTP **8 Mio** maximum.
- Seuils de l'étape : corpus **≥ 95 %** ; lecture **≥ 3600 s** écran éteint sans erreur ;
  Wasmtime ajoute **≤ 10 Mio** au `.so` arm64 strippé ; bibliothèques `media_kit` **sans**
  `--enable-gpl` ni `--enable-nonfree`.
- Android : identifiant du probe `app.vehicoule.probe.playback` ; fichiers dans l'espace
  propre à l'app (`/sdcard/Android/data/<id>/files/`).

## Review Focus

1. **Titres en écriture non latine** (japonais, coréen, arabe) : la normalisation ne doit pas
   les vider ; deux titres identiques en kanji doivent obtenir une similarité de 1.0.
   → test `normalize_keeps_non_latin` (tâche 1).
2. **Durée absente** côté résultat YouTube : le score ne panique pas et pénalise au lieu
   d'éliminer. → test `missing_duration_is_penalized_not_fatal` (tâche 1).
3. **Mur anti-bot ou 429 pendant le corpus** : erreur typée, le CLI continue et compte
   l'échec à part au lieu de s'arrêter. → tests `player_login_required_bot_is_provider_wall`
   (tâche 3) et `check_continues_after_provider_wall` (tâche 4).
4. **Formats uniquement chiffrés** (`signatureCipher` sans `url`) : `NeedsJs`, pas de panique ;
   c'est le déclencheur du plan B `js`. → test `cipher_only_formats_need_js` (tâche 3).
5. **Réponse HTTP énorme** renvoyée à un plugin : refusée au-delà de 8 Mio avec une erreur
   typée, sans allouer le tout. → test `oversized_response_is_rejected` (tâche 5).

---

### Task 1 : dépôt `vehicoule-ytmusic` et score de correspondance

**Files :**
- Create : `vehicoule-ytmusic/Cargo.toml` (workspace : `crates/resolve`, `crates/cli`),
  `LICENSE-MIT`, `LICENSE-APACHE`, `README.md`, `.gitignore`
- Create : `crates/resolve/Cargo.toml`, `src/lib.rs`, `src/matching.rs`
- Test : `crates/resolve/src/matching.rs` (module `#[cfg(test)]`)

**Interfaces :**
- Produces :
  ```rust
  pub struct TrackQuery { pub title: String, pub artists: Vec<String>,
                          pub album: Option<String>, pub duration_ms: u32 }
  pub enum ResultKind { Song, Video }
  pub struct Candidate { pub video_id: String, pub title: String, pub artists: Vec<String>,
                         pub duration_ms: Option<u32>, pub kind: ResultKind }
  pub const MATCH_THRESHOLD: f32 = 0.75;
  pub fn normalize(s: &str) -> String;
  pub fn score(q: &TrackQuery, c: &Candidate) -> f32;            // 0.0..=1.0
  pub fn best_match<'a>(q: &TrackQuery, cs: &'a [Candidate]) -> Option<&'a Candidate>;
  ```

- [ ] **Step 1 : créer le dépôt** (`git init -b main`, workspace, licences, README d'une
  ligne) et le crate `resolve` vide.
- [ ] **Step 2 : écrire les tests qui échouent**

  ```rust
  #[test] fn exact_song_scores_above_threshold()      // même titre/artiste, Song, Δ=0 s → > 0.9
  #[test] fn song_beats_video_with_same_metadata()     // score(Song) > score(Video)
  #[test] fn duration_outside_3s_is_heavily_penalized()// Δ=2 s ≥ MATCH_THRESHOLD ; Δ=10 s < MATCH_THRESHOLD
  #[test] fn live_penalized_unless_in_reference()      // "X (Live)" < "X" ; ref "X (Live)" → "X (Live)" gagne
  #[test] fn each_penalized_word_lowers_score()        // live, remix, cover, sped up, instrumental
  #[test] fn feat_and_brackets_ignored()               // "X (feat. Y)" ≈ "X" → similarité titre 1.0
  #[test] fn normalize_keeps_non_latin()               // normalize("夜に駆ける") non vide ; deux égaux → 1.0
  #[test] fn missing_duration_is_penalized_not_fatal() // duration_ms: None → score < même avec Δ=0, pas de panique
  #[test] fn best_match_returns_none_below_threshold()
  ```
- [ ] **Step 3 : vérifier l'échec** — `cargo test -p ytmusic-resolve` → FAIL (fonctions
  absentes).
- [ ] **Step 4 : implémenter** `normalize` (minuscules, suppression des accents latins via
  décomposition Unicode, retrait de `feat.`/`ft.` et du contenu entre parenthèses ou
  crochets **sauf** les mots pénalisés, espaces compactés ; les caractères non latins sont
  conservés) puis `score` = moyenne pondérée : similarité titre 0.45, similarité artistes 0.3,
  durée 0.25 (1.0 si Δ ≤ 3 s, puis décroissance rapide ; 0.5 si durée absente), × 0.85 si
  Video, × 0.6 par mot pénalisé absent de la référence. Similarité = Jaro-Winkler (crate
  `strsim`).
- [ ] **Step 5 : vérifier** — `cargo test -p ytmusic-resolve` → PASS.
- [ ] **Step 6 : commit** — `feat: score de correspondance YouTube Music`.

### Task 2 : recherche YouTube Music → candidats

**Files :**
- Create : `crates/resolve/src/http.rs`, `src/error.rs`, `src/search.rs`
- Create : `crates/resolve/tests/fixtures/search_*.json` (réponses réelles enregistrées)
- Test : `crates/resolve/tests/search.rs`

**Interfaces :**
- Consumes : `Candidate`, `ResultKind` (tâche 1).
- Produces :
  ```rust
  pub enum Method { Get, Post }
  pub struct HttpRequest { pub method: Method, pub url: String,
                           pub headers: Vec<(String, String)>, pub body: Option<Vec<u8>> }
  pub struct HttpResponse { pub status: u16, pub headers: Vec<(String, String)>, pub body: Vec<u8> }
  pub trait Http { async fn send(&self, req: HttpRequest) -> Result<HttpResponse, ResolveError>; }
  pub enum ResolveError { Network(String), ProviderWall(String), RateLimited,
                          NotFound, NeedsJs, Parse(String) }
  pub async fn search(http: &impl Http, query: &str, region: &str) -> Result<Vec<Candidate>, ResolveError>;
  ```

- [ ] **Step 1 : enregistrer 3 fixtures** depuis l'API InnerTube de YouTube Music
  (`POST https://music.youtube.com/youtubei/v1/search?prettyPrint=false`, client `WEB_REMIX`,
  `hl: "en"` pour des libellés « Song » / « Video » stables, `gl` = région) : une recherche
  pop anglaise, une japonaise, une qui renvoie des clips et des titres mélangés.
- [ ] **Step 2 : écrire les tests qui échouent** avec un `FakeHttp` qui renvoie la fixture :
  `parses_songs_and_videos` (kinds, `video_id` de 11 caractères, durées en ms),
  `status_429_is_rate_limited`, `status_403_is_provider_wall`, `garbage_body_is_parse_error`.
- [ ] **Step 3 : vérifier l'échec** — `cargo test -p ytmusic-resolve --test search` → FAIL.
- [ ] **Step 4 : implémenter** `search` : extraction des éléments des étagères de résultats
  (titre, artistes, durée « m:ss », type depuis le premier segment du sous-titre).
- [ ] **Step 5 : vérifier** → PASS. **Step 6 : commit** — `feat: recherche YouTube Music`.

### Task 3 : résolution d'un `videoId` en flux audio

**Files :**
- Create : `crates/resolve/src/player.rs`, `src/profile.rs`
- Create : `crates/resolve/tests/fixtures/player_*.json`
- Test : `crates/resolve/tests/player.rs`

**Interfaces :**
- Consumes : `Http`, `ResolveError` (tâche 2).
- Produces :
  ```rust
  pub enum Quality { Low, Normal, High }
  pub struct ClientProfile { pub client_name: &'static str, pub client_version: &'static str,
                             pub user_agent: &'static str, pub extra_headers: &'static [(&'static str, &'static str)] }
  pub static PROFILES: &[ClientProfile];   // essayés dans l'ordre
  pub struct Resolved { pub url: String, pub headers: Vec<(String, String)>,
                        pub expires_at_unix: u64, pub mime: String, pub bitrate: u32,
                        pub loudness_db: Option<f32> }
  pub async fn resolve(http: &impl Http, video_id: &str, quality: Quality, region: &str)
      -> Result<Resolved, ResolveError>;
  ```

- [ ] **Step 1 : trouver le profil client** qui renvoie des formats audio avec `url` directe
  sans OAuth : demander à l'utilisateur la configuration qui marchait dans Auqw, ou lire
  (sans copier) l'ancien plugin YouTube d'Auqw. Remplir `PROFILES` avec ce profil en
  premier. Enregistrer les fixtures `player_ok.json`, `player_cipher_only.json` (formats en
  `signatureCipher`), `player_bot.json` (`LOGIN_REQUIRED`, raison mentionnant le bot),
  `player_unplayable.json`.
- [ ] **Step 2 : écrire les tests qui échouent** :
  `picks_highest_bitrate_for_high`, `picks_closest_to_128k_for_normal`,
  `picks_lowest_for_low`, `reads_loudness_db`, `expiry_from_expire_param`
  (repli : maintenant + 6 h), `cipher_only_formats_need_js`,
  `player_login_required_bot_is_provider_wall`, `unplayable_is_not_found`,
  `falls_back_to_next_profile_on_provider_wall`.
- [ ] **Step 3 : vérifier l'échec** → FAIL.
- [ ] **Step 4 : implémenter** `resolve` : `POST …/youtubei/v1/player` avec le profil ; ne
  garder que les `adaptiveFormats` `audio/*` avec `url` ; `playerConfig.audioConfig.loudnessDb`
  pour `loudness_db` ; `headers` = User-Agent du profil + `extra_headers`.
- [ ] **Step 5 : vérifier** → PASS. **Step 6 : commit** — `feat: résolution des flux audio`.

### Task 4 : corpus de correspondance et CLI de mesure

**Files :**
- Create : `crates/cli/Cargo.toml`, `crates/cli/src/main.rs`, `crates/cli/src/reqwest_http.rs`
- Create : `corpus/deezer_ids.txt`, `corpus/corpus.json`
- Test : `crates/cli/src/main.rs` (module `#[cfg(test)]`)

**Interfaces :**
- Consumes : `search`, `best_match`, `resolve`, `Http` (tâches 1-3).
- Produces : le binaire `ytm` et les fichiers suivants :
  - `corpus.json` : `[{ "deezer_id": u64, "title", "artists": [..], "album", "duration_ms",
    "expected_video_id" }]` ;
  - `playlist.json` (sous-commande `playlist`) : `[{ "title", "url", "headers": {..},
    "expires_at_unix" }]`.

- [ ] **Step 1 : implémenter `ReqwestHttp`** (rustls, délai 10 s) et un limiteur simple :
  **une requête YouTube toutes les 1,5 s** au maximum.
- [ ] **Step 2 : sous-commande `ytm corpus-build`** : pour chaque id de `deezer_ids.txt`,
  `GET https://api.deezer.com/track/{id}` (durée Deezer en secondes × 1000), puis affiche les
  3 meilleurs candidats YouTube et écrit `corpus.json` avec `expected_video_id` vide.
- [ ] **Step 3 : constituer le corpus (humain)** : environ 100 ids Deezer répartis en
  40 grand public EN/FR, 15 en écriture non latine, 15 avec des pièges (versions live,
  remix, acoustiques existantes), 10 classique / titres longs, 10 indé confidentiels,
  10 avec beaucoup de featurings. **L'utilisateur confirme chaque `expected_video_id`** ;
  l'agent peut proposer.
- [ ] **Step 4 : test qui échoue** `check_continues_after_provider_wall` : avec un faux
  `Http` qui renvoie un mur anti-bot pour un titre sur trois, `run_check` termine et compte
  ces titres dans `walls` plutôt que dans `wrong`.
- [ ] **Step 5 : sous-commande `ytm corpus-check`** :
  `struct CorpusEntry` (champs de `corpus.json`, serde) ;
  `async fn run_check(http: &impl Http, corpus: &[CorpusEntry]) -> CheckReport`
  avec `CheckReport { ok, wrong, not_found, walls: u32, accuracy: f32 }`
  (`accuracy = ok / (ok + wrong + not_found)`), affiche le rapport et sort en erreur si
  `accuracy < 0.95`.
- [ ] **Step 6 : vérifier** — `cargo test` → PASS ; puis le test réel
  `cargo run -p ytm -- corpus-check corpus/corpus.json` → **accuracy ≥ 0.95**. Noter le
  résultat et les erreurs pour le rapport (tâche 7).
- [ ] **Step 7 : sous-commande `ytm playlist <n>`** : résout les `n` premiers titres du
  corpus en qualité `Normal` et écrit `playlist.json`.
- [ ] **Step 8 : commit** — `feat: corpus et CLI de mesure`.

### Task 5 : `core/contract` + `core/plugin-host` minimal sur Wasmtime + Pulley

**Files (dépôt `Vehicoule`) :**
- Create : `LICENSE` (MPL-2.0), `README.md`, `.gitignore`, `core/Cargo.toml` (workspace)
- Create : `core/contract/{Cargo.toml, LICENSE-MIT, LICENSE-APACHE, wit/host.wit, src/lib.rs}`
- Create : `core/plugin-host/{Cargo.toml, src/lib.rs, src/engine.rs, src/http.rs}`
- Create : composants de test `core/plugin-host/guests/{echo,spin,hog}/` (workspace séparé,
  cible `wasm32-wasip2`, exclu du workspace principal)
- Test : `core/plugin-host/tests/budgets.rs`

**Interfaces :**
- Produces :
  - WIT `package vehicoule:host@0.1.0;` (0.x = brouillon, le contrat 1.0 sera conçu dans le
    plan du socle), `interface http { record request { method: string, url: string,
    headers: list<tuple<string, string>>, body: option<list<u8>> } record response
    { status: u16, headers: list<tuple<string, string>>, body: list<u8> } variant
    http-error { network(string), too-large, timeout } send: func(req: request) ->
    result<response, http-error>; }` et `world probe { import http; export run:
    func(input: string) -> result<string, string>; }`.
  - ```rust
    pub struct Limits { pub fuel: u64, pub epoch_ticks: u64, pub memory_bytes: usize,
                        pub max_response_bytes: usize }
    impl Default for Limits   // 200_000_000, 300, 64 Mio, 8 Mio
    pub struct Host { /* Engine + ticker d'epoch toutes les 100 ms */ }
    pub struct Plugin { /* Component compilé + son Linker */ }
    impl Host {
        pub fn new() -> anyhow::Result<Host>;
        pub fn compile(&self, wasm: &[u8]) -> anyhow::Result<Plugin>;   // Pulley, sur l'appareil
        pub async fn run(&self, p: &Plugin, input: &str, limits: Limits) -> Result<String, RunError>;
    }
    pub enum RunError { OutOfFuel, Deadline, Memory, Guest(String), Internal(String) }
    ```

- [ ] **Step 1 : workspace, licences, crate `contract`** avec `wit/host.wit` et les bindings
  hôte (`wasmtime::component::bindgen!`, imports en mode async ; la syntaxe exacte dépend de
  la LTS choisie).
- [ ] **Step 2 : composants de test** : `echo` (appelle `http.send` sur l'URL reçue et
  renvoie le statut), `spin` (boucle infinie), `hog` (alloue 100 Mio). Construits par un
  helper de test via `cargo build --release --target wasm32-wasip2` (une seule fois,
  `OnceLock`).
- [ ] **Step 3 : écrire les tests qui échouent** (serveur HTTP local via `wiremock`) :
  `echo_returns_status_through_async_http`, `spin_runs_out_of_fuel`,
  `spin_hits_epoch_deadline_with_unlimited_fuel` (fuel `u64::MAX`, `epoch_ticks: 2`),
  `hog_hits_memory_limit`, `oversized_response_is_rejected` (corps de 9 Mio → `too-large`,
  lecture du corps interrompue à 8 Mio), `engine_targets_pulley`.
- [ ] **Step 4 : vérifier l'échec** — `cargo test -p plugin-host` → FAIL.
- [ ] **Step 5 : implémenter** `Host` : `Config::target("pulley64")`, fuel, interruption par
  epoch, support async, `StoreLimits` ; une instance neuve par `run` ; `http.send` via
  reqwest avec lecture du corps en flux plafonnée à `max_response_bytes`.
- [ ] **Step 6 : vérifier** → PASS. **Step 7 : commit** — `feat: hôte de plugins minimal
  (Wasmtime + Pulley)`.

### Task 6 : mesures sur Android arm64 (Wasmtime, lecture, licences)

**Files (dépôt `Vehicoule`, jetables) :**
- Create : `probes/README.md` (« jetable, supprimé quand le socle remplace ces sondes »)
- Create : `probes/wasmtime-android/` (binaire qui utilise `plugin-host`) et
  `probes/baseline-android/` (mêmes dépendances tokio + reqwest, sans Wasmtime)
- Create : `probes/android-playback/` (app Flutter : `flutter create --org
  app.vehicoule.probe --platforms android playback`)
- Create : `probes/android-playback/tool/check_log.dart`, `tool/check_licenses.sh`

**Interfaces :**
- Consumes : `Host`, `Limits`, composants de test (tâche 5) ; `playlist.json` (tâche 4).
- Produces : les mesures reportées dans la tâche 7.

- [ ] **Step 1 : Wasmtime sur l'appareil** :
  `cargo ndk -t arm64-v8a build --release -p wasmtime-android-probe`, `adb push` du binaire et
  des 3 composants dans `/data/local/tmp/`, puis exécution via `adb shell`. Attendu :
  `echo` renvoie 200 (sur `https://example.com`), `spin` → `OutOfFuel`, `spin` sans limite de
  fuel → `Deadline`, `hog` → `Memory`. Noter le temps de compilation Pulley de chaque
  composant.
- [ ] **Step 2 : taille** : `llvm-strip` des deux binaires, puis
  `taille(wasmtime-android-probe) − taille(baseline-android)` **≤ 10 Mio**.
- [ ] **Step 3 : app de lecture** : `media_kit` + `media_kit_libs_audio` + `audio_service`
  (versions figées dans `pubspec.yaml`) ; au lancement, lit `files/playlist.json`, ouvre
  une playlist `media_kit` avec les en-têtes de chaque titre, relie lecture / pause /
  suivant de l'écran verrouillé au lecteur. Manifest : `FOREGROUND_SERVICE`,
  `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `WAKE_LOCK`, service `audio_service` de type
  `mediaPlayback`. Chaque événement (début, fin, erreur, chargement > 2 s) est ajouté en
  JSON à `files/playback-log.jsonl` : `{ "t": ms, "event", "index", "detail" }`.
- [ ] **Step 4 : test d'1 h** : générer `ytm playlist 25` sur le Mac **juste avant**, avec le
  téléphone sur **le même Wi-Fi** (les URLs YouTube sont liées à l'IP publique), `adb push`
  vers `/sdcard/Android/data/app.vehicoule.probe.playback/files/`, lancer, éteindre l'écran,
  attendre 1 h, `adb pull` du log.
- [ ] **Step 5 : `check_log.dart`** : asserts — durée écoutée cumulée ≥ 3600 s, zéro
  événement `error`. Affiche aussi l'écart maximal entre une fin de titre et le début du
  suivant (à noter pour le rapport : c'est le préchargement de la spec 3.1).
  `dart run tool/check_log.dart playback-log.jsonl` → PASS.
- [ ] **Step 6 : `check_licenses.sh`** : sur les `.so` arm64 du build release
  (`build/app/intermediates/merged_native_libs/`), `strings` sur `libavcodec*`,
  `libavformat*` et `libmpv*` : échec si `--enable-gpl` ou `--enable-nonfree` apparaît dans
  la configuration FFmpeg, ou si la licence affichée est « GPL ». À lancer avec
  `media_kit_libs_audio`, puis en remplaçant temporairement par `media_kit_libs_video`
  (l'anime en dépendra), puis revenir à `media_kit_libs_audio`.
- [ ] **Step 7 : commit** — `chore: sondes Android (Wasmtime, lecture, licences)`.

### Task 7 : rapport de l'étape 1 et décision

**Files :**
- Create : `docs/superpowers/reports/2026-10-etape-1-faisabilite.md`

- [ ] **Step 1 : remplir le tableau** critère → seuil → mesuré → OK/KO : corpus (≥ 95 %),
  murs anti-bot rencontrés, profil client retenu, `NeedsJs` rencontré ou non, 1 h écran
  éteint, écart max entre titres, Wasmtime (fuel, epoch, mémoire, HTTP async, taille
  ≤ 10 Mio, temps de compilation Pulley), licences `media_kit` audio et vidéo.
- [ ] **Step 2 : décisions écrites** : composants WASM gardés **ou** repli Wasmi (spec
  4.2 bis) ; interface hôte `js` nécessaire ou non (spec 4.5) ; recompilation LGPL de
  libmpv / FFmpeg nécessaire ou non.
- [ ] **Step 3 : commit** — `docs: rapport de l'étape 1`. La suite est la rédaction des plans
  du socle, à partir de ces décisions.
