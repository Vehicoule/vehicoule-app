# Vehicoule — Interface de la musique v1 : design

Date : 2026-10-23 · Statut : en relecture (v2 : lecteur, mini-lecteur, desktop, réutilisation)

Spec parente : `2026-10-18-socle-musique-design.md` (le « socle »). Celle-ci fixe l'identité
visuelle, les composants, les écrans et les deux nouveautés de cœur qu'ils demandent
(`music.browse`, le fil d'accueil). Maquettes de référence : `.superpowers/brainstorm/…/content/`
(`revision-1.html`, `composants.html`, `desktop.html`, `retours-2.html`, `accueil.html`, puis
`59588-…/content/desktop-2.html` et `lecteur-v3.html`).

## 1. Ce que cette spec change dans le socle

| Socle | Devient |
|---|---|
| §1 Design : « Material 3 officiel + nos tokens ; `material_3_expressive` seulement pour les composants manquants » | `material_ui` (la bibliothèque Material officielle, sortie du SDK) + `material_3_expressive` 1.2.0 pour les composants M3E, les deux derrière `app/lib/design/` (section 3) |
| §1 / §3.2 Accueil « uniquement des données locales, pas de flux éditorial » | Accueil = fil personnel, préparé une fois par jour à partir de tes données et des plugins (section 6.1). Le contenu éditorial reste dans Explorer |
| §11 « Accueil éditorial (classements, nouveautés) : hors v1 » | En v1 : capacité `music.browse`, implémentée par le plugin Deezer (section 7.1) |
| Barre du bas Accueil / Recherche / Bibliothèque | Accueil / Explorer / Bibliothèque / Réglages (Home / Explore / Library / Settings) |

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
- Dégradés : seulement le haut des écrans (`surfaceContainer` → `surface`) et le fond du
  lecteur (un dégradé radial teinté derrière la pochette). Les deux viennent du schéma.

### 2.3 Formes

Les formes expressives de M3E, avec retenue : pochette mise en avant, bouton lecture qui morphe,
cartes héros, FAB. Les listes, les champs et les réglages gardent des coins standards.

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

### 2.6 Mouvement

- Ressorts M3E (spatial et effets) depuis les tokens. Pas de courbes ad hoc.
- Tout passe par `transform` et `opacity`, sans mise en page à chaque image.
- « Réduire les animations » (système ou réglage) remplace tout par des fondus courts.

### 2.7 Espacement

Une seule échelle : 4 · 8 · 12 · 16 · 24 · 32.

- Marges d'écran : 16 sur téléphone, 24 au-delà.
- 24 entre deux sections, 8 entre deux cartes.

Tout vient de `design/tokens.dart`. Aucun nombre magique dans les écrans (vérifié en revue).

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
  - le widget `NowPlaying` (section 5.5) et le sélecteur Lecteur · Paroles · File ;
  - la ligne de titre (section 5.1) ;
  - le menu expressif avec élément soulevé, s'il manque au paquet ;
  - les transitions partagées mini-lecteur → lecteur et carte → page.

## 4. Navigation et coques

### 4.1 Téléphone

- **Barre de navigation M3E** classique, fixe en bas : Accueil, Explorer, Bibliothèque, Réglages.
- **Grande app bar qui se replie** en haut de chaque onglet : grand titre, actions de l'onglet,
  ☰ à gauche. Pas de barre de logo.
- **☰ ouvre le rail déplié M3E en modal**. Il remplace le tiroir, qui n'est plus recommandé en
  M3E. Il contient :
  - les domaines : Musique, puis Anime et Manga quand ils existent ;
  - les sections globales : Dépôts et plugins, Téléchargements.

  La barre du bas montre les destinations du domaine courant.
- **Mini-lecteur** flottant au-dessus de la barre (section 5.3).
- **Bottom sheets** pour « ajouter à une playlist », le tri et le filtre, l'import de lien, et les
  détails du flux. La file et les paroles ne sont pas des feuilles : ce sont des vues du lecteur
  (5.5).

### 4.2 Desktop (fenêtres ≥ 840 px)

- **Barre de titre maison** (macOS : `TitleBarStyle.hidden`) :
  - ← → pour l'historique de navigation (aussi ⌘[ ⌘]) ;
  - au centre, **la recherche, toujours visible** (⌘F). Taper ouvre les suggestions (mêmes
    règles que 6.2) en menu déroulant sous le champ ; Entrée ouvre les résultats dans Explorer ;
  - à droite, les téléchargements en cours, puis Dépôts et plugins.
- **Rail à gauche**, replié (icônes) ↔ déplié :
  - les quatre destinations ;
  - puis **« Épinglés »** : Likés, Téléchargés et les collections que l'utilisateur épingle
    (pochettes seules quand le rail est replié). Ce sont aussi des cibles de glisser-déposer ;
  - en bas, le domaine (Musique / Anime / Manga), qui remplace le ☰ du mobile.
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
  - Il se replie en une **bande de 76 px**, symétrique du rail : pochette du disque avec son
    anneau, like, ⏯, ⏭, volume. Cette bande est le mini-lecteur du desktop. Il n'y a ni
    barre en bas ni mini-lecteur flottant.
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
| FAB étendu → FAB | Album / playlist : « Lire », qui se réduit au défilement |
| FAB menu | Bibliothèque : nouvelle playlist, importer un lien |
| Split button | Album / playlist : « Lire » \| ▾ (aléatoire, lire ensuite, ajouter à la file) |
| Groupe de boutons connectés | Lecteur (like / playlist / télécharger), rangée rapide des menus |
| Loading indicator M3E | Résultats de recherche, chargement de page, premier lancement |
| Progress ondulé | Anneau du disque (lecteur, mini-lecteur, bande desktop), bord en vague, téléchargements |
| Toolbar flottante | Mini-lecteur (+ FAB ⏯), sélecteur Lecteur · Paroles · File, sélection multiple |
| FAB | ⏯ du mini-lecteur (devient le loading indicator pendant un chargement) |
| Chips | Filtres de recherche et de bibliothèque |
| Listes en groupes arrondis | Réglages |
| Snackbar, dialogues, badges, switch, tirer pour rafraîchir | Où l'usage M3 les place |
| Squelettes | Toute zone qui charge ; même taille que le contenu final |

### 5.5 Le lecteur : un seul widget `NowPlaying`, trois tailles

Le même widget sert partout. Seules la taille et la mise en page changent :

| Taille | Où |
|---|---|
| **compact** | mini-lecteur mobile (5.3), bande desktop (4.2), en-tête des vues Paroles et File |
| **moyen** | panneau desktop |
| **grand** | lecteur plein écran mobile, vue immersive desktop |

**Les blocs, toujours dans cet ordre :**

1. En-tête : ⌄ ou replier · « Lecture depuis … » · sortie audio · ⤢ (desktop) · ⋮.
2. La pochette, selon le style choisi (ci-dessous).
3. Le titre (Google Sans arrondie) et les artistes.
4. Le groupe connecté Like / Ajouter à une playlist / Télécharger.
5. La progression (ci-dessous) et les temps.
6. Le groupe de contrôles : aléatoire · ⏮ · ⏯ · ⏭ · répétition.
   - C'est un button group M3E : les largeurs morphent à l'appui.
   - ⏯ morphe et devient le loading indicator pendant un chargement.
7. Le **sélecteur Lecteur · Paroles · File**, une toolbar flottante en bas.
   - L'onglet actif s'élargit et affiche son libellé.
   - Sur desktop, le volume se place juste au-dessus.

**Les trois vues** du sélecteur partagent le même cadre :

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
  - Les temps sont sous l'anneau.
- **Vague.** La pochette est en pleine largeur, et son **bord bas est une onde** qui ondule
  pendant la lecture et s'aplatit en pause.
  - La partie déjà jouée de l'onde est tracée en `primary` : **le bord est la progression**.
    On glisse le long du bord pour avancer, avec la même sémantique de slider.
  - L'onde rogne le bas de l'image d'environ 10 px.
  - Les temps sont sous le titre.

Dans les deux styles, le mini-lecteur, la bande desktop et l'en-tête compact gardent la pochette
du disque. Avec « réduire les animations », il n'y a ni rotation ni ondulation : la forme et
l'onde restent statiques.

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
    Chaque tuile a une teinte pastel fixe tirée de l'identifiant de la catégorie, et l'image de
    la catégorie inclinée dans le coin. Pas d'extraction.
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
  - **Likés** ;
  - **Téléchargés** ;
  - **Top 50** : tes 50 titres les plus écoutés. On compte les écoutes d'au moins 30 s sur
    90 jours. Si cela donne moins de 50 titres, on complète sur tout l'historique. Ordre fixe ;
  - **Historique** : groupé par jour.
- **Puces** Playlists / Albums / Artistes, puis la liste.
- **FAB menu** : nouvelle playlist, importer un lien.
- **Tri** (bottom sheet sur mobile, menu sur desktop ; choix retenu par liste) :
  - collections (playlists, albums, artistes) : Récents (défaut, date d'ajout ou de like),
    Dernière écoute, Nom A→Z ;
  - listes de titres (Likés, Téléchargés) : Date d'ajout (défaut), Titre, Artiste.
- Le tri se fait dans le cœur, parce que les listes sont paginées (7.3).

### 6.4 Album / playlist

- La pochette en grand, en forme expressive, fondue dans la surface du thème (pas de teinte
  propre, 2.2).
- Titre, artistes, année et durée.
- Split button « Lire | ▾ », like et télécharger en boutons tonaux.
- Lignes de titre (numérotées pour un album).
- Au défilement, l'en-tête se replie et un FAB lecture reste.
- Playlist perso : réordonner par glisser, et sélection multiple avec toolbar flottante.

### 6.5 Artiste

Photo en grand fondue dans la surface, bouton Radio (la radio remplace la file), titres
populaires, albums en carousel multi-browse.

### 6.6 Lecteur plein écran (mobile)

`NowPlaying` en grande taille (5.5), sur le fond teinté du thème.

- On l'ouvre depuis le mini-lecteur (↑ ou toucher).
- On le ferme avec ⌄ ou en glissant vers le bas.
- La sortie audio ouvre le sélecteur du système.
- File et Paroles sont des vues du lecteur, pas des feuilles.

### 6.7 Réglages, premier lancement, sources, téléchargements

- **Réglages** : listes M3E en groupes arrondis.
  - Apparence : source de couleur, noir pur, thème, style du lecteur (Disque / Vague).
  - Lecture : radio de fin de file, normalisation.
  - Téléchargements.
  - Sources : dépôts, ordre des plugins.
  - Confidentialité : télémétrie, découvertes à partir de l'écoute.
  - À propos : mises à jour, diagnostics, rapport de bug.

  Pour une vérification forcée des mises à jour : `Ok(None)` affiche « à jour » ; une mise à
  jour disponible n'apparaît que par la notice.
- **Premier lancement** : loading indicator M3E, étapes, puis le choix de télémétrie sans option
  présélectionnée (socle §4.6).
- **Dépôts et plugins**, **Téléchargements** : sections globales, ouvertes depuis le rail.

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
  - les artistes du top sur 90 jours ;
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
| `top_tracks() -> Vec<TrackView>` | Top 50 (6.3) |
| `history(offset, limit) -> Vec<HistoryEntryView { played_at, track }>` | L'historique groupé par jour a besoin de l'heure |

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
- **Revue** :
  - aucun import de `package:flutter/material.dart`, ni de `material_3_expressive` hors de
    `design/` ;
  - aucun nombre d'espacement hors des tokens ;
  - aucun écran ni coque qui recrée une des six briques de la règle de réutilisation (§5).

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

  Les Tasks 2 à 4 ne changent pas.

## 11. Hors de cette spec

- Partage, synchronisation et comptes : socle §11.
- `browse` pour YouTube Music (humeurs et genres). C'est possible plus tard, en ajoutant
  l'export au plugin, sans toucher au cœur.
- Le design de l'anime et du manga : leurs specs. Le rail et la barre du bas sont déjà prêts à
  les accueillir.
