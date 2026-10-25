// « Épinglés » in the desktop rail (spec UI §4.2), per domain (addendum §2.3): ids in
// `ui.pinned.<domain>` (JSON), Likés and Téléchargés by default. Each is a page and a drop
// target for a selection of tracks.
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../bridge/api/catalog.dart' show entity;
import '../bridge/api/library.dart';
import '../bridge/api/settings.dart';
import '../bridge/library.dart';
import '../design/design.dart';
import '../domains.dart';
import '../l10n/app_localizations.dart';

class Pinned extends ChangeNotifier {
  Pinned(this.domain);

  static const liked = 'liked', downloaded = 'downloaded';

  final Domain domain;

  String get _key => 'ui.pinned.${domain.name}';

  List<String> _ids = const [liked, downloaded];
  final _titles = <String, String>{};
  final _playlists = <String>{};

  List<String> get ids => _ids;

  Future<void> load() async {
    try {
      final saved = await uiPref(key: _key);
      if (saved != null) _ids = (jsonDecode(saved) as List).cast<String>();
    } on Object {
      // Unreadable: the defaults.
    }
    notifyListeners();
    try {
      for (final p in await playlists(sort: CollectionSort.recent)) {
        _titles[p.id] = p.title;
        if (p.isUserPlaylist) _playlists.add(p.id);
      }
    } on Object {
      // No titles yet: they come with the next load.
    }
    for (final id in _ids) {
      if (id == liked || id == downloaded || _titles.containsKey(id)) continue;
      try {
        _titles[id] = (await entity(id: id)).header.title;
      } on Object {
        // Offline: the title comes later.
      }
    }
    notifyListeners();
  }

  List<VPinned> items(AppLocalizations l) => [
    for (final id in _ids)
      VPinned(
        id,
        switch (id) {
          liked => l.likedTracks,
          downloaded => l.downloadedTracks,
          _ => _titles[id] ?? '',
        },
        kind: id.startsWith('artist:') ? ArtKind.artist : ArtKind.item,
        droppable: _droppable(id),
        // What it is (desktop-2: « Playlist », « Artiste »). Track counts need a
        // count from the core: plan 5b.
        subtitle: switch (id.split(':').first) {
          liked || downloaded => l.pinnedKindTracks,
          'playlist' => l.pinnedKindPlaylist,
          'album' => l.pinnedKindAlbum,
          'artist' => l.pinnedKindArtist,
          _ => null,
        },
      ),
  ];

  bool _droppable(String id) =>
      id == liked || id == downloaded || _playlists.contains(id);

  /// Pins [id] (last), saved at once.
  Future<void> pin(String id) async {
    if (_ids.contains(id)) return;
    _ids = [..._ids, id];
    await setUiPref(key: _key, value: jsonEncode(_ids));
    notifyListeners();
  }

  Future<void> unpin(String id) async {
    _ids = [..._ids.where((i) => i != id)];
    await setUiPref(key: _key, value: jsonEncode(_ids));
    notifyListeners();
  }

  /// Where a pinned item leads: the domain's library.
  String route(String id) {
    final library = libraryRoot(domain);
    return switch (id) {
      liked => '$library/liked',
      downloaded => '$library/downloaded',
      _ => '$library/${id.split(':').first}/${Uri.encodeComponent(id)}',
    };
  }

  /// Tracks dropped on [id]: added to the playlist, liked, or downloaded.
  Future<void> drop(String id, List<String> tracks) async {
    switch (id) {
      case liked:
        for (final t in tracks) {
          await setLiked(id: t, liked: true);
        }
      // Task 6 sends it through startDownload (the notification permission).
      case downloaded:
        await download(ids: tracks);
      case _ when _playlists.contains(id):
        await addToPlaylist(id: id, items: tracks);
    }
  }
}
