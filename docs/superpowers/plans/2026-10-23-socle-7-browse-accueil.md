# Socle 7 — `music.browse` et fil d'accueil : plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** ce que les écrans Accueil, Explorer, Bibliothèque et Réglages du plan 5 demandent au cœur :
- la capacité `browse` (contrat 1.1, hôte, plugin Deezer) ;
- le fil d'accueil personnel ;
- les tris paginés, le Top 50, l'historique daté et les suggestions typées ;
- les préférences d'interface ;
- le pont régénéré.

**Architecture :**
- `browse` s'ajoute au contrat comme une interface exportée de plus. L'hôte la détecte comme
  les autres. Le cœur la route et met en cache ses réponses.
- Le fil d'accueil est un module `home` du cœur, en deux couches :
  - une fonction pure qui assemble les étagères à partir d'entrées déjà chargées ;
  - une couche qui charge ces entrées (base locale, radio, `browse`) et stocke le résultat en
    `kv`.
- L'accueil lit toujours ce cache.

**Tech Stack :** Rust 2024, Wasmtime 48.0.6, wit-bindgen 0.63, flutter_rust_bridge 2.13.0,
rusqlite, serde_json.

**Spec :** `docs/superpowers/specs/2026-10-23-socle-ui-design.md`, sections 1, 6.1–6.3, 6.7
(réglage), 7, 9. Socle : §4.2, §4.7, §5.

Prérequis : plans 1, 2, 4 et 6 terminés. Le plan 5 (Tasks 6 et 7) consomme ce plan.

## Global Constraints

- **Dépôts :**
  - `/Users/btw/Documents/repo/Vehicoule-socle`, branche `socle` : contrat, SDK, hôte, cœur,
    pont.
  - `/Users/btw/Documents/repo/vehicoule-plugins`, branche `socle-plugins` : Deezer, itunes,
    lrclib.

  Commit = `git commit -s -m "<msg>" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"`.
  Ne jamais stash, reset, ni changer de branche. Ne jamais lancer de script de publication
  ou de signature. Ne jamais lire ni copier `~/.config/vehicoule/feed-keys/`.
- **Contrat :**
  - le paquet `vehicoule:music` passe à **1.1.0** ;
  - `vehicoule:host` reste à **1.0.0** ;
  - les manifestes acceptés sont `"contract": "1.0"` et `"1.1"` ;
  - tags `contract-v1.1.0` et `plugin-host-v1.1.0` à la fin des Tasks 1 et 2.
- **Compatibilité :** un plugin 1.0 se charge dans l'hôte 1.1, sans `browse`. La recherche
  d'export de Wasmtime 48 tient compte de semver (`@1.1.0` trouve un export `@1.0.0`). Le
  test de la Task 2 le prouve. **S'il échoue, s'arrêter et le signaler (BLOCKED), sans
  contournement.**
- **Cache du cœur :** la table `plugin_kv`, sous l'espace `"@core"`. Ce nom est invalide comme
  id de plugin (`validate_id`), donc aucun plugin ne peut le lire.

  | Clé | Contenu |
  |---|---|
  | `browse_categories` | catégories `browse` |
  | `browse_category:<id>` | première page d'une catégorie |
  | `browse_releases:<artist item id>` | sorties d'un artiste |
  | `home_feed` | le fil d'accueil |

  Chaque valeur est en JSON et porte `built_at_ms`. Durée de vie : **24 h**. Hors ligne, ou
  si l'appel échoue, on sert la dernière copie quel que soit son âge.
- **Valeurs de la spec :**
  - découverte : **30** titres, au plus **5** graines ;
  - fenêtre du top : **90 jours** ;
  - une écoute compte à partir de **30 s** (`listened_ms ≥ 30_000`) ;
  - Top 50 : **50** titres ;
  - Redécouvrir : likés **non écoutés depuis 60 jours** ;
  - Nouveautés : sorties de **moins de 30 jours**, au plus **10** artistes likés par jour ;
  - pages du fil : **4** étagères ;
  - raccourcis : **6** collections.
- **Vie privée :** réglage d'appareil `discover`, activé sauf s'il vaut `"false"`. Désactivé,
  le fil ne contient que des étagères locales et aucun appel `radio` ou `browse` n'en part.
  Un test le prouve en comptant les appels.
- **Textes :** le cœur ne produit aucun texte d'interface. Les étagères portent un `kind` et
  une `seed` (nom affichable), et Dart traduit.
- **Pas de code hérité :** l'ancienne `api::library::home()` et `HomeView` sont supprimées,
  pas dépréciées.
- **Vérifications de chaque task Rust :**
  - `cargo test` des crates touchées, **deux fois** ;
  - `cargo clippy --workspace --all-targets -- -D warnings` ;
  - `cargo fmt --check` sur les crates touchées.
- **Pont :** tout changement d'API régénère le pont (`flutter_rust_bridge_codegen generate`,
  comme au plan 4) et passe `flutter analyze` dans `app/`.

## Review Focus

1. **Fil construit hors ligne ou sans plugin `browse` / `radio`** : l'accueil montre les
   étagères locales et la fin, sans erreur ni étagère vide.
   → test `feed_offline_keeps_local_shelves` (Task 6).
2. **Historique vide (premier lancement)** : la découverte prend ses graines dans la première
   catégorie vedette de `browse` ; sans `browse`, le fil ne contient que `End`.
   → test `feed_first_launch_seeds_from_chart` (Task 6).
3. **Le même morceau chez deux fournisseurs** (ids différents, ISRC absent) n'apparaît
   qu'une fois dans la découverte, et jamais s'il est déjà écouté ou liké.
   → test `discovery_dedupes_by_folded_title_and_artist` (Task 6).
4. **Réglage `discover` coupé pendant qu'un fil réseau est en cache** : le fil n'expose
   plus aucune étagère réseau, même en cache.
   → test `discover_off_hides_cached_network_shelves` (Task 7).
5. **Pagination qui tombe sur une étagère « Parce que tu as écouté X » non chargée, hors
   ligne** : elle est sautée, et la page reste de 4 étagères tant qu'il en reste.
   → test `unloaded_because_shelf_is_skipped_offline` (Task 7).

---

### Task 1 : contrat `vehicoule:music` 1.1.0 et SDK

**Files :**
- Modify : `core/contract/wit/music/music.wit` : `package vehicoule:music@1.1.0`, nouvelle
  `interface browse`, `export browse` dans le monde `plugin`.
- Modify : `core/contract/src/lib.rs` : `browse` ajouté au module `music` ; commentaires
  `@1.1.0`.
- Modify : `sdk/src/lib.rs` si un chemin ou un nom de version y est écrit en dur.
- Modify : `core/plugin-host/guests/wit/world.wit` et `core/core/tests/guests/wit/world.wit`
  (les copies vendorisées), qui restent identiques au contrat.
- Test : `core/contract/tests/` (le test existant qui compare les WIT vendorisés, ou un
  nouveau `browse_shape.rs`).

**Interfaces :**
- Produces (WIT, recopié de la spec §7.1) :
  ```wit
  interface browse {
      use types.{error, image, album};
      use entity.{entity};
      record category { id: string, title: string, artwork: list<image>, featured: bool }
      record shelf { title: string, items: list<entity> }
      record category-page { title: string, shelves: list<shelf>, next: option<string> }
      record release {
          album: album,
          /// ISO 8601 `YYYY-MM-DD`.
          date: string,
      }
      categories: func(region: string) -> result<list<category>, error>;
      fetch-category: func(id: string, region: string, cursor: option<string>) -> result<category-page, error>;
      releases: func(artist-id: string, region: string) -> result<list<release>, error>;
  }
  ```
- Rust : `contract::music::browse::{Category, Shelf, CategoryPage, Release}`.

- [ ] **Step 1 : test qui échoue** : `music_wit_is_1_1_with_browse`. Il vérifie que
  `MUSIC_WIT` commence par `package vehicoule:music@1.1.0;`, contient `interface browse` et
  `export browse;`, et que `HOST_WIT` reste `@1.0.0`.
- [ ] **Step 2 :** `cargo test -p contract` → FAIL.
- [ ] **Step 3 : implémenter.** Le reste du fichier ne change pas : additif seulement.
- [ ] **Step 4 :** `cargo test -p contract`, puis `cargo build` du SDK pour
  `wasm32-wasip2` → PASS.
- [ ] **Step 5 : commit**, `feat(contract): music 1.1 — interface browse`, puis
  `git tag contract-v1.1.0`.

### Task 2 : hôte — capacité `Browse`, compatibilité 1.0

**Files :**
- Modify : `core/plugin-host/src/lib.rs`, ajouter `Capability::Browse`.
- Modify : `core/plugin-host/src/engine.rs`, la détection `browse::GuestIndices::new(&pre)`.
- Modify : `core/plugin-host/src/calls.rs`, trois appels.
- Modify : `core/plugin-host/src/cache.rs`, ajouter `Browse` aux capacités cachées 24 h par
  défaut, comme `Search`.
- Modify : `core/plugin-host/src/manifest.rs`, `validate_contract` accepte `1.0` et `1.1`.
- Create : un composant de test `core/plugin-host/guests/browse-only/` (monde qui n'exporte
  que `browse@1.1.0`).
- Keep : un composant de test existant reste compilé contre le WIT **1.0.0**. Vendoriser
  l'ancien `music.wit` 1.0 dans `guests/wit-1.0/` pour lui.
- Test : `core/plugin-host/tests/browse.rs`.

**Interfaces :**
- Produces :
  ```rust
  impl Host {
      pub async fn browse_categories(&self, p: &Plugin, region: &str) -> Result<Vec<Category>, CallError>;
      pub async fn browse_category(&self, p: &Plugin, id: &str, region: &str, cursor: Option<String>) -> Result<CategoryPage, CallError>;
      pub async fn browse_releases(&self, p: &Plugin, artist_id: &str, region: &str) -> Result<Vec<Release>, CallError>;
  }
  ```
  Les images hors de l'allowlist sont retirées, comme pour les autres appels
  (`keep_allowed`).

- [ ] **Step 1 : tests qui échouent**
  ```rust
  #[tokio::test] async fn plugin_1_0_loads_without_browse()      // guest 1.0 : load Ok, capabilities sans Browse, search/lyrics appelables
  #[tokio::test] async fn browse_only_guest_exposes_browse()      // capabilities == {Browse}; les 3 appels rendent ce que le guest renvoie
  #[test] fn contract_1_1_is_accepted_2_0_is_not()                 // "1.0" ok, "1.1" ok, "1.2" err, "2.0" err
  #[tokio::test] async fn browse_artwork_outside_allowlist_is_dropped()
  ```
- [ ] **Step 2 :** `cargo test -p plugin-host` → FAIL. Si `plugin_1_0_loads_without_browse`
  ne peut pas passer, s'arrêter : voir Global Constraints.
- [ ] **Step 3 : implémenter.**
- [ ] **Step 4 :** tests, clippy et fmt → PASS.
- [ ] **Step 5 : commit**, `feat(plugin-host): capacité browse, contrats 1.0 et 1.1`, puis
  `git tag plugin-host-v1.1.0`.

### Task 3 : plugin Deezer — `browse` (dépôt `vehicoule-plugins`)

**Files :**
- Modify : `Cargo.toml` de chaque plugin et de `tests/` : tags `contract-v1.1.0` et
  `plugin-host-v1.1.0`.
- Modify : `wit/music/music.wit` (vendorisé), pour suivre le SDK. Mettre à jour le test
  `wit_deps_match_sdk` avec `UPDATE_WIT=1`.
- Modify : les `wit/world.wit` et les `with:` de `lib.rs` de deezer, itunes et lrclib, de
  `@1.0.0` vers `@1.1.0` (mécanique). Mettre à jour les manifestes : `"contract": "1.1"`, et
  `"version": "0.2.0"` pour deezer.
- Modify : `plugins/deezer/wit/world.wit`, ajouter `export vehicoule:music/browse@1.1.0;`.
- Modify : `plugins/deezer/src/api.rs` (les parseurs) et `plugins/deezer/src/lib.rs`
  (`impl browse::Guest`).
- Create : `tests/fixtures/deezer/{browse_genres,browse_chart,browse_selection,browse_releases}/`,
  enregistrés avec l'outil de rejeu du plan 6 (Task 4).
- Test : `plugins/deezer/src/api.rs` (`#[cfg(test)]`), `tests/tests/deezer.rs`.

**Interfaces :**
- Correspondance (spec §7.1, sondée le 2026-10-23) :
  - `categories` = deux vedettes, puis les genres de `/genre` sauf l'id 0 (« Tous ») :
    - `{ id: "chart:0", title: "Top 50", featured: true }`, artwork du premier titre de
      `/chart/0/tracks` ;
    - `{ id: "selection:0", title: "Sélection", featured: true }`, artwork du premier album de
      `/editorial/0/selection`.

    Une catégorie de genre vaut `{ id: "genre:<id>", title: name, artwork: picture_xl /
    picture_medium, featured: false }`. Les titres des vedettes sont des noms propres du
    fournisseur, pas du texte d'interface.
  - `fetch-category("chart:<g>" | "genre:<g>")` = `/chart/<g>` en quatre étagères dans cet ordre :
    titres, albums, artistes, playlists. Les titres d'étagère valent `"tracks"`, `"albums"`,
    `"artists"` et `"playlists"`, des clés que Dart traduit. Les étagères vides sont omises.
    `next` = `None` (les classements Deezer tiennent en une page).
  - `fetch-category("selection:0")` = une étagère `"albums"` tirée de `/editorial/0/selection`.
  - `releases(artist)` = `/artist/<id>/albums?limit=50`, triées par `release_date`
    décroissante. Les albums sans date sont omis.
  - `region` est ignoré : les classements Deezer suivent le pays de l'IP.
  - Un id inconnu donne `not-found`.

- [ ] **Step 1 : tests unitaires qui échouent** (sur les JSON enregistrés)
  ```rust
  #[test] fn genres_parse_without_all()               // id 0 absent, picture_xl d'abord
  #[test] fn chart_parses_into_four_ordered_shelves()  // titres "tracks","albums","artists","playlists" ; vide → omise
  #[test] fn releases_sorted_newest_first_undated_dropped()
  #[test] fn unknown_category_id_is_not_found()       // "foo:1" → Error::NotFound sans requête
  ```
- [ ] **Step 2 : tests e2e qui échouent** (rejeu, vrai `.wasm`, `plugin-host` 1.1)
  ```rust
  async fn browse_categories_lists_featured_then_genres()  // [0], [1] featured, puis featured == false
  async fn browse_chart_category_has_track_shelf()
  async fn browse_releases_has_dates()                      // date au format YYYY-MM-DD
  async fn manifest_and_exports_match()                     // existant : exports deezer = {search, entity, radio, browse}
  ```
- [ ] **Step 3 :** `cargo test --workspace` → FAIL.
- [ ] **Step 4 : implémenter.**
- [ ] **Step 5 :** `cargo test --workspace` deux fois, clippy, fmt, puis
  `cargo build --release --target wasm32-wasip2` → PASS. Les tests itunes et lrclib passent
  inchangés.
- [ ] **Step 6 : commit**, `feat(deezer): browse (genres, classements, sélection, sorties) ; contrat 1.1`.

### Task 4 : cœur — `browse` routé, caché, exposé

**Files :**
- Modify : `core/core/src/router.rs`, `cap_name(Browse) = "browse"` ; liste de
  `capability()` ; ordre par défaut `["deezer"]`.
- Modify : `core/core/src/error.rs`, `_Capability` miroir avec `Browse`.
- Create : `core/core/src/browse.rs` (appels routés, cache `@core`, conversion vers le
  catalogue).
- Create : `core/core/src/api/browse.rs`, puis l'ajouter à `api/mod.rs`.
- Modify : `core/core/src/catalog.rs` : `CardView` y est défini, pour être réutilisé par la
  Task 7.
- Test : `core/core/src/browse.rs` (`#[cfg(test)]`, plugins de test du cœur).

**Interfaces :**
- Produces :
  ```rust
  // catalog.rs
  pub enum CardView { Track { track: TrackView, reason: Option<String> }, Collection(CollectionView) }
  // api/browse.rs
  pub struct CategoryView { pub id: String, pub title: String, pub artwork: Option<String>, pub featured: bool }   // artwork = id d'item pour artwork_file, ou None
  pub struct BrowseShelfView { pub title: String, pub items: Vec<CardView> }
  pub struct CategoryPageView { pub title: String, pub shelves: Vec<BrowseShelfView>, pub next: Option<String>, pub from_cache: bool }
  pub async fn browse_categories() -> Result<Vec<CategoryView>, CoreError>;
  pub async fn browse_category(id: String, cursor: Option<String>) -> Result<CategoryPageView, CoreError>;
  // browse.rs (crate) — utilisé par home
  pub(crate) async fn releases(artist: ItemId) -> Result<Vec<(ItemId, String /*date*/)>, CoreError>;
  ```
- Comportement :
  - Chaque entité reçue passe par `catalog::upsert_*` (comme `search`), donc les ids exposés
    sont ceux du cœur.
  - L'artwork d'une catégorie passe par un item du catalogue de genre `Kind::Playlist`, sans
    enfants (référence externe = id de la catégorie chez le fournisseur), pour que
    `artwork_file` serve l'image. L'item n'est ni liké ni dans une playlist perso, donc il
    n'apparaît jamais dans la bibliothèque.
  - Cache : la première page seulement. Une page suivante (`cursor`) n'est jamais servie
    depuis le cache.
  - `from_cache` vaut `true` quand on sert une copie.
  - Ni copie ni plugin : `NoPlugin(Browse)`. Hors ligne sans copie : `Offline`.

- [ ] **Step 1 : tests qui échouent**
  ```rust
  #[tokio::test] async fn categories_are_cached_24h()          // 2e appel < 24 h : aucun appel plugin
  #[tokio::test] async fn stale_categories_refetch()           // built_at_ms - 24 h - 1 : un appel
  #[tokio::test] async fn offline_serves_last_copy()           // ancienne de 3 jours, offline → Ok, from_cache
  #[tokio::test] async fn no_browse_plugin_is_no_plugin()       // CoreError::NoPlugin(Capability::Browse)
  #[tokio::test] async fn category_items_are_catalogued()       // les ids rendus passent parse_id et track_view
  #[tokio::test] async fn releases_map_to_items_with_dates()
  #[tokio::test] async fn category_artwork_item_not_in_library_search()   // search_library(titre de la catégorie) == []
  ```
- [ ] **Step 2 :** `cargo test -p vehicoule-core browse` → FAIL.
- [ ] **Step 3 : implémenter**, régénérer le pont, puis `flutter analyze`.
- [ ] **Step 4 :** vérifications Rust (Global Constraints) → PASS.
- [ ] **Step 5 : commit**, `feat(core): capacité browse routée et mise en cache`.

### Task 5 : bibliothèque — tris, Top 50, historique daté, suggestions typées, contexte des écoutes

**Files :**
- Create : `core/core/migrations/0002_play_context.sql`, avec
  `ALTER TABLE plays ADD COLUMN context_id BLOB REFERENCES items(id);` et l'index
  `plays_context` sur `(context_id, started_at DESC) WHERE context_id IS NOT NULL`.
- Modify : `core/core/src/library/plays.rs`. `start` prend `context: Option<ItemId>`. Ajouter
  les fonctions de requête ci-dessous.
- Modify : `core/core/src/library/likes.rs` et `library/downloads.rs`, pour les variantes
  triées.
- Modify : `core/core/src/player.rs:~1105`. Le contexte de la file (`PlayContext.id`, pour
  `kind` ∈ album, playlist, artist) est enregistré avec l'écoute.
- Modify : `core/core/src/api/library.rs` et `core/core/src/catalog.rs` (suggest).
- Test : dans chaque fichier `library/*.rs` modifié, plus `core/core/src/api/library.rs`.

**Interfaces :**
- Produces :
  ```rust
  pub enum TrackSort { Added, Title, Artist }               // Added = liked_at / created_at desc ; Title, Artist = fold() asc
  pub enum CollectionSort { Recent, Played, Title }         // Recent = liked_at / created_at desc ; Played = dernière écoute d'un de ses titres desc ; Title = fold(title) asc (pas `Name` : en Dart, `name` est déjà un getter des enums)
  pub struct HistoryEntryView { pub played_at_ms: i64, pub track: TrackView }
  pub struct SuggestionView { pub text: String, pub from_history: bool }
  pub async fn liked(kind: ItemKind, sort: CollectionSort, offset: u32, limit: u32) -> Result<Vec<CollectionView>, CoreError>;
  pub async fn liked_tracks(sort: TrackSort, offset: u32, limit: u32) -> Result<Vec<TrackView>, CoreError>;
  pub async fn playlists(sort: CollectionSort) -> Result<Vec<CollectionView>, CoreError>;
  pub async fn downloaded(sort: TrackSort, offset: u32, limit: u32) -> Result<Vec<TrackView>, CoreError>;
  pub async fn top_tracks() -> Result<Vec<TrackView>, CoreError>;
  pub async fn history(offset: u32, limit: u32) -> Result<Vec<HistoryEntryView>, CoreError>;
  pub async fn suggest(prefix: String) -> Result<Vec<SuggestionView>, CoreError>;   // api/catalog.rs, remplace Vec<String>
  // library/plays.rs, pour home (Task 6)
  pub fn top_items(c: &Connection, kind: Kind, since_ms: i64, limit: u32) -> rusqlite::Result<Vec<ItemId>>;  // Track : écoutes ≥ 30 s ; Artist : via music_track_artists
  pub fn top_contexts(c: &Connection, since_ms: i64, limit: u32) -> rusqlite::Result<Vec<ItemId>>;          // collections par nombre d'écoutes récentes
  pub fn liked_not_played_since(c: &Connection, before_ms: i64, limit: u32) -> rusqlite::Result<Vec<ItemId>>;
  pub fn played_or_liked(c: &Connection) -> rusqlite::Result<HashSet<ItemId>>;   // pour exclure de la découverte
  ```
- Top 50 : `top_items(Track, now − 90 j, 50)`. S'il rend moins de 50 titres, on complète
  avec `top_items(Track, 0, 50)` sans doublon. Ordre : nombre d'écoutes décroissant, puis
  dernière écoute.
- L'ancienne signature `downloads()` (progression) ne change pas. `downloaded` liste les
  titres terminés.

- [ ] **Step 1 : tests qui échouent**
  ```rust
  #[test] fn plays_record_their_context()
  #[test] fn top_items_counts_only_30s_plays_in_window()     // 29 999 ms ignoré ; écoute à 91 j ignorée
  #[test] fn top_50_backfills_from_all_time()
  #[test] fn liked_sorts_recent_played_title()                 // 3 albums, ordres attendus par tri
  #[test] fn liked_tracks_sort_by_artist_uses_fold()          // "Édith" avant "Zaz"
  #[test] fn sorted_pages_do_not_overlap()                    // offset 0..2 puis 2..4 : 4 ids distincts
  #[test] fn liked_not_played_since_excludes_recent_plays()
  #[tokio::test] async fn history_entries_carry_played_at()
  #[tokio::test] async fn suggest_marks_history_entries()     // historique "yoasobi" + plugin "yoasobi live" → [true, false], dédoublonnés
  ```
- [ ] **Step 2 :** → FAIL.
- [ ] **Step 3 : implémenter**, régénérer le pont, `flutter analyze`. Mettre à jour les
  appels Dart existants dans `app/integration_test/bridge_test.dart`, s'ils utilisent les
  anciennes signatures.
- [ ] **Step 4 :** vérifications Rust → PASS.
- [ ] **Step 5 : commit**, `feat(core): tris de bibliothèque, Top 50, historique daté, suggestions typées`.

### Task 6 : fil d'accueil — assemblage et construction

**Files :**
- Create : `core/core/src/home/mod.rs` (types stockés et `build`), `home/assemble.rs`
  (fonction pure) et `home/seeds.rs` (lectures locales).
- Modify : `core/core/src/player.rs`, pour exposer `radio_tracks(seed: ItemId) ->
  Result<Vec<ItemId>, CoreError>` (`pub(crate)`). Elle est extraite de l'actuelle
  `radio()`, sans le filtre « dernières écoutes » que la file garde de son côté.
- Test : `core/core/src/home/assemble.rs` (unitaires, sans base) et `home/mod.rs`
  (plugins de test du cœur).

**Interfaces :**
- Produces :
  ```rust
  #[derive(Serialize, Deserialize)] pub(crate) enum ShelfKind { Shortcuts, Discovery, Mixes, BecauseYouListened, NewReleases, Rediscover, Chart, Recent, Playlists, Downloads, End }
  #[derive(Serialize, Deserialize)] pub(crate) struct StoredItem { pub id: String, pub reason: Option<String> }   // reason = titre de la graine (découverte)
  #[derive(Serialize, Deserialize)] pub(crate) struct StoredShelf { pub kind: ShelfKind, pub seed: Option<String>, pub seed_id: Option<String>, pub network: bool, pub loaded: bool, pub items: Vec<StoredItem> }
  #[derive(Serialize, Deserialize)] pub(crate) struct FeedDoc { pub built_at_ms: i64, pub shelves: Vec<StoredShelf> }
  pub(crate) struct Inputs { /* locales : shortcuts, top_artists (id, nom), mixes, rediscover, recent, playlists, downloads, excluded: HashSet<ItemId>, folded_excluded: HashSet<String>;
                               réseau : discovery: Vec<(seed title, Vec<Candidate>)>, releases: Vec<ItemId>, chart: Vec<ItemId> */ }
  pub(crate) struct Candidate { pub id: ItemId, pub isrc: Option<String>, pub folded: String }   // folded = fold(titre) + "\u{1f}" + fold(premier artiste)
  pub(crate) fn assemble(inputs: Inputs, discover: bool) -> Vec<StoredShelf>;
  pub(crate) async fn build(now_ms: i64) -> Result<FeedDoc, CoreError>;   // lit les graines, appelle radio / browse si discover && online, assemble, écrit kv "@core"/"home_feed"
  ```
- **Assemblage** (le seul algorithme que les signatures ne déterminent pas) :
  1. **Découverte** : prendre les listes de candidats graine par graine, en alternance (le
     1er de chaque graine, puis le 2e…). Écarter un candidat dont l'id, l'ISRC ou la clé
     `folded` est déjà vu, ou présent dans `excluded` / `folded_excluded`. S'arrêter à 30.
     La `reason` est le titre de la graine.
  2. **Ordre des étagères** :
     `Shortcuts, Discovery, Mixes, BYL(a1), NewReleases, Rediscover, Chart, BYL(a2), Recent,
     BYL(a3), Playlists, BYL(a4), Downloads, BYL(a5…a10), End`.
     - `BYL(ai)` est le i-ème artiste du top. Il est créé avec `loaded: false, items: []` et
       se charge à la demande (Task 7).
     - Une étagère dont `items` est vide et `loaded == true` est omise.
     - `End` est toujours la dernière.
  3. **Sans `discover`** : seulement Shortcuts, Rediscover, Recent, Playlists, Downloads, End.
     Toutes ont `network: false`.
  4. **Historique vide** : les graines de la découverte sont les 5 premiers titres de la
     catégorie vedette `"chart:0"`, ou à défaut de la première vedette. Sans `browse`,
     l'étagère Discovery est omise.
- **Construction (`build`)** :
  - **Graines locales** :
    - les likés récents (5), puis `top_items(Track, 90 j)`, sans doublon, jusqu'à 5 au total ;
    - les artistes : `top_items(Artist, 90 j, 10)` ;
    - `mixes` = les 6 premiers artistes.
  - **Réseau** (seulement si `discover` est actif et en ligne) :
    - `radio_tracks` par graine de titre ;
    - `browse::releases` sur les 10 premiers artistes likés, avec la date ≥ maintenant − 30 j ;
    - la première étagère `"tracks"` de `browse_category("chart:0")`.
  - Une erreur réseau sur une source vide cette source seulement, et la consigne dans
    `logs::push`.

- [ ] **Step 1 : tests unitaires qui échouent** (`assemble`, sans base)
  ```rust
  #[test] fn discovery_round_robins_seeds_and_caps_at_30()
  #[test] fn discovery_dedupes_by_folded_title_and_artist()   // même titre/artiste, ids et ISRC différents → 1
  #[test] fn discovery_dedupes_by_isrc()
  #[test] fn discovery_excludes_played_or_liked()              // par id et par clé folded
  #[test] fn shelves_follow_the_spec_order_and_end_last()
  #[test] fn empty_loaded_shelves_are_omitted()
  #[test] fn discover_off_has_only_local_shelves()
  ```
- [ ] **Step 2 : tests d'intégration qui échouent** (`build`, plugins de test du cœur)
  ```rust
  #[tokio::test] async fn feed_offline_keeps_local_shelves()
  #[tokio::test] async fn feed_first_launch_seeds_from_chart()     // aucun plays / likes, browse de test → Discovery non vide ; sans browse → [End]
  #[tokio::test] async fn discover_off_makes_no_network_call()    // compteur d'appels du plugin de test == 0
  #[tokio::test] async fn build_writes_the_feed_doc()             // kv "@core"/"home_feed" relu == doc rendu
  ```
- [ ] **Step 3 :** `cargo test -p vehicoule-core home` → FAIL.
- [ ] **Step 4 : implémenter.** `radio_tracks` reprend l'appel routé et l'`upsert` de
  `radio()`. `radio()` l'utilise ensuite, sans changer son comportement : les tests du
  lecteur passent inchangés.
- [ ] **Step 5 :** vérifications Rust → PASS.
- [ ] **Step 6 : commit**, `feat(core): fil d'accueil — graines, découverte, assemblage`.

### Task 7 : fil d'accueil — API, déclencheurs, mixes, intégration

**Files :**
- Modify : `core/core/src/home/mod.rs`, pour `page`, le chargement paresseux des BYL et les
  déclencheurs.
- Modify : `core/core/src/api/library.rs`. Supprimer `home()` et `HomeView`, puis ajouter
  l'API ci-dessous.
- Modify : `core/core/src/api/settings.rs`, avec le champ `discover` (réglage d'appareil).
- Modify : `core/core/src/events.rs`, ajouter `LibraryChanged::Home`.
- Modify : `core/core/src/player.rs`, ajouter `play_mix`.
- Modify : `core/core/src/plugins.rs` (ou là où `set_online(true)` est traité), pour la
  reconstruction au retour en ligne.
- Modify : `app/integration_test/bridge_test.dart`.
- Test : `core/core/src/home/mod.rs`, `core/core/src/api/library.rs`.

**Interfaces :**
- Consumes : `home::build`, `FeedDoc`, `ShelfKind` (Task 6) ; `CardView` (Task 4) ;
  `radio_tracks` (Task 6).
- Produces :
  ```rust
  pub enum ShelfKindView { Shortcuts, Discovery, Mixes, BecauseYouListened, NewReleases, Rediscover, Chart, Recent, Playlists, Downloads, End }
  pub struct ShelfView { pub kind: ShelfKindView, pub seed: Option<String>, pub items: Vec<CardView> }   // seed = nom d'artiste (BYL) ; Discovery : CardView::Track avec reason ; Mixes : CardView::Collection d'artistes
  pub struct HomeFeedPage { pub shelves: Vec<ShelfView>, pub next: Option<String> }
  pub async fn home_feed(cursor: Option<String>) -> Result<HomeFeedPage, CoreError>;
  pub async fn refresh_home() -> Result<(), CoreError>;
  pub async fn play_mix(artist_id: String) -> Result<(), CoreError>;
  // Settings gagne `pub discover: bool` (défaut true ; clé d'appareil "discover")
  pub async fn ui_pref(key: String) -> Result<Option<String>, CoreError>;            // api/settings.rs
  pub async fn set_ui_pref(key: String, value: Option<String>) -> Result<(), CoreError>;
  ```
- **Préférences d'interface** :
  - stockées en réglages d'appareil (`settings_device`) ;
  - la clé doit commencer par `ui.`, sinon `NotFound` (même garde que les clés réservées de
    `device_set`) ;
  - `None` efface la valeur.

  Dart y range l'apparence (`ui.color_source`, `ui.preset`, `ui.pure_black`, `ui.theme`), le
  tri choisi par liste (`ui.sort.<liste>`), le rail déplié et le panneau ouvert. Le cœur ne
  les interprète pas.
- Règles :
  - **Curseur** : `cursor` est l'index (en texte) de la prochaine étagère dans `FeedDoc`.
    Une page rend jusqu'à **4** étagères affichables. `next` vaut `None` quand `End` est
    rendue.
  - **BYL non chargée** :
    - en ligne et `discover` actif : `radio_tracks` sur le titre le plus écouté de l'artiste,
      puis les albums et artistes distincts du résultat, sans l'artiste graine (au plus 12).
      L'étagère est écrite dans le doc avec `loaded: true` ;
    - sinon, elle est sautée pour cette page. Elle reste `loaded: false` et pourra se charger
      plus tard.
  - **`discover` désactivé** : les étagères `network: true` du doc en cache sont filtrées à
    la lecture. Le doc n'est pas réécrit.
  - **Déclencheurs** :
    1. `home_feed(None)` avec un doc absent ou de plus de 24 h : rend le doc actuel (ou, s'il
       est absent, un doc local construit sans réseau), et lance `build` en arrière-plan
       (un seul à la fois, comme `download_update`) ;
    2. `refresh_home()` : `build`, puis attente du résultat ;
    3. passage en ligne avec un doc de plus de 24 h : `build` en arrière-plan.

    Chaque `build` réussi émet `LibraryChanged::Home`.
  - **`play_mix(artist)`** : la graine est le titre de l'artiste avec le plus d'écoutes
    (`top_items` filtré sur l'artiste, toute la période). Sans écoute, c'est le premier titre
    de sa page `entity`. Ensuite `radio_tracks(graine)`, puis
    `play(items, 0, PlayContext { kind: "mix", id: Some(artist), title: nom })`. Hors ligne :
    `Offline`.

- [ ] **Step 1 : tests qui échouent**
  ```rust
  #[tokio::test] async fn feed_pages_by_four_and_ends()
  #[tokio::test] async fn unloaded_because_shelf_is_skipped_offline()
  #[tokio::test] async fn because_shelf_loads_once_and_is_stored()   // 2e lecture : aucun appel radio
  #[tokio::test] async fn discover_off_hides_cached_network_shelves()
  #[tokio::test] async fn stale_feed_rebuilds_in_background_once()   // 2 home_feed(None) rapprochés → 1 build
  #[tokio::test] async fn refresh_home_emits_library_changed_home()
  #[tokio::test] async fn play_mix_seeds_with_most_played_track()
  #[test] fn settings_discover_defaults_on()
  #[tokio::test] async fn ui_pref_round_trips_and_rejects_other_keys()   // "ui.theme" ok ; "quality" → NotFound ; None efface
  ```
- [ ] **Step 2 :** → FAIL.
- [ ] **Step 3 : implémenter**, régénérer le pont, `flutter analyze`.
- [ ] **Step 4 :** dans `bridge_test.dart`, ajouter `homeFeed(cursor: null)`, qui rend une
  page dont la dernière étagère est `End` sur une base vide, et `browseCategories()`, qui
  rend `NoPlugin` sans plugin. Lancer le test d'intégration sur macOS, puis sur l'émulateur
  Android → `All tests passed!`.
- [ ] **Step 5 :** vérifications Rust → PASS.
- [ ] **Step 6 : commit**, `feat(core): API du fil d'accueil, mixes, réglage découvertes`.
