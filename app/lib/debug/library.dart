/// The test library: real titles and artists (metadata only, no cover art), shared by the
/// design gallery, the design tests and, later, the debug fake API (preflight C11, S33).
/// No artwork is committed: the gallery looks real covers up through the core when a
/// source answers ([sampleQuery]); otherwise artwork shows the missing-cover look.
library;

import '../bridge/catalog.dart';

TrackView _t(
  String id,
  String title,
  List<String> artists,
  String album,
  int seconds, {
  bool explicit = false,
  bool liked = false,
  bool downloaded = false,
}) => TrackView(
  id: 'track:$id',
  title: title,
  artists: [for (final a in artists) ArtistRefView(id: 'artist:$a', name: a)],
  album: AlbumRefView(id: 'album:$album', title: album),
  durationMs: seconds * 1000,
  explicit: explicit,
  liked: liked,
  downloaded: downloaded,
);

final sampleTracks = <TrackView>[
  _t(
    '1',
    'Alors on danse',
    ['Stromae'],
    'Cheese',
    206,
    liked: true,
    downloaded: true,
  ),
  _t(
    '2',
    'Get Lucky',
    ['Daft Punk', 'Pharrell Williams', 'Nile Rodgers'],
    'Random Access Memories',
    369,
  ),
  _t(
    '3',
    'La vie en rose',
    ['Édith Piaf'],
    'La vie en rose',
    186,
    downloaded: true,
  ),
  _t('4', 'HUMBLE.', ['Kendrick Lamar'], 'DAMN.', 177, explicit: true),
  _t('5', 'プラスティック・ラヴ', ['竹内まりや'], 'VARIETY', 474, liked: true),
  _t('6', 'Midnight City', ['M83'], "Hurry Up, We're Dreaming", 243),
  _t('7', 'Dernière danse', ['Indila'], 'Mini World', 215),
  _t(
    '8',
    'Clair de lune',
    ['Claude Debussy', 'Alexis Weissenberg'],
    'Suite bergamasque',
    318,
  ),
  _t('9', 'Paranoid Android', ['Radiohead'], 'OK Computer', 387, liked: true),
  _t('10', 'Je veux', ['ZAZ'], 'Zaz', 219),
  _t('11', 'Feel Good Inc.', ['Gorillaz'], 'Demon Days', 222),
  _t('12', 'Christine', ['Christine and the Queens'], 'Chaleur humaine', 230),
];

/// Album and playlist cards for shelves: (id, title, subtitle).
const sampleCollections = <(String, String, String)>[
  ('album:Random Access Memories', 'Random Access Memories', 'Daft Punk'),
  ('album:Cheese', 'Cheese', 'Stromae'),
  ('album:OK Computer', 'OK Computer', 'Radiohead'),
  ('album:DAMN.', 'DAMN.', 'Kendrick Lamar'),
  ('album:VARIETY', 'VARIETY', '竹内まりや'),
  ('album:Demon Days', 'Demon Days', 'Gorillaz'),
];

/// What to search for to find the real item behind a sample id: a track's title and first
/// artist, an album's title and artist, an artist's name.
String? sampleQuery(String id) {
  for (final t in sampleTracks) {
    if (t.id == id) return '${t.title} ${t.artists.first.name}';
  }
  for (final (cid, title, artist) in sampleCollections) {
    if (cid == id) return '$title $artist';
  }
  return id.startsWith('artist:') ? id.substring('artist:'.length) : null;
}
