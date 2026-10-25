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
avec `StreamBuilder` ; les listes chargent par `VAsyncList` et rechargent sur
`LibraryChanged`. Seul `platform/` parle aux plugins natifs.

**Tech Stack :** Flutter 3.47.2 (stable), Dart 3.13, go_router 18.1.1, media_kit 1.2.6 +
media_kit_libs_audio 1.0.7, audio_service 0.18.19, window_manager 0.5.2, connectivity_plus
7.3.2, url_launcher 6.3.3, path_provider 2.1.6, app_links 7.2.2, package_info_plus 10.2.2,
device_info_plus 13.3.0, share_plus 13.3.1, home_widget 0.10.0, material_ui 1.8.0,
material_3_expressive 1.2.0 (derrière `design/`), dynamic_color 2.1.0 (source « Système »),
material_color_utilities 0.13.0, gen-l10n, Kotlin (deux services Android).

**Spec :** `docs/superpowers/specs/2026-10-23-socle-ui-design.md` (interface : identité,
composants, écrans ; amendée par 1d6b301, 6214976 et 398def0) ;
`docs/superpowers/specs/2026-10-18-socle-musique-design.md` (v4), sections 1
(périmètre, critères), 2 (règles des coques), 3.1, 3.4, 3.6, 3.7, 4.6, 6, 7, 8, 12 ;
`docs/superpowers/specs/2026-10-25-navigation-domaines.md` (l'« addendum », §11 et §12 :
Task 5, Task 5r, Tasks 6, 7, 8 et 10) ; `docs/superpowers/specs/2026-10-25-surface-attaque.md`
(§2 et §9 : Task 5c, Task 8). Les autres ajouts v1 de l'addendum §12 sont au plan 8
(`2026-10-25-socle-8-ajouts-v1-musique.md`), exécuté après celui-ci.
Rapport : « Reste à faire » (test sur téléphone). Prérequis : plan 4 (façade
`app/lib/bridge/`, squelette `app/`) ; plan 7 avant les tâches 6 et 7 ; plan 6 pour la
validation finale.

**Espace du plan :** `.superpowers/sdd/2026-10-19-socle-5-coques-flutter/` (ledger
`progress.md`, `preflight.md`, rapports et captures des tâches).

## Global Constraints

- Dépôt `/Users/btw/Documents/repo/Vehicoule-socle`, branche `socle` (copie partagée avec
  d'autres sessions : jamais de `stash`, de `reset` ni de changement de branche). Licence
  MPL-2.0. Commit = `git commit -s -m "<msg>" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"`.
- Ordre d'exécution : 2, 1, 3, 4, 5 (jusqu'à son commit), 5r, point de contrôle du shell
  (Task 5 Step 6), 5b, 5c, 6, 7, 10, 8. La 9 est manuelle, sur appareils, après la Task 7 du
  plan 6. Les tâches 1 à 4 sont terminées.
- Chaque sous-agent tourne en modèle opus, effort high.
- Versions de paquets **figées** (pas de `^`) dans `app/pubspec.yaml`, aux versions de la Tech
  Stack. Chaque tâche ajoute les paquets qu'elle importe la première et liste
  `app/pubspec.yaml` dans ses Modify.
- Dossiers (spec 2) : `app/lib/{bridge,design,l10n,platform,features/music,features/app,shell_mobile,shell_desktop,debug}`.
  `features/app/` tient les écrans globaux, communs à tous les domaines (addendum §2.3).
  `bridge/` n'est jamais modifié à la main. `debug/` ne sert qu'en `kDebugMode`, aux tests et
  à la galerie.
- `package:flutter/material.dart` n'est importé nulle part : les écrans importent
  `package:material_ui/material_ui.dart` et `design/design.dart`. `material_3_expressive`
  n'est importé **que** dans `app/lib/design/`. Aucun nombre d'espacement ni de rayon hors des
  tokens. Les tests de `test/design/` le vérifient (`imports_test`, `spacing_test`,
  `guards_test`) ; le garde « brique maison » (`ownBrick`) porte sur `lib/features` et
  `lib/shell_*`.
- Navigation : **go_router**. Coque choisie par `windowClassOf(largeur)` (spec UI §4), seule
  source des points de rupture :
  - `WindowClass.expanded` (≥ 840 dp) → desktop (spec UI §4.2) :
    - barre de titre maison avec la recherche, sur macOS, Windows et Linux seulement
      (`window_manager`, `TitleBarStyle.hidden`) ; une tablette Android ≥ 840 dp n'en a pas,
      la recherche reste dans la grande app bar ;
    - rail M3E permanent avec ses épinglés et le FAB de la destination ;
    - à droite, le panneau « en lecture », qui se replie en bande de 76 px : replié par défaut
      sous `VBreakpoints.paneOpen` (1000 dp), déplié au-delà. Pas de barre de lecture en bas ;
  - `WindowClass.medium` (600 à 840 dp) → la coque mobile, mais le rail replié à gauche
    remplace la barre du bas (spec UI §4.3) ;
  - `WindowClass.compact` → mobile : barre de navigation M3E (Accueil, puis les destinations
    du domaine courant : Explorer, Bibliothèque), ☰ qui ouvre le rail déplié en modal,
    mini-lecteur flottant au-dessus. Réglages, Sources et Téléchargements sont des sections
    globales (addendum §2.1).
- Listes : `CustomScrollView` + `VAsyncList` (ses quatre états : chargement, vide, erreur avec
  « Réessayer », hors ligne). Une longue liste est `VAsyncList.paged` (pages de 100 via l'API) :
  une playlist de 10 000 titres défile sans tout charger. Une liste dont la requête change
  (tri, filtre, autre playlist) passe la requête dans `reloadKey`.
- Recherche : `VSearchBar` de `design/`. Suggestions pendant la frappe, résultats à la
  validation seulement (spec UI §6.2).
- Lecteur : **un seul widget `VNowPlaying`** dans `design/` (spec UI §5.5) :
  - trois tailles (compact, moyen, grand) et deux styles (Disque, Vague) ;
  - le sélecteur Paroles · Lecteur · File (groupe de boutons connectés), dont les contenus
    sont fournis par `features/` ;
  - sur une surface unie (`vScreenSurface`), sans dégradé.

  Plein écran mobile : `DraggableScrollableSheet`. Le passage mini-lecteur → lecteur suit
  l'extent de la feuille : `VExtentFlight` entre les rects rendus par
  `VNowPlaying.onArtworkRect` des deux côtés, jamais un `Hero`. La progression est
  `PlayerAdapter.position` (`ValueListenable<int>`, ms), branchée sur
  `player.stream.position` côté Dart (Rust ne reçoit qu'une position toutes les ~10 s) ; un
  seek y pose sa cible tout de suite.
- Réutilisation (spec UI §5) : les briques (pochette, contrôles, progression ondulée,
  sélecteur, ligne de titre, menu, FAB, split button) n'existent qu'une fois, dans `design/`.
  Un split button est toujours `VSplitButton`, jamais `M3ESplitButton`.
- Pochettes : `ArtworkResolver` (défaut : `artworkFile`, cache Rust), jamais d'image réseau.
  Aucune pochette protégée n'est commitée : galerie, tests et captures montrent l'aspect
  « pochette absente » (`surfaceContainerHighest` uni et l'icône centrée), ou de vraies
  pochettes lues à l'exécution par le cœur.
- Actions sur un titre : le menu expressif `showVMenu(anchor:, originRect:)` (appui long, clic
  droit, ⋮), le même sur les deux coques. Erreurs discrètes : `showVSnack`.
- **FAB, FAB menu, split button** (spec UI §5.4, règle d'emploi) : un seul FAB ou split button
  par écran, pour son action principale. Un écran le déclare par `ScreenFab` (Task 5) ; sur
  téléphone, `VFabDock` le place au-dessus du ⏯ du mini-lecteur ; sur desktop, le rail porte
  celui de la destination. Les groupes de boutons connectés servent aux bascules et aux choix,
  jamais à une action principale.
- Couleur : `seedForArtwork(path, fallback:)` pour le titre qui joue ; une pochette sans
  couleur donne la graine de repli (Système, sinon le préréglage), jamais celle du titre
  précédent. `coverTopFromArtwork` va avec la graine dans `NowPlayingData.coverTop`.
- État : pas de Riverpod ni Bloc.
- Raccourcis desktop : tout le tableau de la spec UI §4.2 (Espace, ← →, ⇧← ⇧→, ⌘↑ ⌘↓, ⌘L,
  ⌘F, ⌘[ ⌘], ⌘⌥B, ⌘⇧F, ⌘,, ⌘R, Suppr ; `Ctrl` hors macOS) ; touches média via audio_service.
  Aucun raccourci quand un champ texte a le focus.
- Android : `applicationId app.vehicoule` ; service audio_service de type
  `mediaPlayback` ; service de téléchargement de premier plan de type `dataSync` avec
  notification de progression ; fichiers dans l'espace propre à l'app, aucune permission
  de stockage.
- Accessibilité : `Semantics`/`tooltip` sur chaque contrôle sans texte, taille de texte
  système respectée (pas de `textScaler` forcé), contrastes WCAG AA dans les tokens. Les tests
  trouvent les widgets par libellé sémantique ou `find.byWidgetPredicate`, jamais par un type
  de `material.dart`.
- FR et EN dès le départ (`gen-l10n`, ARB) ; aucun texte en dur dans les widgets. Ton et
  vocabulaire de `docs/voice.md` (spec UI §2.9) : « source » et « lien de source », jamais
  « plugin » ni « dépôt » à l'écran, dans un nom de fichier ou une route. Sans source de
  lecture : « Il te faut une source pour lire. » avec l'action « Ajouter une source ».
- Clés de `uiPref`/`setUiPref` : toujours `ui.*` (une autre clé lève `CoreError.notFound`).
- Données de test : `lib/debug/library.dart` (vrais titres et artistes, métadonnées seules) et
  `lib/debug/fake_api.dart` (Task 3), branché par `RustLib.initMock(api: FakeApi())`.
- **Garde-fous contre l'IA slop** (spec UI §2.8) : chaque tâche les respecte ; le relecteur de
  tâche reçoit le tableau §2.8 comme grille et compte toute violation comme Important.
- **Revue, captures et rapports** (audit 13a, 13g) :
  - chaque point de contrôle utilisateur comprend des captures à taille réelle (téléphone
    412 × 892 dp, desktop 1280 × 800 dp), chacune à côté de la maquette validée rendue à la
    même largeur, et la liste des écarts. Le relecteur reçoit maquettes et captures, et compte
    tout écart visuel comme Important. Maquettes :
    `.superpowers/brainstorm/59588-1792794291/content/{lecteur-v3,app-formes,desktop-2}.html`
    et `.superpowers/brainstorm/14247-1792758406/content/accueil.html` ;
  - les captures vont dans l'espace du plan,
    `.superpowers/sdd/2026-10-19-socle-5-coques-flutter/task-<n>-screenshots/` ;
    `app/.shots/` (le banc de capture temporaire) n'est jamais commité ;
  - une ronde de corrections Important ne prend pas les mineurs : ils sont listés dans le
    ledger et gardés pour la revue finale, sauf ruling contraire ;
  - chaque rapport se termine par la fin de la sortie de `flutter test` et de
    `flutter analyze`.
- Télémétrie Dart : pas de `sentry_flutter`. Les erreurs Dart non rattrapées
  (`FlutterError.onError`, `PlatformDispatcher.instance.onError`) passent par
  `reportDartError` du cœur : un seul filtre, testé au plan 4. Limite connue : les
  plantages natifs Kotlin/Swift ne sont pas captés en v1 ; on ajoutera `sentry_flutter`
  s'ils apparaissent.
- Mesure du premier son : horodatage au tap (`PlayerAdapter.markTap()`, appelé par
  `playTracks`, Task 6), première position > 0 après le `Play` correspondant →
  `reportPerf(metric: PerfMetric.tapToFirstSoundMs, valueMs:)`.

## Review Focus

1. **Espace ou flèches tapés dans le champ de recherche sur desktop** : le texte reçoit la
   touche, la lecture ne se met pas en pause. → test `shortcuts_ignored_while_typing` (tâche 5).
2. **Texte système à 200 %** : aucun débordement sur l'accueil, Explorer, le
   mini-lecteur, le lecteur plein écran et les Réglages. → test `no_overflow_at_text_scale_2`
   (tâche 8).
3. **Erreur du lecteur qui cache un 403 dans un message mpv** : elle doit arriver à Rust
   comme `Forbidden` pour déclencher la nouvelle résolution, pas comme `Other`.
   → test `classify_player_errors` (tâche 3).
4. **Changement de piste automatique de mpv après un `EnqueueNext`** : l'adaptateur envoie
   `TrackStarted` avec l'entrée préchargée, sinon Rust croit encore jouer l'ancienne piste.
   → test `auto_advance_reports_preloaded_entry` (tâche 3).
5. **Premier lancement hors ligne** (feed officiel injoignable) : l'accueil explique qu'il
   faut du réseau pour installer les sources, l'app ne reste pas bloquée sur un indicateur.
   → test `onboarding_offline_explains_and_continues` (tâche 7).
6. **Seek** : la progression montre la cible dès le geste, sans retour à l'ancienne position
   ni minuterie dans `design/`. → test `seek_publishes_its_target_at_once` (tâche 3).
7. **Lancement Android après le renommage** : le symbole JNI de `RustInit.initVerifier` suit
   le nouveau paquet Kotlin, sinon l'app plante au démarrage (`UnsatisfiedLinkError`) alors
   que tous les tests Dart et Rust passent. → test `jni_symbols_follow_the_kotlin_package`
   et lancement sur l'émulateur (tâche 5r).
8. **Build macOS de release** : le proxy média écoute sur `127.0.0.1` ; sans
   `com.apple.security.network.server` dans `Release.entitlements` (seul `DebugProfile` l'a),
   le son marche en debug et jamais en release. → test `release entitlements allow the proxy`
   (tâche 5c).

---

### Task 1 : système de design (`design/`)

**État : terminée** (commits 0901a7a..becfd07 ; 143 tests, analyse propre ; galerie
approuvée par le contrôleur sous délégation de l'utilisateur, consigné au ledger). Les étapes
ci-dessous sont l'historique de la tâche ; le bloc Interfaces est l'API livrée. Le code
(`app/lib/design/design.dart` et `components/`) fait foi.

**Files :**
- Create :
  - `app/lib/design/{design,tokens,theme,color,typography,motion,symbols}.dart` ;
  - `app/lib/design/components/{artwork,wave_artwork,wave_progress,controls,view_selector,now_playing,track_row,menu,side_sheet,shelf,loading,empty_state,snack}.dart` ;
  - `app/lib/design/gallery.dart` : la galerie de validation, une route de debug
    `/debug/gallery` enregistrée seulement si `kDebugMode`, sans `FakeApi` (données en dur,
    pochettes de `app/assets/gallery/`) ;
  - `app/assets/fonts/` : Google Sans Flex variable (axes `opsz`, `wght`, `ROND`), Noto Sans
    JP variable, Material Symbols Rounded variable (`FILL`, `wght`).
- Modify : `app/pubspec.yaml` (`material_ui: 1.8.0`, `material_3_expressive: 1.2.0`,
  polices déclarées).
- Test : `app/test/design/{contrast,imports,spacing,color,track_row,menu,motion}_test.dart`.

**Interfaces (livrées) :**
- Produces — les écrans et les coques importent `design/design.dart` (qui cache
  `VArtworkPicture`) ; données de démonstration dans `app/lib/debug/library.dart`
  (`sampleTracks`, `sampleCollections`, `sampleQuery`) :
  ```dart
  // tokens.dart
  abstract final class VSpace { static const s4 = 4.0, s8 = 8.0, s12 = 12.0, s16 = 16.0, s24 = 24.0, s32 = 32.0;
    static const marginCompact = 16.0, marginWide = 24.0, sectionGap = 24.0, cardGap = 8.0; static double margin(WindowClass c); }
  abstract final class VSize { static const trackRow = 56.0 /* hauteur minimale */, trackArt = 44.0, trackArtRadius = 12.0, menuTarget = 48.0,
    shelfCard = 108.0, strip = 76.0, sideSheet = 360.0, railExpanded = 280.0, compactArt = 56.0, fab = 56.0, toolbar = 64.0, swipe = 96.0,
    headerArt = 220.0, heroCard = 280.0, icon = 24.0, iconLarge = 48.0, albumColumn = 220.0, durationColumn = 56.0; /* … voir tokens.dart */ }
  abstract final class VRadius { static const small = 12.0, medium = 16.0, large = 28.0; }
  enum WindowClass { compact, medium, expanded }
  abstract final class VBreakpoints { static const medium = 600.0, expanded = 840.0, paneOpen = 1000.0; }
  WindowClass windowClassOf(double width);                               // seule source des points de rupture
  // color.dart
  enum ColorSource { nowPlaying, system, preset }
  abstract final class VPresets { static const List<Color> seeds; }
  Color pastelSeed(Color raw);                                           // HCT : chroma plafonnée à 48, teinte gardée
  Future<Color?> seedFromArtwork(String path);                           // décodée à 112 px, quantifiée dans Isolate.run ; cache LRU de 64 chemins
  Future<Color> seedForArtwork(String? path, {required Color fallback}); // pochette sans couleur ou absente → fallback
  Future<Color?> systemSeed();                                           // dynamic_color ; null sans le plugin
  class VCoverTop { const VCoverTop(double low, double high); }          // luminance du haut de la pochette (1er et 99e centiles)
  Future<VCoverTop?> coverTopFromArtwork(String path);                   // même décodage que la graine, même cache
  enum VOnCover { light, dark, scrim }
  VOnCover vOnCoverFor(VCoverTop? top);                                  // contenu de l'en-tête de la Vague
  // theme.dart
  ThemeData vTheme({required Brightness brightness, required Color seed, bool pureBlack = false});
  Color vScreenSurface(ColorScheme cs);                                  // fond plein écran : surfaceContainer, 0 en noir pur
  const List<LocalizationsDelegate<dynamic>> vLocalizationsDelegates;    // les nôtres + ceux de material_ui
  Widget vAppBuilder(BuildContext context, Widget? child);               // MaterialApp.builder : M3ETheme, police, anneau de focus
  // typography.dart
  abstract final class VFonts { static const family = 'GoogleSansFlex'; static const fallback = ['NotoSansJP']; }
  TextTheme vTextTheme(TextTheme base); void vRegisterFontLicenses();
  // motion.dart — les seules durées, courbes et transitions de l'app
  abstract final class VDurations { reduced /*150 ms*/, short, medium, long, undo /*5 s*/, snack /*4 s*/, themeFade, debounce /*150 ms*/,
    seekStep /*10 s*/, stagger /*40 ms*/, spin /*20 s*/; }
  abstract final class VCurves { emphasized, emphasizedDecelerate, emphasizedAccelerate, standard, linear, spring; }
  abstract final class VSprings { spatial, spatialFast, effects; }
  bool reduceMotion(BuildContext c); Duration vMotion(BuildContext c, Duration d);
  Page<T> vContainerTransformPage<T>({required LocalKey key, required Widget child, required Object heroTag});
  Widget vContainerSource({required Object heroTag, required Widget child}); // la carte ou la ligne d'origine
  Page<T> vFadeThroughPage<T>({required LocalKey key, required Widget child});
  Widget vSharedAxis({required Widget child, required Object key, bool reverse = false});
  Widget vEntrance(int index, Widget child);                             // fondu + montée, décalé de VDurations.stagger
  class VExtentFlight extends StatelessWidget { const VExtentFlight({required double extent, required Rect from, required Rect to,
    required Widget Function(BuildContext context, double side) builder}); } // Positioned dans un Stack ; rect interpolé par l'extent 0..1, sans Hero
  // haptics.dart : VHaptics.light() / selection() / medium(), Android et iOS seulement
  // symbols.dart : abstract final class VIcons { … }   (Material Symbols Rounded ; la liste grandit par tâche)
  class VSymbol extends StatelessWidget { const VSymbol(IconData icon, {bool filled = false, double weight = 400, double? size, Color? color, String? semanticLabel}); }
  // components/artwork.dart
  typedef ArtworkSource = Future<ImageProvider?> Function(String itemId, int px);
  class ArtworkResolver extends InheritedWidget { const ArtworkResolver({required ArtworkSource resolve, required Widget child}); }
  class NowPlayingScope extends InheritedWidget { const NowPlayingScope({required String? trackId, String? contextId, required bool playing,
    required Widget child}); static bool isPlaying(BuildContext c, String itemId); }   // fourni par les coques
  enum ArtKind { item, artist }   enum ArtShape { roundedSquare, cookie, circle }
  class VArtwork extends StatefulWidget { const VArtwork({required String itemId, required double size, ArtKind kind = ArtKind.item, bool? playing,
    bool selected = false, List<String>? mosaic, double? progress, ValueChanged<double>? onSeek, double seekStep = 0.05, String? semanticLabel}); }
  enum VDecorShape { clover, flower, sunny, burst, pill, arch, gem, cookie }
  VDecorShape decorFor(String id);
  class VDecor extends StatelessWidget { const VDecor({required VDecorShape shape, required double size, String? imageItemId, Widget? child, double tilt = 0}); }
  class VEqualizer extends StatefulWidget { const VEqualizer({required double size, bool onArtwork = false}); }
  // components/wave_progress.dart, wave_artwork.dart
  class VWaveProgress extends StatelessWidget { const VWaveProgress({required double progress, required bool playing, required ValueChanged<double>? onSeek, double step = 0.05}); }
  class VDownloadIcon extends StatelessWidget { const VDownloadIcon({required DownloadStateView? state, double? progress, double size = VSize.icon}); } // flèche → anneau → coche
  class VWaveArtwork extends StatefulWidget { const VWaveArtwork({required String itemId, required double width, required double progress,
    required bool playing, required ValueChanged<double> onSeek, double seekStep = 0.05, double? height}); }
  // components/controls.dart
  enum VIconStyle { standard, filled, tonal, outlined }
  class VIconButton extends StatelessWidget { const VIconButton({required IconData icon, required String label, required VoidCallback? onPressed,
    bool? selected, VIconStyle style = VIconStyle.standard, bool? glyphFilled}); }   // selected null = pas une bascule
  enum VButtonStyle { filled, tonal, outlined, text }
  class VButton extends StatelessWidget { const VButton({required String label, required VoidCallback? onPressed, IconData? icon, VButtonStyle style = VButtonStyle.filled}); }
  class VConnectedGroup extends StatelessWidget { const VConnectedGroup({required List<VAction> actions, bool autofocusFirst = false}); } // bascules (VAction.selected)
  class VSplitButton extends StatelessWidget { const VSplitButton({required String label, required IconData icon, required VoidCallback onPressed, required List<VAction> items}); }
  class VControls extends StatelessWidget { const VControls({required bool playing, required bool loading, required bool shuffle, required Repeat repeat,
    required VoidCallback onPlayPause, required VoidCallback onNext, required VoidCallback onPrevious, required VoidCallback onShuffle,
    required VoidCallback onRepeat, bool tall = false}); }
  class VPlayPauseFab extends StatelessWidget { const VPlayPauseFab({required bool playing, required bool loading, required VoidCallback onPressed}); }
  class VVolume extends StatelessWidget { const VVolume({required double value, required ValueChanged<double>? onChanged, bool vertical = false}); }
  class VSlider extends StatelessWidget { const VSlider({required double value, required ValueChanged<double>? onChanged, required String label}); }
  // components/kit.dart
  enum VFabSize { small, regular, large }
  class VFab extends StatelessWidget { const VFab({required IconData icon, required String label, required VoidCallback? onPressed, VFabSize size = VFabSize.regular}); }
  class VExtendedFab extends StatelessWidget { const VExtendedFab({required IconData icon, required String label, required VoidCallback? onPressed,
    bool extended = true, bool secondary = false}); }
  class VScreenFab extends StatelessWidget { const VScreenFab({required VAction action, List<VAction> items = const [], bool extended = true,
    bool secondary = false, bool startAligned = false}); }   // items non vide → FAB menu
  class VFabMenu extends StatelessWidget { const VFabMenu({required List<VAction> items, required String label, IconData icon = VIcons.add}); }
  class VFabDock extends StatefulWidget { const VFabDock({required Widget body, VAction? fab, List<VAction> fabItems = const [], Widget? player}); }
  class VChoiceGroup<T> extends StatelessWidget { const VChoiceGroup({required List<(T, String)> choices, required T value, required ValueChanged<T> onChanged}); }
  class VToolbar extends StatelessWidget { const VToolbar({required List<VAction> actions, String? title, Widget? leading, bool docked = false, Widget? fab}); }
  class VChip extends StatelessWidget { const VChip({required String label, required VoidCallback? onPressed, IconData? icon, bool selected = false, bool filter = false}); }
  class VSwitch extends StatelessWidget { const VSwitch({required bool value, required ValueChanged<bool>? onChanged, required String label}); }
  class VBadge extends StatelessWidget { const VBadge({required Widget child, int? count, String? label}); }
  class VRichTooltip extends StatefulWidget { const VRichTooltip({required String title, required String message, required Widget child, bool showOnStart = false}); }
  class VSkeleton extends StatelessWidget { const VSkeleton({required double width, required double height, ArtKind? kind}); static Widget row(); }
  // components/menu.dart
  class VAction { const VAction(String label, IconData icon, VoidCallback onSelected, {bool selected = false, Widget? leading}); }
  Future<void> showVMenu(BuildContext c, {required Rect anchor, required List<VAction> quick, required List<List<VAction>> groups,
    Widget? origin, Rect? originRect, bool startAligned = false});      // anchor = le déclencheur ; origin/originRect = l'élément soulevé
  Future<T?> showVSheet<T>(BuildContext c, {required WidgetBuilder builder}); // bottom sheet < 840, dialogue au-delà ; null si une feuille est ouverte
  // components/surfaces.dart
  class VDestination { const VDestination(String label, IconData icon, {int? badge}); }
  class VNavigationBar extends StatelessWidget { const VNavigationBar({required List<VDestination> destinations, required int selected, required ValueChanged<int> onSelected}); }
  class VPinned { const VPinned(String itemId, String label, {ArtKind kind = ArtKind.item}); }
  class VNavigationRail extends StatelessWidget { const VNavigationRail({required List<VDestination> destinations, required List<VPinned> pinned,
    required int selected, required ValueChanged<int> onSelected, required bool expanded, required ValueChanged<bool> onExpanded,
    VAction? fab, List<VAction> fabItems = const []}); }               // fab = le FAB de la destination, replié et déplié
  class VSearchBar extends StatefulWidget { const VSearchBar({required List<Widget> Function(BuildContext context, String text) suggestions, ValueChanged<String>? onSubmitted}); }
  enum VCarouselKind { hero, multiBrowse, uncontained }
  class VCarouselItem { const VCarouselItem({required String itemId, required String title, String? subtitle, required VoidCallback onTap}); }
  class VCarousel extends StatelessWidget { const VCarousel({required VCarouselKind kind, required List<VCarouselItem> items, required double height}); }
  Future<bool?> showVDialog(BuildContext c, {required String title, required String message, required String action, String? cancel});
  Future<void> showVSideSheet(BuildContext c, {required String title, required Widget body});
  class VStandardSheet extends StatelessWidget { const VStandardSheet({required Widget child}); }
  class VListGroup extends StatelessWidget { const VListGroup({required String title, required List<Widget> children}); }
  class VListRow extends StatelessWidget { const VListRow({String? title, String? subtitle, Widget? trailing, Widget? below, VoidCallback? onTap}); }
  class VLargeAppBar extends StatelessWidget { const VLargeAppBar({required String title, Widget? leading, List<Widget> actions = const []}); }
  class VCircularProgress extends StatelessWidget { const VCircularProgress({required double? value, double size = VSize.iconLarge}); }
  // components/now_playing.dart
  enum PlayerSize { compact, medium, large }   enum PlayerStyle { disc, wave }   String vTime(int ms);
  class NowPlayingData { const NowPlayingData({required TrackView track, required String sourceTitle, required bool playing, required bool loading,
    required int durationMs, required bool liked, required DownloadStateView? download, double? downloadProgress, required bool shuffle,
    required Repeat repeat, Duration? sleepLeft, bool sleepEndOfTrack = false, VCoverTop? coverTop}); }
  class NowPlayingActions { const NowPlayingActions({required VoidCallback onPlayPause, required VoidCallback onNext, required VoidCallback onPrevious,
    required ValueChanged<int> onSeek, required VoidCallback onLike, required VoidCallback onAddToPlaylist, required VoidCallback onDownload,
    required VoidCallback onShuffle, required VoidCallback onRepeat, VoidCallback? onOutput, ValueChanged<Rect>? onMenu, VoidCallback? onCollapse,
    VoidCallback? onOpen, VoidCallback? onStop}); }                    // onSeek en ms ; onMenu reçoit le rect du ⋮
  class VNowPlaying extends StatefulWidget { const VNowPlaying({required NowPlayingData data, required ValueListenable<int> position,
    required PlayerSize size, required PlayerStyle style, required PlayerView view, required ValueChanged<PlayerView> onView,
    required NowPlayingActions actions, required WidgetBuilder lyrics, required WidgetBuilder queue, VoidCallback? onImmersive, Widget? volume,
    Axis axis = Axis.horizontal, bool wide = false, bool immersive = false, bool artworkVisible = true, ValueChanged<Rect>? onArtworkRect}); }
  // components/view_selector.dart
  enum PlayerView { player, lyrics, queue }
  class VViewSelector extends StatelessWidget { const VViewSelector({required PlayerView value, required ValueChanged<PlayerView> onChanged,
    List<PlayerView> views = VViewSelector.order}); static const order = [PlayerView.lyrics, PlayerView.player, PlayerView.queue]; }
  // components/track_row.dart
  class VTrackRow extends StatefulWidget { const VTrackRow({required TrackView track, int? number, Widget? leading, bool? playing, bool offline = false,
    bool selected = false, bool wide = false, int? handleIndex, required VoidCallback onTap, VoidCallback? onDoubleTap,
    required VoidCallback onPlayNext, VoidCallback? onRemove, required List<VAction> quick, required List<List<VAction>> groups}); }
  // components/shelf.dart, header.dart
  class VShelf extends StatelessWidget { const VShelf({required String title, String? subtitle, VoidCallback? onMore, required double extent,
    required List<Widget> items, double itemWidth = VSize.shelfCard}); }
  class VCard extends StatelessWidget { const VCard({required String itemId, required String title, String? subtitle, ArtKind kind = ArtKind.item, required VoidCallback onTap}); }
  class VHeroCard extends StatelessWidget { const VHeroCard({required String itemId, required String title, String? subtitle, required VoidCallback onTap}); }
  class VScreenBackground extends StatelessWidget { const VScreenBackground({required Widget child}); } // le seul dégradé : haut d'écran surfaceContainer → surface
  class VFlexibleHeader extends StatelessWidget { const VFlexibleHeader({required Widget artwork, required String title, String? subtitle,
    required List<Widget> actions, required Widget fab}); }
  // components/async_list.dart
  class VAsyncList<T> extends StatefulWidget {
    const VAsyncList({required Future<List<T>> Function() load, required Widget Function(BuildContext, List<T>) builder, required Widget empty,
      required String Function(Object error) errorText, Object? reloadKey});
    const VAsyncList.stream({required Stream<List<T>> Function() watch, required Widget Function(BuildContext, List<T>) builder, required Widget empty,
      required String Function(Object error) errorText, Object? reloadKey});
    const VAsyncList.paged({required Future<List<T>> Function(int offset, int limit) page, required Widget Function(BuildContext, T, int) itemBuilder,
      required Widget empty, required String Function(Object error) errorText, Object? reloadKey, int pageSize = 100}); }
  // components/loading.dart, empty_state.dart, snack.dart, side_sheet.dart, focus_ring.dart
  class VLoading extends StatelessWidget { const VLoading({double size = VSize.iconLarge, bool contained = false, bool onContainer = false}); }
  class VRefresh extends StatelessWidget { const VRefresh({required Future<void> Function() onRefresh, required Widget child}); }
  class VEmptyState extends StatelessWidget { const VEmptyState({required IconData icon, required String message, Widget? action}); }
  class VOfflineChip extends StatelessWidget { const VOfflineChip(); }  // « Hors ligne · tes téléchargements restent là »
  void showVSnack(BuildContext c, String message, {String? actionLabel, VoidCallback? onAction, Duration duration = VDurations.snack});
  class VSideSheet extends StatelessWidget { const VSideSheet({required bool open, required Widget child, double width = VSize.sideSheet}); }
  class VFocusRing extends StatefulWidget { const VFocusRing({required Widget child, ShapeBorder shape = const StadiumBorder(), FocusNode? node}); }
  ```
- Règles (spec UI §2, §3, §5), telles que livrées :
  - **Couleur** : une seule source de teinte à la fois. Aucune extraction ailleurs que dans
    `color.dart`. Le lecteur est sur `vScreenSurface`, sans dégradé ; le seul dégradé est
    `VScreenBackground`.
  - **Mouvement** : les ressorts viennent de `M3ETheme` et de `VSprings`. Avec
    `reduceMotion`, toute transition de page devient un fondu de 150 ms et chaque ressort est
    instantané. Les tags de `vContainerSource` sont uniques par source (route + étagère + id),
    sinon une carte au même tag sur la route précédente s'envole aussi.
  - **Pochette** : la forme vient du sens (`artShapeFor`) — carré arrondi au repos, cookie qui
    tourne en lecture, cercle pour un artiste, cookie + coche sélectionnée. `playing` null =
    lu dans `NowPlayingScope`. `mosaic` = les ids des 4 premiers titres distincts d'une
    playlist perso sans image (1 pleine, 2 en diagonale, 3 répétés, 4 distincts, 0 l'icône).
    `progress` dessine l'anneau qui suit le contour ; `onSeek` en fait un slider.
  - **Ligne de titre** : hauteur minimale 56, elle grandit avec le texte ; marge 16 ; pochette
    44 de rayon 12 (ronde pour un artiste) :
    - `number` ou `leading` (le rang du Top 50) remplace la pochette dans le même carré ;
    - `playing` : pochette en cookie, égaliseur à côté du ⋮ (à la place du numéro s'il y en a
      un), `Semantics` « en lecture » ;
    - `offline` : opacité 0,38, et le toucher affiche le message hors ligne ;
    - glisser à droite : `onPlayNext` ; à gauche : `onRemove` ; haptique au seuil ;
    - `wide` : colonnes album et durée, ▶ et ⋮ au survol ou au focus, clic / double-clic ;
    - `handleIndex` : la poignée d'une `ReorderableList` ;
    - appui long, clic droit, ⋮, touche Menu ou ⇧F10 : `showVMenu` ;
    - badges E et téléchargé depuis `TrackView` ; un seul nœud sémantique (« titre, artistes,
      état ») avec « Lire ensuite » et « Retirer » en actions.
  - **Menu** : la rangée `quick` en groupe connecté en tête de la même surface, puis les
    groupes séparés ; l'origine se soulève ; ouvert près de `anchor` (le déclencheur).
  - **Lecteur `VNowPlaying`** : présentation seulement, blocs de la spec UI §5.5 dans l'ordre ;
    seule la progression se reconstruit à chaque `position`.
    - `compact` est le mini-lecteur complet : toolbar flottante (pochette disque + anneau,
      titre, artiste, like) et `VPlayPauseFab` à côté. Les gestes ← → ↑ ↓ (seuil
      `VSize.swipe`, haptiques) et leurs entrées de menu appellent `onNext`, `onPrevious`,
      `onOpen`, `onStop`. Toucher appelle `onOpen` ;
    - `axis: Axis.vertical` en compact = la bande desktop de 76 ;
    - `wide` = deux colonnes (paysage, largeur moyenne, immersif) ; `immersive` = la vue
      immersive desktop (son sélecteur n'a pas « Lecteur ») ;
    - `artworkVisible: false` garde la place sans peindre la pochette (pendant un
      `VExtentFlight`) ; `onArtworkRect` rend le rect global de la pochette après chaque mise
      en page ;
    - l'en-tête de la Vague s'adapte à `coverTop` (`vOnCoverFor`) ; sans `coverTop`, un voile.
  - **Sélecteur** : Paroles · Lecteur · File, centré, groupe de boutons connectés M3E ; l'actif
    est plein avec son icône et son libellé, les autres n'ont que l'icône.
  - **FAB** : `VFabDock` place le FAB d'écran au-dessus du ⏯ du mini-lecteur (bord droit
    aligné, 16 dp d'écart, `VScreenFab` étendu en `secondaryContainer`), le masque au
    défilement vers le bas, le rend vers le haut, et ajoute sa hauteur au padding bas du
    `body`. Sans `player`, le FAB a le coin. `VNavigationRail(fab:, fabItems:)` porte le FAB
    de la destination, replié et déplié ; ses `fabItems` s'ouvrent dans un menu sous lui.
  - **Choix** : `VChoiceGroup` (groupe de boutons connectés à choix unique) ; pas de segmented
    button.

**Ajouts — 8 sujets (spec UI §2.2, §2.8, §4.3, §4.4) :**
- `WindowClass { compact, medium, expanded }` et `windowClassOf(width)` (< 600, 600–840,
  ≥ 840), seule source des points de rupture.
- Thème clair (spec UI §2.2) : surfaces aux tons 98–92 teintées, jamais `#FFFFFF` ; le test de
  contraste couvre déjà clair, sombre et noir pur.
- `VFocusRing` : trait `secondary` 3 px, décalé de 2 px, qui suit la forme ; visible seulement
  en `FocusHighlightMode.traditional`.
- Tests des garde-fous §2.8, dans `test/design/guards_test.dart`, qui parcourent `lib/` :

```dart
test('no raw colors outside design/', ...);          // Color(0x, Colors. interdits hors lib/design
test('no blur, glass, glow or extra gradients', ...); // BackdropFilter, ImageFilter.blur, BoxShadow, *Gradient hors lib/design
test('no ad-hoc durations or curves in screens', ...); // Duration(, Curves. interdits dans features/ et shell_*
test('focus ring follows the shape and only shows on keyboard', ...);
test('light scheme never uses pure white surfaces', ...);
```

- [ ] **Step 1 : tests qui échouent**

```dart
testWidgets('VNowPlaying keeps the block order in every size and style', ...);
testWidgets('mosaic artwork tiles 1, 2, 4 and 0 items', ...);
testWidgets('artwork shape follows meaning: idle rounded, playing cookie, artist circle, selected check', ...);
testWidgets('playing cookie stops spinning and morphs back when paused or with reduce motion', ...);
test('decorFor is stable per id and spreads over the shapes', ...);
testWidgets('flexible header docks the artwork into the app bar on scroll', ...);
testWidgets('reduce motion turns every page transition into a fade', ...);
test('haptics are silent on desktop and when the system disables them', ...);  // en-tête, pochette, titre, groupe connecté, progression, contrôles, sélecteur
testWidgets('VNowPlaying compact is artwork, title, like and play/pause only', ...);
testWidgets('view selector switches views and widens the active one', ...);
testWidgets('lyrics and queue views show the compact header', ...);
testWidgets('disc ring and wave edge seek like a slider', ...);              // glisser → onSeek(0.5) ; ←/→ au clavier ; Semantics slider
testWidgets('paused disc morphs to a rounded square and stops spinning', ...);
testWidgets('loading turns play/pause into the loading indicator', ...);
test('no feature or shell file defines its own artwork, controls, progress, selector, track row or menu', ...); // grep lib/features, lib/shell_* : aucune classe CustomPainter de pochette/onde, aucun widget Slider/ProgressIndicator/SegmentedButton/MenuAnchor direct
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
- [ ] **Step 5 : galerie.** `gallery.dart` montre :
  - chaque composant de `components/` dans tous ses états :
    - `VTrackRow` : normal, numéroté, en lecture, hors ligne, glissé, mode large desktop ;
    - `VNowPlaying` dans ses 3 tailles × 2 styles × 3 vues, en lecture, en pause et en
      chargement ;
    - le menu ouvert, une étagère, une carte héros, un split button, un groupe connecté,
      une mosaïque ;
    - les trois transitions de page, rejouables ;
    - `VLoading`, une snackbar avec action, une side sheet ;
  - la typographie ;
  - l'échelle d'espacement.

  En haut, des sélecteurs : clair / sombre / noir pur, source de couleur (3 pochettes
  d'exemple, Système, 2 préréglages) et « réduire les animations ». Test :
  `testWidgets('gallery renders every component without overflow', ...)` à 400 et 1280 dp.
- [ ] **Step 6 : commit** : `feat(app): système de design M3E (tokens, couleur, typo, composants, galerie)`.
- [ ] **Step 7 : point de contrôle utilisateur (bloquant).** Lancer la galerie sur le
  téléphone Android de référence et sur macOS (`flutter run --debug`, route
  `/debug/gallery`). Demander à l'utilisateur de la valider. Ses retours sont corrigés dans
  `design/` (tokens d'abord), avec le test de la galerie toujours vert, puis commités.
  Les tâches 5 à 7 ne commencent qu'après son accord, consigné dans le ledger
  (`Ruling (user): gallery approved`).

### Task 2 : traductions FR / EN et messages d'erreur

**État : terminée** (commits f0cfc40..0901a7a, revue propre après une ronde).

**Files :**
- Create : `app/l10n.yaml`, `app/lib/l10n/app_fr.arb`, `app/lib/l10n/app_en.arb`,
  `app/lib/l10n/errors.dart`
- Test : `app/test/l10n/l10n_test.dart`

**Interfaces (livrées) :**
- Produces : `AppLocalizations` (généré dans `lib/l10n/`, modèle `app_fr.arb`) ;
  `String errorMessage(AppLocalizations l, CoreError e)` — un `switch` exhaustif sur les 10
  variantes : `network`, `providerWall`, `rateLimited`, `budgetExceeded`, `notFound` (« Ce
  contenu n'est plus disponible. »), `expired`, `internal`, `offline`, `invalidFeed`,
  `noPlugin(capability)` (une phrase « Il te faut une source pour … » par capacité ; pour
  `resolve` : « Il te faut une source pour lire. », avec l'action « Ajouter une source »).
- `docs/voice.md` : règles et tableau des messages types FR/EN. Mots interdits en EN
  seulement : `repo`, `repository` (« repos » est un mot français).

**Ajouts — ton (spec UI §2.9) :** écrire `docs/voice.md` (règles + tableau des messages
types FR/EN de la maquette « Le ton des messages »), puis :

```dart
test('arb strings follow voice.md', ...); // aucun « ! », aucun emoji, aucun mot interdit
                                          // (plugin, dépôt, feed, résolution, oups, oops,
                                          // veuillez, please, codes HTTP), dans les deux langues
```

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

### Task 3 : lecteur (`platform/player.dart`) et API simulée de debug

**Files :**
- Create : `app/lib/platform/player.dart`, `app/lib/platform/player_errors.dart`,
  `app/lib/debug/fake_api.dart`
- Modify :
  - `app/pubspec.yaml` (`media_kit: 1.2.6`, `media_kit_libs_audio: 1.0.7`) ;
  - `app/lib/design/components/wave_progress.dart` : `VSeekable` perd `_held` et le `Timer`
    `_hold` (audit 13d) ;
  - `app/test/design/artwork_test.dart` : les tests du seek tenu sont réécrits (voir Step 1).
- Test : `app/test/platform/player_test.dart`, `app/test/platform/player_errors_test.dart`,
  `app/test/debug/fake_api_test.dart`

**Interfaces :**
- Consumes : `playerCommands()`, `playerEvent(e:)` (synchrone, `void` : appelé dans l'ordre
  des événements, jamais attendu), `reportPerf(metric:, valueMs:)` (plan 4) ; le type du pont
  `Source { uri, headers: List<(String, String)> }`.
- Produces :
  ```dart
  abstract interface class MediaBackend {        // media_kit en vrai, faux dans les tests
    Future<void> open(List<Source> items, {required bool play});
    Future<void> add(Source s); Future<void> removeAt(int index);
    Future<void> seek(Duration d); Future<void> play(); Future<void> pause(); Future<void> playOrPause();
    Future<void> setVolume(double percent);
    Stream<int> get index; Stream<Duration> get position; Stream<Duration> get duration;
    Stream<bool> get playing; Stream<bool> get completed; Stream<String> get errors;
  }
  class PlayerAdapter {
    PlayerAdapter(MediaBackend backend, {Stream<PlayerCommand>? commands, void Function(PlayerEvent e)? report}); // défauts : playerCommands(), playerEvent
    void start();                                  // écoute les commandes, émet les PlayerEvent
    ValueListenable<int> get position;             // ms ; VNowPlaying.position et les paroles
    Stream<Duration?> get duration; Stream<bool> get playing;
    Stream<bool> get loading;                      // vrai au markTap() ou à un Play ; faux à la première position > 0, à Error, à Stop
    ValueListenable<double> get volume;            // 0..1, le réglage de l'utilisateur
    Future<void> setVolume(double v);              // le backend reçoit v × gainToVolume(gain de l'entrée)
    Future<void> play(); Future<void> pause(); Future<void> togglePlay();  // play/pause pour l'écran verrouillé, toggle pour l'interface
    Future<void> seek(Duration d); Future<void> seekBy(Duration delta);
    void markTap();                                // horodatage pour la mesure du premier son
  }
  PlayerErrorKind classifyPlayerError(String mpvMessage);
  double gainToVolume(double gainDb);              // 100 × 10^(gain/20)
  // lib/debug/fake_api.dart
  class FakeApi implements RustLibApi {            // pas `extends Fake` : lib/ ne dépend pas de flutter_test
    FakeApi();                                     // données de lib/debug/library.dart
    final List<Invocation> calls;                  // chaque appel reçu, pour les tests
    final StreamController<PlayerCommand> commands;   // crateApiPlaybackPlayerCommands() le rend
    @override dynamic noSuchMethod(Invocation i);  // consigne l'appel puis lève UnimplementedError(nom du membre)
  }
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
  `ClearNext` → `removeAt(courant + 1)` s'il y en a une ; `Stop` → `pause` + `open([])` ;
  `Pause { fadeMs }` (minuterie de sommeil, plan 7 Task 8) → volume ramené à 0 en fondu sur
  `fadeMs` depuis `volume × gain`, `pause`, volume restauré, puis `Paused`. C'est une pause
  « système », conforme au contrat de `Paused`.
  L'adaptateur tient la liste `index mpv → entry` et le gain de chaque entrée (appliqué au
  changement d'index). Événements : `TrackStarted` à chaque changement d'index,
  `Duration` dès connue, `Position` toutes les 10 s pendant la lecture et à chaque pause,
  `Paused`/`Resumed`, `Seeked`, `Ended` quand `completed` sans suivante, `Error` classée
  avec `positionMs` = position au moment de l'erreur (un 403 reprend là ; en pause, Rust
  renvoie un `Play` sans autoplay ; 0 si le lecteur l'a perdue à l'ouverture : Rust garde
  la dernière connue).
- **Seek** (audit 13d) : `seek(d)` pose `d` dans `position` avant d'appeler le backend. Les
  positions du backend arrivées avant que `backend.seek` ait rendu sont ignorées ; ensuite
  `position` suit le backend. `seekBy` part de `position.value`. `design/` ne tient plus de
  seek : `VSeekable` affiche `_drag ?? widget.progress`.
- `MediaKitBackend` = `Player()` de media_kit ; en-têtes passés par
  `Media(uri, httpHeaders: Map.fromEntries(headers))`.
- `FakeApi` : données de `lib/debug/library.dart`. Cette tâche couvre les flux du lecteur
  (`playerCommands`, `playerEvent`, `nowPlaying`, `queueStates`) ; chaque tâche suivante y
  ajoute les appels qu'elle utilise et le liste dans ses Modify.

- [ ] **Step 1 : tests qui échouent** (`FakeBackend`, et les paramètres `commands`/`report`
  de `PlayerAdapter` à la place du pont)

```dart
test('play opens the source at the given position', ...);
test('pause command fades out, pauses, restores volume, reports Paused', ...);
test('auto_advance_reports_preloaded_entry', ...);   // EnqueueNext(e2) puis index 0→1 → TrackStarted(e2)
test('replace_next swaps the queued source', ...);
test('position is reported every 10s and on pause', ...); // fakeAsync
test('gain is applied when the track changes', ...);  // gainToVolume(-6) ≈ 50.1
test('user volume scales the gain and the sleep fade starts from it', ...); // setVolume(0.5), gain -6 → backend 25.05
test('pause when already paused stays paused', ...);  // pause() deux fois → aucun play
test('loading turns on at tap and off at the first position', ...);
test('classify_player_errors', ...);                  // échantillons en ligne : "...HTTP error 403 Forbidden" → forbidden ; "Failed to open ... Connection refused" / "timed out" → network ; "Failed to recognize file format" → decode ; autre → other
test('first position after a tap reports tap-to-first-sound', ...);
test('seek_publishes_its_target_at_once', ...);       // seek(90 s) → position.value == 90000 avant tout événement ; une position backend à 12 s pendant le seek est ignorée
test('fake api records calls and streams player commands', ...);  // fake_api_test.dart
// artwork_test.dart, réécrits :
testWidgets('a seek shows the given progress with no timer left', ...);   // remplace l'attente du seek tenu
testWidgets('arrow keys step from the progress the parent passes', ...);  // remplace « a second arrow during a held seek… »
```
- [ ] **Step 2 : vérifier l'échec** → FAIL.
- [ ] **Step 3 : vérifier media_kit d'abord** : `media_kit` ajouté, `flutter build apk --debug`
  et `flutter build macos --debug`. Si l'un échoue, s'arrêter et le rapporter.
- [ ] **Step 4 : implémenter.**
- [ ] **Step 5 : vérifier** : `cd app && flutter test` puis `flutter analyze` → PASS.
- [ ] **Step 6 : commit** — `feat(app): adaptateur du lecteur (commandes Rust, événements, seek immédiat) et API simulée de debug`.

### Task 4 : plateforme (écran verrouillé, téléchargements, réseau, chemins, liens, mises à jour, démarrage)

**Files :**
- Create :
  - `app/lib/platform/{lock_screen,downloads_service,network,paths,updates,errors,links,notifications}.dart` ;
  - `app/lib/design/components/splash_overlay.dart` (exporté par `design.dart`) ;
  - `app/android/app/src/main/kotlin/app/vehicoule/DownloadService.kt`,
    `app/android/app/src/main/kotlin/app/vehicoule/Installer.kt`,
    `app/android/app/src/main/res/xml/file_paths.xml`,
    `app/android/app/src/main/res/drawable/splash_mochi.xml` (vecteur animé),
    `app/android/app/src/main/res/values/strings.xml`,
    `app/android/app/src/main/res/values-fr/strings.xml` (textes natifs : actions de la
    notification) ;
  - `branding/icon/export.sh` : exporte, depuis `branding/icon/mochi_master.svg`, l'icône
    adaptative et monochrome Android, la tuile macOS, les icônes Windows et Linux et la
    variante ≤ 48 px (rail, barre des tâches).
- Modify :
  - `app/android/app/src/main/AndroidManifest.xml`, `MainActivity.kt` (canal
    `app.vehicoule/notifications`) ;
  - `app/macos/Runner/*.entitlements` (réseau sortant), `app/macos/Runner/Info.plist`
    (`CFBundleURLTypes`, schéma `vehicoule`) ;
  - `app/pubspec.yaml` (`audio_service: 0.18.19`, `connectivity_plus: 7.3.2`,
    `path_provider: 2.1.6`, `url_launcher: 6.3.3`, `app_links: 7.2.2`,
    `package_info_plus: 10.2.2`, `device_info_plus: 13.3.0`) ;
  - `app/lib/debug/fake_api.dart` (les appels de la tâche).
- Test : `app/test/platform/{lock_screen,downloads_service,network,links,notifications}_test.dart`,
  `app/test/design/splash_test.dart`

**Interfaces :**
- Consumes : `PlayerAdapter` (Task 3) ; `initApp`, `setOnline`, `nowPlaying`, `skipNext`,
  `previous(positionMs:)`, `setLiked`, `stop`, `downloadProgress`, `tracks`, `downloadUpdate`,
  `reportDartError`, `uiPref`/`setUiPref` (`ui.notif_asked`).
- Produces :
  ```dart
  Future<AppConfig> appConfig();                     // les 8 champs d'AppConfig : data = applicationSupport, cache = applicationCache,
                                                     // downloads = Android getExternalStorageDirectory()/music, macOS applicationSupport/downloads ;
                                                     // région = pays de la locale ; appVersion (package_info_plus) ; platform, osVersion, deviceModel (device_info_plus)
  class LockScreen extends BaseAudioHandler { LockScreen(PlayerAdapter p); } // play() → p.play(), pause() → p.pause(), seek → p.seek ;
                                                     // skipToNext → skipNext() ; skipToPrevious → previous(positionMs: p.position.value) ;
                                                     // customAction 'like' → setLiked, 'stop' → stop() ; mediaItem depuis nowPlaying() (artUri file://)
  class DownloadsService { void start(); }           // canal app.vehicoule/downloads : start/update(title, done, total)/stop selon downloadProgress() ;
                                                     // titres par tracks(ids) (plan 4)
  class Network { void start(); ValueListenable<bool> get online; } // connectivity_plus → setOnline et online
  Stream<Uri> links();                               // platform/links.dart : app_links, chaque vehicoule:// une fois ; branché Task 7 (add-source) et Task 10 (now-playing)
  Future<bool> requestNotificationPermission();      // platform/notifications.dart : Android 13+ par le canal de MainActivity
                                                     // (ActivityCompat.requestPermissions) ; true ailleurs
  Future<void> installUpdate(UpdateInfo u);          // Android : downloadUpdate puis canal app.vehicoule/update install(path) ; macOS : url_launcher(pageUrl)
  void installErrorHooks();                          // FlutterError.onError et PlatformDispatcher.onError → reportDartError
  class SplashOverlay extends StatefulWidget { const SplashOverlay({required Widget child}); } // macOS, Windows, Linux : la séquence du Mochi au premier frame
  ```
- Manifeste : `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`,
  `FOREGROUND_SERVICE_DATA_SYNC`, `POST_NOTIFICATIONS`, `REQUEST_INSTALL_PACKAGES`,
  `INTERNET`, `WAKE_LOCK` ; service audio_service `foregroundServiceType="mediaPlayback"` ;
  `com.ryanheise.audioservice.MediaButtonReceiver` déclaré (boutons du widget, Task 10) ;
  `DownloadService` `foregroundServiceType="dataSync"` ; `FileProvider` pour l'APK ; filtre
  d'intent `vehicoule://add-source`.
  `DownloadService` (service de premier plan) : actif seulement tant qu'un téléchargement
  est `Running` (pas pour `Queued` : hors ligne, la file attend sans service), arrêté sinon ; notification de progression mise à jour au rythme des événements
  (≤ 2/s, déjà limité par Rust).

**Ajouts — 8 sujets (spec UI §6.10, §6.11, §6.7) :**
- **Écran de démarrage** : Android 12+ par l'API SplashScreen avec une icône animée en vecteur
  (le Mochi rebondit, la note sort, ≤ 900 ms) ; macOS, Windows et Linux jouent la même séquence
  dans la fenêtre au premier frame (`SplashOverlay`). Rien au démarrage à chaud ;
  « réduire les animations » → icône fixe et fondu. Les ressources viennent de
  `branding/icon/`, fichiers Mochi de l'utilisateur, que le contrôleur demande avant la tâche.
  Sans eux, l'écran de démarrage et les icônes utilisent un remplaçant neutre (aucun Mochi
  inventé), la demande va dans la liste « Pending user confirmation » du ledger, et
  `export.sh` se relance à leur arrivée.
- **Lien profond** `vehicoule://add-source` : filtre d'intent Android, `CFBundleURLTypes` sur
  macOS, `links()`. Cette tâche s'arrête au flux ; la Task 7 ouvre `AddSourceSheet`.
- **Notification média** : like en action personnalisée d'audio_service (le cœur se remplit),
  et × pour arrêter. Libellés dans `strings.xml` (FR et EN).
- **Demande de notifications** : `requestNotificationPermission()` (Android 13+), appelée par le
  premier lancement et au premier téléchargement si `ui.notif_asked` dit « plus tard ».
- **macOS** : « En cours de lecture » et touches média via audio_service (infos de lecture du
  système).

```dart
test('links emits each vehicoule uri once', ...);
test('media notification exposes like and stop actions', ...);
test('notification permission is asked again only at the first download', ...);
testWidgets('splash is static with reduce motion', ...);
```

- [ ] **Step 1 : tests qui échouent**

```dart
test('lock screen skip goes through Rust, play/pause stays local', ...);
test('lock screen previous passes the current position', ...);   // previous(positionMs: position.value)
test('now playing becomes a media item with a file artUri', ...);
test('downloads service starts on first running download and stops when idle', ...); // canal de méthode simulé
test('network exposes online and calls setOnline', ...);
test('app config fills all eight fields', ...);
```
- [ ] **Step 2 : vérifier l'échec** → FAIL.
- [ ] **Step 3 : implémenter.**
- [ ] **Step 4 : vérifier** → `flutter test` puis `flutter analyze` → PASS ; sur l'émulateur,
  `flutter run` puis un téléchargement lancé et l'app mise en arrière-plan : la notification
  de progression reste et le fichier se termine.
- [ ] **Step 5 : commit** — `feat(app): écran verrouillé, téléchargements en arrière-plan, réseau, liens, mises à jour, démarrage`.

### Task 5 : routes et coques

**État : en rondes de correction.** La ronde 2 applique l'addendum §11 (navigation entre
domaines) avant le point de contrôle du shell ; le texte ci-dessous en tient compte. Les noms
du bloc Interfaces marqués « addendum » sont ceux du plan ; si la ronde en livre d'autres,
le code fait foi et ce bloc est corrigé au commit de la ronde.

**Files :**
- Create :
  - `app/lib/router.dart` ;
  - `app/lib/domains.dart` (addendum : la liste des domaines, `domainOf`, `sessionTarget`) ;
  - `app/lib/app_scope.dart` (`AppScope`) et `app/lib/screen_fab.dart` (`ScreenFab`,
    `ScreenFabHost`) ;
  - `app/lib/shell_mobile/{mobile_shell,mini_player,domain_rail}.dart` (le rail replié de la
    largeur moyenne est dans `mobile_shell.dart`) ;
  - `app/lib/shell_desktop/{desktop_shell,now_playing_pane,title_bar,pinned,shortcuts,immersive}.dart` ;
  - `app/lib/features/music/now_playing/now_playing_sheet.dart` (la feuille et le vol de la
    pochette ; contenus remplis à la Task 6) ;
  - `app/lib/theme_controller.dart`.
- Modify : `app/lib/main.dart`, `app/pubspec.yaml` (`go_router: 18.1.1`,
  `window_manager: 0.5.2`), `app/lib/debug/fake_api.dart`, ARB FR/EN.
- Test : `app/test/shell/{shell,mini_player,sheet,theme,shortcuts,screen_fab}_test.dart`.

**Interfaces :**
- Consumes : `design/` (Task 1, API livrée) ; `PlayerAdapter` (Task 3) ; `Network.online`,
  `LockScreen`, `DownloadsService`, `appConfig`, `installErrorHooks` (Task 4) ; API des plans
  4 et 7 : `nowPlaying`, `queueStates`, `skipNext`, `previous(positionMs:)`, `stop`,
  `undoStop`, `uiPref`, `setUiPref`, `artworkFile`, `onboarding`, `addToPlaylist`, `setLiked`,
  `download`, `notices`, `checkUpdates`.
- Produces :
  ```dart
  GoRouter buildRouter();   // un StatefulShellRoute.indexedStack ; branches : /home, puis destinationsOf(d) pour chaque d de `domains`
                            //   (v1 : /music/explore, /music/library), dans cet ordre ; aucun index écrit en dur ailleurs
                            // pages d'entité dans la branche d'où elles viennent, préfixées par le domaine :
                            //   /music/explore/{album,artist,playlist,category}/:id, /music/library/{album,artist,playlist}/:id,
                            //   /home/music/{album,artist,playlist,category}/:id
                            // /music/library/{liked,downloaded,top,history}
                            // globales, hors branches : /downloads, /sources, /settings, /settings/appearance, /settings/diagnostics,
                            //   /onboarding (redirect tant que onboarding().done == false), /debug/gallery (kDebugMode seulement)
                            // réservées, non déclarées en v1 : /anime/…, /books/…, /watch/:id, /read/:id
  void openItem(BuildContext context, String id, {Object? heroTag}); // seul constructeur de chemins d'entité : branche courante + domaine de l'item
  // domains.dart (addendum §3, §11)
  enum Domain { music }                                 // noms internes des paquets WIT ; anime et books s'ajoutent avec leurs specs
  const List<Domain> domains = [Domain.music];          // la seule liste : branches, barre, rail, rail des domaines
  class DomainDestination { const DomainDestination({required String path, required IconData icon,
    required String Function(AppLocalizations) label}); }
  List<DomainDestination> destinationsOf(Domain d);     // music : Explorer (/music/explore), Bibliothèque (/music/library)
  Domain domainOf(String location, {required Domain stored}); // /<d>/… ou /home/<d>/… → d ; sinon stored (= ui.domain)
  enum PlaybackSession { music }                        // la vidéo s'ajoute avec la spec anime
  PlaybackSession sessionTarget(BuildContext c);        // la session visée par les raccourcis ; v1 : toujours music
  class AdaptiveShell extends StatelessWidget { const AdaptiveShell({required StatefulNavigationShell shell}); } // windowClassOf : compact, medium → mobile ; expanded → desktop
  class AppScope extends InheritedWidget { const AppScope({required PlayerAdapter player, required ThemeController theme,
    required ValueListenable<bool> online, required ValueNotifier<Rect?> miniPlayerRect, required Widget child});
    static AppScope of(BuildContext c); } // miniPlayerRect : rect global de la toolbar du mini-lecteur (ou de la bande), pour l'arrimage (addendum §5.2)
  class ScreenFab extends StatefulWidget { const ScreenFab({VAction? action, List<VAction> items = const [], Widget? bar, required Widget child}); }
      // l'action principale d'un écran ; items non vide → FAB menu ; bar → remplace le mini-lecteur (sélection multiple)
  class ScreenFabHost extends StatefulWidget { const ScreenFabHost({required Widget Function(BuildContext, VAction? action, List<VAction> items, Widget? bar) builder}); }
      // fourni par la coque ; seule publie la ScreenFab dont la route est courante (ModalRoute.isCurrent) et la branche active (TickerMode.valuesOf(context).enabled)
  class DesktopShortcuts extends StatelessWidget { const DesktopShortcuts({required Widget child, required PlayerAdapter player, required VoidCallback focusSearch}); }
      // une table intent → action, la même pour la PlatformMenuBar ; les actions de lecture passent par sessionTarget(c)
  class ThemeController extends ChangeNotifier {
    ThemeData get light; ThemeData get dark; ThemeMode get mode; PlayerStyle get playerStyle; VCoverTop? get coverTop;
    Future<void> setSource(ColorSource s); Future<void> setPreset(int index); Future<void> setPureBlack(bool v);
    Future<void> setMode(ThemeMode m); Future<void> setPlayerStyle(PlayerStyle s);   // chacun : setUiPref puis notifyListeners
  } // clés ui.color_source, ui.preset, ui.pure_black, ui.theme, ui.player_style
  ```
- Règles (spec UI §4, §5.3, §5.4, §2.2 ; addendum §2, §3, §11) :
  - **Domaines** (addendum §11, points 3 à 5) :
    - `domainOf(location, stored:)` est la seule lecture du domaine courant ; aucun écran ni
      aucune coque ne parse la route pour le trouver ;
    - `ui.domain` (nom interne, `music`) est écrit à chaque changement de domaine et lu au
      lancement ; sur `/home` seul et sur une section globale, le domaine est `ui.domain` ;
    - la barre et le rail montrent Accueil + `destinationsOf(domainOf(location))` ; l'index
      sélectionné se calcule depuis la route, jamais écrit en dur ;
    - changer de domaine ouvre la dernière destination visitée de ce domaine (sa première au
      premier passage) ; l'Accueil ne change pas ;
    - le rail des domaines (☰ et bas du rail desktop) se construit depuis `domains` ; en v1
      il ne contient que Musique.
  - **Mobile** :
    - `VNavigationBar` à 3 destinations : Accueil, puis celles du domaine (Explorer,
      Bibliothèque) ;
    - une `VLargeAppBar` qui se replie, par onglet, avec ☰ à gauche. Celle de `/home` prévoit
      sous le titre la rangée de puces de domaine (Tout · Musique · …), **masquée** tant que
      `domains.length == 1` (addendum §4) ;
    - ☰ ouvre `domain_rail` : le rail déplié en modal, avec 1. les domaines (Musique), 2. les
      sections globales « Téléchargements » (`/downloads`), « Sources » (`/sources`),
      « Réglages » (`/settings`) ;
    - au-dessus de la barre : `ScreenFabHost` → `VFabDock(body: shell, fab: action, fabItems: items,
      player: bar ?? miniPlayer)`. Le FAB d'écran se place au-dessus du ⏯, se masque au
      défilement vers le bas et revient vers le haut. Sans titre chargé, pas de mini-lecteur :
      le FAB a le coin.
  - **Couches** (addendum §11 point 7), de bas en haut, sur les deux coques : le contenu ;
    le mini-lecteur et `VFabDock` (desktop : la bande ou le panneau) ; une **couche vidéo**
    libre (un `SizedBox.shrink()` en v1, rien n'y est dessiné) ; puis les feuilles,
    dialogues et snackbars du `Navigator`. La coque écrit le rect global de la toolbar du
    mini-lecteur (ou de la bande) dans `AppScope.miniPlayerRect` après chaque mise en page.
  - **Mini-lecteur** (spec UI §5.3) : `VNowPlaying(size: PlayerSize.compact)`. La toolbar, le
    `VPlayPauseFab` (loading indicator pendant un chargement), les gestes au seuil
    `VSize.swipe`, leurs haptiques et leurs entrées de menu sont dans `design/` ; la coque ne
    fournit que `NowPlayingActions` :
    - `onNext` → `skipNext()` ; `onPrevious` → `previous(positionMs: player.position.value)` ;
    - `onOpen` (↑ ou toucher) → la feuille du lecteur s'ouvre ;
    - `onStop` (↓) → `stop()`, puis `showVSnack` « Lecture arrêtée », action « Annuler » →
      `undoStop()`, pendant `VDurations.undo`.
  - **Lecteur plein écran mobile** (`now_playing_sheet.dart`, audit 13d) :
    - un `DraggableScrollableSheet` (extent 0 → 1) au-dessus de la coque ; `onOpen` l'anime
      vers 1, ⌄ ou un glisser vers le bas le ramène à 0 ;
    - pendant que l'extent est entre 0 et 1, un `VExtentFlight(extent, from: rect du disque du
      mini-lecteur, to: rect de la pochette du lecteur)` dessine la pochette, et les deux
      `VNowPlaying` ont `artworkVisible: false` ;
    - les deux rects viennent de `onArtworkRect`. Ils sont rendus après chaque mise en page,
      donc une feuille qui déplace le lecteur sans le reconstruire les rend périmés : `to` est
      gardé relatif au haut de la feuille et recalculé à chaque extent.
  - **Desktop** (spec UI §4.2) :
    - **Barre de titre** maison, sur macOS, Windows et Linux (`TitleBarStyle.hidden`,
      `DragToMoveArea`, place laissée aux boutons natifs à gauche) :
      - ← → (historique go_router, ⌘[ ⌘]) ;
      - `VSearchBar` au centre (⌘F). Ses suggestions sont celles de la Task 6
        (`suggestions_view.dart`), en menu déroulant ; Entrée ouvre les résultats dans Explorer ;
      - à droite, téléchargements, puis Sources.
    - **Rail** `VNavigationRail`, permanent, replié ↔ déplié (`ui.rail_expanded`) :
      - Accueil et les destinations du domaine courant (3 en v1) ;
      - `fab`/`fabItems` = la `ScreenFab` publiée (le FAB de la destination : « Lancer »
        sur Accueil, « Nouvelle » sur Bibliothèque, « Ajouter une source » sur Sources) ;
      - « Épinglés » **du domaine courant** (`pinned.dart`) : ids dans `ui.pinned.<domaine>`
        (JSON ; v1 `ui.pinned.music`, jamais `ui.pinned`), par défaut Likés et Téléchargés ;
        pochettes seules quand le rail est replié ;
      - en bas, le choix du domaine (depuis `domains`), puis les sections globales
        Téléchargements, Sources, Réglages. ⌘, ouvre toujours `/settings`.

      Déposer une sélection de titres sur un épinglé fait ceci : playlist → `addToPlaylist` ;
      Likés → `setLiked` pour chaque id ; Téléchargés → `download` (la Task 6 le fait passer
      par `startDownload`).
    - **Panneau à droite** : `VNowPlaying(size: PlayerSize.medium, volume: VVolume(…))` dans un
      `VSideSheet`. Replié, c'est une **bande de 76 px** : `VNowPlaying(size:
      PlayerSize.compact, axis: Axis.vertical, volume: VVolume(vertical: true, …))`.
      `ui.now_playing_open` est retenu ; sans valeur, déplié si la largeur ≥
      `VBreakpoints.paneOpen`, replié sinon. Pas de barre en bas.
    - **Immersif** (`immersive.dart`) : l'icône ⤢ du panneau (`onImmersive`), ou ⌘⇧F.
      `VNowPlaying(size: PlayerSize.large, immersive: true, wide: true)` sur toute la fenêtre
      (pochette à gauche, vue Paroles ou File à droite). Échap pour sortir.
    - **Fenêtre** :
      - taille minimale 840 × 600 ; taille et position enregistrées dans `ui.window_bounds`
        (sur `onWindowResized`/`onWindowMoved`, après `VDurations.debounce`) et restaurées ;
      - fermer la fenêtre garde la lecture (l'app reste dans le Dock) ; ⌘Q quitte ;
      - la `PlatformMenuBar` macOS (Lecture, Aller, Fenêtre) prend ses actions dans la table de
        `DesktopShortcuts`.
    - **Raccourcis** : tout le tableau de la spec UI §4.2, aucun quand un champ texte a le
      focus. Chaque action de lecture demande d'abord `sessionTarget(c)` (addendum §5.3) ; en
      v1 c'est toujours `PlaybackSession.music`. ⌘↑/⌘↓ → `player.setVolume(±0,1)` ; Suppr agit seulement dans la vue File et une
      playlist perso (retrait différé, Task 6) ; Espace sélectionne quand le focus est dans un
      tableau de titres, sinon lecture/pause.
  - **Ce qui joue** : la coque fournit `NowPlayingScope(trackId:, contextId:, playing:)` depuis
    `nowPlaying()`, `queueStates()` et `player.playing`. Chaque `VArtwork` le lit. Aucun écran
    ne recalcule cette information.
  - **Hors ligne** : sous l'app bar de chaque destination, `VOfflineChip` tant que
    `AppScope.of(c).online.value` est faux.
  - **Notices** : un seul écouteur de `notices()`, dans `router.dart`, au-dessus des deux
    coques : `skipped` → `showVSnack` (texte : Task 6), `updateAvailable` → la feuille de mise à
    jour (Task 7), `error` → `showVSnack(errorMessage(l, e))`.
  - **Transitions** : chaque route go_router prend sa page dans `motion.dart`. Les pages
    album, artiste, playlist et catégorie s'ouvrent en `vContainerTransformPage` (tag unique
    par source : route + étagère + id) ; le changement de destination se fait en
    `vFadeThroughPage`.
  - **Chemins** : `openItem` construit tous les chemins d'entité (branche courante + domaine
    de l'item) ; une page ouverte depuis l'Accueil reste dans la branche Accueil
    (`/home/music/album/:id`, Accueil sélectionné, barre du domaine Musique). Aucune autre
    route ne s'écrit en dur hors de `router.dart` et `domains.dart`.
  - **Thème** :
    - la graine du titre qui joue vient de `seedForArtwork(artworkPath, fallback:)`, une fois
      par titre ; `fallback` = `systemSeed()`, sinon le préréglage choisi. `coverTop` vient de
      `coverTopFromArtwork` en même temps ;
    - le changement de couleur se fait en fondu de `VDurations.themeFade` (`AnimatedTheme`),
      seulement quand le titre change ; sans fondu avec `reduceMotion` ;
    - la source `system` lit `systemSeed()`.
- `main.dart` :
  1. `RustLib.init()` (en `kDebugMode` avec `--dart-define=VEHICOULE_FAKE=true` :
     `RustLib.initMock(api: FakeApi())`), `installErrorHooks()`, `initApp(await appConfig())`,
     `AudioService.init(LockScreen)`, `windowManager` (desktop), `vRegisterFontLicenses()` ;
  2. les abonnements de `PlayerAdapter`, `LockScreen`, `Network`, `DownloadsService` et
     `ThemeController` ; le volume lu dans `ui.volume`, réécrit à chaque `setVolume` ;
  3. **puis `start()`**, pour que la restauration de la file et la reprise des
     téléchargements arrivent sur des flux déjà écoutés ;
  4. puis `runApp` (`MaterialApp.router` avec `localizationsDelegates:
     vLocalizationsDelegates`, `builder: vAppBuilder`, sous `AppScope`) ;
  5. après le premier frame : `checkUpdates(force: false)`, jamais bloquant.

  Une mise à jour n'est affichée que par `Notice.updateAvailable(UpdateInfo)`.

**Ajouts — 8 sujets (spec UI §4.3, §4.4) :**
- Largeur moyenne : la coque mobile avec le rail replié à gauche à la place de la barre du
  bas ; mini-lecteur et `VFabDock` inchangés.
- Clavier : ordre de Tab barre de titre → rail → contenu → panneau ; focus itinérant dans les
  tableaux et grilles (Entrée lit, Espace sélectionne dans une liste, Menu / ⇧F10 ouvre le
  menu, Échap ferme) ; une ligne focalisée montre ▶.

```dart
testWidgets('medium width uses the collapsed rail instead of the bottom bar', ...);
testWidgets('tab order is title bar, rail, content, panel', ...);
testWidgets('arrow keys move focus inside a track table', ...);
```

- [ ] **Step 1 : tests qui échouent** (API simulée : `FakeApi` de `lib/debug/fake_api.dart`)

```dart
testWidgets('narrow width uses the navigation bar and mini player', ...);   // 400 dp : 3 destinations (Accueil, Explorer, Bibliothèque)
testWidgets('menu button opens the modal rail with domains and global sections', ...);
// addendum §11 point 10
testWidgets('settings is a global section, not a bar destination', ...);  // ☰ et bas du rail : Téléchargements, Sources, Réglages ; aucune destination Réglages ; ⌘, → /settings
testWidgets('the domain comes from the route', ...);                      // /music/explore → music ; /home/music/album/x → music ; /home → ui.domain
testWidgets('an album opened from home stays in the home branch', ...);   // openItem depuis /home → /home/music/album/:id, Accueil sélectionné
testWidgets('pinned are stored per domain', ...);                         // épingler → setUiPref("ui.pinned.music", …) ; jamais "ui.pinned"
testWidgets('home app bar keeps the chip row hidden with one domain', ...);
testWidgets('the video layer sits between the mini player and the overlays', ...); // ordre de la pile ; AppScope.miniPlayerRect == rect de la toolbar
testWidgets('900 dp starts with the collapsed strip, no bottom bar', ...);
testWidgets('android tablet at 900 dp has no title bar', ...);
testWidgets('the playing album is a cookie in lists, shortcuts and pinned', ...);   // NowPlayingScope : contexte = album X → toutes ses VArtwork en playing
testWidgets('offline shows the chip under the app bar', ...);
testWidgets('1280 dp starts with the side sheet; collapsing is remembered', ...); // replier → ui.now_playing_open = "false" ; relance → bande
testWidgets('immersive opens from the pane icon and closes with Escape', ...);
testWidgets('dropping tracks on a pinned playlist adds them', ...);
testWidgets('title bar history buttons navigate back and forward', ...);
testWidgets('mini player swipe left skips, right goes back with the position', ...); // skipNext() ; previous(positionMs:)
testWidgets('mini player swipe down stops and Annuler undoes', ...);        // stop() puis undoStop() ; sans Annuler pendant VDurations.undo : un seul stop()
testWidgets('the artwork flies with the sheet extent, no Hero', ...);       // extent 0 → rect du disque, 1 → rect du lecteur, 0,5 → entre les deux ; aucun Hero
testWidgets('only the visible screen publishes its FAB', ...);              // téléphone : au-dessus du ⏯ ; desktop : en haut du rail ; branche cachée : rien
testWidgets('a selection bar replaces the mini player while it is set', ...);
testWidgets('theme seed changes once per track, not per position', ...);    // 3 NowPlaying même titre → 1 seedForArtwork
testWidgets('a colourless cover gives the fallback seed, not the previous one', ...);
testWidgets('theme setters persist then notify', ...);                      // setPlayerStyle(wave) → setUiPref("ui.player_style", "wave") puis notifyListeners
testWidgets('every 4.2 shortcut reaches its action', ...);                  // une table : touche → appel attendu sur FakeApi / PlayerAdapter
testWidgets('shortcuts_ignored_while_typing', ...);                         // focus dans la search bar, Espace → texte " ", lecteur inchangé
testWidgets('space selects in a focused track table', ...);
testWidgets('cmd+f focuses search', ...);                                    // desktop : le champ de la barre de titre ; mobile : /music/explore
testWidgets('playback shortcuts go through sessionTarget', ...);             // Espace → la session rendue par sessionTarget (music en v1)
testWidgets('menu bar items and shortcuts share one intent table', ...);
testWidgets('window bounds are saved and restored', ...);
testWidgets('first launch redirects to onboarding', ...);
```
- [ ] **Step 2 : vérifier l'échec** → FAIL.
- [ ] **Step 3 : implémenter.**
- [ ] **Step 4 : vérifier** : `flutter test` puis `flutter analyze` → PASS.
- [ ] **Step 5 : commit** : `feat(app): routes, coques mobile et desktop, mini-lecteur à gestes, feuille du lecteur, thème suivant la lecture`.
- [ ] **Step 6 : point de contrôle utilisateur du shell (bloquant).** Lancer l'app en debug
  avec `FakeApi` (`flutter run --debug --dart-define=VEHICOULE_FAKE=true`) sur le téléphone
  Android de référence et sur macOS. Écrans fictifs simples, sans contenu réel. Captures à
  taille réelle dans `task-5-screenshots/`, chacune à côté de sa maquette :
  `lecteur-v3.html` (mini-lecteur, lecteur Disque et Vague, sélecteur, vues Paroles et File),
  `desktop-2.html` (barre de titre, rail replié et déplié avec son FAB, panneau, bande,
  immersif), `app-formes.html` (FAB d'écran au-dessus du ⏯) ; la liste des écarts va dans le
  rapport. Faire valider :
  - la barre du bas, le ☰ et le rail modal ;
  - le rail desktop replié et déplié, avec le FAB de la destination ;
  - la barre de titre (recherche, ← →), les épinglés et le glisser-déposer ;
  - le panneau « en lecture » déplié, puis replié en bande (fenêtre redimensionnée en
    direct), puis l'immersif ;
  - les deux styles du lecteur (Disque, Vague), le sélecteur Paroles · Lecteur · File ;
  - le mini-lecteur : toolbar + FAB, anneau, like, ⏯, les 4 gestes avec l'Annuler, et le FAB
    d'écran au-dessus du ⏯ ;
  - l'ouverture du lecteur, la pochette qui suit la feuille ;
  - le thème qui suit la pochette, le repli pour une pochette sans couleur, et « réduire les
    animations ».

  Ses retours sont corrigés dans `design/` ou les coques, avec les tests verts, puis commités.
  La tâche 6 ne commence qu'après son accord, consigné dans le ledger
  (`Ruling (user): shell approved`).

### Task 5r : identifiant `com.vehicoule` et domaine `vehicoule.com` (addendum §12)

Une tâche isolée, après le commit de la Task 5 et avant son point de contrôle. L'identifiant
de l'app devient **`com.vehicoule`** et son domaine **`vehicoule.com`** (sous-domaines
`feeds.`, `updates.`, `telemetry.`), avant toute release : l'identifiant ne change plus
ensuite. Cette tâche réécrit aussi les plans, celui-ci compris : son texte ne nomme les
anciennes valeurs que dans les deux expressions de recherche ci-dessous, qui ne se
trouvent pas elles-mêmes.

**Files :**
- Move : le dossier du paquet Kotlin sous `app/android/app/src/main/kotlin/` (l'ancien
  identifiant découpé en dossiers) → `app/android/app/src/main/kotlin/com/vehicoule/`
  (`git mv`), `package com.vehicoule` dans chaque fichier ; de même pour
  `app/android/app/src/androidTest/kotlin/` s'il existe.
- Modify :
  - `app/android/app/build.gradle.kts` (`namespace`, `applicationId`) ;
  - `app/macos/Runner/Configs/AppInfo.xcconfig` (`PRODUCT_BUNDLE_IDENTIFIER`),
    `app/macos/Runner/Info.plist` (`CFBundleURLName`),
    `app/macos/Runner.xcodeproj/project.pbxproj`,
    `app/macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme`,
    `app/ios/Runner.xcodeproj/project.pbxproj`, `app/linux/CMakeLists.txt` ;
  - les canaux de plateforme (`com.vehicoule/notifications`, `com.vehicoule/downloads`,
    `com.vehicoule/update`, l'id de canal de notification `com.vehicoule.playback`) dans
    `MainActivity.kt` et `app/lib/platform/{downloads_service,lock_screen,notifications,updates}.dart` ;
  - `core/core/src/android.rs` (symbole JNI `Java_com_vehicoule_RustInit_initVerifier`),
    `core/core/src/{app,keys,updates}.rs` (`https://feeds.vehicoule.com/official/feed.json`,
    `https://updates.vehicoule.com/releases`, le chemin de cache macOS du commentaire),
    puis le pont régénéré (`app/lib/bridge/**`, jamais à la main) ;
  - `core/plugin-host/src/engine.rs` (User-Agent `Vehicoule/<version> (+https://vehicoule.com)`),
    `core/plugin-host/tests/net.rs` ;
  - les tests Dart : `app/test/platform/{downloads_service,links,notifications,paths}_test.dart`,
    `app/integration_test/bridge_test.dart` ;
  - `probes/**` (supprimé à la Task 8, renommé ici pour que la recherche soit vide) ;
  - `docs/superpowers/plans/2026-10-19-*.md`, `2026-10-23-*.md`,
    `docs/superpowers/specs/2026-10-18-socle-musique-design.md` (§12 et chaque adresse).
- Ne change pas : `docs/superpowers/specs/2026-10-25-navigation-domaines.md`, qui consigne
  la décision et doit garder les deux anciennes valeurs ; c'est la seule exclusion des
  recherches du Step 3 (ruling : la réécrire lui ferait dire « renommer X en X »).
- Test : `core/core/src/android.rs` (`#[cfg(test)]`), les tests modifiés ci-dessus.

**Interfaces :**
- Produces : identifiant `com.vehicoule` (Android `applicationId` et `namespace`, bundle
  macOS et iOS, `APPLICATION_ID` Linux, préfixe des canaux de plateforme) ; domaine
  `vehicoule.com`. Les plans 8 et suivants les emploient tels quels.

- [ ] **Step 1 : tests qui échouent.** Mettre les nouvelles valeurs dans les attentes :
  `descriptive_user_agent_is_set` (plugin-host) attend `(+https://vehicoule.com)` ; les
  tests Dart de canal attendent `com.vehicoule/…` ; `paths_test` attend
  `Application Support/com.vehicoule` ; et un nouveau test Rust :
  ```rust
  #[test] fn jni_symbols_follow_the_kotlin_package() // lit le fichier `RustInit.kt` sous kotlin/com/vehicoule/, en tire `package com.vehicoule`,
                                                    // et vérifie que android.rs déclare Java_com_vehicoule_RustInit_<fn> pour chaque `external fun`
  ```
  `cargo test -p plugin-host -p vehicoule-core` et `flutter test test/platform` → FAIL.
- [ ] **Step 2 : renommer** (fichiers ci-dessus ; `git mv` pour le paquet Kotlin).
  L'app installée avec l'ancien identifiant devient une autre app : ses données de dev ne
  sont pas migrées (rien n'est sorti).
- [ ] **Step 3 : vérifier que rien ne reste**, les trois commandes doivent être vides (contenu,
  symboles JNI et chemins de plans, chemins de fichiers) :
  ```bash
  git grep -n -E "app\.vehicoule|vehicoule\.app" -- ':!docs/superpowers/specs/2026-10-25-navigation-domaines.md'
  git grep -n -E "app[/_]vehicoule" -- ':!docs/superpowers/specs/2026-10-25-navigation-domaines.md'
  git ls-files | grep -E "app[/_]vehicoule"
  ```
- [ ] **Step 4 : vérifier** : `cargo test --workspace` (dans `core/`), `cargo clippy
  --workspace --all-targets -- -D warnings`, `cd app && flutter test`, `flutter analyze`,
  `flutter build apk --debug`, `flutter build macos --debug` → PASS. Puis lancer l'app sur
  l'émulateur Android (`flutter run --debug`) : elle démarre et charge l'accueil (le symbole
  JNI est trouvé), et sur macOS.
- [ ] **Step 5 : consigner au ledger**, dans « Pending user confirmation » : les
  enregistrements DNS de `vehicoule.com` et les règles de redirection `feeds.`, `updates.`,
  `telemetry.` (addendum §3.1), et la republication du feed officiel à sa nouvelle adresse.
  Ce sont des étapes de l'utilisateur ; d'ici là, les vérifications passent par le feed de
  dev local.
- [ ] **Step 6 : commit** : `chore: identifiant com.vehicoule et domaine vehicoule.com (addendum §12)`.

### Task 5b : fil d'accueil et données du cœur pour la spec UI v2 (Rust, avant la Task 6)

Aucune fonction de la spec UI v2 n'est coupée : les données qui manquent viennent du cœur, ici.
L'implémenteur vérifie d'abord ce qui existe déjà, puis n'ajoute que ce qui manque, en TDD.

**Files :**
- Modify : `core/core/src/home/mod.rs` (items 1 à 3) ; pour les items 4 à 12, les modules du
  cœur qui portent la donnée (`core/core/src/{plugins,player}.rs`,
  `core/core/src/api/*.rs`, `core/core/src/library/**`), puis le pont régénéré
  (`app/lib/bridge/**`, jamais à la main) et `app/lib/debug/fake_api.dart` (les nouveaux
  appels).
- Test : tests Rust à côté du code (`#[cfg(test)]`), `cargo test -p core`.

**Items :**

Issus de la revue finale du plan 7 (`final-rereview.md`), dans `core/core/src/home/mod.rs` :

1. `failure()` ne compte pas `NotFound` (radio vide) comme une panne réseau. Test : toutes
   les radios répondent vide en ligne → le fil est reconstruit, pas figé.
2. La page 1 s'arrête sur une étagère « Parce que tu as écouté » non chargée au lieu de la
   sauter, **seulement quand `ask`** (découvertes activées et en ligne) ; sinon elle garde
   `continue`. Test : 4 étagères locales vides devant la 2ᵉ BYL → elle arrive en page 2,
   chargée ; hors ligne, la page 1 n'est pas coupée.
3. Un build réseau demandé, l'appareil désormais hors ligne et un doc existant → `Offline`,
   rien n'est écrit. Test : le doc stocké reste identique à l'octet près.

Données du cœur pour la spec UI v2 (Rust + pont régénéré) :

4. Activer / désactiver une source : `set_plugin_enabled(id, enabled)`, état dans
   `installed_plugins` (`PluginView.enabled`). Une source désactivée n'est plus routée.
   (Écran Sources, Task 7.)
5. Mise à jour d'un feed signée par une autre clé : refusée avec une erreur distincte
   (`FeedView.error: Option<FeedErrorKind>` avec `KeyChanged`, ou équivalent), pour que l'écran
   Sources montre le message de spec UI §6.7. (Task 7.)
6. Taille de la mise à jour dans `UpdateInfo` (la taille de l'asset de la release). (Feuille de
   mise à jour, Task 7.)
7. `playlists_containing(track_id) -> Vec<String>` pour « Ajouter à une playlist » (cookie +
   coche). (Task 6.)
8. Candidats de « Ce n'est pas le bon morceau » avec la source et la durée, et un moyen de
   lire un candidat avant de le choisir, sans le retenir. (Task 6.)
9. Progression de l'import page par page (`LibraryChanged::ImportProgress { page, pages }` ou
   un flux équivalent), pour la progression ondulée. (Task 7.)
10. Année et durée totale d'un album dans `CollectionView` (en-tête de spec UI §6.4). (Task 6.)
11. La source en cause dans `CoreError::ProviderWall` et `Notice::Skipped`, pour « YouTube
    bloque ce titre pour l'instant » (spec UI §2.9). (Task 6 : `errorMessage` et le texte de
    `Notice.skipped` prennent le nom.)
12. Radio depuis un titre : `play_radio(track_id)` (la file devient la radio de ce titre),
    pour « Radio de ce que j'écoute » (FAB menu de l'Accueil) et l'entrée « Radio » des
    split buttons des likés et téléchargés. (Tasks 6 et 7.)

La Task 6 repart de la page 1 à chaque `LibraryChanged::Home`, et continue à charger tant
qu'une page a moins de deux étagères hors écran.

- [ ] **Step 1 : tests qui échouent** (un test Rust par item, noms en `snake_case`
  reprenant l'item) → `cargo test -p core` FAIL.
- [ ] **Step 2 : implémenter les items 1 à 3** → `cargo test -p core home::` PASS. Commit —
  `fix(core): fil d'accueil — NotFound n'est pas une panne, page 1 s'arrête sur une BYL non chargée, build hors ligne n'écrit rien`.
- [ ] **Step 3 : implémenter les items 4 à 12**, régénérer le pont, étendre `FakeApi` →
  `cargo test -p core`, `cargo clippy -p core`, puis `cd app && flutter test` et
  `flutter analyze` → PASS. Commit —
  `feat(core): données de la spec UI v2 (sources activables, clé changée, taille de mise à jour, playlists d'un titre, candidats écoutables, progression d'import, année et durée, source bloquante, radio d'un titre)`.

### Task 5c : proxy média local (Rust, crate `stream`) et mpv limité à `127.0.0.1`

Surface d'attaque §2 et §9 : mpv ne reçoit plus jamais l'URL d'un plugin. Il suivait seul les
redirections et les playlists HLS, hors de la liste de domaines et du refus des IP privées du
socle §4.3. Désormais un serveur de `stream`, sur `127.0.0.1`, fait chaque requête avec les
règles du plugin. Le plan 4 est clos : la tâche vit ici, avant les écrans d'écoute.

**Files :**
- Create : `core/stream/src/proxy.rs` (serveur, sessions, plages d'octets),
  `core/stream/src/hls.rs` (réécriture des playlists, fonction pure),
  `core/stream/tests/proxy.rs`, `app/integration_test/mpv_whitelist_test.dart`.
- Modify :
  - `core/stream/Cargo.toml` : `hyper` 1 (`server`, `http1`), `hyper-util` (`tokio`),
    `http-body-util`, `bytes`, `tokio` (`net`, `sync`, `macros`), `uuid` du workspace (plus
    la fonction `v4`, pour les jetons). Justification (surface
    §7.2) : un serveur HTTP/1 minimal ; hyper est déjà dans le graphe par reqwest, Rust pur,
    projet hyperium ; le stdlib n'a pas de serveur HTTP ;
  - `core/stream/src/lib.rs` (`pub mod proxy; mod hls;`, `StreamError::Refused(String)`) ;
  - `core/core/src/app.rs` (`App.proxy`, démarré dans `init`),
    `core/core/src/player.rs` et `core/core/src/player/tests.rs` (chaque `Source` envoyée
    au lecteur est une URL du proxy ; sessions fermées quand l'entrée quitte la courante et
    la suivante ; erreur typée) ;
  - `app/lib/platform/player.dart`, `app/test/platform/player_test.dart` ;
  - `app/macos/Runner/Release.entitlements` (`com.apple.security.network.server`, que
    `DebugProfile.entitlements` a déjà) ;
  - `app/lib/debug/fake_api.dart` (ses `PlayerCommand` portent des URL `http://127.0.0.1:…`).
- Test : les fichiers ci-dessus.

**Interfaces :**
- Consumes : `Host::check_url(&Plugin, &str)`, `Host::http_client(&Plugin)` (plugin-host :
  chaque connexion et chaque redirection, 5 au plus, passent la liste du plugin ; DNS filtré,
  IP privées refusées) ; `Resolution { plugin, source: Source { uri, headers }, mime, … }`
  et `source_for` (fichier téléchargé ou réseau) de `player.rs`.
- Produces :
  ```rust
  // core/stream/src/proxy.rs
  pub type UrlCheck = Arc<dyn Fn(&reqwest::Url) -> Result<(), String> + Send + Sync>;
  pub enum Upstream {
      Remote { client: reqwest::Client, url: reqwest::Url, headers: Vec<(String, String)>, check: UrlCheck },
      File { path: PathBuf },
  }
  pub struct Proxy;                                   // Clone ; un seul par App
  impl Proxy {
      pub async fn start() -> std::io::Result<Proxy>; // écoute 127.0.0.1:0 (port aléatoire)
      pub fn open(&self, up: Upstream) -> ProxySession;
      pub fn close(&self, token: &str);
      pub fn take_error(&self, token: &str) -> Option<StreamError>; // la dernière requête refusée de la session
  }
  pub struct ProxySession { pub token: String, pub url: String } // url = http://127.0.0.1:<port>/<token>/0
  // core/stream/src/hls.rs
  pub(crate) fn is_playlist(content_type: Option<&str>, head: &[u8]) -> bool; // types mpegurl, ou corps commençant par #EXTM3U
  pub(crate) fn rewrite(body: &str, base: &reqwest::Url, mut map: impl FnMut(reqwest::Url) -> String) -> String;
  ```
  `PlayerCommand::{Play, EnqueueNext, ReplaceNext}` portent `source.uri` = l'URL du proxy et
  `source.headers` vide : les en-têtes du plugin restent côté Rust.
- Règles (surface §2) :
  - **Jeton** : 122 bits aléatoires (`uuid::Uuid::new_v4`, en hexadécimal) par session de
    lecture, dans le chemin. Jeton inconnu ou fermé → 404. Chemins : `/<jeton>/0` (la source)
    et `/<jeton>/u/<n>` (l'URL n° n d'une playlist réécrite, gardée côté Rust : mpv ne voit
    jamais d'URL externe).
  - **Chaque requête** vers l'amont passe `check` (la liste du plugin) puis le client du
    plugin (redirections vérifiées, IP privées refusées après DNS). Refus → réponse 502 à mpv,
    `StreamError::Refused` gardé pour `take_error`. Jamais 403 : mpv le classerait
    `Forbidden` et relancerait la résolution.
  - **Plages** : l'en-tête `Range` de mpv est transmis tel quel ; 206, `Content-Range`,
    `Content-Length` et `Content-Type` de l'amont reviennent tels quels. Un fichier local est
    servi avec la même sémantique (`bytes=a-b`, `bytes=a-`).
  - **HLS** : une réponse qui est une playlist (`is_playlist`) est lue entière (plafond
    1 Mio) et réécrite : chaque ligne d'URI, et l'attribut `URI="…"` de `#EXT-X-KEY`,
    `#EXT-X-MAP`, `#EXT-X-MEDIA`, `#EXT-X-I-FRAME-STREAM-INF`, résolus contre l'URL de la
    playlist, deviennent `/<jeton>/u/<n>`. Une URL que `check` refuse n'est pas ajoutée à la
    table : la ligne devient une URL du proxy qui répond 502.
  - **Fichiers et cache** : un titre téléchargé passe aussi par le proxy (`Upstream::File`) ;
    mpv ne reçoit jamais `file://`.
  - **Debug** : rien ne change pour le feed de dev local (`127.0.0.1:65200`) : le proxy ne
    touche ni le téléchargement des feeds ni celui des plugins (`plugins.rs`), et les URL
    de lecture qu'ils rendent passent le proxy comme les autres.
- Règles mpv (`MediaKitBackend`, à la création du `Player`, par `NativePlayer.setProperty`) :
  `ytdl=no`, `load-scripts=no`, `access-references=no`, `load-unsafe-playlists=no`,
  `stream-lavf-o=protocol_whitelist=[http,tcp,crypto]`,
  `demuxer-lavf-o=protocol_whitelist=[http,tcp,crypto]` (`crypto` : clés AES-128 du HLS,
  servies par le proxy). `PlayerAdapter` refuse toute `Source` dont l'URI ne commence pas par
  `http://127.0.0.1:` : il n'appelle pas le backend et rapporte
  `PlayerEvent.error(kind: other)`.

- [ ] **Step 1 : tests qui échouent**
  ```rust
  // core/stream/tests/proxy.rs (wiremock pour l'amont, reqwest pour jouer mpv)
  #[tokio::test] async fn hls_segment_to_a_private_ip_is_refused()   // playlist dont un segment est http://10.0.0.1/s.ts → ce segment 502, take_error == Some(Refused), les autres 200
  #[tokio::test] async fn redirect_outside_the_plugin_domains_is_refused() // 302 vers un hôte hors liste → 502, Refused
  #[tokio::test] async fn wrong_token_is_404()
  #[tokio::test] async fn closed_session_is_404()
  #[tokio::test] async fn range_is_forwarded_and_206_comes_back()   // Range: bytes=100-199 → 206, Content-Range et 100 octets
  #[tokio::test] async fn local_file_is_served_with_ranges()
  #[tokio::test] async fn rewritten_playlist_holds_no_external_url() // variante, segments, EXT-X-KEY, EXT-X-MAP → toutes en http://127.0.0.1:<port>/<jeton>/u/<n>
  #[test] fn rewrite_resolves_relative_uris_against_the_playlist()
  // core/core/src/player/tests.rs
  #[tokio::test] async fn player_commands_carry_proxy_urls_only()   // Play, EnqueueNext, ReplaceNext, et un titre téléchargé : uri commence par http://127.0.0.1:, headers vides
  #[tokio::test] async fn sessions_close_when_entries_leave()        // après Play d'une autre piste, l'ancienne URL → 404
  ```
  ```dart
  // app/test/platform/player_test.dart
  test('mpv joins no other host', ...);       // « mpv ne joint aucun autre hôte » : Play d'une Source https://cdn.example/x → backend.open jamais appelé, Error(other) rapportée ;
                                              // les options de MediaKitBackend.mpvOptions contiennent les deux protocol_whitelist et ytdl=no
  test('release entitlements allow the proxy', ...); // macos/Runner/Release.entitlements contient com.apple.security.network.server
  // app/integration_test/mpv_whitelist_test.dart (macOS, vrai mpv)
  testWidgets('mpv refuses file and other hosts', ...); // avec les options : file:///System/Library/Sounds/Ping.aiff → erreur ;
                                              // une playlist servie en local dont le segment est file:// → erreur ; une source du proxy → du son (position > 0)
  ```
  `cargo test -p vehicoule-stream -p vehicoule-core` et `flutter test test/platform` → FAIL.
- [ ] **Step 2 : implémenter** `stream::proxy` et `stream::hls`, puis le branchement dans
  `player.rs` : `send_play` et l'envoi de la suivante ouvrent une session par entrée
  (`Upstream::Remote` avec `host.http_client(&plugin)` et un `check` qui appelle
  `host.check_url(&plugin, …)`, ou `Upstream::File`) ; une `PlayerEvent::Error` de l'entrée
  consulte `take_error` : `Refused` est consigné (`logs::push`, sans URL) et traité comme une
  erreur réseau, jamais comme `Forbidden`.
- [ ] **Step 3 : implémenter le côté Dart** : `MediaKitBackend.mpvOptions` (la table
  ci-dessus, appliquée à la création) et le refus dans `PlayerAdapter`.
- [ ] **Step 4 : vérifier** : `cargo test -p vehicoule-stream -p vehicoule-core` (deux fois),
  `cargo clippy --workspace --all-targets -- -D warnings`, `cd app && flutter test`,
  `flutter analyze`, `flutter test integration_test/mpv_whitelist_test.dart -d macos` → PASS.
  Puis, en debug avec le feed de dev (`--dart-define=VEHICOULE_DEV_FEED=…`,
  `VEHICOULE_DEV_PLAY=…`) sur macOS et l'émulateur : le titre joue, et le journal de mpv
  ne montre que des URL `http://127.0.0.1:`. Enfin `flutter build macos --release` et un
  titre joué dans ce build.
- [ ] **Step 5 : commit** : `feat(stream): proxy média local (règles du plugin à chaque requête, HLS réécrit), mpv limité à 127.0.0.1`.

### Task 6 : écrans d'écoute (accueil, Explorer, pages, lecteur, file, paroles)

**Files :**
- Create :
  - `app/lib/features/music/home/{home_page,discovery_hero,feed_shelf}.dart` ;
  - `features/music/explore/{explore_page,suggestions_view,results_view,category_page}.dart` ;
  - `features/music/entity/{album_page,artist_page,playlist_page}.dart` ;
  - `features/music/now_playing/{now_playing_controller,lyrics_view,queue_view}.dart`
    (les données de `VNowPlaying` et les contenus des vues Paroles et File) ;
  - `features/music/actions/track_actions.dart` : les seuls chemins vers la lecture, le
    téléchargement et le menu d'un titre.
- Modify :
  - `features/music/now_playing/now_playing_sheet.dart` (Task 5 : contenus réels) ;
  - `shell_desktop/title_bar.dart` (suggestions de `suggestions_view.dart`),
    `shell_mobile/mini_player.dart` (astuce de geste), `shell_desktop/pinned.dart` (dépôt sur
    Téléchargés → `startDownload`), `router.dart` (texte de `Notice.skipped`) ;
  - `app/android/app/src/main/kotlin/app/vehicoule/MainActivity.kt` (sélecteur de sortie
    audio) ;
  - `app/lib/l10n/errors.dart` (la source bloquante, Task 5b item 11),
    `app/lib/debug/fake_api.dart` (fil de 12 étagères, 2 catégories vedettes et 6 catégories,
    recherche, entités), ARB FR/EN.
- Test : `app/test/features/{home,explore,entity,now_playing,actions}_test.dart`.

**Interfaces :**
- Consumes :
  - API du plan 4 : `search`, `searchLibrary`, `entity`, `play`, `queueOp`, `queueStates`,
    `skipNext`, `previous(positionMs:)`, `nowPlaying`, `lyrics`, `fixMatch`, `chooseMatch`,
    `setLiked`, `download`, `addToPlaylist`, `playlistEntries`, `removeFromPlaylist`,
    `moveInPlaylist`, `setSleepTimer`, `notices`, `hasResolver`, `artistLatestRelease`,
    `uiPref`/`setUiPref` ;
  - API du plan 7 : `homeFeed`, `refreshHome`, `playMix`, `browseCategories`,
    `browseCategory`, `suggest` (rend `SuggestionView`), `likedTracks`, `libraryChanges`
    (`Home`) ;
  - Task 5b : `playlistsContaining`, candidats écoutables, année et durée, `playRadio` ;
  - `AppScope` (`player`, `theme`, `online`), `ScreenFab`, `NowPlayingScope` et `design/`.
- Produces (`track_actions.dart`) :
  ```dart
  Future<void> playTracks(BuildContext c, List<String> ids, int start, PlayContext context);   // player.markTap() puis play(...) ; tout toucher qui lit passe ici
  Future<void> shuffleTracks(BuildContext c, List<String> ids, PlayContext context);           // playTracks(ids, index au hasard, context) puis queueOp(QueueOp.shuffle(true))
  Future<void> startDownload(BuildContext c, List<String> ids);                                // au premier téléchargement, requestNotificationPermission() si ui.notif_asked == "later", puis download(ids)
  Future<void> showTrackMenu(BuildContext c, TrackView t, {required Rect anchor, Rect? originRect, Widget? origin});
      // showVMenu : quick = like, lire ensuite, ajouter à la file ; groupes = ajouter à une playlist, télécharger,
      // aller à l'album, aller à l'artiste, « Ce n'est pas le bon morceau »
  List<VAction> playVariants(BuildContext c, {required List<String> Function() ids, required PlayContext context, bool shuffleFirst = false});
      // le ▾ d'un split : « Lire » → Aléatoire, Lire ensuite, Ajouter à la file ;
      // « Aléatoire » (shuffleFirst) → Lire dans l'ordre, Radio, Lire ensuite, Ajouter à la file
  ```
- Règles :
  - **Accueil** (spec UI §6.1) :
    - « Bonsoir / Bonjour / Bonne nuit » selon l'heure locale, dans une `VLargeAppBar` qui
      se replie ;
    - pas de `SliverList` de pages : un `CustomScrollView` d'étagères à hauteur fixe ;
    - `homeFeed(cursor: next)` est appelé tant que `next != null` et qu'il reste moins de 2
      étagères hors écran : une page courte en appelle une autre tout de suite ;
    - à chaque `LibraryChanged.home`, le fil repart de la page 1 ;
    - les étagères qui chargent sont des `VSkeleton` de la même hauteur ;
    - tirer pour rafraîchir (`VRefresh`) appelle `refreshHome()` ; sur `Offline`, le geste
      se termine et `showVSnack` dit qu'on est hors ligne, sans réessai ;
    - le titre d'une étagère se traduit depuis son `ShelfKindView` et sa `seed` ;
    - `shortcuts` : une rangée de `VChip` avec leur `VArtwork`, les 6 collections les plus
      jouées ;
    - `Discovery` : `discovery_hero` (un toucher sur ▶ appelle
      `playTracks(tous les titres, 0, PlayContext(kind: 'discovery', title: <titre traduit de l'étagère>))`),
      puis des pages de 4 `VTrackRow` qui s'aimantent, avec leur `reason` (« comme … ») ;
      sur une page sans étagère `shortcuts` ni `recent` (historique vide), la carte devient
      « Pour commencer » ;
    - sans `browse` (`browseCategories` lève `NoPlugin(browse)`) et sans étagère
      `Discovery`, une carte envoie vers Explorer ;
    - `Mixes` : `VCarousel(kind: VCarouselKind.hero)`, un toucher appelle `playMix(artistId:)` ;
    - `End` : la carte « Tu as fait le tour » vers `/music/explore` ;
    - une étagère entre par `vEntrance(index, …)` la première fois qu'elle est construite, et
      plus jamais ;
    - la carte héros se rétracte en sortant de l'écran (échelle 1 → 0,92 et parallaxe) ;
    - pas d'aimantation verticale ;
    - **FAB menu « Lancer »** (`ScreenFab(action: VAction(l.fabLaunch, VIcons.play, …), items: …)`) :
      - « Mélanger mes likés » → `shuffleTracks(likedTracks par pages de 500, PlayContext(kind: 'liked', title:))` ;
      - « Radio de ce que j'écoute » → `playRadio(id du titre en cours)`, sinon du dernier
        titre de `history` ; absente sans l'un ni l'autre ;
      - « Reprendre la dernière écoute » → `queueOp(QueueOp.jumpTo(currentEntry))` sur la file
        restaurée ; absente si `queueStates` n'a pas d'entrée courante ou si elle joue.
  - **Explorer** (spec UI §6.2) :
    - au repos : `VSearchBar`, les catégories `featured` en deux grandes cartes, puis la
      grille « Parcourir » (2 colonnes en compact, de 3 à 5 en expanded). La teinte d'une
      tuile est `pastelSeed` d'une teinte tirée du hash de `CategoryView.id`. Son image est un
      `VDecor(shape: decorFor(id), imageItemId: artwork)` incliné qui dépasse du coin. Au
      toucher, la forme grossit et morphe en carré pendant le container transform. Les cartes
      vedettes font de même, en plus grand ;
    - pendant la frappe, la search view plein écran ne contient **que** :
      - « Dans ta bibliothèque » : `searchLibrary` (des titres), au plus 3 lignes ; un toucher
        lit le titre (`playTracks`) ;
      - puis « Suggestions » : `suggest`, après `VDurations.debounce` sans frappe ; une réponse
        plus ancienne que la dernière demande (numéro de séquence) est ignorée. L'icône est
        l'horloge si `fromHistory`, la loupe sinon. Le préfixe tapé est en gras, et ↖ recopie
        la suggestion dans le champ ;
    - `suggestions_view.dart` sert aussi au menu déroulant de la barre de titre desktop ;
    - aucune `search()` avant la validation ;
    - à la validation : `search()`, `VLoading` pendant l'appel, les `VChip` Tout / Titres /
      Albums / Artistes / Playlists, le meilleur résultat en carte, puis les sections. Meilleur
      résultat : l'artiste dont le nom normalisé égale la requête, sinon le premier titre ;
    - les catégories s'affichent dès que `browseCategories()` rend `Ok` (même hors ligne,
      depuis le cache) ; sur `Err(Offline)` ou `Err(NoPlugin(browse))`, la recherche locale
      et l'historique restent, les vedettes et la grille sont remplacées par un message ;
    - `/music/explore/category/:id` (et `/home/music/category/:id` depuis l'Accueil) : `browseCategory(id:, cursor:)`, ses étagères paginées, leur titre
      (`tracks`, `albums`, `artists`, `playlists`) traduit ; la copie du cache
      (`fromCache`) est signalée ; split button « Lire | ▾ ».
  - **Pages** (spec UI §6.4, §6.5) :
    - la pochette ou la photo est en grand, fondue dans la surface, sans teinte propre, dans un
      `VFlexibleHeader` (album, playlist, artiste en cercle, catégorie) ; titre, artistes,
      année et durée (Task 5b item 10) ;
    - **split button d'en-tête** (`VSplitButton` dans `actions`), like et télécharger en
      `VIconButton(style: VIconStyle.tonal)` :
      - album, playlist, catégorie : « Lire | ▾ » → `playTracks(ids, 0, context)`, ▾ =
        `playVariants(…)` ;
      - artiste : « Aléatoire | ▾ » → `shuffleTracks(titres populaires, context)`, ▾ =
        `playVariants(…, shuffleFirst: true)`, dont « Radio » → `playMix(artistId:)`. C'est
        la radio de l'artiste (spec UI §6.5) ; pas de second bouton Radio ;
    - en-tête replié : dans la coque mobile, le split devient le FAB d'écran
      (`ScreenFab(action: VAction(<même libellé>, <même icône>, <même action>))`, placé par
      `VFabDock` au-dessus du ⏯) et l'en-tête reçoit `fab: const SizedBox.shrink()` ; sur
      desktop, l'en-tête replié montre `VFab` dans son app bar, et la page ne publie pas de
      `ScreenFab` ;
    - album : lignes numérotées ;
    - artiste : la carte « Dernière sortie » si `artistLatestRelease(artistId:)` rend une
      valeur (appel séparé, la page ne l'attend pas), puis les titres populaires et les albums
      en `VCarousel(kind: VCarouselKind.multiBrowse)` ;
    - une playlist perso sans image a `VArtwork(mosaic: <ids des 4 premiers titres distincts de playlistEntries(id, 0, 4)>)`,
      partout où elle apparaît ;
    - une playlist perso est paginée par `playlistEntries(id:, offset:, limit: 100)` (les
      `entry` servent à réordonner) ; les entités du fournisseur par `entity(id:, cursor:)` ;
    - **playlist perso, sélection multiple** (mobile) : appui long → mode sélection ; l'app
      bar montre le nombre et « Annuler » ; `ScreenFab(bar: VToolbar(actions: [ajouter à une
      playlist, télécharger, like, retirer], fab: VFab(« Lire »)))` prend la place du
      mini-lecteur ; « Lire » → `playTracks(ids sélectionnés, 0, context)` ;
    - retirer d'une playlist ou supprimer une playlist : la ligne disparaît tout de suite,
      `showVSnack` avec « Annuler » ; `removeFromPlaylist`/`deletePlaylist` part quand le
      snack se ferme sans « Annuler ».
  - **Lecteur** (spec UI §5.5, §6.6) :
    - `now_playing_controller` construit `NowPlayingData` depuis `nowPlaying`, `queueStates`,
      `player.playing`, `player.loading`, `downloadProgress` et `theme.coverTop`, et fournit
      `NowPlayingActions`. La position est `player.position`, passée telle quelle à
      `VNowPlaying.position`. Le style vient de `ThemeController.playerStyle` (Disque par
      défaut) ;
    - vue Paroles : `lyrics_view` (ligne active = la dernière dont `startMs ≤ position` ; un
      toucher y amène la lecture). Vue File : `queue_view`, avec « À suivre » puis « Radio ·
      titres proches », en `VTrackRow(handleIndex:)`. Glisser pour réordonner
      (`QueueOp.move(entry:, after: voisin du dessus)`) ; glisser à gauche pour retirer
      (`onRemove` → `QueueOp.remove(entry)`) ;
    - les mêmes contenus servent au plein écran mobile, au panneau desktop et à l'immersif ;
    - en paysage (téléphone) et en largeur moyenne : `VNowPlaying(wide: true)` ;
    - la sortie audio : sur Android 11+, l'intent `android.settings.panel.action.MEDIA_OUTPUT`
      par le canal de `MainActivity`, bouton masqué avant 11 ; sur desktop, un `showVMenu` des
      sorties media_kit (`audioDevices`, `setAudioDevice`), près du volume ;
    - `NowPlaying.source` et `mime` alimentent « Détails du flux » (menu ⋮, dans
      `showVSheet`) ;
    - le menu ⋮ porte aussi la **Minuterie** : 15, 30, 45 ou 60 min, fin du titre, annuler
      (`setSleepTimer`). `NowPlaying.sleep` donne `sleepLeft` ou `sleepEndOfTrack` à
      `NowPlayingData` ;
    - « Ce n'est pas le bon morceau » (`showVSheet`) : les candidats avec leur source et leur
      durée, « Lire » pour écouter avant de choisir (Task 5b item 8), « Choisir » →
      `chooseMatch`.
  - **Ajouter à une playlist** (`showVSheet`) : « Nouvelle playlist » en tête, puis une
    recherche ; les playlists de `playlistsContaining(trackId)` portent le cookie + coche.
  - **Desktop, listes** (spec UI §4.2) :
    - les listes de titres sont en tableau (#, titre + artistes, album, durée, ⋮), avec
      `VTrackRow(wide: true)` ;
    - au survol, le numéro devient ▶ et ⋮ apparaît ;
    - **double-clic = lire** (`onDoubleTap` → `playTracks`), clic = sélectionner
      (`selected`), ⇧/⌘ clic = sélection multiple, Entrée lit la sélection, Suppr retire
      (vue File, playlist perso) ;
    - glisser la sélection vers un épinglé, une playlist ou la file ;
    - au survol d'une carte, un bouton ▶ apparaît ;
    - « Épingler / Désépingler » figure dans le menu des collections.
  - **Règles reprises du plan 4** :
    - sans résolveur (`hasResolver()` faux), le bouton lecture dit « Il te faut une source
      pour lire. » avec l'action « Ajouter une source » (ouvre `AddSourceSheet`, Task 7) ;
    - `Notice.skipped` → snackbar discrète, avec le nom de la source s'il est connu ;
    - bouton lecture sans piste chargée → `queueOp(QueueOp.jumpTo(currentEntry))`.
  - Like, ⏯ et le sélecteur appellent leurs `VHaptics` dans `design/` ; aucun écran ne les
    appelle pour eux.

**Ajouts — 8 sujets (spec UI §5.7, §4.3) :**
- Astuces de gestes, une seule fois chacune (`ui.hint.mini_player`, `ui.hint.row_swipe`) :
  la `VRichTooltip` du premier mini-lecteur avec l'esquisse du geste, puis la première ligne
  qui s'entrouvre. Avec « réduire les animations » : la tooltip seule. Rien sur desktop.
- Lecteur en deux colonnes en paysage (téléphone) et en largeur moyenne.

```dart
testWidgets('gesture hints show once and never again', ...);
testWidgets('landscape player uses two columns', ...);
```

- [ ] **Step 1 : tests qui échouent**

```dart
testWidgets('home pages the feed two shelves before the end', ...);   // FakeApi : 12 étagères → homeFeed("4") demandé, pas homeFeed("8") avant défilement
testWidgets('a short page fetches the next one at once', ...);
testWidgets('home reloads from page 1 on LibraryChanged.home', ...);
testWidgets('home pull to refresh calls refreshHome through VRefresh', ...);
testWidgets('home refresh offline ends and says so', ...);
testWidgets('discovery hero plays the whole shelf', ...);              // playTracks(…, PlayContext(kind: 'discovery', title: …))
testWidgets('discovery rows show their reason', ...);
testWidgets('empty history turns discovery into Pour commencer', ...);
testWidgets('shortcuts row shows six chips', ...);
testWidgets('mix tap calls playMix', ...);
testWidgets('shelf titles come from kind and seed', ...);             // BecauseYouListened + seed "Kaytranada" → « Parce que tu as écouté Kaytranada »
testWidgets('end card leads to explore', ...);
testWidgets('home FAB menu Lancer runs its launches', ...);           // likés mélangés ; playRadio ; jumpTo(currentEntry)
testWidgets('explore idle shows featured cards then the grid', ...);
testWidgets('typing shows only suggestions, no search', ...);          // "y","yo","yoa" à 100 ms → 1 suggest("yoa"), 0 search
testWidgets('a stale suggestion answer is dropped', ...);
testWidgets('history suggestions use the clock icon', ...);
testWidgets('north west arrow fills the field without searching', ...);
testWidgets('library hit plays the track', ...);
testWidgets('submit shows chips and sectioned results', ...);
testWidgets('best result is the exact artist, else the first track', ...);
testWidgets('explore offline keeps local search and explains', ...);
testWidgets('category page shows its shelves', ...);
testWidgets('album rows are numbered', ...);
testWidgets('album header shows year and duration', ...);
testWidgets('playlist page builds lazily', ...);                       // 10 000 titres simulés : moins de 50 VTrackRow construits
testWidgets('tapping a track plays it with its context', ...);         // markTap() puis play(items, start, PlayContext(kind: 'album', title: …))
testWidgets('play without resolver explains why', ...);                // « Il te faut une source pour lire. » + « Ajouter une source »
testWidgets('collection split plays and its menu shuffles', ...);
testWidgets('artist split shuffles and its menu starts the radio', ...);
testWidgets('collapsed header split becomes the screen FAB above the mini player', ...);
testWidgets('user playlist selection shows the toolbar and its Lire FAB', ...);
testWidgets('removing from a playlist hides at once and calls the API when the snackbar closes', ...);
testWidgets('synced lyrics highlight the current line', ...);
testWidgets('not the right track lists candidates, plays one, pins the choice', ...);
testWidgets('add to playlist marks playlists that hold the track', ...);
testWidgets('track actions use the expressive menu on both shells', ...);
testWidgets('first download asks for notifications once', ...);        // startDownload
testWidgets('player style setting switches Disque and Vague live', ...);
testWidgets('sleep timer menu sets the timer and the header shows the moon', ...);
testWidgets('artist page shows the latest release card only when present', ...);
testWidgets('user playlist without image shows a mosaic', ...);
testWidgets('genre tile uses the same decor shape for the same id', ...);
testWidgets('album header collapses into the app bar', ...);
testWidgets('queue view reorders with move(entry, after) and removes on swipe left', ...);
testWidgets('desktop: double click plays, single click selects, shift selects a range', ...);
testWidgets('desktop: hover shows play on the row number', ...);
```
- [ ] **Step 2 : vérifier l'échec** → FAIL.
- [ ] **Step 3 : implémenter.**
- [ ] **Step 4 : vérifier** : `flutter test` puis `flutter analyze` → PASS.
- [ ] **Step 5 : commit** : `feat(app): accueil, Explorer, pages, lecteur, file, paroles`.
- [ ] **Step 6 : point de contrôle utilisateur (bloquant).** Lancer l'app en debug avec
  `FakeApi` sur le téléphone Android de référence et sur macOS, et avec les vraies sources
  (feed de dev local du ledger) quand elles répondent. Captures à taille réelle dans
  `task-6-screenshots/`, chacune à côté de sa maquette :
  - l'accueil (téléphone : « Bonsoir », raccourcis, découverte, mixes, étagères, FAB menu
    « Lancer ») ↔ `14247-1792758406/content/accueil.html` ;
  - Explorer au repos (vedettes, grille « Parcourir ») et une catégorie ↔
    `59588-1792794291/content/app-formes.html` ;
  - le lecteur (Disque, Vague, Paroles, File) ↔ `lecteur-v3.html` ;
  - l'accueil, un album en tableau et Explorer à 1280 dp ↔ `desktop-2.html`.

  Le rapport liste les écarts ; le relecteur compte tout écart visuel comme Important. Les
  retours sont corrigés, tests verts, puis commités. La tâche 7 ne commence qu'après
  l'accord, consigné dans le ledger (`Ruling (user): listening screens approved`).

### Task 7 : bibliothèque, réglages, sources, premier lancement

**Files :**
- Create :
  - `app/lib/features/music/library/{library_page,collection_list,track_list_page,top_page,history_page,sort_sheet}.dart` ;
  - `features/music/library/{new_playlist_sheet,import_dialog}.dart` ;
  - écrans globaux (addendum §2.3, §12 : ils ne sont plus propres à la musique) :
    `features/app/settings/{settings_page,appearance_page,diagnostics_page}.dart` (routes
    `/settings`, `/settings/appearance`, `/settings/diagnostics`),
    `features/app/sources/{sources_page,add_source_sheet}.dart` (route `/sources` ;
    `parseSourceLink` dans `add_source_sheet.dart`),
    `features/app/downloads/downloads_page.dart` (route `/downloads`) ;
  - `features/music/onboarding/onboarding_page.dart`, `features/music/updates/update_sheet.dart`.
- Modify : `app/lib/router.dart` (`links()` → `AddSourceSheet` ; `Notice.updateAvailable` →
  `update_sheet`), `app/pubspec.yaml` (`share_plus: 13.3.1`), `app/lib/debug/fake_api.dart`,
  ARB FR/EN.
- Test : `app/test/features/{library,settings,sources,onboarding,downloads}_test.dart`.
- Autre dépôt : `/Users/btw/Documents/repo/vehicoule-ytmusic-socle`, branche `socle-plugin`
  (README, voir les Ajouts).

**Interfaces :**
- Consumes :
  - API du plan 4 : `playlists`, `playlistEntries`, `createPlaylist`, `renamePlaylist`,
    `deletePlaylist`, `moveInPlaylist`, `removeFromPlaylist`, `importPlaylist`,
    `downloads`, `downloadProgress`, `cancelDownload`, `searchLibrary`, `libraryChanges`,
    `settings`, `setSettings`, `installedPlugins`, `capabilityOrder`, `setCapabilityOrder`,
    `previewFeed(url:, publicKey:)`, `addFeed`, `removeFeed`, `refreshFeeds`, `onboarding`,
    `finishOnboarding`, `diagnostics`, `exportLogs`, `checkUpdates`, `feeds`, `tracks`,
    `hasResolver`, `browseCategories`, `browseCategory`, `search`, `setLiked`, et
    `installUpdate`, `links`, `requestNotificationPermission` (Task 4) ;
  - API du plan 7 : `liked(kind:, sort:, offset:, limit:)`, `likedTracks(sort:, …)`,
    `playlists(sort:)`, `downloaded(sort:, …)`, `downloadStorage`, `topTracks`, `history`
    (`HistoryEntryView`), `uiPref`, `setUiPref`, `Settings.discover` ;
  - Task 5b : `setPluginEnabled`, `FeedView.error`, `UpdateInfo` avec sa taille, la
    progression d'import, `playRadio` ;
  - Task 6 : `playTracks`, `shuffleTracks`, `startDownload`, `playVariants` ; Task 5 :
    `ThemeController` (ses setters), `ScreenFab`.
- Produces :
  ```dart
  ({String url, String publicKey})? parseSourceLink(String text); // vehicoule://add-source?feed=<url>&key=<clé>, sinon null
  Future<void> showAddSourceSheet(BuildContext c, {required String url, required String publicKey});
  ```
- Règles :
  - **Bibliothèque** (spec UI §6.3) :
    - `VLargeAppBar` avec ☰, recherche (`searchLibrary`) et tri ;
    - tuiles Likés / Téléchargés / Top 50 / Historique ; Likés montre un collage des 3
      dernières pochettes likées ; chaque tuile a son icône dans une `VDecor` de forme
      différente ;
    - `VChip` Playlists / Albums / Artistes, puis la liste (`VAsyncList`, `reloadKey` = tri) ;
    - **FAB menu « Nouvelle »** : `ScreenFab(action: VAction(l.fabNew, VIcons.add, …), items:
      [VAction(l.actionNewPlaylist, VIcons.playlistAdd, …), VAction(l.actionImportLink,
      VIcons.addLink, …)])`. « Nouvelle playlist » → `new_playlist_sheet` (`showVSheet` : un
      nom et l'aperçu de la mosaïque) → `createPlaylist` ; « Importer un lien » →
      `import_dialog` ;
    - **Likés, Téléchargés** (`track_list_page`) : split button « Aléatoire | ▾ » →
      `shuffleTracks(toutes les pages, par 500)`, ▾ = `playVariants(…, shuffleFirst: true)`
      (« Radio » → `playRadio` du premier titre dans le tri courant) ; replié, il devient le
      FAB d'écran (règle de la Task 6) ;
    - **Top 50 en podium** (`top_page`) :
      - les 3 premiers en tête, le n°1 au centre et plus grand, en `VArtwork` (cookie + anneau
        s'il joue) ;
      - puis les rangs en grands chiffres arrondis en contour (style `displaySmall` ROND 100,
        trait `primary`), passés à `VTrackRow(leading:)` ;
      - le sous-titre donne le nombre d'écoutes ;
      - split button « Lire | ▾ » (ordre des rangs ; ▾ = `playVariants(…)`), replié en FAB
        d'écran ; ordre fixe, pas de tri ;
    - Historique : groupé par jour local (« Aujourd'hui », « Hier », puis la date longue), avec
      des en-têtes de jour qui restent visibles au défilement ;
    - **états vides** : `VEmptyState` ; les likés vides montrent `VIcons.favorite` avec son
      libellé parlé, jamais le caractère ♡.
  - **Tri** (`sort_sheet`, `showVSheet` : feuille sur mobile, dialogue au-delà de 840) :
    - collections : Récents (`CollectionSort.recent`, défaut), Dernière écoute
      (`CollectionSort.played`), Nom A→Z (`CollectionSort.title`) ;
    - titres : Date d'ajout (`TrackSort.added`, défaut), Titre, Artiste ;
    - le choix est passé à l'API et retenu par liste (`setUiPref("ui.sort.<liste>")`).
  - **Import** (`import_dialog`, `showVSheet`) : l'avertissement de coupe à 50 pages (5 000
    titres) avant de commencer, la progression ondulée page par page (Task 5b item 9), puis
    « Ouvrir » ; `ImportResult.truncated` → mention « playlist tronquée à 50 pages ».
  - **Réglages** : `VListGroup` et `VListRow` (listes M3E en groupes arrondis). Les choix sont
    des `VChoiceGroup` (groupes de boutons connectés), jamais des listes radio ni des segmented
    buttons. Ordre (addendum §2.3) : les sections générales, puis une section par domaine ;
    en v1 « Lecture » est la section **Musique**, les autres sont générales.
    - Apparence (`appearance_page`, `/settings/appearance`) :
      - en haut, un **aperçu en direct** : un `VNowPlaying(size: PlayerSize.compact)` sur ce
        qui joue, ou sur un titre de `sampleTracks` en pochette absente, qui se met à jour à
        chaque toucher ;
      - source de couleur (Ce qui joue, par défaut / Système / Préréglage + choix), noir pur,
        thème clair/sombre/système, style du lecteur (Disque, par défaut / Vague) ; chaque choix
        appelle le setter de `ThemeController`, jamais `setUiPref` directement.
    - Lecture : radio de fin de file, normalisation.
    - Téléchargements.
    - Sources : lien vers l'écran Sources, l'ordre des capacités.
    - Confidentialité : télémétrie, « Découvertes à partir de mon écoute »
      (`Settings.discover`).
    - À propos : mises à jour, diagnostics, rapport de bug.
    - Desktop : « Afficher dans la barre des menus » (macOS, `ui.menu_bar`, activé par
      défaut ; la Task 10 branche `MenuBar.setVisible`).
  - **Premier lancement** (spec 4.6, spec UI §6.7) : `VLoading`, puis 6 étapes (3 et 4
    sautables, 5 seulement sur Android 13 et plus) :
    1. ce qu'est l'app, livrée sans source de streaming ;
    2. installation du feed officiel (`refreshFeeds`, `VLoading`) : l'étape réussit quand
       `installedPlugins()` n'est pas vide ; sinon « Réessayer », avec le message hors ligne si
       `online` est faux. `refreshFeeds` ne lève pas par feed : seul `installedPlugins` décide ;
    3. **« Ajoute une source pour lire »**, poussée seulement si `hasResolver()` est faux : une
       phrase, un champ « Colle un lien de source » qui ouvre `AddSourceSheet`, puis
       « Passer » ;
    4. **« Choisis au moins 3 artistes »** (spec UI §6.7) :
       - des **bulles** de tailles variées (3 tailles, réparties sans chevauchement, qui
         flottent doucement ; immobiles avec « réduire les animations »), tirées de l'étagère
         « artists » de `browseCategory(id: <première catégorie featured de browseCategories()>)`,
         avec une recherche au-dessus (`search`, artistes) ;
       - un toucher appelle `setLiked(id:, liked: true)` : la bulle grossit et devient
         `VArtwork(kind: ArtKind.artist, selected: true)` (cookie avec coche), puis
         `VHaptics.light()` ;
       - « Continuer · N » s'active à partir de 3 artistes, « Passer » est toujours là ;
       - l'étape est sautée sans `browse`, sans catégorie vedette, ou hors ligne ;
    5. **« Les notifications »** (Android 13 et plus seulement), spec UI §6.7 : « Plus tard » /
       « Autoriser » (`requestNotificationPermission`) ; après « Plus tard »,
       `ui.notif_asked` = `"later"` et la demande revient seulement au premier téléchargement
       (`startDownload`) ;
    6. télémétrie : deux boutons, **aucun présélectionné**, et on ne peut pas continuer sans
       choisir → `finishOnboarding(telemetry:)`.

    Les étapes s'enchaînent en `vSharedAxis`. Chacune a sa grande `VDecor`, qui morphe vers
    celle de l'étape suivante.
  - **Ajout d'une source** (spec UI §6.7), une seule feuille `AddSourceSheet` (`showVSheet`) :
    - entrée : un **lien de source** `vehicoule://add-source?feed=<url>&key=<clé>`, venu de
      `links()` (branché dans `router.dart`) ou collé ; `parseSourceLink` rejette tout autre
      texte avec la phrase de `voice.md` (`invalidFeed`) ;
    - `previewFeed(url:, publicKey:)` → nom, capacités en mots (« Lecture des titres ·
      Paroles »), la phrase de confiance ; empreinte, domaines et version repliés sous
      « Détails » ;
    - « Ajouter » → `addFeed` (toucher « Ajouter » vaut accord explicite), puis snackbar
      « <nom> ajoutée » ;
    - jamais d'ajout sans la feuille, ni case à cocher ni champ de clé.
  - **Écran Sources** (`sources_page`, `/sources`) :
    - `feeds()` groupés par origine (Officiel, puis chaque lien) ; une ligne par source
      (`installedPlugins`) avec ce qu'elle fait en mots et un `VSwitch` →
      `setPluginEnabled(id, enabled)` ;
    - le menu d'un lien propose « Retirer » : la ligne disparaît tout de suite, `showVSnack`
      avec « Annuler », `removeFeed(url:)` part quand le snack se ferme sans « Annuler » ;
    - l'ordre par capacité (`capabilityOrder`/`setCapabilityOrder`) dans « Avancé », replié ;
    - un feed dont `error` vaut « clé changée » montre : « Cette source a changé de
      signature. Retire-la, puis ajoute-la de nouveau depuis son lien. » ;
    - **FAB étendu « Ajouter une source »** : `ScreenFab(action: VAction(l.actionAddSource,
      VIcons.add, …))`, qui ouvre un champ « Colle un lien de source » puis `AddSourceSheet` ;
      sur desktop il est en haut du rail.
  - **Mise à jour** (`update_sheet`, `showVSheet`, ouverte par `Notice.updateAvailable`) :
    version, taille (Task 5b item 6), notes en trois lignes au plus, « Plus tard » /
    « Installer » (`installUpdate`).
  - **« Rechercher une mise à jour »** = `checkUpdates(force: true)` :
    - `Ok(None)` → « à jour » ;
    - `Some` n'est pas affiché depuis la valeur de retour, seulement par
      `Notice.updateAvailable` ;
    - `Err` → `errorMessage`.
  - **« Envoyer un rapport »** : `exportLogs(dest:)` vers un fichier du dossier cache ; sur
    Android, `share_plus` le partage ; sur macOS, il est copié dans `~/Downloads` et montré
    dans le Finder. Puis ouverture de `https://github.com/Vehicoule/vehicoule/issues/new`
    sans aucune donnée dans l'URL.
  - **Téléchargements** (`/downloads`, section globale ouverte depuis le ☰ et le bas du rail) :
    - `downloads()`, avec les titres via `tracks(ids)`, et l'annulation ;
    - en tête, la barre de stockage (`downloadStorage()` : musique téléchargée / espace
      libre) ;
    - un titre en cours affiche `VArtwork(progress: pourcentage)`, l'anneau du mini-lecteur.

**Ajouts — 8 sujets (spec UI §6.7, §5.8) :** l'écran Sources, `AddSourceSheet` et les étapes
« Ajoute une source pour lire » et « Les notifications » (détails ci-dessus). Les feuilles
et dialogues suivent spec UI §5.8 par `showVSheet`. Le lien de source de ytmusic est publié
dans le README de `vehicoule-ytmusic-socle` (branche `socle-plugin`, un commit dans ce dépôt) ;
sa clé publique vient de ce dépôt ou de son `feed.json` publié, jamais de
`~/.config/vehicoule/feed-keys/`. Si aucun des deux ne l'a, la demande va dans « Pending user
confirmation ».

```dart
test('parseSourceLink accepts only vehicoule://add-source with feed and key', ...);
testWidgets('add source sheet shows name, capabilities and trust line, details folded', ...);
testWidgets('add source needs the Ajouter tap', ...);
testWidgets('add-source deep link opens the sheet and never adds by itself', ...);
testWidgets('a changed signing key shows the re-add message', ...);
```

- [ ] **Step 1 : tests qui échouent**

```dart
testWidgets('library tiles open liked, downloaded, top 50 and history', ...);
testWidgets('library FAB menu Nouvelle creates a playlist or imports a link', ...);
testWidgets('sort choice reaches the API and is remembered per list', ...); // Nom A→Z → liked(kind, CollectionSort.title, …) puis setUiPref("ui.sort.albums", "title")
testWidgets('liked split shuffles and its menu plays in order', ...);
testWidgets('empty likes show the heart icon with its spoken label', ...);
testWidgets('top 50 has a split button and no sort menu', ...);
testWidgets('top 50 shows a podium then outlined ranks', ...);
testWidgets('history is grouped by local day', ...);
testWidgets('history keeps the day header pinned while scrolling', ...);
testWidgets('settings choices are connected button groups', ...);
testWidgets('appearance changes apply live', ...);                        // noir pur → surface noire, par ThemeController.setPureBlack
testWidgets('appearance preview updates on every choice', ...);
testWidgets('discoveries toggle saves Settings.discover', ...);
testWidgets('playlist reorder calls moveInPlaylist with the new neighbour', ...);
testWidgets('import warns, shows page progress, then opens the new playlist', ...);
testWidgets('local library search shows fuzzy hits', ...);
testWidgets('sources FAB opens the add source sheet', ...);
testWidgets('source switch calls setPluginEnabled', ...);
testWidgets('removing a source hides it and calls removeFeed when the snackbar closes', ...);
testWidgets('update sheet shows version, size and notes', ...);
testWidgets('onboarding has six steps, 3 and 4 skippable, 5 on Android 13 and later only', ...);
testWidgets('onboarding step 2 succeeds once installedPlugins is not empty', ...);
testWidgets('telemetry choice has no default and blocks continue', ...);
testWidgets('artist step likes picks and enables continue at 3', ...);
testWidgets('artist step is skipped without browse or offline', ...);
testWidgets('onboarding_offline_explains_and_continues', ...);
testWidgets('downloads show the storage bar and a ring per running item', ...);
testWidgets('report never puts data in the issue URL', ...);  // URL ouverte == URL fixe
```
- [ ] **Step 2 : vérifier l'échec** → FAIL.
- [ ] **Step 3 : implémenter.**
- [ ] **Step 4 : vérifier** : `flutter test` puis `flutter analyze` → PASS.
- [ ] **Step 5 : commit** : `feat(app): bibliothèque, réglages, sources, premier lancement`.
- [ ] **Step 6 : point de contrôle utilisateur (bloquant).** Lancer l'app en debug sur le
  téléphone Android de référence et sur macOS (le premier lancement depuis une base vide).
  Captures à taille réelle dans `task-7-screenshots/`, chacune à côté de sa maquette :
  - le Top 50 (podium, rangs en contour, split button) ↔
    `59588-1792794291/content/app-formes.html` ;
  - le premier lancement, dont « Choisis au moins 3 artistes » ↔ `app-formes.html` ;
  - le Top 50 et la Bibliothèque à 1280 dp ↔ `desktop-2.html` ;
  - la Bibliothèque (tuiles, FAB menu « Nouvelle »), les Réglages › Apparence et les Sources
    (FAB étendu) en captures seules, jugées sur la spec UI §6.3 et §6.7 (pas de maquette
    dédiée).

  Le rapport liste les écarts ; le relecteur compte tout écart visuel comme Important. Les
  retours sont corrigés, tests verts, puis commités. La tâche 10 ne commence qu'après
  l'accord, consigné dans le ledger (`Ruling (user): library and onboarding approved`).

### Task 8 : tests de démarrage par coque, accessibilité, tests dorés, CI, nettoyage

**Files :**
- Create : `app/integration_test/startup_mobile_test.dart`,
  `app/integration_test/startup_desktop_test.dart`, `app/test/a11y_test.dart`,
  `app/test/goldens/screens_golden_test.dart` (et ses images sous `app/test/goldens/`),
  `.github/workflows/ci.yml`, `core/deny.toml` (surface §7.2)
- Modify : `app/lib/debug/fake_api.dart` (le parcours de démarrage : recherche « halo »,
  lecture)
- Delete : `probes/` (remplacé par le socle, spec de l'étape 1)
- Create : `TRADEMARK.md` (spec 12 : nom et logo réservés, les forks prennent un autre nom)
- Test : les fichiers ci-dessus

**Interfaces :**
- Consumes : `FakeApi` (`lib/debug/fake_api.dart`, Task 3, étendue par chaque tâche),
  branché par `RustLib.initMock(api: FakeApi())` ; `lib/debug/library.dart`.

**Ajouts — tests dorés (spec UI §2.8) :** chaque écran en clair et sombre, en largeurs
compacte, moyenne et étendue, et avec le texte à 200 %, sur `lib/debug/library.dart` (vrais
titres, métadonnées seules ; pochettes à l'aspect « pochette absente », aucune pochette
commitée). Le fichier porte `@Tags(['golden'])` ; il tourne seulement dans le job macOS de la
CI (rendu des polices stable).

- [ ] **Step 1 : tests qui échouent**

```dart
// startup_mobile_test.dart (taille 400×800) et startup_desktop_test.dart (1280×800)
testWidgets('launch, search fake data, play', ...);   // l'accueil s'affiche, Explorer, recherche "halo" validée, tap → FakeApi a reçu play(...) et le mini-lecteur / la bande affiche le titre
// a11y_test.dart, sur accueil, Explorer, mini-lecteur, lecteur plein écran, réglages, dans les deux coques :
testWidgets('meets accessibility guidelines', ...);   // androidTapTargetGuideline, labeledTapTargetGuideline, textContrastGuideline
testWidgets('no_overflow_at_text_scale_2', ...);       // MediaQuery textScaler 2.0 : aucune exception de débordement
// screens_golden_test.dart
testWidgets('screens match their goldens', ...);       // matrice clair/sombre × compact/medium/expanded × texte 1.0/2.0
```
- [ ] **Step 2 : vérifier l'échec** → FAIL.
- [ ] **Step 3 : implémenter les corrections** que ces tests révèlent.
- [ ] **Step 4 : CI** (`ci.yml`) : job Rust (`cargo test` + clippy du workspace `core/`, cible
  `wasm32-wasip2` installée) ; job Android (`flutter test --exclude-tags golden`,
  `flutter build apk --release --target-platform android-arm64`, APK renommé
  `vehicoule-<version>-android-arm64-v8a.apk` + `.sha256` en artefact) ; job macOS
  (`flutter test`, goldens compris, `flutter test integration_test -d macos`,
  `flutter build macos`) ; compilation seule : `flutter build ios --no-codesign`,
  `flutter build windows`, `flutter build linux` (chacun sur son runner).
  Job **dépendances** (surface §7.2, §5), sur chaque push :
  - `cargo deny check` avec `core/deny.toml` : `advisories` (RustSec) ; `licenses` (permises :
    MIT, Apache-2.0, Apache-2.0 WITH LLVM-exception, BSD-2-Clause, BSD-3-Clause, ISC,
    MPL-2.0, Unicode-3.0, Zlib, CC0-1.0, OpenSSL, CDLA-Permissive-2.0 ; toute autre fait
    échouer) ; `bans` (doublons en avertissement) ; `sources` (crates.io et
    `https://github.com/Vehicoule/*` seulement) ;
  - `osv-scanner scan source --lockfile app/pubspec.lock --lockfile core/Cargo.lock` ;
  - `test -z "$(cargo tree -i ring --target all)"` dans `core/` (vide aujourd'hui ; le plan 8
    retire aussi `ring` de `Cargo.lock` et le bannit).

  Une faille connue **bloque la release, pas le développement** : le job a
  `continue-on-error: ${{ !startsWith(github.ref, 'refs/tags/v') }}`, et le job de release
  Android dépend de lui.
- [ ] **Step 5 : vérifier** — `flutter test` → PASS ; `flutter analyze` → PASS ;
  `flutter test integration_test -d macos` → PASS ; `git rm -r probes`.
  Puis, en local : `cargo deny check` (dans `core/`) et `osv-scanner` sur les deux lockfiles
  → sortie consignée au rapport ; une alerte trouvée va au ledger, pas dans cette tâche.
- [ ] **Step 6 : commit** — `test(app): démarrage par coque, accessibilité, tests dorés ; CI (dont cargo deny, osv-scanner, ring) ; retrait des sondes`.

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
- [ ] **Step 5 : fluidité** (spec UI §8) : `flutter run --profile` sur le téléphone de
  référence, défilement de l'accueil et d'Explorer ; noter les temps d'image (60 images/s
  attendues).
- [ ] **Step 6 : macOS** : raccourcis, touches média, barre de titre, une journée d'usage.
- [ ] **Step 7 : rapport** (mesures, constructeur et modèle du téléphone, écarts), puis
  démarrage des deux semaines d'usage quotidien (critère 1). Commit —
  `docs: validation du socle sur appareils`.

### Task 10 : widget Android et barre des menus macOS (exécutée entre les Tasks 7 et 8)

**Files :**
- Create :
  - `app/android/app/src/main/kotlin/app/vehicoule/widget/{NowPlayingWidget,NowPlayingWidgetReceiver}.kt` (Jetpack Glance) ;
  - `app/android/app/src/main/res/xml/now_playing_widget_{small,large}.xml` ;
  - `app/macos/Runner/MenuBar/{MenuBarController,NowPlayingPopover,MenuBarState}.swift` (SwiftUI ;
    `MenuBarState` décode l'état reçu, fonction pure) ;
  - `app/macos/Runner/{en,fr}.lproj/Localizable.strings` (« Ouvrir Vehicoule », …) ;
  - `app/macos/RunnerTests/MenuBarStateTests.swift` (XCTest) ;
  - `app/lib/platform/{home_widget,menu_bar}.dart` ;
  - `app/lib/platform/resume.dart` (la carte Reprendre, partagée par le widget, les
    raccourcis d'icône et le menu du Dock ; addendum §7, §12) ;
  - `app/android/app/src/main/kotlin/app/vehicoule/ResumeShortcuts.kt` (raccourcis dynamiques,
    `ShortcutManagerCompat`).
- Modify : `app/pubspec.yaml` (`home_widget: 0.10.0`), `AndroidManifest.xml` (filtres
  d'intent `vehicoule://now-playing` et `vehicoule://resume`),
  `app/android/app/src/main/res/values{,-fr}/strings.xml`
  (« Reprendre »), `MainActivity.kt` (canal `app.vehicoule/shortcuts`),
  `app/macos/Runner/AppDelegate.swift` (menu du Dock, `applicationDockMenu(_:)`),
  `app/lib/platform/links.dart` (route `resume`),
  `app/macos/Runner.xcodeproj/project.pbxproj` (les fichiers Swift compilés),
  `app/lib/main.dart` (abonnements), `app/lib/router.dart` (`links()` : `now-playing` ouvre
  le lecteur), `features/app/settings/settings_page.dart` (`MenuBar.setVisible` après
  `setUiPref("ui.menu_bar")`).
- Test : `app/test/platform/{home_widget,menu_bar}_test.dart`, `app/android/app/src/androidTest/kotlin/app/vehicoule/widget/NowPlayingWidgetTest.kt`, `MenuBarStateTests.swift`.

**Interfaces :**
- Consumes : `nowPlaying` (avec `sleep`), `queueStates`, `artworkFile`, `uiPref` (`ui.menu_bar`) ;
  la session média d'`audio_service` et son action personnalisée `like` (Task 4) ;
  `PlayerAdapter`, `ThemeController`, `links()`.
- Produces :
  ```dart
  class HomeWidgetPublisher { void start(Stream<NowPlaying> s, PlayerAdapter p, ThemeController t); } // publie title, artist, artworkPath, playing (p.playing), seed ARGB (t), resumable via home_widget, puis demande la mise à jour du widget
  class MenuBar { void start(Stream<NowPlaying> s, PlayerAdapter p); void setVisible(bool visible); } // canal "vehicoule/menu_bar" : Dart → Swift `state` ; Swift → Dart `command` (prev, toggle, next, like, open, resume)
  // platform/resume.dart — v1 : une seule carte, la file musique sauvegardée (le plan 8 la tire de l'étagère Resume)
  class ResumeCard { const ResumeCard({required String domain, required String title, String? subtitle, String? artworkPath, required Uri link}); }
  ResumeCard? resumeCardOf(QueueView q, String? artworkPath); // q.current == null → null ; title = q.context?.title ?? q.current.title ;
                                                              // subtitle = titre courant ; link = vehicoule://resume/music
  class ResumePublisher { void start(Stream<QueueView> s); }  // à chaque QueueView : le widget (via HomeWidgetPublisher), les raccourcis Android (canal shortcuts : set(cards) / clear)
                                                              // et le menu du Dock (champ `resume` de l'état du canal vehicoule/menu_bar)
  Stream<Uri> resumeLinks();                                  // links.dart ; vehicoule://resume/<domaine> → queueOp(QueueOp.jumpTo(currentEntry)) puis lecture
  ```
- Règles (spec UI §6.8) : ce sont deux interfaces natives, sans logique.
  - **Android** : deux tailles.
    - 2×2 : pochette cookie avec l'anneau, et ⏯.
    - 4×2 : pochette, titre, artiste, ⏮ ⏯ ⏭, like.

    Couleurs dynamiques (Android 12+), repli sur la graine publiée. Toucher la pochette ouvre
    le lecteur (deep link `vehicoule://now-playing`, reçu par `links()`). Les boutons envoient
    des intents à la session média d'`audio_service` (`MediaButtonReceiver`, déclaré à la
    Task 4), ce qui fonctionne sans interface Flutter. Like envoie l'action personnalisée
    `like` de la même session, comme la notification : pas d'isolat en arrière-plan ni de
    second cœur. Sans lecture, le 4×2 affiche **la carte Reprendre** (`ResumeCard` : pochette,
    « Reprendre », titre de la file) et son toucher ouvre `vehicoule://resume/music` ; sans
    file sauvegardée, l'icône de l'app et « Ouvrir Vehicoule ».
  - **Raccourcis Reprendre** (addendum §7) : l'appui long sur l'icône Android montre un
    raccourci dynamique par carte Reprendre (« Reprendre · <titre> », icône = la pochette en
    cookie), mis à jour par `ResumePublisher` ; le menu du Dock macOS montre les mêmes cartes,
    au-dessus des entrées du système. Les deux ouvrent le lien de la carte.
  - **macOS** :
    - `NSStatusItem` avec une note, animée pendant la lecture ;
    - popover SwiftUI : pochette cookie avec l'anneau, titre, artiste, ⏮ ⏯ ⏭, like,
      « Ouvrir Vehicoule » ;
    - masqué si `ui.menu_bar == "false"` ; `setVisible` l'applique sans relance ;
    - vit tant que l'app tourne, fenêtre fermée comprise.

- [ ] **Step 1 : tests qui échouent**
  ```dart
  test('home widget publishes state on every NowPlaying', ...);        // playing et la graine compris
  test('menu bar sends state and maps commands to the player', ...);   // command "toggle" → PlayerAdapter.togglePlay
  test('menu bar hides when ui.menu_bar is false and on setVisible(false)', ...);
  test('now-playing link opens the player', ...);
  test('resume card comes from the saved queue', ...);                 // resumeCardOf : titre du contexte, sinon du titre ; null sans titre courant
  test('the widget shows the resume card when nothing plays', ...);    // playing false + file sauvegardée → resume publié
  test('resume cards reach the shortcuts channel and the dock menu', ...); // canal shortcuts set([card]) ; état menu_bar avec resume
  test('resume link jumps to the saved entry', ...);                   // vehicoule://resume/music → queueOp(QueueOp.jumpTo(currentEntry))
  ```
  Côté Android, le test instrumenté `NowPlayingWidgetTest` vérifie que l'état publié est
  rendu, que ⏯ envoie `KEYCODE_MEDIA_PLAY_PAUSE` à la session, et que la carte Reprendre
  s'affiche sans lecture. Côté macOS, `MenuBarStateTests` vérifie le décodage de l'état reçu
  par le canal (cartes Reprendre comprises) ; le menu du Dock est construit depuis cet état.
- [ ] **Step 2 : vérifier l'échec** → FAIL.
- [ ] **Step 3 : implémenter.**
- [ ] **Step 4 : vérifier** : `flutter test test/platform`, `flutter analyze`, puis le test
  instrumenté sur l'émulateur et `xcodebuild test` du schéma Runner. Ensuite, contrôle
  manuel : le widget posé sur l'écran d'accueil de l'émulateur, et le popover sur macOS.
- [ ] **Step 5 : commit** : `feat(app): widget Android et mini-lecteur de la barre des menus macOS`.
