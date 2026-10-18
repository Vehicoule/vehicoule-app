# probes/

Jetable : sondes de l'étape 1 (mesures sur Android). Supprimé quand le socle remplace ces sondes.

- `wasmtime-android/` : lance les composants de test de `core/plugin-host` sur l'appareil.
- `baseline-android/` : mêmes dépendances (tokio, reqwest) sans Wasmtime, pour mesurer l'écart de taille.
- `android-playback/` : app Flutter de lecture d'1 h écran éteint (media_kit + audio_service).
