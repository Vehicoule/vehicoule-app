# Vehicoule — Interface de la musique v1 : design

Date : 2026-10-23 · Statut : en relecture (v2 : lecteur, mini-lecteur, desktop, réutilisation,
mouvement, haptique, minuterie, widget Android, barre des menus macOS, langage des formes)

Spec parente : `2026-10-18-socle-musique-design.md` (le « socle »). Celle-ci fixe l'identité
visuelle, les composants, les écrans et les deux nouveautés de cœur qu'ils demandent
(`music.browse`, le fil d'accueil). Maquettes de référence : `.superpowers/brainstorm/…/content/`
(`revision-1.html`, `composants.html`, `desktop.html`, `retours-2.html`, `accueil.html`, puis
`59588-…/content/desktop-2.html`, `lecteur-v3.html` et `app-formes.html`).

## 1. Ce que cette spec change dans le socle

| Socle | Devient |
|---|---|
| §1 Design : « Material 3 officiel + nos tokens ; `material_3_expressive` seulement pour les composants manquants » | `material_ui` (la bibliothèque Material officielle, sortie du SDK) + `material_3_expressive` 1.2.0 pour les composants M3E, les deux derrière `app/lib/design/` (section 3) |
| §1 / §3.2 Accueil « uniquement des données locales, pas de flux éditorial » | Accueil = fil personnel, préparé une fois par jour à partir de tes données et des plugins (section 6.1). Le contenu éditorial reste dans Explorer |
| §11 « Accueil éditorial (classements, nouveautés) : hors v1 » | En v1 : capacité `music.browse`, implémentée par le plugin Deezer (section 7.1) |
| Barre du bas Accueil / Recherche / Bibliothèque | Accueil / Explorer / Bibliothèque (Home / Explore / Library) ; Réglages, Sources et Téléchargements sont des sections globales (addendum navigation entre domaines §2.1) |

Le reste du socle ne bouge pas.

## 2. Identité

### 2.1 Personnalité

Material 3 Expressive, dans l'esprit des apps Android Yokai et Kotatsu : formes généreuses,
couleurs douces, mouvements à ressort. L'expressivité sert les éléments actifs (bouton lecture,
pochette mise en avant, sélection) ; le reste est calme.

### 2.2 Couleur

- **Sources**, au choix dans Réglages › Apparence :
  1. **Ce qui joue** (défaut) : la graine est la pochette du titre en cours.
  2. **Système** : Material You sur Android, couleur d'accent de l'OS sur macOS.
  3. **Préréglages** : une poignée de graines choisies.
- **Toujours pastel** : quelle que soit la source, la chroma est plafonnée et le contraste est
  garanti par les tons du schéma (texte ≥ 4,5:1), jamais par la teinte.
- **Noir pur** en option pour le thème sombre (surfaces à 0).
- **Une seule source de teinte à la fois** : le `ColorScheme` de l'app. Aucune page ne prend la
  couleur de sa propre pochette. Une page album affiche sa pochette en grand, fondue dans la
  surface du thème, sans extraction. Raison : deux palettes qui se battent quand on ouvre un album
  pendant qu'un autre joue, des recolorations au défilement, et un coût par écran.
- **Coût** : l'extraction se fait une fois par titre, hors du thread UI (isolate,
  `QuantizerCelebi` de `material_color_utilities` sur la miniature 112 px), avec un cache par
  pochette. Le thème passe à la nouvelle couleur en fondu (environ 400 ms) au changement de titre
  seulement, et sans animation quand « réduire les animations » est actif. Aucune extraction par
  carte ou par ligne.
- Dégradés : seulement le haut des écrans (`surfaceContainer` → `surface`), qui vient du
  schéma. Le lecteur est sur une surface unie, sans dégradé.
- **Pochette sans couleur** (noir et blanc, ou chroma trop faible pour une graine) : le thème
  prend la graine de repli, celle de la source Système, ou le préréglage choisi. Il ne garde
  jamais la couleur du titre précédent.

- **Thème clair** : mêmes graines, schéma clair. Surfaces aux tons 98 à 92, légèrement
  teintées, jamais `#FFFFFF`. `primary` au ton 40, conteneurs au ton 90. Les tuiles de genre
  gardent leur pastel au ton 90, texte au ton 10. En style Vague, si la pochette est claire, un
  voile de `surface` passe sous le titre pour garder le contraste. Choix : système (défaut),
  clair, sombre ; noir pur seulement en sombre.

### 2.3 Formes

Les formes expressives de M3E, avec retenue : pochette mise en avant, bouton lecture qui morphe,
cartes héros, FAB. Les listes, les champs et les réglages gardent des coins standards.

**Langage des formes.** Chaque forme de pochette a un sens fixe, le même partout. C'est
`VArtwork` qui l'applique ; un écran ne choisit pas la forme d'une pochette.

| Forme | Sens | Où on la voit |
|---|---|---|
| Carré arrondi | au repos | toute pochette de titre, d'album ou de playlist |
| **Cookie** (12 lobes), qui tourne lentement | **ce qui joue** | le titre, l'album ou la playlist en cours, dans les listes, les raccourcis de l'accueil, les cartes, l'en-tête de sa page et les épinglés du rail ; dans le lecteur, en style Disque |
| Cercle | un artiste | lignes, cartes et en-têtes d'artiste. Un artiste qui joue garde son cercle, avec l'égaliseur |
| Cookie + coche | choisi, sélectionné | sélection multiple, artistes du premier lancement |

Les autres formes M3E (trèfle, fleur, soleil, éclat, pilule, arche, gemme…) ne servent qu'au
décor : tuiles de genre, étapes du premier lancement, états vides, tirer-pour-rafraîchir. Elles
ne servent jamais aux pochettes. Avec « réduire les animations », le cookie ne tourne plus.

### 2.4 Typographie

Google Sans Flex, une seule famille :

- axe `ROND` à 100 pour l'affichage, les gros titres et le titre du morceau dans le lecteur ;
- `ROND` à 0 pour le texte courant ;
- Noto Sans JP en repli pour le CJK.

Les polices sont embarquées, sans téléchargement au lancement.

### 2.5 Icônes

Material Symbols Rounded, police variable. Toutes les icônes sont animées :

- transitions des axes `FILL` et `wght` (le cœur qui se remplit, l'onglet actif qui s'épaissit) ;
- `AnimatedIcon` là où il existe ;
- morphs de chemins pour nos cas : téléchargement (flèche → anneau de progression → coche) et
  lecture/pause.

**Icône de l'app** : la mascotte Mochi, dessinée par l'utilisateur. Le maître est
`branding/icon/mochi_master.svg`, avec deux calques séparés : un fond uni et un premier plan.
Les exports vivent dans `branding/icon/` :

- **Android adaptative** : premier plan dans la zone sûre de 66 dp, version **monochrome**
  (silhouette unie, visage en creux) pour les icônes à thème ;
- **iOS / macOS** : macOS sur la grille Big Sur (tuile de 824 px dans 1024, ombre comprise) ;
- **Windows / Linux** : tuile arrondie.

Une **variante petite taille** (≤ 48 px) supprime la note et l'ombre au sol et agrandit le
Mochi. Elle sert aussi de favicon, d'icône de la barre des tâches et de marque du rail.

### 2.6 Mouvement

- Ressorts M3E (spatial et effets) depuis les tokens. Pas de courbes ad hoc.
- Tout passe par `transform` et `opacity`, sans mise en page à chaque image.
- « Réduire les animations » (système ou réglage) remplace tout par des fondus courts.

### 2.7 Espacement

Une seule échelle : 4 · 8 · 12 · 16 · 24 · 32.

- Marges d'écran : 16 sur téléphone, 24 au-delà.
- 24 entre deux sections, 8 entre deux cartes.

Tout vient de `design/tokens.dart`. Aucun nombre magique dans les écrans (vérifié en revue).

### 2.8 Garde-fous contre l'« IA slop »

Une interface générée a des tics reconnaissables. Ils sont interdits ici, et chaque règle a
son contrôle, automatique ou en revue. En revue, une violation compte comme **Important**.

| Règle | Contrôle |
|---|---|
| Couleurs seulement depuis le `ColorScheme` et les tokens ; aucun `Color(0x…)` ni `Colors.*` hors `design/` | test qui parcourt les sources |
| Pas de flou, de verre, de lueur ni d'ombre décorative : seulement les niveaux d'élévation M3. Dégradés : seulement les deux de §2.2 | test : `BackdropFilter`, `ImageFilter.blur`, `BoxShadow`, `*Gradient` interdits hors `design/` |
| Durées et courbes seulement depuis `design/motion.dart` | test : `Duration(` et `Curves.` interdits dans `screens/` et `shell/` |
| Espacements et rayons seulement depuis les tokens (§2.7) | test |
| Tout le texte passe par les ARB et suit `docs/voice.md` (§2.9) | test sur les ARB : aucun `!`, aucun emoji, aucun mot interdit |
| Icônes seulement Material Symbols Rounded ; aucune icône « magie » ou « IA » (✨) | revue |
| Une seule action principale par écran ou feuille ; jamais de carte dans une carte ; pas de pastilles ni de badges décoratifs | revue |
| Texte aligné à gauche, sauf dans le lecteur et les états vides ; pas d'écrans entièrement centrés | revue |
| Majuscule seulement en début de phrase, jamais de Title Case | revue |
| Chaque liste a ses quatre états : chargement (loading indicator M3E, ou squelette aux vraies dimensions, sans scintillement), vide (§6.9), erreur (une phrase et « Réessayer »), hors ligne | test de widget par liste |
| Données réelles partout : la galerie, les tests dorés et les captures utilisent la bibliothèque de test (vrais titres, vraies pochettes), jamais de lorem ipsum ni de « Artist Name » | revue |
| Tests dorés par écran : clair et sombre, largeurs compacte, moyenne et étendue, texte à 200 % | test |

Les points de contrôle utilisateur (galerie, coques) comparent le rendu aux maquettes
validées, pas à une idée générale de « joli ».

### 2.9 Ton des messages

`docs/voice.md` fixe les règles pour les deux langues :

- tutoiement ;
- une phrase, deux au plus : ce qui se passe, puis ce qu'on peut faire ;
- jamais la faute de l'utilisateur ;
- ni code d'erreur ni jargon (pas de « 403 », « plugin », « dépôt », « feed », « résolution ») ;
- le nom du fournisseur seulement s'il aide (« YouTube bloque ce titre pour l'instant ») ;
- aucun point d'exclamation ;
- guillemets français en français, anglais en anglais.

Le vocabulaire visible est fixe : une **source** (ce qui donne la recherche, la lecture ou les
paroles) et un **lien de source** (ce qui en ajoute). Les mots « plugin » et « dépôt »
n'apparaissent jamais à l'écran. Le tableau des messages types (hors ligne, mur du
fournisseur, limite de débit, titre sauté, aucune source, téléchargement raté, arrêt,
listes vides) est dans `docs/voice.md`.

## 3. Bibliothèques Flutter

- `material_ui` 1.8.0 remplace `package:flutter/material.dart` partout. Le lint
  `avoid_material_import` (ou un `grep` en CI) interdit l'ancien import.
- `material_3_expressive` est épinglé à 1.2.0. Il fournit `M3ETheme` (tokens) et les composants
  M3E : barre de navigation, rail, app bar flexible, search bar/view, FAB et FAB menu, split
  button, groupes de boutons connectés, loading indicator, progress ondulés, slider, toolbar
  flottante, menus. Il est importé **seulement** dans `app/lib/design/`. Les écrans importent
  `design/`. Raison : un seul mainteneur non vérifié ; si le paquet meurt, on remplace `design/`
  sans toucher aux écrans.
- `design/tokens.dart` part de `M3ETheme` et pose nos réglages par-dessus : pastel, espacement,
  typographie, ressorts.
- À construire dans `design/`, faute d'équivalent :
  - la side sheet standard (M3 l'indique « indisponible » sur Flutter) ;
  - la pochette à forme M3E (cookie 12 lobes) qui tourne et morphe en carré arrondi, avec
    son anneau ondulé ;
  - la pochette à bord en vague (style « Vague » du lecteur) ;
  - le widget `NowPlaying` (section 5.5) et le sélecteur Paroles · Lecteur · File ;
  - la ligne de titre (section 5.1) ;
  - le menu expressif avec élément soulevé, s'il manque au paquet ;
  - les transitions partagées mini-lecteur → lecteur et carte → page.

## 4. Navigation et coques

### 4.1 Téléphone

- **Barre de navigation M3E** classique, fixe en bas : Accueil, puis les destinations du domaine courant (musique : Explorer, Bibliothèque). Réglages n'est pas une destination (addendum navigation entre domaines §2.1) ; une section globale s'ouvre en page, sans barre, avec ←.
- **Grande app bar qui se replie** en haut de chaque onglet : grand titre, actions de l'onglet,
  ☰ à gauche. Pas de barre de logo.
- **☰ ouvre le rail déplié M3E en modal**. Il remplace le tiroir, qui n'est plus recommandé en
  M3E. Il contient :
  - les domaines : Musique, puis Vidéos (films, séries et anime, code `video`) et Livres quand ils existent ;
  - les sections globales : Téléchargements, Sources, Réglages.

  La barre du bas montre les destinations du domaine courant.
- **Mini-lecteur** flottant au-dessus de la barre (section 5.3).
- **Bottom sheets** pour « ajouter à une playlist », le tri et le filtre, l'import de lien, et les
  détails du flux. La file et les paroles ne sont pas des feuilles : ce sont des vues du lecteur
  (5.5).

### 4.2 Desktop (fenêtres ≥ 840 px)

- **Barre du haut maison** (macOS : `TitleBarStyle.hidden`), haute de 64 dp ; la zone des
  feux tricolores de macOS reste libre ; tout est sur la ligne de la recherche :
  - ← → à gauche pour l'historique de navigation (aussi ⌘[ ⌘]) ;
  - **la recherche, toujours visible** (⌘F), haute de 48 dp et centrée verticalement (8 dp au
    moins du haut de la fenêtre et du haut de la carte de contenu et du lecteur). Elle est
    centrée sur la **carte de contenu**, pas sur la fenêtre, et large de 360 à 560 dp. Taper
    ouvre les suggestions (mêmes règles que 6.2) en menu déroulant sous le champ ; la vue
    ouverte garde la place, la hauteur, l'icône de recherche et la touche « ⌘F » de la barre
    (rien ne saute au clic ni à la fermeture). Entrée ouvre les résultats dans Explorer ;
  - à droite, les téléchargements en cours, puis Sources.
- **Rail à gauche**, replié (icônes) ↔ déplié :
  - Accueil et les destinations du domaine courant (3 en musique) ;
  - puis **« Épinglés » du domaine courant** (`ui.pinned.<domaine>`) : Likés, Téléchargés et
    les collections que l'utilisateur épingle, en pochettes de 32 dp (titre et sous-titre
    quand le rail est déplié). Ce sont aussi des cibles de glisser-déposer : la ligne entière
    se borde en tirets avec « déposer ici » ;
  - en bas, le choix du domaine : un **FAB menu M3E** avec l'icône du domaine courant (son nom
    à côté quand le rail est déplié), qui s'ouvre vers le haut sur la liste des domaines, le
    courant coché. **Masqué tant qu'il n'y a qu'un domaine** (la v1), comme la rangée de puces
    de l'Accueil ; la galerie le montre avec trois domaines fictifs. Puis les sections
    globales Téléchargements, Sources, Réglages, qui remplacent le ☰ du mobile.
- **Routes** (addendum navigation entre domaines §3) : `/home`, `/music/explore`,
  `/music/library/…` ; une page d'entité s'ouvre dans la branche d'où elle vient, préfixée par
  le domaine (`/home/music/album/:id`, `/music/explore/album/:id`) ; `/downloads`, `/sources`,
  `/settings/…` sont globales. Le domaine courant se lit dans la route (`domainOf`).
- **Pages en largeur** :
  - en-tête horizontal (pochette à gauche, titre et actions à droite) ;
  - les listes de titres deviennent un tableau : #, titre + artistes, album, durée, ⋮. C'est la
    même ligne de titre (5.1), avec deux colonnes de plus quand la place le permet.
- **Souris** :
  - au survol d'une ligne, le numéro devient ▶ et ⋮ apparaît ;
  - **double-clic = lire**, clic simple = sélectionner ;
  - ⇧ / ⌘ clic = sélection multiple ; Entrée lit la sélection ;
  - clic droit = menu expressif (5.2) ;
  - glisser une sélection vers un épinglé, vers une playlist ou vers la file ;
  - au survol d'une carte, un bouton ▶ apparaît.
- **Panneau « en lecture » à droite** : le widget `NowPlaying` en taille moyenne (5.5), dans
  une side sheet standard.
  - Il se replie en une **bande de 76 px**, symétrique du rail, cohérente avec le lecteur :
    trois groupes répartis sur la hauteur, espacements en jetons :
    - en haut, le bouton qui rouvre le panneau, puis la pochette du disque avec son anneau ;
    - au milieu, ⏯ rempli (le plus gros, même style que dans le lecteur), ⏭ tonal, like ;
    - en bas, le volume en slider **vertical** de 120 dp au plus, à piste épaisse (M3E
      « m », le haut-parleur dans la piste, en bas), poignée visible et dans son cadre.

    Cette bande est le mini-lecteur du desktop. Il n'y a ni barre en bas ni mini-lecteur
    flottant.
  - **Le bouton qui change la taille du lecteur est toujours dans le coin haut droit de sa
    surface, en dernier** : panneau = en-tête à droite (sortie audio · ⤢ · replier) ; bande =
    en haut de la bande, au-dessus de la pochette ; immersif = le même coin (⤡), et Échap.
  - Déplié par défaut au-dessus de 1000 px, replié en dessous. Le choix de l'utilisateur
    (⌘⌥B) est retenu (`ui.now_playing_open`).
- **Vue immersive** : une icône ⤢ dans l'en-tête du panneau, ou ⌘⇧F. Le lecteur prend toute la
  fenêtre : pochette à gauche, la vue Paroles ou File à droite, contrôles en bas. Échap pour
  sortir.
- **Les bottom sheets deviennent :**
  - « ajouter à une playlist », tri et filtre → menus ;
  - import de lien et détails du flux → dialogues.
- **Clavier** :

  | Touches | Action |
  |---|---|
  | Espace | lecture / pause |
  | ← / → | ±10 s |
  | ⇧← / ⇧→ | précédent / suivant |
  | ⌘↑ / ⌘↓ | volume |
  | ⌘L | like |
  | ⌘F | recherche |
  | ⌘[ / ⌘] | historique |
  | ⌘⌥B | panneau |
  | ⌘⇧F | immersif |
  | ⌘, | réglages |
  | ⌘R | rafraîchir l'accueil |
  | Suppr | retire de la playlist ou de la file |

  Aucun raccourci quand un champ texte a le focus. La barre de menus macOS (Lecture, Aller,
  Fenêtre) et les touches média portent les mêmes actions.
- **Fenêtre** :
  - taille minimale 840 × 600 ;
  - taille, position et état du rail et du panneau retenus ;
  - fermer la fenêtre **garde la musique** (l'app reste dans le Dock) ; ⌘Q quitte.
- **Le desktop n'a pas** de bottom sheets, de gestes du mini-lecteur, ni de tirer pour
  rafraîchir.

### 4.3 Tablettes, pliables, paysage

Il y a trois classes de largeur M3 :

- **compacte** (< 600 dp) : la coque téléphone ;
- **moyenne** (600 à 840 dp : tablette en portrait, pliable ouvert) :
  - le rail replié à gauche remplace la barre du bas ;
  - les grilles et les étagères s'élargissent ;
  - le mini-lecteur reste la toolbar et le FAB du téléphone ;
  - le lecteur plein écran passe en deux colonnes ;
- **étendue** (≥ 840 dp) : la coque desktop. Sur une tablette Android, elle n'a pas de barre
  de titre maison : la recherche est dans l'app bar.

Un téléphone en paysage met le lecteur en deux colonnes, la pochette à gauche et les blocs à
droite. Les listes restent sur une colonne.

### 4.4 Clavier et focus

Ces règles valent partout où il y a un clavier : desktop, mais aussi tablette avec clavier.

- **Anneau de focus** : un trait `secondary` de 3 px, décalé de 2 px, qui épouse la forme de
  l'élément (pilule, carte, cookie). Il n'apparaît qu'au clavier, jamais au clic ni au toucher.
  Il est défini une fois, dans `design/`.
- **Ordre de Tab** : barre de titre, puis rail, contenu et panneau.
- **Tableaux et grilles** : Tab y entre une fois, puis les flèches se déplacent (focus
  itinérant).
  - Entrée lit.
  - Dans une liste, Espace sélectionne ; ailleurs, Espace fait lecture / pause.
  - Menu ou ⇧F10 ouvre le menu expressif, Échap le ferme.
  - Une ligne qui a le focus montre ▶, comme au survol.

## 5. Composants partagés

**Règle de réutilisation, pour toute l'app :** chaque élément visuel existe **une seule fois**
dans `design/`, paramétré par sa taille et son état. Un écran ou une coque n'en recrée jamais
une variante. Les six briques :

- **la pochette** (`VArtwork` : forme, anneau, rotation) ;
- **le groupe de contrôles** ;
- **la progression ondulée** (circulaire autour d'une pochette, linéaire, ou bord en vague) ;
- **le sélecteur** de vues ;
- **la ligne de titre** ;
- **le menu expressif**.

Les tests de `design/` vérifient que les écrans n'importent pas leurs propres versions (§9).

### 5.1 La ligne de titre (une seule, partout)

Recherche, album, playlist, file, historique, likés, téléchargés : même composant.

- Hauteur 56. Marge gauche 16. Pochette 44 en carré arrondi (rayon 12), ronde pour un artiste.
- Titre en `titleMedium`. En dessous : badges (E explicite, téléchargé) puis artistes en
  `bodyMedium` `onSurfaceVariant`. Ellipse sur une ligne.
- ⋮ à droite, en cible tactile de 48.
- États :
  - **En lecture** : titre en `primary` et égaliseur animé sur la pochette.
  - **Hors ligne et pas téléchargé** : opacité 38 %, toucher → message « hors ligne ».
- **Page album, seule exception** : le numéro de piste prend la place de la pochette, avec la
  même géométrie (12 fois la même image n'apporte rien).
- Gestes :
  - toucher = lire (desktop : double-clic, voir 4.2) ;
  - glisser à droite = « Lire ensuite » (fond tonal qui se révèle, ressort) ;
  - appui long, ou clic droit sur desktop = menu expressif (5.2).
- Si M3E propose mieux plus tard, par exemple des listes segmentées en groupes, on change ce
  composant, une seule fois.

### 5.2 Menu expressif

Appui long sur mobile, clic droit sur desktop, ⋮ partout. L'élément se soulève. Le menu s'ouvre
à côté : d'abord une rangée d'actions rapides en groupe connecté (lire ensuite, ajouter à la
file, like), puis des groupes séparés par des espaces. Même menu sur mobile et sur desktop.

### 5.3 Mini-lecteur (mobile) : toolbar flottante + FAB

- Le couple officiel M3E, flottant au-dessus de la barre de navigation :
  - une **toolbar flottante** en pilule, qui contient la pochette du disque (forme cookie qui
    tourne pendant la lecture, avec l'anneau ondulé de progression), le titre, l'artiste et
    like ;
  - à côté, un **FAB carré arrondi ⏯**. Il morphe entre lecture et pause et, pendant un
    chargement, devient le loading indicator M3E (formes qui se transforment).
- Gestes, sur la toolbar :
  - ← / → : titre suivant / précédent (la toolbar suit le doigt, ressort) ;
  - ↑ (ou toucher) : ouvre le lecteur. La pochette grandit en continu jusqu'au lecteur ;
  - ↓ : arrête et masque, avec une snackbar « Lecture arrêtée — Annuler » pendant 5 s
    (`stop()` / `undoStop()` du plan 4).

  Chaque geste a son équivalent dans le menu de la toolbar.
- Le même assemblage (pochette + titre + like + ⏯) sert d'en-tête compact aux vues Paroles et
  File du lecteur (5.5) : c'est le même widget.

### 5.4 Autres composants

| Composant | Où |
|---|---|
| Carousel héros | Accueil (découverte, mixes) |
| Carousel multi-browse | Artiste (albums) |
| Étagère (titre + rangée horizontale de cartes 108) | Accueil, Explorer |
| FAB étendu → FAB | Sources : « Ajouter une source » (ouvre la feuille §6.7) ; sur desktop, le FAB de la destination se place en haut du rail |
| FAB menu | Bibliothèque : « Nouvelle » (nouvelle playlist, importer un lien) ; Accueil : « Lancer », icône ▶ (`play_arrow`) pleine (mélanger mes likés, radio de ce que j'écoute, reprendre la dernière écoute) ; lecteur : Paroles · Lecteur · File (5.5) ; rail desktop : le choix du domaine (4.2) |
| Split button | Toute collection qui se lit, qui se réduit en FAB lecture au défilement : album, playlist, Top 50, genre : « Lire » \| ▾ (aléatoire, lire ensuite, ajouter à la file) ; artiste, likés, téléchargés : « Aléatoire » \| ▾ (lire dans l'ordre, radio, lire ensuite, ajouter à la file) |
| Groupe de boutons | Contrôles du lecteur (aléatoire · ⏮ · ⏯ · ⏭ · répétition, grande taille) |
| Groupe de boutons connectés | Rangée rapide des menus, choix des Réglages |
| Loading indicator M3E | Résultats de recherche, chargement de page, premier lancement |
| Progress ondulé | Anneau du disque (lecteur, mini-lecteur, bande desktop), bord en vague, téléchargements |
| Toolbar flottante | Mini-lecteur (+ FAB ⏯) ; sélection multiple (+ FAB « Lire » ; ajouter à une playlist, télécharger, like, retirer dans la toolbar) |
| FAB | ⏯ du mini-lecteur (devient le loading indicator pendant un chargement) |
| Chips | Filtres de recherche et de bibliothèque |
| Listes en groupes arrondis | Réglages |
| Snackbar, dialogues, badges, switch, tirer pour rafraîchir | Où l'usage M3 les place |
| Squelettes | Toute zone qui charge ; même taille que le contenu final |

**Règle d'emploi** (guide M3) : un seul FAB ou split button par écran, pour son action
principale. Un FAB menu regroupe plusieurs lancements ou créations d'un même écran. Un split
button, c'est une action principale et ses variantes. Les groupes de boutons connectés servent
aux bascules indépendantes (like / playlist / télécharger) et aux choix ; jamais à une action
principale. Le FAB ⏯ du mini-lecteur appartient au lecteur, pas à l'écran : sur téléphone, le
FAB d'écran se place au-dessus de lui, aligné à droite avec 16 dp d'écart, se masque au
défilement vers le bas et revient vers le haut. Un split button d'en-tête qui se réduit au
défilement devient ce FAB d'écran.

### 5.5 Le lecteur : un seul widget `NowPlaying`, trois tailles

Le même widget sert partout. Seules la taille et la mise en page changent :

| Taille | Où |
|---|---|
| **compact** | mini-lecteur mobile (5.3), bande desktop (4.2), en-tête des vues Paroles et File |
| **moyen** | panneau desktop |
| **grand** | lecteur plein écran mobile, vue immersive desktop |

**Les blocs, toujours dans cet ordre** (la même colonne dans le panneau, l'immersif et le
plein écran mobile) :

1. En-tête : « Lecture depuis … » · sortie audio (desktop) · ⤢ (desktop) · ⋮ · **le bouton
   de taille** (⌄ sur mobile, replier dans le panneau, ⤡ dans l'immersif), toujours dernier,
   dans le coin haut droit.
   - Le ⋮ contient : Aller à l'album · Aller à l'artiste · **Minuterie** (15, 30, 45 ou 60 min,
     fin du titre, annuler) · « Ce n'est pas le bon morceau » · Détails du flux.
   - Quand une minuterie tourne, une lune et le temps restant s'affichent dans l'en-tête.
2. La pochette, selon le style choisi (ci-dessous), dimensionnée pour que pochette, écart et
   trait de progression tiennent dans sa boîte, avec un espace en jetons sous l'en-tête :
   l'anneau ou la vague ne débordent jamais sur l'en-tête ni sur une séparation.
3. Les temps : en Disque, centrés juste sous l'anneau, en une ligne `1:14 / 3:26`
   (labelLarge, chiffres tabulaires, onSurfaceVariant) ; en Vague, sous la vague, à gauche et
   à droite.
4. Le titre (Google Sans arrondie) et les artistes à gauche ; à droite du titre, **trois
   boutons icônes standard** (sans conteneur) : J'aime (bascule), Ajouter à une playlist,
   Télécharger (icône de téléchargement, pleine une fois téléchargé, anneau de progression
   pendant).
5. Le groupe de contrôles : aléatoire · ⏮ · ⏯ · ⏭ · répétition, sur toute la largeur de la
   colonne. C'est l'action principale du lecteur : rien d'autre dans la colonne n'est plus
   gros.
   - Un button group M3E grande taille (64 dp de haut au moins, 72 sur un téléphone
     tenu droit) : aléatoire et répétition en bascules aux extrémités, ⏮ et ⏭ tonals, ⏯
     rempli et le plus large. Les largeurs morphent à l'appui.
   - ⏯ morphe et devient le loading indicator pendant un chargement.
6. La **rangée du bas** : à gauche, le volume (desktop), un slider M3E à piste épaisse
   (« m », le haut-parleur dans la piste), poignée visible et dans son cadre, qui prend la
   place restante, 240 dp au plus ; sur mobile, à sa place, le
   bouton de sortie audio. À droite, un **FAB menu M3E** qui remplace le sélecteur : son icône
   est celle de la vue courante, il s'ouvre vers le haut sur Paroles · Lecteur · File
   (l'entrée courante cochée).

Les écarts verticaux viennent des jetons, sans bande morte ; la colonne se centre si l'écran
est plus haut que nécessaire.

**Les trois vues** du FAB menu partagent le même cadre :

- **Lecteur** : tous les blocs.
- **Paroles** : la pochette se rétracte en en-tête compact (transition partagée). Les paroles
  synchronisées suivent : la ligne active est en grand, et toucher une ligne y amène la
  lecture.
- **File** : le même en-tête compact, puis « À suivre » et « Radio · titres proches », en
  lignes de titre (5.1) avec poignée. On glisse une ligne pour réordonner, et on la glisse à
  gauche pour la retirer.

**Deux styles**, au choix dans Réglages › Apparence › « Style du lecteur »
(`ui.player_style`) ; le défaut est **Disque** :

- **Disque.** La pochette est masquée par une forme M3E « cookie » à 12 lobes.
  - Pendant la lecture, elle tourne lentement (un tour en 20 s). En pause, elle morphe en carré
    arrondi, et la pochette entière redevient visible.
  - Autour, l'**anneau ondulé est la progression**. On le fait glisser pour avancer.
    Sémantique : un slider accessible, avec ←/→ au clavier.
  - Les temps sont sous l'anneau, en une ligne centrée.
- **Vague.** La pochette est en pleine largeur, et son **bord bas est une onde** qui ondule
  pendant la lecture et s'aplatit en pause.
  - La partie déjà jouée de l'onde est tracée en `primary` : **le bord est la progression**.
    On glisse le long du bord pour avancer, avec la même sémantique de slider.
  - L'onde rogne le bas de l'image d'environ 10 px.
  - Les temps sont sous la vague, aux deux bouts.

Dans les deux styles, le mini-lecteur, la bande desktop et l'en-tête compact gardent la pochette
du disque. Avec « réduire les animations », il n'y a ni rotation ni ondulation : la forme et
l'onde restent statiques.

### 5.6 Transitions et haptique (une fois, dans `design/`)

**Transitions de page.** Elles sont toutes définies dans `design/motion.dart`. Une route n'en
choisit jamais d'autre.

| Transition | Où |
|---|---|
| **Container transform** | carte ou ligne → sa page (album, artiste, playlist, catégorie) ; la carte s'agrandit en page |
| **Shared axis horizontal** | vues du sélecteur Paroles · Lecteur · File ; étapes du premier lancement |
| **Fade through** | changement de destination (barre du bas, rail) |
| **Élément partagé** | pochette du mini-lecteur → lecteur ; en-tête compact ↔ grande pochette |

Avec « réduire les animations », tout devient un fondu de 150 ms.

**Haptique** (mobile seulement), discrète, toujours liée à un mouvement :

| Retour | Déclencheur |
|---|---|
| léger | like ; ⏯ |
| « sélection » | changement de vue du sélecteur ; franchissement du seuil d'un geste du mini-lecteur ou d'un glissement de ligne |
| moyen | arrêt par ↓ ; dépôt d'un élément réordonné |

Les réglages système sont respectés (haptique désactivée → rien). Un seul point d'entrée :
`design/haptics.dart`.

### 5.7 Faire découvrir les gestes

Tout le monde doit connaître les contrôles cachés. Chaque astuce s'affiche **une seule
fois**, jamais en boucle, et est retenue dans `ui.hint.*` :

- **Premier mini-lecteur** : une rich tooltip M3 au-dessus, « Glisse ← → pour changer de
  titre, ↓ pour arrêter », avec « OK ». La toolbar esquisse le geste une fois : un petit
  va-et-vient, puis un léger rebond vers le bas. « OK » ou n'importe quel geste la ferme pour
  de bon.
- **Première liste de titres** : la première ligne s'entrouvre seule vers la droite (« Lire
  ensuite » apparaît), puis revient en ressort. Cela dure 1 s, sans texte.

Avec « réduire les animations », seule la tooltip s'affiche, sans mouvement. Il n'y a rien sur
desktop, faute de gestes.

### 5.8 Feuilles et dialogues

Ce sont des feuilles sur mobile, des menus ou des dialogues sur desktop (4.2). Les règles :

- une seule action principale, à droite ;
- « Annuler » en bouton texte ;
- jamais de dialogue par-dessus un dialogue ;
- une action destructrice se fait tout de suite, avec « Annuler » dans un snackbar, plutôt
  qu'avec une confirmation.

| Flux | Contenu |
|---|---|
| Ajouter à une playlist | « Nouvelle playlist » en tête, puis une recherche ; les playlists qui ont déjà le titre portent le cookie + coche (§2.3) |
| Nouvelle playlist | un nom et l'aperçu de la mosaïque |
| Importer un lien | la progression ondulée page par page ; l'avertissement de coupe à 50 pages (5 000 titres) avant de commencer ; « Ouvrir » à la fin |
| Ce n'est pas le bon morceau | les candidats avec leur source et leur durée ; « Lire » pour écouter avant de choisir ; le choix est retenu pour ce titre |
| Mise à jour disponible | version, taille, notes en trois lignes au plus, « Plus tard » / « Installer » |
| Ajouter une source | §6.7, une seule feuille |

## 6. Écrans

### 6.1 Accueil : ce qui est à toi

Un fil qui se charge au fur et à mesure. Dans l'ordre :

1. **« Bonsoir »** (selon l'heure), en grande app bar qui se replie.
2. **Raccourcis** (local) : une ligne de pastilles, les 6 collections les plus jouées
   récemment.
3. **À découvrir** (réseau) : une carte héros « Ta découverte du jour » (30 titres jamais
   écoutés, lecture en un toucher), puis des pages de 4 lignes de titre qu'on fait glisser.
   Chaque ligne affiche sa raison (« comme Halo »).
4. **Tes mixes** (réseau au toucher) : carousel héros, un mix par artiste de ton top. La radio
   est lancée au toucher seulement.
5. **Le fil**, une étagère à la fois, puis ça recommence avec de nouvelles graines :
   - « Parce que tu as écouté X » : albums et artistes proches, un X différent à chaque fois ;
   - Nouveautés de tes artistes : sorties de moins de 30 jours ;
   - Redécouvrir (local) : likés pas écoutés depuis 60 jours ;
   - Classement du moment : la première catégorie vedette de `music.browse` (avec Deezer, le
     Top 50) ;
   - Écoutés récemment, Tes playlists, Téléchargés (local).
6. **Fin honnête** : le fil s'arrête quand il n'a plus de vraies graines, soit environ 15 à 25
   étagères. Il se termine sur une carte « Tu as fait le tour » qui mène à Explorer. Pas
   d'étagères de remplissage.

Fluidité :

- Le fil est préparé par le cœur (7.2). L'accueil s'ouvre depuis le cache, même hors ligne.
- Pages de 4 étagères ; la suivante est demandée à 2 étagères de la fin.
- Étagères à hauteur fixe. Images décodées à leur taille d'affichage.

Animations :

- **Pas d'aimantation verticale.** Sur un long fil, elle contrarie les gestes rapides.
- Les rangées horizontales et les carousels s'aimantent (ressort).
- Une étagère entre en fondu avec une légère montée la première fois qu'elle apparaît
  (décalage de 40 ms entre ses cartes), puis plus jamais.
- « Bonsoir » se replie, et la carte découverte se rétracte (échelle et parallaxe de sa
  mosaïque) en sortant.

Tirer pour rafraîchir reconstruit le fil.

**Premier lancement / historique vide** : les raccourcis et les étagères personnelles sont
masqués. La découverte prend ses graines dans les Classements de `music.browse` : la carte
devient « Pour commencer ». Sans plugin browse, une carte envoie vers Explorer.

**Réglage** Confidentialité › « Découvertes à partir de mon écoute » (activé par défaut) :
désactivé, l'accueil ne garde que les étagères locales, et aucune graine ne part vers un plugin.

### 6.2 Explorer : le monde

- **Au repos** :
  - la search bar en haut ;
  - deux grandes cartes « vedettes » données par `music.browse` (avec Deezer : Top 50 et
    Sélection) ;
  - la grille « Parcourir » des catégories (genres et humeurs), deux colonnes, sur téléphone.
    Chaque tuile a une teinte pastel fixe tirée de l'identifiant de la catégorie. L'image de la
    catégorie y est **découpée dans une forme de décor M3E**, elle aussi fixe et tirée de l'id
    (trèfle, soleil, fleur, pilule, éclat, arche, gemme, cookie). Elle est inclinée et dépasse
    du coin de la tuile. Au toucher, la forme grossit et morphe en carré pendant le container
    transform vers la page du genre. Pas d'extraction. Les deux cartes vedettes suivent la
    même règle, en plus grand.
- **Une catégorie** : grande app bar, puis des étagères (titres, albums, artistes, playlists),
  paginées.
- **Pendant la frappe** : search view M3 en plein écran, **que des suggestions** :
  1. « Dans ta bibliothèque » (local, instantané) : jusqu'à 3 lignes. Un toucher ouvre
     directement l'élément.
  2. « Suggestions » : historique de recherche (icône horloge) puis suggestions du plugin
     (icône loupe). Le préfixe tapé est en gras. ↖ recopie la suggestion dans le champ.
  3. La requête au plugin part après 150 ms sans frappe, et la précédente est annulée.
- **À la validation** : les vrais résultats.
  - Puces Tout / Titres / Albums / Artistes / Playlists.
  - Meilleur résultat en carte, puis les sections.
  - Loading indicator M3E seulement à cet endroit.
- **Hors ligne, ou sans plugin browse** : la search bar, l'historique et la bibliothèque. Les
  vedettes et la grille sont remplacées par un message clair (hors ligne : dernière copie en
  cache si elle existe).
- Desktop : 3 à 5 colonnes selon la largeur ; `Cmd+F` focalise la recherche.

### 6.3 Bibliothèque

- Grande app bar : ☰, recherche dans la bibliothèque, tri.
- **Tuiles** :
  - **Likés** : un petit collage des 3 dernières pochettes likées ;
  - **Téléchargés** ;
  - **Top 50** : tes 50 titres les plus écoutés. On compte les écoutes d'au moins 30 s sur
    90 jours. Si cela donne moins de 50 titres, on complète sur tout l'historique. Ordre fixe ;
  - **Historique** : groupé par jour, avec des en-têtes de jour qui restent visibles au
    défilement.

  Chaque tuile a son icône dans un conteneur de forme de décor différente.
- **Page Top 50 en podium** :
  - les 3 premiers en tête, le n°1 au centre et plus grand. Le n°1 est en cookie avec son
    anneau s'il joue, sinon en carré arrondi ;
  - ensuite, les rangs s'affichent en **grands chiffres arrondis en contour**, à la place du
    numéro dans la ligne de titre ;
  - le sous-titre donne le nombre d'écoutes ;
  - ▶ et aléatoire sont dans l'app bar ; pas de tri.
- **Puces** Playlists / Albums / Artistes, puis la liste.
- **FAB menu** : nouvelle playlist, importer un lien.
- **Tri** (bottom sheet sur mobile, menu sur desktop ; choix retenu par liste) :
  - collections (playlists, albums, artistes) : Récents (défaut, date d'ajout ou de like),
    Dernière écoute, Nom A→Z ;
  - listes de titres (Likés, Téléchargés) : Date d'ajout (défaut), Titre, Artiste.
- Le tri se fait dans le cœur, parce que les listes sont paginées (7.3).

### 6.4 Album / playlist

- La pochette en grand (carré arrondi, ou cookie si cet album joue), fondue dans la surface du
  thème (pas de teinte propre, 2.2).
- Titre, artistes, année et durée.
- Split button « Lire | ▾ », like et télécharger en boutons tonaux.
- Lignes de titre (numérotées pour un album).
- **En-tête qui se replie** (app bar flexible M3E) : au défilement, la grande pochette
  rétrécit en continu jusqu'à se loger dans l'app bar, à gauche du titre, qui la suit. Le
  split button étendu devient un FAB lecture. La même mécanique sert aux pages playlist,
  artiste (en cercle) et catégorie.
- Playlist perso : réordonner par glisser, et sélection multiple avec toolbar flottante.
- **Pochette d'une playlist perso** : sa pochette propre si elle en a une. Sinon, une
  **mosaïque 2×2** des pochettes des 4 premiers titres distincts, ou moins s'il y en a moins.
  Vide, la playlist affiche une icône. La mosaïque est une forme de `VArtwork`, partout où
  la playlist apparaît.

### 6.5 Artiste

Photo en grand fondue dans la surface, bouton Radio (la radio remplace la file), puis une carte
**« Dernière sortie »** quand l'artiste a sorti quelque chose depuis moins de 90 jours
(`browse.releases`, mis en cache 24 h ; sans plugin `browse` ou sans sortie récente, pas de
carte). Viennent ensuite les titres populaires, puis les albums en carousel multi-browse.

### 6.6 Lecteur plein écran (mobile)

`NowPlaying` en grande taille (5.5), sur le fond teinté du thème : une surface unie
(`surfaceContainer`), sans dégradé.

- On l'ouvre depuis le mini-lecteur (↑ ou toucher).
- On le ferme avec ⌄ (en haut à droite) ou en glissant vers le bas.
- La sortie audio ouvre le sélecteur du système.
- File et Paroles sont des vues du lecteur, pas des feuilles.

### 6.7 Réglages, premier lancement, sources, téléchargements

- **Réglages** : listes M3E en groupes arrondis.
  - Apparence : source de couleur, noir pur, thème, style du lecteur (Disque / Vague).
    - En haut, un **aperçu en direct** : un vrai `VNowPlaying` compact (ce qui joue, ou une
      pochette d'exemple) qui change à chaque toucher.
    - Les choix sont des **groupes de boutons connectés**, pas des listes radio.
  - Lecture : radio de fin de file, normalisation.
  - Téléchargements.
  - Sources : la liste des sources, l'ajout par lien, l'ordre (avancé).
  - Confidentialité : télémétrie, découvertes à partir de l'écoute.
  - À propos : mises à jour, diagnostics, rapport de bug.

  Pour une vérification forcée des mises à jour : `Ok(None)` affiche « à jour » ; une mise à
  jour disponible n'apparaît que par la notice.
- **Premier lancement** : loading indicator M3E, étapes, puis le choix de télémétrie sans option
  présélectionnée (socle §4.6). Deux étapes changent :
  - **« Ajoute une source pour lire »** remplace « Ajouter un dépôt ». Elle a une phrase et un
    champ « Colle un lien de source », qui ouvre la feuille ci-dessous, puis « Passer ».
  - **« Les notifications »**, juste avant la télémétrie, sur Android 13 et plus : « Pour voir
    la lecture sur l'écran verrouillé et suivre tes téléchargements. Rien d'autre. »
    Boutons « Plus tard » et « Autoriser ». Après « Plus tard », la demande ne revient qu'au
    premier téléchargement. Une étape s'ajoute après l'installation des sources :
  **« Choisis au moins 3 artistes »**.
  - Des **bulles** de tailles variées, qui flottent doucement. Elles sont tirées de l'étagère
    « artists » de la catégorie vedette `chart:0`, avec un champ de recherche au-dessus.
  - Un toucher like l'artiste : sa bulle grossit et morphe de cercle en cookie, avec une coche
    et une haptique légère.
  - Le bouton s'écrit « Continuer · N ».
  - Chaque étape du premier lancement a sa grande forme de décor, qui morphe vers celle de
    l'étape suivante (shared axis).
  - « Continuer » s'active dès 3 artistes ; « Passer » reste toujours possible.
  - Sans plugin `browse`, ou hors ligne, l'étape est sautée.
  - Ces likes servent de graines au fil d'accueil dès la première ouverture (7.2).
- **Sources** :
  - **Ajouter une source** tient en une feuille. Une source s'ajoute avec un **lien de
    source** : `vehicoule://add-source?feed=<URL du feed>&key=<clé publique>`. Le lien est
    publié par l'auteur de la source, sur son site ou son README. L'URL et la clé voyagent
    ensemble, et l'utilisateur ne voit jamais de clé. Le lien arrive de deux façons :
    - toucher le lien (lien profond) ouvre la feuille ;
    - « Coller un lien » dans Réglages › Sources, ou à l'étape du premier lancement.
  - La feuille montre :
    - le nom de la source ;
    - ce qu'elle ajoute, en mots simples (« Lecture des titres · Paroles ») ;
    - une phrase : « Cette source ne vient pas de Vehicoule. Ajoute-la seulement si tu lui
      fais confiance. » ;
    - les boutons « Annuler » et « Ajouter ».

    L'empreinte, les domaines contactés et la version sont repliés sous « Détails ». Toucher
    « Ajouter » vaut accord explicite (socle §4.4). Il n'y a ni case à cocher ni champ de clé.
    Un lien ne fait jamais rien sans cette feuille.
  - Après l'ajout, les sources s'installent seules, et un snackbar dit « Communauté FR
    ajoutée ».
  - La clé est retenue à la première fois. Si une mise à jour arrive signée par une autre clé,
    elle est refusée, avec ce message : « Cette source a changé de signature. Retire-la, puis
    ajoute-la de nouveau depuis son lien. »
  - L'écran Sources liste chaque source par origine (Officiel, puis le nom de chaque lien
    ajouté). Une ligne montre ce que fait la source et un interrupteur ; son menu propose
    « Retirer », avec Annuler. L'ordre de priorité par capacité vit dans « Avancé », replié.
- **Sources**, **Téléchargements** : sections globales, ouvertes depuis le rail.
  - Téléchargements : une barre de stockage en tête (musique téléchargée / espace libre). Un
    titre en cours a l'**anneau ondulé** autour de sa pochette, celui du mini-lecteur, qui
    montre le pourcentage.

### 6.9 États transverses

- **Hors ligne** : une puce discrète sous l'app bar, « Hors ligne · tes téléchargements restent
  là ». Pas de bannière.
- **Tirer pour rafraîchir** : le loading indicator M3E (forme qui morphe), pas un spinner.
- **États vides** : une grande forme de décor avec une icône, une phrase et une action. Aucune
  image externe ; un seul `VEmptyState`.

### 6.8 Hors de l'app : widget Android, barre des menus macOS

Ce sont les deux seules exceptions à la règle de réutilisation : Flutter ne dessine ni les
widgets d'écran d'accueil Android ni les popovers de la barre des menus. Ils sont donc natifs.
Ils reprennent les mêmes couleurs (Material You sur Android, la teinte « ce qui joue » sinon),
la pochette en forme cookie et l'ordre des blocs du lecteur compact. Ils ne contiennent aucune
logique : ils affichent l'état et envoient des commandes.

- **Widget Android** (Jetpack Glance, Kotlin), en deux tailles :
  - 2×2 : la pochette cookie avec l'anneau, et ⏯ ;
  - 4×2 : la pochette, le titre, l'artiste, ⏮ ⏯ ⏭ et like.

  Les couleurs dynamiques sont celles d'Android 12 et plus. Toucher la pochette ouvre le
  lecteur. Les boutons passent par la session média d'`audio_service` (MediaButtonReceiver),
  si bien qu'ils marchent même quand l'interface Flutter n'est pas lancée. Dart publie l'état
  (titre, artiste, chemin de la pochette, en lecture) à chaque `NowPlaying`, avec le paquet
  `home_widget`. Sans lecture en cours, le widget affiche « Reprendre » sur la dernière file.
- **Barre des menus macOS** (SwiftUI, `NSStatusItem` + popover) :
  - l'icône est une note qui s'anime pendant la lecture ;
  - le popover montre la pochette cookie avec l'anneau, le titre, l'artiste, ⏮ ⏯ ⏭, like et
    « Ouvrir Vehicoule ».

  L'état et les commandes passent par un canal de plateforme vers Dart. Le popover vit tant
  que l'app tourne, y compris fenêtre fermée (4.2). Un réglage desktop « Afficher dans la
  barre des menus » est activé par défaut.

### 6.10 Écran de démarrage

- **Fond** : la couleur de fond de l'icône. **Centre** : le Mochi.
- **Animation**, en 900 ms au plus : le Mochi tombe et rebondit une fois (écrasement puis
  étirement), la note sort, puis l'accueil arrive en fondu (200 ms).
- **Android 12 et plus** : l'API SplashScreen, avec une icône animée en vecteur.
- **macOS, Windows, Linux** : la même séquence dans la fenêtre, au premier frame Flutter.
- Ni texte, ni spinner, ni logo écrit. Le démarrage n'attend jamais le réseau : l'accueil
  s'ouvre depuis le cache (7.2).
- Rien au démarrage à chaud. Avec « réduire les animations » : l'icône fixe, puis le fondu.

### 6.11 Surfaces système

- **Notification média Android**, qui sert aussi à l'écran verrouillé :
  - la pochette et la progression ;
  - ⏮ ⏯ ⏭ ;
  - like en action personnalisée (le cœur se remplit) ;
  - × pour arrêter.

  Les couleurs sont laissées au système.
- **Permission de notifications** : §6.7.
- **macOS** : « En cours de lecture » du Centre de contrôle et touches média, par les infos de
  lecture du système. Le mini-lecteur de la barre des menus s'y ajoute (6.8).

## 7. Cœur : ce qui s'ajoute

### 7.1 Contrat `vehicoule:music` 1.1.0 : interface `browse`

L'ajout est additif, d'où la version mineure. Un plugin 1.0 reste chargé, simplement sans
`browse`. Le plan vérifie par un test que l'hôte trouve les exports 1.0 d'un plugin quand il
attend 1.1.

```wit
interface browse {
    use types.{error, image, album};
    use entity.{entity};

    record category {
        id: string,
        title: string,
        artwork: list<image>,
        /// Shown as a big card at the top of Explore.
        featured: bool,
    }
    record shelf { title: string, items: list<entity> }
    record category-page { title: string, shelves: list<shelf>, next: option<string> }
    record release {
        album: album,
        /// ISO 8601 date, `YYYY-MM-DD`.
        date: string,
    }

    /// Explore's idle view: featured cards first, then the browse grid.
    categories: func(region: string) -> result<list<category>, error>;
    fetch-category: func(id: string, region: string, cursor: option<string>) -> result<category-page, error>;
    /// An artist's releases, newest first (for "new from your artists").
    releases: func(artist-id: string, region: string) -> result<list<release>, error>;
}
```

`release` porte une date complète, parce que `album.year` ne suffit pas pour « moins de
30 jours ». Le record `album` ne change pas, pour ne rien casser.

Plugin Deezer (API publique, vérifiée le 2026-10-23) :

- **Vedettes** :
  - « Top 50 » = `/chart/0` ;
  - « Sélection » = `/editorial/0/selection`. `/editorial/*/releases` renvoie vide, donc pas de
    carte « Nouveautés ».
- **Grille** = `/genre`, avec leurs images.
- **Catégorie** = `/chart/{genre}`, en étagères Titres / Albums / Artistes / Playlists.
- **Sorties** = `/artist/{id}/albums`, avec `release_date`.

Les classements Deezer suivent le pays de l'IP : `region` est ignoré. Les autres plugins
n'exportent pas `browse` en v1.

Cœur :

- `browse` est une capacité routée comme les autres (socle §4.7).
- Catégories et pages sont mises en cache 24 h (`http_cache` / `kv`). Hors ligne, on sert la
  dernière copie.

### 7.2 Le fil d'accueil

Un module `home` du cœur, sans nouvelle capacité à part `browse`.

- **Graines** (local) :
  - jusqu'à 5 titres parmi les likés récents et le top sur 90 jours ;
  - les artistes du top sur 90 jours, complétés par les artistes likés ;
  - s'il manque des graines de titres, le titre le plus écouté de chaque artiste liké, ou à
    défaut le premier titre de sa page `entity`. C'est ce qui rend le fil personnel dès le
    premier lancement (6.7) ;
  - pas de genre : le contrat ne porte pas de genre par titre, donc pas d'étagère « ton
    genre ». Le classement du fil est la première catégorie vedette de `browse`.
- **Découverte** :
  - `music.radio` sur chaque graine ;
  - fusion en alternance ;
  - dédoublonnage par id canonique, puis par ISRC, puis par titre + artiste normalisés ;
  - retrait de tout ce qui est dans `plays` ou `likes` ;
  - on garde 30 titres, chacun avec sa graine (la « raison »).
- **Parce que tu as écouté X** : `music.radio` sur un titre de X, puis les albums et artistes
  distincts du résultat, sans X.
- **Nouveautés** : `browse.releases` des artistes likés (au plus 10 par jour), sorties de moins
  de 30 jours.
- **Classement** : `browse.category` de la première vedette, première étagère de titres.
- **Redécouvrir, Top 50, récents, playlists, téléchargés** : requêtes locales.
- Les titres et albums du fil sont enregistrés au catalogue comme ceux d'une recherche, donc
  lisibles et likables.
- **Quand** :
  - au premier affichage après 24 h, en arrière-plan ;
  - sur tirer pour rafraîchir ;
  - au retour en ligne si le fil date de plus de 24 h.

  Le fil complet (ids et raisons) est stocké en `kv`. L'accueil lit toujours le cache.
- **Coût réseau** : environ 5 radios + 10 artistes + 1 classement par jour, plus une radio par
  « Parce que tu as écouté X » chargée. Rien à l'ouverture
  de l'app.
- **Vie privée** : les requêtes ne portent que des titres et artistes de graine, sans compte ni
  identifiant d'appareil, comme la radio de fin de file. Le réglage 6.1 les coupe toutes.
- **Mixes** : `play_mix(artist)` choisit ton titre le plus écouté de cet artiste comme graine,
  appelle `music.radio` et lance la lecture.
- **Fin du fil** : quand les graines sont épuisées, `next` vaut `None`.

### 7.3 Ajouts à l'API du pont

| Fonction | Rôle |
|---|---|
| `home_feed(cursor) -> HomeFeedPage { shelves, next }` | Le fil, par pages de 4 étagères, depuis le cache |
| `refresh_home()` | Reconstruit le fil (tirer pour rafraîchir) ; émet `LibraryChanged::Home` |
| `play_mix(artist_id)` | Mix d'artiste (7.2) |
| `browse_categories() -> Vec<CategoryView>` | Vedettes et grille d'Explorer |
| `browse_category(id, cursor) -> CategoryPageView` | Page d'une catégorie |
| `suggest(prefix) -> Vec<SuggestionView { text, from_history }>` | Remplace `Vec<String>` (l'icône dépend de l'origine) |
| `liked(kind, sort, offset, limit)`, `liked_tracks(sort, …)`, `playlists(sort)`, `downloaded(sort, offset, limit)` | Tri côté cœur (6.3) |
| `top_tracks() -> Vec<TopTrackView { plays, track }>` | Top 50 (6.3) : le sous-titre du podium donne `plays` |
| `history(offset, limit) -> Vec<HistoryEntryView { played_at, track }>` | L'historique groupé par jour a besoin de l'heure |
| `set_sleep_timer(SleepTimer)` | `Off`, `Minutes(u32)` ou `EndOfTrack`. À l'échéance, le lecteur met en pause (le volume baisse en fondu sur 5 s avant). Le timer ne survit pas à un redémarrage |
| `NowPlaying.sleep: Option<SleepState>` | `ends_at_ms` ou `end_of_track`, pour l'icône lune et le compte à rebours affichés dans l'en-tête du lecteur |
| `artist_latest_release(artist_id) -> Option<ReleaseView { album: CollectionView, date }>` | Carte « Dernière sortie » (6.5), depuis le cache de `browse.releases` |

Une étagère est `ShelfView { kind: ShelfKind, seed: Option<String>, items: Vec<CardView> }`.
`ShelfKind` vaut Shortcuts, Discovery, Mixes, BecauseYouListened, NewReleases, Rediscover,
Chart, Recent, Playlists, Downloads ou End. Le **titre est traduit côté Dart** à partir du
`kind` et de la `seed` : le cœur ne produit pas de texte d'interface. Une étagère Discovery
porte des `TrackView` et la raison de chacun.

`TrackSort` : Added, Title, Artist. `CollectionSort` : Recent, Played, Title (« Nom A→Z »).

## 8. Accessibilité et performance

- Libellés sur tous les contrôles, y compris les gestes. Chaque geste a son équivalent dans un
  menu : glisser = « Lire ensuite » ; mini-lecteur ↓ = « Arrêter ».
- Texte système à 200 % sans débordement sur l'accueil, Explorer, le lecteur et les Réglages
  (déjà dans le plan 5, Task 8). Les étagères à hauteur fixe grandissent avec le facteur de
  texte.
- Contraste vérifié sur les trois sources de couleur, dans les deux thèmes, par un test de
  tons.
- 60 images/s tenues en défilant l'accueil et Explorer sur l'appareil de référence Android,
  mesurées en profil (plan 5, Task 9).

## 9. Tests

- **Rust** :
  - le fil (graines, dédoublonnage, retrait de l'écouté, fin honnête, cache et hors ligne,
    réglage coupé = aucun appel) ;
  - les tris paginés ;
  - Top 50 (seuil 30 s, fenêtre de 90 jours, complément) ;
  - `browse` routé et mis en cache ;
  - un plugin 1.0 chargé par un hôte 1.1.
- **Plugin Deezer** : `categories`, `fetch-category` et `releases` sur des réponses enregistrées.
- **Dart, widgets** :
  - variantes de la ligne de titre ;
  - suggestions puis résultats (pas de recherche avant validation, annulation à 150 ms) ;
  - pagination du fil ;
  - geste ↓ du mini-lecteur puis Annuler ; FAB ⏯ qui devient le loading indicator pendant un
    chargement ;
  - `NowPlaying` dans ses trois tailles et ses deux styles (Disque, Vague) : mêmes blocs dans
    le même ordre ; le sélecteur change de vue ; l'anneau et le bord en vague se manipulent
    comme un slider (glisser, ←/→) ;
  - desktop : le panneau se replie en bande et s'en souvient ; double-clic lit, clic simple
    sélectionne ; ⇧/⌘ clic sélectionne plusieurs lignes ; glisser une sélection sur un
    épinglé l'ajoute ; ⌘F donne le focus à la recherche de la barre de titre ;
  - « réduire les animations » sans mouvement ;
  - aucune extraction de couleur hors du titre en cours.
- **Natif** :
  - widget Android : un test instrumenté pour l'état publié, puis les boutons, puis la session
    média ;
  - popover macOS : un test de l'état reçu par le canal.
- **Cœur** :
  - la minuterie (échéance, fin de titre, annulation, fondu) ;
  - la dernière sortie (moins de 90 jours, sinon `None`) ;
  - les graines venant d'artistes likés sans aucune écoute.
- **Revue** :
  - aucun import de `package:flutter/material.dart`, ni de `material_3_expressive` hors de
    `design/` ;
  - aucun nombre d'espacement hors des tokens ;
  - aucun écran ni coque qui recrée une des six briques de la règle de réutilisation (§5) ;
  - les garde-fous de §2.8, avec leurs tests ;
  - le vocabulaire et le ton de §2.9 sur les ARB.

## 10. Impact sur les plans

- **Nouveau plan 7, « browse et fil d'accueil »**, à exécuter avant les Tasks 6 et 7 du plan 5 :
  - contrat 1.1 et compatibilité avec 1.0 (plan 1) ;
  - routage et cache de `browse` (hôte et cœur) ;
  - module `home` et ajouts d'API (7.3), puis régénération du pont ;
  - `browse` dans le plugin Deezer (plan 6, dépôt `vehicoule-plugins`).
- **Plan 5, mis à jour** :
  - Task 1 (design) : `material_ui`, `material_3_expressive` 1.2.0, tokens, composants de la
    section 5, `NowPlaying` (5.5) compris, puis la galerie de validation ;
  - Task 5 (routes et coques) : navigation de la section 4 (barre de titre, rail avec
    épinglés, panneau et bande), mini-lecteur (5.3), puis le point de contrôle du shell ;
  - Task 6 (écrans d'écoute) : 6.1, 6.2, 6.4 à 6.6, dont les vues Paroles et File du
    lecteur ;
  - Task 7 : 6.3 et 6.7.

  Les Tasks 2 à 4 ne changent pas. Nouvelle **Task 10** : widget Android et barre des menus
  macOS (6.8), après la Task 6.
- **Plan 7, Task 8 (nouvelle)** : minuterie de sommeil, `artist_latest_release`. Les graines
  issues des artistes likés s'ajoutent à la Task 6 du plan 7.

- **Les 8 sujets** (§2.2 thème clair, 2.5 icône, 2.8, 2.9, 4.3, 4.4, 5.7, 5.8, 6.7 Sources,
  6.10, 6.11) vont au plan 5 :
  - Task 1 : les classes de largeur, l'anneau de focus et les tests de garde-fous §2.8 ;
  - Task 2 : `docs/voice.md` et le test des ARB ;
  - Task 4 : l'écran de démarrage, le lien profond `vehicoule://add-source`, la notification
    média avec like, la demande de notifications, « En cours de lecture » sur macOS ;
  - Task 5 : la largeur moyenne, l'ordre de Tab et le focus itinérant ;
  - Task 6 : les astuces de gestes, le lecteur en deux colonnes ;
  - Task 7 : l'écran Sources, la feuille d'ajout et les deux étapes du premier lancement ;
  - Task 8 : la matrice des tests dorés.

  Le dépôt `vehicoule-ytmusic` publie son lien de source dans son README.

## 11. Hors de cette spec

- Partage, synchronisation et comptes : socle §11.
- `browse` pour YouTube Music (humeurs et genres). C'est possible plus tard, en ajoutant
  l'export au plugin, sans toucher au cœur.
- Le design de l'anime et du manga : leurs specs. Le rail et la barre du bas sont déjà prêts à
  les accueillir.
