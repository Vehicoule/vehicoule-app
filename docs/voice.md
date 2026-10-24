# Le ton de Vehicoule

Tout texte visible passe par les ARB (`app/lib/l10n/app_fr.arb`, modèle, et `app_en.arb`)
et suit ces règles, dans les deux langues. Le test `app/test/l10n/l10n_test.dart`
(« arb strings follow voice.md ») vérifie ce qui se vérifie ; le reste se juge en revue.

## Règles

- **Tutoiement.** Jamais « vous » ni « veuillez » (en anglais, pas de « please »).
- **Une phrase, deux au plus** : ce qui se passe, puis ce qu'on peut faire.
- **Jamais la faute de l'utilisateur.** On dit ce qui se passe, pas ce qu'il a mal fait.
- **Ni code d'erreur ni jargon** : pas de « 403 », « plugin », « dépôt », « feed »,
  « résolution », ni « oups » / « oops ». Le détail technique va aux diagnostics, jamais
  à l'écran.
- **Le nom du fournisseur seulement s'il aide** (« YouTube bloque ce titre pour
  l'instant »).
- **Aucun point d'exclamation, aucun emoji.** Le ♡ est le symbole du like, pas un emoji.
- **Guillemets** : « » en français, “ ” en anglais ; jamais de guillemets droits `"`.
- **Espaces insécables en français** (U+00A0) à l'intérieur des « » et avant ? ; : —
  la ligne ne se coupe jamais sur un signe seul.
- **Majuscule seulement en début de phrase**, jamais de Title Case.

## Vocabulaire

| Dire | Ne jamais dire |
|---|---|
| une **source** (ce qui donne la recherche, la lecture ou les paroles) | plugin, extension, module |
| un **lien de source** (ce qui ajoute une source) | dépôt, feed, flux, URL de dépôt |

## Messages types

| Situation | Français | English |
|---|---|---|
| Hors ligne | Hors ligne · tes téléchargements restent là. | Offline · your downloads are still here. |
| Mur du fournisseur | YouTube bloque ce titre pour l'instant. On passe au suivant. | YouTube is blocking this track for now. Skipping to the next. |
| Limite de débit | Trop de demandes d'un coup. Réessaie dans une minute. | Too many requests at once. Try again in a minute. |
| Titre sauté | « Halo » n'a pas pu être lu, on continue. | Couldn't play “Halo”, moving on. |
| Aucune source | Il te faut une source pour lire. Ajouter une source ? | You need a source to play music. Add a source? |
| Téléchargement raté | « Ivy » n'a pas pu être téléchargé. Réessayer ? | Couldn't download “Ivy”. Retry? |
| Arrêt | Lecture arrêtée · Annuler | Playback stopped · Undo |
| Vide (likés) | Rien de liké pour l'instant. Touche ♡ sur un titre pour le retrouver ici. | Nothing liked yet. Tap ♡ on a track to find it here. |

Les erreurs du cœur (`CoreError`) ont chacune leur phrase : `errorMessage` dans
`app/lib/l10n/errors.dart`, textes dans les ARB (clés `error…`).
