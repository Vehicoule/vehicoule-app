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
url_launcher 6, path_provider 2, material_ui 1.8.0, material_3_expressive 1.2.0 (derrière
`design/`), dynamic_color (source « Système »), gen-l10n,
Kotlin (deux services Android).

**Spec :** `docs/superpowers/specs/2026-10-23-socle-ui-design.md` (interface : identité,
composants, écrans) ; `docs/superpowers/specs/2026-10-18-socle-musique-design.md` (v4), sections 1
(périmètre, critères), 2 (règles des coques), 3.1, 3.4, 3.6, 3.7, 4.6, 6, 7, 8, 12.
Rapport : « Reste à faire » (test sur téléphone). Prérequis : plan 4 (façade
`app/lib/bridge/`, squelette `app/`) ; plan 7 avant les tâches 6 et 7 ; plan 6 pour la
validation finale.

## Global Constraints

- Dépôt `/Users/btw/Documents/repo/Vehicoule`, branche `socle-5-app`. Licence MPL-2.0.
  Commit = `git commit -s -m "<msg>" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"`.
- Versions de paquets **figées** (pas de `^`) dans `app/pubspec.yaml`.
- Dossiers (spec 2) : `app/lib/{bridge,design,l10n,platform,features/music,shell_mobile,shell_desktop}`.
  `bridge/` n'est jamais modifié à la main.
- `package:flutter/material.dart` n'est importé nulle part : `material_ui` le remplace.
  `material_3_expressive` n'est importé **que** dans `app/lib/design/` ; les écrans passent
  par `design/`. Aucun nombre d'espacement hors des tokens. Des tests le vérifient (tâche 1).
- Navigation : **go_router**. Coque choisie par `LayoutBuilder` (spec UI §4) :
  - largeur ≥ **840 dp** → desktop : rail M3E permanent, barre de titre maison sur macOS via
    `window_manager` (`TitleBarStyle.hidden`). En dessous de **1000 dp**, la barre de lecture
    est ancrée en bas ; à partir de 1000 dp, c'est le panneau « en lecture » en side sheet à
    droite ;
  - sinon mobile : barre de navigation M3E (Accueil, Explorer, Bibliothèque, Réglages), ☰ qui
    ouvre le rail déplié en modal, mini-lecteur flottant au-dessus.
- Listes : `CustomScrollView` + `SliverAppBar` + `SliverList.builder` (paresseux ; une
  playlist de 10 000 titres défile sans tout charger : pages de 100 via l'API).
- Recherche : search bar et search view M3E de `design/`. Suggestions pendant la frappe,
  résultats à la validation seulement (spec UI §6.2).
- Lecteur plein écran : `DraggableScrollableSheet` ; `Slider` de progression branché sur
  `player.stream.position` côté Dart (Rust ne reçoit qu'une position toutes les ~10 s).
- Pochettes : `Image.file` sur le chemin rendu par `artworkFile` (cache Rust), jamais
  d'image réseau.
- Actions sur un titre : le menu expressif `showVMenu` (appui long, clic droit, ⋮), le même
  sur les deux coques. Erreurs discrètes : `showVSnack`.
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
2. **Texte système à 200 %** : aucun débordement sur l'accueil, Explorer, le
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
- Create :
  - `app/lib/design/{design,tokens,theme,color,typography,motion,symbols}.dart` ;
  - `app/lib/design/components/{artwork,artwork_ring,track_row,menu,side_sheet,shelf,loading,empty_state,snack}.dart` ;
  - `app/assets/fonts/` : Google Sans Flex variable (axes `opsz`, `wght`, `ROND`), Noto Sans
    JP variable, Material Symbols Rounded variable (`FILL`, `wght`).
- Modify : `app/pubspec.yaml` (`material_ui: 1.8.0`, `material_3_expressive: 1.2.0`,
  polices déclarées).
- Test : `app/test/design/{contrast,imports,spacing,color,track_row,menu,motion}_test.dart`.

**Interfaces :**
- Produces :
  ```dart
  // tokens.dart — valeurs de la spec UI §2.7 et §5.1
  abstract final class VSpace { static const s4 = 4.0, s8 = 8.0, s12 = 12.0, s16 = 16.0, s24 = 24.0, s32 = 32.0;
    static const marginCompact = 16.0, marginWide = 24.0, sectionGap = 24.0, cardGap = 8.0; }
  abstract final class VSize { static const trackRow = 56.0, trackArt = 44.0, trackArtRadius = 12.0, menuTarget = 48.0, shelfCard = 108.0; }
  // color.dart
  enum ColorSource { nowPlaying, system, preset }
  Color pastelSeed(Color raw);                 // HCT : chroma plafonnée à 48, teinte gardée
  Future<Color?> seedFromArtwork(String path);  // Isolate.run, QuantizerCelebi sur l'image réduite à 112 px ; cache LRU de 64 chemins
  // theme.dart
  ThemeData vTheme({required Brightness brightness, required Color seed, bool pureBlack = false}); // M3ETheme + nos réglages ; pureBlack : surfaces sombres à 0
  // typography.dart : titres ROND 100, texte courant ROND 0, repli Noto Sans JP
  // motion.dart
  bool reduceMotion(BuildContext c);          // MediaQuery.disableAnimations
  // symbols.dart
  class VSymbol extends StatelessWidget { const VSymbol(IconData icon, {bool filled = false, double weight = 400, String? semanticLabel}); } // FILL / wght animés
  // components/
  class VArtwork extends StatelessWidget { const VArtwork({required String itemId, required double size, bool circle = false, double radius = VSize.trackArtRadius, String? semanticLabel}); } // Image.file via artworkFile, décodée à la taille affichée
  class VArtworkRing extends StatelessWidget { const VArtworkRing({required String itemId, required double size, required double progress, required bool playing}); } // anneau ondulé, plat en pause
  class VTrackRow extends StatelessWidget { const VTrackRow({required TrackView track, int? number, bool playing = false, bool offline = false, required VoidCallback onTap, required VoidCallback onPlayNext, required List<VAction> quick, required List<List<VAction>> groups}); }
  class VAction { const VAction(String label, IconData icon, VoidCallback onSelected); }
  Future<void> showVMenu(BuildContext c, {required Rect anchor, required List<VAction> quick, required List<List<VAction>> groups}); // menu expressif, mobile et desktop
  class VSideSheet extends StatelessWidget { const VSideSheet({required bool open, required Widget child, double width = 360}); } // side sheet standard, coplanaire
  class VShelf extends StatelessWidget { const VShelf({required String title, String? subtitle, VoidCallback? onMore, required double extent, required List<Widget> items}); } // rangée horizontale aimantée, hauteur fixe
  class VLoading extends StatelessWidget {}   // loading indicator M3E
  class VEmptyState extends StatelessWidget { const VEmptyState({required IconData icon, required String message, Widget? action}); }
  void showVSnack(BuildContext c, String message, {String? actionLabel, VoidCallback? onAction, Duration duration = const Duration(seconds: 4)});
  ```
- Règles (spec UI §2, §3, §5) :
  - **Couleur** : une seule source de teinte à la fois. Aucune extraction ailleurs que dans
    `seedFromArtwork`.
  - **Mouvement** : les ressorts viennent de `M3ETheme`. Avec `reduceMotion`, tout devient
    un fondu de 150 ms.
  - **Ligne de titre** : 56 de haut, marge 16, pochette 44 de rayon 12 (ronde pour un
    artiste) :
    - avec `number`, le numéro remplace la pochette dans le même carré ;
    - `playing` : titre en `primary` et égaliseur animé (`Semantics` « en lecture ») ;
    - `offline` : opacité 0,38, et le toucher affiche le message hors ligne ;
    - glisser à droite : `onPlayNext`, avec un fond tonal ;
    - appui long, clic droit ou ⋮ : `showVMenu`.
  - **Menu** : la rangée `quick` en groupe connecté, puis les groupes séparés par un espace.
    L'élément d'origine se soulève.

- [ ] **Step 1 : tests qui échouent**

```dart
test('token color pairs meet WCAG AA for every source', ...);   // seeds : 12 teintes HCT × {clair, sombre, sombre+pureBlack} ; onPrimary/primary, onSurface/surface, onSurfaceVariant/surface, onSecondaryContainer/secondaryContainer ≥ 4.5:1
test('pastelSeed caps chroma at 48', ...);
test('seedFromArtwork caches by path', ...);           // 2 appels, même chemin → 1 quantification
test('no material.dart import, material_3_expressive only in design/', ...); // lib/** hors bridge/ : aucun package:flutter/material.dart ; material_3_expressive seulement sous lib/design/
test('no spacing literals outside design/', ...);      // lib/features, lib/shell_* : aucun EdgeInsets/SizedBox/Gap avec un nombre littéral
testWidgets('VTrackRow: number replaces artwork, same height', ...);
testWidgets('VTrackRow: playing is primary with equalizer label', ...);
testWidgets('VTrackRow: offline dims and explains on tap', ...);
testWidgets('VTrackRow: swipe right calls onPlayNext', ...);
testWidgets('VTrackRow: long press and secondary tap open the menu', ...);
testWidgets('VTrackRow exposes a semantic label', ...);  // titre + artistes
testWidgets('reduce motion settles in one frame', ...);  // disableAnimations : menu et anneau sans animation en cours
```
- [ ] **Step 2 : vérifier l'échec** : `cd app && flutter test test/design` → FAIL.
- [ ] **Step 3 : implémenter.** Utiliser le composant M3E de `material_3_expressive` quand il
  existe. Sinon, le construire dans `components/` à partir des tokens.
- [ ] **Step 4 : vérifier** : `flutter test test/design` puis `flutter analyze` → PASS.
- [ ] **Step 5 : commit** : `feat(app): système de design M3E (tokens, couleur, typo, composants)`.

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
  `Resumed` = le son part (après un `Play` en lecture aussi) ; `Paused` = une pause
  de l'utilisateur ou du système (bouton, casque débranché, appel), jamais l'arrêt causé
  par une erreur ou par la fin de la piste : celui-là n'envoie que `Error` ou `Ended`
  (sinon un 403 en pleine lecture reprendrait en pause). Rust ne déduit « en lecture » que de `Resumed`/`Paused` (et `Ended`/`Error`,
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
  renvoie un `Play` sans autoplay ; 0 si le lecteur l'a perdue à l'ouverture : Rust garde
  la dernière connue).

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
- Create :
  - `app/lib/router.dart` ;
  - `app/lib/shell_mobile/{mobile_shell,mini_player,domain_rail}.dart` ;
  - `app/lib/shell_desktop/{desktop_shell,now_playing_pane,player_bar,title_bar,shortcuts}.dart` ;
  - `app/lib/features/music/now_playing/now_playing_sheet.dart` (squelette, rempli à la
    Task 6) ;
  - `app/lib/theme_controller.dart`.
- Modify : `app/lib/main.dart`.
- Test : `app/test/shell/{shell,mini_player,theme}_test.dart`.

**Interfaces :**
- Consumes : `design/` (Task 1) ; API des plans 4 et 7 (`nowPlaying`, `queueOp`, `stop`,
  `undoStop`, `uiPref`, `setUiPref`, `artworkFile`).
- Produces :
  ```dart
  GoRouter buildRouter();   // StatefulShellRoute.indexedStack, branches : /home, /explore, /library, /settings
                            // routes : /album/:id, /artist/:id, /playlist/:id, /category/:id, /library/liked, /library/downloaded,
                            //          /library/top, /library/history, /queue, /downloads, /settings/plugins, /settings/feeds/add,
                            //          /settings/diagnostics, /onboarding (redirect tant que onboarding().done == false)
  class AdaptiveShell extends StatelessWidget { const AdaptiveShell({required StatefulNavigationShell shell}); } // < 840 mobile ; ≥ 840 desktop ; panneau à droite ≥ 1000
  class DesktopShortcuts extends StatelessWidget { const DesktopShortcuts({required Widget child, required PlayerAdapter player, required VoidCallback focusSearch}); }
  class ThemeController extends ChangeNotifier { ThemeData light; ThemeData dark; ThemeMode mode; } // source ui.color_source, ui.preset, ui.pure_black, ui.theme ; nowPlaying → seedFromArtwork → pastelSeed, une fois par titre
  ```
- Règles (spec UI §4, §5.3, §2.2) :
  - **Mobile** :
    - barre de navigation M3E à 4 destinations (Accueil, Explorer, Bibliothèque, Réglages) ;
    - une grande app bar qui se replie, par onglet, avec ☰ à gauche ;
    - ☰ ouvre `domain_rail` : le rail déplié en modal, avec le domaine Musique, puis
      « Dépôts et plugins » (`/settings/plugins`) et « Téléchargements » (`/downloads`) ;
    - le mini-lecteur flottant est au-dessus de la barre.
  - **Mini-lecteur** : `VArtworkRing`, titre, artiste, like et pause.
    - glisser horizontalement de plus de 30 % de la largeur, ou lancer → titre
      suivant / précédent (`queueOp`) ;
    - vers le haut → le lecteur s'ouvre (`Hero` sur la pochette) ;
    - vers le bas → `stop()`, puis `showVSnack` « Lecture arrêtée », action « Annuler » →
      `undoStop()`, pendant 5 s ;
    - chaque geste a son équivalent dans le menu du mini-lecteur (« Arrêter »…).
  - **Desktop** :
    - rail permanent, replié ↔ déplié (`ui.rail_expanded`), avec le même contenu que le rail
      modal, plus les 4 destinations ;
    - barre de titre maison sur macOS (`TitleBarStyle.hidden`, `DragToMoveArea`, la place des
      boutons natifs est laissée à gauche) ;
    - largeur ≥ 1000 : `now_playing_pane` dans un `VSideSheet` à droite, repliable
      (`ui.now_playing_open`), avec les onglets File / Paroles / Infos ;
    - de 840 à 1000 : `player_bar` ancrée en bas.
  - **Thème** :
    - le changement de couleur se fait en fondu de 400 ms (`AnimatedTheme`), seulement quand
      le titre change ;
    - sans fondu avec `reduceMotion` ;
    - la source `system` lit `DynamicColorPlugin` sur Android et la couleur d'accent sur
      macOS.
- `main.dart` :
  1. `RustLib.init()`, `installErrorHooks()`, `initApp(await appConfig())`,
     `AudioService.init(LockScreen)`, `windowManager` (desktop) ;
  2. les abonnements de `PlayerAdapter`, `LockScreen`, `Network`, `DownloadsService` et
     `ThemeController` ;
  3. **puis `start()`**, pour que la restauration de la file et la reprise des
     téléchargements arrivent sur des flux déjà écoutés ;
  4. puis `runApp` ;
  5. après le premier frame : `checkUpdates(force: false)`, jamais bloquant.

  Une mise à jour n'est affichée que par `Notice.updateAvailable(UpdateInfo)`.

- [ ] **Step 1 : tests qui échouent** (API simulée : `FakeApi`, voir la Task 8)

```dart
testWidgets('narrow width uses the navigation bar and mini player', ...);   // 400 dp : 4 destinations
testWidgets('menu button opens the modal rail with domains and global sections', ...);
testWidgets('840–1000 uses the rail and the docked player bar', ...);        // 900 dp
testWidgets('≥ 1000 uses the rail and the now playing side sheet', ...);     // 1280 dp ; replier → ui.now_playing_open = "false"
testWidgets('mini player swipe left skips, right goes back', ...);
testWidgets('mini player swipe down stops and Annuler undoes', ...);        // stop() puis undoStop() ; sans Annuler en 5 s : un seul stop()
testWidgets('mini player swipe up opens the player', ...);
testWidgets('theme seed changes once per track, not per position', ...);    // 3 NowPlaying même titre → 1 seedFromArtwork
testWidgets('space toggles playback on desktop', ...);
testWidgets('shortcuts_ignored_while_typing', ...);                         // focus dans la search bar, Espace → texte " ", lecteur inchangé
testWidgets('cmd+f focuses search', ...);                                    // ouvre /explore et donne le focus au champ
testWidgets('first launch redirects to onboarding', ...);
```
- [ ] **Step 2 : vérifier l'échec** → FAIL.
- [ ] **Step 3 : implémenter.**
- [ ] **Step 4 : vérifier** → PASS.
- [ ] **Step 5 : commit** : `feat(app): routes, coques mobile et desktop, mini-lecteur à gestes, thème suivant la lecture`.

### Task 6 : écrans d'écoute (accueil, Explorer, pages, lecteur, file, paroles)

**Files :**
- Create :
  - `app/lib/features/music/home/{home_page,discovery_hero,feed_shelf}.dart` ;
  - `features/music/explore/{explore_page,suggestions_view,results_view,category_page}.dart` ;
  - `features/music/entity/{album_page,artist_page,playlist_page}.dart` ;
  - `features/music/now_playing/{now_playing_sheet,lyrics_view}.dart` ;
  - `features/music/queue/queue_page.dart` ;
  - `features/music/actions/track_actions.dart` : like, lire ensuite, ajouter à la file,
    ajouter à une playlist, télécharger, « ce n'est pas le bon morceau ».
- Test : `app/test/features/{home,explore,entity,now_playing,actions}_test.dart`.

**Interfaces :**
- Consumes :
  - API du plan 4 : `search`, `searchLibrary`, `entity`, `play`, `queueOp`, `queueStates`,
    `nowPlaying`, `lyrics`, `fixMatch`, `chooseMatch`, `setLiked`, `download`,
    `addToPlaylist`, `notices`, `hasResolver` ;
  - API du plan 7 : `homeFeed`, `refreshHome`, `playMix`, `browseCategories`,
    `browseCategory`, `suggest` (rend `SuggestionView`), `libraryChanges` (`Home`) ;
  - `PlayerAdapter.position` et `design/`.
- Règles :
  - **Accueil** (spec UI §6.1) :
    - « Bonsoir / Bonjour / Bonne nuit » selon l'heure locale, dans une grande app bar qui se
      replie ;
    - pas de `SliverList` de pages : un `CustomScrollView` d'étagères à hauteur fixe ;
    - `homeFeed(next)` est appelé à 2 étagères de la fin ;
    - les étagères qui chargent sont des squelettes de la même hauteur ;
    - tirer pour rafraîchir appelle `refreshHome()` ;
    - le titre d'une étagère se traduit depuis son `kind` et sa `seed` ;
    - `Discovery` : `discovery_hero` (un toucher sur ▶ appelle
      `play(tous les titres, 0, PlayContext(kind: "discovery"))`), puis des pages de 4
      `VTrackRow` qui s'aimantent, avec leur `reason` (« comme … ») ;
    - `Mixes` : carousel héros, un toucher appelle `playMix(id)` ;
    - `End` : la carte « Tu as fait le tour » vers `/explore` ;
    - une étagère entre en fondu avec une montée de 16 px la première fois qu'elle est
      construite (décalage de 40 ms par carte), et plus jamais ;
    - la carte héros se rétracte en sortant de l'écran (échelle 1 → 0,92 et parallaxe) ;
    - pas d'aimantation verticale.
  - **Explorer** (spec UI §6.2) :
    - au repos : la search bar, les catégories `featured` en deux grandes cartes, puis la
      grille « Parcourir » (2 colonnes sur mobile, de 3 à 5 sur desktop). La teinte d'une
      tuile est `pastelSeed` d'une teinte tirée du hash de `CategoryView.id` ;
    - pendant la frappe, la search view plein écran ne contient **que** :
      - « Dans ta bibliothèque » : `searchLibrary`, au plus 3 lignes, un toucher ouvre
        l'élément ;
      - puis « Suggestions » : `suggest`, après 150 ms sans frappe, la requête précédente
        ignorée. L'icône est l'horloge si `fromHistory`, la loupe sinon. Le préfixe tapé est
        en gras, et ↖ recopie la suggestion dans le champ ;
    - aucune `search()` avant la validation ;
    - à la validation : `search()`, `VLoading` pendant l'appel, les puces Tout / Titres /
      Albums / Artistes / Playlists, le meilleur résultat en carte, puis les sections ;
    - hors ligne, ou sur `NoPlugin(browse)` : la recherche locale et l'historique restent ;
      les vedettes et la grille sont remplacées par un message, ou par la copie
      (`fromCache`) quand elle existe ;
    - `/category/:id` : `browseCategory`, avec ses étagères paginées.
  - **Pages** (spec UI §6.4, §6.5) :
    - la pochette ou la photo est en grand, fondue dans la surface, sans teinte propre ;
    - album : lignes numérotées, et split button « Lire | ▾ » (aléatoire, lire ensuite,
      ajouter à la file) ;
    - le FAB lecture reste quand l'en-tête est replié ;
    - artiste : bouton Radio, titres populaires, albums en carousel multi-browse ;
    - les pages sont paginées par 100 (`entity(cursor)`).
  - **Lecteur** (spec UI §6.6) :
    - la pochette pleine largeur, fondue ;
    - ⌄, « Lecture depuis … », ⋮ ;
    - le groupe connecté like / playlist / télécharger ;
    - le slider ondulé, plat en pause, branché sur `player.stream.position` ;
    - aléatoire, puis précédent et suivant tonaux, la lecture/pause qui morphe, puis la
      répétition ;
    - la toolbar flottante File / Paroles / Sortie (bottom sheets sur mobile, panneau sur
      desktop) ;
    - `NowPlaying.source` et `mime` alimentent « détails du flux ».
  - **Règles reprises du plan 4** :
    - sans résolveur, le bouton lecture explique pourquoi et renvoie vers « Ajouter un
      dépôt » ;
    - `Notice.skipped` → snackbar discrète ;
    - paroles synchronisées : la ligne active est la dernière dont `startMs ≤ position` ;
    - bouton lecture sans piste chargée → `queueOp(QueueOp.jumpTo(currentEntry))` ;
    - réordonner la file : `QueueOp.move(entry, after: voisin du dessus)`.

- [ ] **Step 1 : tests qui échouent**

```dart
testWidgets('home pages the feed two shelves before the end', ...);   // FakeApi : 12 étagères → homeFeed("4") demandé, pas homeFeed("8") avant défilement
testWidgets('home pull to refresh calls refreshHome', ...);
testWidgets('discovery hero plays the whole shelf', ...);
testWidgets('discovery rows show their reason', ...);
testWidgets('mix tap calls playMix', ...);
testWidgets('shelf titles come from kind and seed', ...);             // BecauseYouListened + seed "Kaytranada" → « Parce que tu as écouté Kaytranada »
testWidgets('end card leads to explore', ...);
testWidgets('explore idle shows featured cards then the grid', ...);
testWidgets('typing shows only suggestions, no search', ...);          // "y","yo","yoa" à 100 ms → 1 suggest("yoa"), 0 search
testWidgets('history suggestions use the clock icon', ...);
testWidgets('north west arrow fills the field without searching', ...);
testWidgets('library hit opens the item directly', ...);
testWidgets('submit shows chips and sectioned results', ...);
testWidgets('explore offline keeps local search and explains', ...);
testWidgets('category page shows its shelves', ...);
testWidgets('album rows are numbered', ...);
testWidgets('playlist page builds lazily', ...);                       // 10 000 titres simulés : moins de 50 VTrackRow construits
testWidgets('tapping a track plays it with its context', ...);         // play(items, start, PlayContext(kind: "album"...))
testWidgets('play without resolver explains why', ...);
testWidgets('synced lyrics highlight the current line', ...);
testWidgets('not the right track lists candidates and pins the choice', ...);
testWidgets('track actions use the expressive menu on both shells', ...);
testWidgets('player progress wave is flat when paused', ...);
```
- [ ] **Step 2 : vérifier l'échec** → FAIL.
- [ ] **Step 3 : implémenter.**
- [ ] **Step 4 : vérifier** → PASS.
- [ ] **Step 5 : commit** : `feat(app): accueil, Explorer, pages, lecteur, file, paroles`.

### Task 7 : bibliothèque, réglages, sources, premier lancement

**Files :**
- Create :
  - `app/lib/features/music/library/{library_page,collection_list,track_list_page,top_page,history_page,sort_sheet}.dart` ;
  - `features/music/library/import_dialog.dart` ;
  - `features/music/settings/{settings_page,appearance_page,plugins_page,add_feed_page,diagnostics_page}.dart` ;
  - `features/music/downloads/downloads_page.dart` ;
  - `features/music/onboarding/onboarding_page.dart`, `features/music/updates/update_banner.dart`.
- Test : `app/test/features/{library,settings,onboarding}_test.dart`.

**Interfaces :**
- Consumes :
  - API du plan 4 : `playlists`, `playlistEntries`, `createPlaylist`, `renamePlaylist`,
    `deletePlaylist`, `moveInPlaylist`, `removeFromPlaylist`, `importPlaylist`,
    `downloads`, `cancelDownload`, `searchLibrary`, `libraryChanges`, `settings`,
    `setSettings`, `installedPlugins`, `capabilityOrder`, `setCapabilityOrder`,
    `previewFeed`, `addFeed`, `removeFeed`, `refreshFeeds`, `onboarding`,
    `finishOnboarding`, `diagnostics`, `exportLogs`, `checkUpdates`, `feeds`, `tracks`,
    `hasResolver`, et `installUpdate` ;
  - API du plan 7 : `liked(kind, sort, …)`, `likedTracks(sort, …)`, `playlists(sort)`,
    `downloaded(sort, …)`, `topTracks`, `history` (`HistoryEntryView`), `uiPref`,
    `setUiPref`, `Settings.discover`.
- Règles :
  - **Bibliothèque** (spec UI §6.3) :
    - grande app bar avec ☰, recherche et tri ;
    - tuiles Likés / Téléchargés / Top 50 / Historique ;
    - puces Playlists / Albums / Artistes, puis la liste ;
    - FAB menu : nouvelle playlist, importer un lien ;
    - Top 50 : ordre fixe, sans menu de tri ;
    - Historique : groupé par jour local (« Aujourd'hui », « Hier », puis la date longue).
  - **Tri** :
    - bottom sheet sur mobile, menu sur desktop ;
    - collections : Récents (défaut), Dernière écoute, Nom A→Z ;
    - titres : Date d'ajout (défaut), Titre, Artiste ;
    - le choix est passé à l'API et retenu par liste (`setUiPref("ui.sort.<liste>")`).
  - **Réglages** : listes M3E en groupes arrondis.
    - Apparence : source de couleur (Ce qui joue, par défaut / Système / Préréglage + choix),
      noir pur, thème clair/sombre/système, le tout dans `ui.*` et appliqué en direct par
      `ThemeController`.
    - Lecture : radio de fin de file, normalisation.
    - Téléchargements.
    - Sources : dépôts, ordre des capacités.
    - Confidentialité : télémétrie, « Découvertes à partir de mon écoute »
      (`Settings.discover`).
    - À propos : mises à jour, diagnostics, rapport de bug.
  - **Premier lancement** (spec 4.6) : `VLoading`, puis 4 étapes :
    1. ce qu'est l'app, livrée sans source de streaming ;
    2. installation du feed officiel (`refreshFeeds`, progression, réessai si hors ligne).
       Après `refreshFeeds`, l'étape décide du réessai par `hasResolver()` ;
    3. « Ajouter un dépôt », facultatif ;
    4. télémétrie : deux boutons, **aucun présélectionné**, et on ne peut pas continuer sans
       choisir.
  - **Ajout d'un dépôt** : URL + clé publique → `previewFeed` → empreinte, domaines déclarés
    et capacités affichés → bouton d'accord explicite → `addFeed`. Ordre des capacités :
    liste réordonnable par capacité. Sources : `feeds()` (nom, officiel, nombre de plugins,
    empreinte), et `removeFeed(url)`.
  - **Import** : `ImportResult.truncated` → mention « playlist tronquée à 50 pages ».
  - **« Rechercher une mise à jour »** = `checkUpdates(force: true)` :
    - `Ok(None)` → « à jour » ;
    - `Some` n'est pas affiché depuis la valeur de retour, seulement par
      `Notice.updateAvailable` ;
    - `Err` → message traduit.
  - **« Envoyer un rapport »** : `exportLogs` vers un fichier du dossier cache, que Dart
    enregistre ou partage, puis ouverture de
    `https://github.com/Vehicoule/vehicoule/issues/new` sans aucune donnée dans l'URL.
  - **Téléchargements** (`/downloads`, ouvert depuis le rail) : `downloads()` avec les
    titres via `tracks(ids)`, et l'annulation.

- [ ] **Step 1 : tests qui échouent**

```dart
testWidgets('library tiles open liked, downloaded, top 50 and history', ...);
testWidgets('sort choice reaches the API and is remembered per list', ...); // Nom A→Z → liked(kind, CollectionSort.title, …) puis setUiPref("ui.sort.albums", "title")
testWidgets('top 50 has no sort menu', ...);
testWidgets('history is grouped by local day', ...);
testWidgets('appearance changes apply live', ...);                        // noir pur → surface == Colors.black
testWidgets('discoveries toggle saves Settings.discover', ...);
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
- [ ] **Step 5 : commit** : `feat(app): bibliothèque, réglages, sources, premier lancement`.

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
  flutter_rust_bridge, données fictives : 3 titres, 1 album, un fil d'accueil de 12 étagères,
  2 catégories vedettes et 6 catégories, flux de commandes simulés),
  branché par `RustLib.initMock(api: FakeApi())`.

- [ ] **Step 1 : tests qui échouent**

```dart
// startup_mobile_test.dart (taille 400×800) et startup_desktop_test.dart (1280×800)
testWidgets('launch, search fake data, play', ...);   // l'accueil s'affiche, Explorer, recherche "halo" validée, tap → FakeApi a reçu play(...) et le mini-lecteur / la barre affiche le titre
// a11y_test.dart, sur accueil, Explorer, lecteur plein écran, réglages, dans les deux coques :
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
