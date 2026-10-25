// The keyboard of spec UI §4.2: one table, command → keys, label, menu and action. The
// keys and the macOS menu bar (Lecture, Aller, Fenêtre) send the same intent to the same
// action, which does nothing while a text field has the focus. ⌘ on Apple, Ctrl
// elsewhere. Space and Delete on a focused track row are the row's (VTrackRow).
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../bridge/api/library.dart' show refreshHome;
import '../design/design.dart';
import '../l10n/app_localizations.dart';
import '../platform/player.dart';
import '../router.dart';

enum ShellCommand {
  playPause,
  seekBack,
  seekForward,
  previous,
  next,
  volumeUp,
  volumeDown,
  like,
  search,
  back,
  forward,
  settings,
  refresh,
  pane,
  immersive,
}

enum _Menu { playback, go, window }

class DesktopShortcuts extends StatelessWidget {
  const DesktopShortcuts({
    super.key,
    required this.child,
    required this.player,
    required this.focusSearch,
    this.onPane,
    this.onImmersive,
  });

  final Widget child;
  final PlayerAdapter player;
  final VoidCallback focusSearch;

  /// ⌘⌥B and ⌘⇧F: the desktop shell's; none on a phone.
  final VoidCallback? onPane, onImmersive;

  static bool get _apple =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;

  static SingleActivator _cmd(
    LogicalKeyboardKey k, {
    bool shift = false,
    bool alt = false,
  }) => SingleActivator(
    k,
    meta: _apple,
    control: !_apple,
    shift: shift,
    alt: alt,
  );

  Map<ShellCommand, _Entry> _table(BuildContext context) {
    final l = AppLocalizations.of(context);
    final playback = AppScope.of(context).playback;
    final history = NavHistory.of(context);
    void volume(double by) => player.setVolume(player.volume.value + by);
    return {
      ShellCommand.playPause: _Entry(
        const SingleActivator(LogicalKeyboardKey.space),
        l.actionPlayPause,
        _Menu.playback,
        playback.playPause,
      ),
      ShellCommand.seekBack: _Entry(
        const SingleActivator(LogicalKeyboardKey.arrowLeft),
        l.actionSeekBack,
        _Menu.playback,
        () => player.seekBy(-VDurations.seekStep),
      ),
      ShellCommand.seekForward: _Entry(
        const SingleActivator(LogicalKeyboardKey.arrowRight),
        l.actionSeekForward,
        _Menu.playback,
        () => player.seekBy(VDurations.seekStep),
      ),
      ShellCommand.previous: _Entry(
        const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true),
        l.actionPrevious,
        _Menu.playback,
        playback.previous,
      ),
      ShellCommand.next: _Entry(
        const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true),
        l.actionNext,
        _Menu.playback,
        playback.next,
      ),
      ShellCommand.volumeUp: _Entry(
        _cmd(LogicalKeyboardKey.arrowUp),
        l.actionVolumeUp,
        _Menu.playback,
        () => volume(0.1),
      ),
      ShellCommand.volumeDown: _Entry(
        _cmd(LogicalKeyboardKey.arrowDown),
        l.actionVolumeDown,
        _Menu.playback,
        () => volume(-0.1),
      ),
      ShellCommand.like: _Entry(
        _cmd(LogicalKeyboardKey.keyL),
        l.actionLike,
        _Menu.playback,
        playback.like,
      ),
      ShellCommand.search: _Entry(
        _cmd(LogicalKeyboardKey.keyF),
        l.actionSearch,
        _Menu.go,
        focusSearch,
      ),
      ShellCommand.back: _Entry(
        _cmd(LogicalKeyboardKey.bracketLeft),
        l.actionHistoryBack,
        _Menu.go,
        history.back,
      ),
      ShellCommand.forward: _Entry(
        _cmd(LogicalKeyboardKey.bracketRight),
        l.actionHistoryForward,
        _Menu.go,
        history.forward,
      ),
      ShellCommand.settings: _Entry(
        _cmd(LogicalKeyboardKey.comma),
        l.navSettings,
        _Menu.go,
        () => GoRouter.of(context).go('/settings'),
      ),
      ShellCommand.refresh: _Entry(
        _cmd(LogicalKeyboardKey.keyR),
        l.actionRefreshHome,
        _Menu.go,
        () => refreshHome().ignore(),
      ),
      ShellCommand.pane: _Entry(
        _cmd(LogicalKeyboardKey.keyB, alt: true),
        l.actionTogglePane,
        _Menu.window,
        onPane,
      ),
      ShellCommand.immersive: _Entry(
        _cmd(LogicalKeyboardKey.keyF, shift: true),
        l.actionImmersive,
        _Menu.window,
        onImmersive,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final table = _table(context);
    Widget shell = Shortcuts(
      shortcuts: {
        for (final MapEntry(:key, :value) in table.entries)
          value.keys: _Run(key),
      },
      child: Actions(
        actions: {_Run: _RunAction(table)},
        // Holds the focus when nothing else does, so the keys reach the table.
        child: Focus(autofocus: true, skipTraversal: true, child: child),
      ),
    );
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      shell = PlatformMenuBar(menus: _menus(context, table), child: shell);
    }
    return shell;
  }

  List<PlatformMenuItem> _menus(
    BuildContext context,
    Map<ShellCommand, _Entry> table,
  ) {
    final l = AppLocalizations.of(context);
    List<PlatformMenuItem> items(_Menu m) => [
      for (final MapEntry(:key, :value) in table.entries)
        if (value.menu == m && value.run != null)
          PlatformMenuItem(
            label: value.label,
            shortcut: value.keys,
            onSelectedIntent: _Run(key),
          ),
    ];
    List<PlatformMenuItem> provided(List<PlatformProvidedMenuItemType> types) =>
        [
          for (final t in types)
            if (PlatformProvidedMenuItem.hasMenu(t))
              PlatformProvidedMenuItem(type: t),
        ];
    return [
      PlatformMenu(
        label: l.appName,
        menus: [
          PlatformMenuItemGroup(
            members: provided([PlatformProvidedMenuItemType.about]),
          ),
          PlatformMenuItemGroup(
            members: provided([
              PlatformProvidedMenuItemType.hide,
              PlatformProvidedMenuItemType.hideOtherApplications,
              PlatformProvidedMenuItemType.showAllApplications,
            ]),
          ),
          PlatformMenuItemGroup(
            members: provided([PlatformProvidedMenuItemType.quit]),
          ),
        ],
      ),
      PlatformMenu(label: l.menuPlayback, menus: items(_Menu.playback)),
      PlatformMenu(label: l.menuGo, menus: items(_Menu.go)),
      PlatformMenu(
        label: l.menuWindow,
        menus: [
          ...provided([
            PlatformProvidedMenuItemType.minimizeWindow,
            PlatformProvidedMenuItemType.zoomWindow,
          ]),
          ...items(_Menu.window),
        ],
      ),
    ];
  }
}

class _Entry {
  const _Entry(this.keys, this.label, this.menu, this.run);

  final SingleActivator keys;
  final String label;
  final _Menu menu;
  final VoidCallback? run;
}

class _Run extends Intent {
  const _Run(this.command);

  final ShellCommand command;

  @override
  bool operator ==(Object other) => other is _Run && other.command == command;

  @override
  int get hashCode => command.hashCode;
}

class _RunAction extends Action<_Run> {
  _RunAction(this._table);

  final Map<ShellCommand, _Entry> _table;

  /// Nothing while typing: the key goes on to the text field.
  @override
  bool isEnabled(_Run intent) =>
      _table[intent.command]?.run != null &&
      FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<EditableText>() ==
          null;

  @override
  void invoke(_Run intent) => _table[intent.command]!.run!();
}
