# Vehicoule — Domaine anime : design

Date : 2026-10-25 · Statut : en relecture (v2 : types de l'hôte 1.1, cookies et vérification par l'utilisateur, JS dans le plugin, focus audio)

Specs parentes : `2026-10-18-socle-musique-design.md` (le « socle »),
`2026-10-23-socle-ui-design.md` (la « spec UI », branche `socle`) et
`2026-10-25-navigation-domaines.md` (l'« addendum »). Cette spec branche l'anime sur le socle :
même cœur, même hôte de plugins, même bibliothèque, mêmes coques.

## 1. But et décisions

Regarder des séries comme dans Aniyomi — bibliothèque, nouveautés, épisodes, reprise exacte,
trackers — avec les garanties du socle : aucune source intégrée, plugins en composants WASM,
données de l'utilisateur indépendantes des fournisseurs.

| Sujet | Décision |
|---|---|
| Identité d'une série | **Un item Vehicoule**. Métadonnées d'un plugin de catalogue (AniList) ; une ou plusieurs sources de lecture rattachées par correspondance (§3.3) |
| Contrat | `vehicoule:anime@1.0.0` : `catalog`, `source`, `themes`, `skip` (§4) |
| Trackers | **Plugins** `vehicoule:tracker@1.0.0`, communs à l'anime et aux livres ; l'hôte fait l'OAuth et garde les jetons (§4.4) |
| Lecteur | Complet, sans accès brut à mpv : gestes, pistes, style des sous-titres, saut du générique, double sous-titres, Anime4K (§6) |
| Lecture | Seconde session, en parallèle de la musique ; fenêtre flottante vivante ; PiP système (addendum §5) |
| Téléchargements | HLS et fichiers directs, par la crate `stream` (§7) |
| Feed officiel | AniList (catalogue + tracker), MyAnimeList (tracker), AnimeThemes, AniSkip, trace.moe. **Aucune source de lecture** |
| Plateformes | Android + macOS, comme la musique |

### Critères de réussite

1. Une série suivie se regarde de bout en bout sur Android et macOS pendant deux semaines
   sans revenir à Aniyomi.
2. Moins de 3 s entre le toucher sur un épisode non préchargé et la première image, sur une
   connexion correcte.
3. La reprise tombe à ±2 s de la position quittée, y compris après un arrêt brutal de l'app.
4. 30 min d'audio d'épisode écran éteint sur Android sans coupure (réglage activé).
5. Plus de 95 % de bonnes correspondances catalogue ↔ source sur un corpus de 100 séries
   (§3.3).

## 2. Ce que le socle généralise

Chaque point est posé dans le socle, pas dans le domaine, parce que les livres en ont aussi
besoin.

| Socle | Généralisation |
|---|---|
| `items.kind` (§5.1) | + `anime`, `episode` (les livres ajoutent `book`, `chapter`) |
| Tables communes (§5.2) | + `library_entries`, `categories`, `progress`, `bookmarks`, `source_bindings` (§3) ; `item_relations` (addendum §6) |
| `vehicoule:host` | 1.1.0 : + `types`, `session` (cookies), `challenge`, `oauth`, filtres, `settings-schema` (§4.5) |
| SDK | + décompacteur, AES compatible CryptoJS, option `js` (Boa, moteur JS en Rust, compilé en WASM dans le composant) si le spike l'exige (§4.5) |
| Manifeste (§4.3) | + `adult: bool` ; Réglages › Sources « Afficher les sources pour adultes », désactivé par défaut |
| Crate `stream` (§3.4) | + HLS : variantes, segments avec reprise, AES-128, playlist locale réécrite, sous-titres à côté (§7) |
| Lecteur | + seconde session : `WatchState` dans le cœur, `VideoPlayerAdapter` côté Dart (§6.1) |
| Plateforme | + tâche périodique (mise à jour de la bibliothèque, §5.5), seconde `MediaSession` Android, PiP |
| Dépendances | `media_kit_libs_audio` → `media_kit_libs_video` pour toute l'app ; + `media_kit_video` |

## 3. Bibliothèque

### 3.1 Tables du domaine

- `anime_series` (clé = item) : titres (romaji, anglais, natif, synonymes), format (TV,
  film, OVA, ONA, spécial), saison, année, statut de diffusion, nombre d'épisodes prévu,
  studios, genres, synopsis, affiche et bannière, prochain épisode (numéro, date).
- `anime_episodes` (clé = item) : série, **numéro réel** (12.5 existe), titre, date de
  diffusion, durée, `filler`.
- `episode_sources` : épisode → plugin + id de l'épisode chez la source, groupe (fansub),
  langue (sous-titré, doublé).

### 3.2 Tables communes nouvelles

Toutes portent les colonnes de synchro du socle §5.3 (`updated_at` HLC, `device_id`,
`deleted_at`).

- `library_entries` : item suivi (série, et plus tard livre), date d'ajout, statut
  personnel (en cours, à voir, fini, en pause, abandonné).
- `categories` (par domaine, ordre fractionnaire) et `library_entry_categories`.
- `progress` : item (épisode, chapitre), position et durée (ms, ou page et nombre de pages),
  `completed_at`. Écrit toutes les ~10 s pendant la lecture et à chaque pause, comme
  `queue_state`.
- `bookmarks` : item, position, note facultative.
- `source_bindings` : série → plugin + id de la série chez la source, priorité, « fixé à la
  main ».

`plays` (socle) reçoit aussi les épisodes : l'historique, « Ton année » (addendum §9 bis) et
l'ordre appris de « Reprendre » (addendum §4) s'en servent sans table de plus.

### 3.3 Correspondance catalogue ↔ source

1. `source_bindings` déjà présent → l'utiliser.
2. Sinon, `source.search` avec les titres de la série, dans l'ordre romaji, anglais, natif,
   synonymes, jusqu'au premier résultat au-dessus du seuil.
3. Score : similarité des titres normalisés (casse, ponctuation, « Season 2 » ↔ « 2nd
   Season », « Part » / « Cour »), année ±1, format, nombre d'épisodes ±1. Pénalité pour
   « dub » si la langue préférée est la VOSTFR, et l'inverse.
4. Sous le seuil → la série affiche « Choisir une source », qui ouvre les candidats.
5. **Correction manuelle** : « Ce n'est pas la bonne série » liste les autres candidats, avec
   leur nombre d'épisodes et leur affiche ; le choix est fixé.
6. **Épisodes** : appariés par numéro réel ; un épisode de la source sans numéro du catalogue
   (récap, spécial) apparaît à part, sous « Hors série ».

Le corpus de 100 séries (titres ambigus, suites, films, saisons coupées en deux) vit avec le
premier plugin de source tiers et sert de test réel, comme celui de YouTube Music.

### 3.4 Plusieurs sources pour une série

Une série peut avoir plusieurs sources (priorité dans `source_bindings`). Un épisode absent
de la première est cherché dans la suivante. « Changer de source » sur la page série
réordonne ; la progression, les catégories et le tracker ne bougent pas, parce qu'ils
pointent vers les items.

## 4. Contrat

### 4.1 `vehicoule:anime@1.0.0`

Les `record` de la 1.0 sont figés avec soin (socle §4.3 : un champ de plus = version
majeure).

```wit
package vehicoule:anime@1.0.0;

interface types {
    use vehicoule:host/types.{error, image};

    enum format { tv, movie, ova, ona, special, music }
    enum airing { airing, finished, upcoming, cancelled, hiatus }
    enum season { winter, spring, summer, fall }
    enum segment-kind { opening, ending, recap, preview }
    record segment { kind: segment-kind, start-ms: u32, end-ms: u32 }
    record titles { romaji: option<string>, english: option<string>, native: option<string>, synonyms: list<string> }
    record series-ref { provider: string, id: string }
    record series {
        ref: series-ref,
        /// Other catalogue ids known for this series (anilist, mal, kitsu…).
        external: list<series-ref>,
        titles: titles,
        format: option<format>,
        airing: option<airing>,
        season: option<season>,
        year: option<u16>,
        episodes: option<u32>,
        /// Average score, 0 to 100.
        score: option<u8>,
        genres: list<string>,
        studios: list<string>,
        synopsis: option<string>,
        poster: list<image>,
        banner: list<image>,
        adult: bool,
    }
    record episode {
        id: string,
        /// Real number: 12.5 exists.
        number: f32,
        title: option<string>,
        /// ISO 8601 date, `YYYY-MM-DD`.
        aired: option<string>,
        duration-s: option<u32>,
        /// 16:9 still, for the episode row.
        thumbnail: list<image>,
        filler: bool,
        group: option<string>,
        /// BCP 47 tags of the audio, then of hard subtitles.
        audio-lang: option<string>,
        hardsub-lang: option<string>,
    }
}

interface catalog {
    use types.{series, series-ref, episode};
    use vehicoule:host/types.{error};

    enum relation-kind { prequel, sequel, side-story, adaptation, source, alternative, spin-off }
    record relation { kind: relation-kind, target: series-ref, domain: string }
    record airing-next { episode: f32, at-unix: s64 }

    search: func(query: string, page: u32) -> result<list<series>, error>;
    fetch: func(ref: series-ref) -> result<series, error>;
    episodes: func(ref: series-ref) -> result<list<episode>, error>;
    relations: func(ref: series-ref) -> result<list<relation>, error>;
    /// Next airing episodes for many series at once (smart library update, §5.5).
    schedule: func(refs: list<series-ref>) -> result<list<tuple<series-ref, airing-next>>, error>;
}

interface source {
    use types.{series, episode, segment};
    use vehicoule:host/types.{error};
    use vehicoule:host/filters.{filter-schema, filter-value};

    enum stream-format { hls, file }
    enum sub-format { ass, srt, vtt }
    record subtitle { url: string, lang: string, label: option<string>, format: sub-format, headers: list<tuple<string, string>> }
    record audio-track { url: string, lang: string, label: option<string> }
    record video {
        url: string,
        headers: list<tuple<string, string>>,
        format: stream-format,
        /// Vertical resolution, 1080 for 1080p.
        height: option<u32>,
        label: option<string>,
        audio: list<audio-track>,
        subtitles: list<subtitle>,
        /// Skip timings some hosters ship with the video; preferred over `skip`.
        segments: list<segment>,
        expires-unix: option<s64>,
    }
    record page { items: list<series>, has-next: bool }

    popular: func(page: u32) -> result<page, error>;
    latest: func(page: u32) -> result<page, error>;
    filters: func() -> result<filter-schema, error>;
    search: func(query: string, filters: list<filter-value>, page: u32) -> result<page, error>;
    fetch: func(id: string) -> result<series, error>;
    episodes: func(series-id: string) -> result<list<episode>, error>;
    /// Every playable variant of one episode, best first. Called again on `expired`.
    videos: func(episode-id: string) -> result<list<video>, error>;
}

interface themes {
    use types.{series-ref};
    use vehicoule:host/types.{error};

    enum theme-kind { opening, ending, insert }
    record theme {
        kind: theme-kind,
        number: u32,
        title: string,
        artists: list<string>,
        /// Episode range this theme plays on, `[first, last]`.
        episodes: option<tuple<f32, f32>>,
    }
    themes: func(ref: series-ref) -> result<list<theme>, error>;
}

interface skip {
    use types.{series-ref, segment};
    use vehicoule:host/types.{error};

    /// `duration-ms` lets the provider pick the right timing for this release.
    segments: func(ref: series-ref, episode: f32, duration-ms: u32) -> result<list<segment>, error>;
}

interface identify {
    use types.{series-ref};
    use vehicoule:host/types.{error};

    record sighting {
        series: series-ref,
        episode: option<f32>,
        at-ms: option<u32>,
        /// 0 to 100.
        confidence: u8,
    }
    /// A screenshot (PNG or JPEG bytes), best match first.
    identify: func(image: list<u8>) -> result<list<sighting>, error>;
}
```

- Un film est une série de format `movie` à un seul épisode : même page, même lecteur, même
  progression.
- `catalog` : plugin AniList (GraphQL public). `external` porte l'id MyAnimeList, dont
  AniSkip et les trackers ont besoin.
- `source` : plugins tiers uniquement, publiés dans leurs propres feeds (socle §4.4).
- `themes` : plugin AnimeThemes. Le cœur cherche chaque thème dans le catalogue musique
  (« titre artiste ») et crée une relation `theme-song` (addendum §6) ; le titre se lit et se
  like comme n'importe quel titre.
- `skip` : plugin AniSkip.
- `identify` : plugin trace.moe, sans clé, dans son quota gratuit (« C'est quoi ? », mode Montrer, addendum §6 bis).
- Routage : liste de priorité par capacité, comme le socle §4.7.
- **Source la plus fiable d'abord** : le cœur note chaque source en local, par série (taux de
  réussite de `videos`, temps jusqu'à la première image, hauteur obtenue, sur les 30 derniers
  essais). Pour chaque épisode, il essaie les sources dans l'ordre de cette note ; un ordre
  fixé à la main dans `source_bindings` passe avant. Une source qui se dégrade descend seule.

### 4.2 Capacités et erreurs

Les erreurs sont celles du socle §6. `expired` sur une vidéo → un seul nouvel appel à
`videos`, reprise à la même position. Une variante qui échoue → la suivante, puis la source
suivante de `source_bindings`.

### 4.3 Sécurité réseau des sources

Les règles du socle §4.3 s'appliquent sans exception : domaines déclarés (vérifiés à chaque
redirection et pour chaque URL de vidéo, de sous-titre et de segment), IP privées refusées.
Les URLs de segments HLS passent par la même vérification dans `stream` et sont refusées hors
des domaines déclarés par le plugin qui a fourni la vidéo.

### 4.4 `vehicoule:tracker@1.0.0`

```wit
package vehicoule:tracker@1.0.0;

interface tracker {
    use vehicoule:host/types.{error};

    enum media { anime, book }
    enum status { current, planning, completed, paused, dropped, repeating }
    record auth-config { authorize-url: string, token-url: string, client-id: string, scopes: list<string> }
    record entry-ref { id: string }
    record entry {
        ref: entry-ref,
        media: media,
        title: string,
        status: option<status>,
        /// Episodes seen, or chapters read.
        progress: u32,
        /// 0 to 100; the plugin converts to its own scale.
        score: option<u8>,
        /// ISO 8601 dates, `YYYY-MM-DD`.
        started: option<string>,
        finished: option<string>,
    }

    auth-config: func() -> auth-config;
    search: func(media: media, query: string) -> result<list<entry>, error>;
    /// By catalogue id when the tracker knows it (anilist:21, mal:21).
    find: func(media: media, catalogue: string, id: string) -> result<option<entry>, error>;
    get: func(ref: entry-ref) -> result<entry, error>;
    update: func(entry: entry) -> result<entry, error>;
    /// The whole user list, for the first import.
    list: func(media: media, cursor: option<string>) -> result<tuple<list<entry>, option<string>>, error>;
}
```

- **Liaison** : au premier ajout d'une série à la bibliothèque, le cœur appelle `find` avec
  les ids de `series.external` ; sans résultat, la page série propose « Lier le tracker »
  (recherche).
- **Mise à jour** : à chaque épisode marqué vu, `update` avec la nouvelle progression ; le
  statut passe à `completed` au dernier épisode. Hors ligne, les mises à jour attendent dans
  une file et partent au retour du réseau, la plus récente seulement.
- **Import** : « Importer depuis AniList » lit `list`, rattache chaque entrée au catalogue et
  remplit `library_entries` et `progress` (épisodes vus jusqu'à `progress`).
- **Conflit** : la progression la plus haute gagne, sauf statut `repeating`.

### 4.5 Ajouts mineurs à `vehicoule:host` (1.1.0)

Ajouter une interface est une version mineure (socle §4.3) ; aucun `record` de la 1.0 ne
change. Les plugins musique 1.0 restent chargés tels quels.

- **`types`** (nouvelle interface) : `error` (les variantes du socle §6) et `image`, communs à
  l'anime, aux trackers et aux livres. `vehicoule:music` garde ses propres types, qu'on ne
  peut pas déplacer sans version majeure.
- **`session`** : un `send` qui passe par une **boîte à cookies par plugin**, gardée par
  l'hôte, avec un User-Agent stable par appareil. `http.send` (1.0) reste sans cookies.
- **`challenge`** : quand une source renvoie `provider-wall` avec une URL, l'app propose « Ouvrir
  la page » : une WebView dans une feuille, où **l'utilisateur passe lui-même** la
  vérification du site. Les cookies obtenus rejoignent la boîte du plugin, et le User-Agent
  de `session` est celui de la WebView. L'app ne résout jamais une vérification à la place de
  l'utilisateur. WebView durcie : `2026-10-25-surface-attaque.md` §4. Aniyomi a le même besoin (sites derrière une protection anti-robots) ; sans
  ça, une grande partie des sources est inutilisable.
- **Pas d'interface `js` dans l'hôte.** Beaucoup d'hébergeurs vidéo cachent l'URL derrière du
  JavaScript obscurci, mais ce JavaScript reste **dans le bac à sable du plugin** :
  - le **SDK** fournit en Rust ce qui couvre la plupart des cas, sans moteur JS : le
    décompacteur « p,a,c,k,e,d » (Aniyomi fait de même en Kotlin), le déchiffrement AES
    compatible CryptoJS, les variantes de base64 ;
  - **aucun moteur JS écrit en C**, ni dans l'hôte ni dans les plugins : QuickJS accumule les
    failles de corruption mémoire (CVE-2026-0821, CVSS 9.8 ; CVE-2026-0822, exploit public),
    et V8 en est à sa sixième faille exploitée de 2026 ;
  - si le spike (§10.1) montre qu'un hébergeur exige un vrai moteur JS, l'option `js` du SDK
    embarque **Boa** (moteur JS écrit en Rust) compilé en WASM dans le composant, avec les
    budgets du plugin, sans réseau ni fichiers.

  **Changement du socle §4.5** (plan B YouTube) : l'interface hôte `js` passe de QuickJS
  natif à **Boa natif** (Rust), pour la même raison.
- **`oauth`** (import) : `begin(plugin)` déclenche le flux PKCE de `auth-config` dans le
  navigateur du système, retour par `vehicoule://oauth/<plugin>`. L'hôte garde les jetons
  dans le trousseau du système (Keystore Android, Keychain macOS) et les rafraîchit.
  `send-authorized(request)` envoie une requête avec `Authorization` ajouté par l'hôte : **le
  plugin ne voit jamais le jeton**. « Se déconnecter » efface les jetons.
- **`filters`** (types) : `filter-schema` (texte, choix unique, choix multiple, tri, case à
  trois états, groupe) et `filter-value`. Communs à l'anime et aux livres. L'UI les dessine
  avec les chips et les feuilles de `design/`.
- **`settings-schema`** (export facultatif de tout plugin) : les préférences d'une source
  (miroir, qualité, langue) décrites avec les mêmes types que les filtres. Valeurs gardées
  par l'hôte, lues par le plugin dans son `kv`. Écran : Sources › une source › Réglages.

## 5. Écrans

### 5.1 Destinations

Accueil (commun, addendum §4) · **Bibliothèque** · **Nouveautés** · **Historique** ·
**Parcourir**. Routes sous `/anime/…` (addendum §3).

- **Bibliothèque** (`/anime/library`) : grille d'affiches 2:3, une page par catégorie (onglets
  défilants), pastille « non vus » en haut à droite de l'affiche. Filtres (non vus,
  téléchargés, statut, tracker), tri (dernier vu, ajout, alphabétique, prochain épisode).
  Desktop : 4 à 8 colonnes, survol ▶ « Reprendre ».
- **Nouveautés** (`/anime/updates`) : bascule **Sortis · À venir**.
  - Sortis : épisodes sortis dans la bibliothèque, groupés par jour, en lignes d'épisode
    (§5.3). Tirer pour rafraîchir lance la mise à jour.
  - À venir : le **calendrier** des sept prochains jours des séries suivies
    (`catalog.schedule`), heure dans le fuseau de l'appareil.
- **Anti-spoiler** (réglage, désactivé par défaut) : titres et vignettes des épisodes non vus
  masqués partout (« Épisode 9 », vignette floutée). Le flou est le seul de l'app, fourni par
  `design/` (spec UI §2.8).
- **Historique** (`/anime/history`) : dernier épisode vu par série, groupé par jour ; ✕ retire
  la série de l'historique, avec Annuler.
- **Parcourir** (`/anime/browse`) : la search bar (catalogue AniList d'abord, puis « Chercher
  dans les sources »), les sources installées ; une source ouvre Populaires · Récents et ses
  filtres. Un résultat d'une source ouvre la page série après correspondance (§3.3).

### 5.2 Page série

- Affiche fondue dans la surface (spec UI §2.2, pas d'extraction), titre, format, année,
  studios, statut de diffusion et « Épisode 8 dans 2 jours ».
- Split button principal : « Reprendre l'épisode N » | ▾ (depuis le début, marquer comme
  vu, télécharger les N suivants). « Ajouter à la bibliothèque » en bouton tonal, avec le
  choix des catégories.
- Synopsis replié à 3 lignes.
- **Liste des épisodes** : lignes d'épisode (§5.3), ordre croissant ou décroissant retenu par
  série, filtres (non vus, téléchargés, favoris), sélection multiple avec la toolbar
  flottante (vu / non vu, télécharger, supprimer, favori). « Vu jusqu'ici » par appui long.
- **Génériques** : étagère des OP et ED (titres de la musique) ; toucher lit dans la session
  musique, ♥ like.
- **Liens** : adaptations et suites (relations du catalogue, addendum §6), « Le manga
  continue au chapitre 87 » quand le domaine livres existe et que la relation est connue.
- **Tracker** : la ligne du tracker lié, statut et note modifiables.
- ⋮ : changer de source, « Ce n'est pas la bonne série », partager (addendum §3.1),
  attacher une bande-son (addendum §6).

### 5.3 Ligne d'épisode (une seule, partout)

Comme la ligne de titre (spec UI §5.1), dans `design/` : vignette 16:9 (ou numéro), titre
« 8 · Le titre », date et groupe en dessous, barre de progression fine sous la vignette si
l'épisode est commencé, opacité 38 % une fois vu, icône de téléchargement à droite (flèche →
anneau ondulé → coche). Toucher = regarder ; glisser à droite = vu / non vu ; appui long =
menu expressif.

### 5.4 Accueil commun

Le domaine fournit au module `home` (addendum §4) : la carte Reprendre (prochain épisode non
vu de la dernière série regardée), « Nouveaux épisodes » (bibliothèque), « Bientôt »
(calendrier des séries suivies), « Tes mixes » gagne **« Ton mix anime »** (radio de la
musique sur les génériques des séries regardées).

### 5.5 Mise à jour de la bibliothèque

- Tâche périodique : 12 h, 24 h (défaut) ou chaque semaine ; Wi-Fi seulement en option.
  Android : `WorkManager` (paquet `workmanager`) qui démarre le cœur sans UI ; macOS : à
  l'ouverture et toutes les 24 h tant que l'app tourne.
- **Mise à jour intelligente** : `catalog.schedule` pour toutes les séries suivies en un
  appel ; on n'interroge `source.episodes` que pour les séries dont un épisode est sorti
  depuis la dernière vérification, plus une vérification complète par semaine (sources en
  avance ou en retard sur le calendrier). Les séries finies et vues ne sont jamais
  interrogées.
- Nouveaux épisodes → `Nouveautés`, pastilles, et le résumé quotidien (addendum §4).
- Téléchargement automatique des nouveaux épisodes en option, par catégorie.

### 5.6 Premier passage dans le domaine

Une étape, la première fois qu'on ouvre Anime : « Lie ton compte » (AniList, MyAnimeList)
avec « Importer ma liste », ou « Passer ». Sans source de lecture installée, le bouton
« Regarder » explique pourquoi et renvoie vers « Ajoute une source » (spec UI §6.7), comme
pour la musique.

## 6. Lecteur vidéo

### 6.1 Rust décide, Dart exécute

```
 Flutter                                      Rust core
 toucher un épisode ── watch(episode) ───────▶ WatchState (épisode, position reprise, pistes)
                                               ├─ téléchargé ? → playlist locale
                                               └─ sinon → source.videos (variantes)
 VideoPlayerAdapter ◀── VideoCommand{source, position, audio, subtitles, secondary}
                    ◀── PreloadNext (pré-résolution à 2 min de la fin)
        └── VideoEvent (première image, fin, erreur, position ~10 s, pistes changées) ─▶
                                               ├─ progress écrit, plays
                                               ├─ vu à 85 % → tracker.update
                                               └─ fin → épisode suivant (compte à rebours 5 s)
```

- `VideoPlayerAdapter` (`platform/video_player.dart`) : un second `Player` de `media_kit` et
  le widget `Video` de `media_kit_video`. Même forme que `PlayerAdapter` : commandes venues
  de Rust, événements vers Rust, position lue côté Dart pour l'UI.
- **Reprise** : `progress` écrit toutes les ~10 s et à chaque pause ; à l'ouverture, position
  enregistrée moins 3 s.
- **Pistes retenues par série** : langue audio, langue des sous-titres, piste secondaire.
- Seuil « vu » réglable (70 à 100 %, défaut 85 %) ; un saut du générique de fin compte comme
  la fin.
- **Démarrage instantané du suivant** : à la pré-résolution, `stream` télécharge les 30
  premières secondes de l'épisode suivant (premiers segments HLS, ou premiers Mo d'un
  fichier) dans le cache ; l'enchaînement et « Suivant » partent de ce cache.
- **Minuterie** : la minuterie commune (addendum §5.1) gagne « À la fin de l'épisode ».

### 6.2 Fonctions

- **Gestes** (mobile) : glisser vertical à gauche = luminosité, à droite = volume ;
  double-toucher à gauche ou à droite = ±10 s (cumulable) ; appui long = ×2 tant qu'on
  maintient ; glisser horizontal = avancer avec aperçu du temps.
- **Contrôles** : ⏯, ±10 s, épisode précédent / suivant, vitesse (0,25 à 3), pistes audio et
  sous-titres, qualité (variantes), rapport d'image (ajuster, remplir, étirer), verrouillage
  de l'écran, rotation forcée.
- **Sous-titres** : ASS rendus par libass dans libmpv, style d'origine conservé, polices
  embarquées du fichier respectées. Option « Imposer mon style » (taille, police, contour,
  position) pour les SRT et VTT, et pour les ASS si on le veut. Décalage ±.
- **Double sous-titres** (`secondary-sid`) : deux pistes affichées ensemble, la seconde en
  haut. En pause, toucher une ligne la copie.
- **Saut du générique** (les `segments` de la vidéo s'il y en a, sinon AniSkip) : bouton « Passer l'OP » pendant le segment, ou saut
  automatique au choix. Pendant le saut, une puce « Ajouter cet OP à ta musique » (le thème
  rattaché par `themes`) reste 5 s.
- **Anime4K** : préréglages Désactivé · Rapide · Qualité, appliqués par `glsl-shaders` avec
  les shaders embarqués (licence MIT). « Rapide » seulement sur Android si le spike tient
  60 images/s en 1080p sur l'appareil de référence ; sinon le choix n'est pas proposé sur cet
  appareil.
- **Commande Musique** dans l'en-tête (addendum §5.1) : titre et ⏯ de la session musique.
- Pas de `mpv.conf` ni de scripts Lua (sécurité du modèle de plugins).

### 6.3 Hors plein écran, arrière-plan, système

- Fenêtre flottante vivante et arrimage au mini-lecteur : addendum §5.2.
- **PiP Android** : `supportsPictureInPicture` sur l'activité, entrée automatique (Android
  12+, `setAutoEnterEnabled`) quand une vidéo joue. En PiP, Flutter ne dessine que la vidéo.
  Actions PiP : ±10 s, ⏯.
- **Audio en arrière-plan** : réglage « Continuer l'audio des épisodes en arrière-plan »,
  désactivé par défaut. Activé, l'écran éteint ou l'app en arrière-plan laisse l'audio
  jouer, dans le service `mediaPlayback`.
- **Seconde `MediaSession`** (Kotlin, canal de plateforme) pour la vidéo, à côté de celle
  d'`audio_service` : métadonnées (série, « Épisode 8 », vignette), ⏮ ⏯ ⏭, ±10 s. L'écran
  verrouillé montre le dernier média démarré (addendum §5.1). macOS : Now Playing suit la même
  règle.
- **Desktop** : `/watch` occupe toute la fenêtre ; double-clic = plein écran système ; les
  raccourcis visent la vidéo (addendum §5.3) : Espace, ← → ±10 s, ↑ ↓ volume, F plein écran,
  S passer le segment, N épisode suivant, V pistes de sous-titres, [ ] vitesse.

## 7. Téléchargements

- `download(episode)` → `source.videos` → variante selon la qualité choisie (Réglages ›
  Anime : 480p, 720p, 1080p, la meilleure) → crate `stream`.
- **HLS** : playlist maître → variante → playlist de segments ; chaque segment est téléchargé
  avec reprise ; clés AES-128 téléchargées et gardées à côté ; playlist locale réécrite en
  chemins relatifs ; pistes audio séparées et sous-titres enregistrés à côté. mpv lit la
  playlist locale hors ligne.
- **Fichier direct** (mp4, mkv) : par morceaux avec reprise, comme la musique.
- **DASH seul** : pas de téléchargement ; l'épisode affiche « Lecture en ligne seulement ».
- Vérification : nombre et taille des segments ; un segment raté est retenté 3 fois, puis le
  téléchargement passe en erreur avec « Réessayer ».
- Service de premier plan `dataSync` (socle §3.4), même page Téléchargements (addendum §2.3),
  même budget de stockage, « Pour le trajet » (addendum §7) : les N épisodes suivants des
  séries en cours, N = 2 par défaut. Supprimer automatiquement un épisode vu (option, après
  24 h).
- Emplacement : espace propre à l'app, comme la musique (`downloads/anime/<série>/<épisode>/`).

## 8. Erreurs, hors ligne, vie privée

- Erreurs typées du socle §6 ; messages selon `docs/voice.md` (« Cette source ne trouve pas
  l'épisode 8. Essaie une autre source. »).
- Hors ligne : bibliothèque, historique, progression et épisodes téléchargés restent là ;
  Parcourir, Nouveautés (rafraîchir) et la lecture en ligne affichent le message hors ligne.
  Les mises à jour du tracker attendent (§4.4).
- Télémétrie (socle §7) : ni titre de série, ni épisode, ni source dans les événements ; les
  mesures (toucher → première image, durée de `videos`, échecs de correspondance) seulement.

## 9. Tests

- **Rust** : correspondance catalogue ↔ source (score, saisons, films, « Hors série »),
  appariement des épisodes au numéro réel, `progress` et reprise, seuil « vu », file du
  tracker hors ligne et conflit, mise à jour intelligente (n'interroge que les séries
  concernées), téléchargement HLS (reprise de segment, AES-128, playlist réécrite, domaines
  refusés), import d'une liste.
- **`plugin-host`** : `oauth` (le jeton n'atteint jamais le composant ; un composant qui lit
  ses imports ne le trouve pas), `send-authorized` refusé hors des domaines déclarés,
  `settings-schema` et filtres ; boîte à cookies isolée par plugin ; un composant de test avec
  l'option `js` du SDK, coupé par son fuel ; un plugin musique 1.0 chargé par l'hôte 1.1.
- **SDK** : décompacteur et AES compatible CryptoJS sur des scripts réels enregistrés.
- **Plugins** (feed officiel) : AniList, AnimeThemes, AniSkip, MyAnimeList sur réponses
  enregistrées.
- **Dart** : ligne d'épisode (états), page série, gestes du lecteur, pistes retenues par
  série, puce de l'OP pendant le saut, fenêtre flottante et arrimage, PiP (le widget ne
  dessine que la vidéo), tests dorés de la matrice de la spec UI §2.8.
- **Natif** : seconde `MediaSession` (test instrumenté : métadonnées, boutons).

## 10. Ordre de travail

### 10.1 Étape 1 : spike de faisabilité (avant tout code anime)

Comme le socle §10 : on découvre ce qui casse avant de construire. Une app de sonde Flutter
jetable, plus une sonde Rust pour le HLS.

| Mesure | Seuil | Si ça casse |
|---|---|---|
| HLS en ligne (maître + variantes, en-têtes `Referer`) sur Android arm64 et macOS | lecture, changement de variante sans coupure | Résolution des variantes dans le cœur, une URL de variante passée à mpv |
| ASS exigeant (karaoké, `\pos`, `\move`, polices embarquées) | rendu identique à mpv de bureau | Vérifier les polices de secours fournies à libass ; police CJK embarquée |
| Double sous-titres (`secondary-sid`) via `NativePlayer.setProperty` | les deux pistes visibles | Seconde piste dessinée par Flutter à partir du fichier, sans style ASS |
| Anime4K « Rapide » 1080p (`glsl-shaders`) sur l'appareil Android de référence | 60 images/s, mesurées en profil | Préréglage proposé seulement sur desktop |
| Audio de la vidéo écran éteint, 30 min | sans coupure | Service `mediaPlayback` propre à la vidéo |
| PiP automatique, Flutter ne dessine que la vidéo | OK sur Android 12+ | PiP manuel (bouton) |
| Musique et vidéo jouent ensemble : le lecteur vidéo ne prend pas le focus audio exclusif, et `audio_service` ne met pas la musique en pause au démarrage d'un épisode | les deux audibles 10 min | La vidéo joue sans demander le focus audio, et la session musique ignore les pertes de focus causées par l'app elle-même |
| Les 20 hébergeurs vidéo les plus utilisés par les extensions Aniyomi : combien se traitent avec les aides Rust du SDK seules | ≥ 18 sur 20 | Option `js` du SDK avec Boa en WASM, mesurée sous Pulley : ≤ 2 s pour un script obscurci de 100 Ko, composant ≤ 4 Mio, boucle infinie coupée par le fuel |
| Deux `MediaSession` (musique + vidéo) | l'écran verrouillé montre la dernière démarrée, chaque bouton atteint la bonne session | Une seule session système, qui bascule sur le dernier média démarré |
| HLS téléchargé par la sonde Rust (AES-128 compris), lu hors ligne par mpv | lecture complète, avance rapide | Remux en un seul fichier (FFmpeg de libmpv) |
| Taille : `media_kit_libs_audio` → `media_kit_libs_video` dans toute l'app, arm64 | **+25 Mio au plus** | libmpv vidéo recompilée sans les décodeurs inutiles |
| Licences | ni GPL ni nonfree | Variante vidéo déjà vérifiée (rapport de l'étape 1 de la musique) ; on ajoute libass (ISC) et les shaders Anime4K (MIT) |

Le rapport va dans `docs/superpowers/reports/`, comme celui de la musique.

### 10.2 Ensuite

1. Généralisations du socle (§2) : tables, `vehicoule:host` mineur, `stream` HLS, seconde
   session.
2. Contrats `vehicoule:anime` et `vehicoule:tracker`, plugins du feed officiel.
3. Bibliothèque, correspondance, mise à jour intelligente.
4. Lecteur, fenêtre flottante, PiP, `MediaSession`.
5. Écrans, puis téléchargements.
6. Validation : les critères du §1.

## 11. Ce que cette spec ne couvre pas

- Le domaine livres : sa spec (les tables et contrats communs posés ici lui servent tels
  quels).
- Les sources de lecture elles-mêmes : plugins tiers, hors des dépôts Vehicoule, comme
  `vehicoule-ytmusic`.
