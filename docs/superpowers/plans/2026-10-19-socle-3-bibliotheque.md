# Socle 3 — Bibliothèque SQLite : plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** la bibliothèque locale commune aux trois domaines : identité générique `items`,
tables de détail musique, données utilisateur prêtes pour la synchro (UUIDv7, HLC, ordre
fractionnaire, suppression logique), stockages techniques, recherche floue locale.

**Architecture :** module `library` de la crate `vehicoule-core` (`core/core/`), créée ici ;
le plan 4 y ajoute le reste du cœur et la façade Dart. Une seule connexion rusqlite derrière
un `Mutex`, appelée depuis `spawn_blocking`. Les fonctions de la bibliothèque sont
synchrones et prennent `&Connection` (lecture) ou `&Tx` (écriture horodatée) ; elles ne
connaissent ni WIT ni les plugins : le plan 4 convertit.

**Tech Stack :** rusqlite 0.40 (`bundled`, `functions`), SQLite FTS5 (tokenizer `trigram`),
uuid 1.x (`v7`), strsim, unicode-normalization, serde_json, tokio.

**Spec :** `docs/superpowers/specs/2026-10-18-socle-musique-design.md` (v4), section 5 (et
3.1 file sauvegardée, 3.4 téléchargements, 4.3 cache HTTP, 4.4 feeds, 4.7 routage pour les
tables techniques). Rapport : constat 6 (recherche floue). Indépendant des plans 1 et 2.

## Global Constraints

- Dépôt `/Users/btw/Documents/repo/Vehicoule`, branche `socle-3-bibliotheque`. Licence
  MPL-2.0. Commit = `git commit -s -m "<msg>" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"`.
- Crate : dossier `core/core`, package **`vehicoule-core`**, lib `vehicoule_core` (le nom
  `core` est réservé par Rust). Ajoutée aux membres du workspace `core/Cargo.toml`.
- Migrations = fichiers SQL numérotés `core/core/migrations/NNNN_nom.sql`, version dans
  `PRAGMA user_version`. Une base plus récente que l'app est refusée, jamais modifiée.
- Pragmas à l'ouverture : `journal_mode=WAL`, `foreign_keys=ON`, `synchronous=NORMAL`,
  `busy_timeout=5000`.
- Identifiants **UUIDv7** partout, stockés en `BLOB` de 16 octets.
- Temps muraux en millisecondes Unix (`INTEGER`). `updated_at` = **HLC** 64 bits :
  48 bits de millisecondes, 16 bits de compteur ; égalités départagées par `device_id`.
- `kind` n'a **pas** de contrainte `CHECK` : ajouter `episode` ou `chapter` plus tard ne
  doit demander aucune migration des tables communes. Le contrôle est en Rust.
- Tables synchronisables (`items`, `likes`, `playlists`, `playlist_items`, `plays`,
  `settings_shared`) : colonnes `updated_at`, `device_id`, `deleted_at` ; on ne supprime
  jamais une ligne, on pose `deleted_at`.
- Ordre des playlists : clé fractionnaire base 62 (`0-9A-Za-z`, ordre ASCII), tri par
  `(order_key, id)`.
- `merged_into` pointe toujours vers une racine (jamais de chaîne) ; toute lecture suit ce
  lien.
- Recherche locale : FTS5 `tokenize = 'trigram remove_diacritics 1'` sur un texte déjà
  replié en Rust (minuscules, sans accents, ponctuation → espace) ; requêtes de moins de
  3 caractères = `LIKE` sur le texte replié ; classement final Jaro-Winkler.
- Plafonds : `search_history` **200** entrées, `http_cache` **64 Mio**.

## Review Focus

1. **Deux appareils insèrent au même endroit d'une playlist** et produisent la même clé
   d'ordre : l'ordre reste stable et total grâce au départage par `id`.
   → test `equal_order_keys_sort_by_id` (tâche 4).
2. **Le même titre arrive de Deezer puis d'iTunes** : un seul item si l'ISRC est identique,
   les likes et playlists ne voient pas de doublon. → test `same_isrc_reuses_item` (tâche 3).
3. **Fusion d'un item qui avait déjà des likes, des lectures et une place en playlist** :
   rien n'est perdu, les listes montrent l'item racine une seule fois.
   → test `merge_keeps_user_data_and_dedupes_likes` (tâche 3).
4. **Ouverture d'une base créée par une version plus récente de l'app** (retour arrière
   d'APK) : erreur claire, base intacte. → test `newer_database_is_refused` (tâche 1).
5. **Recherche avec fautes, accents, ponctuation ou titres non latins courts**
   (« beyonse », « edith », « ac dc », « 夜に ») → résultats attendus.
   → test `fuzzy_search_absorbs_typos_and_accents` (tâche 5).

---

### Task 1 : crate, ouverture, migrations, identifiants, horloge

**Files :**
- Create : `core/core/Cargo.toml`, `core/core/src/lib.rs`, `src/library/mod.rs`,
  `src/library/db.rs`, `src/library/ids.rs`, `src/library/hlc.rs`,
  `core/core/migrations/0001_init.sql`
- Modify : `core/Cargo.toml` (membre `core`, `rusqlite = { version = "0.40", features = ["bundled", "functions"] }`,
  `uuid = { version = "1", features = ["v7"] }` en dépendances de workspace)
- Test : modules `#[cfg(test)]` de `db.rs`, `hlc.rs`

**Interfaces :**
- Produces :
  ```rust
  #[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
  pub struct ItemId(pub uuid::Uuid);           // ToSql/FromSql en BLOB 16 o ; Display = forme à tirets
  impl ItemId { pub fn new() -> ItemId; }      // UUIDv7
  #[derive(Debug, Clone, Copy, PartialEq, Eq)]
  pub enum Kind { Track, Album, Artist, Playlist }   // as_str()/parse() : "track"…
  #[derive(Debug, Clone, Copy)]
  pub struct Stamp { pub updated_at: i64, pub device_id: uuid::Uuid }
  pub struct Hlc { last: u64 }
  impl Hlc { pub fn tick(&mut self, wall_ms: u64) -> u64; pub fn observe(&mut self, remote: u64, wall_ms: u64) -> u64; }
  #[derive(Debug, Clone, PartialEq)] pub enum DbError { Sqlite(String), Migration(String) }
  #[derive(Clone)] pub struct Db { /* Arc<Mutex<Inner { conn, hlc, device_id }>> */ }
  pub struct Tx<'a> { pub tx: rusqlite::Transaction<'a>, pub stamp: Stamp }
  impl Db {
      pub fn open(path: &Path) -> Result<Db, DbError>;
      pub fn open_in_memory() -> Result<Db, DbError>;
      pub fn device_id(&self) -> uuid::Uuid;
      pub async fn read<R: Send + 'static>(&self, f: impl FnOnce(&Connection) -> rusqlite::Result<R> + Send + 'static) -> Result<R, DbError>;
      pub async fn write<R: Send + 'static>(&self, f: impl FnOnce(&Tx) -> rusqlite::Result<R> + Send + 'static) -> Result<R, DbError>;
      pub fn read_blocking<R>(&self, f: impl FnOnce(&Connection) -> rusqlite::Result<R>) -> Result<R, DbError>;   // pour Storage (plan 4), appels courts
      pub fn write_blocking<R>(&self, f: impl FnOnce(&Tx) -> rusqlite::Result<R>) -> Result<R, DbError>;
  }
  pub struct Page { pub offset: u32, pub limit: u32 }
  ```

- [ ] **Step 1 : écrire `0001_init.sql`** (schéma complet, il fixe les décisions) :

```sql
-- ids: UUIDv7 BLOB(16). Wall times: unix ms. updated_at: HLC.
CREATE TABLE items (
  id BLOB PRIMARY KEY, kind TEXT NOT NULL, title TEXT NOT NULL,
  merged_into BLOB REFERENCES items(id),
  updated_at INTEGER NOT NULL, device_id BLOB NOT NULL, deleted_at INTEGER);
CREATE INDEX items_merged ON items(merged_into) WHERE merged_into IS NOT NULL;

CREATE TABLE music_tracks (item_id BLOB PRIMARY KEY REFERENCES items(id),
  album_id BLOB REFERENCES items(id), duration_ms INTEGER, isrc TEXT, explicit INTEGER NOT NULL DEFAULT 0);
CREATE INDEX music_tracks_isrc ON music_tracks(isrc) WHERE isrc IS NOT NULL;
CREATE TABLE music_track_artists (track_id BLOB NOT NULL REFERENCES items(id),
  artist_id BLOB NOT NULL REFERENCES items(id), position INTEGER NOT NULL, PRIMARY KEY (track_id, position));
CREATE TABLE music_albums (item_id BLOB PRIMARY KEY REFERENCES items(id), year INTEGER, track_count INTEGER);
CREATE TABLE music_album_artists (album_id BLOB NOT NULL REFERENCES items(id),
  artist_id BLOB NOT NULL REFERENCES items(id), position INTEGER NOT NULL, PRIMARY KEY (album_id, position));
CREATE TABLE music_album_tracks (album_id BLOB NOT NULL REFERENCES items(id),
  track_id BLOB NOT NULL REFERENCES items(id), position INTEGER NOT NULL, PRIMARY KEY (album_id, position));
CREATE TABLE music_artists (item_id BLOB PRIMARY KEY REFERENCES items(id));
-- Provider playlists (editorial cache). User playlists live in `playlists`.
CREATE TABLE music_playlists (item_id BLOB PRIMARY KEY REFERENCES items(id),
  owner TEXT, description TEXT, track_count INTEGER);
CREATE TABLE music_playlist_tracks (playlist_id BLOB NOT NULL REFERENCES items(id),
  track_id BLOB NOT NULL REFERENCES items(id), position INTEGER NOT NULL, PRIMARY KEY (playlist_id, position));
CREATE TABLE artwork (item_id BLOB NOT NULL REFERENCES items(id), provider TEXT NOT NULL,
  url TEXT NOT NULL, width INTEGER, PRIMARY KEY (item_id, provider, url));

CREATE TABLE external_refs (item_id BLOB NOT NULL REFERENCES items(id), provider TEXT NOT NULL,
  external_id TEXT NOT NULL, pinned INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (item_id, provider, external_id));
CREATE INDEX external_refs_lookup ON external_refs(provider, external_id);

CREATE TABLE likes (item_id BLOB PRIMARY KEY REFERENCES items(id), liked_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL, device_id BLOB NOT NULL, deleted_at INTEGER);
CREATE TABLE playlists (item_id BLOB PRIMARY KEY REFERENCES items(id), description TEXT,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, device_id BLOB NOT NULL, deleted_at INTEGER);
CREATE TABLE playlist_items (id BLOB PRIMARY KEY, playlist_id BLOB NOT NULL REFERENCES items(id),
  item_id BLOB NOT NULL REFERENCES items(id), order_key TEXT NOT NULL, added_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL, device_id BLOB NOT NULL, deleted_at INTEGER);
CREATE INDEX playlist_items_order ON playlist_items(playlist_id, order_key, id);
CREATE TABLE plays (id BLOB PRIMARY KEY, item_id BLOB NOT NULL REFERENCES items(id),
  started_at INTEGER NOT NULL, listened_ms INTEGER NOT NULL DEFAULT 0, source TEXT NOT NULL,
  updated_at INTEGER NOT NULL, device_id BLOB NOT NULL, deleted_at INTEGER);
CREATE INDEX plays_recent ON plays(started_at DESC);
CREATE TABLE downloads (item_id BLOB PRIMARY KEY REFERENCES items(id), state TEXT NOT NULL,
  path TEXT, quality TEXT NOT NULL, mime TEXT, loudness_db REAL, bytes_total INTEGER,
  bytes_done INTEGER NOT NULL DEFAULT 0, error TEXT, created_at INTEGER NOT NULL, finished_at INTEGER);
CREATE TABLE queue_state (id INTEGER PRIMARY KEY CHECK (id = 1), state TEXT NOT NULL);
CREATE TABLE lyrics (item_id BLOB PRIMARY KEY REFERENCES items(id), provider TEXT NOT NULL,
  plain TEXT, synced TEXT, fetched_at INTEGER NOT NULL);
CREATE TABLE plugin_kv (plugin_id TEXT NOT NULL, key TEXT NOT NULL, value BLOB NOT NULL, PRIMARY KEY (plugin_id, key));
CREATE TABLE search_history (query TEXT PRIMARY KEY, used_at INTEGER NOT NULL);
CREATE TABLE http_cache (key BLOB PRIMARY KEY, plugin_id TEXT NOT NULL, status INTEGER NOT NULL,
  url TEXT NOT NULL, headers TEXT NOT NULL, body BLOB NOT NULL, stored_at INTEGER NOT NULL, expires_at INTEGER NOT NULL);
CREATE TABLE settings_device (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE settings_shared (key TEXT PRIMARY KEY, value TEXT NOT NULL,
  updated_at INTEGER NOT NULL, device_id BLOB NOT NULL, deleted_at INTEGER);
CREATE TABLE feeds (url TEXT PRIMARY KEY, name TEXT NOT NULL, public_keys TEXT NOT NULL,
  official INTEGER NOT NULL, last_sequence INTEGER, fetched_at INTEGER, feed BLOB);
CREATE TABLE plugins (id TEXT PRIMARY KEY, feed_url TEXT NOT NULL REFERENCES feeds(url),
  version TEXT NOT NULL, manifest BLOB NOT NULL, wasm_sha256 TEXT NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1, installed_at INTEGER NOT NULL);
CREATE TABLE capability_order (capability TEXT NOT NULL, plugin_id TEXT NOT NULL,
  position INTEGER NOT NULL, PRIMARY KEY (capability, plugin_id));
CREATE VIRTUAL TABLE library_fts USING fts5(item_id UNINDEXED, title, subtitle,
  tokenize = 'trigram remove_diacritics 1');
```

- [ ] **Step 2 : tests qui échouent**

```rust
#[test] fn migrations_apply_once()            // open deux fois le même fichier : user_version == 1, aucune erreur
#[test] fn newer_database_is_refused()        // user_version = 99 → Err(Migration("database from a newer app version")), user_version toujours 99
#[test] fn pragmas_are_set()                  // journal_mode == "wal" (fichier), foreign_keys == 1
#[test] fn device_id_is_stable()              // deux ouvertures du même fichier → même device_id (UUIDv7)
#[test] fn hlc_is_monotonic_when_wall_clock_goes_back() // tick(1000), tick(900) → 2e > 1er
#[test] fn hlc_observe_jumps_past_remote()    // observe(remote = tick(5000) d'un autre) puis tick(1000) > remote
#[test] fn hlc_survives_restart()             // write sur fichier, réouverture, write : 2e stamp > 1er même si l'horloge recule
#[test] fn item_ids_are_v7_and_time_ordered()
```
- [ ] **Step 3 : vérifier l'échec** — `cargo test -p vehicoule-core library::` → FAIL.
- [ ] **Step 4 : implémenter.** `device_id` et `hlc_last` dans `settings_device` ; `write`
  ouvre une transaction, fait un seul `tick` (même `Stamp` pour toute la transaction),
  enregistre `hlc_last`, exécute `f`, valide. Commentaire
  `// ponytail: one connection behind a mutex; add a read connection if UI reads stall behind writes`.
- [ ] **Step 5 : vérifier** → PASS.
- [ ] **Step 6 : commit** — `feat(core): bibliothèque SQLite, migrations, UUIDv7, HLC`.

### Task 2 : clés d'ordre fractionnaires

**Files :**
- Create : `core/core/src/library/order.rs`
- Test : même fichier

**Interfaces :**
- Produces : `pub fn key_between(a: Option<&str>, b: Option<&str>) -> String;` — précondition
  `a < b` quand les deux sont présents (panique sinon, c'est un bug d'appelant).

- [ ] **Step 1 : tests qui échouent**

```rust
#[test] fn first_key_is_in_the_middle()        // key_between(None, None) == "V"
#[test] fn keys_sort_between_bounds()          // pour (None,"V"), ("V",None), ("V","W"), ("V","V1"), ("az","b") : a < k < b
#[test] fn never_ends_with_zero()              // aucune clé produite ne finit par '0'
#[test] fn thousand_prepends_stay_short()      // 1000 insertions en tête : ordre correct, longueur max ≤ 200
#[test] fn random_inserts_keep_order()         // 2000 insertions à des positions tirées par un LCG fixe : liste triée == ordre d'insertion voulu
```
- [ ] **Step 2 : vérifier l'échec** → FAIL.
- [ ] **Step 3 : implémenter** (algorithme du milieu de deux chaînes en base 62, sans
  partie entière ; une clé ne finit jamais par le plus petit chiffre, donc il existe
  toujours une clé entre deux clés).
- [ ] **Step 4 : vérifier** → PASS.
- [ ] **Step 5 : commit** — `feat(core): clés d'ordre fractionnaires`.

### Task 3 : catalogue, références externes, fusion

**Files :**
- Create : `core/core/src/library/catalog.rs`, `src/library/refs.rs`, `src/library/items.rs`,
  `src/library/fold.rs`
- Test : modules `#[cfg(test)]`

**Interfaces :**
- Produces :
  ```rust
  pub struct Image { pub url: String, pub width: Option<u32> }
  pub struct ArtistData { pub ext_id: Option<String>, pub name: String, pub artwork: Vec<Image> } // None : le fournisseur ne donne que le nom
  pub struct TrackData { pub ext_id: String, pub title: String, pub artists: Vec<ArtistData>,
                         pub album: Option<(Option<String>, String)>, // (ext_id, titre)
                         pub duration_ms: Option<u32>, pub isrc: Option<String>, pub explicit: bool,
                         pub artwork: Vec<Image> }
  pub struct AlbumData { pub ext_id: String, pub title: String, pub artists: Vec<ArtistData>,
                         pub year: Option<u16>, pub track_count: Option<u32>, pub artwork: Vec<Image> }
  pub struct PlaylistData { pub ext_id: String, pub title: String, pub owner: Option<String>,
                            pub description: Option<String>, pub track_count: Option<u32>, pub artwork: Vec<Image> }
  // catalog.rs — `provider` = id du plugin
  pub fn upsert_track(tx: &Tx, provider: &str, t: &TrackData) -> rusqlite::Result<ItemId>;
  pub fn upsert_album(tx: &Tx, provider: &str, a: &AlbumData) -> rusqlite::Result<ItemId>;
  pub fn upsert_artist(tx: &Tx, provider: &str, a: &ArtistData) -> rusqlite::Result<ItemId>;
  pub fn upsert_playlist(tx: &Tx, provider: &str, p: &PlaylistData) -> rusqlite::Result<ItemId>;
  pub fn set_children(tx: &Tx, parent: ItemId, tracks: &[ItemId], append: bool) -> rusqlite::Result<()>; // album ou playlist fournisseur
  pub struct TrackRow { pub id: ItemId, pub title: String, pub artists: Vec<(ItemId, String)>,
                        pub album: Option<(ItemId, String)>, pub duration_ms: Option<u32>, pub isrc: Option<String>,
                        pub explicit: bool, pub artwork: Vec<Image>, pub liked: bool, pub downloaded: bool }
  pub struct CollectionRow { pub id: ItemId, pub kind: Kind, pub title: String, pub subtitle: Option<String>,
                             pub artwork: Vec<Image>, pub track_count: Option<u32>, pub liked: bool }
  pub fn track(c: &Connection, id: ItemId) -> rusqlite::Result<Option<TrackRow>>;
  pub fn tracks(c: &Connection, ids: &[ItemId]) -> rusqlite::Result<Vec<TrackRow>>;       // ordre conservé
  pub fn collection(c: &Connection, id: ItemId) -> rusqlite::Result<Option<CollectionRow>>; // album, artiste, playlist
  pub fn children(c: &Connection, parent: ItemId, page: Page) -> rusqlite::Result<Vec<ItemId>>;
  // refs.rs
  pub struct ExtRef { pub external_id: String, pub pinned: bool }
  pub fn item_for(c: &Connection, provider: &str, external_id: &str) -> rusqlite::Result<Option<ItemId>>; // racine
  pub fn get(c: &Connection, item: ItemId, provider: &str) -> rusqlite::Result<Option<ExtRef>>;           // épinglée d'abord
  pub fn all(c: &Connection, item: ItemId) -> rusqlite::Result<Vec<(String, ExtRef)>>;
  pub fn record(tx: &Tx, item: ItemId, provider: &str, external_id: &str) -> rusqlite::Result<()>;        // non épinglée, ignorée si une épinglée existe
  pub fn pin(tx: &Tx, item: ItemId, provider: &str, external_id: &str) -> rusqlite::Result<ItemId>;      // renvoie la racine après fusion éventuelle
  // items.rs
  pub fn canonical(c: &Connection, id: ItemId) -> rusqlite::Result<ItemId>;
  pub fn merge(tx: &Tx, a: ItemId, b: ItemId) -> rusqlite::Result<ItemId>;  // le plus récent (UUIDv7) pointe vers le plus ancien ; renvoie la racine
  // fold.rs
  pub fn fold(s: &str) -> String;   // minuscules, accents latins retirés (NFD sans marques), ponctuation → espace, espaces compactés ; non-latin conservé
  ```
- Règles : un artiste ou un album sans `ext_id` est référencé par
  `(provider, "name:" + fold(nom))` (homonymes fusionnés chez ce seul fournisseur) ;
  `upsert_*` cherche d'abord `(provider, ext_id)`, puis pour un titre l'ISRC ;
  sinon crée l'item. Il met à jour titre, détails, pochettes du fournisseur et la ligne
  `library_fts` (`title` = `fold(titre)`, `subtitle` = `fold(artistes + album)`). `pin`
  supprime les autres références de `(item, provider)` ; si `external_id` est déjà
  **épinglé** sur un autre item du même `kind`, les deux sont fusionnés. `merge` réécrit
  aussi les `merged_into` qui visaient l'item fusionné, pour garder un seul saut.

- [ ] **Step 1 : tests qui échouent**

```rust
#[test] fn upsert_is_idempotent()                   // deux upsert_track du même (deezer, "123") → même ItemId, 1 ligne items
#[test] fn same_isrc_reuses_item()                  // deezer "1" puis itunes "9" même ISRC → même ItemId, 2 refs
#[test] fn track_row_carries_artists_album_artwork()
#[test] fn pinned_ref_wins_and_survives_auto_match() // record(ytmusic,"a") ; pin(ytmusic,"b") ; record(ytmusic,"c") → get == ("b", pinned)
#[test] fn pin_revealing_duplicate_merges()          // B épinglé sur "x" ; pin(A,"x") → racine = le plus ancien des deux ; canonical(plus récent) == racine
#[test] fn merge_keeps_user_data_and_dedupes_likes() // A liké + en playlist + 2 lectures, B liké ; merge → likes::list contient 1 item, la playlist montre la racine, plays comptés sur la racine
#[test] fn merge_never_chains()                      // merge(B→A) puis merge(A→Z plus ancien) → merged_into de B == Z
#[test] fn fold_normalizes()                         // fold("Édith  Piaf") == "edith piaf" ; fold("AC/DC") == "ac dc" ; fold("夜に駆ける") == "夜に駆ける"
```
- [ ] **Step 2 : vérifier l'échec** → FAIL.
- [ ] **Step 3 : implémenter.**
- [ ] **Step 4 : vérifier** → PASS.
- [ ] **Step 5 : commit** — `feat(core): catalogue, références externes, fusion d'items`.

### Task 4 : données utilisateur (likes, playlists, historique, file, téléchargements)

**Files :**
- Create : `core/core/src/library/{likes,playlists,plays,queue,downloads}.rs`
- Test : modules `#[cfg(test)]`

**Interfaces :**
- Consumes : `Tx`, `Stamp`, `ItemId`, `key_between`, `canonical`.
- Produces :
  ```rust
  // likes.rs
  pub fn set(tx: &Tx, item: ItemId, liked: bool) -> rusqlite::Result<()>;      // unlike = deleted_at
  pub fn is_liked(c: &Connection, item: ItemId) -> rusqlite::Result<bool>;
  pub fn list(c: &Connection, kind: Kind, page: Page) -> rusqlite::Result<Vec<ItemId>>; // racines distinctes, plus récent d'abord
  // playlists.rs
  #[derive(Clone, Copy)] pub struct EntryId(pub uuid::Uuid);
  pub enum Place { End, Start, After(EntryId) }
  pub fn create(tx: &Tx, title: &str, description: Option<&str>) -> rusqlite::Result<ItemId>;  // item kind playlist + ligne playlists
  pub fn rename(tx: &Tx, playlist: ItemId, title: &str) -> rusqlite::Result<()>;
  pub fn delete(tx: &Tx, playlist: ItemId) -> rusqlite::Result<()>;
  pub fn add(tx: &Tx, playlist: ItemId, items: &[ItemId], at: Place) -> rusqlite::Result<Vec<EntryId>>;
  pub fn move_entry(tx: &Tx, entry: EntryId, at: Place) -> rusqlite::Result<()>;
  pub fn remove_entry(tx: &Tx, entry: EntryId) -> rusqlite::Result<()>;
  pub fn entries(c: &Connection, playlist: ItemId, page: Page) -> rusqlite::Result<Vec<(EntryId, ItemId)>>; // items racines
  pub fn list(c: &Connection) -> rusqlite::Result<Vec<ItemId>>;                 // playlists perso non supprimées
  // plays.rs
  pub fn start(tx: &Tx, item: ItemId, source: &str) -> rusqlite::Result<uuid::Uuid>;
  pub fn set_listened(tx: &Tx, play: uuid::Uuid, listened_ms: u64) -> rusqlite::Result<()>;
  pub fn recent_items(c: &Connection, kind: Kind, page: Page) -> rusqlite::Result<Vec<ItemId>>; // distincts, par dernière écoute
  // queue.rs  (le type QueueState est défini au plan 4 ; ici du JSON)
  pub fn save(tx: &Tx, json: &str) -> rusqlite::Result<()>;
  pub fn load(c: &Connection) -> rusqlite::Result<Option<String>>;
  // downloads.rs
  pub enum DownloadState { Queued, Running, Done, Failed }
  pub struct DownloadRow { pub item: ItemId, pub state: DownloadState, pub path: Option<String>, pub quality: String,
                           pub mime: Option<String>, pub loudness_db: Option<f32>,
                           pub bytes_total: Option<u64>, pub bytes_done: u64, pub error: Option<String> }
  pub fn enqueue(tx: &Tx, item: ItemId, quality: &str) -> rusqlite::Result<()>;
  pub fn update(tx: &Tx, row: &DownloadRow) -> rusqlite::Result<()>;
  pub fn get(c: &Connection, item: ItemId) -> rusqlite::Result<Option<DownloadRow>>;
  pub fn list(c: &Connection, state: Option<DownloadState>) -> rusqlite::Result<Vec<DownloadRow>>;
  pub fn remove(tx: &Tx, item: ItemId) -> rusqlite::Result<Option<String>>;   // renvoie le chemin à effacer
  ```

- [ ] **Step 1 : tests qui échouent**

```rust
#[test] fn like_unlike_is_logical_delete()     // set(true), set(false) : ligne présente, deleted_at non nul, is_liked false ; set(true) la ranime
#[test] fn writes_carry_sync_columns()         // likes, playlists, playlist_items, plays : updated_at = stamp HLC, device_id = db.device_id()
#[test] fn playlist_add_and_move_keep_order()  // add [a,b,c] End ; move c After(a) → [a,c,b] ; add [d] Start → [d,a,c,b]
#[test] fn equal_order_keys_sort_by_id()       // deux lignes forcées avec la même order_key → ordre = ordre des id, stable entre lectures
#[test] fn move_next_to_equal_keys_does_not_panic() // add/move_entry prennent les voisins strictement ordonnés et valides (order::is_valid_key)
#[test] fn deleted_playlist_is_hidden()
#[test] fn recent_items_are_distinct()         // a, b, a → [a, b]
#[test] fn queue_roundtrip()                   // save puis load → même JSON ; une seule ligne
#[test] fn download_remove_returns_path()
```
- [ ] **Step 2 : vérifier l'échec** → FAIL.
- [ ] **Step 3 : implémenter.**
- [ ] **Step 4 : vérifier** → PASS.
- [ ] **Step 5 : commit** — `feat(core): likes, playlists, historique, file, téléchargements`.

### Task 5 : recherche floue locale et historique de recherche

**Files :**
- Create : `core/core/src/library/search.rs`
- Test : même fichier

**Interfaces :**
- Consumes : `fold` (tâche 3), table `library_fts`.
- Produces :
  ```rust
  pub struct LocalHit { pub item: ItemId, pub kind: Kind, pub score: f32 }
  /// Items in the user's library only: liked, in a user playlist, downloaded or played.
  pub fn local(c: &Connection, query: &str, limit: u32) -> rusqlite::Result<Vec<LocalHit>>;
  pub fn record_query(tx: &Tx, query: &str) -> rusqlite::Result<()>;          // garde les 200 plus récentes
  pub fn history(c: &Connection, prefix: &str, limit: u32) -> rusqlite::Result<Vec<String>>; // préfixe replié, plus récentes d'abord
  ```
- Algorithme (non déterminé par la signature) : `q = fold(query)` ; si `q` compte au moins
  3 caractères, `MATCH` = OU des trigrammes distincts de `q`, chacun entre guillemets,
  classés par `bm25`, 200 candidats ; sinon `fold`-LIKE `%q%` via une fonction SQL `fold`
  enregistrée sur la connexion. Filtre « dans la bibliothèque » par `EXISTS`, puis score =
  1.0 si le titre replié contient `q`, sinon `strsim::jaro_winkler(q, titre replié)` ; tri
  décroissant, `limit`.

- [ ] **Step 1 : tests qui échouent**

```rust
#[test] fn fuzzy_search_absorbs_typos_and_accents() // likés : "Beyoncé - Halo", "Édith Piaf - Hymne", "AC/DC - T.N.T.", "YOASOBI - 夜に駆ける" ; "beyonse" → Halo 1er ; "edith" → Hymne ; "ac dc" → T.N.T. ; "夜に" → 夜に駆ける
#[test] fn search_is_limited_to_the_library()       // titre seulement en cache catalogue → absent
#[test] fn exact_substring_ranks_first()            // "halo" : "Halo" avant "Hallo Hallo"
#[test] fn fts_operators_are_inert()                // requêtes "AND", "\"", "a*", "NEAR(" → Ok, pas d'erreur SQL
#[test] fn history_keeps_200_most_recent()
```
- [ ] **Step 2 : vérifier l'échec** → FAIL.
- [ ] **Step 3 : implémenter.**
- [ ] **Step 4 : vérifier** → PASS.
- [ ] **Step 5 : commit** — `feat(core): recherche floue locale (FTS5 trigram)`.

### Task 6 : stockages techniques (paroles, kv, cache HTTP, réglages, plugins)

**Files :**
- Create : `core/core/src/library/{lyrics,kv,http_cache,settings,plugins}.rs`
- Test : modules `#[cfg(test)]`

**Interfaces :**
- Produces :
  ```rust
  // lyrics.rs
  pub struct LyricsRow { pub provider: String, pub plain: Option<String>, pub synced: Vec<(u32, String)> } // synced en JSON [[ms,"…"],…]
  pub fn get(c: &Connection, item: ItemId) -> rusqlite::Result<Option<LyricsRow>>;
  pub fn put(tx: &Tx, item: ItemId, row: &LyricsRow) -> rusqlite::Result<()>;
  // kv.rs
  pub fn get(c: &Connection, plugin: &str, key: &str) -> rusqlite::Result<Option<Vec<u8>>>;
  pub fn set(tx: &Tx, plugin: &str, key: &str, value: &[u8]) -> rusqlite::Result<()>;
  pub fn delete(tx: &Tx, plugin: &str, key: &str) -> rusqlite::Result<()>;
  pub fn usage(c: &Connection, plugin: &str) -> rusqlite::Result<u64>;
  // http_cache.rs
  pub struct CacheRow { pub plugin: String, pub status: u16, pub url: String, pub headers: Vec<(String, String)>,
                        pub body: Vec<u8>, pub stored_at: i64, pub expires_at: i64 }
  pub fn get(c: &Connection, key: &[u8; 32]) -> rusqlite::Result<Option<CacheRow>>;
  pub fn put(tx: &Tx, key: &[u8; 32], row: &CacheRow) -> rusqlite::Result<()>;   // puis élagage à 64 Mio : expirées d'abord, puis plus anciennes
  // settings.rs
  pub fn device_get(c: &Connection, key: &str) -> rusqlite::Result<Option<String>>;
  pub fn device_set(tx: &Tx, key: &str, value: &str) -> rusqlite::Result<()>;
  pub fn shared_get(c: &Connection, key: &str) -> rusqlite::Result<Option<String>>;
  pub fn shared_set(tx: &Tx, key: &str, value: &str) -> rusqlite::Result<()>;     // colonnes de synchro
  // plugins.rs
  pub struct FeedRow { pub url: String, pub name: String, pub public_keys: Vec<[u8; 32]>, pub official: bool,
                       pub last_sequence: Option<u64>, pub fetched_at: Option<i64>, pub feed: Option<Vec<u8>> }
  pub struct PluginRow { pub id: String, pub feed_url: String, pub version: String, pub manifest: Vec<u8>,
                         pub wasm_sha256: String, pub enabled: bool }
  pub fn feeds(c: &Connection) -> rusqlite::Result<Vec<FeedRow>>;
  pub fn put_feed(tx: &Tx, f: &FeedRow) -> rusqlite::Result<()>;
  pub fn remove_feed(tx: &Tx, url: &str) -> rusqlite::Result<()>;                 // retire aussi ses plugins
  pub fn plugins(c: &Connection) -> rusqlite::Result<Vec<PluginRow>>;
  pub fn put_plugin(tx: &Tx, p: &PluginRow) -> rusqlite::Result<()>;
  pub fn capability_order(c: &Connection, capability: &str) -> rusqlite::Result<Vec<String>>;
  pub fn set_capability_order(tx: &Tx, capability: &str, plugin_ids: &[String]) -> rusqlite::Result<()>;
  ```

- [ ] **Step 1 : tests qui échouent**

```rust
#[test] fn lyrics_roundtrip_keeps_synced_lines()
#[test] fn kv_usage_counts_keys_and_values()
#[test] fn http_cache_is_pruned_to_64_mib()     // 70 entrées de 1 Mio → total ≤ 64 Mio, les plus anciennes parties
#[test] fn shared_settings_carry_sync_columns()
#[test] fn removing_a_feed_removes_its_plugins()
#[test] fn capability_order_roundtrip()
```
- [ ] **Step 2 : vérifier l'échec** → FAIL.
- [ ] **Step 3 : implémenter.**
- [ ] **Step 4 : vérifier** — `cargo test -p vehicoule-core` → PASS ; clippy `-D warnings` → OK.
- [ ] **Step 5 : commit** — `feat(core): paroles, kv, cache HTTP, réglages, plugins installés`.
