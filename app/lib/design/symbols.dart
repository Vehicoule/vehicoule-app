/// Material Symbols Rounded, the app's only icon font (spec UI §2.5). Code points come from
/// the font's `.codepoints` file (`app/assets/fonts/README.md`); add one here when a
/// screen needs a new icon — the shipped font already has every glyph.
library;

import 'package:material_ui/material_ui.dart';

import 'motion.dart';

abstract final class VIcons {
  static const _f = 'MaterialSymbolsRounded';

  static const add = IconData(0xe145, fontFamily: _f);
  static const addToQueue = IconData(0xe05c, fontFamily: _f);
  static const album = IconData(0xe019, fontFamily: _f);
  static const arrowBack = IconData(0xe5c4, fontFamily: _f);
  static const bedtime = IconData(0xf159, fontFamily: _f);
  static const check = IconData(0xe668, fontFamily: _f);
  static const chevronRight = IconData(0xe5cc, fontFamily: _f);
  static const close = IconData(0xe5cd, fontFamily: _f);
  static const cloudOff = IconData(0xe2c1, fontFamily: _f);
  static const collapse = IconData(
    0xe313,
    fontFamily: _f,
  ); // keyboard_arrow_down
  static const delete = IconData(0xe92e, fontFamily: _f);
  static const devices = IconData(0xe326, fontFamily: _f);
  static const download = IconData(0xf090, fontFamily: _f);
  static const downloadDone = IconData(0xf091, fontFamily: _f);
  static const dragHandle = IconData(0xe25d, fontFamily: _f);
  static const error = IconData(0xf8b6, fontFamily: _f);
  static const explicit = IconData(0xe01e, fontFamily: _f);
  static const explore = IconData(0xe87a, fontFamily: _f);
  static const favorite = IconData(0xe87e, fontFamily: _f);
  static const fullscreen = IconData(0xf1ce, fontFamily: _f); // open_in_full
  static const home = IconData(0xe9b2, fontFamily: _f);
  static const library = IconData(0xe030, fontFamily: _f); // library_music
  static const lyrics = IconData(0xec0b, fontFamily: _f);
  static const menu = IconData(0xe5d2, fontFamily: _f);
  static const more = IconData(0xe5d4, fontFamily: _f); // more_vert
  static const musicNote = IconData(0xe405, fontFamily: _f);
  static const musicOff = IconData(0xe440, fontFamily: _f);
  static const pause = IconData(0xe034, fontFamily: _f);
  static const person = IconData(0xf0d3, fontFamily: _f);
  static const play = IconData(0xe037, fontFamily: _f); // play_arrow
  static const playNext = IconData(0xe066, fontFamily: _f); // queue_play_next
  static const playlistAdd = IconData(0xe03b, fontFamily: _f);
  static const queue = IconData(0xe03d, fontFamily: _f); // queue_music
  static const refresh = IconData(0xe5d5, fontFamily: _f);
  static const repeat = IconData(0xe040, fontFamily: _f);
  static const repeatOne = IconData(0xe041, fontFamily: _f);
  static const search = IconData(0xef7a, fontFamily: _f);
  static const settings = IconData(0xe8b8, fontFamily: _f);
  static const shuffle = IconData(0xe043, fontFamily: _f);
  static const skipNext = IconData(0xe044, fontFamily: _f);
  static const skipPrevious = IconData(0xe045, fontFamily: _f);
  static const volume = IconData(0xe050, fontFamily: _f); // volume_up
}

/// An icon whose FILL and wght axes animate (the heart that fills, the active tab that
/// thickens). Without [semanticLabel] it is decorative.
class VSymbol extends StatelessWidget {
  const VSymbol(
    this.icon, {
    super.key,
    this.filled = false,
    this.weight = 400,
    this.size,
    this.color,
    this.semanticLabel,
  });

  final IconData icon;
  final bool filled;
  final double weight;
  final double? size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: filled ? 1 : 0),
    duration: vMotion(context, VDurations.short),
    curve: VCurves.standard,
    builder: (context, fill, _) => TweenAnimationBuilder<double>(
      tween: Tween(end: weight),
      duration: vMotion(context, VDurations.short),
      curve: VCurves.standard,
      builder: (context, w, _) => Icon(
        icon,
        fill: fill,
        weight: w,
        size: size,
        color: color,
        semanticLabel: semanticLabel,
      ),
    ),
  );
}
