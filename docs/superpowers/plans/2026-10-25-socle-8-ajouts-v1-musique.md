# Socle 8 — Ajouts v1 musique de l'addendum et surface d'attaque : plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** tout ce que l'addendum §12 range dans la v1 musique et que le plan 5 ne prend pas
(⌘K, résumé quotidien, « Ton année », « Pour le trajet » et budget de stockage, liens collés,
liens de partage, sauvegarde, mode économie, lecture sur la TV, M1, M3, « C'est quoi ? »,
`item_relations`, accueil commun, minuterie d'app), plus le reste de la surface d'attaque
(FFmpeg et libmpv réduits, rustls + aws-lc-rs seul, `material_3_expressive` dans le dépôt).

**Architecture :** comme les plans 4 à 7 : Rust décide, Dart affiche et exécute. Chaque ajout
commence dans le cœur (`core/core/src/<module>.rs`, API dans `core/core/src/api/`, pont
régénéré), puis son écran. Les écrans communs à tous les domaines vont dans
`app/lib/features/app/`, ceux de la musique dans `app/lib/features/music/`. Le travail en
arrière-plan sur Android passe par WorkManager et une entrée JNI du cœur, sans moteur Flutter
sans interface. Le site `vehicoule.com` (page statique et Worker Rust) vit dans `web/`, hors du
workspace `core/`.

**Tech Stack :** celles des plans 4 à 7 (Rust 2024, Wasmtime 48.0.6, flutter_rust_bridge
2.13.0, Flutter 3.47.2, go_router 18.1.1, media_kit 1.2.6). Nouvelles dépendances, chacune
justifiée dans sa tâche : `flate2` (moteur `miniz_oxide`), `chacha20poly1305`, `argon2`,
`roxmltree`, `symphonia`, `lindera` (dictionnaire IPADIC embarqué), `pinyin`, `worker`
(workers-rs) ; Android `androidx.work:work-runtime-ktx` ; Dart `flutter_secure_storage` ;
plugins `rusty-chromaprint`.

**Spec :** `docs/superpowers/specs/2026-10-25-navigation-domaines.md` (l'« addendum ») §3,
§3.1, §4, §5.1, §5.4, §6, §6 bis, §7, §7 bis, §8, §9, §9 bis, §12, §13 (M1, M3) ;
`docs/superpowers/specs/2026-10-25-surface-attaque.md` (la « surface ») §2 (exception TV),
§3, §5, §7, §8 ; `docs/superpowers/specs/2026-10-25-anime-design.md` §4.5 (Boa à la place de
QuickJS, seulement pour le socle) ; specs de base `2026-10-18-socle-musique-design.md` et
`2026-10-23-socle-ui-design.md`.

Prérequis : plan 5 terminé (dont 5r : identifiant `com.vehicoule`, domaine `vehicoule.com` ;
5c : proxy média ; Task 8 : CI). Le plan 6 Task 7 et la validation finale (plan 5 Task 9)
viennent après ce plan.

**Espace du plan :** `.superpowers/sdd/2026-10-25-socle-8-ajouts-v1-musique/` (ledger
`progress.md`, rapports, captures).

## Global Constraints

- **Dépôts :** `/Users/btw/Documents/repo/Vehicoule-socle`, branche `socle` (app, cœur, contrat,
  SDK, `web/`) ; `/Users/btw/Documents/repo/vehicoule-plugins`, branche `socle-plugins`
  (plugins officiels : `mymemory`, `acoustid`). Commit =
  `git commit -s -m "<msg>" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"`.
  Jamais de `stash`, de `reset` ni de changement de branche (copies partagées).
- **Rien ne se publie dans une tâche.** Ni Cloudflare, ni feed, ni release, ni DNS : les
  tâches produisent le code et la configuration ; chaque mise en ligne est une étape
  **(utilisateur)**, consignée au ledger dans « Pending user confirmation ». Ne jamais lancer
  `publish.sh`, ne jamais lire ni copier `~/.config/vehicoule/feed-keys/`.
- Ordre d'exécution : 1 à 20, dans l'ordre. Chaque sous-agent tourne en opus, effort high.
- **Identité :** `com.vehicoule` (Android, bundle, préfixe des canaux de plateforme
  `com.vehicoule/<nom>`), `https://vehicoule.com`. Liens internes `vehicoule://<route>`.
- **Domaines :** `Domain` (Rust, pont) et `Domain` (Dart, `app/lib/domains.dart`, plan 5) ne
  valent que `music` en v1. Tout ce qui est « par domaine » (réglages, cartes Reprendre,
  résumé, « Pour le trajet ») est indexé par ce nom interne.
- **Nouvelle dépendance** (surface §7.2) : sa justification en commentaire au-dessus de la
  ligne qui l'ajoute (ce qu'elle fait, pourquoi le stdlib ou une dépendance présente ne suffit
  pas, son langage, son mainteneur). Rust : version figée `=x.y.z`, la dernière stable au
  début de la tâche ; Dart : version sans `^`. Aucune nouvelle dépendance en C ou C++ exposée
  au contenu tiers (aucune n'est prévue ici).
- **Cœur sans texte :** le cœur rend des nombres, des genres et des noms ; Dart (ARB FR/EN,
  `docs/voice.md`), Kotlin (`strings.xml`) et Swift (`Localizable.strings`) écrivent les
  phrases.
- **Réglages** (`settings_device` sauf mention ; booléens actifs sauf `"false"`) :

  | Clé | Valeurs | Défaut | Tâche |
  |---|---|---|---|
  | `economy` | `auto`, `always`, `never` | `auto` | 11 |
  | `downloads_budget` | octets, ou `0` = sans limite | 5 GiB | 12 |
  | `commute.music` | booléen | actif | 12 |
  | `summary.music` | booléen | actif | 13 |
  | `backup.every` | `day`, `week`, `never` | `week` | 6 |
  | `sound.<sortie>` | JSON `SoundProfile` | plat, normalisation active | 18 |
  | `ui.home_filter`, `ui.lyrics.romanize`, `ui.lyrics.translate`, `ui.backup.folder` | préférences d'interface | — | 4, 15, 7 |

- **Migrations** (`core/core/migrations/`, ajoutées à la liste de `library/db.rs`) :
  `0003_item_relations.sql` (Task 6), `0004_download_origin.sql` (Task 12),
  `0005_recognized.sql` (Task 16).
- **Contrat :** `vehicoule:music` passe à **1.2.0** (Task 14) ; `vehicoule:host` reste à
  **1.0.0** (sa 1.1.0 appartient à la spec anime). Manifestes acceptés : `1.0`, `1.1`, `1.2`.
- **Vie privée :** « Ton année », l'ordre des cartes et le résumé se calculent en local. Ne
  sortent de l'appareil que : la liste d'une playlist partagée (geste de l'utilisateur, avec la
  phrase de la feuille), l'empreinte sonore et les paroles à traduire (par un plugin, dans
  son bac à sable). Aucun identifiant d'utilisateur ou d'appareil dans un lien.
- **TDD :** le Step 1 de chaque tâche écrit les tests nommés puis les lance : ils échouent
  (FAIL, pas une erreur de compilation ailleurs) avant toute implémentation ; le rapport
  montre cette sortie.
- **Vérifications de chaque tâche** (les « vérifications globales ») :
  - Rust : `cargo test` des crates touchées, deux fois ; `cargo clippy --workspace
    --all-targets -- -D warnings` ; `cargo fmt --check` ;
  - pont : tout changement d'API régénère le pont (`flutter_rust_bridge_codegen generate`)
    et étend `app/lib/debug/fake_api.dart` ;
  - Dart : `cd app && flutter test` puis `flutter analyze` ; les gardes du plan 5
    (`imports_test`, `spacing_test`, `guards_test`, `l10n_test`) restent verts ;
  - le rapport se termine par la fin de ces sorties ; un écran nouveau a ses captures à
    taille réelle (412 × 892 et 1280 × 800 dp) dans l'espace du plan.
- **Rulings du plan** (choix que les specs laissaient ouverts ou qui se contredisaient) :
  - R1 Boa : rien à construire ; le plan B YouTube (socle §4.5) reste non construit en v1,
    son texte passe de QuickJS à Boa et `cargo deny` bannit les moteurs JS en C (Task 1).
  - R2 `ring` : `cargo tree -i ring` est déjà vide (mesuré le 2026-10-25) mais
    `core/Cargo.lock` liste encore `ring` ; la CI vérifie donc aussi le lockfile (Task 1).
  - R3 FFmpeg réduit pour les deux plateformes v1 (Android arm64, macOS) ; iOS, Windows et
    Linux, compilés seulement, gardent les bibliothèques de media_kit (Task 2).
  - R4 L'accueil devient commun : `home_page.dart` passe dans `features/app/home/` ; les
    étagères musique restent dans `features/music/home/` (Task 4).
  - R5 Liens universels macOS : l'entitlement `associated-domains` exige une équipe Apple
    payante (le mur qui a écarté ShazamKit) ; le fichier `apple-app-site-association` est
    livré (Task 8), l'entitlement attend l'équipe (« Pending user confirmation »), et
    `vehicoule://` (bouton de la page) couvre macOS d'ici là, comme l'addendum §3.1 le
    prévoit pour une app non notarisée (Task 5).
  - R6 Aperçu de la page de partage : demandé au catalogue depuis le navigateur ; si le
    catalogue refuse CORS, la page montre une carte générique, sans passer par un service
    (Task 8).
  - R7 Débit plafonné par IP pour `/p/` : une règle « rate limiting » de Cloudflare (une
    gratuite), dans la configuration de déploiement, pas dans le Worker (Task 8).
  - R8 Sauvegarde automatique : faite pendant que l'app tourne (au lancement, puis chaque
    heure si elle est due), sans tâche de fond ; la phrase de passe vit dans le trousseau du
    système (Task 7).
  - R9 Restaurer fusionne aussi les tables non synchronisées (catalogue, `external_refs`)
    sans écraser ; `queue_state`, `downloads`, caches et `plugin_kv` ne sont pas sauvegardés
    (Task 6).
  - R10 Budget : on retire d'abord les titres de « Pour le trajet » (le plus ancien d'abord),
    puis les téléchargements de l'utilisateur déjà écoutés (dernière écoute la plus ancienne
    d'abord) ; jamais un titre non écouté de l'utilisateur, le titre en cours ni un titre de
    la file (Task 12).
  - R11 Arrière-plan Android : WorkManager appelle le cœur par JNI ; le cœur relit la
    configuration que l'app a écrite à son dernier lancement (`app_config.json`) (Task 12).
  - R12 Résumé quotidien : la musique n'a que « chaque jour » ou « jamais » ; ses sorties
    sont relevées une fois par jour, donc « immédiat » ne changerait rien (Task 13).
  - R13 Traduction des paroles : capacité `translate` du contrat 1.2, servie par un plugin
    officiel `mymemory` (API publique sans clé) ; aucun traducteur n'existe en Rust pur ni
    dans les OS sans SDK fermé (ML Kit) (Task 15).
  - R14 Romanisation : japonais (lindera + IPADIC, puis Hepburn), coréen (romanisation
    révisée, calculée), chinois (pinyin) (Task 15).
  - R15 « C'est quoi ? » : extrait mono 16 kHz, 12 s au plus ; tous les plugins `identify`
    sont appelés en parallèle, le meilleur score ≥ 0,5 gagne (Task 16).
  - R16 Son partagé vers l'app : `ACTION_SEND` `audio/*` sur Android ; sur macOS, déposer
    le fichier sur le dialogue (pas d'extension de partage) (Task 17).
  - R17 Son de l'ordinateur : tap Core Audio (macOS 14.2 et plus), option masquée avant ;
    Windows et Linux, micro seulement (Task 17).
  - R18 DLNA écrit à la main (SSDP + SOAP, XML lu par `roxmltree`) ; pas de transcodage :
    un format que la TV refuse est dit avant de lancer (Task 19).
  - R19 AirPlay : `AVRoutePickerView` (le sélecteur du système), mpv sur
    `audio-device=auto` (Task 20).
  - R20 M3 : 5 bandes (60, 230, 910, 3 600, 14 000 Hz, ±12 dB) et la normalisation, par
    sortie ; la clé d'une sortie est son genre et son nom (Task 18).

## Review Focus

1. **Restaurer une sauvegarde sur un appareil déjà utilisé** : ce qui a changé depuis sur
   l'appareil reste ; rien de récent ne se perd. → test `restore_keeps_newer_local_rows`
   (Task 6).
2. **Mauvaise phrase de passe, fichier tronqué ou d'une autre app** : un résultat typé, la
   base intacte à l'octet près. → test `restore_refuses_bad_files_and_changes_nothing`
   (Task 6).
3. **Budget de stockage dépassé pendant l'écoute** : le titre en cours, ceux de la file et
   les téléchargements non écoutés de l'utilisateur ne partent jamais. → test
   `eviction_spares_current_queued_and_unplayed` (Task 12).
4. **La TV disparaît en pleine lecture** (éteinte, Wi-Fi coupé) : la lecture revient sur
   l'appareil, en pause à la dernière position connue, et l'écoute réseau du proxy se ferme.
   → test `tv_lost_falls_back_paused_and_closes_lan_listener` (Task 19).
5. **Un texte collé qui ressemble à un lien mais qu'aucune source ne reconnaît** : la
   recherche part normalement sur le texte, sans message d'erreur. → test
   `unrecognised link falls back to search` (Task 5).

---

### Task 1 : dépendances — un seul fournisseur cryptographique, bans, `material_3_expressive` dans le dépôt

**Files :**
- Modify : `core/core/Cargo.toml`, `core/plugin-host/Cargo.toml`, `core/stream/Cargo.toml`
  (options de `sentry`, `reqwest`, `rustls`, `rustls-platform-verifier` choisies pour
  aws-lc-rs seul), `core/Cargo.lock`, `core/deny.toml` (bans), `.github/workflows/ci.yml`
  (job dépendances du plan 5 Task 8).
- Create : `third_party/material_3_expressive/` (copie exacte du paquet 1.2.0 de pub.dev,
  `LICENSE` compris) et `third_party/material_3_expressive/VENDORED` (une ligne : nom,
  version, source, sha256 de l'archive).
- Modify : `app/pubspec.yaml` (`material_3_expressive: { path: ../third_party/material_3_expressive }`),
  `app/pubspec.lock`, `app/test/design/imports_test.dart`.
- Modify : `docs/superpowers/specs/2026-10-18-socle-musique-design.md` §4.5 (« interface
  hôte `js` (Boa natif, moteur JS écrit en Rust) », d'après la spec anime §4.5).

**Interfaces :**
- Produces : `core/deny.toml` `[bans] deny = [ring, openssl, openssl-sys, rquickjs,
  rquickjs-sys, quick-js, libquickjs-sys, v8]` ; la CI vérifie
  `! grep -qx 'name = "ring"' core/Cargo.lock`.

- [ ] **Step 1 : tests qui échouent**
  ```bash
  cd core && ! grep -qx 'name = "ring"' Cargo.lock      # FAIL aujourd'hui
  cd core && cargo deny check bans                       # FAIL une fois ring banni
  ```
  ```dart
  test('material_3_expressive comes from third_party', ...); // pubspec.lock : source "path", path ../third_party/material_3_expressive ; VENDORED dit 1.2.0
  ```
- [ ] **Step 2 : retirer `ring`.** `cargo tree -e features -i ring --target all` (en ligne)
  nomme les options qui l'activent ; ne garder que celles qui passent par aws-lc-rs.
  `cargo update -p ring` ne suffit pas : le lockfile doit le perdre.
- [ ] **Step 3 : copier `material_3_expressive` 1.2.0** depuis le cache pub (sha256 de
  l'archive noté dans `VENDORED`) ; la dépendance de `app/pubspec.yaml` pointe sur ce
  chemin (pas de `dependency_overrides`).
- [ ] **Step 4 : amender le socle §4.5** (QuickJS → Boa, une phrase).
- [ ] **Step 5 : vérifier** : les deux commandes du Step 1 passent ; vérifications globales ;
  l'app en debug sur macOS joue un titre réel (TLS par aws-lc-rs).
- [ ] **Step 6 : commit** : `chore(deps): rustls avec aws-lc-rs seul, ring et moteurs JS en C bannis, material_3_expressive dans third_party`.

### Task 2 : libmpv et FFmpeg réduits (recette dans le dépôt)

Surface §3. Liste blanche, LGPL, sans TLS (le proxy du plan 5 Task 5c parle en `http` à
`127.0.0.1`). Les filtres audio dont M3 (Task 18) a besoin sont dans la liste.

**Files :**
- Create :
  - `third_party/libmpv/versions.env` (FFmpeg, mpv, et libass pour le profil vidéo : version
    et sha256 de chaque archive source) ;
  - `third_party/libmpv/ffmpeg-components.txt` (la liste blanche, seule source) :
    - conteneurs (démultiplexeurs) : `hls`, `mpegts`, `mov` (MP4, fMP4), `matroska` (et WebM),
      `ogg`, `mp3`, `flac`, `wav`, `aac` ;
    - audio : `aac`, `mp3float`, `flac`, `opus`, `vorbis` ;
    - vidéo (profil `video` seulement) : `h264`, `hevc`, `av1`, `vp9` ;
    - décodeurs natifs de FFmpeg seulement (ni libopus, ni libdav1d, ni autre bibliothèque C) ;
    - sous-titres (profil `video`) : `ass`, `ssa`, `srt`, `subrip`, `webvtt` ;
    - protocoles : `http`, `tcp`, `crypto` ;
    - filtres : `equalizer`, `volume`, `aformat`, `aresample`, `anull`, `abuffer`,
      `abuffersink` ;
    - parseurs et bitstream filters exigés par ces décodeurs, rien d'autre ;
  - `third_party/libmpv/build.sh <android-arm64|macos> <audio|video>` : FFmpeg en
    `--disable-everything --disable-network-tls --disable-gpl --disable-nonfree` puis les
    `--enable-*` de la liste, puis libmpv ; sortie dans `third_party/libmpv/dist/<cible>/`
    (ignoré par git, mis en cache par la CI sur le hash de `versions.env` et de la liste) ;
  - `third_party/libmpv/check.sh <cible>` : compare l'ensemble activé
    (`libavformat/demuxer_list.c`, `libavcodec/codec_list.c`, `libavformat/protocol_list.c`,
    `libavfilter/filter_list.c` du build) à la liste blanche, à l'élément près ;
  - `third_party/libmpv/fixtures/` (sons de test générés une fois par `fixtures.sh` avec un
    ffmpeg du système : une seconde de sinus par conteneur et codec de la liste audio, plus
    une playlist HLS de deux segments ; aucune œuvre protégée) ;
  - `third_party/media_kit_libs_android_audio/`, `third_party/media_kit_libs_macos_audio/` :
    copies des paquets de la version utilisée, dont l'étape de téléchargement est remplacée
    par les binaires de `third_party/libmpv/dist/` ;
  - `app/integration_test/formats_test.dart`.
- Modify : `app/pubspec.yaml` (`dependency_overrides` vers ces deux copies), `.github/workflows/ci.yml`
  (étape de build mise en cache avant les jobs Android et macOS), `.gitignore`.

**Interfaces :**
- Produces : `third_party/libmpv/build.sh` ; les bibliothèques de lecture des builds Android
  et macOS viennent de lui. Le profil `video` sert à l'étape 1 de l'anime (mesure de taille).

- [ ] **Step 1 : tests qui échouent**
  ```bash
  third_party/libmpv/check.sh macos          # FAIL : pas encore de build
  ```
  ```dart
  // formats_test.dart (macOS, vrai mpv avec les options du plan 5 Task 5c ; fixtures servies sur 127.0.0.1 par un HttpServer du test)
  testWidgets('every whitelisted format plays', ...);         // chaque fixture : position > 0, aucune erreur
  testWidgets('the equalizer filter is available', ...);      // af=lavfi=[equalizer=f=60:t=o:w=1.5:g=6] accepté, le son continue
  testWidgets('https is refused by the reduced build', ...);  // une URL https directe → erreur (pas de TLS dans FFmpeg)
  ```
- [ ] **Step 2 : écrire la recette** et construire `macos audio` puis `android-arm64 audio`.
  La licence reste LGPL : `check.sh` vérifie aussi `--disable-gpl` dans `config.h`.
- [ ] **Step 3 : brancher** les deux copies de paquets ; `flutter build apk --debug` et
  `flutter build macos --debug`.
- [ ] **Step 4 : vérifier** : `check.sh` passe pour les deux cibles ; `formats_test` sur
  macOS ; sur l'émulateur Android, un titre réel joue (feed de dev). Noter au rapport la
  taille de `libmpv` et des bibliothèques FFmpeg avant et après, par cible. Construire aussi
  `macos video` une fois, pour prouver le profil, et noter sa taille.
- [ ] **Step 5 : commit** : `build(media): libmpv et FFmpeg réduits à une liste blanche (recette, vérification, profils audio et vidéo)`.

### Task 3 : minuterie d'app

Addendum §5.1 : la minuterie arrête **toutes** les sessions, avec le même fondu. En v1 il n'y
a que la musique, mais la minuterie quitte l'acteur du lecteur pour un module d'app ; la
spec anime y ajoute la vidéo.

**Files :**
- Create : `core/core/src/timer.rs`.
- Modify : `core/core/src/player.rs` (la minuterie en minutes en sort ; « fin du titre »
  reste dans l'acteur, elle est propre à la musique), `core/core/src/api/playback.rs`
  (`set_sleep_timer` délègue), `core/core/src/lib.rs`.
- Test : `#[cfg(test)]` de `timer.rs`, `core/core/src/player/tests.rs`.

**Interfaces :**
- Consumes : `PlayerCommand::Pause { fade_ms }`, `SleepTimer`, `SleepState`,
  `NowPlaying.sleep` (plan 7 Task 8).
- Produces :
  ```rust
  // timer.rs
  pub(crate) async fn set(timer: SleepTimer);   // Minutes(n) : une échéance d'app ; EndOfTrack : transmis au lecteur musique ; Off : annule les deux
  pub(crate) fn state() -> Option<SleepState>;  // ce que NowPlaying.sleep publie
  // player.rs : la pause en fondu de la session musique, que la minuterie appelle à l'échéance
  pub(crate) async fn fade_pause(fade_ms: u32); // envoie PlayerCommand::Pause { fade_ms } si la musique joue
  ```
  L'API du pont ne change pas (`set_sleep_timer(timer: SleepTimer)`).

- [ ] **Step 1 : tests qui échouent**
  ```rust
  #[tokio::test(start_paused = true)] async fn app_timer_pauses_every_session()   // échéance → Pause { fade_ms: 5000 } envoyé ; NowPlaying.sleep efface
  #[tokio::test(start_paused = true)] async fn app_timer_survives_a_new_queue()   // play() d'une autre file : la minuterie continue (elle n'est plus celle de la file)
  #[tokio::test] async fn end_of_track_stays_in_the_music_player()
  ```
- [ ] **Step 2 : implémenter**, déplacer les tests de minuterie existants de
  `player/tests.rs` vers `timer.rs` quand ils portent sur les minutes.
- [ ] **Step 3 : vérifier** (vérifications globales).
- [ ] **Step 4 : commit** : `refactor(core): minuterie de sommeil d'app, qui vise toutes les sessions`.

### Task 4 : accueil commun (`ShelfView.domain`, étagère Reprendre, filtre par domaine)

Addendum §4 et §12 (plan 7). En v1, l'accueil est celui de la spec UI §6.1 plus la carte
Reprendre de la file musique en tête.

**Files :**
- Modify : `core/core/src/api/library.rs` (`Domain`, `ShelfView.domain`,
  `ShelfKindView::Resume`, `home_feed(cursor, filter)`), `core/core/src/home/{mod,assemble}.rs`,
  le pont, `fake_api.dart`.
- Move : `app/lib/features/music/home/home_page.dart` → `app/lib/features/app/home/home_page.dart`
  (R4) ; `discovery_hero.dart` et `feed_shelf.dart` restent sous `features/music/home/`.
- Create : `app/lib/features/app/home/resume_tile.dart`.
- Modify : `app/lib/router.dart` (import).
- Test : `core/core/src/home/` (tests du module), `app/test/features/home_test.dart`.

**Interfaces :**
- Consumes : `queue_states` / l'état de file sauvegardé (`library::queue`), `PlayContext`,
  `TrackView`, `CardView`.
- Produces :
  ```rust
  pub enum Domain { Music }                                   // api/library.rs ; anime et books s'ajoutent avec leurs specs
  pub struct ShelfView { pub kind: ShelfKindView, pub domain: Domain, pub seed: Option<String>, pub items: Vec<CardView> }
  ShelfKindView::Resume                                       // une carte par domaine en cours ; musique : CardView::Track { track: titre courant de la file sauvegardée, reason: Some(titre du contexte) }
  pub async fn home_feed(cursor: Option<String>, filter: Option<Domain>) -> Result<HomeFeedPage, CoreError>;
  ```
  ```dart
  class ResumeTile extends StatelessWidget { const ResumeTile({required CardView card, required Domain domain}); }
      // forme du domaine (addendum §8 : VDecorShape.cookie pour la musique) ; toucher → queueOp(jumpTo(currentEntry)) puis lecture ;
      // à ne pas confondre avec ResumeCard (platform/resume.dart, plan 5 Task 10 : les données du widget, des raccourcis et du Dock)
  ```
- Règles :
  - `Resume` est une étagère **locale**, lue au service comme `Shortcuts` (la file change
    sans reconstruire le fil), toujours la première de la page 1 quand la file sauvegardée a
    une entrée courante ; absente sinon ;
  - le fil entrelace les domaines (un seul en v1) ; `filter: Some(d)` ne garde que les
    étagères de `d` ; `ui.home_filter` retient le choix ; la rangée de puces reste masquée
    avec un seul domaine (plan 5 Task 5) ;
  - l'ordre appris des cartes Reprendre (addendum §4.2) n'a rien à trier avec une carte :
    il arrive avec l'anime (addendum §11).

- [ ] **Step 1 : tests qui échouent**
  ```rust
  #[tokio::test] async fn resume_is_first_on_page_one_when_a_queue_is_saved()
  #[tokio::test] async fn no_resume_without_a_current_entry()
  #[tokio::test] async fn every_shelf_carries_its_domain()
  #[tokio::test] async fn filter_keeps_only_that_domain()
  ```
  ```dart
  testWidgets('home shows the resume card first, with the music shape', ...);
  testWidgets('resume card resumes the saved queue', ...);   // queueOp(QueueOp.jumpTo(currentEntry))
  ```
- [ ] **Step 2 : implémenter le cœur**, régénérer le pont, étendre `FakeApi`.
- [ ] **Step 3 : déplacer `home_page.dart`** et ajouter la carte.
- [ ] **Step 4 : vérifier** (vérifications globales) ; captures de l'accueil avec la carte.
- [ ] **Step 5 : commit** : `feat: accueil commun (domaine des étagères, carte Reprendre, filtre par domaine)`.

### Task 5 : références de partage, liens collés et liens vérifiés

Addendum §3 (liens collés) et §3.1 (référence Vehicoule, App Links, liens universels).

**Files :**
- Create : `core/core/src/share.rs`, `core/core/src/api/share.rs`,
  `app/lib/features/app/share/share.dart`.
- Modify : `core/core/src/{lib.rs,api/mod.rs}`, le pont, `fake_api.dart` ;
  `app/lib/platform/links.dart` (routes `ref` et `text`) ; `app/lib/features/music/actions/track_actions.dart`
  (« Partager » dans le menu d'un titre et d'une collection) ;
  `app/lib/features/music/now_playing/now_playing_controller.dart` (« Partager » dans le ⋮) ;
  `app/lib/features/music/explore/explore_page.dart` (lien collé) ;
  `app/lib/shell_desktop/title_bar.dart` (lien collé) ;
  `AndroidManifest.xml` (App Links `https://vehicoule.com` pour `/t/`, `/a/`, `/r/`, `/l/`,
  `/p`, `android:autoVerify="true"` ; `ACTION_SEND` `text/plain`) ; ARB FR/EN. macOS garde
  son schéma `vehicoule` (R5).
- Test : `#[cfg(test)]` de `share.rs`, `app/test/features/share_test.dart`,
  `app/test/platform/links_test.dart`.

**Interfaces :**
- Consumes : `refs::all`, `refs::item_for`, `catalog::upsert_*`, `router::first_ok`,
  `Host::parse_link`, `Host::fetch_entity` (comme `import_playlist`), `share_plus`.
- Produces :
  ```rust
  pub struct LinkTarget { pub domain: Domain, pub kind: ItemKind, pub id: String, pub at_ms: Option<u32> }
  pub async fn share_ref(id: String) -> Result<Option<String>, CoreError>;   // "t/d3135556" ; None : rien de public (playlist perso : Task 8)
  pub async fn open_ref(reference: String) -> Result<LinkTarget, CoreError>; // NotFound : fournisseur inconnu ou id introuvable
  pub async fn open_link(url: String) -> Result<Option<LinkTarget>, CoreError>;
      // https://vehicoule.com/<ref>, vehicoule://<ref>, ou un lien qu'un plugin `entity` reconnaît (parse-link) ; None : personne
  ```
  ```dart
  Future<void> shareItem(BuildContext c, String id);       // share_ref → https://vehicoule.com/<ref> → feuille de partage du système
  bool looksLikeLink(String text);                         // une URL http(s) ou vehicoule:// sur une ligne
  Future<bool> openPastedLink(BuildContext c, String text); // open_link puis openItem ; false → l'appelant cherche le texte
  Stream<Uri> refLinks(); Stream<String> sharedTexts();    // links.dart
  ```
- Règles (addendum §3.1) :
  - catégories `t` titre, `a` album, `r` artiste, `l` playlist éditoriale ; fournisseurs
    `d` Deezer (`external_refs` du plugin `deezer`), `i` ISRC (`music_tracks.isrc`), `m`
    MusicBrainz. `share_ref` préfère `d`, puis `i` pour un titre ; jamais d'id interne ni de
    référence d'une source de lecture ;
  - `open_ref` : `d` → `fetch_entity` du plugin `deezer` avec l'id ; `i` → le même avec l'id
    `isrc:<code>` (l'API Deezer accepte `/track/isrc:<code>` ; un test du plugin dans
    `vehicoule-plugins` le vérifie, et l'y ajoute s'il manque) ; `m` → `NotFound` (aucune
    source ne lit MusicBrainz en v1) ; `?t=` est lu (`12m34` ou des secondes) et rendu dans
    `at_ms` ;
  - la même référence partout : `vehicoule://t/d3135556` et `https://vehicoule.com/t/d3135556`
    ouvrent la même page ; la palette ⌘K (Task 9) l'accepte aussi ;
  - lien collé : dans la recherche (Explorer, barre de titre) et partagé vers l'app
    (`ACTION_SEND`), `looksLikeLink` → `openPastedLink` ; s'il rend `false`, la recherche
    part sur le texte, sans message ;
  - « Partager » dans le menu expressif et le ⋮ du lecteur (addendum §3.1).

- [ ] **Step 1 : tests qui échouent**
  ```rust
  #[tokio::test] async fn share_ref_prefers_deezer_then_isrc()
  #[tokio::test] async fn share_ref_never_uses_an_internal_id()       // titre sans ref publique → None
  #[tokio::test] async fn open_ref_fetches_and_upserts_the_entity()   // t/d3135556 → plugin deezer fetch(track, "3135556") → LinkTarget { kind: Track }
  #[tokio::test] async fn open_ref_by_isrc_asks_deezer_with_isrc_prefix()
  #[tokio::test] async fn open_ref_reads_the_instant()                // e?t=12m34 → 754000 ; t=90 → 90000
  #[tokio::test] async fn unknown_provider_is_not_found()
  #[tokio::test] async fn open_link_accepts_web_app_and_source_links()
  ```
  ```dart
  testWidgets('unrecognised link falls back to search', ...);   // openLink → null : search(texte) appelé, aucun snackbar
  testWidgets('a pasted deezer link opens the album page', ...);
  testWidgets('share builds a vehicoule.com link', ...);
  test('vehicoule.com and vehicoule:// refs reach the same route', ...); // links_test
  ```
- [ ] **Step 2 : implémenter le cœur**, régénérer le pont, étendre `FakeApi`.
- [ ] **Step 3 : implémenter le côté Dart et les manifestes.**
- [ ] **Step 4 : vérifier** (vérifications globales). Sur l'émulateur :
  `adb shell am start -a android.intent.action.VIEW -d https://vehicoule.com/t/d3135556`
  ouvre la page du titre (la vérification `autoVerify` attend le site de la Task 8 ; d'ici
  là, le sélecteur d'app suffit).
- [ ] **Step 5 : commit** : `feat: références de partage, liens collés, liens vérifiés vehicoule.com`.

### Task 6 : sauvegarde — cœur (`item_relations`, export chiffré, restauration par fusion HLC)

Addendum §6 (table `item_relations`, vide en v1) et §7 bis.

**Files :**
- Create : `core/core/migrations/0003_item_relations.sql`, `core/core/src/backup.rs`,
  `core/core/src/api/backup.rs`.
- Modify : `core/core/src/library/db.rs` (migration), `core/core/Cargo.toml` (`flate2` avec
  `rust_backend`, `chacha20poly1305`, `argon2` : RustCrypto et miniz_oxide, Rust pur ; le
  stdlib n'a ni compression ni AEAD), `core/core/src/{lib.rs,api/mod.rs}`, le pont,
  `fake_api.dart`.
- Test : `#[cfg(test)]` de `backup.rs`.

**Interfaces :**
- Consumes : `Hlc::observe`, `Stamp`, les tables du socle §5, `refs::item_for`,
  `library::fold` (`merged_into`).
- Produces :
  ```sql
  CREATE TABLE item_relations (id BLOB PRIMARY KEY, from_item BLOB NOT NULL REFERENCES items(id),
    to_item BLOB NOT NULL REFERENCES items(id), kind TEXT NOT NULL, source TEXT NOT NULL,
    updated_at INTEGER NOT NULL, device_id BLOB NOT NULL, deleted_at INTEGER);
  CREATE INDEX item_relations_from ON item_relations(from_item, kind);
  ```
  ```rust
  pub enum BackupEvery { Day, Week, Never }
  pub struct BackupInfo { pub path: String, pub created_at_ms: i64, pub encrypted: bool, pub bytes: u64 }
  pub struct BackupStatus { pub last: Option<BackupInfo>, pub every: BackupEvery, pub auto_dir: String }
  pub enum RestoreOutcome { Restored { added: u32, updated: u32 }, NeedsPassphrase, WrongPassphrase, NotABackup, NewerFormat }
  pub async fn create_backup(dir: Option<String>, passphrase: Option<String>) -> Result<BackupInfo, CoreError>;
      // écrit <dir>/vehicoule-<AAAA-MM-JJ-HHmm>.vehicoule ; None : sauvegarde automatique, dans auto_dir (<data_dir>/backups), garde les 4 dernières
  pub async fn restore_backup(path: String, passphrase: Option<String>) -> Result<RestoreOutcome, CoreError>;
  pub async fn backup_status() -> Result<BackupStatus, CoreError>;
  pub async fn backup_due() -> Result<bool, CoreError>;            // backup.every et la date du dernier automatique
  pub async fn set_backup_every(every: BackupEvery) -> Result<(), CoreError>;
  ```
- Règles :
  - **Format** : `b"VHCBAK"`, un octet de version (1), un octet de drapeaux (bit 0 :
    chiffré) ; si chiffré, sel (16 octets) et nonce (24 octets) ; puis la charge. Charge =
    deflate brut de lignes JSON : une ligne d'en-tête `{ "format": 1, "created_at_ms",
    "device_id", "app_version" }`, puis `{ "t": "<table>", "r": { colonne: valeur } }` par
    ligne (BLOB en base64).
  - **Chiffrement** : XChaCha20-Poly1305 ; clé = Argon2id(phrase, sel), m = 64 Mio, t = 3,
    p = 1. Sans phrase, compressé seulement.
  - **Contenu** (R9) : `items` référencés et les tables `music_*` de ces items, `artwork`,
    `external_refs`, `likes`, `playlists`, `playlist_items`, `plays`, `item_relations`,
    `settings_shared`, et `feeds` non officiels (URL, nom, clés publiques). Une seule liste,
    `const BACKUP_TABLES`, que les tâches suivantes complètent (Task 16 : `recognized`).
  - **Fusion** : dans **une** transaction ; tables synchronisées : la ligne entrante remplace
    la locale seulement si `(updated_at, device_id)` est plus grand ; les tombes
    (`deleted_at`) suivent la même règle ; autres tables : `INSERT OR IGNORE`. Un item
    entrant dont une `external_ref` désigne déjà un autre item local est inséré avec
    `merged_into` = l'item local. Puis `Hlc::observe(max updated_at)`, index FTS des items
    ajoutés, `LibraryChanged::{Likes, Playlists, History, Home}`.

- [ ] **Step 1 : tests qui échouent**
  ```rust
  #[test] fn item_relations_migration_applies_once()
  #[tokio::test] async fn backup_round_trips_every_listed_table()
  #[tokio::test] async fn restore_keeps_newer_local_rows()               // like local plus récent que celui du fichier → gardé ; plus ancien → remplacé
  #[tokio::test] async fn restore_refuses_bad_files_and_changes_nothing() // mauvaise phrase → WrongPassphrase ; tronqué ou autre fichier → NotABackup ; version 2 → NewerFormat ; base identique à l'octet
  #[tokio::test] async fn encrypted_backup_needs_its_passphrase()       // sans phrase → NeedsPassphrase
  #[tokio::test] async fn restore_joins_duplicates_by_merged_into()
  #[tokio::test] async fn restore_moves_the_clock_past_the_file()
  #[tokio::test] async fn automatic_backups_keep_the_last_four()
  #[tokio::test] async fn backup_due_follows_the_schedule()             // week : 6 j → false, 7 j → true ; never → false
  #[test] fn caches_downloads_and_queue_are_not_saved()
  ```
- [ ] **Step 2 : implémenter**, régénérer le pont, étendre `FakeApi`.
- [ ] **Step 3 : vérifier** (vérifications globales) ; noter au rapport la durée d'Argon2 sur
  le téléphone de référence (attendu : moins de 2 s).
- [ ] **Step 4 : commit** : `feat(core): item_relations, sauvegarde chiffrée et restauration par fusion HLC`.

### Task 7 : sauvegarde — Réglages › Sauvegarde, automatique, premier lancement

**Files :**
- Create : `app/lib/features/app/settings/backup_page.dart` (route `/settings/backup`),
  `app/lib/platform/files.dart`, `app/lib/platform/backup_scheduler.dart`,
  `app/android/app/src/main/kotlin/com/vehicoule/Files.kt`,
  `app/macos/Runner/Files.swift`.
- Modify : `app/pubspec.yaml` (`flutter_secure_storage` : Keystore et Keychain, paquet
  maintenu, aucune dépendance présente ne garde un secret ; sur macOS
  `useDataProtectionKeyChain: false`, qui n'exige pas d'équipe Apple),
  `MainActivity.kt` (canal `com.vehicoule/files`), `app/macos/Runner/AppDelegate.swift`,
  `app/macos/Runner/*.entitlements` (`com.apple.security.files.user-selected.read-write`,
  `com.apple.security.files.bookmarks.app-scope`),
  `app/lib/features/app/settings/settings_page.dart` (entrée « Sauvegarde »),
  `app/lib/features/music/onboarding/onboarding_page.dart` (« Restaurer une sauvegarde » à la
  première étape, à côté de « Commencer »), `app/lib/main.dart`, `router.dart`, ARB FR/EN.
- Test : `app/test/features/backup_test.dart`, `app/test/platform/files_test.dart`.

**Interfaces :**
- Consumes : l'API de la Task 6.
- Produces :
  ```dart
  // platform/files.dart, canal com.vehicoule/files
  Future<String?> pickFolder();                         // Android : OPEN_DOCUMENT_TREE + permission persistante ; macOS : NSOpenPanel + signet ; rend un id opaque
  Future<void> copyToFolder(String path, String folderId);
  Future<String?> pickFile();                           // copie le fichier choisi dans le cache, rend son chemin
  class BackupScheduler { void start(); }               // au lancement puis chaque heure : backupDue() → createBackup(dir: null, phrase du trousseau)
                                                        // → copyToFolder si ui.backup.folder ; jamais bloquant
  ```
- Règles (addendum §7 bis) :
  - l'écran : « Sauvegarder maintenant », « Restaurer », la date de la dernière sauvegarde,
    la fréquence (`VChoiceGroup` Chaque jour / Chaque semaine / Jamais), la phrase de passe
    (définir, changer, retirer), « Copier aussi dans un dossier » ;
  - sans phrase, l'écran dit que le fichier n'est pas chiffré ;
  - « Restaurer » : `pickFile` → `restoreBackup` ; `NeedsPassphrase` → demande la phrase
    (`showVSheet`) ; chaque autre résultat a sa phrase (`voice.md`) ; un succès dit combien
    d'éléments ont été ajoutés et mis à jour ;
  - la phrase vit dans le trousseau du système (R8), jamais dans la base ni dans `ui.*`.

- [ ] **Step 1 : tests qui échouent**
  ```dart
  testWidgets('backup page shows the last backup and saves now', ...);
  testWidgets('without a passphrase the page says the file is not encrypted', ...);
  testWidgets('restore asks for the passphrase when needed', ...);
  testWidgets('each restore outcome has its sentence', ...);
  testWidgets('onboarding offers to restore a backup', ...);
  test('scheduler backs up when due and copies to the chosen folder', ...);
  test('scheduler does nothing when not due', ...);
  ```
- [ ] **Step 2 : implémenter.**
- [ ] **Step 3 : vérifier** (vérifications globales) ; sur l'émulateur et macOS : sauvegarder,
  effacer les données de l'app, restaurer au premier lancement, retrouver likes et playlists.
- [ ] **Step 4 : commit** : `feat(app): Réglages › Sauvegarde, sauvegarde automatique, restauration au premier lancement`.

### Task 8 : site `vehicoule.com` et playlists perso partagées (`/p/`)

Addendum §3.1 (playlist perso, app absente, hébergement) et surface §8.

**Files :**
- Create :
  - `web/site/{index.html,app.js,style.css,_headers,_redirects}` : la page statique, un seul
    fichier JavaScript écrit à la main, aucune dépendance npm ;
  - `web/site/.well-known/apple-app-site-association.in`, `web/site/.well-known/assetlinks.json.in`
    et `web/gen-wellknown.sh <empreinte sha256 du certificat Android> <équipe Apple ou ->` ;
  - `web/site/app.test.mjs` (`node --test`, sans npm) ;
  - `web/worker/{Cargo.toml,wrangler.toml,src/lib.rs}` : crate `vehicoule-share`, workspace
    à part, `worker` (workers-rs : le Worker en Rust exigé par la surface §8 ; projet de
    Cloudflare) ;
  - `core/core/src/share_playlist.rs`.
- Modify : `core/core/src/api/share.rs` (Task 5), le pont, `fake_api.dart`,
  `app/lib/features/app/share/share.dart`, `app/lib/platform/links.dart` (`/p/…` et
  `/p#…`), `app/lib/features/music/library/` (« Partager » d'une playlist perso),
  `.github/workflows/ci.yml` (`node --test web/site`, `cargo test` dans `web/worker`), ARB.
- Test : les fichiers ci-dessus, `#[cfg(test)]` de `share_playlist.rs` et de `web/worker`.

**Interfaces :**
- Consumes : `share_ref` (Task 5), `flate2` (Task 6), le client du cœur pour ses propres
  requêtes (comme `updates.rs`).
- Produces :
  ```rust
  pub struct SharedPlaylistView { pub name: String, pub tracks: Vec<TrackView>, pub missing: u32 }
  pub async fn share_playlist_link(id: String) -> Result<String, CoreError>;
      // POST https://vehicoule.com/api/p {"name","refs"} (5 s) → https://vehicoule.com/p/<code> ;
      // tout échec (hors ligne, 4xx, 5xx, quota) → https://vehicoule.com/p#<base64url(deflate brut du même JSON)>
  pub async fn open_shared_playlist(url: String) -> Result<SharedPlaylistView, CoreError>; // GET /api/p/<code> ou le fragment, puis open_ref de chaque titre
  ```
  Worker : `POST /api/p` → 200 `{ "code" }` (même contenu → même code, aucune écriture si
  la clé existe) ; 400 (JSON invalide, plus de 200 titres, référence hors `t/[dim]…`, nom de
  plus de 100 caractères, corps de plus de 16 Kio) ; 409 (même code, autre contenu) ; 503
  (écriture KV refusée, dont le quota de 1 000 par jour). `GET /api/p/<code>` → 200 JSON ou
  404. Code = base62 des 48 premiers bits du SHA-256 du JSON compact `{"n":…,"r":[…]}`
  (8 caractères). Aucun en-tête, cookie ni journal qui garde l'IP.
- Règles :
  - feuille de partage d'une playlist perso : la phrase « Ce lien publie la liste des
    titres » avant de partager ;
  - ouvrir un lien `/p/` : la liste (titres trouvés, nombre de manquants), puis
    « Enregistrer dans mes playlists » → `createPlaylist` puis `addToPlaylist` (API du
    plan 4) ;
  - page statique : décode la référence ou le fragment (`DecompressionStream('deflate-raw')`),
    demande l'aperçu au catalogue depuis le navigateur (R6 : carte générique si le
    catalogue refuse), boutons « Ouvrir dans Vehicoule » (`vehicoule://<ref>`) et
    « Télécharger l'app » (page des releases) ; Open Graph générique ;
  - `_headers` : `Content-Security-Policy: default-src 'none'; script-src 'self'; style-src 'self';
    img-src 'self' https://*.dzcdn.net; connect-src 'self' https://api.deezer.com; base-uri 'none';
    form-action 'none'; frame-ancestors 'none'`, `Referrer-Policy: no-referrer`,
    `X-Content-Type-Options: nosniff` ; aucun cookie, aucun suivi ;
  - `_redirects` : `/t/*`, `/a/*`, `/r/*`, `/l/*`, `/p/*`, `/p` → `/index.html` (200) ;
  - `wrangler.toml` : route `vehicoule.com/api/p*`, KV `PLAYLISTS` (son id est rempli au
    déploiement par l'utilisateur).

- [ ] **Step 1 : tests qui échouent**
  ```rust
  // web/worker
  #[test] fn same_content_gives_the_same_code()
  #[test] fn validation_refuses_over_200_refs_and_foreign_refs()
  // core
  #[tokio::test] async fn share_link_uses_the_service_code()        // wiremock 200 {"code":"7Hq2xAbc"} → https://vehicoule.com/p/7Hq2xAbc
  #[tokio::test] async fn share_link_falls_back_to_the_fragment()   // 503, puis hors ligne → /p#… qui se décode en la même liste
  #[tokio::test] async fn open_shared_playlist_reads_code_and_fragment()
  #[tokio::test] async fn tracks_without_public_ref_are_left_out_and_counted()
  ```
  ```js
  // web/site/app.test.mjs
  test('decodeRef reads category, provider and id', ...);
  test('decodeFragment inflates the playlist', ...);
  test('preview failure shows the generic card', ...);
  ```
  ```dart
  testWidgets('sharing a user playlist says the list is published', ...);
  testWidgets('a shared playlist link offers to save it', ...);
  ```
- [ ] **Step 2 : implémenter le Worker, la page, puis le cœur et l'app.**
- [ ] **Step 3 : vérifier** : vérifications globales ; `node --test web/site` ; `cargo test`
  et `cargo clippy` dans `web/worker` ; `npx wrangler dev` n'est pas lancé (outil npm de
  l'utilisateur).
- [ ] **Step 4 (utilisateur) : déployer.** `web/gen-wellknown.sh` avec l'empreinte du
  certificat de release Android (et l'équipe Apple si elle existe) ; Cloudflare Pages pour
  `web/site/` ; `wrangler deploy` dans `web/worker/` après création du KV ; la règle de
  débit (R7 : 10 POST par minute et par IP sur `/api/p`) ; les redirections `feeds.`,
  `updates.`, `telemetry.`. Consigné dans « Pending user confirmation ».
- [ ] **Step 5 : commit** : `feat: site vehicoule.com (page de partage, Worker Rust des playlists partagées), partage de playlists perso`.

### Task 9 : palette ⌘K (desktop)

Addendum §9 : elle cherche dans tous les domaines (bibliothèque locale) et lance des actions ;
la recherche de la barre de titre reste celle du domaine courant.

**Files :**
- Create : `app/lib/shell_desktop/command_palette.dart`, `app/lib/features/music/palette.dart`
  (les entrées de la musique).
- Modify : `app/lib/shell_desktop/shortcuts.dart` (⌘K, `Ctrl+K` hors macOS, dans la table
  d'intents et la `PlatformMenuBar` « Aller »), `app/lib/domains.dart` (chaque domaine fournit
  ses entrées), ARB FR/EN.
- Test : `app/test/shell/palette_test.dart`.

**Interfaces :**
- Consumes : `searchLibrary`, `openRef` (Task 5), `playRadio`, `setSleepTimer`, `openItem`,
  `domains`, `destinationsOf`.
- Produces :
  ```dart
  class PaletteEntry { const PaletteEntry({required String label, required IconData icon, required FutureOr<void> Function(BuildContext) run,
    String? shortcut, String? itemId}); }
  Future<void> showCommandPalette(BuildContext c);
  Future<List<PaletteEntry>> paletteEntries(BuildContext c, String query); // pure sur ses entrées, testable
  List<PaletteEntry> musicPaletteEntries(BuildContext c);                 // « Radio de ce titre », « Minuterie… », destinations musique
  ```
- Règles : un `showVSheet` (dialogue au-delà de 840 dp) avec un champ et une liste ; ↑ ↓,
  Entrée lance, Échap ferme ; requête vide → les actions ; texte → les titres de
  `searchLibrary` (au plus 8), puis les actions dont le libellé contient le texte ; une
  référence (`t/d…`) → « Ouvrir » ; actions globales : « Aller à Téléchargements », « Aller
  aux Sources », « Réglages », et « Changer de domaine » (masquée avec un seul domaine).
  Aucun raccourci de lecture tant que la palette a le focus.

- [ ] **Step 1 : tests qui échouent**
  ```dart
  testWidgets('cmd+k opens the palette and escape closes it', ...);
  testWidgets('empty query lists the actions', ...);
  testWidgets('typing lists library tracks then matching actions', ...);
  testWidgets('a vehicoule reference opens its page', ...);
  testWidgets('change domain is hidden with one domain', ...);
  testWidgets('space types in the palette and never toggles playback', ...);
  ```
- [ ] **Step 2 : implémenter.**
- [ ] **Step 3 : vérifier** (vérifications globales) ; capture à 1280 dp.
- [ ] **Step 4 : commit** : `feat(desktop): palette ⌘K (bibliothèque de tous les domaines, actions)`.

### Task 10 : « Ton année » (`/recap/:year`)

Addendum §9 bis. En v1 : minutes d'écoute, artistes et titres en tête ; chaque domaine ajoute
ses chiffres plus tard dans la même page.

**Files :**
- Create : `core/core/src/recap.rs`, `app/lib/features/app/recap/recap_page.dart`.
- Modify : `core/core/src/library/plays.rs` (agrégats), `core/core/src/api/library.rs`
  (`recap`, `ShelfKindView::Recap`), `core/core/src/home/{mod,assemble}.rs` (carte en
  décembre), le pont, `fake_api.dart`, `app/lib/router.dart` (route globale `/recap/:year`),
  `app/lib/features/music/library/history_page.dart` (action « Ton année »),
  `app/lib/features/music/home/feed_shelf.dart` (la carte), ARB FR/EN.
- Test : `#[cfg(test)]` de `recap.rs`, `app/test/features/recap_test.dart`.

**Interfaces :**
- Produces :
  ```rust
  pub struct RecapTrack { pub track: TrackView, pub plays: u32 }
  pub struct RecapArtist { pub artist: ArtistRefView, pub minutes: u32 }
  pub struct RecapView { pub year: i32, pub minutes: u32, pub days: u32, pub tracks: u32,
    pub top_tracks: Vec<RecapTrack>, pub top_artists: Vec<RecapArtist>, pub top_month: Option<u8> }
  pub async fn recap(year: i32, utc_offset_min: i32) -> Result<Option<RecapView>, CoreError>; // None : aucune écoute cette année
  ShelfKindView::Recap  // seed = l'année ; page 1, juste après Resume, du 1er au 31 décembre, si recap(année) a des écoutes
  ```
- Règles : une écoute compte à partir de 30 s (`listened_ms ≥ 30_000`, comme le Top 50) ;
  minutes = somme de `listened_ms` ; bornes de l'année en heure locale
  (`utc_offset_min` fourni par Dart) ; 5 titres et 5 artistes (minutes d'écoute de leurs
  titres) ; jours = jours locaux avec au moins une écoute ; rien ne sort de l'appareil.
  La page : une grande forme de décor par chiffre, les classements en `VTrackRow` et
  cartes d'artiste ; « Lire mon top » → `playTracks`.

- [ ] **Step 1 : tests qui échouent**
  ```rust
  #[tokio::test] async fn recap_counts_minutes_days_and_tops_in_local_time() // une écoute le 31/12 à 23 h 30 en UTC+1 compte pour l'année suivante
  #[tokio::test] async fn short_plays_do_not_count()
  #[tokio::test] async fn empty_year_is_none()
  #[tokio::test] async fn recap_card_is_on_the_home_in_december_only()
  ```
  ```dart
  testWidgets('recap page shows minutes, top tracks and artists', ...);
  testWidgets('history opens the recap of the current year', ...);
  ```
- [ ] **Step 2 : implémenter le cœur**, régénérer le pont, puis la page.
- [ ] **Step 3 : vérifier** (vérifications globales) ; captures.
- [ ] **Step 4 : commit** : `feat: « Ton année » (agrégats locaux, page /recap/:year, carte de décembre)`.

### Task 11 : conditions de l'appareil et mode économie

Addendum §7 : automatique = données mobiles ou économie de batterie du système. En musique :
qualité `low`, et « Pour le trajet » coupé (Task 12).

**Files :**
- Create : `core/core/src/conditions.rs`, `app/lib/platform/conditions.dart`,
  `app/android/app/src/main/kotlin/com/vehicoule/Conditions.kt`,
  `app/macos/Runner/Conditions.swift`.
- Modify : `core/core/src/api/settings.rs` (`Settings.economy`), `core/core/src/player.rs`
  (`call_resolve` : `Quality::Low` quand l'économie est active), le pont, `fake_api.dart`,
  `MainActivity.kt` et `AppDelegate.swift` (canal d'événements `com.vehicoule/conditions`),
  `app/lib/design/components/empty_state.dart` (`VEconomyChip`, à côté de `VOfflineChip`),
  les coques (la puce sous l'app bar), `app/lib/features/app/settings/settings_page.dart`
  (section « Données et batterie »), `app/lib/main.dart`, ARB FR/EN.
- Test : `#[cfg(test)]` de `conditions.rs`, `app/test/platform/conditions_test.dart`,
  `app/test/features/settings_test.dart`.

**Interfaces :**
- Produces :
  ```rust
  pub struct DeviceConditions { pub metered: bool, pub power_save: bool, pub charging: bool, pub wifi: bool }
  pub enum EconomyMode { Auto, Always, Never }
  pub fn set_device_conditions(c: DeviceConditions);   // api ; garde le dernier état
  pub fn economy_states(sink: StreamSink<bool>);       // l'état effectif, à chaque changement d'état ou de réglage
  pub(crate) fn economy() -> bool;                     // Always ; Auto && (metered || power_save) ; Never → false
  pub(crate) fn conditions() -> DeviceConditions;
  ```
  ```dart
  class ConditionsWatcher { void start(); }            // canal → setDeviceConditions ; Android : ConnectivityManager (metered, wifi), PowerManager.isPowerSaveMode,
                                                       // BatteryManager (charging) ; macOS : NWPathMonitor (isExpensive), ProcessInfo.isLowPowerModeEnabled, IOPowerSources
  class VEconomyChip extends StatelessWidget { const VEconomyChip(); }  // « Économie de données »
  ```
- Règles : la puce s'affiche sous l'app bar comme la puce hors ligne ; hors ligne l'emporte
  (une seule puce) ; le changement s'applique à la prochaine résolution, jamais au titre en
  cours ; Réglages › Données et batterie : `VChoiceGroup` Automatique / Toujours / Jamais.

- [ ] **Step 1 : tests qui échouent**
  ```rust
  #[test] fn economy_follows_mode_and_conditions()             // table : Auto × metered/power_save, Always, Never
  #[tokio::test] async fn economy_resolves_in_low_quality()     // resolve demandé en Quality::Low
  #[tokio::test] async fn economy_applies_from_the_next_resolve() // aucun Play renvoyé pour le titre en cours
  ```
  ```dart
  test('conditions reach the core on every change', ...);
  testWidgets('economy chip shows under the app bar, offline wins', ...);
  testWidgets('data and battery setting saves the mode', ...);
  ```
- [ ] **Step 2 : implémenter.**
- [ ] **Step 3 : vérifier** (vérifications globales) ; sur l'émulateur, passer en données
  mobiles simulées (`adb shell svc wifi disable`) : la puce paraît, le titre suivant est
  résolu en `low` (journal du cœur).
- [ ] **Step 4 : commit** : `feat: mode économie (conditions de l'appareil, qualité low, puce)`.

### Task 12 : budget de stockage, « Pour le trajet », tâches de fond Android

Addendum §7 : un budget unique (Réglages › Téléchargements) ; « Pour le trajet » télécharge la
découverte du jour en Wi-Fi et en charge, réglable par domaine.

**Files :**
- Create : `core/core/migrations/0004_download_origin.sql`
  (`ALTER TABLE downloads ADD COLUMN origin TEXT NOT NULL DEFAULT 'user'`),
  `core/core/src/{budget,commute,background}.rs`,
  `app/android/app/src/main/kotlin/com/vehicoule/work/{Background,CommuteWorker,Schedule}.kt`.
- Modify : `core/core/src/library/{db,downloads}.rs`, `core/core/src/downloads.rs`
  (`origin`, `enforce` après chaque titre terminé), `core/core/src/app.rs` (écrit
  `<data_dir>/app_config.json` à chaque `init`), `core/core/src/android.rs` (entrée JNI),
  `core/core/src/api/{settings,library}.rs`, le pont, `fake_api.dart` ;
  `app/android/app/build.gradle.kts` (`androidx.work:work-runtime-ktx` : la seule API Android
  pour un travail sous contraintes Wi-Fi et charge, bibliothèque Jetpack) ;
  `AndroidManifest.xml` ; `app/lib/features/app/downloads/downloads_page.dart` (la barre
  montre le budget) ; `app/lib/features/app/settings/settings_page.dart` (budget, « Pour le
  trajet » dans la section Musique) ; ARB FR/EN.
- Test : `#[cfg(test)]` des trois modules, `app/android/app/src/androidTest/kotlin/com/vehicoule/work/BackgroundConfigTest.kt`,
  `app/test/features/downloads_test.dart`.

**Interfaces :**
- Consumes : `conditions()`, `economy()` (Task 11), l'étagère `Discovery` du fil
  (`home::page`), `downloads::enqueue`, `library::downloads`.
- Produces :
  ```rust
  pub(crate) async fn enforce() -> Result<Vec<ItemId>, CoreError>;            // budget.rs : retire selon R10 jusqu'à passer sous le budget
  pub struct CommuteReport { pub queued: u32, pub removed: u32 }
  pub(crate) async fn run_commute() -> Result<Option<CommuteReport>, CoreError>; // None : conditions non remplies, réglage coupé, économie, ou déjà fait aujourd'hui
  pub(crate) fn run_background(files_dir: &str, task: &str) -> String;       // background.rs : lit app_config.json, init, lance la tâche, rend un JSON ; "{}" sans config
  // android.rs
  #[unsafe(no_mangle)] pub extern "system" fn Java_com_vehicoule_work_Background_run(env, this, files_dir: JString, task: JString) -> jstring;
  // api
  pub struct StorageView { pub music_bytes: u64, pub free_bytes: u64, pub budget_bytes: u64 } // champ ajouté
  pub async fn set_download_budget(bytes: u64) -> Result<(), CoreError>;
  ```
  ```kotlin
  object Background { external fun run(filesDir: String, task: String): String }      // filesDir = PathUtils.getFilesDir(context), le dossier de path_provider
  class CommuteWorker : CoroutineWorker   // setForeground (notification dataSync, comme DownloadService), Background.run(filesDir, "commute") ; attend la fin de la file (30 min au plus)
  object Schedule { fun all(context: Context) }   // périodique 12 h, contraintes UNMETERED + charging ; appelé au lancement de l'app
  ```
- Règles :
  - « Pour le trajet » (musique) : les titres de la découverte du jour, en `origin =
    'commute'`, sans retélécharger ce qui est déjà là ; à chaque passage, les titres
    `commute` qui ne sont plus dans la découverte, ni écoutés, ni likés, partent ;
  - déclenché aussi dans l'app quand les conditions deviennent Wi-Fi + charge (une fois par
    jour local) ; jamais en économie ;
  - budget : défaut 5 Gio ; `0` = sans limite ; ordre de retrait R10 ;
  - `app_config.json` contient l'`AppConfig` du dernier lancement ; la tâche de fond n'a
    rien à faire tant que l'app n'a jamais été lancée.

- [ ] **Step 1 : tests qui échouent**
  ```rust
  #[test] fn download_origin_migration_applies_once()
  #[tokio::test] async fn eviction_spares_current_queued_and_unplayed()  // budget dépassé : ni le titre en cours, ni la file, ni un titre user non écouté
  #[tokio::test] async fn eviction_takes_commute_first_then_oldest_played()
  #[tokio::test] async fn commute_downloads_todays_discovery_once_a_day()
  #[tokio::test] async fn commute_skips_without_wifi_and_charging_or_in_economy()
  #[tokio::test] async fn commute_drops_yesterdays_unplayed_tracks()
  #[test] fn background_without_config_does_nothing()
  #[test] fn background_reads_the_config_written_by_init()
  ```
  `BackgroundConfigTest` (instrumenté) : après un lancement de l'app,
  `File(PathUtils.getFilesDir(ctx), "app_config.json")` existe et son `data_dir` est ce
  dossier.
  ```dart
  testWidgets('downloads bar shows the budget', ...);
  testWidgets('commute and budget settings are saved', ...);
  ```
- [ ] **Step 2 : implémenter le cœur**, régénérer le pont.
- [ ] **Step 3 : implémenter le côté Android** (`Background`, `CommuteWorker`, `Schedule`).
- [ ] **Step 4 : vérifier** (vérifications globales), puis sur l'émulateur :
  `adb shell cmd jobscheduler run -f com.vehicoule <id>` (ou l'inspecteur WorkManager) avec
  l'app fermée : les titres de la découverte arrivent, la notification de progression reste
  le temps du travail.
- [ ] **Step 5 : commit** : `feat: budget de stockage, « Pour le trajet » en Wi-Fi et en charge, tâches de fond Android`.

### Task 13 : résumé quotidien

Addendum §4 point 4 ; en v1, les sorties de tes artistes (`browse.releases`, plan 7), en une
notification par jour. Réglage par domaine (R12 : chaque jour ou jamais).

**Files :**
- Create : `core/core/src/summary.rs`,
  `app/android/app/src/main/kotlin/com/vehicoule/work/SummaryWorker.kt`,
  `app/android/app/src/main/kotlin/com/vehicoule/Notify.kt`,
  `app/macos/Runner/Notify.swift`, `app/lib/platform/notify.dart`,
  `app/lib/platform/summary_scheduler.dart`.
- Modify : `core/core/src/background.rs` (tâche `summary`), `core/core/src/api/library.rs`
  (`daily_summary`), le pont, `fake_api.dart`, `Schedule.kt` (périodique 24 h, premier
  passage au prochain 18 h local, contrainte réseau), `app/android/app/src/main/res/values{,-fr}/strings.xml`
  (pluriels), `app/macos/Runner/{en,fr}.lproj/Localizable.strings`, `MainActivity.kt` et
  `AppDelegate.swift` (canal `com.vehicoule/notify`),
  `app/lib/platform/links.dart` (route `home`), `settings_page.dart` (« Résumé quotidien »,
  section Musique), `app/lib/main.dart`.
- Test : `#[cfg(test)]` de `summary.rs`, `app/test/platform/summary_scheduler_test.dart`.

**Interfaces :**
- Produces :
  ```rust
  pub struct DailySummary { pub releases: u32 }
  pub async fn daily_summary() -> Result<Option<DailySummary>, CoreError>;
      // None : réglage coupé, déjà envoyé aujourd'hui (jour local), ou rien de nouveau ; les albums annoncés vont dans kv @core/summary_seen
  ```
  ```dart
  class SummaryScheduler { void start(); }   // macOS, Windows, Linux : à 18 h locales (ou au premier lancement après), daily_summary → notify
  Future<void> notify(String title, String body, Uri link);   // canal com.vehicoule/notify : Android NotificationCompat (MainActivity), macOS UNUserNotificationCenter ;
                                                              // sert aussi à la Task 17 ; le résumé Android passe par SummaryWorker
  ```
  ```kotlin
  class SummaryWorker : CoroutineWorker   // Background.run(filesDir, "summary") → {"releases": n} ; n > 0 → la notification (pluriel natif), lien vehicoule://home
  ```
- Règles : une notification, « 2 sorties de tes artistes » (pluriels natifs) ; toucher →
  `vehicoule://home` → `/home`. Sorties = albums de moins de 30 jours des artistes likés,
  jamais annoncés.

- [ ] **Step 1 : tests qui échouent**
  ```rust
  #[tokio::test] async fn summary_counts_new_releases_once()
  #[tokio::test] async fn summary_is_sent_once_per_local_day()
  #[tokio::test] async fn summary_off_sends_nothing()
  ```
  ```dart
  test('summary scheduler notifies at 18h when there is news', ...);
  test('home link opens the home', ...);
  ```
- [ ] **Step 2 : implémenter.**
- [ ] **Step 3 : vérifier** (vérifications globales) ; sur l'émulateur, lancer le worker à la
  main : la notification paraît et ouvre l'accueil ; sur macOS, la notification paraît.
- [ ] **Step 4 : commit** : `feat: résumé quotidien des sorties de tes artistes`.

### Task 14 : contrat `vehicoule:music` 1.2.0 (`identify`, `translate`)

Ajout mineur (socle §4.3), comme `browse` au plan 7.

**Files :**
- Modify : `core/contract/wit/music/music.wit` (`package vehicoule:music@1.2.0`, deux
  interfaces exportées), `core/contract/src/lib.rs`, les copies vendorisées
  (`core/plugin-host/guests/wit/world.wit`, `core/core/tests/guests/wit/world.wit`),
  `sdk/src/lib.rs` si une version y est écrite, `core/plugin-host/src/{lib.rs,calls.rs,manifest.rs}`
  (`Capability::{Identify, Translate}`, appels, contrat `1.2` accepté), un composant de test
  sous `core/plugin-host/guests/`, `core/core/src/{error.rs,router.rs}` (miroir du pont,
  `cap_name`), `app/lib/l10n/errors.dart` et ARB (« Il te faut une source pour reconnaître
  un morceau. », « Il te faut une source pour traduire les paroles. »).
- Test : `core/contract/tests/`, `core/plugin-host/tests/calls.rs`.

**Interfaces :**
- Produces :
  ```wit
  interface identify {
      use types.{error, track};
      /// Mono, 16 000 Hz, 12 s au plus.
      record clip { samples: list<s16> }
      record identified { track: track, /// 0..1
          score: f32 }
      identify: func(clip: clip, region: string) -> result<list<identified>, error>;
  }
  interface translate {
      use types.{error};
      /// `source-lang` : BCP 47 ou "auto" ; une ligne rendue par ligne reçue, dans l'ordre.
      lines: func(lines: list<string>, source-lang: string, target-lang: string) -> result<list<string>, error>;
  }
  ```
  ```rust
  impl Host { pub async fn identify(&self, p: &Plugin, clip: Vec<i16>, region: &str) -> Result<Vec<Identified>, CallError>;
              pub async fn translate(&self, p: &Plugin, lines: Vec<String>, source: &str, target: &str) -> Result<Vec<String>, CallError>; }
  ```
  Tags locaux `contract-v1.2.0` et `plugin-host-v1.2.0` à la fin (jamais poussés par la tâche).

- [ ] **Step 1 : tests qui échouent**
  ```rust
  #[test] fn music_wit_is_1_2_with_identify_and_translate()
  #[tokio::test] async fn plugin_1_1_loads_in_host_1_2_without_the_new_capabilities()
  #[tokio::test] async fn identify_reaches_the_guest_and_back()
  #[tokio::test] async fn translate_must_return_one_line_per_line()   // un guest qui en rend moins → CallError::Internal
  ```
  ```dart
  test('every CoreError variant has a message in both languages', ...); // existant : couvre NoPlugin(identify|translate)
  ```
- [ ] **Step 2 : implémenter.** Si le test de compatibilité 1.1 → 1.2 échoue, s'arrêter et
  le signaler (BLOCKED), sans contournement (même règle qu'au plan 7).
- [ ] **Step 3 : vérifier** (vérifications globales).
- [ ] **Step 4 : commit** : `feat(contract): vehicoule:music 1.2.0, capacités identify et translate`.

### Task 15 : paroles M1 — romanisées en local et traduites

Addendum §13 M1. La vue Paroles (plan 5 Task 6) gagne deux bascules.

**Files :**
- Create : `core/core/src/romanize.rs` (+ `romanize/kana.rs` : table Hepburn) ;
  `vehicoule-plugins/plugins/mymemory/` (plugin `translate`, `manifest.json` : domaine
  `api.mymemory.translated.net`).
- Modify : `core/core/Cargo.toml` (`lindera` avec IPADIC embarqué : lecture des kanji, Rust
  pur, aucune autre source de lectures ; `pinyin` : données du pinyin, Rust pur),
  `core/core/src/lyrics.rs` (`LyricLine.romanized`, `LyricsView.romanizable`,
  `translate_lyrics`), le pont, `fake_api.dart`,
  `app/lib/features/music/now_playing/lyrics_view.dart`, ARB FR/EN ;
  `vehicoule-plugins` : `Cargo.toml` du workspace, le feed (déclaration seulement, aucune
  publication).
- Test : `#[cfg(test)]` de `romanize.rs` et `lyrics.rs`, tests du plugin (wiremock),
  `app/test/features/now_playing_test.dart`.

**Interfaces :**
- Produces :
  ```rust
  pub(crate) fn romanize(line: &str) -> Option<String>;   // None : rien à romaniser (latin, vide)
  pub(crate) fn script_lang(text: &str) -> Option<&'static str>; // "ja" (kana présents), "ko" (hangul), "zh" (han sans kana)
  pub struct LyricLine { pub start_ms: u32, pub text: String, pub romanized: Option<String> }
  pub struct LyricsView { pub plain: Option<String>, pub synced: Vec<LyricLine>, pub romanizable: bool }
  pub async fn translate_lyrics(id: String, target_lang: String) -> Result<Vec<String>, CoreError>;
      // une ligne par ligne synchronisée (ou du texte simple) ; kv @core/lyrics_tr:<item>:<langue> ; même langue → les lignes telles quelles
  ```
- Règles :
  - japonais : lindera (IPADIC) donne la lecture en katakana, puis Hepburn modifié (`ō`,
    `ū`, particules `は` → `wa`, `へ` → `e`, `を` → `o`) ; coréen : romanisation révisée
    calculée depuis les jamo ; chinois : pinyin avec tons ; un mot inconnu garde sa forme ;
  - traduction : langue cible = langue de l'app ; source = `script_lang`, sinon `"auto"` ;
    le plugin `mymemory` regroupe les lignes en requêtes de 450 caractères au plus et rend
    `CallError::RateLimited` quand le quota anonyme est atteint ;
  - vue Paroles : `VChip` « Romaniser » (présente si `romanizable`) et « Traduire »
    (présente si un plugin `translate` est installé) ; `ui.lyrics.romanize`,
    `ui.lyrics.translate` ; chaque ligne garde l'original et montre, plus petit dessous, la
    romanisation puis la traduction ; la ligne active reste celle du temps.

- [ ] **Step 1 : tests qui échouent**
  ```rust
  #[test] fn japanese_lines_become_hepburn()            // « 夜に駆ける » → « yoru ni kakeru » ; « 私は » → « watashi wa »
  #[test] fn korean_lines_follow_revised_romanization() // « 사랑해 » → « saranghae »
  #[test] fn chinese_lines_get_pinyin_with_tones()      // « 月亮 » → « yuè liàng »
  #[test] fn latin_lines_are_not_romanized()
  #[tokio::test] async fn translation_is_cached_per_track_and_language()
  #[tokio::test] async fn translation_keeps_one_line_per_line()
  ```
  ```rust
  // plugin mymemory
  #[test] fn batches_lines_under_450_chars()
  #[test] fn quota_answer_is_rate_limited()
  ```
  ```dart
  testWidgets('lyrics show romanized and translated lines under the original', ...);
  testWidgets('romanize chip only shows for romanizable lyrics', ...);
  ```
- [ ] **Step 2 : implémenter le cœur**, puis le plugin, puis la vue.
- [ ] **Step 3 : vérifier** (vérifications globales ; dans `vehicoule-plugins`, `cargo test`
  et le build `wasm32-wasip2`). Noter au rapport la taille de `libvehicoule_core` avant et
  après (arm64 et macOS). Au-delà de +20 Mio, le consigner au ledger pour l'utilisateur.
- [ ] **Step 4 (utilisateur) : publier** le feed officiel avec `mymemory` (Pending).
- [ ] **Step 5 : commit** (un par dépôt) : `feat: paroles romanisées en local et traduites ligne à ligne` ;
  `feat(mymemory): plugin translate`.

### Task 16 : « C'est quoi ? » — cœur et plugin AcoustID

Addendum §6 bis, mode Écouter (le mode Montrer arrive avec l'anime et les livres).

**Files :**
- Create : `core/core/src/identify.rs`, `core/core/migrations/0005_recognized.sql`,
  `vehicoule-plugins/plugins/acoustid/` (plugin `identify` : `rusty-chromaprint` dans le
  composant, empreinte calculée dans le bac à sable, seule l'empreinte part ;
  `api.acoustid.org`).
- Modify : `core/core/Cargo.toml` (`symphonia` : décoder un fichier partagé, Rust pur, mp3,
  aac/mp4, flac, vorbis/ogg, wav), `core/core/src/backup.rs` (`recognized` dans
  `BACKUP_TABLES`), `core/core/src/api/app.rs` (`set_online(true)` appelle aussi
  `identify::on_online()`, à côté de `home::on_online()`), `core/core/src/events.rs`
  (`Notice::Identified`), le pont, `fake_api.dart`.
- Test : `#[cfg(test)]` de `identify.rs`, tests du plugin.

**Interfaces :**
- Consumes : `router::ordered(Capability::Identify)`, `Host::identify`, `open_ref` (Task 5),
  `catalog::search`, `catalog::upsert_track`.
- Produces :
  ```sql
  CREATE TABLE recognized (id BLOB PRIMARY KEY, item_id BLOB NOT NULL REFERENCES items(id), recognized_at INTEGER NOT NULL,
    score REAL NOT NULL, updated_at INTEGER NOT NULL, device_id BLOB NOT NULL, deleted_at INTEGER);
  CREATE TABLE pending_identify (id BLOB PRIMARY KEY, samples BLOB NOT NULL, created_at INTEGER NOT NULL);
  ```
  ```rust
  pub struct IdentifiedView { pub track: TrackView, pub score: f32 }
  pub enum IdentifyOutcome { Found(Vec<IdentifiedView>), NothingFound, Queued }
  pub async fn identify_clip(samples: Vec<i16>) -> Result<IdentifyOutcome, CoreError>;   // mono 16 kHz ; NoPlugin(Identify) sans fournisseur
  pub async fn identify_file(path: String) -> Result<IdentifyOutcome, CoreError>;        // symphonia : 12 premières secondes, mono, 16 kHz
  pub struct RecognizedView { pub at_ms: i64, pub track: TrackView }
  pub async fn recognized(offset: u32, limit: u32) -> Result<Vec<RecognizedView>, CoreError>;
  Notice::Identified { track: TrackView }   // une entrée en attente a abouti au retour du réseau
  ```
- Règles :
  - R15 : tous les plugins `identify` en parallèle, scores ≥ 0,5, triés, 3 au plus ;
  - rattachement : le titre rendu est inscrit sous le plugin, puis rattaché au catalogue
    musique : par ISRC (`open_ref("t/i<isrc>")`) s'il en a un, sinon par `search("<titre>
    <artiste>")` dont le titre et l'artiste repliés (`fold`) égalent les siens ; sinon il
    reste tel quel ;
  - chaque résultat retenu (le premier) va dans `recognized` ; hors ligne, l'extrait va dans
    `pending_identify` (`Queued`) et part au retour du réseau, puis `Notice::Identified` ;
  - la clé d'application AcoustID est une constante du plugin, fournie par l'utilisateur
    (inscription sur acoustid.org) : d'ici là, « Pending user confirmation » ; les tests
    utilisent `test-key` contre wiremock.

- [ ] **Step 1 : tests qui échouent**
  ```rust
  #[tokio::test] async fn identify_calls_every_provider_and_keeps_the_best()
  #[tokio::test] async fn low_scores_are_nothing_found()
  #[tokio::test] async fn a_match_is_attached_by_isrc_then_by_search()
  #[tokio::test] async fn offline_clips_wait_and_notify_when_back_online()
  #[tokio::test] async fn recognized_lists_newest_first()
  #[test] fn shared_file_is_decoded_to_16k_mono()        // fixture wav 44,1 kHz stéréo de 20 s → 192 000 échantillons
  #[test] fn recognized_is_backed_up()
  // plugin acoustid
  #[test] fn lookup_sends_only_the_fingerprint_and_duration()
  #[test] fn recordings_become_tracks_with_scores()
  ```
- [ ] **Step 2 : implémenter le cœur**, puis le plugin.
- [ ] **Step 3 : vérifier** (vérifications globales ; plugin : `cargo test`, build wasm).
- [ ] **Step 4 (utilisateur) : clé AcoustID et publication** du feed avec `acoustid`
  (Pending).
- [ ] **Step 5 : commit** (un par dépôt) : `feat(core): « C'est quoi ? » (identify en parallèle, rattachement au catalogue, reconnus, file hors ligne)` ;
  `feat(acoustid): plugin identify`.

### Task 17 : « C'est quoi ? » — l'écran, ses entrées, « Reconnus »

**Files :**
- Create :
  - `app/lib/design/components/shape_stage.dart` (`VShapeStage`, exporté par `design.dart`) ;
  - `app/lib/features/app/identify/identify_page.dart` (route globale `/identify`) ;
  - `app/lib/platform/capture.dart`, `app/android/app/src/main/kotlin/com/vehicoule/Capture.kt`,
    `app/macos/Runner/Capture.swift` ;
  - `app/android/app/src/main/kotlin/com/vehicoule/IdentifyTileService.kt`,
    `app/android/app/src/main/res/xml/shortcuts.xml` (raccourci statique « C'est quoi ? »).
- Modify : `app/lib/design/components/surfaces.dart` (`VSearchBar(trailing:)`),
  `app/lib/design/gallery.dart`, `app/lib/features/music/explore/explore_page.dart` et
  `app/lib/features/app/home/home_page.dart` (bouton cookie au bout de la recherche),
  `app/lib/shell_desktop/title_bar.dart`, `app/lib/features/music/palette.dart` (entrée),
  `app/lib/router.dart` (route `/identify` ; l'écouteur de `notices()` traite
  `Notice::Identified`), `app/lib/platform/links.dart` (route `identify`, `ACTION_SEND audio/*`),
  `AndroidManifest.xml` (`RECORD_AUDIO`, tuile, raccourcis, `ACTION_SEND audio/*`),
  `app/macos/Runner/Info.plist` (`NSMicrophoneUsageDescription`,
  `NSAudioCaptureUsageDescription`), `*.entitlements` (`com.apple.security.device.audio-input`),
  le widget 4×2 (bouton cookie) et le popover de la barre des menus (entrée) du plan 5
  Task 10, `app/lib/features/music/library/{library_page,history_page}.dart` (tuile et filtre
  « Reconnus »), ARB FR/EN.
- Test : `app/test/design/shape_stage_test.dart`, `app/test/features/identify_test.dart`,
  `app/test/platform/capture_test.dart`.

**Interfaces :**
- Consumes : `identify_clip`, `identify_file`, `recognized`, `Notice::Identified` (Task 16).
- Produces :
  ```dart
  enum VStageState { listening, analysing, found, nothingFound }
  class VShapeStage extends StatefulWidget { const VShapeStage({required VStageState state, ValueListenable<double>? level,
    double progress = 0, VDecorShape? settleOn, VoidCallback? onTap}); }
      // 60 % de la largeur ; listening : respire avec level, morphe entre les formes de décor, anneau ondulé = progress (0..1 sur 12 s) ;
      // found : se pose sur settleOn ; nothingFound : se dégonfle en cercle ; reduceMotion : forme fixe, anneau linéaire
  Stream<Int16List> captureMic({Duration max = const Duration(seconds: 12)});    // 16 kHz mono ; Android AudioRecord, macOS AVAudioEngine + AVAudioConverter
  Stream<Int16List> captureSystem({Duration max = const Duration(seconds: 12)}); // macOS 14.2+ (tap Core Audio) ; ailleurs : jamais proposé
  ValueListenable<double> captureLevel();                                         // niveau RMS 0..1 pour la respiration
  Future<void> showIdentify(BuildContext c, {String? sharedFile});               // plein écran sur téléphone, dialogue sur desktop
  ```
- Règles (addendum §6 bis, « L'écran, en M3E ») :
  - plein écran sur `surfaceContainer`, sans dégradé ; une ligne de texte sous la forme
    (« J'écoute… », puis le résultat) ; haptique « sélection » au résultat ;
  - trouvé : container transform de la forme vers la page du titre (le cookie devient la
    pochette) ; plusieurs réponses : la forme se divise en 2 ou 3 cartes (carousel), chacune
    avec sa confiance en mots (≥ 0,8 « Très probable », sinon « Possible ») ;
  - rien trouvé : « Je n'ai pas reconnu ce morceau. Rapproche-toi de la source du son. » et
    « Réessayer » ; sans fournisseur : une phrase et « Ajouter une source » ; `Queued` : « Je
    le chercherai dès que tu seras en ligne. », puis `Notice::Identified` → `notify` (Task 13)
    avec le titre trouvé, dont le toucher ouvre sa page ;
  - le groupe Écouter · Montrer est masqué tant qu'un seul mode existe ; desktop : option
    « Écouter l'ordinateur » (R17) et dépôt d'un fichier (R16) ;
  - permission micro demandée au premier usage ; refusée → une phrase et le lien vers les
    réglages du système ;
  - entrées : bouton cookie au bout de la search bar (Explorer, Accueil, barre de titre),
    ⌘K, tuile des réglages rapides, raccourci d'icône, bouton du widget, popover de la barre
    des menus, son partagé vers l'app ;
  - « Reconnus » : une tuile de la Bibliothèque musique (liste `recognized`) et un filtre de
    l'Historique.

- [ ] **Step 1 : tests qui échouent**
  ```dart
  testWidgets('shape stage breathes with the level and fills its ring', ...);
  testWidgets('shape stage is static with reduce motion', ...);
  testWidgets('identify shows found, several, nothing and queued states', ...);
  testWidgets('without a provider identify says so and offers to add a source', ...);
  testWidgets('a found track opens its page with a container transform', ...);
  testWidgets('every entry opens identify', ...);   // bouton de recherche, ⌘K, lien vehicoule://identify
  testWidgets('a queued clip found later notifies with its track', ...); // Notice.identified → notify(…, lien de la page du titre)
  testWidgets('recognized tile and history filter list recognized tracks', ...);
  test('capture stops at 12 seconds', ...);
  ```
- [ ] **Step 2 : implémenter** `VShapeStage` (galerie comprise), la capture, l'écran, puis
  les entrées.
- [ ] **Step 3 : vérifier** (vérifications globales) ; sur l'émulateur (micro de l'hôte) et
  sur macOS : un titre joué à côté est reconnu (feed de dev avec `acoustid` construit en
  local, clé de l'utilisateur si elle est arrivée) ; captures de chaque état à côté de la
  description de l'addendum.
- [ ] **Step 4 : commit** : `feat(app): « C'est quoi ? » (grande forme M3E, capture, entrées, Reconnus)`.

### Task 18 : M3 — son retenu par sortie audio

Addendum §13 M3 : égaliseur et normalisation retenus par sortie (casque, enceinte, voiture),
par les filtres de libmpv (gardés par la Task 2).

**Files :**
- Create : `core/core/src/sound.rs`, `app/lib/platform/audio_output.dart`,
  `app/android/app/src/main/kotlin/com/vehicoule/AudioOutputs.kt`,
  `app/macos/Runner/AudioOutputs.swift`,
  `app/lib/features/music/settings/sound_page.dart` (route `/settings/music/sound`).
- Modify : `core/core/src/player.rs` (`PlayerCommand::SetEqualizer`, `gain_db` selon la
  normalisation de la sortie), le pont, `fake_api.dart`, `app/lib/platform/player.dart`
  (filtre `af`), `MainActivity.kt`, `AppDelegate.swift`,
  `app/lib/features/app/settings/settings_page.dart` (entrée « Son », section Musique),
  ARB FR/EN.
- Test : `#[cfg(test)]` de `sound.rs`, `app/test/platform/player_test.dart`,
  `app/test/features/sound_test.dart`.

**Interfaces :**
- Produces :
  ```rust
  pub enum OutputKind { Speaker, Wired, Bluetooth, Usb, Car, Other }
  pub struct AudioOutput { pub key: String, pub label: String, pub kind: OutputKind } // key = "<kind>:<nom>"
  pub struct SoundProfile { pub bands_db: Vec<f32>, pub normalize: bool }           // 5 bandes, ±12 dB
  pub fn set_audio_output(o: AudioOutput);
  pub async fn sound_profile(key: String) -> Result<SoundProfile, CoreError>;
  pub async fn set_sound_profile(key: String, p: SoundProfile) -> Result<(), CoreError>;
  pub fn current_output() -> Option<AudioOutput>;
  PlayerCommand::SetEqualizer { bands_db: Vec<f32> }   // envoyé au changement de sortie ou de profil
  ```
  ```dart
  // platform/audio_output.dart : canal d'événements com.vehicoule/audio_output → setAudioOutput
  String equalizerFilter(List<double> bandsDb);   // "" si tout est à 0 ; sinon lavfi=[equalizer=f=60:t=o:w=1.5:g=…,…] pour 60, 230, 910, 3600, 14000 Hz
  ```
- Règles : Android : `AudioDeviceCallback`, la sortie active est la route de plus haute
  priorité (Bluetooth A2DP, filaire, USB, haut-parleur) ; « voiture » = un appareil
  Bluetooth dont la classe est `AUDIO_VIDEO_CAR_AUDIO` ; macOS : périphérique de sortie par
  défaut de Core Audio et son écouteur. Un profil s'applique dès que la sortie change, sans
  couper le son. Écran : nom de la sortie en cours, 5 `VSlider`, l'interrupteur
  « Normalisation », « Réinitialiser ».

- [ ] **Step 1 : tests qui échouent**
  ```rust
  #[tokio::test] async fn each_output_keeps_its_profile()
  #[tokio::test] async fn changing_output_sends_its_equalizer()
  #[tokio::test] async fn normalization_off_for_an_output_gives_zero_gain()
  ```
  ```dart
  test('equalizer filter is empty when flat and lists five bands otherwise', ...);
  test('SetEqualizer sets the af property', ...);
  testWidgets('sound page edits the current output profile', ...);
  ```
- [ ] **Step 2 : implémenter.**
- [ ] **Step 3 : vérifier** (vérifications globales) ; sur macOS, changer de sortie
  (haut-parleur → casque) : le profil suit, le son ne s'interrompt pas.
- [ ] **Step 4 : commit** : `feat: son retenu par sortie audio (égaliseur 5 bandes, normalisation)`.

### Task 19 : lire sur la TV — DLNA dans le cœur

Addendum §5.4 et surface §2 (exception du proxy pour la seule TV choisie).

**Files :**
- Create : `core/core/src/tv/{mod,ssdp,upnp}.rs`, fixtures `core/core/tests/fixtures/dlna/`
  (description de renderer, réponses SOAP).
- Modify : `core/core/Cargo.toml` (`roxmltree` : lecture XML sans écriture ni entités
  externes, Rust pur ; R18), `core/stream/src/proxy.rs` (`share_on_lan`, `close_lan`),
  `core/core/src/player.rs` (les commandes vont à la sortie active ; les événements de la TV
  reviennent comme ceux du lecteur), `core/core/src/events.rs` (`NowPlaying.output`,
  `Notice::TvRefused`), le pont, `fake_api.dart`.
- Test : `#[cfg(test)]` des modules, `core/stream/tests/proxy.rs`.

**Interfaces :**
- Produces :
  ```rust
  pub struct RendererView { pub id: String, pub name: String }        // id = UDN
  pub enum OutputTarget { Device, Tv { id: String, name: String } }
  pub enum RemoteOp { Play, Pause, SeekTo { ms: u64 }, Volume { percent: u8 } }
  pub struct RemoteState { pub playing: bool, pub position_ms: u64, pub volume: u8 }
  pub async fn tv_discover() -> Result<Vec<RendererView>, CoreError>; // M-SEARCH MediaRenderer:1, 3 s
  pub async fn set_output(target: OutputTarget) -> Result<(), CoreError>;  // reprend à la position courante sur la nouvelle sortie
  pub async fn remote(op: RemoteOp) -> Result<(), CoreError>;
  pub fn remote_states(sink: StreamSink<RemoteState>);               // une fois par seconde tant qu'une TV joue
  // stream::proxy
  impl Proxy { pub async fn share_on_lan(&self, token: &str, peer: IpAddr) -> std::io::Result<String>; pub fn close_lan(&self, token: &str); }
  ```
- Règles :
  - SSDP : M-SEARCH vers `239.255.255.250:1900`, `ST:
    urn:schemas-upnp-org:device:MediaRenderer:1` ; la description (`LOCATION`) est lue
    seulement si son hôte est l'IP qui a répondu ; l'app ne s'annonce jamais ;
  - SOAP : `AVTransport` (`SetAVTransportURI` avec un DIDL-Lite minimal, `Play`, `Pause`,
    `Seek REL_TIME`, `Stop`, `GetPositionInfo`, `GetTransportInfo`) et `RenderingControl`
    (`SetVolume`, `GetVolume`) ; `ConnectionManager.GetProtocolInfo` donne les formats
    acceptés ;
  - la TV reçoit une URL de `share_on_lan` : une seconde écoute sur l'adresse locale tournée
    vers la TV, qui ne répond qu'à l'IP de la TV choisie (toute autre IP : connexion
    fermée), avec un jeton propre à cette lecture ; arrêter la lecture sur la TV ou changer
    de sortie appelle `close_lan` ;
  - un format que `GetProtocolInfo` n'accepte pas → `Notice::TvRefused { title }` avant
    l'envoi, la lecture reste sur l'appareil (R18) ;
  - l'exécuteur TV émet `TrackStarted`, `Position` (sondage chaque seconde), `Paused`,
    `Resumed`, `Ended` (état `STOPPED` à moins de 2 s de la fin, ou `NO_MEDIA_PRESENT`) ; la
    suivante tenue est lancée par lui à la fin, comme le lecteur Dart ; la minuterie (Task 3)
    met la TV en pause, sans fondu ;
  - TV injoignable (3 sondages ratés) → sortie `Device`, en pause à la dernière position
    connue, `close_lan`.

- [ ] **Step 1 : tests qui échouent** (renderer simulé : un répondeur UDP sur `127.0.0.1`,
  l'adresse de recherche injectée en test, wiremock pour la description et le SOAP)
  ```rust
  #[tokio::test] async fn discover_lists_renderers_and_ignores_foreign_locations()
  #[tokio::test] async fn playing_on_tv_sends_the_lan_url_and_plays()
  #[tokio::test] async fn lan_listener_answers_only_the_chosen_tv()   // stream : pair autorisé → 200 ; autre IP → fermé
  #[tokio::test] async fn unsupported_format_is_refused_before_sending()
  #[tokio::test] async fn tv_end_starts_the_held_next_and_reports_it()
  #[tokio::test] async fn tv_lost_falls_back_paused_and_closes_lan_listener()
  #[tokio::test] async fn switching_back_resumes_on_the_device_at_the_tv_position()
  ```
- [ ] **Step 2 : implémenter.**
- [ ] **Step 3 : vérifier** (vérifications globales).
- [ ] **Step 4 : commit** : `feat(core): lire sur la TV (DLNA, proxy ouvert à la seule TV choisie)`.

### Task 20 : lire sur la TV — sorties du lecteur, télécommande, AirPlay

**Files :**
- Create : `app/lib/platform/tv.dart`, `app/macos/Runner/AirPlay.swift`,
  `app/android/app/src/main/kotlin/com/vehicoule/Multicast.kt`.
- Modify : `app/lib/platform/player.dart` (`PlayerAdapter` en mode distant),
  `app/lib/features/music/now_playing/now_playing_controller.dart` (menu de sortie),
  `app/lib/platform/lock_screen.dart` (les commandes suivent la sortie),
  `MainActivity.kt` (`com.vehicoule/multicast`), `AndroidManifest.xml`
  (`CHANGE_WIFI_MULTICAST_STATE`, `ACCESS_WIFI_STATE`), `AppDelegate.swift`
  (`com.vehicoule/airplay`), `app/macos/Runner/Info.plist` (`NSLocalNetworkUsageDescription`),
  ARB FR/EN.
- Test : `app/test/platform/player_test.dart`, `app/test/features/now_playing_test.dart`.

**Interfaces :**
- Consumes : l'API de la Task 19, `NowPlaying.output`.
- Produces :
  ```dart
  Future<List<RendererView>> findTvs();          // Android : MulticastLock pris le temps de tvDiscover, puis rendu
  Future<void> showAirPlayPicker(Rect anchor);   // macOS : AVRoutePickerView (R19)
  // PlayerAdapter
  void attachRemote(Stream<RemoteState> states);  // sortie TV : position, playing et volume viennent de la TV ;
                                                  // play, pause, seek, setVolume appellent remote(op) ; retour à Device : le backend reprend la main
  ```
- Règles : la sortie du lecteur (spec UI §5.5 bloc 1) liste « Sur cet appareil », puis les
  TV trouvées (recherche à l'ouverture du menu, `VLoading` pendant 3 s), puis sur macOS
  « AirPlay… » ; sur la TV, l'en-tête montre son nom, le téléphone devient la télécommande
  (⏯, ±10 s, suivant, volume de la TV par `VVolume`) ; l'écran verrouillé et la
  notification pilotent la TV ; `Notice::TvRefused` → `showVSnack` (« Cette TV ne lit pas ce
  format. »).

- [ ] **Step 1 : tests qui échouent**
  ```dart
  test('remote mode drives position and sends play, pause, seek and volume to the core', ...);
  test('back on the device the backend takes over at the tv position', ...);
  testWidgets('output menu lists this device, then tvs, then airplay on macOS', ...);
  testWidgets('a refused format shows its snackbar', ...);
  ```
- [ ] **Step 2 : implémenter.**
- [ ] **Step 3 : vérifier** (vérifications globales) ; sur l'émulateur ou le téléphone, avec
  une TV DLNA du réseau (ou un renderer logiciel, par exemple gmrender-resurrect, lancé par
  l'utilisateur) : un titre passe sur la TV, ⏯ et le volume répondent, l'arrêt ferme
  l'écoute ; sur macOS, le sélecteur AirPlay s'ouvre (une enceinte AirPlay, si
  l'utilisateur en a une : sinon Pending).
- [ ] **Step 4 : commit** : `feat(app): lire sur la TV (sorties du lecteur, télécommande), AirPlay sur macOS`.
