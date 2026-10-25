/// The app's theme (spec UI §2.2): the user's choices, kept in `ui.*` preferences, and,
/// with « Ce qui joue », the seed of the playing track's cover, once per track.
library;

import 'package:material_ui/material_ui.dart';

import 'bridge/api/playback.dart' show nowPlaying;
import 'bridge/api/settings.dart';
import 'bridge/events.dart';
import 'design/design.dart';

typedef SeedFor = Future<Color> Function(
  String? path, {
  required Color fallback,
});

class ThemeController extends ChangeNotifier {
  /// The three seams are for the tests.
  ThemeController({
    this._seedFor = seedForArtwork,
    this._coverTopFor = coverTopFromArtwork,
    this._systemSeedFor = systemSeed,
  });

  static const _sourceKey = 'ui.color_source',
      _presetKey = 'ui.preset',
      _pureBlackKey = 'ui.pure_black',
      _modeKey = 'ui.theme',
      _styleKey = 'ui.player_style';

  final SeedFor _seedFor;
  final Future<VCoverTop?> Function(String path) _coverTopFor;
  final Future<Color?> Function() _systemSeedFor;

  ColorSource _source = ColorSource.nowPlaying;
  int _preset = 0;
  bool _pureBlack = false;
  ThemeMode _mode = ThemeMode.system;
  PlayerStyle _style = PlayerStyle.disc;
  Color? _system;

  /// The playing cover's own seed; null for a colourless cover (the fallback then).
  Color? _cover;
  VCoverTop? _coverTop;

  /// The track and cover the seed was read for.
  (String, String?)? _for;
  ThemeData? _light, _dark;

  ColorSource get source => _source;
  int get preset => _preset;
  bool get pureBlack => _pureBlack;
  ThemeMode get mode => _mode;
  PlayerStyle get playerStyle => _style;

  /// The playing cover's top band, for the Vague's header.
  VCoverTop? get coverTop => _coverTop;

  /// A colourless cover, the System source without a system colour: the System seed,
  /// else the chosen preset.
  Color get _fallback => _system ?? VPresets.seeds[_preset];

  Color get seed => switch (_source) {
    ColorSource.nowPlaying => _cover ?? _fallback,
    ColorSource.system => _fallback,
    ColorSource.preset => VPresets.seeds[_preset],
  };

  ThemeData get light =>
      _light ??= vTheme(brightness: Brightness.light, seed: seed);
  ThemeData get dark => _dark ??= vTheme(
    brightness: Brightness.dark,
    seed: seed,
    pureBlack: _pureBlack,
  );

  /// Reads the saved choices and the system colour.
  Future<void> load() async {
    final keys = [_sourceKey, _presetKey, _pureBlackKey, _modeKey, _styleKey];
    final values = await Future.wait([for (final k in keys) uiPref(key: k)]);
    String? v(String k) => values[keys.indexOf(k)];
    _source = ColorSource.values.asNameMap()[v(_sourceKey)] ?? _source;
    _preset = (int.tryParse(v(_presetKey) ?? '') ?? 0).clamp(
      0,
      VPresets.seeds.length - 1,
    );
    _pureBlack = v(_pureBlackKey) == 'true';
    _mode = ThemeMode.values.asNameMap()[v(_modeKey)] ?? _mode;
    _style = PlayerStyle.values.asNameMap()[v(_styleKey)] ?? _style;
    _system = await _systemSeedFor();
    _changed();
  }

  /// Follows what plays: a new seed when the track (or its cover) changes, never per
  /// position or play/pause.
  void start() => nowPlaying().listen(_onNowPlaying);

  Future<void> _onNowPlaying(NowPlaying n) async {
    final id = n.track?.id;
    // Nothing loaded (a stop): the theme stays.
    if (id == null) return;
    final key = (id, n.artworkPath);
    if (key == _for) return;
    _for = key;
    final path = n.artworkPath;
    final fallback = _fallback;
    final (seed, top) = await (
      _seedFor(path, fallback: fallback),
      path == null ? Future<VCoverTop?>.value() : _coverTopFor(path),
    ).wait;
    if (_for != key) return;
    // The fallback is kept as such: a later preset change applies to it.
    _cover = seed == fallback ? null : seed;
    _coverTop = top;
    _changed();
  }

  Future<void> setSource(ColorSource s) => _set(_sourceKey, s.name, () {
    _source = s;
  });

  Future<void> setPreset(int index) => _set(_presetKey, '$index', () {
    _preset = index;
  });

  Future<void> setPureBlack(bool v) => _set(_pureBlackKey, '$v', () {
    _pureBlack = v;
  });

  Future<void> setMode(ThemeMode m) => _set(_modeKey, m.name, () {
    _mode = m;
  });

  Future<void> setPlayerStyle(PlayerStyle s) => _set(_styleKey, s.name, () {
    _style = s;
  });

  /// Saved first, then shown.
  Future<void> _set(String key, String value, VoidCallback apply) async {
    await setUiPref(key: key, value: value);
    apply();
    _changed();
  }

  void _changed() {
    _light = _dark = null;
    notifyListeners();
  }
}
