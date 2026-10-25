# Vehicoule — Surface d'attaque : décisions

Date : 2026-10-25 · Statut : approuvé dans la conversation (v1)

Specs parentes : le socle (`2026-10-18-socle-musique-design.md`), l'addendum navigation et la
spec anime du 2026-10-25. Vehicoule exécute des plugins tiers et lit des flux venus de sources
tierces : tout ce qui parse du contenu non fiable est une surface d'attaque. Règle générale :
**Rust partout où c'est possible, rien de web dans l'app, et le moins de code C possible
exposé au contenu tiers.**

## 1. Décisions

| # | Décision | Change |
|---|---|---|
| 1 | **Tout le trafic média passe par un proxy local** de la crate `stream` | socle §3.1 (« pas de serveur local en v1 ») |
| 2 | **libmpv et FFmpeg recompilés réduits** aux formats utiles | socle §9, §12 ; spike anime (plan B taille) |
| 3 | **WebView de `challenge` durcie** | spec anime §4.5 |
| 4 | **Une seule bibliothèque cryptographique** : rustls + aws-lc-rs | dépendances du cœur |
| 5 | **Garde-fous de CI** sur les dépendances | socle §8 |
| 6 | **Aucun HTML rendu dans l'app**, aucun moteur JS écrit en C | spec anime §4.5, future spec livres |

## 2. Proxy média local

**Le problème.** `media_kit` reçoit l'URL de lecture telle que la donne le plugin (socle
§3.1). L'hôte vérifie cette URL, mais mpv suit ensuite seul les redirections et, pour le HLS,
les URLs de playlists et de segments. Un plugin malveillant peut donc faire interroger le
réseau local (`192.168.x.x`, `localhost`) par mpv, en contournant la liste de domaines et le
refus des IP privées du socle §4.3.

**La décision.**

- `stream` ouvre un serveur HTTP sur `127.0.0.1`, sur un port aléatoire, avec un jeton
  aléatoire par session de lecture dans le chemin : `http://127.0.0.1:<port>/<jeton>/…`.
- Rust donne à mpv l'URL du proxy, jamais l'URL d'origine. Le proxy fait la requête avec les
  en-têtes du plugin et applique **à chaque requête** les règles du socle §4.3 : domaines du
  plugin, vérification à chaque redirection, refus des IP privées après résolution DNS.
- Les playlists HLS sont **réécrites par le proxy** : chaque URL de variante, de segment, de
  clé ou de sous-titre devient une URL du proxy. mpv ne voit jamais d'URL externe.
- mpv et FFmpeg sont limités au protocole `http` vers `127.0.0.1` (`protocol_whitelist`,
  options `stream-lavf-o`) ; tout autre protocole ou hôte est refusé.
- Les fichiers téléchargés et le cache passent par le même proxy : une seule logique de lecture
  pour l'en ligne, le hors ligne et le préchargement (« démarrage instantané du suivant »,
  spec anime §6.1).
- Musique et vidéo l'utilisent pareil. C'est le « serveur local » que le socle §11 prévoyait.
- **Session du plugin** : quand la vidéo vient d'un plugin qui utilise `session` (spec anime
  §4.5), le proxy envoie les requêtes avec **sa boîte à cookies et son User-Agent** : un site
  derrière une protection anti-robots refuse sinon les segments que la page a autorisés.
- Retour OAuth des trackers par lien vérifié `https://vehicoule.com/oauth/…`, jamais par le
  schéma `vehicoule://` (spec anime §4.5).

**Tests.** Une playlist HLS dont un segment pointe vers une IP privée → segment refusé, erreur
typée ; une redirection hors des domaines du plugin → refusée ; un jeton faux → 404 ; mpv
configuré ne peut pas ouvrir `file://`, `tcp://` ni un autre hôte.

## 3. libmpv et FFmpeg réduits

- Les failles de FFmpeg se concentrent dans les démultiplexeurs et décodeurs rares. On
  recompile avec une **liste blanche** :
  - conteneurs : HLS, MPEG-TS, MP4 / fMP4, Matroska / WebM, Ogg, MP3, FLAC, WAV ;
  - audio : AAC, MP3, FLAC, Opus, Vorbis ;
  - vidéo : H.264, HEVC, AV1, VP9 ;
  - sous-titres : ASS / SSA, SRT, WebVTT ;
  - protocoles : `http` seulement (le TLS est fait par le proxy, d'où mbedTLS retiré de
    FFmpeg).
- La licence reste LGPL (configuration de l'étape 1, rapport du 2026-10).
- Effets : moins de code C exposé, binaire plus petit (plan B de taille du spike anime), et
  une bibliothèque de moins (mbedTLS).
- La recette de build vit dans le dépôt, reproductible en CI ; chaque mise à jour de FFmpeg ou
  de libmpv passe par elle.

## 4. WebView de `challenge`

La seule technologie web dans l'app (spec anime §4.5). Elle reste, durcie :

- ouverte **seulement à la demande de l'utilisateur** (« Ouvrir la page »), jamais en
  arrière-plan ni automatiquement ;
- navigation limitée aux domaines déclarés par le plugin ; tout autre lien est bloqué ;
- **aucun pont JavaScript** vers l'app (pas de `addJavascriptInterface`, pas de canal de
  messages), accès aux fichiers et au contenu désactivés, pas de téléchargements ;
- **profil de cookies séparé par plugin**, dont seuls les cookies des domaines du plugin
  sont copiés dans sa boîte ;
- fermée dès la vérification passée ; rien ne survit en dehors de la boîte à cookies du plugin ;
- moteur : la WebView du système (Android System WebView, WKWebView), mise à jour par l'OS,
  sans moteur embarqué.

## 5. Cryptographie et TLS

- rustls avec **aws-lc-rs** comme seul fournisseur cryptographique ; `ring` retiré du graphe
  (options de `sentry`, `reqwest` et `rustls-platform-verifier` choisies pour cela).
- ed25519-dalek pour les signatures des feeds (Rust pur), sha2 pour les sommes.
- Test de CI : `cargo tree -i ring` est vide.

## 6. Contenu non fiable affiché dans l'app

- **HTML** (synopsis AniList, notes de version GitHub, descriptions de sources) : converti en
  texte stylé par une petite fonction Rust qui ne garde que `<br>`, `<i>`, `<b>` et les
  paragraphes. Jamais de WebView, jamais de lien cliquable non vérifié.
- **Markdown** (notes de version) : même conversion, sans images distantes.
- **EPUB** (future spec livres) : rendu **natif** (XHTML lu en Rust, mise en page par
  Flutter), sans WebView ni JavaScript.
- **JavaScript** : aucun moteur écrit en C nulle part ; aides Rust du SDK, et Boa (Rust)
  seulement si le spike anime l'exige (spec anime §4.5).
- **Images** : décodées par Flutter (moteur), taille plafonnée avant décodage par `stream`.

## 7. Dépendances

### 7.1 Inventaire (branche `socle`, 2026-10-25)

Du code C ou C++ est marqué **(C)**.

| Couche | Dépendances |
|---|---|
| Plugins | wasmtime + wasmtime-wasi 48 LTS (Cranelift ne produit que du bytecode Pulley) |
| Base | rusqlite, SQLite intégré **(C)** |
| Réseau | reqwest 0.13, rustls, aws-lc-rs / aws-lc-sys **(C)**, ring **(C, à retirer)**, tower, tokio |
| Divers Rust | flutter_rust_bridge, ed25519-dalek, sha2, uuid, serde / serde_json, base64, strsim, unicode-normalization, semver, fs4, anyhow, getrandom, futures, bytes, sentry ; jni et rustls-platform-verifier sur Android |
| SDK des plugins | wit-bindgen, serde, serde_json, form_urlencoded |
| Lecture | media_kit 1.2.6, libmpv + FFmpeg + libass **(C)**, mbedTLS **(C, retiré par §3)** ; audio_service |
| Flutter | moteur Flutter **(C++)** ; go_router, intl, material_ui, material_3_expressive, material_color_utilities, dynamic_color, freezed_annotation |
| Plateforme | connectivity_plus, path_provider, url_launcher, app_links, package_info_plus, device_info_plus, window_manager |
| Prévues | prost (sauvegardes Aniyomi), chacha20poly1305 + argon2 (sauvegarde chiffrée), media_kit_video et libs vidéo, workmanager, home_widget, sentry_flutter, webview_flutter, stockage sécurisé des jetons, capture du micro, rusty-chromaprint, Boa (si le spike l'exige) |

### 7.2 Règles

- **Nouvelle dépendance = justification écrite** dans le plan qui l'ajoute : ce qu'elle fait,
  pourquoi le stdlib ou une dépendance déjà là ne suffit pas, son langage, son mainteneur.
  Une dépendance en C exposée au contenu tiers demande un accord explicite de l'utilisateur.
- Préférer, dans l'ordre : Rust pur ; paquets officiels Flutter ou `plus` ; le reste.
- Versions figées (déjà la règle du plan 5) ; lockfiles commités.
- **CI** :
  - `cargo deny` : failles connues (RustSec), licences autorisées, doublons, sources
    autorisées (crates.io et les dépôts Vehicoule seulement) ;
  - `osv-scanner` sur `pubspec.lock` et `Cargo.lock` ;
  - une alerte de faille connue bloque la release, pas le développement.
- **`material_3_expressive`** (un seul mainteneur, compte non vérifié) : copié dans le dépôt
  (`third_party/`) à la version 1.2.0 ; chaque mise à jour est une relecture du diff.
- Pas de récupération de code ou de polices au lancement (déjà la règle de la spec UI §2.4).

## 8. Services en ligne de Vehicoule

- **Worker Cloudflare** (`/p/`, addendum §3.1) écrit en **Rust** (`workers-rs`) ; il ne stocke
  que des listes de références.
- **Page de partage** : HTML statique et un seul fichier JavaScript écrit à la main, **sans
  dépendance npm**, avec une `Content-Security-Policy` stricte (scripts du domaine seulement,
  connexions vers les seuls catalogues publics).
- Aucun cookie ni suivi sur `vehicoule.com`.

## 9. Impact sur les plans

- **Plan 4 (cœur et pont) et crate `stream`** : le proxy local (§2) ; `PlayCommand` porte une
  URL du proxy. Avant les écrans d'écoute du plan 5.
- **Plan 5, Task 3 (lecteur)** : options mpv `protocol_whitelist` ; test « mpv ne joint aucun
  autre hôte ».
- **Étape 1 de l'anime** : la recette FFmpeg réduite remplace le simple passage à
  `media_kit_libs_video` dans la mesure de taille.
- **CI (plan 5, Task 8)** : `cargo deny`, `osv-scanner`, `cargo tree -i ring`.
- **Plan 6 (plugins)** : rien ; le SDK gagne ses aides Rust avec la spec anime.
