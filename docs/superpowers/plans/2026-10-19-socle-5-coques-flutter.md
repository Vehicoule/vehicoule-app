# Socle 5 — Coques Flutter mobile et desktop : plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** l'app utilisable au quotidien sur Android et macOS : système de design, FR/EN,
adaptateurs de plateforme (lecteur, écran verrouillé, téléchargements en arrière-plan,
réseau, mises à jour), tous les écrans musique, deux coques, tests, CI, validation finale
des critères de la spec.

**Architecture :** Dart affiche et exécute. Les écrans de `features/music/` sont écrits une
fois et partagés ; `shell_mobile/` et `shell_desktop/` ne fournissent que navigation, mise
en page et comportements (survol, clavier, barre de titre). Pas de gestionnaire d'état :
Rust pousse `QueueView`, `NowPlaying`, `LibraryChanged`… en flux, les widgets les lisent
avec `StreamBuilder` ; les pages chargent leurs données par `FutureBuilder` et rechargent
sur `LibraryChanged`. Seul `platform/` parle aux plugins natifs.

**Tech Stack :** Flutter 3.47 (stable), Dart 3.13, go_router 18, media_kit 1.2.6 +
media_kit_libs_audio 1.0.7, audio_service 0.18.19, window_manager 0.5, connectivity_plus 7,
url_launcher 6, path_provider 2, material_3_expressive 1.1.7 (derrière `design/`), gen-l10n,
Kotlin (deux services Android).

**Spec :** `docs/superpowers/specs/2026-10-18-socle-musique-design.md` (v4), sections 1
(périmètre, critères), 2 (règles des coques), 3.1, 3.4, 3.6, 3.7, 4.6, 6, 7, 8, 12.
Rapport : « Reste à faire » (test sur téléphone). Prérequis : plan 4 (façade
`app/lib/bridge/`, squelette `app/`), plan 6 pour la validation finale.

## Global Constraints

- Dépôt `/Users/btw/Documents/repo/Vehicoule`, branche `socle-5-app`. Licence MPL-2.0.
  Commit = `git commit -s -m "<msg>" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"`.
- Versions de paquets **figées** (pas de `^`) dans `app/pubspec.yaml`.
- Dossiers (spec 2) : `app/lib/{bridge,design,l10n,platform,features/music,shell_mobile,shell_desktop}`.
  `bridge/` n'est jamais modifié à la main.
- `material_3_expressive` n'est importé **que** dans `app/lib/design/` ; les écrans
  n'importent pas `material` pour un composant que `design/` fournit. Un test le vérifie.
- Navigation : **go_router**. Coque choisie par `LayoutBuilder` : largeur ≥ **840 dp** →
  desktop (`NavigationRail` + barre de lecture en bas + barre de titre maison sur macOS via
  `window_manager`, `TitleBarStyle.hidden`) ; sinon mobile (`NavigationBar` en bas,
  mini-lecteur fixe au-dessus).
- Listes : `CustomScrollView` + `SliverAppBar` + `SliverList.builder` (paresseux ; une
  playlist de 10 000 titres défile sans tout charger : pages de 100 via l'API).
- Recherche : `SearchAnchor` / `SearchBar` M3.
- Lecteur plein écran : `DraggableScrollableSheet` ; `Slider` de progression branché sur
  `player.stream.position` côté Dart (Rust ne reçoit qu'une position toutes les ~10 s).
- Pochettes : `Image.file` sur le chemin rendu par `artworkFile` (cache Rust), jamais
  d'image réseau.
- Actions sur un titre : `MenuAnchor` (clic droit, bouton « … ») sur desktop, bottom sheet
  sur mobile. Erreurs discrètes : `SnackBar`.
- État : pas de Riverpod ni Bloc.
- Raccourcis desktop : `Espace` lecture/pause, `←`/`→` recul/avance de 10 s, `Cmd+F`
  (`Ctrl+F` hors macOS) recherche ; touches média via audio_service. Aucun raccourci
  quand un champ texte a le focus.
- Android : `applicationId app.vehicoule` ; service audio_service de type
  `mediaPlayback` ; service de téléchargement de premier plan de type `dataSync` avec
  notification de progression ; fichiers dans l'espace propre à l'app, aucune permission
  de stockage.
- Accessibilité : `Semantics`/`tooltip` sur chaque contrôle sans texte, taille de texte
  système respectée (pas de `textScaler` forcé), contrastes WCAG AA dans les tokens.
- FR et EN dès le départ (`gen-l10n`, ARB) ; aucun texte en dur dans les widgets.
- Télémétrie Dart : pas de `sentry_flutter`. Les erreurs Dart non rattrapées
  (`FlutterError.onError`, `PlatformDispatcher.instance.onError`) passent par
  `reportDartError` du cœur : un seul filtre, testé au plan 4. Limite connue : les
  plantages natifs Kotlin/Swift ne sont pas captés en v1 ; on ajoutera `sentry_flutter`
  s'ils apparaissent.
- Mesure du premier son : horodatage au tap, première position > 0 après le `Play`
  correspondant → `reportPerf(tapToFirstSoundMs)`.

## Review Focus

1. **Espace ou flèches tapés dans le champ de recherche sur desktop** : le texte reçoit la
   touche, la lecture ne se met pas en pause. → test `shortcuts_ignored_while_typing` (tâche 5).
2. **Texte système à 200 %** : aucun débordement sur l'accueil, la recherche, le
   mini-lecteur et le lecteur plein écran. → test `no_overflow_at_text_scale_2` (tâche 8).
3. **Erreur du lecteur qui cache un 403 dans un message mpv** : elle doit arriver à Rust
   comme `Forbidden` pour déclencher la nouvelle résolution, pas comme `Other`.
   → test `classify_player_errors` (tâche 3).
4. **Changement de piste automatique de mpv après un `EnqueueNext`** : l'adaptateur envoie
   `TrackStarted` avec l'entrée préchargée, sinon Rust croit encore jouer l'ancienne piste.
   → test `auto_advance_reports_preloaded_entry` (tâche 3).
5. **Premier lancement hors ligne** (feed officiel injoignable) : l'accueil explique qu'il
   faut du réseau pour installer les sources, l'app ne reste pas bloquée sur un indicateur.
   → test `onboarding_offline_explains_and_continues` (tâche 7).

---

### Task 1 : système de design (`design/`)

**Files :**
- Create : `app/lib/design/{tokens,theme,components}.dart`, `app/lib/design/design.dart` (exports)
- Modify : `app/pubspec.yaml`
- Test : `app/test/design/contrast_test.dart`, `app/test/design/imports_test.dart`

**Interfaces :**
- Produces :
  ```dart
  ThemeData vTheme(Brightness b);                        // M3 officiel + nos tokens réglés sur M3E
  abstract final class VTokens { static const spacing…; static const radius…; static const motion… }
  class VArtwork extends StatelessWidget { const VArtwork({required String itemId, required double size, String? semanticLabel}); } // Image.file via artworkFile, repli icône
  class VTrackTile extends StatelessWidget { const VTrackTile({required TrackView track, VoidCallback? onTap, Widget? trailing, bool selected = false}); }
  class VCollectionCard extends StatelessWidget { const VCollectionCard({required CollectionView item, VoidCallback? onTap}); }
  class VSectionHeader extends StatelessWidget { const VSectionHeader(String title, {VoidCallback? onMore}); }
  class VEmptyState extends StatelessWidget { const VEmptyState({required IconData icon, required String message, Widget? action}); }
  class VLoading extends StatelessWidget {}             // indicateur M3E (material_3_expressive) si disponible
  void showVSnack(BuildContext c, String message);
  Future<T?> showVActions<T>(BuildContext c, {required List<VAction> actions, Offset? anchor}); // MenuAnchor sur desktop, bottom sheet sur mobile
  class VAction { const VAction(String label, IconData icon, VoidCallback onSelected); }
  ```

- [ ] **Step 1 : tests qui échouent**

```dart
test('token color pairs meet WCAG AA', ...);         // clair et sombre : onPrimary/primary, onSurface/surface, onSurfaceVariant/surface, onSecondaryContainer/secondaryContainer… ≥ 4.5:1 (formule de luminance relative WCAG 2.1)
test('only design/ imports material_3_expressive', ...); // parcourt lib/**.dart hors lib/design/ et lib/bridge/ : aucun import de material_3_expressive
testWidgets('VTrackTile exposes a semantic label', ...); // titre + artistes lus par Semantics
```
- [ ] **Step 2 : vérifier l'échec** — `cd app && flutter test test/design` → FAIL.
- [ ] **Step 3 : implémenter.** `material_3_expressive` seulement pour ce que M3 officiel
  n'a pas (indicateur de chargement expressif, formes) ; tout le reste en M3 officiel.
- [ ] **Step 4 : vérifier** → PASS.
- [ ] **Step 5 : commit** — `feat(app): système de design`.

### Task 2 : traductions FR / EN et messages d'erreur

**Files :**
- Create : `app/l10n.yaml`, `app/lib/l10n/app_fr.arb`, `app/lib/l10n/app_en.arb`,
  `app/lib/l10n/errors.dart`
- Test : `app/test/l10n/l10n_test.dart`

**Interfaces :**
- Produces : `AppLocalizations` (généré, modèle `app_fr.arb`) ;
  `String errorMessage(AppLocalizations l, CoreError e)` — un message par variante :
  `network`, `providerWall`, `rateLimited`, `budgetExceeded`, `notFound`, `expired`,
  `internal`, `offline`, `noPlugin(capability)` (pour `resolve` : « Aucune source de
  lecture installée » + renvoi vers « Ajouter un dépôt », spec 4.6.5).

- [ ] **Step 1 : tests qui échouent**

```dart
test('fr and en arb files have the same keys', ...);
test('every CoreError variant has a message in both languages', ...);
```
- [ ] **Step 2 : vérifier l'échec** → FAIL.
- [ ] **Step 3 : écrire les ARB** (au fil des tâches suivantes, chaque texte ajouté l'est
  dans les deux fichiers ; ce test reste le garde-fou).
- [ ] **Step 4 : vérifier** → PASS.
- [ ] **Step 5 : commit** — `feat(app): traductions FR/EN et messages d'erreur`.

### Task 3 : lecteur (`platform/player.dart`)

**Files :**
- Create : `app/lib/platform/player.dart`, `app/lib/platform/player_errors.dart`
- Test : `app/test/platform/player_test.dart`, `app/test/platform/player_errors_test.dart`

**Interfaces :**
- Consumes : `playerCommands()`, `playerEvent(e:)` (synchrone, `void` : appelé dans l'ordre
  des événements, jamais attendu), `reportPerf` (plan 4).
- Produces :
  ```dart
  abstract interface class MediaBackend {        // media_kit en vrai, faux dans les tests
    Future<void> open(List<MediaSource> items, {required bool play});
    Future<void> add(MediaSource m); Future<void> removeAt(int index);
    Future<void> seek(Duration d); Future<void> play(); Future<void> pause(); Future<void> playOrPause();
    Future<void> setVolume(double percent);
    Stream<int> get index; Stream<Duration> get position; Stream<Duration> get duration;
    Stream<bool> get playing; Stream<bool> get completed; Stream<String> get errors;
  }
  class MediaSource { final String uri; final Map<String, String> headers; }
  class PlayerAdapter {
    PlayerAdapter(MediaBackend backend);
    void start();                                  // écoute playerCommands, émet les PlayerEvent
    Stream<Duration> get position;                 // pour le Slider et les paroles
    Stream<Duration?> get duration; Stream<bool> get playing;
    Future<void> togglePlay(); Future<void> seek(Duration d); Future<void> seekBy(Duration delta);
    void markTap();                                // horodatage pour la mesure du premier son
  }
  PlayerErrorKind classifyPlayerError(String mpvMessage);
  double gainToVolume(double gainDb);              // 100 × 10^(gain/20)
  ```
- Contrat avec Rust (plan 4, `player.rs`) : le lecteur tient une piste courante et au plus
  une suivante. `Play` remplace les deux (la suivante tenue est abandonnée) ;
  `EnqueueNext` et `ReplaceNext` remplacent la suivante tenue (ou la posent s'il n'y en a
  pas) ; `ClearNext` l'abandonne. À la fin de la courante, le lecteur enchaîne seul sur la
  suivante tenue et envoie `TrackStarted` pour elle. Sens des événements :
  `TrackStarted` = piste chargée (aussi pour un chargement en pause, `autoplay: false`) ;
  `Resumed` = le son part (après un `Play` en lecture aussi) ; `Paused` = le son
  s'arrête. Rust ne déduit « en lecture » que de `Resumed`/`Paused` (et `Ended`/`Error`,
  après lesquels le lecteur est arrêté) ; après une `Error`, Rust n'envoie rien s'il n'y a
  rien à rejouer (erreur réseau : le lecteur reste arrêté, l'utilisateur relance).
- Règles : `Play` → `open([source], play: autoplay)` puis `seek(position)` ;
  `EnqueueNext`/`ReplaceNext` → `removeAt(courant + 1)` s'il y a une suivante, puis `add` ;
  `ClearNext` → `removeAt(courant + 1)` s'il y en a une ; `Stop` → `pause` + `open([])`.
  L'adaptateur tient la liste `index mpv → entry` et le gain de chaque entrée (appliqué au
  changement d'index). Événements : `TrackStarted` à chaque changement d'index,
  `Duration` dès connue, `Position` toutes les 10 s pendant la lecture et à chaque pause,
  `Paused`/`Resumed`, `Seeked`, `Ended` quand `completed` sans suivante, `Error` classée
  avec `positionMs` = position au moment de l'erreur (un 403 reprend là ; en pause, Rust
  renvoie un `Play` sans autoplay).

- [ ] **Step 1 : tests qui échouent** (avec un `FakeBackend` et un flux de commandes de test)

```dart
test('play opens the source at the given position', ...);
test('auto_advance_reports_preloaded_entry', ...);   // EnqueueNext(e2) puis index 0→1 → TrackStarted(e2)
test('replace_next swaps the queued source', ...);
test('position is reported every 10s and on pause', ...); // fakeAsync
test('gain is applied when the track changes', ...);  // gainToVolume(-6) ≈ 50.1
test('classify_player_errors', ...);                  // messages relevés à l'étape 1 (probes/android-playback/tool/check_log.dart) : "...HTTP error 403 Forbidden" → forbidden ; "Failed to open ... Connection refused" / "timed out" → network ; "Failed to recognize file format" → decode ; autre → other
test('first position after a tap reports tap-to-first-sound', ...);
```
- [ ] **Step 2 : vérifier l'échec** → FAIL.
- [ ] **Step 3 : implémenter** (`MediaKitBackend` = `Player()` de media_kit ; en-têtes
  passés par `Media(uri, httpHeaders: …)`).
- [ ] **Step 4 : vérifier** → PASS.
- [ ] **Step 5 : commit** — `feat(app): adaptateur du lecteur (commandes Rust, événements)`.

### Task 4 : plateforme (écran verrouillé, téléchargements, réseau, chemins, mises à jour)

**Files :**
- Create : `app/lib/platform/{lock_screen,downloads_service,network,paths,updates,errors}.dart`
- Create : `app/android/app/src/main/kotlin/app/vehicoule/DownloadService.kt`,
  `app/android/app/src/main/kotlin/app/vehicoule/Installer.kt`,
  `app/android/app/src/main/res/xml/file_paths.xml`
- Modify : `app/android/app/src/main/AndroidManifest.xml`, `MainActivity.kt`,
  `app/macos/Runner/*.entitlements` (réseau sortant)
- Test : `app/test/platform/lock_screen_test.dart`, `app/test/platform/downloads_service_test.dart`

**Interfaces :**
- Produces :
  ```dart
  Future<AppConfig> appConfig();                     // path_provider : data = applicationSupport, cache = applicationCache,
                                                     // downloads = Android getExternalStorageDirectory()/music, macOS applicationSupport/downloads ; région = pays de la locale
  class LockScreen extends BaseAudioHandler { LockScreen(PlayerAdapter p); } // play/pause/seek → adaptateur ; skipToNext/Previous → skipNext()/previous() ; mediaItem depuis nowPlaying() (artUri file://)
  class DownloadsService { void start(); }           // canal app.vehicoule/downloads : start/update(title, done, total)/stop selon downloadProgress() ;
                                                     // titres par tracks(ids) (plan 4)
  class Network { void start(); }                    // connectivity_plus → setOnline
  Future<void> installUpdate(UpdateInfo u);          // Android : downloadUpdate puis canal app.vehicoule/update install(path) ; macOS : url_launcher(pageUrl)
  void installErrorHooks();                          // FlutterError.onError et PlatformDispatcher.onError → reportDartError
  ```
- Manifeste : `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`,
  `FOREGROUND_SERVICE_DATA_SYNC`, `POST_NOTIFICATIONS`, `REQUEST_INSTALL_PACKAGES`,
  `INTERNET`, `WAKE_LOCK` ; service audio_service `foregroundServiceType="mediaPlayback"` ;
  `DownloadService` `foregroundServiceType="dataSync"` ; `FileProvider` pour l'APK.
  `DownloadService` (service de premier plan) : actif seulement tant qu'un téléchargement
  est `Running` (pas pour `Queued` : hors ligne, la file attend sans service), arrêté sinon ; notification de progression mise à jour au rythme des événements
  (≤ 2/s, déjà limité par Rust).

- [ ] **Step 1 : tests qui échouent**

```dart
test('lock screen skip goes through Rust, play/pause stays local', ...);
test('now playing becomes a media item with a file artUri', ...);
test('downloads service starts on first running download and stops when idle', ...); // canal de méthode simulé
```
- [ ] **Step 2 : vérifier l'échec** → FAIL.
- [ ] **Step 3 : implémenter.**
- [ ] **Step 4 : vérifier** → PASS ; sur l'émulateur, `flutter run` puis un téléchargement
  lancé et l'app mise en arrière-plan : la notification de progression reste et le fichier
  se termine.
- [ ] **Step 5 : commit** — `feat(app): écran verrouillé, téléchargements en arrière-plan, réseau, mises à jour`.

### Task 5 : routes et coques

**Files :**
- Create : `app/lib/router.dart`, `app/lib/shell_mobile/{mobile_shell,mini_player}.dart`,
  `app/lib/shell_desktop/{desktop_shell,player_bar,title_bar,shortcuts}.dart`,
  `app/lib/features/music/now_playing/now_playing_sheet.dart` (squelette, rempli tâche 6)
- Modify : `app/lib/main.dart`
- Test : `app/test/shell/shell_test.dart`

**Interfaces :**
- Produces :
  ```dart
  GoRouter buildRouter();   // StatefulShellRoute.indexedStack, branches : /home, /search, /library
                            // routes : /album/:id, /artist/:id, /playlist/:id, /queue, /settings, /settings/plugins,
                            //          /settings/feeds/add, /settings/diagnostics, /onboarding (redirect tant que onboarding().done == false)
  class AdaptiveShell extends StatelessWidget { const AdaptiveShell({required StatefulNavigationShell shell}); } // LayoutBuilder, seuil 840
  class DesktopShortcuts extends StatelessWidget { const DesktopShortcuts({required Widget child, required PlayerAdapter player, required VoidCallback focusSearch}); }
  ```
- `main.dart` : `RustLib.init()`, `installErrorHooks()`, `initApp(await appConfig())`,
  `AudioService.init(LockScreen)`, `windowManager` (desktop), abonnements de
  `PlayerAdapter`, `LockScreen`, `Network`, `DownloadsService`, **puis `start()`** (la
  restauration de la file et la reprise des téléchargements arrivent sur des flux déjà
  écoutés), puis `runApp` ; après le premier frame : `checkUpdates(force: false)` (jamais
  bloquant). Une mise à jour arrive par `Notice.updateAvailable(UpdateInfo)`, seul signal
  affiché.

- [ ] **Step 1 : tests qui échouent** (API simulée, voir tâche 8 pour `FakeApi`)

```dart
testWidgets('narrow width uses NavigationBar and mini player', ...);   // 400 dp
testWidgets('wide width uses NavigationRail and player bar', ...);     // 1200 dp
testWidgets('space toggles playback on desktop', ...);
testWidgets('shortcuts_ignored_while_typing', ...);                    // focus dans SearchBar, Espace → texte " ", lecteur inchangé
testWidgets('cmd+f focuses search', ...);
testWidgets('first launch redirects to onboarding', ...);
```
- [ ] **Step 2 : vérifier l'échec** → FAIL.
- [ ] **Step 3 : implémenter.** Barre de titre macOS : `TitleBarStyle.hidden`, zone
  `DragToMoveArea`, place laissée aux boutons de fenêtre natifs à gauche.
- [ ] **Step 4 : vérifier** → PASS.
- [ ] **Step 5 : commit** — `feat(app): routes go_router, coques mobile et desktop, raccourcis`.

### Task 6 : écrans d'écoute (accueil, recherche, pages, lecteur, file, paroles)

**Files :**
- Create : `app/lib/features/music/home/home_page.dart`,
  `features/music/search/search_page.dart`,
  `features/music/entity/{album_page,artist_page,playlist_page}.dart`,
  `features/music/now_playing/{now_playing_sheet,lyrics_view}.dart`,
  `features/music/queue/queue_page.dart`,
  `features/music/actions/track_actions.dart` (like, lire ensuite, ajouter à la file,
  ajouter à une playlist, télécharger, « ce n'est pas le bon morceau »)
- Test : `app/test/features/{home,search,entity,now_playing,actions}_test.dart`

**Interfaces :**
- Consumes : API du plan 4 (`home`, `search`, `suggest`, `entity`, `play`, `queueOp`,
  `queueStates`, `nowPlaying`, `lyrics`, `fixMatch`, `chooseMatch`, `setLiked`, `download`,
  `addToPlaylist`, `notices`, `hasResolver`), `PlayerAdapter.position`, `design/`.
- Règles : sans résolveur (`hasResolver() == false`), le bouton lecture ouvre une
  explication avec un lien vers « Ajouter un dépôt » ; hors ligne, la recherche affiche un
  message et non une erreur ; `Notice.skipped` → `SnackBar` discrète ; paroles
  synchronisées : ligne active = dernière ligne dont `startMs ≤ position`, défilement
  automatique ; pages paginées par 100 (`entity(cursor)`) au défilement. Bouton lecture
  sans piste chargée (après un arrêt sur erreurs, ou `NowPlaying.track` sans `Play` reçu) :
  `queueOp(QueueOp.jumpTo(currentEntry))`. Réordonner la file :
  `QueueOp.move(entry, after: voisin du dessus)` (`null` = juste après la courante), sans
  calcul d'index. `NowPlaying.source`/`mime` alimentent « détails du flux ».

- [ ] **Step 1 : tests qui échouent**

```dart
testWidgets('search shows suggestions then sectioned results', ...);
testWidgets('search offline shows the offline message', ...);
testWidgets('playlist page builds lazily', ...);           // 10 000 titres simulés : moins de 50 VTrackTile construits
testWidgets('tapping a track plays it with its context', ...); // play(items, start, PlayContext(kind: "album"...))
testWidgets('play without resolver explains why', ...);
testWidgets('synced lyrics highlight the current line', ...);
testWidgets('not the right track lists candidates and pins the choice', ...);
testWidgets('desktop actions use a menu, mobile a bottom sheet', ...);
```
- [ ] **Step 2 : vérifier l'échec** → FAIL.
- [ ] **Step 3 : implémenter.**
- [ ] **Step 4 : vérifier** → PASS.
- [ ] **Step 5 : commit** — `feat(app): accueil, recherche, pages, lecteur, file, paroles`.

### Task 7 : bibliothèque, réglages, sources, premier lancement

**Files :**
- Create : `app/lib/features/music/library/{library_page,playlists_page,downloads_page,history_page}.dart`,
  `features/music/library/import_dialog.dart`,
  `features/music/settings/{settings_page,plugins_page,add_feed_page,diagnostics_page}.dart`,
  `features/music/onboarding/onboarding_page.dart`, `features/music/updates/update_banner.dart`
- Test : `app/test/features/{library,settings,onboarding}_test.dart`

**Interfaces :**
- Consumes : API du plan 4 (`likedTracks`, `liked`, `playlists`, `playlistEntries`,
  `createPlaylist`, `renamePlaylist`, `deletePlaylist`, `moveInPlaylist`,
  `removeFromPlaylist`, `importPlaylist`, `downloads`, `cancelDownload`, `history`,
  `searchLibrary`, `libraryChanges`, `settings`, `setSettings`, `installedPlugins`,
  `capabilityOrder`, `setCapabilityOrder`, `previewFeed`, `addFeed`, `removeFeed`,
  `refreshFeeds`, `onboarding`, `finishOnboarding`, `diagnostics`, `exportLogs`,
  `checkUpdates`, `feeds`, `tracks`, `hasResolver`), `installUpdate`.
- Règles : premier lancement (spec 4.6) = 1. ce qu'est l'app, livrée sans source de
  streaming ; 2. installation du feed officiel (`refreshFeeds`, progression, réessai si
  hors ligne) ; 3. « Ajouter un dépôt » facultatif ; 4. télémétrie : deux boutons, **aucun
  pré-sélectionné**, impossible de continuer sans choisir. Après `refreshFeeds`, l'étape 2
  décide du réessai par `hasResolver()` (un feed en échec est journalisé, pas levé). Ajout d'un dépôt : URL + clé
  publique → `previewFeed` → empreinte, domaines déclarés et capacités affichés → bouton
  d'accord explicite → `addFeed`. Ordre des capacités : liste réordonnable par capacité.
  Sources : `feeds()` (nom, officiel, nombre de plugins, empreinte) ; `removeFeed(url)`.
  Import : `ImportResult.truncated` → mention « playlist tronquée à 50 pages ».
  Réglages : « Rechercher une mise à jour » = `checkUpdates(force: true)`.
  « Envoyer un rapport » : `exportLogs` vers un fichier du dossier cache, puis Dart
  l'enregistre ou le partage (sélecteur système : les URI `content://` d'Android ne sont
  pas des chemins pour Rust), puis ouverture de
  `https://github.com/Vehicoule/vehicoule/issues/new` sans aucune donnée dans l'URL.

- [ ] **Step 1 : tests qui échouent**

```dart
testWidgets('playlist reorder calls moveInPlaylist with the new neighbour', ...);
testWidgets('import shows progress then opens the new playlist', ...);
testWidgets('local library search shows fuzzy hits', ...);
testWidgets('telemetry choice has no default and blocks continue', ...);
testWidgets('onboarding_offline_explains_and_continues', ...);
testWidgets('adding a feed requires seeing fingerprint and domains', ...);
testWidgets('report never puts data in the issue URL', ...);  // URL ouverte == URL fixe
```
- [ ] **Step 2 : vérifier l'échec** → FAIL.
- [ ] **Step 3 : implémenter.**
- [ ] **Step 4 : vérifier** → PASS.
- [ ] **Step 5 : commit** — `feat(app): bibliothèque, réglages, sources, premier lancement`.

### Task 8 : tests de démarrage par coque, accessibilité, CI, nettoyage

**Files :**
- Create : `app/test/fakes/fake_api.dart`, `app/integration_test/startup_mobile_test.dart`,
  `app/integration_test/startup_desktop_test.dart`, `app/test/a11y_test.dart`,
  `.github/workflows/ci.yml`
- Delete : `probes/` (remplacé par le socle, spec de l'étape 1)
- Create : `TRADEMARK.md` (spec 12 : nom et logo réservés, les forks prennent un autre nom)
- Test : les fichiers ci-dessus

**Interfaces :**
- Produces : `class FakeApi extends Fake implements RustLibApi` (méthodes générées par
  flutter_rust_bridge, données fictives : 3 titres, 1 album, flux de commandes simulés),
  branché par `RustLib.initMock(api: FakeApi())`.

- [ ] **Step 1 : tests qui échouent**

```dart
// startup_mobile_test.dart (taille 400×800) et startup_desktop_test.dart (1280×800)
testWidgets('launch, search fake data, play', ...);   // l'accueil s'affiche, recherche "halo", tap → FakeApi a reçu play(...) et le mini-lecteur / la barre affiche le titre
// a11y_test.dart, sur accueil, recherche, lecteur plein écran, réglages, dans les deux coques :
testWidgets('meets accessibility guidelines', ...);   // androidTapTargetGuideline, labeledTapTargetGuideline, textContrastGuideline
testWidgets('no_overflow_at_text_scale_2', ...);       // MediaQuery textScaler 2.0 : aucune exception de débordement
```
- [ ] **Step 2 : vérifier l'échec** → FAIL.
- [ ] **Step 3 : implémenter les corrections** que ces tests révèlent.
- [ ] **Step 4 : CI** (`ci.yml`) : job Rust (`cargo test` + clippy du workspace `core/`, cible
  `wasm32-wasip2` installée) ; job Android (`flutter test`, `flutter build apk --release
  --target-platform android-arm64`, APK renommé `vehicoule-<version>-android-arm64-v8a.apk` +
  `.sha256` en artefact) ; job macOS (`flutter test`, `flutter test integration_test -d macos`,
  `flutter build macos`) ; compilation seule : `flutter build ios --no-codesign`,
  `flutter build windows`, `flutter build linux` (chacun sur son runner).
- [ ] **Step 5 : vérifier** — `flutter test` → PASS ; `flutter test integration_test -d macos` → PASS ;
  `git rm -r probes` et le README racine mis à jour (plus de mention des sondes).
- [ ] **Step 6 : commit** — `test(app): démarrage par coque, accessibilité ; CI ; retrait des sondes`.

### Task 9 : validation finale sur appareils (manuelle, après le plan 6)

**Files :**
- Create : `docs/superpowers/reports/2026-xx-socle-validation.md`

- [ ] **Step 1 : téléphone Android de l'utilisateur, Wi-Fi** : 1 h écran éteint sans
  coupure (critère 4), avec une file de 16 titres non téléchargés ; noter les écarts entre
  titres (attendu : imperceptible grâce au préchargement, contre 1,5 s mesuré sans).
- [ ] **Step 2 : même test en 4G**, puis app tuée par le système : la file revient en pause
  à la même position au relancement.
- [ ] **Step 3 : premier son** sur 20 titres non préchargés, résolution comprise, depuis
  `diagnostics()` / `tapToFirstSoundMs` : médiane < 2 s (critère 2).
- [ ] **Step 4 : téléchargement de 10 titres app en arrière-plan**, puis mode avion : ils
  se lisent, les autres sont sautés et signalés (spec 3.6).
- [ ] **Step 5 : macOS** : raccourcis, touches média, barre de titre, une journée d'usage.
- [ ] **Step 6 : rapport** (mesures, constructeur et modèle du téléphone, écarts), puis
  démarrage des deux semaines d'usage quotidien (critère 1). Commit —
  `docs: validation du socle sur appareils`.
