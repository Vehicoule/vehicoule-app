/// Material Symbols Rounded, the app's only icon font (spec UI §2.5). Code points come from
/// the font's `.codepoints` file (`app/assets/fonts/README.md`); add one here when a
/// screen needs a new icon — the shipped font already has every glyph.
library;

import 'package:material_ui/material_ui.dart';

import 'motion.dart';

abstract final class VIcons {
  static const _f = 'MaterialSymbolsRounded';

  static const add = IconData(0xe145, fontFamily: _f);
  static const addToQueue = IconData(0xe03d, fontFamily: _f); // queue_music
  static const album = IconData(0xe019, fontFamily: _f);
  static const arrowBack = IconData(0xe5c4, fontFamily: _f);
  static const arrowForward = IconData(0xe5c8, fontFamily: _f);
  static const bedtime = IconData(0xf159, fontFamily: _f);
  static const check = IconData(0xe668, fontFamily: _f);
  static const chevronRight = IconData(0xe5cc, fontFamily: _f);
  static const close = IconData(0xe5cd, fontFamily: _f);
  static const closeFullscreen = IconData(0xf1cf, fontFamily: _f);
  static const cloudOff = IconData(0xe2c1, fontFamily: _f);
  static const collapse = IconData(
    0xe313,
    fontFamily: _f,
  ); // keyboard_arrow_down
  static const delete = IconData(0xe92e, fontFamily: _f);
  static const devices = IconData(0xe326, fontFamily: _f);
  static const download = IconData(0xf090, fontFamily: _f);
  static const downloadDone = IconData(0xf091, fontFamily: _f);
  static const downloaded = IconData(
    0xf000,
    fontFamily: _f,
  ); // download_for_offline, filled once downloaded
  static const dragHandle = IconData(0xe25d, fontFamily: _f);
  static const error = IconData(0xf8b6, fontFamily: _f);
  static const explicit = IconData(0xe01e, fontFamily: _f);
  static const explore = IconData(0xe87a, fontFamily: _f);
  static const favorite = IconData(0xe87e, fontFamily: _f);
  static const fullscreen = IconData(0xf1ce, fontFamily: _f); // open_in_full
  static const home = IconData(0xe9b2, fontFamily: _f);
  static const books = IconData(0xea19, fontFamily: _f); // menu_book
  static const library = IconData(0xe030, fontFamily: _f); // library_music
  static const lyrics = IconData(0xec0b, fontFamily: _f);
  static const menu = IconData(0xe5d2, fontFamily: _f);
  static const menuOpen = IconData(0xe9bd, fontFamily: _f);
  static const more = IconData(0xe5d4, fontFamily: _f); // more_vert
  static const musicNote = IconData(0xe405, fontFamily: _f);
  static const musicOff = IconData(0xe440, fontFamily: _f);
  static const pause = IconData(0xe034, fontFamily: _f);
  static const person = IconData(0xf0d3, fontFamily: _f);
  static const play = IconData(0xe037, fontFamily: _f); // play_arrow
  static const playNext = IconData(0xe05f, fontFamily: _f); // playlist_play
  static const playlistAdd = IconData(0xe03b, fontFamily: _f);
  static const queue = IconData(0xe03d, fontFamily: _f); // queue_music
  static const radio = IconData(0xe03e, fontFamily: _f);
  static const history = IconData(0xe889, fontFamily: _f);
  static const refresh = IconData(0xe5d5, fontFamily: _f);
  static const repeat = IconData(0xe040, fontFamily: _f);
  static const repeatOne = IconData(0xe041, fontFamily: _f);
  static const search = IconData(0xef7a, fontFamily: _f);
  static const settings = IconData(0xe8b8, fontFamily: _f);
  static const shuffle = IconData(0xe043, fontFamily: _f);
  static const skipNext = IconData(0xe044, fontFamily: _f);
  static const skipPrevious = IconData(0xe045, fontFamily: _f);
  static const stop = IconData(0xe047, fontFamily: _f);
  static const expandUp = IconData(0xe316, fontFamily: _f); // keyboard_arrow_up
  static const video = IconData(0xe639, fontFamily: _f); // live_tv
  static const volume = IconData(0xe050, fontFamily: _f); // volume_up
  static const addLink = IconData(0xe178, fontFamily: _f);
  static const brightnessAuto = IconData(0xe1ab, fontFamily: _f);
  static const darkMode = IconData(0xe51c, fontFamily: _f);
  static const edit = IconData(0xe150, fontFamily: _f);
  static const filter = IconData(0xe152, fontFamily: _f);
  static const info = IconData(0xe88e, fontFamily: _f);
  static const lightMode = IconData(0xe518, fontFamily: _f);
  static const link = IconData(0xe157, fontFamily: _f);
  static const notifications = IconData(0xe7f4, fontFamily: _f);
  static const palette = IconData(0xe3b7, fontFamily: _f);
  static const panelClose = IconData(0xf705, fontFamily: _f);
  static const panelOpen = IconData(0xf704, fontFamily: _f);
  static const pushPin = IconData(0xf10d, fontFamily: _f);
  static const selectAll = IconData(0xe162, fontFamily: _f);
  static const speaker = IconData(0xe32d, fontFamily: _f);
  static const source = IconData(0xe87b, fontFamily: _f); // extension
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
    // The heart fills (and the active icon thickens) on the M3E effects spring.
    duration: vMotion(context, VDurations.medium),
    curve: VCurves.spring,
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
