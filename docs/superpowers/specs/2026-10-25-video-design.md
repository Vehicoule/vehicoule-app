# Vehicoule — Domaine vidéo (films, séries, animés) : design

Date : 2026-10-25 · Statut : en relecture (remplace la spec anime du même jour)

Specs parentes : `2026-10-18-socle-musique-design.md` (le « socle »),
`2026-10-23-socle-ui-design.md` (la « spec UI », branche `socle`),
`2026-10-25-navigation-domaines.md` (l'« addendum ») et `2026-10-25-surface-attaque.md`. Cette
spec branche la vidéo sur le socle : même cœur, même hôte de plugins, même bibliothèque, mêmes
coques. Elle remplace `2026-10-25-anime-design.md` : l'anime est désormais une partie du domaine
vidéo, avec la même expérience (modèle Aniyomi). Les numéros de section de l'ancienne spec sont
gardés là où d'autres specs les citent.

Nom : libellé **« Vidéos »**, identifiant de code **`video`** (routes `/video/…`, paquet WIT
`vehicoule:video`, capacités `video.*`).

## 1. But et décisions

Regarder des films, des séries et des animés avec une seule bibliothèque, une reprise exacte,
« À suivre », les nouveaux épisodes et des trackers, avec les garanties du socle : aucune source
de scraping intégrée, plugins en composants WASM, données de l'utilisateur indépendantes des
fournisseurs. Pour l'anime, l'expérience d'Aniyomi.

| Sujet | Décision |
|---|---|
| Identité | **Une seule identité** pour les trois : items `movie`, `show`, `season`, `episode`, `collection`. Un animé n'est pas une sorte à part : un `show` ou un `movie` marqué `anime` (§3.1) |
| Numérotation | Chaque épisode porte son numéro dans la saison **et** son numéro absolu ; plusieurs ordres par série (diffusion, DVD, absolu, histoire) ; les fiches AniList sont rattachées à des saisons ou à des plages d'épisodes (§3.6) |
| Contrat | `vehicoule:video@1.0.0` : `catalog`, `source`, `subtitles`, `themes`, `skip`, `identify` (§4) |
| Catalogues | TMDB (films, séries) avec la clé du projet ; AniList (animés) ; correspondances ouvertes entre les deux (§3.6). TVDB écarté (API payante pour les apps) |
| Trackers | Plugins `vehicoule:tracker@1.0.0` : Trakt, Simkl, AniList, MyAnimeList. L'hôte fait l'OAuth et garde les jetons (§4.4) |
| Sources légales | Dans le feed officiel : **Jellyfin / Emby, Plex**, et les **fichiers locaux** (fournisseur du cœur) (§4.6) |
| Lecteur | Complet, sans accès brut à mpv : gestes, pistes VO / VF, style des sous-titres, saut de l'intro et du générique, double sous-titres, Anime4K pour l'anime (§6) |
| Lecture | Seconde session, en parallèle de la musique ; fenêtre flottante vivante ; PiP système ; lecture sur la TV (addendum §5) |
| Téléchargements | HLS et fichiers directs, par la crate `stream` (§7) |
| Feed officiel | TMDB, AniList, Trakt, Simkl, MyAnimeList, OpenSubtitles, AnimeThemes, AniSkip, trace.moe, Jellyfin / Emby, Plex. Les sources de streaming non officielles viennent de feeds tiers, comme ytmusic |
| Plateformes | Android + macOS, comme la musique |

### Critères de réussite

1. Une série suivie et un animé suivi se regardent de bout en bout sur Android et macOS
   pendant deux semaines sans revenir à une autre app (Aniyomi, l'app Jellyfin).
2. Moins de 3 s entre le toucher sur un épisode non préchargé et la première image, sur une
   connexion correcte.
3. La reprise tombe à ±2 s de la position quittée, y compris après un arrêt brutal de l'app.
4. 30 min d'audio d'épisode écran éteint sur Android sans coupure (réglage activé).
5. Plus de 95 % de bonnes correspondances catalogue ↔ source sur un corpus de 100 titres
   (§3.3), et 100 % des épisodes bien placés sur un corpus de 20 séries à numérotation
   difficile (§3.6).

## 2. Ce que le socle généralise

Chaque point est posé dans le socle, pas dans le domaine, parce que les livres en ont aussi
besoin.

| Socle | Généralisation |
|---|---|
| `items.kind` (§5.1) | + `movie`, `show`, `season`, `episode`, `collection` (les livres ajoutent `book`, `chapter`). **`anime` n'est pas une sorte** |
| Tables communes (§5.2) | + `library_entries`, `categories`, `progress`, `bookmarks`, `source_bindings` (§3.2) ; `item_relations` (addendum §6) |
| `vehicoule:host` | 1.1.0 : + `types`, `session` (cookies), `challenge`, `oauth`, filtres, `settings-schema` (§4.5) ; `credentials` (spec livres §4.5) ; adresses du réseau local accordées par l'utilisateur (§4.6) |
| SDK | + décompacteur, AES compatible CryptoJS, option `js` (Boa, moteur JS en Rust, compilé en WASM dans le composant) si le spike l'exige (§4.5) |
| Manifeste (§4.3) | + `adult: bool` ; Réglages › Sources « Afficher les sources pour adultes », désactivé par défaut |
| Crate `stream` (§3.4) | + HLS : variantes, segments avec reprise, AES-128, playlist locale réécrite, sous-titres à côté (§7) ; proxy local (surface d'attaque §2) |
| Lecteur | + seconde session : `WatchState` dans le cœur, `VideoPlayerAdapter` côté Dart (§6.1) |
| Plateforme | + tâche périodique (mise à jour de la bibliothèque, §5.5), seconde `MediaSession` Android, PiP, verrouillage de l'app (§8) |
| Dépendances | libmpv + FFmpeg vidéo **recompilés réduits** (surface d'attaque §3) à la place de `media_kit_libs_audio`, pour toute l'app ; + `media_kit_video` |

## 3. Bibliothèque

### 3.1 Tables du domaine

- `video_titles` (clé = item `movie`, `show` ou `collection`) :
  - titres : original, localisés par langue, et pour l'anime romaji, natif et synonymes ;
  - langue originale, **`anime: bool`**, pays d'origine ;
  - statut (annoncé, en cours, fini, annulé, en pause), année, saison d'anime (hiver,
    printemps, été, automne) ;
  - genres, studios ou chaînes, synopsis, affiche, fond, classification d'âge, durée (film),
    note moyenne.
- `video_seasons` (clé = item `season`) : série, numéro (**0 = spéciaux**), titre, dates de
  diffusion, nombre d'épisodes prévu, affiche.
- `video_episodes` (clé = item `episode`) : saison, **numéro dans la saison**, **numéro
  absolu** (12.5 existe), titre, date de diffusion, durée, vignette, `filler`.
- `episode_orders` : série, type d'ordre (`aired`, `dvd`, `absolute`, `story`), et pour
  chaque épisode sa position dans cet ordre (§3.6).
- `collection_parts` : collection → film, ordre de sortie et ordre chronologique.
- `catalog_spans` : une fiche d'un catalogue (par exemple une entrée AniList) → la série, la
  saison et la plage d'épisodes qu'elle couvre (§3.6).
- `episode_sources` : épisode, ou film, → plugin + id chez la source, groupe (fansub, release),
  langue audio, sous-titres incrustés.

Un **film** n'a ni saison ni épisode : sa progression, son historique et ses sources portent
sur l'item `movie`.

### 3.2 Tables communes nouvelles

Toutes portent les colonnes de synchro du socle §5.3 (`updated_at` HLC, `device_id`,
`deleted_at`).

- `library_entries` : item suivi (film, série, livre), date d'ajout, statut personnel (en
  cours, à voir, fini, en pause, abandonné).
- `categories` (par domaine, ordre fractionnaire) et `library_entry_categories`.
- `progress` : item (épisode, film, chapitre), position et durée (ms, ou page et nombre de
  pages), `completed_at`. Écrit toutes les ~10 s pendant la lecture et à chaque pause, comme
  `queue_state`.
- `bookmarks` : item, position, note facultative.
- `source_bindings` : film ou série → plugin + id chez la source, priorité, « fixé à la
  main ».

`plays` (socle) reçoit aussi les épisodes et les films : l'historique, « Ton année » (addendum
§9 bis) et l'ordre appris de « Reprendre » (addendum §4) s'en servent sans table de plus.

### 3.3 Correspondance catalogue ↔ source

1. `source_bindings` déjà présent → l'utiliser.
2. Identifiant direct : si la source donne un id TMDB, IMDb, TVDB ou AniList (Jellyfin et Plex
   le font), rattachement sans recherche.
3. Sinon, `source.search` avec les titres, dans l'ordre : titre original, titre localisé, et
   pour l'anime romaji, anglais, natif, synonymes ; jusqu'au premier résultat au-dessus du
   seuil.
4. Score :
   - titres normalisés (casse, ponctuation, articles, « Season 2 » ↔ « 2nd Season »,
     « Part » / « Cour ») ;
   - année ±1 ;
   - film : durée ±10 % ; série : nombre de saisons ; anime : format et nombre d'épisodes ±1 ;
   - pénalité « dub » si la langue audio préférée est la VO, et l'inverse.
5. Sous le seuil → « Choisir une source », qui ouvre les candidats.
6. **Correction manuelle** : « Ce n'est pas le bon titre » liste les autres candidats (affiche,
   année, nombre d'épisodes) ; le choix est fixé.
7. **Épisodes** : appariés dans le schéma de numérotation de la source (§3.6) ; un épisode de
   la source sans place connue apparaît sous « Hors série ».

Le corpus de 100 titres (films homonymes, remakes, suites, animés aux saisons coupées en deux)
vit avec le premier plugin de source tiers et sert de test réel, comme celui de YouTube Music.

### 3.4 Plusieurs sources pour un titre

Un film ou une série peut avoir plusieurs sources, ordonnées par la note de fiabilité (§4.1),
puis par l'ordre fixé à la main. Un épisode absent de la première est cherché dans la
suivante. « Changer de source » réordonne ; la progression, les catégories et les trackers ne
bougent pas, parce qu'ils pointent vers les items.

### 3.5 Importer depuis une autre app

- **Aniyomi (et Mihon)** : la sauvegarde `.tachibk` (protobuf compressé), lue en Rust
  (`prost`). Fichier non fiable : taille plafonnée avant décompression, décodage borné, aucune
  URL du fichier ouverte.
  - Repris : séries de la bibliothèque, catégories, épisodes vus et position, favoris,
    historique, trackers liés.
  - **Rattachement** : d'abord par les ids de tracker de la sauvegarde (AniList, MyAnimeList :
    sans recherche), sinon par la correspondance du §3.3. Les épisodes s'apparient par
    numéro, à travers `catalog_spans` (§3.6).
  - Les sources d'Aniyomi (extensions Kotlin) n'ont pas d'équivalent : chaque série cherche
    ses sources parmi celles installées, et affiche « Choisir une source » sinon.
  - La partie manga est reprise par la spec livres, avec le même lecteur de fichier.
- **Trakt, Simkl, AniList, MyAnimeList** : « Importer ma liste et mon historique »
  (`tracker.list` et `history`, §4.4).
- Entrée : Réglages › Sauvegarde › « Importer depuis une autre app », et le premier passage
  dans le domaine (§5.6). Fin : un résumé (« 142 titres importés, 3 à vérifier ») ; les titres
  à vérifier s'ouvrent dans une liste.

### 3.6 Numérotation, ordres, spéciaux, collections

**Le problème** : les catalogues ne découpent pas pareil. TMDB a *L'Attaque des Titans* en une
série de quatre saisons ; AniList en a une fiche par saison ou par « cour » (*Saison 3
partie 2* est une entrée à part). Une source d'anime numérote souvent en absolu (E69), une
source de séries en SxxEyy, Jellyfin selon les fichiers.

**La règle** : la série Vehicoule est unique ; tout le reste s'y rattache.

- **Identité** : pour un `show` animé, TMDB donne la structure (saisons, épisodes, dates) ;
  AniList donne les métadonnées d'anime (titres, studios, génériques, relations). Sans fiche
  TMDB, la structure vient d'AniList, une saison par fiche.
- **`catalog_spans`** : chaque fiche AniList est rattachée à une saison, ou à une plage
  d'épisodes absolus. Les correspondances viennent de données ouvertes (**anime-offline-
  database**, qui relie AniList, MyAnimeList, Kitsu et d'autres ; les listes de Fribb, qui
  relient AniList / AniDB à TMDB et TVDB), téléchargées et mises à jour comme un catalogue,
  avec correction manuelle si elles se trompent.
- **Schéma de la source** : chaque épisode renvoyé par une source dit ce qu'il porte (saison +
  numéro, absolu, ou numéro dans une fiche donnée) ; le cœur le traduit vers l'épisode
  Vehicoule par `catalog_spans` et `episode_orders`.
- **Ordres** : diffusion (défaut), DVD, absolu, histoire, quand le catalogue les fournit
  (« episode groups » de TMDB). Choisi par série (« Ordre : diffusion ▾ ») ; la liste
  d'épisodes, « À suivre » et la source suivent l'ordre choisi. Sans ça, *Firefly*,
  *Futurama* ou *One Piece* tombent faux.
- **Spéciaux au bon endroit** : un épisode de la saison 0 (OVA, spécial, film intercalé comme
  *Mugen Train* entre deux saisons de *Demon Slayer*) se place dans « À suivre » à sa place
  dans l'histoire, d'après l'ordre `story` ou les relations du catalogue, au lieu d'être rangé
  à part. Réglage par série : « Inclure les spéciaux ».
- **Collections** : une `collection` (sagas TMDB : Harry Potter, Ghibli…) avec l'ordre de
  sortie ou chronologique, et « Reprendre la saga ».
- **Ordre de visionnage d'une franchise d'anime** (*Monogatari*, *Fate*) : « Par où
  commencer ? » sur la page, construit avec les relations AniList (suites, préquelles,
  histoires parallèles), ordre de sortie par défaut.

## 4. Contrat

### 4.1 `vehicoule:video@1.0.0`

Les `record` de la 1.0 sont figés avec soin (socle §4.3 : un champ de plus = version
majeure).

```wit
package vehicoule:video@1.0.0;

interface types {
    use vehicoule:host/types.{error, image};

    enum title-kind { movie, show }
    enum status { announced, airing, finished, cancelled, hiatus }
    enum anime-season { winter, spring, summer, fall }
    enum segment-kind { intro, opening, ending, credits, recap, preview }
    record segment { kind: segment-kind, start-ms: u32, end-ms: u32 }
    record title-ref { provider: string, id: string }
    record titles {
        original: option<string>,
        /// BCP 47 tag, then title.
        localized: list<tuple<string, string>>,
        romaji: option<string>,
        native: option<string>,
        synonyms: list<string>,
    }
    record title {
        ref: title-ref,
        /// Other ids known for this title (tmdb, imdb, tvdb, anilist, mal, kitsu…).
        external: list<title-ref>,
        kind: title-kind,
        titles: titles,
        /// BCP 47 tag of the original audio.
        original-language: option<string>,
        anime: bool,
        status: option<status>,
        year: option<u16>,
        anime-season: option<anime-season>,
        seasons: option<u32>,
        episodes: option<u32>,
        runtime-min: option<u32>,
        /// Average score, 0 to 100.
        score: option<u8>,
        /// Age rating for the user's region, as the catalogue writes it.
        certification: option<string>,
        genres: list<string>,
        studios: list<string>,
        synopsis: option<string>,
        poster: list<image>,
        backdrop: list<image>,
        adult: bool,
    }
    record season {
        /// 0 holds specials.
        number: u32,
        title: option<string>,
        /// ISO 8601 date, `YYYY-MM-DD`.
        aired: option<string>,
        episodes: option<u32>,
        poster: list<image>,
    }
    /// How a source numbers this episode: what the core maps from (§3.6).
    variant numbering {
        season-episode(tuple<u32, f32>),
        absolute(f32),
        /// Number inside one catalogue entry (an AniList entry, for instance).
        in-entry(tuple<title-ref, f32>),
    }
    record episode {
        id: string,
        numbering: numbering,
        title: option<string>,
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
    use types.{title, title-ref, season, episode, title-kind};
    use vehicoule:host/types.{error};

    enum relation-kind { prequel, sequel, side-story, adaptation, source, alternative, spin-off }
    record relation { kind: relation-kind, target: title-ref, domain: string }
    enum order-kind { aired, dvd, absolute, story }
    record episode-order {
        kind: order-kind,
        name: string,
        /// Episode id, then its position in this order.
        positions: list<tuple<string, u32>>,
    }
    record collection { ref: title-ref, title: string, parts: list<title-ref> }
    record airing-next { episode: episode, at-unix: s64 }

    search: func(query: string, kind: option<title-kind>, page: u32) -> result<list<title>, error>;
    fetch: func(ref: title-ref) -> result<title, error>;
    seasons: func(ref: title-ref) -> result<list<season>, error>;
    /// All episodes, or one season's.
    episodes: func(ref: title-ref, season: option<u32>) -> result<list<episode>, error>;
    orders: func(ref: title-ref) -> result<list<episode-order>, error>;
    relations: func(ref: title-ref) -> result<list<relation>, error>;
    collection: func(ref: title-ref) -> result<option<collection>, error>;
    /// Next airing episodes for many shows at once (smart library update, §5.5).
    schedule: func(refs: list<title-ref>) -> result<list<tuple<title-ref, airing-next>>, error>;
}

interface source {
    use types.{title, episode, segment};
    use vehicoule:host/types.{error};
    use vehicoule:host/filters.{filter-schema, filter-value};

    enum stream-format { hls, file }
    enum sub-format { ass, srt, vtt }
    record subtitle { url: string, lang: string, label: option<string>, format: sub-format, sdh: bool, headers: list<tuple<string, string>> }
    record audio-track { url: string, lang: string, label: option<string> }
    record video {
        url: string,
        headers: list<tuple<string, string>>,
        format: stream-format,
        /// Vertical resolution, 1080 for 1080p.
        height: option<u32>,
        hdr: bool,
        label: option<string>,
        audio: list<audio-track>,
        subtitles: list<subtitle>,
        /// Skip timings some hosters ship with the video; preferred over `skip`.
        segments: list<segment>,
        expires-unix: option<s64>,
    }
    record page { items: list<title>, has-next: bool }

    popular: func(page: u32) -> result<page, error>;
    latest: func(page: u32) -> result<page, error>;
    filters: func() -> result<filter-schema, error>;
    search: func(query: string, filters: list<filter-value>, page: u32) -> result<page, error>;
    fetch: func(id: string) -> result<title, error>;
    /// A movie has one episode here, whose id `videos` takes.
    episodes: func(title-id: string) -> result<list<episode>, error>;
    /// Every playable variant, best first. Called again on `expired`.
    videos: func(episode-id: string) -> result<list<video>, error>;
}

interface subtitles {
    use types.{title-ref};
    use source.{subtitle};
    use vehicoule:host/types.{error};

    record query {
        title: title-ref,
        season: option<u32>,
        episode: option<f32>,
        langs: list<string>,
        /// OpenSubtitles-style hash of the file, when it is local.
        file-hash: option<string>,
    }
    search: func(q: query) -> result<list<subtitle>, error>;
}

interface themes {
    use types.{title-ref};
    use vehicoule:host/types.{error};

    enum theme-kind { opening, ending, insert }
    record theme {
        kind: theme-kind,
        number: u32,
        title: string,
        artists: list<string>,
        /// Absolute episode range this theme plays on, `[first, last]`.
        episodes: option<tuple<f32, f32>>,
    }
    themes: func(ref: title-ref) -> result<list<theme>, error>;
}

interface skip {
    use types.{title-ref, segment};
    use vehicoule:host/types.{error};

    /// `duration-ms` lets the provider pick the right timing for this release.
    segments: func(ref: title-ref, episode: f32, duration-ms: u32) -> result<list<segment>, error>;
}

interface identify {
    use types.{title-ref};
    use vehicoule:host/types.{error};

    record sighting {
        title: title-ref,
        episode: option<f32>,
        at-ms: option<u32>,
        /// 0 to 100.
        confidence: u8,
    }
    /// A screenshot (PNG or JPEG bytes), best match first.
    identify: func(image: list<u8>) -> result<list<sighting>, error>;
}
```

- `catalog` : plugins **TMDB** (films, séries, ordres, collections, calendrier) et **AniList**
  (animés, GraphQL public), un même plugin AniList servant aussi les livres. Le plugin TMDB
  porte la clé d'application du projet (gratuite pour un usage non commercial) : l'utilisateur
  ne saisit rien. `external` porte les ids IMDb, TVDB, MyAnimeList, dont les sources, AniSkip
  et les trackers ont besoin.
- `source` : Jellyfin / Emby et Plex dans le feed officiel (§4.6) ; les autres viennent de
  feeds tiers, publiés hors des dépôts Vehicoule (socle §4.4).
- `subtitles` : plugin **OpenSubtitles** (clé d'application du projet ; pas de clé de
  l'utilisateur), pour un titre sans sous-titres dans la langue voulue, ou un fichier local.
- `themes` : plugin AnimeThemes. Le cœur cherche chaque thème dans le catalogue musique
  (« titre artiste ») et crée une relation `theme-song` (addendum §6) ; le titre se lit et se
  like comme n'importe quel titre.
- `skip` : plugin AniSkip (anime). Pour les autres séries, l'intro est **détectée sur
  l'appareil** (§6.2).
- `identify` : plugin trace.moe, sans clé, dans son quota gratuit (« C'est quoi ? », mode
  Montrer, addendum §6 bis).
- Routage : liste de priorité par capacité, comme le socle §4.7. Pour un titre `anime`,
  AniList passe avant TMDB pour les métadonnées d'anime.
- **Source la plus fiable d'abord** : le cœur note chaque source en local, par titre (taux de
  réussite de `videos`, temps jusqu'à la première image, hauteur obtenue, sur les 30 derniers
  essais). Pour chaque épisode, il essaie les sources dans l'ordre de cette note ; un ordre
  fixé à la main dans `source_bindings` passe avant. Une source qui se dégrade descend seule.

### 4.2 Capacités et erreurs

Les erreurs sont celles du socle §6. `expired` sur une vidéo → un seul nouvel appel à
`videos`, reprise à la même position. Une variante qui échoue → la suivante, puis la source
suivante de `source_bindings`.

### 4.3 Sécurité réseau des sources

Les règles du socle §4.3 s'appliquent sans exception, à travers le proxy local (surface
d'attaque §2) : domaines déclarés, vérifiés à chaque redirection et pour chaque URL de vidéo,
de sous-titre et de segment ; IP privées refusées, sauf l'adresse accordée par l'utilisateur à
un plugin de serveur personnel (§4.6).

### 4.4 `vehicoule:tracker@1.0.0`

```wit
package vehicoule:tracker@1.0.0;

interface tracker {
    use vehicoule:host/types.{error};

    enum media { anime, movie, show, book }
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
    /// By catalogue id when the tracker knows it (anilist:21, tmdb:1399, imdb:tt0944947).
    find: func(media: media, catalogue: string, id: string) -> result<option<entry>, error>;
    get: func(ref: entry-ref) -> result<entry, error>;
    update: func(entry: entry) -> result<entry, error>;
    /// The whole user list, for the first import.
    list: func(media: media, cursor: option<string>) -> result<tuple<list<entry>, option<string>>, error>;
}

/// Optional export: per-episode history and playback position (Trakt, Simkl).
interface history {
    use vehicoule:host/types.{error};

    record watch-key { catalogue: string, id: string, season: option<u32>, episode: option<f32> }
    watched: func(key: watch-key, at-unix: s64) -> result<_, error>;
    unwatched: func(key: watch-key) -> result<_, error>;
    /// Paused position, 0 to 100, for resuming on another device.
    set-progress: func(key: watch-key, percent: u8) -> result<_, error>;
    progress: func() -> result<list<tuple<watch-key, u8>>, error>;
    /// Watched episodes and movies, newest first, for the first import.
    watched-list: func(cursor: option<string>) -> result<tuple<list<tuple<watch-key, s64>>, option<string>>, error>;
}
```

- **Liaison** : au premier ajout d'un titre à la bibliothèque, le cœur appelle `find` avec les
  ids de `title.external` ; sans résultat, la page propose « Lier le tracker » (recherche).
- **Mise à jour** : à chaque épisode ou film marqué vu, `update` (trackers à compteur :
  AniList, MyAnimeList) ou `history.watched` (trackers à historique : Trakt, Simkl). Hors
  ligne, les mises à jour attendent dans une file et partent au retour du réseau.
- **Pont entre appareils** : en pause et à la fermeture, `history.set-progress` ; à
  l'ouverture de l'app, `history.progress` met à jour « À suivre » et la reprise. Deux
  appareils liés au même compte Trakt reprennent au même endroit, sans attendre la synchro de
  Vehicoule.
- **Conflit** : la progression la plus haute gagne, sauf statut `repeating`.

### 4.5 Ajouts mineurs à `vehicoule:host` (1.1.0)

Ajouter une interface est une version mineure (socle §4.3) ; aucun `record` de la 1.0 ne
change. Les plugins musique 1.0 restent chargés tels quels.

- **`types`** (nouvelle interface) : `error` (les variantes du socle §6) et `image`, communs à
  la vidéo, aux trackers et aux livres. `vehicoule:music` garde ses propres types, qu'on ne
  peut pas déplacer sans version majeure.
- **`session`** : un `send` qui passe par une **boîte à cookies par plugin**, gardée par
  l'hôte, avec un User-Agent stable par appareil. `http.send` (1.0) reste sans cookies.
- **`challenge`** : quand une source renvoie `provider-wall` avec une URL, l'app propose
  « Ouvrir la page » : une WebView dans une feuille, où **l'utilisateur passe lui-même** la
  vérification du site. Les cookies obtenus rejoignent la boîte du plugin, et le User-Agent de
  `session` est celui de la WebView. L'app ne résout jamais une vérification à la place de
  l'utilisateur. WebView durcie : surface d'attaque §4.
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
  navigateur du système, retour par un **lien vérifié** `https://vehicoule.com/oauth/<plugin>`
  (App Links, liens universels) : un schéma `vehicoule://` peut être revendiqué par une autre
  app installée, pas un lien vérifié (RFC 8252). L'hôte garde les jetons dans le trousseau du
  système (Keystore Android, Keychain macOS) et les rafraîchit. `send-authorized(request)`
  ajoute `Authorization` : **le plugin ne voit jamais le jeton**. « Se déconnecter » efface
  les jetons.
- **`filters`** (types) : `filter-schema` (texte, choix unique, choix multiple, tri, case à
  trois états, groupe) et `filter-value`. Communs à la vidéo et aux livres. L'UI les dessine
  avec les chips et les feuilles de `design/`.
- **`settings-schema`** (export facultatif de tout plugin) : les préférences d'une source
  (miroir, qualité, langue) décrites avec les mêmes types que les filtres. Valeurs gardées
  par l'hôte, lues par le plugin dans son `kv`. Écran : Sources › une source › Réglages.

### 4.6 Sources légales : serveurs personnels et fichiers locaux

Sans feed tiers, l'app doit déjà servir, et légalement. Le feed officiel livre :

- **Jellyfin / Emby** (même famille d'API) et **Plex** : des plugins `source` (et `catalog`
  pour leurs métadonnées locales). Ils donnent les ids TMDB / IMDb / TVDB : rattachement
  direct (§3.3). La progression peut être renvoyée au serveur (option), pour que l'app
  officielle du serveur reste à jour. Les mêmes plugins exportent `vehicoule:music` pour les
  bibliothèques musicales du serveur ; Navidrome et les serveurs Subsonic suivent le même
  modèle côté musique.
  - Connexion : adresse du serveur et identifiants par l'interface `credentials` (spec livres
    §4.5) pour Jellyfin / Emby ; flux PIN de Plex par `oauth`.
  - **Réseau local** : un serveur personnel est souvent sur une IP privée, que le socle §4.3
    refuse. À l'ajout, l'utilisateur **accorde cette adresse à ce plugin seulement** (« Autoriser
    192.168.1.20 pour Jellyfin ») ; l'accord est gardé par l'hôte, affiché dans Sources ›
    Détails, retirable. Aucun autre plugin ne peut joindre cette adresse, et aucune autre
    adresse privée n'est accordée (surface d'attaque §2).
- **Fichiers locaux** : un fournisseur **du cœur** (Rust, pas un plugin : il lit des fichiers,
  ce qu'un plugin ne peut pas), comme le fournisseur `local` prévu par le socle §11.
  - Dossiers choisis par l'utilisateur (sélecteur système ; Android : SAF, lu par Dart et
    passé au cœur).
  - Reconnaissance des noms (`Titre (2019).mkv`, `S01E02`, `[Groupe] Titre - 12`), puis
    rattachement au catalogue (§3.3) et sous-titres à côté (`.ass`, `.srt`).
  - Les mêmes dossiers servent à la musique locale.

## 5. Écrans

### 5.1 Destinations

Accueil (commun, addendum §4) · **Bibliothèque** · **Nouveautés** · **Historique** ·
**Parcourir**. Routes sous `/video/…` (addendum §3).

- **Bibliothèque** (`/video/library`) :
  - en tête, la rangée **« À suivre »** : le prochain épisode non vu de chaque série en cours
    (dans l'ordre choisi, spéciaux compris si demandé), puis les films commencés ;
  - puces : Tout · Séries · Films · Animés · puis les catégories ;
  - grille d'affiches 2:3, pastille « non vus » en haut à droite. Filtres (non vus,
    téléchargés, statut, tracker), tri (dernier vu, ajout, alphabétique, prochain épisode).
    Desktop : 4 à 8 colonnes, survol ▶ « Reprendre ».
- **Nouveautés** (`/video/updates`) : bascule **Sortis · À venir**.
  - Sortis : épisodes sortis des séries suivies, groupés par jour, en lignes d'épisode
    (§5.3). Tirer pour rafraîchir lance la mise à jour.
  - À venir : le **calendrier** des sept prochains jours (`catalog.schedule`), heure dans le
    fuseau de l'appareil, et les films annoncés des collections suivies.
- **Anti-spoiler** (réglage, désactivé par défaut) : titres, vignettes et synopsis des
  épisodes non vus masqués partout (« Épisode 9 », vignette floutée). Le flou est le seul de
  l'app, fourni par `design/` (spec UI §2.8).
- **Historique** (`/video/history`) : dernier épisode vu par série et films vus, groupés par
  jour ; ✕ retire de l'historique, avec Annuler.
- **Parcourir** (`/video/browse`) : la search bar (catalogues TMDB et AniList d'abord, puis
  « Chercher dans les sources »), les serveurs et sources installés ; une source ouvre
  Populaires · Récents et ses filtres. Un résultat d'une source ouvre la page du titre après
  correspondance (§3.3).

### 5.1 bis Langue des titres

Réglages › Vidéos › « Titres en » :

- films et séries : **titre dans la langue de l'app** quand il existe (TMDB), sinon le titre
  original ; ou toujours le titre original ;
- animés : romaji, anglais, natif, ou **français quand il existe** (TMDB, puis synonymes
  AniList, puis l'anglais).

Le choix s'applique partout : grilles, pages, notifications, Reprendre, partage. La recherche
cherche toujours dans tous les titres.

### 5.2 Pages

**Film** (`/video/<branche>/movie/:id`) :
- fond et affiche fondus dans la surface (spec UI §2.2, pas d'extraction), titre, année,
  durée, classification, genres ;
- split button « Lire » ou « Reprendre à 1 h 12 » | ▾ (depuis le début, marquer comme vu,
  télécharger) ; « Ajouter à la bibliothèque » en bouton tonal ;
- synopsis replié à 3 lignes ; distribution (étagère) ; la **collection** (« Saga Harry
  Potter · 3 sur 8 ») avec « Reprendre la saga » ;
- ⋮ : changer de source, « Ce n'est pas le bon titre », partager (addendum §3.1).

**Série** (`/video/<branche>/show/:id`), et l'anime avec ses ajouts :
- même en-tête, avec statut de diffusion et « Épisode 8 dans 2 jours » ;
- split button « Reprendre S2 E5 » | ▾ (depuis le début, marquer comme vu, télécharger les N
  suivants) ;
- **onglets de saisons** (Spéciaux en dernier), ou liste absolue pour un anime selon l'ordre
  choisi ; « Ordre : diffusion ▾ » quand plusieurs ordres existent ;
- lignes d'épisode (§5.3), ordre croissant ou décroissant retenu par série, filtres (non vus,
  téléchargés, favoris), sélection multiple avec la toolbar flottante (vu / non vu,
  télécharger, supprimer, favori). « Vu jusqu'ici » par appui long ;
- **anime** : étagère des génériques (OP, ED : titres de la musique, toucher lit dans la
  session musique, ♥ like) ; « Par où commencer ? » pour une franchise (§3.6) ; liens vers
  l'adaptation (« Le manga continue au chapitre 87 », addendum §6) ;
- tracker lié, statut et note modifiables ;
- ⋮ : changer de source, « Ce n'est pas le bon titre », inclure les spéciaux, partager,
  attacher une bande-son (addendum §6).

### 5.3 Ligne d'épisode (une seule, partout)

Comme la ligne de titre (spec UI §5.1), dans `design/` : vignette 16:9 (ou numéro), titre
« S2 E5 · Le titre » (ou « 69 · Le titre » en numérotation absolue), date et groupe en
dessous, barre de progression fine sous la vignette si l'épisode est commencé, opacité 38 % une
fois vu, icône de téléchargement à droite (flèche → anneau ondulé → coche). Toucher =
regarder ; glisser à droite = vu / non vu ; appui long = menu expressif.

### 5.4 Accueil commun

Le domaine fournit au module `home` (addendum §4) :

- la carte Reprendre : le premier d'« À suivre » ;
- « Nouveaux épisodes » (bibliothèque), « Bientôt » (calendrier des séries suivies) ;
- « Tes mixes » gagne **« Ton mix anime »** (radio de la musique sur les génériques des
  animés regardés).

### 5.5 Mise à jour de la bibliothèque

- Tâche périodique : 12 h, 24 h (défaut) ou chaque semaine ; Wi-Fi seulement en option.
  Android : `WorkManager` (paquet `workmanager`) qui démarre le cœur sans UI ; macOS : à
  l'ouverture et toutes les 24 h tant que l'app tourne. La même tâche sert aux livres.
- **Mise à jour intelligente** : `catalog.schedule` (TMDB, AniList) pour toutes les séries
  suivies en un appel ; on n'interroge `source.episodes` que pour les séries dont un épisode
  est sorti depuis la dernière vérification, plus une vérification complète par semaine
  (sources en avance ou en retard sur le calendrier). Les séries finies et vues ne sont jamais
  interrogées. Un serveur personnel (Jellyfin, Plex) est interrogé à chaque mise à jour : il
  est local et gratuit.
- Nouveaux épisodes → Nouveautés, pastilles, résumé quotidien (addendum §4).
- Téléchargement automatique des nouveaux épisodes en option, par catégorie.

### 5.6 Premier passage dans le domaine

Une étape, la première fois qu'on ouvre Vidéos :

1. « Tu as un serveur Jellyfin, Emby ou Plex ? » → ajouter le serveur (§4.6), ou « Choisir un
   dossier » (fichiers locaux), ou « Passer ».
2. « Lie ton compte » (Trakt, Simkl, AniList, MyAnimeList) avec « Importer ma liste », ou
   « Passer ».

Sans aucune source, le bouton « Regarder » explique pourquoi et renvoie vers « Ajoute une
source » (spec UI §6.7), comme pour la musique.

## 6. Lecteur vidéo

### 6.1 Rust décide, Dart exécute

```
 Flutter                                      Rust core
 toucher un épisode ── watch(item) ──────────▶ WatchState (épisode ou film, position, pistes)
                                               ├─ téléchargé ou local ? → fichier par le proxy
                                               └─ sinon → source.videos (variantes)
 VideoPlayerAdapter ◀── VideoCommand{url du proxy, position, audio, subtitles, secondary}
                    ◀── PreloadNext (pré-résolution à 2 min de la fin)
        └── VideoEvent (première image, fin, erreur, position ~10 s, pistes changées) ─▶
                                               ├─ progress écrit, plays
                                               ├─ vu au seuil → trackers
                                               └─ fin → suivant d'« À suivre » (compte à rebours 5 s)
```

- `VideoPlayerAdapter` (`platform/video_player.dart`) : un second `Player` de `media_kit` et
  le widget `Video` de `media_kit_video`. Même forme que `PlayerAdapter` : commandes venues
  de Rust, événements vers Rust, position lue côté Dart pour l'UI.
- **Reprise** : `progress` écrit toutes les ~10 s et à chaque pause ; à l'ouverture, position
  enregistrée moins 3 s.
- **Seuil « vu »** réglable (70 à 100 %, défaut 85 % ; pour un film, défaut 90 % ou le début du
  générique de fin s'il est connu).
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
- **Pistes audio (VO / VF…)** : Réglages › Vidéos › « Langue audio » : **originale** (défaut)
  ou une langue choisie (« français, sinon originale »), séparément pour les animés. Le choix
  fait sur un titre est retenu pour ce titre. Une source qui sert la VO et la VF en deux
  entrées (`audio-lang`) est choisie selon ce réglage.
- **Sous-titres** :
  - défaut intelligent : **affichés quand l'audio n'est pas dans ta langue**, masqués sinon ;
    retenu par titre ;
  - ASS (anime) rendus par libass dans libmpv, style d'origine et polices embarquées
    respectés ; SRT et VTT (films et séries) avec le style de l'utilisateur. Option « Imposer
    mon style » (taille, police, contour, position), y compris pour les ASS. Décalage ± ;
  - « Chercher des sous-titres » : la capacité `subtitles` (OpenSubtitles), avec le hachage
    du fichier quand il est local.
- **Double sous-titres** (`secondary-sid`) : deux pistes affichées ensemble, la seconde en
  haut. En pause, toucher une ligne la copie.
- **Sous-titres pour sourds et malentendants** : un filtre retire, ou garde seuls, les
  annotations sonores (`[musique]`, `(rires)`, noms de locuteurs) des pistes SDH ; une
  police haute lisibilité est proposée dans le style des sous-titres.
- **Passer l'intro et le générique** :
  - anime : les `segments` de la vidéo s'il y en a, sinon AniSkip. Pendant le saut d'un OP,
    une puce « Ajouter cet OP à ta musique » (le thème rattaché par `themes`) reste 5 s ;
  - autres séries : **intro détectée sur l'appareil**, en comparant les empreintes audio
    (`rusty-chromaprint`) du début de deux épisodes d'une même saison, comme l'« Intro
    Skipper » de Jellyfin. Calculé à la lecture ou au téléchargement, gardé par épisode ;
    rien ne sort de l'appareil ;
  - bouton « Passer l'intro » pendant le segment, ou saut automatique au choix, par série.
- **Anime4K** (animés seulement) : préréglages Désactivé · Rapide · Qualité, appliqués par
  `glsl-shaders` avec les shaders embarqués (licence MIT). « Rapide » seulement sur Android si
  le spike tient 60 images/s en 1080p sur l'appareil de référence.
- **HDR** : HDR10 et HLG rendus directement si l'écran les gère, sinon convertis en SDR par mpv
  (tone mapping) ; Dolby Vision profil 5 converti par libplacebo si le spike le permet.
- **Commande Musique** dans l'en-tête (addendum §5.1) : titre et ⏯ de la session musique.
- Pas de `mpv.conf` ni de scripts Lua (sécurité du modèle de plugins).

### 6.3 Hors plein écran, arrière-plan, système

- Fenêtre flottante vivante et arrimage au mini-lecteur : addendum §5.2. Lire sur la TV :
  addendum §5.4.
- **PiP Android** : `supportsPictureInPicture` sur l'activité, entrée automatique (Android
  12+, `setAutoEnterEnabled`) quand une vidéo joue. En PiP, Flutter ne dessine que la vidéo.
  Actions PiP : ±10 s, ⏯.
- **Audio en arrière-plan** : réglage « Continuer l'audio des vidéos en arrière-plan »,
  désactivé par défaut. Activé, l'écran éteint ou l'app en arrière-plan laisse l'audio
  jouer, dans le service `mediaPlayback`.
- **Seconde `MediaSession`** (Kotlin, canal de plateforme) pour la vidéo, à côté de celle
  d'`audio_service` : métadonnées (titre, « S2 E5 », vignette), ⏮ ⏯ ⏭, ±10 s. L'écran
  verrouillé montre le dernier média démarré (addendum §5.1). macOS : Now Playing suit la même
  règle.
- **Desktop** : `/watch` occupe toute la fenêtre ; double-clic = plein écran système ; les
  raccourcis visent la vidéo (addendum §5.3) : Espace, ← → ±10 s, ↑ ↓ volume, F plein écran,
  S passer le segment, N épisode suivant, V pistes de sous-titres, [ ] vitesse.

## 7. Téléchargements

- `download(item)` → `source.videos` → variante selon la qualité choisie (Réglages › Vidéos :
  480p, 720p, 1080p, la meilleure) → crate `stream`.
- **HLS** : playlist maître → variante → playlist de segments ; chaque segment est téléchargé
  avec reprise ; clés AES-128 téléchargées et gardées à côté ; playlist locale réécrite en
  chemins relatifs ; pistes audio séparées et sous-titres enregistrés à côté. Hors ligne, mpv
  lit la playlist locale par le proxy.
- **Fichier direct** (mp4, mkv) : par morceaux avec reprise, comme la musique.
- **Serveur personnel** : le fichier d'origine, ou une version transcodée par le serveur si la
  qualité choisie est plus basse (Jellyfin et Plex le proposent).
- **DASH seul** : pas de téléchargement ; l'épisode affiche « Lecture en ligne seulement ».
- Vérification : nombre et taille des segments ; un segment raté est retenté 3 fois, puis le
  téléchargement passe en erreur avec « Réessayer ».
- Service de premier plan `dataSync` (socle §3.4), même page Téléchargements (addendum §2.3),
  même budget de stockage, « Pour le trajet » (addendum §7) : les N épisodes suivants
  d'« À suivre », N = 2 par défaut. Supprimer automatiquement un épisode vu (option, après
  24 h).
- Emplacement : espace propre à l'app (`downloads/video/<titre>/<saison>/<épisode>/`).

## 8. Erreurs, hors ligne, vie privée

- Erreurs typées du socle §6 ; messages selon `docs/voice.md` (« Cette source ne trouve pas
  l'épisode 8. Essaie une autre source. »).
- Hors ligne : bibliothèque, historique, progression, fichiers locaux et épisodes téléchargés
  restent là ; Parcourir, Nouveautés (rafraîchir) et la lecture en ligne affichent le message
  hors ligne. Les mises à jour des trackers attendent (§4.4).
- **Verrouillage de l'app** (Réglages › Confidentialité) : par biométrie ou code du système,
  au lancement et après N minutes en arrière-plan ; **écran masqué dans les apps récentes**
  (Android `FLAG_SECURE`, macOS : contenu masqué dans l'aperçu). Valable pour toute l'app.
- **Lecture privée** : depuis le ⋮ d'un titre ou du lecteur, « Regarder sans historique » :
  ni `plays`, ni tracker, ni « À suivre » pour cette lecture.
- Télémétrie (socle §7) : ni titre, ni épisode, ni source dans les événements ; les mesures
  (toucher → première image, durée de `videos`, échecs de correspondance) seulement.

## 9. Tests

- **Rust** :
  - correspondance catalogue ↔ source (films homonymes, remakes, saisons, animés, « Hors
    série ») ;
  - **numérotation** : traduction `season-episode` / `absolute` / `in-entry` vers l'épisode
    Vehicoule à travers `catalog_spans` ; ordres DVD et absolu (*Firefly*, *Futurama*, *One
    Piece*) ; spéciaux placés par l'ordre `story` ; corpus des 20 séries difficiles (§1) ;
  - « À suivre » (ordre choisi, spéciaux, films commencés), collections ;
  - `progress` et reprise, seuils « vu », file des trackers hors ligne et conflit, pont
    `history.progress` ;
  - mise à jour intelligente (n'interroge que les séries concernées) ;
  - téléchargement HLS (reprise de segment, AES-128, playlist réécrite, domaines refusés) ;
  - fichiers locaux : reconnaissance des noms sur un corpus de noms réels ;
  - détection d'intro sur deux épisodes enregistrés ;
  - imports (`.tachibk`, listes de trackers).
- **`plugin-host`** : `oauth` (le jeton n'atteint jamais le composant), `send-authorized` refusé
  hors des domaines déclarés, `settings-schema` et filtres ; boîte à cookies isolée par
  plugin ; adresse locale accordée à un seul plugin (refusée aux autres) ; un composant de test
  avec l'option `js` du SDK, coupé par son fuel ; un plugin musique 1.0 chargé par l'hôte 1.1.
- **SDK** : décompacteur et AES compatible CryptoJS sur des scripts réels enregistrés.
- **Plugins** (feed officiel) : TMDB, AniList, Trakt, Simkl, MyAnimeList, OpenSubtitles,
  AnimeThemes, AniSkip, Jellyfin, Plex sur réponses enregistrées.
- **Dart** : ligne d'épisode (états, numérotation), pages film et série, onglets de saisons et
  choix d'ordre, gestes du lecteur, pistes et sous-titres retenus par titre, puce de l'OP
  pendant le saut, fenêtre flottante et arrimage, PiP (le widget ne dessine que la vidéo),
  verrouillage de l'app, tests dorés de la matrice de la spec UI §2.8.
- **Natif** : seconde `MediaSession` (test instrumenté : métadonnées, boutons).

## 10. Ordre de travail

### 10.1 Étape 1 : spike de faisabilité (avant tout code vidéo)

Comme le socle §10 : on découvre ce qui casse avant de construire. Une app de sonde Flutter
jetable, plus une sonde Rust pour le HLS.

| Mesure | Seuil | Si ça casse |
|---|---|---|
| HLS en ligne (maître + variantes, en-têtes `Referer`) sur Android arm64 et macOS, par le proxy local | lecture, changement de variante sans coupure | Résolution des variantes dans le cœur, une URL de variante passée à mpv |
| ASS exigeant (karaoké, `\pos`, `\move`, polices embarquées) | rendu identique à mpv de bureau | Vérifier les polices de secours fournies à libass ; police CJK embarquée |
| Double sous-titres (`secondary-sid`) via `NativePlayer.setProperty` | les deux pistes visibles | Seconde piste dessinée par Flutter à partir du fichier, sans style ASS |
| **H.264 10 bits (Hi10P) 1080p**, fréquent dans les fansubs, décodé en logiciel sur l'appareil Android de référence | 24 images/s tenues, sans saut | Proposer la variante 8 bits quand la source en a une ; sinon le dire sur l'épisode |
| **HDR10** et Dolby Vision profil 5 : rendu HDR si l'écran le gère, sinon conversion en SDR | couleurs justes (mire de test) | HDR10 seul ; Dolby Vision lu en couche de base |
| Anime4K « Rapide » 1080p (`glsl-shaders`) sur l'appareil Android de référence | 60 images/s, mesurées en profil | Préréglage proposé seulement sur desktop |
| Audio de la vidéo écran éteint, 30 min | sans coupure | Service `mediaPlayback` propre à la vidéo |
| PiP automatique, Flutter ne dessine que la vidéo | OK sur Android 12+ | PiP manuel (bouton) |
| Musique et vidéo jouent ensemble : le lecteur vidéo ne prend pas le focus audio exclusif, et `audio_service` ne met pas la musique en pause au démarrage d'un épisode | les deux audibles 10 min | La vidéo joue sans demander le focus audio, et la session musique ignore les pertes de focus causées par l'app elle-même |
| Les 20 hébergeurs vidéo les plus utilisés par les extensions Aniyomi : combien se traitent avec les aides Rust du SDK seules | ≥ 18 sur 20 | Option `js` du SDK avec Boa en WASM, mesurée sous Pulley : ≤ 2 s pour un script obscurci de 100 Ko, composant ≤ 4 Mio, boucle infinie coupée par le fuel |
| Deux `MediaSession` (musique + vidéo) | l'écran verrouillé montre la dernière démarrée, chaque bouton atteint la bonne session | Une seule session système, qui bascule sur le dernier média démarré |
| HLS téléchargé par la sonde Rust (AES-128 compris), lu hors ligne par mpv | lecture complète, avance rapide | Remux en un seul fichier (FFmpeg de libmpv) |
| Jellyfin sur le réseau local, adresse accordée au seul plugin Jellyfin | lecture directe et transcodée | — (bloquant : revoir l'accord d'adresse) |
| Détection d'intro par empreintes sur 10 séries réelles | intro trouvée à ±1 s sur 8 séries sur 10 | Bouton « Passer 85 s » manuel, retenu par série |
| Taille : libmpv + FFmpeg vidéo réduits (surface d'attaque §3) à la place de `media_kit_libs_audio`, dans toute l'app, arm64 | **+25 Mio au plus** | Retirer AV1 et HEVC logiciels (décodage matériel seulement) |
| Conditions d'usage de TMDB et d'OpenSubtitles pour une clé d'application embarquée dans une app open source | autorisé, attribution respectée (§11) | Clé servie par le Worker Cloudflare (requêtes relayées, quota par appareil) |
| Licences | ni GPL ni nonfree | Variante vidéo déjà vérifiée (rapport de l'étape 1 de la musique) ; on ajoute libass (ISC), les shaders Anime4K (MIT), libplacebo (LGPL) |

Le rapport va dans `docs/superpowers/reports/`, comme celui de la musique.

### 10.2 Ensuite

1. Généralisations du socle (§2) : tables, `vehicoule:host` mineur, `stream` HLS, seconde
   session.
2. Contrats `vehicoule:video` et `vehicoule:tracker`, plugins du feed officiel.
3. Bibliothèque, numérotation et correspondance, mise à jour intelligente.
4. Lecteur, fenêtre flottante, PiP, `MediaSession`.
5. Écrans, serveurs personnels et fichiers locaux, puis téléchargements.
6. Validation : les critères du §1.

## 11. Licences et conditions des données

Les données ont leurs propres règles, distinctes de celles du code :

| Donnée | Règle | Dans l'app |
|---|---|---|
| TMDB | usage non commercial avec clé ; **logo et mention obligatoires** ; pas d'usage présenté comme approuvé par TMDB | Réglages › À propos › Sources de données, et la mention sous les fiches qui en viennent |
| AniList | conditions de l'API (débit, pas de revente des données) | mention dans À propos ; limite de débit déclarée au manifeste |
| anime-offline-database | **ODbL** : attribution, et partage à l'identique d'une base dérivée | mention dans À propos ; `catalog_spans` exportable sous ODbL si on la publie |
| Listes de Fribb | leur licence, vérifiée au spike | mention dans À propos |
| OpenSubtitles, Trakt, Simkl | conditions de leur API, attribution | mention dans À propos |

Chaque plugin du feed officiel déclare dans son manifeste les mentions qu'il impose ; l'écran
À propos les affiche toutes.

## 12. Ce que cette spec ne couvre pas

- Le domaine livres : sa spec (les tables et contrats communs posés ici lui servent tels
  quels).
- Les sources de streaming non officielles : plugins tiers, hors des dépôts Vehicoule, comme
  `vehicoule-ytmusic`.
