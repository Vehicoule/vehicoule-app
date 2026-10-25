/// Spacing, sizes, radii and breakpoints (spec UI §2.7, §4.3, §5.1). Screens take every
/// number from here; the guards in `test/design/` reject literals elsewhere.
library;

/// The one spacing scale: 4 · 8 · 12 · 16 · 24 · 32.
abstract final class VSpace {
  static const s4 = 4.0,
      s8 = 8.0,
      s12 = 12.0,
      s16 = 16.0,
      s24 = 24.0,
      s32 = 32.0;
  static const marginCompact = 16.0,
      marginWide = 24.0,
      sectionGap = 24.0,
      cardGap = 8.0;

  /// Screen margin: 16 on a phone, 24 beyond.
  static double margin(WindowClass c) =>
      c == WindowClass.compact ? marginCompact : marginWide;
}

abstract final class VSize {
  static const trackRow = 56.0,
      trackArt = 44.0,
      trackArtRadius = 12.0,
      menuTarget = 48.0;
  static const shelfCard = 108.0;

  /// The collapsed desktop "now playing" strip (spec UI §4.2), mirror of the rail.
  static const strip = 76.0;

  /// The expanded rail (M3: 220 to 360), wide enough for its FAB's label.
  static const railExpanded = 280.0;

  /// The rail's width from which its FAB shows its label (while it grows, a plain FAB).
  static const railFabExtended = 200.0;

  /// The standard side sheet that holds the desktop "now playing" pane.
  static const sideSheet = 360.0;

  /// Icon sizes: inline badge, list and button icon, empty-state icon.
  static const iconSmall = 16.0, icon = 24.0, iconLarge = 48.0;

  /// Slider tracks (M3E sizes): « s » (24) for a plain slider; « m » (40) for the
  /// volume, whose speaker sits inside the track (M3E inset icons start at « m »).
  static const sliderTrack = 24.0, volumeTrack = 40.0;

  /// A chip's leading icon (M3 chips: 18).
  static const chipIcon = 18.0;

  /// The loading indicator inside ⏯.
  static const playIcon = 32.0;

  /// Artwork with its ring in the compact player (mini player, strip, compact header).
  static const compactArt = 56.0;

  /// The regular FAB (the mini player's ⏯) and the floating toolbar beside it.
  static const fab = 56.0, toolbar = 64.0;

  /// The narrowest segment of the player's view selector (icon only); the active one
  /// widens with its label.
  static const selectorSegment = 64.0;

  /// The header row of the player.
  static const playerHeader = 56.0;

  /// The widest a control button gets (⏯ takes two), and the controls' height when the
  /// player has the room (a phone held upright).
  static const controlMax = 72.0, controlTall = 72.0;

  /// From this body height the large player uses tall controls.
  static const tallPlayer = 640.0;

  /// From this width the immersive player has its group, controls and selector on one
  /// row.
  static const immersiveRow = 1100.0;

  /// The empty-state decor shape.
  static const emptyDecor = 160.0;

  /// The wavy progress stroke and its gap to the artwork.
  static const ringStroke = 4.0, ringGap = 4.0;

  /// The ring around a small artwork (the mini player, the strip, ≤ [ringSmallUpTo]):
  /// thinner and closer, so the picture keeps its size.
  static const ringStrokeSmall = 3.0, ringGapSmall = 2.0, ringSmallUpTo = 96.0;

  /// How far a row slides before a swipe acts.
  static const swipe = 96.0;

  /// Desktop table columns.
  static const albumColumn = 220.0, durationColumn = 56.0;

  /// Hero card width in a carousel.
  static const heroCard = 280.0;

  /// The band under a carousel item's text: how dark at the bottom, how high, and the
  /// narrowest item that carries text (M3E shows the title from 200).
  static const carouselScrim = 0.6, carouselBand = 0.5, carouselText = 200.0;

  /// The surface's opacity under the Vague's header: its icons read on any cover.
  static const headerScrim = 0.88;

  /// The thin stroke of small progress icons (download).
  static const iconStroke = 3.0;

  /// How far inside the ring's edge a finger still grabs it.
  static const ringHit = 24.0;

  /// The wave edge: amplitude, wavelength and how much of the picture it crops.
  static const waveAmplitude = 5.0, waveLength = 48.0, waveCrop = 10.0;

  /// How much taller than wide the Vague's cover may grow on a tall screen.
  static const waveTallest = 1.15;

  /// App bar height, and the artwork docked in it by a flexible header.
  static const appBar = 64.0, dockedArt = 40.0;

  /// The flexible header's artwork (compact, expanded) and its text block at 100 % text.
  static const headerArt = 220.0, headerArtWide = 200.0, headerText = 72.0;

  /// The player's artwork: largest in each size, smallest, and the room the blocks under
  /// it need (title, actions, controls) at 100 % text.
  static const playerArtLarge = 420.0,
      playerArtMedium = 300.0,
      playerArtMin = 120.0;
  static const playerBlocks = 260.0;

  /// The expressive menu's width.
  static const menu = 280.0;
}

abstract final class VRadius {
  /// Small artwork (rows, cards) and list highlights.
  static const small = 12.0;

  /// Cards, menus and large artwork.
  static const medium = 16.0;

  /// Hero artwork and the player.
  static const large = 28.0;
}

/// M3 window size classes (spec UI §4.3). [windowClassOf] is the only source of breakpoints.
enum WindowClass { compact, medium, expanded }

abstract final class VBreakpoints {
  static const medium = 600.0, expanded = 840.0;

  /// Above this width the desktop "now playing" pane is open by default (spec UI §4.2).
  static const paneOpen = 1000.0;
}

WindowClass windowClassOf(double width) => width < VBreakpoints.medium
    ? WindowClass.compact
    : width < VBreakpoints.expanded
    ? WindowClass.medium
    : WindowClass.expanded;
