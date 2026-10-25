# Vehicoule — Navigation entre domaines : addendum

Date : 2026-10-25 · Statut : en relecture (v1)

Specs parentes : `2026-10-18-socle-musique-design.md` (le « socle ») et
`2026-10-23-socle-ui-design.md` (la « spec UI », branche `socle`). Cet addendum fixe comment
l'app accueille ses trois domaines — musique, anime, livres (ebooks et mangas) — **avant** que
la Task 5 du plan 5 (routes et coques) ne fige une navigation propre à la musique. La v1 ne
livre que la musique : presque tout ici est invisible en v1, mais les routes, la place des
Réglages et la structure des coques doivent déjà être celles de l'état final.

Noms internes des domaines : `music`, `anime`, `books` (comme les paquets WIT
`vehicoule:music`, `vehicoule:anime`, `vehicoule:books`). Le libellé visible du domaine
`books` (« Manga », « Livres »…) est fixé par sa spec.

## 1. Décisions

| Sujet | Décision |
|---|---|
| Modèle | **Accueil commun + sélecteur de domaine** : l'Accueil est le même pour tous les domaines ; les autres destinations sont celles du domaine courant |
| Accueil | « Reprendre » (une carte par domaine en cours) puis un **fil mixte** alimenté par chaque domaine, filtrable par puces Tout · Musique · Anime · Livres |
| Domaine courant | **Déduit de la route** ; il suit le contenu ouvert. Le ☰ (mobile) et le bas du rail (desktop) le changent exprès |
| Réglages, Sources, Téléchargements | **Globaux**, hors de la barre de navigation, rangés par domaine à l'intérieur |
| Bibliothèque, Explorer / Parcourir | **Par domaine** : leurs modèles diffèrent trop pour être unifiés |
| Recherche | Dans le domaine courant ; « Dans ta bibliothèque » couvre tous les domaines |
| Lecture | **Deux sessions indépendantes** : musique (audio) et vidéo, qui jouent en parallèle |
| Vidéo hors plein écran | **Fenêtre vidéo flottante vivante** dans l'app (façon YouTube), PiP système hors de l'app |
| Thème « ce qui joue » | La graine reste la musique en cours ; la vidéo ne change pas la couleur |

## 2. Navigation

### 2.1 Barre, rail et domaines

- **Destinations** = **Accueil**, toujours en premier, puis celles du domaine courant :

  | Domaine | Destinations après Accueil |
  |---|---|
  | Musique | Explorer · Bibliothèque |
  | Anime | fixées par sa spec (modèle Aniyomi : Bibliothèque · Nouveautés · Historique · Parcourir) |
  | Livres | fixées par sa spec |

  Une barre M3 porte de 3 à 5 destinations : Accueil + 4 au plus par domaine.
- **Réglages quitte la barre du bas** (spec UI §4.1 et §1 : « Accueil / Explorer / Bibliothèque
  / Réglages » devient « Accueil / Explorer / Bibliothèque »). Il rejoint Sources et
  Téléchargements parmi les sections globales.
- **☰ (mobile)** ouvre le rail déplié en modal :
  1. les domaines (Musique, puis Anime et Livres quand ils existent) ;
  2. les sections globales : Téléchargements, Sources, Réglages.
- **Desktop** : le rail montre Accueil et les destinations du domaine, puis les épinglés **du
  domaine courant** ; en bas, le choix du domaine, puis les sections globales. ⌘, ouvre
  toujours les Réglages.
- Changer de domaine ouvre la **dernière destination visitée** de ce domaine (sa première au
  premier passage). L'Accueil ne change pas.
- **Glisser la barre du bas** horizontalement fait passer au domaine voisin ; les
  destinations morphent (ressort M3E, fondu avec « réduire les animations »). Astuce affichée
  une fois (spec UI §5.7). Le ☰ reste l'équivalent accessible. Inactif avec un seul domaine.
- Le dernier domaine est retenu (`ui.domain`) : l'app rouvre dessus.

### 2.2 Le domaine suit le contenu

Le domaine courant n'est **pas un état à part** : il se lit dans la route (§3).

- Ouvrir un épisode depuis l'Accueil, depuis « Dans ta bibliothèque » ou par un lien passe le
  domaine courant à Anime : la barre montre les destinations anime, l'Accueil reste
  sélectionné.
- Sur l'Accueil seul ou une section globale, le domaine courant est `ui.domain`.
- Chaque changement de domaine réécrit `ui.domain`.

### 2.3 Ce qui est commun, ce qui est par domaine

| Surface | Portée | Détail |
|---|---|---|
| Accueil | commun | §4 |
| Explorer / Parcourir, Bibliothèque, Historique | par domaine | modèles propres à chaque domaine |
| Recherche (barre de titre desktop, search bar mobile) | domaine courant | résultats des sources du domaine ; suggestions « Dans ta bibliothèque » sur tous les domaines, avec l'icône du type |
| Épinglés du rail | par domaine | `ui.pinned.<domaine>` |
| Téléchargements | global | une page, une section par domaine, une seule barre de stockage |
| Sources | global | rangées par origine (spec UI §6.7) ; une ligne dit ce que la source ajoute, domaines compris |
| Réglages | global | sections générales, puis une section par domaine (Lecture musique, Lecteur vidéo, Lecteur de livres) |

## 3. Routes

Un seul `StatefulShellRoute.indexedStack`. Ses branches : **l'Accueil, puis chaque
destination de chaque domaine**. La coque n'affiche que l'Accueil et les branches du domaine
courant ; les autres gardent leur pile, si bien qu'on retrouve sa page anime en revenant.

| Route | Rôle |
|---|---|
| `/home` | branche Accueil |
| `/music/explore`, `/music/library` (+ `/music/library/liked`, `/downloaded`, `/top`, `/history`) | branches musique |
| `/music/explore/album/:id`, `/music/library/artist/:id`… | une page ouverte dans la branche d'où elle vient (règle actuelle d'`openItem`, préfixée par le domaine) |
| `/home/music/album/:id`, `/home/anime/series/:id`… | une page ouverte depuis l'Accueil : la branche Accueil reste sélectionnée, le domaine vient du segment après `/home` |
| `/anime/…`, `/books/…` | réservées, remplies par leurs specs |
| `/watch/:id`, `/read/:id` | lecteur vidéo et lecteur de livres, globaux, au-dessus des coques |
| `/downloads`, `/sources`, `/settings`, `/settings/appearance`, `/settings/diagnostics` | sections globales (`/settings/sources` devient `/sources`) |
| `/onboarding`, `/debug/gallery` | inchangées |

Règle : **`domainOf(location)`** est la seule fonction qui lit le domaine courant :
`/<domaine>/…` ou `/home/<domaine>/…`, sinon `ui.domain`.

**Liens collés** : un lien Deezer, YouTube Music, AniList, MyAnimeList ou d'une source, collé
dans la recherche ou partagé vers l'app, ouvre la bonne page dans le bon domaine. Chaque
domaine déclare les hôtes qu'il reconnaît ; le concentrateur de liens existant (`links()`)
les route. Les liens `vehicoule://` ne changent pas.

## 4. Accueil commun

1. **« Bonsoir »** (spec UI §6.1), puis les **puces** Tout · Musique · Anime · Livres. Le
   choix est retenu (`ui.home_filter`). Les puces sont masquées tant qu'un seul domaine
   existe.
2. **Reprendre** : une carte par domaine en cours — la file musique sauvegardée, l'épisode
   suivant, le chapitre suivant. La carte porte la forme du domaine (§8).
   - **Ordre appris** : les cartes sont triées selon ce que *tu* fais d'habitude à cette
     heure-ci et ce jour-là (l'anime le soir, la musique le matin), calculé en local sur
     `plays`. Rien ne sort de l'appareil.
3. **Le fil mixte** : chaque domaine fournit ses étagères au module `home` du cœur (la
   musique : celles de la spec UI §6.1 ; l'anime : nouveaux épisodes de ta bibliothèque,
   etc.). Le cœur les entrelace en alternant les domaines ; le filtre n'en garde qu'un.
   Fin honnête, cache et hors ligne : inchangés (spec UI §7.2).
4. **Un seul résumé par jour** pour les nouveautés : « 3 nouveaux épisodes, 2 chapitres,
   1 sortie de tes artistes ». Le toucher ouvre l'Accueil. Un domaine peut passer en
   notification immédiate dans ses réglages.

En v1, seule la musique alimente l'Accueil : il est exactement celui de la spec UI §6.1, plus
la carte Reprendre de la file musique.

## 5. Lecture

### 5.1 Deux sessions

- **Musique** : la session actuelle (file, `PlayerAdapter`, `audio_service`), inchangée. Le
  mini-lecteur, le panneau et la bande desktop, `VNowPlaying` restent **purement musique**.
- **Vidéo** : un second lecteur `media_kit`, avec son état propre, posé par la spec anime.
- **Les deux jouent ensemble.** Lancer un épisode ne touche pas à la musique. Le lecteur
  vidéo a son volume propre et, dans son en-tête, une commande **Musique** (titre + ⏯) pour
  couper l'un ou l'autre d'un toucher. Lire un livre ne joue rien : la musique continue.
- **Session système** (écran verrouillé, notification, Now Playing macOS) : le système n'en
  montre qu'une. Elle suit **le dernier média démarré** ; l'autre reste pilotable dans l'app.
  La faisabilité sur Android (deux `MediaSession`, PiP) est un point du spike de la spec
  anime.
- **Minuterie de sommeil commune** : la minuterie (plan 7) arrête **toutes** les sessions,
  avec le même fondu.

### 5.2 La fenêtre vidéo flottante

- Plein écran : `/watch/:id`. Le quitter (retour, ⌄, Échap sur desktop) **réduit la vidéo en
  fenêtre flottante vivante** dans l'app.
- On la déplace d'un coin à l'autre (aimantation, ressort) ; un toucher l'agrandit ; un
  glisser hors de l'écran la ferme et met en pause.
- **Arrimage** : quand la musique joue aussi, la fenêtre se pose juste au-dessus de la
  toolbar du mini-lecteur et forme avec elle **un seul bloc** qui se déplace ensemble. Jamais
  deux objets flottants qui se chevauchent.
- Couche : au-dessus du contenu et du mini-lecteur, sous les feuilles, les dialogues et les
  snackbars.
- **Même widget sur mobile et desktop.** Sur desktop, `/watch` occupe toute la fenêtre comme
  l'immersif ; le panneau de droite reste celui de la musique.
- Hors de l'app : PiP système Android.

### 5.3 Raccourcis

Les raccourcis desktop (spec UI §4.2) visent **la vidéo** quand elle est en plein écran ou que
sa fenêtre a le focus, **la musique** sinon. Une seule fonction choisit la session visée.

## 6. Relations entre domaines

Ce qui justifie le 3-en-1 : les domaines se parlent.

- **Table `item_relations`** (item → item, type, source), avec les colonnes de synchro du
  socle §5.3. Types : `theme-song` (anime → titre : OP / ED), `adaptation` (anime ↔ livre),
  `continues-at` (anime → chapitre : « le manga continue au chapitre 87 »), `soundtrack`
  (série → playlist).
- Sources des relations : données ouvertes (AnimeThemes pour les génériques, relations
  AniList), via des capacités des plugins, décrites dans la spec anime.
- **Une page anime** montre ses génériques : un toucher les lit ou les like dans ta musique.
  Elle montre aussi « Adapté de ce manga » et « Le manga continue après l'épisode 24 ».
- **Une playlist attachée à une série** (`soundtrack`) : tu associes une playlist, ou les
  génériques, à un anime ou un manga. À l'ouverture du lecteur de livres, une puce propose
  « Reprendre la bande-son ».

## 7. Hors ligne et hors de l'app

- **Budget de stockage unique** pour tous les domaines (Réglages › Téléchargements). Au-delà,
  les plus anciens éléments déjà vus ou lus partent en premier.
- **« Pour le trajet »** : en Wi-Fi et en charge, l'app télécharge les N prochains épisodes et
  chapitres de ce que tu suis, plus ta découverte du jour. Réglable par domaine.
- **Raccourcis Reprendre** : l'appui long sur l'icône (raccourcis Android, menu du Dock macOS)
  et le widget Android 4×2 proposent les cartes Reprendre (« Épisode 8 de X », « Ta file
  musique »).

## 8. Identité par domaine

Chaque domaine a **une forme de décor fixe** (spec UI §2.3), utilisée pour son icône dans le
rail, ses états vides et ses cartes Reprendre : **cookie** pour la musique, **pilule 16:9**
pour l'anime, **arche** (une page) pour les livres. On reconnaît le domaine d'une carte du fil
mixte sans lire. La couleur reste unique (spec UI §2.2).

## 9. Desktop : palette ⌘K

Une palette de commandes qui cherche dans **tous** les domaines (bibliothèque locale) et lance
des actions : « Radio de ce titre », « Aller à Téléchargements », « Épisode suivant »,
« Changer de domaine ». La recherche de la barre de titre reste celle du domaine courant.
Livrée dès la v1 musique (bibliothèque et actions de la musique) ; chaque domaine y ajoute
ses entrées.

## 9 bis. « Ton année »

Un bilan local de toutes les activités, calculé sur `plays` et jamais envoyé : minutes
d'écoute, artistes et titres en tête, puis épisodes vus et chapitres lus quand ces domaines
existent, et les croisements (l'OP le plus écouté de l'anime le plus regardé). Page globale
`/recap/:year`, ouverte par une carte de l'Accueil en décembre et à tout moment depuis
l'Historique. Livré dès la v1 musique ; chaque domaine y ajoute ses chiffres.

## 10. Ce que l'addendum change dans les specs existantes

| Spec | Devient |
|---|---|
| UI §1, §4.1 : barre « Accueil / Explorer / Bibliothèque / Réglages » | « Accueil / Explorer / Bibliothèque » ; Réglages dans le ☰ et le rail, avec Sources et Téléchargements |
| UI §4.2 : rail « les quatre destinations », épinglés globaux | Accueil + destinations du domaine, épinglés du domaine (`ui.pinned.music`), puis domaine et sections globales en bas |
| UI §6.7 : `/settings/sources` | `/sources` |
| UI §7.2, §7.3 : fil d'accueil musique | Module `home` commun : chaque étagère porte son domaine, nouvelle étagère `Resume`, filtre par domaine |
| Socle §5.1 : tables communes | + `item_relations` |
| UI §5.5 / plan 7 : minuterie de la file | Minuterie de l'app, qui vise toutes les sessions |

## 11. Contraintes pour la Task 5 du plan 5 (routes et coques)

À appliquer **avant le point de contrôle du shell** ; le reste de l'addendum arrive avec le
domaine anime.

1. **Routes** comme au §3 : `/home` ; `/music/explore`, `/music/library` et ses sous-routes ;
   pages d'entité sous `/<branche>/…` préfixées par le domaine (`/music/explore/album/:id`,
   `/home/music/album/:id`) ; `/downloads`, `/sources`, `/settings/…` globales. `openItem`
   construit ces chemins ; aucune route ne s'écrit en dur ailleurs.
2. **Réglages n'est plus une destination** : barre mobile à 3 (Accueil, Explorer,
   Bibliothèque) ; rail desktop idem. Réglages, Sources et Téléchargements forment les
   sections globales du ☰ modal et du bas du rail desktop. ⌘, ouvre `/settings`.
3. **`domainOf(location)`**, seule source du domaine courant (§3) ; `ui.domain` est écrit à
   chaque changement de domaine et lu au lancement.
4. **Branches** : Accueil + une branche par destination de domaine, déclarées depuis une
   seule liste de domaines (`music` en v1) ; la barre et le rail montrent Accueil +
   `destinationsOf(domainOf(location))`. Aucun index de branche écrit en dur dans les coques.
5. **Rail des domaines** (☰ et bas du rail desktop) construit depuis la même liste ; en v1 il
   ne contient que Musique.
6. **Épinglés** stockés en `ui.pinned.music`, pas `ui.pinned`.
7. **Couches des coques** : l'ordre de la pile laisse une place entre le mini-lecteur (ou la
   bande desktop) et les feuilles / dialogues / snackbars, pour la fenêtre vidéo de §5.2. Le
   rect de la toolbar du mini-lecteur est lisible depuis la coque (arrimage). Rien n'est
   dessiné dans cette couche en v1.
8. **Raccourcis** : `DesktopShortcuts` passe par une seule fonction qui renvoie la session
   visée ; en v1 elle renvoie toujours la musique.
9. **Accueil** : l'app bar de `/home` prévoit la rangée de puces sous le titre, masquée avec un
   seul domaine.
10. **Tests à ajouter** :

    ```dart
    testWidgets('settings is a global section, not a bar destination', ...);  // ☰ et rail : Téléchargements, Sources, Réglages
    testWidgets('the domain comes from the route', ...);                      // /music/explore → music ; /home/music/album/x → music ; /home → ui.domain
    testWidgets('an album opened from home stays in the home branch', ...);   // /home/music/album/:id, Accueil sélectionné
    testWidgets('pinned are stored per domain', ...);                         // ui.pinned.music
    ```

Ce qui **n'a rien à montrer avec un seul domaine** arrive avec la spec anime : le glisser de
la barre, les puces visibles, la fenêtre vidéo, l'ordre appris de Reprendre. Tout le reste
entre dans la v1 musique (§12).

## 12. Impact sur les autres plans

- **Plan 3 (bibliothèque)** : migration `item_relations` (§6), vide en v1.
- **Plan 7 (fil d'accueil)** : `ShelfView` gagne `domain` ; `ShelfKind::Resume` (en v1 : la
  file musique sauvegardée) ; `home_feed(cursor, filter: Option<Domain>)`. La minuterie
  devient une minuterie d'app (§5.1).
- **Plan 5, Task 10 (widget, barre des menus)** : le widget 4×2 sans lecture en cours affiche
  la carte Reprendre (déjà « Reprendre sur la dernière file ») ; les raccourcis d'icône
  Android et le menu du Dock reprennent les cartes Reprendre.
- **Plan 5, Tasks 6 et 7** : écrans sous `features/music/` inchangés ; Réglages, Sources et
  Téléchargements passent dans un dossier `features/app/` (global), parce qu'ils ne sont plus
  propres à la musique.
- **Ajouts à la v1 musique** (utiles avec la musique seule, donc pas repoussés) :
  - **⌘K** (§9) : coque desktop, plan 5 ;
  - **résumé quotidien** (§4) : en v1, les sorties de tes artistes (`browse.releases` du
    plan 7), en une notification par jour ;
  - **« Ton année »** (§9 bis) : agrégats dans le cœur (plan 7), page `/recap/:year`
    (plan 5) ;
  - **« Pour le trajet »** et **budget de stockage** (§7) : la découverte du jour téléchargée
    en Wi-Fi et en charge (plan 4, service de téléchargement) ;
  - **liens collés** (§3) : liens Deezer et YouTube Music ;
  - **M1** paroles romanisées et traduites, **M3** son par sortie audio (§13).

## 13. Idées propres à un domaine

| Idée | Où |
|---|---|
| **M1** Paroles romanisées (rōmaji calculés en local) et traduites ligne à ligne | v1 musique (révision de la spec UI, vue Paroles) |
| **M3** Égaliseur et normalisation retenus par sortie audio (casque, enceinte, voiture) | v1 musique (filtres libmpv, Réglages › Lecture) |
| Sauter le générique (AniSkip), avec la puce « Ajouter cet OP à ta musique » pendant le saut | spec anime |
| Double sous-titres (japonais + français), toucher un mot en pause le copie | spec anime |
| **M2** « Ton mix anime » : radio dont les graines sont les OP / ED des séries regardées | spec anime (étagère « Tes mixes ») |
| **B1** Sens de lecture déduit des métadonnées puis retenu par série | spec livres |
| **B2** Lecture case par case (détection des cases sur l'appareil) | spec livres |
| **B3** Mode liseuse : e-ink, sans animation, touches de volume, rafraîchissement complet | spec livres |
| Défilement webtoon automatique, mode « au tempo » de la musique en cours | spec livres |
