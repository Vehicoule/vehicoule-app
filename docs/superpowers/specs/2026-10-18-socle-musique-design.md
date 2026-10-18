# Vehicoule — Socle + Musique v1 : design

Date : 2026-10-18 · Statut : en relecture (v2, après revue externe)

## 1. But et contexte

Vehicoule est une app 3-en-1 — musique, anime, ebooks/mangas — qui doit tourner partout et
tenir dans le temps. Distribution visée : open source hors stores (APK, DMG…) avec une
communauté de plugins ; une version stores officiels reste possible plus tard.

Cette spec couvre **le socle** (cœur, plugins, bibliothèque, lecteur, deux coques) et **le
premier domaine branché dessus : la musique**. L'anime et les livres auront chacun leur spec.

### Ce qui est décidé

| Sujet | Décision |
|---|---|
| UI | Flutter, deux coques (mobile, desktop) qui partagent écrans et composants |
| Cœur | Rust : il possède l'état et les règles. Dart affiche et exécute |
| Pont | `flutter_rust_bridge` |
| Plugins | Composants WASM (WIT), Wasmtime + Pulley ; repli prévu sur Wasmi + JSON (section 4.2 bis) |
| Lecture | `media_kit` (vidéo et audio) + `audio_service` (écran verrouillé, service d'arrière-plan). `just_audio` seulement si un problème est mesuré |
| Design | Material 3 officiel + nos tokens réglés sur M3E ; `material_3_expressive` seulement pour les composants manquants, derrière `app/lib/design/` |
| Métadonnées | Deezer en principal ; iTunes puis Cover Art Archive en repli pour les pochettes ; YouTube Music pour la lecture et en dernier recours |
| Paroles | LRCLIB |
| Langues | Français et anglais dès le départ (`gen-l10n` de Flutter) |
| Plateformes v1 | Android + macOS |
| Code hérité | Aucun. Les anciens projets (Auqw, Klaxon) inspirent, rien n'est porté ni compatible |

### Périmètre fonctionnel v1

- Chercher (avec suggestions), lire, file d'attente.
- **Enchaînement sans trou perceptible** entre les pistes (préchargement de la suivante).
- **Radio en fin de file** : la lecture continue sur des titres proches, désactivable.
- Likes, bibliothèque, playlists perso, pages album / artiste / playlist.
- **Import** : copier une playlist publique Deezer ou YouTube Music (coller son lien) dans
  ses playlists.
- **Historique d'écoute**, enregistré dès le premier jour.
- **Accueil** construit sur les données locales : récemment écoutés, likes, playlists,
  téléchargements.
- Contrôles écran verrouillé, téléchargements hors ligne (y compris app en arrière-plan sur
  Android), paroles simples et synchronisées, normalisation du volume.
- **Premier lancement** guidé (section 4.6).

### Critères de réussite

1. L'app sert de lecteur de musique au quotidien sur Android et macOS pendant deux semaines
   sans retour à une autre app.
2. Moins de 2 s entre le tap et le premier son pour un titre non préchargé, sur une
   connexion correcte.
3. Plus de 95 % de bonnes correspondances YouTube Music sur un corpus d'environ 100 titres
   Deezer dont le `videoId` attendu est connu (section 3.3).
4. Une heure de lecture écran éteint sur Android sans coupure.

## 2. Structure du dépôt

```
vehicoule/
├── core/                     espace de travail Cargo
│   ├── contract/             fichiers WIT du contrat + bindings hôte générés
│   ├── plugin-host/          hôte Wasmtime + Pulley, budgets, domaines autorisés, signatures, feeds
│   ├── stream/               téléchargements par morceaux avec reprise, cache des pochettes
│   └── core/                 bibliothèque SQLite, règles musique, façade Dart
├── app/                      Flutter
│   └── lib/
│       ├── bridge/           code généré par flutter_rust_bridge (jamais modifié à la main)
│       ├── design/           tokens + nos composants (seul endroit qui importe material_3_expressive)
│       ├── l10n/             traductions FR / EN
│       ├── platform/         lecteur (media_kit), écran verrouillé (audio_service), services Android, chemins
│       ├── features/music/   écrans et widgets partagés par les deux coques
│       ├── shell_mobile/     navigation et mise en page mobile
│       └── shell_desktop/    navigation et mise en page desktop
└── sdk/                      crate Rust guest (bindings wit-bindgen + aides) + doc ; dépend de contract
```

Trois dépôts dès le départ :

| Dépôt | Contenu |
|---|---|
| `vehicoule` | l'app, le cœur, `contract` et `sdk` |
| `vehicoule-plugins` | le feed officiel : deezer, itunes, lrclib |
| `vehicoule-ytmusic` | le plugin ytmusic, son feed, le corpus de correspondance |

- Les deux dépôts de plugins dépendent de `contract` et `sdk` par une dépendance Git épinglée
  sur un tag de `vehicoule`. Un changement de contrat = un tag, puis une montée de version
  dans chaque dépôt de plugins. Ils consomment le SDK exactement comme un tiers.
- **ytmusic n'est jamais avec les plugins légitimes** : une demande de retrait sur son dépôt
  n'emporte ni l'app ni le feed officiel. L'utilisateur ajoute ce dépôt lui-même (la leçon de
  Tachiyomi).

Règles :

- Dart n'appelle que la façade de `core`. `plugin-host` n'est jamais exposé.
- `contract` est la seule source de vérité du contrat : les fichiers WIT. L'hôte, le SDK et
  les bindings des autres langages en dérivent.
- On pose dès le départ la structure finale connue : `plugin-host` (retirable pour la version
  stores) et `stream` (téléchargements, cache, plus tard serveur local) sont des crates.
- Les coques ne diffèrent que par la navigation, la mise en page et le comportement (survol,
  clavier, barre de titre macOS). Aucun écran n'est écrit deux fois.
- Les écrans n'importent jamais `material` ou `material_3_expressive` pour un composant que
  `design/` fournit.

## 3. Flux de données

### 3.1 Lecture

```
 Flutter (vue + adaptateurs)                 Rust core (état + décisions)
 tap sur un titre ──── play(titre, contexte) ──▶ file mise à jour → flux QueueState
                                                ├─ téléchargé ? → chemin local
                                                └─ sinon → music.resolve (section 3.3)
 Lecteur (media_kit) ◀── PlayCommand{source, position}
                     ◀── EnqueueNext{source}   (pré-résolution ~20 s avant la fin)
                     ◀── ReplaceNext / ClearNext (la file a changé)
        └── PlayerEvent (début de piste, fin, erreur, seek, position toutes les ~10 s) ──▶
 Écran verrouillé (audio_service) ◀── flux NowPlaying (métadonnées + pochette en cache)
        └── lecture / pause / suivant ──▶ mêmes commandes que l'UI
```

- **Rust décide, Dart exécute.** Le lecteur Dart ne choisit jamais la piste suivante : il
  joue ce que Rust a poussé dans sa playlist.
- **Préchargement** : à la pré-résolution, Rust pousse la piste suivante dans la playlist de
  `media_kit` pour que mpv la précharge. Résultat visé : pas de trou perceptible. Le vrai
  gapless d'album (zéro échantillon de silence) dépend du remplissage d'encodeur des fichiers
  source et n'est pas garanti avec les flux YouTube.
- **Position** : l'UI et les paroles lisent la position côté Dart, directement dans le
  lecteur. Rust ne reçoit que les événements utiles, plus une position toutes les ~10 s pour
  reprendre la lecture et compter l'historique.
- **Normalisation du volume** : si `music.resolve` renvoie `loudness_db`, Dart ajuste le gain
  du lecteur. Désactivable.
- **Pas de serveur local en v1** : `media_kit` reçoit directement l'URL et les en-têtes.

### 3.2 Fin de file, accueil, import

- **Radio** : quand la file se termine, `core` appelle `music.radio` (graine = dernier titre)
  et ajoute des titres. Sources : Deezer (radio d'artiste, artistes proches) ; YouTube Music
  (« à suivre ») en repli. Activée par défaut.
- **Accueil** : uniquement des données locales (historique, likes, playlists,
  téléchargements). Pas de flux éditorial en v1.
- **Import** : l'utilisateur colle le lien d'une playlist publique ; `core` appelle
  `music.entity` et crée une copie locale.

### 3.3 Correspondance avec YouTube Music

YouTube Music n'expose presque jamais l'ISRC : la correspondance repose en pratique sur titre,
artiste et durée.

1. Si `external_refs` contient déjà un `videoId` pour ce titre → l'utiliser directement.
2. Sinon, recherche YouTube Music avec « artiste titre ».
3. Score de chaque résultat :
   - préférer les résultats de type « song » (piste audio) aux clips vidéo ;
   - durée dans ±3 s de la durée Deezer, sinon fortement pénalisé ;
   - titre et artiste normalisés (casse, accents, « feat. », contenu entre parenthèses)
     comparés par similarité ;
   - pénaliser « live », « remix », « cover », « sped up », « instrumental » sauf si le
     titre Deezer les contient.
4. Meilleur score au-dessus du seuil → `videoId` enregistré dans `external_refs`. En dessous
   → erreur `not-found`.
5. **Correction manuelle** : « ce n'est pas le bon morceau » propose les autres candidats ;
   le choix est enregistré et prioritaire pour toujours.

Le corpus d'environ 100 titres Deezer avec leur `videoId` attendu vit dans le dépôt
`vehicoule-ytmusic` et sert de test réel.

### 3.4 Téléchargements et paroles

- `download(titre)` → résolution → crate `stream` : récupération par morceaux avec reprise →
  vérification de taille → pochette en cache → marqué téléchargé. Le fichier local passe
  toujours en premier à la lecture.
- **Android** : les téléchargements tournent dans un service de premier plan de type
  `dataSync`, avec une notification de progression, pour survivre à l'app en arrière-plan.
  Le service de lecture d'`audio_service` est déclaré de type `mediaPlayback` (Android 14+).
- **Paroles** : `music.lyrics` (titre, artiste, album, durée) → stockées en base. Les lignes
  synchronisées sont horodatées, Dart surligne selon la position.

### 3.5 Pont Rust ↔ Dart

- **Commandes** asynchrones : `play`, `enqueue`, `search`, `suggest`, `entity`, `like`,
  `import_playlist`, `download`, `lyrics`, `fix_match`…
- **Flux d'état complets** pour les petits états : `QueueState`, `NowPlaying`.
- **Bibliothèque** : requêtes paginées, plus un événement `LibraryChanged{quoi}` pour que
  l'UI recharge ce qui est visible.
- **Téléchargements** : progression limitée à ~2 envois par seconde.

## 4. Plugins

### 4.1 Exécution : modèle de composants WASM

- Les plugins sont des **composants WASM** décrits en **WIT**. Moteur : **Wasmtime** avec son
  interpréteur **Pulley** sur toutes les plateformes. Un seul comportement partout, et c'est
  compatible iOS (pas de compilation à la volée vers du code natif).
- Le `.wasm` est compilé en bytecode Pulley **sur l'appareil**, une fois, puis gardé en
  cache. On ne charge jamais d'artefact précompilé venu d'un feed : désérialiser du code
  précompilé non fiable n'est pas sûr.
- Chaque appel crée une **instance neuve**. Budgets : *fuel* (budget d'instructions),
  *epoch interruption* (30 s maximum), `StoreLimits` (64 Mo de mémoire), plafonds de nombre
  d'appels HTTP et d'octets échangés.
- **Les plugins importent des interfaces de l'hôte** et les appellent comme des fonctions
  normales. Côté hôte, elles sont asynchrones (support async de Wasmtime) : un plugin qui
  attend une réponse HTTP ne bloque pas de thread.
- Interfaces de l'hôte : `http` (requête simple ou lot de 8), `kv` (espace par plugin),
  `clock`, `log`. Plus un **sous-ensemble de WASI sans fichiers ni réseau** (horloges, aléa,
  sortie standard redirigée vers `log`), pour que les chaînes de compilation non Rust
  fonctionnent.
- **Multi-langages** : `wit-bindgen` et les outils de la Bytecode Alliance génèrent les
  bindings guest pour Rust, C/C++, Go, JS, Python… Pas de SDK maison à maintenir par langage.
- **SDK Rust** : bindings générés + aides au parsing typé des réponses des fournisseurs (le
  JSON en arbre générique coûte cher en *fuel*).

### 4.2 Le contrat en WIT

- Paquets versionnés : `vehicoule:host@1.0.0` (interfaces importées) et
  `vehicoule:music@1.0.0` (interfaces exportées). Plus tard `vehicoule:anime`,
  `vehicoule:books`.
- Chaque capacité est **une interface exportée** : `search`, `suggest`, `entity` (album,
  artiste, playlist), `resolve` (URL, en-têtes, expiration, candidats, `loudness-db`
  optionnel), `lyrics`, `radio`. Un plugin n'exporte que ce qu'il implémente ; l'hôte lit
  les exports pour savoir ce qu'il sait faire.
- Les données sont des `record` et des `variant` WIT, pas du JSON : les erreurs sont typées
  dès le plugin.
- Les pochettes sont des champs des entités ; le repli entre sources est géré par le cœur.
- La crate `contract` contient les fichiers WIT (seule source de vérité) et les bindings hôte
  générés (`wasmtime::component::bindgen!`).

### 4.2 bis Repli si le modèle de composants ne tient pas

Si l'étape 1 (section 9) montre que Wasmtime + Pulley ne convient pas sur Android (budgets
inopérants, async cassé, binaire trop lourd), on revient au contrat déjà conçu : modules
WASM sans import sur **Wasmi**, dialogue par messages JSON étape par étape (`alloc` /
`handle`), mêmes services, mêmes capacités, SDK Rust qui cache la machine à étapes derrière
une API async. Le reste de la spec ne change pas.

### 4.3 Manifeste et sécurité réseau

- Le manifeste déclare id, version, version du contrat et domaines autorisés (les capacités se lisent dans les exports du composant),
  jokers acceptés (`*.googlevideo.com`). Pas de champ `permissions` tant qu'aucune
  permission n'existe.
- La liste des domaines est vérifiée **à chaque redirection** et pour toute URL renvoyée par
  le plugin (pochettes comprises).
- Les adresses IP privées, locales et de bouclage sont refusées après résolution DNS, même
  pour un domaine autorisé (protection contre le DNS rebinding).
- Toutes ces vérifications vivent dans l'implémentation hôte de l'interface `http` : le
  plugin n'a aucun autre accès au réseau.
- Compatibilité : même version majeure des paquets WIT, mineure ≤ celle de l'hôte.

### 4.4 Distribution

- Chaque feed est un `feed.json` signé ed25519 : **numéro de séquence croissant**, puis pour
  chaque plugin id, version, contrat, sha256 du `.wasm` et du manifeste.
- L'app retient la dernière séquence vue par feed et **refuse un feed plus ancien** (pas de
  retour forcé vers une version vulnérable).
- **Deux clés publiques** embarquées pour le feed officiel, pour pouvoir changer de clé sans
  mise à jour d'urgence.
- Vérification en arrière-plan, jamais au démarrage ; un cache valide est chargé en attendant.
- **Feed officiel** (préconfiguré, publié par `vehicoule-plugins`) : deezer, itunes, lrclib.
- **Feeds tiers** (dont `vehicoule-ytmusic`) : l'utilisateur ajoute une URL + une clé
  publique ; l'app affiche l'empreinte, les domaines déclarés, et demande l'accord avant
  installation.

### 4.5 Plan B si YouTube impose du JavaScript

Si la signature `n` ou les jetons PO exigent d'exécuter le JavaScript du lecteur YouTube, un
moteur JS compilé en WASM et interprété par Pulley sera trop lent. Plan prévu : une
interface hôte `js` (QuickJS natif, sans compilation à la volée), ajoutée comme version
mineure de `vehicoule:host`. Non construite en v1.

Aujourd'hui, la lecture fonctionne sans OAuth avec la bonne configuration de client (validé
dans Auqw). Quand YouTube change sa détection, une nouvelle version du plugin suffit.

### 4.6 Premier lancement

1. Écran d'accueil : ce qu'est l'app, et le fait qu'elle est livrée sans source de streaming.
2. Le feed officiel (deezer, itunes, lrclib) est installé : recherche, pages et paroles
   fonctionnent tout de suite.
3. Écran « Ajouter un dépôt » : coller une URL + une clé publique, voir l'empreinte et les
   domaines, accepter. Accessible ensuite depuis les réglages.
4. Tant qu'aucun plugin ne fournit `music.resolve`, le bouton lecture explique pourquoi et
   renvoie vers cet écran.

## 5. Bibliothèque

SQLite via rusqlite dans `core`. Migrations = fichiers SQL numérotés, version suivie par
`PRAGMA user_version`.

Tables :

- `recordings` (titre, artistes, album, durée, ISRC), `external_refs` (fournisseur + id
  externe → recording, avec un drapeau « fixé à la main »), `entities` (cache albums /
  artistes / playlists).
- `likes`, `playlists`, `playlist_items`, `downloads`, `lyrics`, `plugin_kv`,
  `search_history`.
- `plays` (historique) : recording, début, durée écoutée, source, appareil.
- `settings_device` (dossier de téléchargement, qualité, tout ce qui est propre à
  l'appareil) et `settings_shared` (ce qui doit suivre l'utilisateur).

Règles :

- **Les données de l'utilisateur ne dépendent jamais d'un fournisseur.** Likes, playlists,
  historique et téléchargements pointent vers l'identité interne et survivent à la
  disparition d'une source. Le cache du catalogue peut être vidé à tout moment.
- **Identifiants UUIDv7 partout**, `recordings` compris : deux appareils ne génèrent jamais
  le même id.
- **Prête pour la synchro** (non livrée en v1, sans migration le jour venu) :
  - `recordings`, `likes`, `playlists`, `playlist_items`, `plays` et `settings_shared`
    portent `updated_at`, `device_id` et `deleted_at` (suppression logique) ;
  - `updated_at` est une **horloge logique hybride** (HLC) encodée en entier 64 bits, pas
    l'heure murale : l'ordre reste correct même si l'horloge d'un appareil dérive. Les
    égalités se départagent par `device_id` ;
  - l'ordre dans `playlist_items` est une **clé d'ordre fractionnaire** (une chaîne qu'on
    peut toujours insérer entre deux autres), pas une position entière ;
  - `recordings` porte `merged_into` (nul par défaut) : quand deux recordings partagent une
    référence externe, la plus récente pointe vers la plus ancienne et toutes les lectures
    suivent ce lien. Utilisé dès la v1 quand une correction manuelle révèle un doublon ; la
    synchro réutilisera le même mécanisme.

## 6. Erreurs

Une enum typée traverse le pont ; l'UI traduit chaque type en message lisible :

| Type | Sens |
|---|---|
| `network` | pas de connexion, délai réseau dépassé |
| `provider-wall` | le fournisseur refuse la session : détection de bot, captcha, IP bloquée |
| `rate-limited` | le fournisseur limite le débit (429 ou équivalent) |
| `budget-exceeded` | le plugin a dépassé un budget (instructions, temps, mémoire, HTTP) |
| `not-found` | rien ne correspond (ou correspondance sous le seuil) |
| `expired` | l'URL de lecture n'est plus valide |
| `internal` | bug de l'hôte ou du plugin |

- Source en échec → candidat suivant ; tous en échec → piste suivante + message discret.
- URL expirée (403) → une seule nouvelle résolution, reprise à la même position.
- Un plugin en échec ne fait jamais planter l'app.
- Écran de diagnostics : logs des plugins, données sensibles masquées.

## 7. Tests

- Rust : tests unitaires de la file, du préchargement, de l'identité, du score de
  correspondance, du routage, du schéma de base, des clés d'ordre fractionnaires.
- `plugin-host` : composants de test `echo` et `spin` (les budgets coupent bien), plus un
  composant écrit dans un autre langage que Rust (preuve du multi-langages) ; tests des domaines
  autorisés (jokers, redirections, IP privées) et du refus d'un feed plus ancien.
- Plugins : réponses HTTP enregistrées, sans réseau en CI. Test réel lancé à la main : le
  corpus de correspondance (critère 3) et la latence du premier son (critère 2).
- Flutter : un test de démarrage par coque (lancer, chercher sur données fictives, lire).
- CI : build et tests Android + macOS ; **compilation seule** pour iOS, Windows et Linux.
- Validation finale : les critères de la section 1.

## 8. Dépendances à surveiller

- `media_kit` et `material_3_expressive` : un seul mainteneur actif chacun (et un compte non
  vérifié pour le second). Versions figées ; on vérifie leur activité avant de commencer et on
  est prêt à les forker. `material_3_expressive` ne s'utilise que derrière `design/`.
- Wasmtime : une version par mois. On suit les **versions LTS** (deux ans de correctifs de
  sécurité) et on monte de version délibérément.

## 9. Ordre de travail

1. **Résolution native d'abord, sans WASM.** La logique `music.resolve` + correspondance de
   ytmusic est écrite comme une bibliothèque Rust ordinaire, derrière une petite interface
   HTTP. On la valide contre le corpus de 100 titres, puis on lit les URLs obtenues avec
   `media_kit` et on tient une heure écran éteint avec `audio_service` sur Android.
   Ce n'est pas du code jetable : le plugin ytmusic enveloppera ensuite cette bibliothèque.
   **Dans la même étape, on valide Wasmtime + Pulley sur Android arm64** avec un composant
   minimal qui importe `http` : le *fuel* et l'*epoch* coupent bien, l'appel HTTP async de
   l'hôte fonctionne, et Wasmtime ajoute **au plus 10 Mo** à l'APK arm64. Sinon → repli de la
   section 4.2 bis.
2. Si ça passe, on construit le socle (contrat, hôte, bibliothèque, flux) puis les écrans.
3. Si ça casse, on le sait avant d'avoir construit le socle.

## 10. Hors v1, et pourquoi ce n'est pas un problème

Chaque élément ci-dessous est **un ajout**, pas une refonte : ce qui serait coûteux à
rattraper est conçu dès maintenant.

| Hors v1 | Ce qui est déjà prévu dans la v1 |
|---|---|
| Synchro entre appareils | UUIDv7, colonnes de synchro, départage par appareil, ordre fractionnaire, réglages séparés |
| Fichiers locaux | Bibliothèque indépendante des fournisseurs ; un fournisseur `local` s'ajoute comme les autres |
| iOS, Windows, Linux | Flutter + Rust déjà multiplateformes ; compilés en CI dès le départ |
| Anime, livres | Hôte de plugins générique, capacités préfixées par domaine |
| Version stores | `plugin-host` est une crate séparée, retirable par une option de compilation |
| Exécution de JavaScript pour YouTube | Interface hôte `js` prévue (section 4.5) |
| Cache des octets pendant la lecture | Crate `stream` en place ; le serveur local s'ajoute sans toucher au reste |
| Accueil éditorial (classements, nouveautés) | Une capacité `music.browse` s'ajoute au contrat |
| CarPlay, Android Auto, Chromecast | `audio_service` + flux `NowPlaying` déjà en place |
