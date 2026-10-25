# Vehicoule — Registre des décisions

Une ligne par décision qui change une spec déjà écrite. La spec citée fait foi ; la ligne
remplacée ne doit plus être suivie. On ajoute en bas, on ne réécrit pas.

| Date | Décision | Fait foi | Remplace |
|---|---|---|---|
| 2026-10-25 | Accueil commun + sélecteur de domaine ; Réglages, Sources, Téléchargements globaux, hors de la barre | `2026-10-25-navigation-domaines.md` §2 | spec UI §1, §4.1 (barre à 4 destinations dont Réglages) |
| 2026-10-25 | Routes préfixées par le domaine (`/music/…`, `/video/…`, `/books/…`), `/sources` global | navigation §3 | spec UI §6.7 (`/settings/sources`) ; routes sans préfixe du plan 5 |
| 2026-10-25 | Domaine `vehicoule.com`, identifiant `com.vehicoule` | navigation §10 | socle §12 (`vehicoule.app`, `app.vehicoule`) |
| 2026-10-25 | Proxy média local : mpv ne joint que 127.0.0.1 | `2026-10-25-surface-attaque.md` §2 | socle §3.1 (« pas de serveur local en v1 ») |
| 2026-10-25 | libmpv + FFmpeg recompilés réduits à une liste blanche | surface d'attaque §3 | socle §1 (`media_kit_libs_*` tels quels) |
| 2026-10-25 | Plan B YouTube : interface `js` en Boa natif (Rust), aucun moteur JS écrit en C | `2026-10-25-video-design.md` §4.5 | socle §4.5 (QuickJS natif) |
| 2026-10-25 | `vehicoule:host` 1.1.0 : `types`, `locale`, `session`, `challenge`, `oauth`, filtres, `settings-schema`, `credentials` | vidéo §4.5, §4.7 ; livres §4.5 | socle §4.1 (interfaces de l'hôte) |
| 2026-10-25 | Retour OAuth par lien vérifié `https://vehicoule.com/oauth/…` | vidéo §4.5 | — |
| 2026-10-25 | Rien en « plus tard », pas de découpage en versions : chaque idée va dans la spec de son domaine | règle de l'utilisateur | socle §11 et toutes les mentions « hors v1 » |
| 2026-10-25 | Le domaine anime devient **Vidéos** (`video`) : films, séries, animés ; sortes `movie`, `show`, `season`, `episode`, `collection` | `2026-10-25-video-design.md` | `2026-10-25-anime-design.md` (sortes `anime`, `episode`) |
| 2026-10-25 | Sources légales dans le feed officiel : Jellyfin / Emby, Plex, Navidrome / Subsonic, fichiers locaux (fournisseur du cœur) | vidéo §4.6 | socle §4.4 (feed officiel sans source de lecture) |
| 2026-10-25 | Adresse du réseau local accordée par l'utilisateur à un seul plugin | surface d'attaque §2 | socle §4.3 (toute IP privée refusée) |
| 2026-10-25 | Feeds à plusieurs miroirs | surface d'attaque §8 bis | socle §4.4 (une URL par feed) |
| 2026-10-25 | Minuterie de sommeil d'app, qui vise toutes les sessions | navigation §5.1 | spec UI §5.5 / plan 7 (minuterie de la file) |
| 2026-10-25 | Langues du contenu : réglage d'app (langues comprises, audio, sous-titres, forcés) ; interface hôte `locale` (`preferred-languages` BCP 47, trois au plus ; `region` ; `Accept-Language` ajouté par l'hôte) dans `vehicoule:host` 1.1.0 | `2026-10-25-video-design.md` §4.7, §6.4 | socle §4.1 (aucune langue transmise aux plugins hors `resolve` et `browse`) |
