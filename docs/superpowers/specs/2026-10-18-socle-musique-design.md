# Vehicoule — Socle + Musique v1 : design

Date : 2026-10-18 · Statut : en relecture

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
| Plugins | WASM, interprétés par Wasmi |
| Lecture | `media_kit` (vidéo et audio) + `audio_service` (écran verrouillé, service d'arrière-plan). `just_audio` seulement si un problème est mesuré |
| Design | Material 3 officiel + nos tokens réglés sur M3E ; `material_3_expressive` seulement pour les composants manquants, derrière `app/lib/design/` |
| Métadonnées | Deezer en principal ; iTunes puis Cover Art Archive en repli pour les pochettes ; YouTube Music pour la lecture et en dernier recours |
| Paroles | LRCLIB |
| Plateformes v1 | Android + macOS |
| Code hérité | Aucun. Les anciens projets (Auqw, Klaxon) inspirent, rien n'est porté ni compatible |

### Périmètre fonctionnel v1

Chercher (avec suggestions), lire, file d'attente, likes et bibliothèque, playlists perso,
pages album / artiste / playlist, contrôles écran verrouillé, téléchargements hors ligne,
paroles (simples et synchronisées). Sur Android et macOS.

**Critère de réussite :** l'app sert de lecteur de musique au quotidien sur Android et macOS
pendant deux semaines sans retour à une autre app.

## 2. Structure du dépôt

```
vehicoule/
├── core/                     espace de travail Cargo
│   ├── plugin-host/          hôte WASM (Wasmi), contrat, budgets, domaines autorisés, signatures
│   ├── stream/               téléchargements par morceaux avec reprise, cache des pochettes
│   └── core/                 bibliothèque SQLite, règles musique, façade exposée à Dart
├── app/                      Flutter
│   └── lib/
│       ├── bridge/           code généré par flutter_rust_bridge (jamais modifié à la main)
│       ├── design/           tokens + nos composants (seul endroit qui importe material_3_expressive)
│       ├── platform/         lecteur (media_kit), écran verrouillé (audio_service), chemins
│       ├── features/music/   écrans et widgets partagés par les deux coques
│       ├── shell_mobile/     navigation et mise en page mobile
│       └── shell_desktop/    navigation et mise en page desktop
├── sdk/                      contrat des plugins (doc + schémas JSON) + crate Rust guest
└── plugins/                  plugins officiels : deezer, itunes, ytmusic, lrclib
```

Règles :

- Dart n'appelle que la façade de `core`. `plugin-host` et `stream` ne sont jamais exposés.
- Les coques ne diffèrent que par la navigation, la mise en page et le comportement (survol,
  clavier, barre de titre macOS). Aucun écran n'est écrit deux fois.
- Les écrans n'importent jamais `material` ou `material_3_expressive` pour un composant que
  `design/` fournit.
- On découpe une crate quand un module devient trop gros, pas avant.

## 3. Flux de données

```
 Flutter (vue + adaptateurs)                 Rust core (état + décisions)
 tap sur un titre ──── play(titre, contexte) ──▶ file mise à jour → flux QueueState
                                                ├─ téléchargé ? → chemin local
                                                └─ sinon → music.resolve (plugin ytmusic)
                                                     correspondance ISRC, sinon titre+artiste+durée
                                                     → {url, en-têtes, expiration, candidats}
 Lecteur (media_kit) ◀── PlayCommand{url, en-têtes, position}
        └── PlayerEvent (position, chargement, fin, erreur) ──▶ décide la suite
 Écran verrouillé (audio_service) ◀── flux NowPlaying (métadonnées + pochette en cache)
        └── lecture / pause / suivant ──▶ mêmes commandes que l'UI
```

- **Rust décide, Dart exécute.** Le lecteur Dart ne choisit jamais la piste suivante.
- **Pré-résolution** de la piste suivante environ 20 s avant la fin.
- **Pas de serveur local en v1** : `media_kit` reçoit directement l'URL et les en-têtes.
- **Téléchargement** : `download(titre)` → résolution → `stream` récupère par morceaux avec
  reprise → vérification de taille → pochette en cache → marqué téléchargé. Le fichier local
  passe toujours en premier à la lecture.
- **Paroles** : `music.lyrics` (titre, artiste, album, durée) → stockées en base ; les lignes
  synchronisées sont horodatées, Dart surligne selon la position.

### Pont Rust ↔ Dart

- **Commandes** asynchrones : `play`, `enqueue`, `search`, `suggest`, `entity`, `like`,
  `download`, `lyrics`…
- **Flux d'état complets** : `QueueState`, `NowPlaying`, `Downloads`, `Library`. L'état entier
  est renvoyé à chaque changement (pas de différences).

## 4. Plugins

### Exécution

- Wasmi, sans compilation à la volée (compatible iOS plus tard).
- Une **instance neuve par appel**. Budget d'instructions, 30 s maximum, 64 Mo de mémoire,
  plafonds de nombre d'appels HTTP et d'octets échangés.
- **Aucun import** : le plugin exporte `memory`, `alloc(len) -> ptr` et
  `handle(ptr, len) -> u64`. Il dialogue avec l'hôte par messages JSON, une étape à la fois.
  Entre deux étapes, l'hôte fait ses requêtes asynchrones sans bloquer de thread.
- Services de l'hôte : `http` (une requête ou un lot de 8), `kv` (espace par plugin), `now`,
  `log`. Tout nouveau service est un ajout de version mineure.
- Le SDK impose le parsing vers des types précis (le JSON en arbre générique épuise le budget).

### Capacités v1

`music.search`, `music.suggest`, `music.entity` (album, artiste, playlist), `music.resolve`,
`music.lyrics`. Les pochettes sont des champs des entités ; le repli entre sources est géré
par le cœur. Les domaines suivants ajouteront `anime.*`, `video.extract`, `books.*` sur le
même hôte.

### Manifeste et sécurité

- Le manifeste déclare id, version, version du contrat, capacités, domaines autorisés,
  permissions.
- Toute requête ou URL renvoyée (pochettes comprises) vers un domaine non déclaré est refusée.
- Compatibilité : même majeure, mineure ≤ celle de l'hôte.

### Distribution

- `feed.json` signé ed25519 : id, version, contrat, sha256 du `.wasm` et du manifeste.
  Vérifié en arrière-plan, jamais au démarrage ; un cache valide est chargé en attendant.
- Dépôts tiers : l'utilisateur ajoute une URL + une clé publique ; l'app affiche l'empreinte,
  les domaines et les permissions, et demande l'accord avant installation.
- L'app est livrée **sans aucune source**.
- SDK v1 : crate Rust + schémas JSON ; plugins de test `echo` et `spin`.

### Risque connu : `music.resolve` YouTube Music

Pas d'OAuth. Il faut trouver la configuration de client qui évite la détection de bot (déjà
fait dans Auqw). Quand YouTube change, une nouvelle version du plugin suffit, sans mise à jour
de l'app. C'est le premier point validé dans le plugin `ytmusic`.

## 5. Bibliothèque

SQLite via rusqlite dans `core`. Migrations = fichiers SQL numérotés, version suivie par
`PRAGMA user_version`.

Tables : `recordings` (identité interne, titre, artistes, album, durée, ISRC),
`external_refs` (fournisseur + id externe → recording), `entities` (cache albums / artistes /
playlists), `likes`, `playlists`, `playlist_items`, `downloads`, `lyrics`, `plugin_kv`,
`settings`, `search_history`.

Règles :

- **Les données de l'utilisateur ne dépendent jamais d'un fournisseur.** Likes, playlists et
  téléchargements pointent vers l'identité interne et survivent à la disparition d'une source.
  Le cache du catalogue peut être vidé à tout moment.
- **Prête pour la synchro dès la v1** : chaque table de données utilisateur (`likes`,
  `playlists`, `playlist_items`, `settings`) porte `updated_at`, `device_id` et une
  suppression logique (`deleted_at`). La synchro elle-même n'est pas livrée en v1, mais elle
  n'exigera aucune migration de ces tables.

## 6. Erreurs

- Une enum typée traverse le pont : `network`, `provider-wall`, `budget-exceeded`,
  `not-found`, `expired`, `internal`. L'UI traduit chaque type en message lisible.
- Source en échec → candidat suivant ; tous en échec → piste suivante + message discret.
- URL expirée (403) → une seule nouvelle résolution, reprise à la même position.
- Un plugin en échec ne fait jamais planter l'app.
- Écran de diagnostics : logs des plugins, données sensibles masquées.

## 7. Tests

- Rust : tests unitaires de la file, de l'identité, du routage, du schéma de base.
- `plugin-host` : plugins `echo` et `spin` (les budgets coupent bien).
- Plugins : réponses HTTP enregistrées, sans réseau en CI ; une tâche de test réel lancée à la
  main pour détecter un changement chez un fournisseur.
- Flutter : un test de démarrage par coque (lancer, chercher sur données fictives, lire).
- CI : build et tests Android + macOS ; **compilation seule** pour iOS, Windows et Linux, pour
  repérer tôt ce qui casse sur les plateformes à venir.
- Validation finale : le critère de réussite de la section 1.

## 8. Hors v1, et pourquoi ce n'est pas un problème

Chaque élément ci-dessous est **un ajout**, pas une refonte : ce qui serait coûteux à
rattraper est conçu dès maintenant.

| Hors v1 | Ce qui est déjà prévu dans la v1 |
|---|---|
| Synchro entre appareils | Identité interne stable, tables utilisateur avec `updated_at` / `device_id` / suppression logique |
| Fichiers locaux | Bibliothèque indépendante des fournisseurs ; un fournisseur `local` s'ajoute comme les autres |
| iOS, Windows, Linux | Flutter + Rust déjà multiplateformes ; compilés en CI dès le départ |
| Anime, livres | Hôte de plugins générique, capacités préfixées par domaine |
| Version stores | `plugin-host` est une crate séparée, retirable par une option de compilation |
| Cache des octets pendant la lecture | `stream` existe ; le serveur local s'ajoute sans toucher au reste |
| CarPlay, Android Auto, Chromecast | `audio_service` + flux `NowPlaying` déjà en place |
