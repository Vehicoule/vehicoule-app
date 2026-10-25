# Vehicoule — Domaine livres : design

Date : 2026-10-25 · Statut : approuvé par l'utilisateur le 2026-10-25

Specs parentes : `2026-10-18-socle-musique-design.md` (le « socle »),
`2026-10-23-socle-ui-design.md` (la « spec UI », branche `socle`),
`2026-10-25-navigation-domaines.md` (l'« addendum »), `2026-10-25-anime-design.md` (la « spec
anime ») et `2026-10-25-surface-attaque.md`. Cette spec branche les livres (mangas, manhwa,
comics, romans, light novels, ebooks) sur le socle : même cœur, même hôte de plugins, même
bibliothèque, mêmes coques, et les tables et contrats communs posés par l'anime.

## 1. But et décisions

Lire des mangas comme dans Mihon et des ebooks comme dans une bonne liseuse, dans la même app,
avec les garanties du socle : sources en composants WASM, données de l'utilisateur
indépendantes des fournisseurs, aucun HTML rendu par une WebView.

| Sujet | Décision |
|---|---|
| Libellé visible | **« Livres »** (« Books » en anglais). Nom interne `books`, routes `/books/…`, forme de décor **arche** (addendum §8) |
| Identité d'un livre | **Un item Vehicoule** `book`, ses chapitres des items `chapter`. Métadonnées d'un catalogue (AniList, Open Library) ; une ou plusieurs sources rattachées (§3.3) |
| Contrat | `vehicoule:books@1.0.0` : `catalog`, `source`, `remote-progress`, `identify` (§4) ; un chapitre fournit des **pages**, du **texte** XHTML ou un **fichier** |
| Trackers | `vehicoule:tracker@1.0.0` de la spec anime, `media: book` : AniList, MyAnimeList |
| Lecteur | Images (page par page, défilant, webtoon, case par case) et texte (EPUB **rendu en natif** : Rust lit, Flutter met en page) (§6) |
| Formats de fichiers | EPUB 2 et 3, CBZ, CB7, PDF, MOBI et AZW3 sans DRM, FB2 ; CBR si un décodeur RAR en Rust tient (§3.5). Tout en Rust pur |
| Feed officiel | AniList (catalogue + tracker, un seul plugin avec l'anime), MyAnimeList (tracker), Open Library, MangaUpdates (sorties), SauceNAO, OPDS (Project Gutenberg, Standard Ebooks, serveurs de l'utilisateur). Les sources de scans viennent de feeds tiers, comme ytmusic et les sources anime |
| Performance | **120 images/s** partout (défilement, pages, zoom), mesurées au 99ᵉ centile (§11.1) |
| Plateformes | Android + macOS, comme la musique et l'anime |

### Critères de réussite

1. Une série suivie et un ebook se lisent de bout en bout sur Android et macOS pendant deux
   semaines sans revenir à Mihon ni à une autre liseuse.
2. Moins de 1 s entre le toucher sur un chapitre hors cache et la première page affichée, sur
   une connexion correcte.
3. Après un arrêt brutal de l'app, la reprise tombe sur la page quittée (images) ou sur la
   phrase quittée (texte).
4. Aucune image perdue en défilement à 120 Hz (§11.1).
5. Plus de 95 % de bonnes correspondances catalogue ↔ source sur un corpus de 100 séries.
6. Plus de 95 % des séries d'une vraie sauvegarde Mihon importées et rattachées sans
   intervention.

## 2. Ce que le socle généralise

| Socle | Généralisation |
|---|---|
| `items.kind` (§5.1) | + `book`, `chapter` (posés par la spec anime §2) |
| Tables communes (spec anime §3.2) | réutilisées telles quelles ; `progress` gagne `locator` (§3.2) |
| `vehicoule:host` 1.1.0 (spec anime §4.5) | + interface `credentials` (§4.5), dans la même version 1.1.0 tant qu'elle n'est pas publiée |
| Manifeste (socle §4.3) | + `replaces-mihon` (§3.6), + domaines ajoutés par l'utilisateur (§4.3) |
| `vehicoule:music` | + capacité `tempo` (mineure, comme `identify`) pour le défilement au tempo (§6.5) |
| Crate `stream` | + pages servies par le proxy local (surface d'attaque §2), désembrouillage, transcodage d'images, découpe des images hautes (§6.2) |
| Lecteur | + `ReadState` dans le cœur, `/read/:id` (addendum §3) |
| Plateforme | même tâche périodique que l'anime (spec anime §5.5) ; synthèse vocale du système (§6.8) |

## 3. Bibliothèque

### 3.1 Tables du domaine

- `book_series` (clé = item) : titres (romaji, anglais, natif, synonymes), format, statut de
  publication, année, pays d'origine, nombre de chapitres et de tomes prévus, auteurs,
  dessinateurs, genres, synopsis, couverture, ISBN, langue, sens de lecture retenu (§6.2),
  groupe de scan préféré (§3.4).
- `book_chapters` (clé = item) : livre, **numéro réel** (10.5 existe), tome, titre, date,
  groupe, langue, nombre de pages.
- `chapter_sources` : chapitre → plugin + id du chapitre chez la source, groupe, langue.
- `book_highlights` : chapitre, début et fin (`locator`), couleur, note facultative. Colonnes
  de synchro du socle §5.3.

### 3.2 Tables communes

Celles de la spec anime §3.2, sans changement de rôle :

- `library_entries` : livres suivis, statut personnel (en cours, à lire, fini, en pause,
  abandonné).
- `categories` (domaine `books`) et `library_entry_categories`.
- `progress` : un chapitre. Pour les images, `position` = page, `length` = nombre de pages.
  Pour le texte, `position` et `length` en dix-millièmes de l'ouvrage, et **`locator`** (texte
  JSON, nouvelle colonne nullable de la table commune) au format *Locator* de Readium :
  fichier du spine, progression dans ce fichier, extrait de texte avant et après. Une position
  ainsi notée survit à un changement de police, de taille ou de marges, et à une légère
  modification du fichier.
- `bookmarks` : signets de page ou de position ; gagne aussi `locator` (nullable), comme
  `progress`.
- `source_bindings` : livre → plugin + id du livre chez la source, priorité, « fixé à la
  main ».

`plays` reçoit les sessions de lecture (début, durée lue) : Historique, « Ton année »
(chapitres, pages, heures, séries finies), ordre appris de « Reprendre » et temps restant
(§6.6) s'en servent.

### 3.3 Correspondance catalogue ↔ source

L'algorithme de la spec anime §3.3, adapté :

1. `source_bindings` déjà présent → l'utiliser.
2. Identifiant direct : ISBN (Open Library), id AniList, MyAnimeList ou MangaUpdates connu
   (sauvegarde, `ComicInfo.xml`, `external` du livre) → rattachement sans recherche.
3. Sinon, `source.search` avec les titres dans l'ordre romaji, anglais, natif, synonymes.
4. Score : similarité des titres normalisés, auteur, année ±1, format, nombre de chapitres
   (la source peut être en avance ou en retard sur le catalogue : écart toléré).
5. Sous le seuil → « Choisir une source ». Correction : « Ce n'est pas le bon livre ».
6. Chapitres appariés par numéro réel ; un chapitre sans numéro (extra, annonce) va sous
   « Hors série ».

Le corpus de 100 séries (titres ambigus, suites, one-shots, versions couleur, manhwa
renommés en anglais) vit avec le premier plugin de source tiers et sert de test réel.

### 3.4 Plusieurs sources, groupes, doublons

- Plusieurs sources par livre, ordonnées par la note de fiabilité de la spec anime §4.1 (taux
  de réussite de `content`, temps jusqu'à la première page), un ordre fixé à la main passant
  avant. Un chapitre absent de la première est cherché dans la suivante.
- **Groupe préféré, retenu par série** : quand plusieurs groupes sortent le même numéro, la
  liste montre un seul chapitre, celui du groupe préféré (sinon le plus récent) ; les autres
  vont sous « Autres versions » dans le menu de la ligne.
- **Langues des chapitres** : Réglages › Livres › « Langues des chapitres », une liste ordonnée
  (FR puis EN, par exemple), modifiable par livre. Un seul chapitre par numéro, dans la première
  langue disponible ; les autres langues vont sous « Autres versions », avec les autres groupes.
- **Doublons à l'ajout** : ajouter un livre déjà présent par une autre source affiche « Déjà
  dans ta bibliothèque » ; les deux items se rejoignent par `merged_into` (socle §5.3).

### 3.5 Fichiers de l'appareil

Une source **intégrée au cœur**, pas un plugin : les fichiers locaux sont lus en Rust natif.

- Entrées : Parcourir › « Fichiers de l'appareil » (un dossier choisi par le sélecteur
  système, permission persistante sur Android, signet à portée de sécurité sur macOS), « Ouvrir
  avec Vehicoule » et le partage d'un fichier depuis une autre app (Android), le
  glisser-déposer sur la fenêtre (macOS). Un fichier ouvert ainsi est copié dans l'espace de
  l'app, rattaché, puis ouvert.
- Sur Android, Kotlin ouvre le document du sélecteur et passe le descripteur de fichier au
  cœur ; Rust ne voit jamais d'URI `content://`.
- Formats, tous en Rust pur :

  | Format | Lecture |
  |---|---|
  | EPUB 2 et 3 | `zip`, OPF, spine, `nav` / NCX ; XHTML et CSS (§6.6) |
  | CBZ, CB7 | `zip`, `sevenz-rust` ; index lu sans tout décompresser |
  | CBR (RAR4, RAR5) | seulement si le spike valide un décodeur en Rust pur ; sinon refusé avec « Convertis-le en CBZ ». Jamais unrar (C++) |
  | PDF | `hayro` : chaque page rendue en image, redessinée plus fine au zoom |
  | MOBI, AZW3 | `mobi`, converti dans l'arbre de blocs du texte (§6.6). DRM → refusé, avec la raison |
  | FB2 | XML lu en Rust, même arbre de blocs |

- **Rattachement automatique** : l'ISBN d'un EPUB (`dc:identifier`) → Open Library
  (`by-isbn`) ; le `ComicInfo.xml` d'un CBZ (série, numéro, tome, auteurs) → recherche dans le
  catalogue avec ces champs. Sans résultat, le livre garde les métadonnées du fichier.
- Un dossier par série, un fichier par chapitre ou par tome ; un fichier seul est un livre à un
  seul chapitre.
- Fichiers non fiables : taille et nombre d'entrées plafonnés avant décompression (bombes
  zip), chemins internes normalisés, aucune URL du fichier ouverte (§4.3).

### 3.6 Importer

Réglages › Sauvegarde › « Importer depuis une autre app », et l'étape du premier passage
(§5.6).

- **Mihon et ses forks** (SY, J2K, Komikku : leurs champs en plus sont ignorés), et **la
  partie manga d'Aniyomi** : le `.tachibk` lu par le même lecteur Rust que la spec anime §3.5
  (`prost`, plafonds, décodage borné). Une sauvegarde Aniyomi s'importe en une fois, anime et
  manga.
  - Repris : bibliothèque, catégories, chapitres lus et dernière page lue, chapitres en
    signet (`bookmarks`), historique, trackers liés, filtre de groupes de scan (→ groupe
    préféré, §3.4).
  - Rattachement : d'abord les ids AniList, MyAnimeList ou MangaUpdates de la sauvegarde,
    sinon la correspondance du §3.3.
  - **`replaces-mihon`** : le manifeste d'un plugin source peut déclarer les ids des sources
    Mihon qu'il remplace, et sa fonction `fetch` accepte alors l'URL relative enregistrée par
    Mihon. Une série importée de cette source se rattache directement, sans recherche.
  - Les séries de la source locale de Mihon se rattachent aux « Fichiers de l'appareil » par
    le nom de dossier, une fois le dossier choisi.
- **Calibre** : choisir le dossier de la bibliothèque. Le cœur lit `metadata.db` (SQLite, déjà
  dans le cœur par rusqlite) en lecture seule : livres, fichiers, couvertures, séries et
  numéros, ISBN. Les fichiers sont lus là où ils sont, comme les « Fichiers de l'appareil ».
- **AniList, MyAnimeList** : « Importer ma liste » (`tracker.list`, `media: book`), comme la
  spec anime §4.4.
- Fin : un résumé (« 312 séries importées, 6 à vérifier »), la liste des séries à vérifier.

### 3.7 Migration en masse

Sources › une source › « Migrer N séries » : la correspondance du §3.3 cherche chaque série
sur les autres sources installées, puis une liste à valider (série, source trouvée, nombre de
chapitres). Valider réordonne `source_bindings` ; progression, catégories, signets et tracker
ne bougent pas, parce qu'ils pointent vers les items. Même entrée pour une sélection dans la
Bibliothèque.

## 4. Contrat

### 4.1 `vehicoule:books@1.0.0`

Les `record` de la 1.0 sont figés avec soin (socle §4.3).

```wit
package vehicoule:books@1.0.0;

interface types {
    use vehicoule:host/types.{error, image};

    enum format { manga, manhwa, manhua, comic, light-novel, novel, one-shot, doujinshi, ebook }
    enum publication { ongoing, finished, hiatus, cancelled, upcoming }
    enum direction { left-to-right, right-to-left, vertical, webtoon }
    record titles { romaji: option<string>, english: option<string>, native: option<string>, synonyms: list<string> }
    record book-ref { provider: string, id: string }
    record book {
        ref: book-ref,
        /// Other catalogue ids known for this book (anilist, mal, mangaupdates, openlibrary…).
        external: list<book-ref>,
        titles: titles,
        format: option<format>,
        publication: option<publication>,
        year: option<u16>,
        /// ISO 3166-1 alpha-2 country of the original publication (JP, KR, CN…).
        country: option<string>,
        /// BCP 47 tag of this edition's language.
        lang: option<string>,
        chapters: option<u32>,
        volumes: option<u32>,
        authors: list<string>,
        artists: list<string>,
        genres: list<string>,
        synopsis: option<string>,
        cover: list<image>,
        isbn: list<string>,
        /// Reading direction hint; the core derives one when absent (§6.2).
        direction: option<direction>,
        adult: bool,
    }
    record chapter {
        id: string,
        /// Real number: 10.5 exists.
        number: f32,
        volume: option<f32>,
        title: option<string>,
        /// ISO 8601 date, `YYYY-MM-DD`.
        published: option<string>,
        /// Scanlation group or publisher.
        group: option<string>,
        lang: option<string>,
        pages: option<u32>,
    }
}

interface catalog {
    use types.{book, book-ref};
    use vehicoule:host/types.{error};

    enum relation-kind { prequel, sequel, side-story, adaptation, source, alternative, spin-off, continues-at }
    record relation {
        kind: relation-kind,
        target: book-ref,
        /// `books`, `anime`.
        domain: string,
        /// For `continues-at`: the adaptation `target` ends after this episode…
        after-episode: option<f32>,
        /// …and the book resumes at this chapter.
        at-chapter: option<f32>,
    }
    record release { book: book-ref, chapter: f32, volume: option<f32>, group: option<string>, at-unix: s64 }

    search: func(query: string, page: u32) -> result<list<book>, error>;
    fetch: func(ref: book-ref) -> result<book, error>;
    by-isbn: func(isbn: string) -> result<option<book>, error>;
    relations: func(ref: book-ref) -> result<list<relation>, error>;
    recommendations: func(ref: book-ref) -> result<list<book>, error>;
    /// Chapters released since `since-unix` for many books at once (smart library update, §5.5).
    releases: func(refs: list<book-ref>, since-unix: s64) -> result<list<release>, error>;
}

interface source {
    use types.{book, chapter};
    use vehicoule:host/types.{error};
    use vehicoule:host/filters.{filter-schema, filter-value};

    /// One rectangle to move back in place, in source image pixels.
    record tile { src-x: u32, src-y: u32, dst-x: u32, dst-y: u32, width: u32, height: u32 }
    variant scramble {
        tiles(list<tile>),
        /// Repeating XOR key over the image bytes.
        xor(list<u8>),
    }
    record page {
        url: string,
        headers: list<tuple<string, string>>,
        /// Lighter version of the page, used by the saving mode.
        low: option<string>,
        /// Undone by the host in Rust, never by the plugin.
        scramble: option<scramble>,
        /// Width and height when known, so the reader lays out before loading.
        size: option<tuple<u32, u32>>,
    }
    enum file-format { epub, cbz, cb7, cbr, pdf, mobi, azw3, fb2 }
    record file { url: string, headers: list<tuple<string, string>>, format: file-format, size: option<u64> }
    variant content {
        pages(list<page>),
        /// XHTML body of the chapter; image URLs inside it are checked like pages.
        text(string),
        file(file),
    }
    record listing { items: list<book>, has-next: bool }

    popular: func(page: u32) -> result<listing, error>;
    latest: func(page: u32) -> result<listing, error>;
    filters: func() -> result<filter-schema, error>;
    search: func(query: string, filters: list<filter-value>, page: u32) -> result<listing, error>;
    /// Also accepts the relative URL Mihon stored, when the manifest declares `replaces-mihon`.
    fetch: func(id: string) -> result<book, error>;
    chapters: func(book-id: string) -> result<list<chapter>, error>;
    /// Called again once on `expired`.
    content: func(chapter-id: string) -> result<content, error>;
}

interface remote-progress {
    use vehicoule:host/types.{error};

    /// Reading position kept by the server (Komga, Kavita), in pages.
    record position { page: u32, pages: u32, completed: bool }
    get: func(chapter-id: string) -> result<option<position>, error>;
    report: func(chapter-id: string, position: position) -> result<_, error>;
}

interface identify {
    use types.{book-ref};
    use vehicoule:host/types.{error};

    record sighting {
        book: book-ref,
        chapter: option<f32>,
        page: option<u32>,
        /// 0 to 100.
        confidence: u8,
    }
    /// A photo or screenshot (PNG or JPEG bytes), best match first.
    identify: func(image: list<u8>) -> result<list<sighting>, error>;
}
```

- **Un ebook** est un livre à un seul chapitre de contenu `file` (ou `text`) ; un tome est un
  chapitre avec `volume`. Un light novel en tomes EPUB est un livre dont chaque chapitre est un
  fichier.
- `catalog` :
  - **AniList** : un seul plugin pour l'anime et les livres (catalogues des deux contrats,
    tracker), donc une seule connexion et un seul quota. `search`, `fetch`, `relations`,
    `recommendations` ; `external` porte les ids MyAnimeList et MangaUpdates quand AniList
    les connaît.
  - **Open Library** (sans clé) : `search`, `fetch`, `by-isbn`.
  - **MangaUpdates** (API publique, sans clé ni compte) : `releases`, `search`, `fetch`. Pas de
    tracker : sa connexion demande un mot de passe.
- `continues-at` : aucune base ouverte ne dit où un anime s'arrête dans le manga. La relation
  vient d'un plugin (feed tiers) qui exporte `relations`, ou de l'utilisateur (« Où reprend le
  manga ? » sur la page série anime ou la page livre, §5.2). Sans l'un ni l'autre, la page
  montre seulement « Adapté de ce manga ».
- `source` :
  - **OPDS** (feed officiel) : un plugin, préréglé sur Project Gutenberg et Standard Ebooks,
    plus les serveurs que l'utilisateur ajoute (Calibre, Komga, Kavita), OPDS 1 et 2 ; ses
    livres sont des `file`.
  - **`remote-progress`** (exporté par le plugin OPDS pour Komga et Kavita, par leurs API
    et les identifiants de `credentials`) : à l'ouverture, la position du serveur est lue et
    la plus avancée gagne ; chaque page lue lui est renvoyée (regroupée toutes les 10 s et à
    la sortie, file hors ligne comme le tracker). On reprend au même endroit dans leurs
    autres clients.
  - **Sources de scans et de romans web** : plugins tiers, dans leurs propres feeds (socle
    §4.4), comme `vehicoule-ytmusic` et les sources anime.
- `identify` : plugin **SauceNAO**, sans clé, dans le quota anonyme (§8).
- Routage : liste de priorité par capacité (socle §4.7) ; note de fiabilité des sources
  (§3.4).

### 4.2 Erreurs

Celles du socle §6. `expired` sur `content` ou une page → un seul nouvel appel à `content`,
reprise à la même page. Une page qui échoue → `low` si elle existe, puis la source suivante.
Un `file` au format non pris en charge → `not-found` côté cœur, avec la raison dans l'UI.

### 4.3 Sécurité réseau, fichiers et images

- Règles du socle §4.3 sans exception : chaque URL de page, de fichier et d'image du `text`
  est vérifiée (domaines du plugin, chaque redirection, IP privées refusées) **dans `stream`**.
- **Domaines ajoutés par l'utilisateur** : un plugin peut déclarer `user-domains: true` dans
  son manifeste (OPDS seulement dans le feed officiel). L'utilisateur saisit lui-même une URL
  de serveur dans Sources › le plugin › Réglages ; ce domaine s'ajoute à ceux du plugin, pour
  ce plugin seul. Une adresse du réseau local (Calibre sur `192.168.x.x`) est permise
  **seulement** si l'utilisateur l'a saisie telle quelle ; l'écran l'affiche (« Serveur du
  réseau local »). Une redirection depuis un domaine déclaré vers une IP privée reste
  refusée.
- Le désembrouillage (`scramble`), le transcodage et la découpe des images se font en Rust
  dans `stream`, sur des images dont la taille est plafonnée avant décodage (surface d'attaque
  §6).
- Fichiers téléchargés (EPUB, CBZ…) : mêmes plafonds que les fichiers de l'appareil (§3.5).

### 4.4 Trackers

Le contrat `vehicoule:tracker@1.0.0` de la spec anime §4.4, avec `media: book` :

- **AniList** (même plugin que l'anime) et **MyAnimeList**. `progress` = chapitres lus (ou
  tomes lus quand le livre se compte en tomes).
- Liaison au premier ajout par `find` avec les ids de `external`, sinon « Lier le tracker ».
- Mise à jour à chaque chapitre lu (§6.1), file hors ligne, conflit (progression la plus
  haute gagne) : comme l'anime.
- Ebooks hors AniList : pas de tracker. Goodreads n'a plus d'API, et Hardcover demande de
  coller une clé, ce qui est exclu.

### 4.5 Ajout à `vehicoule:host` 1.1.0 : `credentials`

Pour les serveurs OPDS privés. Nouvelle interface, posée dans la 1.1.0 avec celles de la spec
anime §4.5 (aucune n'est encore publiée).

- L'utilisateur saisit l'identifiant et le mot de passe **de son propre serveur** dans Sources
  › le plugin › Réglages, champ par champ. Ce n'est pas une clé d'API.
- L'hôte les garde dans le trousseau du système (Keystore Android, Keychain macOS), à côté des
  jetons OAuth.
- `send-with-credentials(request)` : l'hôte ajoute `Authorization` (Basic, ou Digest pour
  Calibre) **seulement** vers le domaine saisi avec ces identifiants ; **le plugin ne voit
  jamais le mot de passe**. Refusé vers tout autre domaine, y compris ceux du plugin.
- « Oublier ce serveur » efface les identifiants. La sauvegarde (addendum §7 bis) ne les
  contient pas.

## 5. Écrans

### 5.1 Destinations

Accueil (commun) · **Bibliothèque** · **Nouveautés** · **Historique** · **Parcourir**. Routes
`/books/library`, `/books/updates`, `/books/history`, `/books/browse` ; pages sous
`/books/<branche>/book/:id` ou `/home/books/book/:id` ; lecteur `/read/:id` (addendum §3).

- **Bibliothèque** : grille de couvertures 2:3, une page par catégorie (onglets défilants),
  pastille « non lus ». Filtres (non lus, téléchargés, images ou texte, statut, tracker), tri
  (dernière lecture, ajout, alphabétique, derniers chapitres sortis). Tuiles « Fichiers de
  l'appareil » et « Reconnus ». Desktop : 4 à 8 colonnes, survol ▶ « Reprendre ».
- **Nouveautés** : chapitres sortis dans la bibliothèque, groupés par jour. Plusieurs chapitres
  d'une même série le même jour tiennent sur **une ligne qui se déplie** (« Chapitres 87 à
  90 »). Pas de calendrier : les chapitres n'ont pas de date annoncée. Tirer pour rafraîchir
  lance la mise à jour.
- **Historique** : dernier chapitre lu par livre, groupé par jour ; ✕ retire le livre, avec
  Annuler ; filtre « Reconnus ».
- **Parcourir** : la search bar (catalogues AniList et Open Library d'abord, puis « Chercher
  dans les sources »), les sources installées (une source ouvre Populaires · Récents et ses
  filtres), les catalogues OPDS (navigation dans leurs rayons), « Fichiers de l'appareil ».
- **Contenu adulte** : le réglage de la spec anime §2 (« Afficher les sources pour adultes »,
  désactivé par défaut) s'applique tel quel ; `book.adult` est respecté dans Parcourir, les
  recommandations et les résultats de « C'est quoi ? ».
- **Anti-spoiler** : le réglage de la spec anime §5.1 s'applique aux titres de chapitres non
  lus.
- **Titres en** : le réglage de la spec anime §5.1 bis (Réglages › Livres).

### 5.2 Page livre

- Couverture fondue dans la surface (spec UI §2.2), titre, auteurs, format, statut, « 3
  nouveaux chapitres ».
- Split button « Reprendre le chapitre N » | ▾ (depuis le début, marquer comme lu,
  télécharger les N suivants) ; « Ajouter à la bibliothèque » en bouton tonal.
- Synopsis replié à 3 lignes (HTML converti en texte, surface d'attaque §6).
- **Liste des chapitres** : lignes de chapitre (§5.3), ordre retenu par livre, filtres (non
  lus, téléchargés, signets, groupe), sélection multiple avec la toolbar flottante. « Lu
  jusqu'ici » par appui long.
- Un livre à un seul chapitre (ebook) montre « Lire » et sa table des matières à la place de
  la liste.
- **Si tu aimes ça** : étagère de `recommendations`.
- **Liens** : l'anime adapté (« L'anime adapte jusqu'au chapitre 52 »), suites, relations ; «
  Où reprend le manga ? » quand une adaptation est connue sans `continues-at`.
- **Tracker** : la ligne du tracker lié, statut et note modifiables.
- ⋮ : changer de source, « Ce n'est pas le bon livre », sens de lecture, groupe préféré,
  partager (`vehicoule.com/b/…`, `/c/…`, addendum §3.1), attacher une bande-son, migrer,
  **« Exporter mes notes »** (un fichier Markdown : citations surlignées, notes, chapitres,
  passé à la feuille de partage du système).

### 5.3 Ligne de chapitre (une seule, partout)

Dans `design/`, comme la ligne d'épisode : « 87 · Le titre », date et groupe en dessous,
« page 12/40 » ou une barre fine si le chapitre est commencé, opacité 38 % une fois lu, icône
de téléchargement à droite (flèche → anneau ondulé → coche). Toucher = lire ; glisser à
droite = lu / non lu ; appui long = menu expressif (dont « Autres versions »).

### 5.4 Accueil commun

Le domaine fournit au module `home` : la carte Reprendre en arche (chapitre suivant de la
dernière série, ou livre en cours avec son pourcentage et le temps restant), « Nouveaux
chapitres » (bibliothèque). Le
résumé quotidien gagne « 2 chapitres ». « Ton année » gagne chapitres, pages, heures de lecture
et séries finies.

### 5.5 Mise à jour de la bibliothèque

- La tâche périodique de la spec anime §5.5, partagée par les deux domaines.
- **Mise à jour maline** : `catalog.releases` (MangaUpdates) pour tous les livres suivis en un
  appel ; on n'interroge `source.chapters` que pour ceux qui ont une sortie depuis la dernière
  vérification, plus une vérification complète par semaine. Les séries finies et lues ne sont
  jamais interrogées.
- Téléchargement automatique des nouveaux chapitres en option, par catégorie.

### 5.6 Premier passage dans le domaine

Une étape, la première fois qu'on ouvre Livres : « Lie ton compte » (AniList, MyAnimeList ;
sauté si AniList est déjà lié par l'anime) avec « Importer ma liste », « Importer depuis Mihon
ou Aniyomi », « Choisir un dossier de livres », ou « Passer ». Sans source qui lit, le bouton «
Lire » explique pourquoi et renvoie vers « Ajoute une source » (spec UI §6.7).

### 5.7 Réglages › Lecteur de livres

Sens par défaut, mode par défaut, zones de toucher, ajustement, touches de volume, netteté,
mode liseuse, flash, police et mise en page du texte, voix.

## 6. Lecteur

### 6.1 Rust décide, Dart exécute

```
 Flutter                                     Rust core
 toucher un chapitre ── read(chapter) ──────▶ ReadState (chapitre, locator, mode, sens)
                                              ├─ téléchargé ou fichier local ? → lu sur place
                                              └─ sinon → source.content
 Lecteur images ◀── pages (URLs du proxy, tailles, cases)
 Lecteur texte  ◀── arbre de blocs du fichier du spine
                ◀── Preload (4 pages suivantes ; début du chapitre suivant en fin de chapitre)
        └── ReadEvent (page ou locator, ~2 s, sortie, fin du chapitre) ─▶
                                              ├─ progress, plays
                                              ├─ fin → chapitre lu → tracker.update
                                              └─ « Chapitre suivant » (page de transition)
```

- `progress` est écrit à chaque page, regroupé toutes les 2 s, et à la sortie.
- Un chapitre est **lu** à sa dernière page (images) ou à la fin de son dernier fichier
  (texte).
- **Lire en avance** : en Wi-Fi, lire le chapitre N télécharge N+1 et N+2.
- **Lecture privée** : un interrupteur dans le ⋮ du lecteur et sur la Bibliothèque. Rien dans
  l'historique ni dans `plays`, aucune mise à jour du tracker, « Reprendre » inchangé. La
  progression du livre est gardée (on reprend où on en était), pas son historique.
- Puce « Reprendre la bande-son » à l'ouverture (addendum §6). La musique continue pendant la
  lecture.

### 6.2 Images (mangas, comics, CBZ, PDF)

- **Modes** : page par page (gauche → droite, droite → gauche), page par page vertical,
  défilant (avec marges), webtoon (défilant sans marge).
- **B1, sens de lecture** : `direction` du livre si la source le donne ; sinon déduit : pays
  JP → droite à gauche, KR → webtoon, CN → webtoon pour un manhua en couleur, sinon gauche à
  droite ; format `comic` → gauche à droite. Changer de sens dans le lecteur le **retient pour
  la série** (`book_series`).
- **Ajustement** : largeur, hauteur, écran, taille réelle, ou automatique (selon le rapport de
  la page). Zoom par double-toucher et pincement. Recadrage automatique des marges blanches,
  calculé en Rust.
- **Double page** sur grand écran (paysage, desktop) : une page panoramique (plus large que
  haute) s'affiche seule ; décalage d'une page au choix, retenu par livre.
- **Zones de toucher** au choix (L, bords, Kindle, désactivées) ; touches de volume en option.
- **Filtres** : luminosité, mode nuit, niveaux de gris.
- **Netteté** : les shaders Anime4K (MIT, déjà embarqués pour l'anime) réécrits en
  `FragmentShader` Flutter, préréglages Désactivé · Rapide · Qualité. Calculée **une fois par
  page** puis gardée en image : le défilement n'en paie pas le coût. « Rapide » sur Android
  seulement si le spike tient le seuil.
- **Images** :
  - servies par le proxy local de `stream` (surface d'attaque §2) : Flutter ne charge que
    `127.0.0.1`, avec le jeton de la session de lecture ; en ligne, cache et téléchargé
    passent par le même chemin ;
  - taille plafonnée avant décodage ; désembrouillage en Rust ;
  - AVIF et JPEG XL transcodés en Rust (rav1d, jxl-oxide) si Flutter ne les lit pas sur la
    plateforme (§11.1) ;
  - une image plus haute que 4096 px coupée en bandes en Rust ;
  - `size` du `record page` utilisé pour réserver la place avant le chargement (pas de saut en
    webtoon).
- **Mode économie** (addendum §7) : `low` quand il existe, préchargement réduit à 2 pages.
- **Page de transition** entre chapitres : « Fin du chapitre 87 · Chapitre 88 », avec le
  groupe et un avertissement si des numéros manquent.
- **PDF** : `hayro` rend chaque page en image, redessinée à la résolution du zoom.

### 6.3 B2, lecture case par case

- Détection en **Rust natif** (pas sous Pulley), sans modèle ML : binarisation, recherche des
  gouttières, découpe récursive (XY-cut), puis contours pour les cases qui touchent le bord.
- Ordre des cases selon le sens de lecture (droite à gauche : de haut à droite vers le bas à
  gauche).
- Un toucher passe à la case suivante par un zoom animé (ressort M3E, à 120 images/s) ; à la
  dernière case, la page suivante. Une page sans découpe fiable se montre entière.
- Calculé pour la page affichée et la suivante, gardé en cache avec la page.
- Accessibilité : « Case 3 sur 6 » annoncé par TalkBack et VoiceOver.

### 6.4 B3, mode liseuse

- Noir et blanc, **aucune animation** (transitions coupées, ressorts remplacés par des
  changements nets), contrastes renforcés.
- Touches de volume pour tourner les pages.
- **Rafraîchissement complet** : un flash noir puis blanc plein écran toutes les N pages
  (1 par défaut), durée réglable, la technique de Mihon (« Flash on page change »).
- Proposé seul quand l'appareil est une liseuse connue (fabricant Onyx, Boox, PocketBook,
  Meebook…) ; toujours disponible dans les réglages.

### 6.5 Défilement webtoon automatique

- Vitesse réglable ; un toucher met en pause, un autre reprend.
- **Au tempo** : la vitesse suit le BPM du titre en cours dans la session musique. Un temps =
  N pixels (réglable). Le BPM vient de la capacité `music.tempo` (le plugin Deezer, champ
  `bpm` gratuit de son API). Au changement de titre, la vitesse change en douceur (ressort) ;
  sans BPM connu ou sans musique, c'est la vitesse réglée.

### 6.6 Texte (EPUB, MOBI, AZW3, FB2, romans web)

**Rust lit, Flutter met en page.**

- **Rust** :
  - XHTML lu par `html5ever` (le parseur de Servo, qui tolère les fichiers mal formés) ;
    CSS par `cssparser`, réduit à un sous-ensemble : polices, tailles, graisse, style,
    alignement, retrait, marges, interligne, `display`, sauts de page, `writing-mode`,
    `text-combine-upright`, couleurs (ignorées par les thèmes sombres), images, listes,
    tableaux simples, ruby ;
  - sortie : un **arbre de blocs** par fichier du spine (paragraphes avec leurs plages
    stylées, titres, images, séparateurs, notes, ruby, tableaux), envoyé à Dart par le pont ;
  - MOBI, AZW3, FB2 et le `text` des sources produisent le même arbre ;
  - **césure** : `hyphenation` (motifs de Liang par langue) insère des césures
    conditionnelles (U+00AD) ;
  - **recherche dans le livre**, sur le texte de l'arbre ;
  - **SVG** (couvertures, illustrations) : rendu en image par `resvg` (Rust pur) dans
    `stream`, taille plafonnée, sans ressource externe ;
  - **polices embarquées** : vérifiées par `read-fonts` (Rust) avant d'être données à
    Flutter ; une police refusée → la police par défaut.
- **Flutter** :
  - pagination ligne à ligne (`TextPainter`), ou défilement ; deux colonnes sur grand
    écran ;
  - tourner la page : glissé suivi au doigt, ressort M3E, 120 images/s ;
  - réglages : police (celle du livre, Literata, Atkinson Hyperlegible, celle du système),
    taille, interligne, marges, justification, césure, thèmes (clair, sépia, sombre, noir,
    celui de l'app). Globaux, et **un livre peut les remplacer** (« Pour ce livre seulement ») ;
  - table des matières, signets, **surlignages** avec note (`book_highlights`), notes de bas
    de page dans une bulle ;
  - sélection : copier, surligner, et le menu du système pour le dictionnaire et la
    traduction (`PROCESS_TEXT` sur Android, « Rechercher » sur macOS) ;
  - lien interne → la cible ; lien externe → son URL affichée et une confirmation avant le
    navigateur (surface d'attaque §6) ;
  - **temps restant** : « ≈ 8 min dans ce chapitre », calculé en local sur ta vitesse de
    lecture (`plays`) ;
  - accessibilité : TalkBack et VoiceOver lisent le texte de la page affichée ; la taille du
    texte suit aussi le réglage du système.

### 6.7 Écriture verticale

Pour les EPUB en `writing-mode: vertical-rl` (light novels japonais), une mise en page propre
en Dart, dans le même lecteur :

- colonnes de droite à gauche, un glyphe par cellule, avec la variante verticale de la police
  (`FontFeature('vert')`) ;
- latin et chiffres longs tournés de 90° ; chiffres courts droits (`text-combine-upright`,
  tate-chū-yoko) ;
- ruby (furigana) à droite de la colonne ;
- pagination et tourner la page de gauche à droite.

### 6.8 Lecture à voix haute

- Voix du système : `TextToSpeech` (Android), `AVSpeechSynthesizer` (macOS), par un canal de
  plateforme ; langue du livre, vitesse réglable.
- La phrase lue est surlignée et la page suit. Continue écran éteint (service `mediaPlayback`
  Android), avec sa notification ; la minuterie commune (addendum §5.1) l'arrête.
- Pendant qu'elle parle, la musique **baisse sans s'arrêter** (atténuation), puis remonte.
- Textes seulement (EPUB, MOBI, AZW3, FB2, romans web).

### 6.9 Desktop

`/read` occupe toute la fenêtre ; double page par défaut ; ← → et Espace, molette en défilant,
F plein écran, ⌘F recherche dans le livre, B case par case, [ ] taille du texte. Les
raccourcis visent le lecteur quand il a le focus (addendum §5.3).

## 7. Téléchargements

- `download(chapter)` → `source.content` :
  - `pages` → toutes les pages (désembrouillées) écrites dans un **CBZ** avec un
    `ComicInfo.xml` (série, numéro, tome, titre, groupe, auteurs) ;
  - `text` → un **EPUB minimal** écrit en Rust (le XHTML, ses images) ;
  - `file` → le fichier tel quel.
- Les fichiers restent lisibles par n'importe quelle autre app.
- Emplacement : `downloads/books/<livre>/<chapitre>.cbz` (ou `.epub`, ou le format d'origine),
  dans l'espace de l'app.
- Vérification : nombre de pages et tailles ; une page ratée est retentée 3 fois, puis le
  chapitre passe en erreur avec « Réessayer ».
- **Cache des pages lues en ligne** : 500 Mio par défaut (réglable), les moins récemment lues
  évincées d'abord, compté dans le budget de stockage unique (addendum §7), vidable dans
  Réglages › Téléchargements.
- Même service (`dataSync`), même page Téléchargements, même budget de stockage. « Pour le
  trajet » : les 3 chapitres suivants des livres en cours. Supprimer automatiquement un
  chapitre lu (option, après 24 h).

## 8. « C'est quoi ? », mode Montrer

L'écran et les règles de l'addendum §6 bis ; le domaine fournit :

- **`books.identify`** par SauceNAO, sans clé, dans le quota anonyme ; en parallèle de
  `anime.identify` (trace.moe). Le spike vérifie que ce quota existe toujours ; sinon la
  capacité vient d'un feed tiers.
- Le résultat se rattache par l'id MangaUpdates ou AniList renvoyé, sinon par le titre (§3.3),
  et ouvre le chapitre à la page trouvée quand elle est connue.
- **Code-barres** : un ISBN visible dans le viseur est décodé **sur l'appareil** (`rxing`,
  Rust) → `catalog.by-isbn` (Open Library) → la page du livre. L'image n'est pas envoyée.
- Le résultat rejoint « Reconnus ».

## 9. Erreurs, hors ligne, vie privée

- Erreurs typées du socle §6 ; messages selon `docs/voice.md` (« Cette source ne trouve pas le
  chapitre 87. Essaie une autre source. »).
- Hors ligne : bibliothèque, historique, progression, fichiers de l'appareil et chapitres
  téléchargés restent là ; Parcourir, Nouveautés (rafraîchir) et la lecture en ligne affichent
  le message hors ligne. Les mises à jour du tracker attendent.
- Télémétrie (socle §7) : ni titre, ni chapitre, ni source, ni fichier dans les événements ;
  les mesures seulement (toucher → première page, durée de `content`, temps de pagination,
  échecs de correspondance).
- Lecture privée : §6.1. Sauvegarde : `book_highlights` et les colonnes ajoutées en font
  partie (addendum §7 bis) ; les identifiants OPDS non.

## 10. Tests

- **Rust** : correspondance (titres, auteurs, one-shots, versions couleur, « Hors série »),
  identifiants directs (ISBN, `ComicInfo.xml`, ids de tracker), groupe préféré et « Autres
  versions », doublons et `merged_into`, `progress` et `locator` (position retrouvée après un
  changement de taille), chapitre lu, file du tracker, mise à jour maline, désembrouillage
  (tuiles, XOR), découpe des images hautes, arbre de blocs (EPUB, MOBI, AZW3, FB2), césure,
  recherche, B2 (XY-cut), langues des chapitres, éviction du cache, `remote-progress` (la plus
  avancée gagne, file hors ligne), export des notes, imports Mihon, SY, Aniyomi, Calibre, `replaces-mihon`, migration en
  masse, CBZ et EPUB écrits relus par nos propres lecteurs.
- **Fuzzing** (`cargo-fuzz`) de chaque parseur de contenu non fiable : EPUB / XHTML / CSS,
  MOBI, AZW3, FB2, CBZ, CB7, CBR, PDF (`hayro`), SVG (`resvg`), `.tachibk`, `ComicInfo.xml`, `metadata.db`,
  polices, images (transcodage). En CI chaque nuit ; un plantage ou un dépassement de mémoire
  bloque la release.
- **Corpus en tests dorés** : les EPUB du spike (ou leurs extraits libres de droits) et les
  300 pages de cases deviennent des tests de non-régression (mise en page, découpe).
- **`plugin-host`** : `credentials` (le mot de passe n'atteint jamais le composant ; refusé
  hors du domaine saisi), `user-domains` (adresse locale permise seulement si saisie, refusée
  par redirection), images d'un `text` hors des domaines refusées.
- **Plugins** (feed officiel) : AniList (livres), Open Library, MangaUpdates, OPDS (Gutenberg,
  Standard Ebooks, un Calibre de test), SauceNAO, MyAnimeList, sur réponses enregistrées.
- **Dart** : ligne de chapitre (états), page livre, modes du lecteur, B1 retenu par série,
  case par case, mode liseuse (aucune animation), défilement au tempo, pagination et
  `locator`, écriture verticale (tests dorés), surlignages, tests dorés de la matrice de la
  spec UI §2.8 ; performance : temps d'image au 99ᵉ centile sur les scénarios du spike
  (`integration_test`), en CI sur l'appareil de Firebase Test Lab.
- **Natif** : synthèse vocale écran éteint, ouverture d'un fichier partagé, glisser-déposer
  macOS.

## 11. Ordre de travail

### 11.1 Étape 1 : spike de faisabilité (avant tout code livres)

Une app de sonde Flutter jetable et une sonde Rust. **Ordre : le plus risqué d'abord** —
texte vertical et webtoon à 120, puis les sources Mihon en WASM, puis le reste.

**Appareils.** Le Xiaomi 14 (Snapdragon 8 Gen 3, 120 Hz) tient trop facilement : les seuils y
sont donc **à moitié du budget**. Un appareil d'entrée de gamme réel (60 ou 90 Hz, 4 Gio de
mémoire) est mesuré dans le quota gratuit de **Firebase Test Lab** : aucune image perdue à sa
fréquence, mémoire sous les mêmes plafonds. macOS : un Mac à 120 Hz (ProMotion).

**Images par seconde** : temps d'image (construction + rastérisation) au 99ᵉ centile,
**≤ 4,2 ms** sur le Xiaomi 14, aucune image perdue sur 60 s, sur chaque scénario marqué 120.
**Mémoire** : PSS de toute l'app.

| Mesure | Seuil (Xiaomi 14) | Si ça casse |
|---|---|---|
| Texte vertical (`vert`, ruby, tate-chū-yoko) sur 5 light novels | identique à Apple Books ; tourner la page à 120 | Paragraphes verticaux mis en page en Rust (`parley`), peints par Flutter |
| Webtoon : 60 images jusqu'à 800×30 000 px, défilement manuel puis automatique | 120 ; PSS ≤ 200 Mio | Bandes de 2048 px, préchargement réduit, images hors écran libérées plus tôt |
| Les 20 sources Mihon les plus installées, en WASM avec le SDK seul (désembrouillage compris) | ≥ 18 sur 20 | Option `js` du SDK (Boa), mesurée comme dans la spec anime §10.1 |
| EPUB natif sur 60 fichiers (Standard Ebooks, Gutenberg, commerciaux sans DRM, EPUB 2 mal formés, les 5 verticaux) | ≥ 57 sur 60 sans perte de texte, mise en forme juste (titres, italiques, images, notes) | Sous-ensemble CSS élargi d'après les échecs ; sinon mise en page entière en Rust (`parley` + `taffy`), Flutter ne fait que peindre |
| Repagination d'un chapitre de 50 000 caractères après un changement de taille | ≤ 100 ms | Pagination progressive : pages autour de la position d'abord, le reste en arrière-plan |
| Tourner une page (images et texte), zoom du case par case | 120 | Pages voisines prérastérisées |
| Ouverture d'un EPUB de 5 Mio ; d'un CBZ de 200 Mio | première page ≤ 250 ms ; ≤ 150 ms (index lu sans tout décompresser) | Arbre de blocs du premier fichier du spine d'abord |
| Lecteur de texte ouvert sur un EPUB de 5 Mio | PSS ≤ 150 Mio | Arbres de blocs gardés pour 3 fichiers du spine au plus |
| Césure conditionnelle (U+00AD) honorée par Flutter, tiret affiché | FR et EN | Coupure faite par notre mise en page Dart |
| AVIF, JPEG XL, WebP animé lus par Flutter sur Android et macOS | liste de ce qui passe | Transcodage en Rust (`rav1d`, `jxl-oxide`) |
| B2 sur 300 pages (manga, comics, manhwa) | ≥ 85 % bien découpées ; ≤ 40 ms par page | Contours en plus du XY-cut ; page sous le seuil montrée entière |
| Netteté Anime4K sur une page de 1500 px, une fois par page | ≤ 15 ms ; défilement toujours à 120 | « Rapide » sur desktop seulement |
| `hayro` sur 30 PDF (scans, texte, BD) | ≥ 28 sur 30 ; ≤ 150 ms par page | PDF retiré ; pas de pdfium sans l'accord de l'utilisateur |
| `mobi` sur 20 MOBI et AZW3 sans DRM | 20 sur 20 | Lecteur KF8 écrit par nous (HTML dans un conteneur PalmDB) |
| Décodeur RAR en Rust pur, RAR4 et RAR5, 20 CBR | 20 sur 20 | CBR refusé : « Convertis-le en CBZ » |
| SVG de 50 EPUB réels par `resvg` | rendu juste ≥ 48 sur 50, ≤ 30 ms | Les SVG non rendus remplacés par leur texte alternatif |
| Polices embarquées vérifiées par `read-fonts`, 50 polices réelles | aucune refusée à tort | Liste des tables vérifiées réduite |
| Fuzzing : 1 h par parseur (§10) | aucun plantage, aucun dépassement de mémoire | Correctif avant toute suite ; le parseur fautif est remplacé s'il ne tient pas |
| SauceNAO sans clé | quota anonyme encore ouvert, ≥ 50 recherches par jour | Capacité fournie par un feed tiers |
| MangaUpdates (`releases`) et Open Library (`by-isbn`) sans clé | réponses complètes, limites de débit notées dans les manifestes | `releases` remplacé par la vérification complète, chaque jour |
| OPDS de Project Gutenberg et Standard Ebooks | flux publics encore ouverts sans compte | Le préréglage concerné est retiré |
| Import de vraies sauvegardes Mihon, SY et Aniyomi (1 000 séries) | ≤ 5 s, rien de perdu | Import en arrière-plan, avec sa progression affichée |
| Voix haute : 30 min écran éteint, surlignage synchronisé, musique atténuée puis remontée | sans coupure | Surlignage par phrase seulement |
| Batterie, 1 h | EPUB ≤ 3 % ; webtoon en défilement automatique à 120 Hz ≤ 6 % | Le mode économie demande 60 Hz au système (`setFrameRate`) |
| Accessibilité : TalkBack et VoiceOver sur une page EPUB et en case par case | texte lu, « Case 3 sur 6 » annoncé | Nœuds de sémantique construits depuis l'arbre de blocs |
| Taille ajoutée par le domaine (`hayro`, `html5ever`, `rxing`, `jxl-oxide`, `rav1d`, `mobi`…), arm64 | ≤ +6 Mio | `rav1d` retiré si Flutter lit déjà l'AVIF |
| Mode liseuse | pas d'appareil e-ink : flash de Mihon, réglable | Mesure par un testeur de la communauté avant la release |

Le rapport va dans `docs/superpowers/reports/`, comme ceux de la musique et de l'anime.

### 11.2 Ensuite

1. Ajouts au socle (§2) : `locator` (`progress`, `bookmarks`), `book_highlights`, `credentials`, `user-domains`,
   `replaces-mihon`, pages dans le proxy de `stream`, `music.tempo`.
2. Contrat `vehicoule:books`, plugins du feed officiel (AniList livres, Open Library,
   MangaUpdates, OPDS, SauceNAO ; MyAnimeList livres).
3. Bibliothèque : correspondance, fichiers de l'appareil, imports, migration, mise à jour
   maline.
4. Lecteur d'images (modes, B1, B2, B3, webtoon, netteté), puis lecteur de texte (arbre de
   blocs, pagination, vertical, voix haute).
5. Écrans, puis téléchargements.
6. Validation : les critères du §1.

## 12. Ce que cette spec change dans les autres specs

| Spec | Devient |
|---|---|
| Addendum §5.1 : « Lire un livre ne joue rien : la musique continue » | Sauf la lecture à voix haute, qui atténue la musique pendant qu'elle parle (§6.8) |
| Addendum §6 : `continues-at` | Fournie par `books.catalog.relations` (plugin tiers) ou saisie par l'utilisateur ; champs `after-episode` et `at-chapter` (§4.1) |
| Addendum §13 : B1, B2, B3, défilement au tempo | §6.2 à §6.5 |
| Spec anime §3.2 : `progress`, `bookmarks` | + colonne `locator` (nullable) |
| Spec anime §4.1 : plugin AniList | Un seul plugin AniList exporte `vehicoule:anime`, `vehicoule:books` et le tracker |
| Spec anime §4.5 : `vehicoule:host` 1.1.0 | + interface `credentials` (§4.5) |
| Socle §4.3 : manifeste | + `replaces-mihon` (liste d'ids de sources Mihon), + `user-domains` (§4.3) |
| Contrat `vehicoule:music` | + capacité `tempo(track) -> option<f32>` (mineure), plugin Deezer |
| Surface d'attaque §7.1 : dépendances prévues | + `html5ever`, `cssparser`, `hyphenation`, `read-fonts`, `zip`, `sevenz-rust`, `hayro`, `resvg`, `mobi`, `rxing`, `jxl-oxide`, `rav1d` (tous Rust), décodeur RAR Rust si le spike le valide ; `cargo-fuzz` en CI |

## 13. Ce que cette spec ne couvre pas

- Les sources de scans et de romans web : plugins tiers, hors des dépôts Vehicoule, comme
  `vehicoule-ytmusic` et les sources anime.
- Les fichiers avec DRM : jamais lus (refus avec la raison).
