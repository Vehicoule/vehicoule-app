// The keyboard (spec UI §4.2, §4.4): every shortcut, none while typing, one table for
// the keys and the macOS menu bar, the tab order, roving focus in a track table.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vehicoule/design/design.dart';
import 'package:vehicoule/shell_desktop/shortcuts.dart';
import 'package:vehicoule/shell_desktop/title_bar.dart';

import 'rig.dart';

bool _typing() =>
    FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<EditableText>() !=
    null;

/// Which part of the window has the keyboard focus.
String? _region(WidgetTester tester) {
  final c = FocusManager.instance.primaryFocus?.context;
  if (c == null) return null;
  bool inside(Finder f) => f.evaluate().any((e) => c == e || _isAncestor(e, c));
  if (inside(find.byType(TitleBar))) {
    return 'title';
  }
  if (inside(find.byType(VNavigationRail))) return 'rail';
  if (inside(find.byType(VSideSheet))) return 'pane';
  return 'content';
}

bool _isAncestor(Element a, BuildContext c) {
  var found = false;
  c.visitAncestorElements((e) {
    found = e == a;
    return !found;
  });
  return found;
}

/// Shows the queue in the pane, its rows a track table.
Future<void> _queue(WidgetTester tester) async {
  // The view menu, then File.
  await tester.tap(
    find.descendant(
      of: find.byType(VSideSheet),
      matching: find.byKey(VNowPlaying.selectorKey),
    ),
  );
  await settle(tester, 10);
  await tester.tap(find.text('File'));
  await settle(tester, 10);
}

Finder get _rows => find.descendant(
  of: find.byType(VSideSheet),
  matching: find.byType(VTrackRow),
);

void main() {
  testWidgets('every 4.2 shortcut reaches its action', (tester) async {
    final r = Rig();
    await r.pump(tester, size: desktop);
    await r.player.setVolume(0.5);

    await key(tester, LogicalKeyboardKey.space);
    expect(r.backend.calls.last, 'play');

    r.backend.positions.add(const Duration(seconds: 30));
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(r.backend.calls.last, 'seek 40000');
    await key(tester, LogicalKeyboardKey.arrowLeft);
    expect(r.backend.calls.last, 'seek 30000');

    await key(tester, LogicalKeyboardKey.arrowRight, shift: true);
    expect(r.names.last, #crateApiPlaybackSkipNext);
    await key(tester, LogicalKeyboardKey.arrowLeft, shift: true);
    expect(r.names.last, #crateApiPlaybackPrevious);

    await key(tester, LogicalKeyboardKey.arrowUp, meta: true);
    expect(r.player.volume.value, closeTo(0.6, 1e-9));
    await key(tester, LogicalKeyboardKey.arrowDown, meta: true);
    expect(r.player.volume.value, closeTo(0.5, 1e-9));

    await key(tester, LogicalKeyboardKey.keyL, meta: true);
    // Back on the first track (liked): ⌘L unlikes it.
    final like = r.last(#crateApiLibrarySetLiked)!;
    expect(like.namedArguments[#id], 'track:1');
    expect(like.namedArguments[#liked], isFalse);

    await key(tester, LogicalKeyboardKey.keyR, meta: true);
    expect(r.names.last, #crateApiLibraryRefreshHome);

    await key(tester, LogicalKeyboardKey.comma, meta: true);
    expect(location(tester), '/settings');
    await key(tester, LogicalKeyboardKey.bracketLeft, meta: true);
    expect(location(tester), '/home');
    await key(tester, LogicalKeyboardKey.bracketRight, meta: true);
    expect(location(tester), '/settings');

    expect(tester.widget<VSideSheet>(find.byType(VSideSheet)).open, isTrue);
    await key(tester, LogicalKeyboardKey.keyB, meta: true, alt: true);
    await settle(tester, 10);
    expect(tester.widget<VSideSheet>(find.byType(VSideSheet)).open, isFalse);

    await key(tester, LogicalKeyboardKey.keyF, meta: true, shift: true);
    expect(
      find.byWidgetPredicate((w) => w is VNowPlaying && w.immersive),
      findsOneWidget,
    );
    await key(tester, LogicalKeyboardKey.escape);

    await key(tester, LogicalKeyboardKey.keyF, meta: true);
    expect(_typing(), isTrue, reason: '⌘F: the search field');
  }, variant: mac);

  testWidgets('shortcuts_ignored_while_typing', (tester) async {
    final r = Rig();
    await r.pump(tester, size: desktop);
    await key(tester, LogicalKeyboardKey.keyF, meta: true);
    expect(_typing(), isTrue);
    final before = [...r.backend.calls];
    final names = [...r.names];
    await key(tester, LogicalKeyboardKey.space);
    await key(tester, LogicalKeyboardKey.arrowRight, shift: true);
    await key(tester, LogicalKeyboardKey.keyL, meta: true);
    expect(r.backend.calls, before, reason: 'the player is untouched');
    expect(r.names, names, reason: 'nothing reached the core');
    expect(_typing(), isTrue);
  }, variant: mac);

  testWidgets('space selects in a focused track table', (tester) async {
    final r = Rig();
    await r.pump(tester, size: desktop);
    await _queue(tester);
    expect(_rows, findsWidgets);
    rowFocus(tester, _rows.first).requestFocus();
    await settle(tester, 2);
    await key(tester, LogicalKeyboardKey.space);
    expect(tester.widget<VTrackRow>(_rows.first).selected, isTrue);
    expect(r.backend.calls, isNot(contains('play')));
    expect(r.backend.calls, isNot(contains('pause')));
  }, variant: mac);

  testWidgets('arrow keys move focus inside a track table', (tester) async {
    final r = Rig();
    await r.pump(tester, size: desktop);
    await _queue(tester);
    expect(_rows.evaluate().length, greaterThan(2));
    final rows = [for (var i = 0; i < 3; i++) rowFocus(tester, _rows.at(i))];
    rows[0].requestFocus();
    await settle(tester, 2);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(FocusManager.instance.primaryFocus, rows[1]);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(FocusManager.instance.primaryFocus, rows[2]);
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(FocusManager.instance.primaryFocus, rows[1]);
    // Tab entered once: it leaves the table instead of walking its rows.
    await key(tester, LogicalKeyboardKey.tab);
    final all = [
      for (var i = 0; i < _rows.evaluate().length; i++)
        rowFocus(tester, _rows.at(i)),
    ];
    expect(all, isNot(contains(FocusManager.instance.primaryFocus)));
  }, variant: mac);

  testWidgets('tab order is title bar, rail, content, panel', (tester) async {
    final r = Rig();
    await r.pump(tester, size: desktop);
    tester.binding.focusManager.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    final seen = <String>[];
    for (var i = 0; i < 60; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final region = _region(tester);
      if (region != null && (seen.isEmpty || seen.last != region)) {
        seen.add(region);
      }
      if (seen.length >= 4) break;
    }
    // The placeholder page holds nothing to focus: Tab passes over it
    // (SkipEmptyScopes) instead of sticking to its route; the regions' order puts
    // the content's own controls between the rail and the pane (Tasks 6 and 7).
    expect(seen.take(3), ['title', 'rail', 'pane']);
  }, variant: mac);

  testWidgets('cmd+f focuses search', (tester) async {
    final r = Rig();
    await r.pump(tester, size: desktop);
    await key(tester, LogicalKeyboardKey.keyF, meta: true);
    // The title bar's search opens, its field focused.
    expect(_typing(), isTrue);
  }, variant: mac);

  testWidgets('ctrl+f on a phone goes to Explorer', (tester) async {
    final r = Rig();
    await r.pump(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);
    expect(location(tester), '/music/explore');
  });

  testWidgets('menu bar items and shortcuts share one intent table', (
    tester,
  ) async {
    final r = Rig();
    await r.pump(tester, size: desktop);
    final bar = tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar));
    final items = <PlatformMenuItem>[];
    void walk(List<PlatformMenuItem> m) {
      for (final i in m) {
        if (i is PlatformMenu) {
          walk(i.menus);
        } else if (i is PlatformMenuItemGroup) {
          walk(i.members);
        } else {
          items.add(i);
        }
      }
    }

    walk(bar.menus);
    final fromMenu = {
      for (final i in items)
        if (i.shortcut case final SingleActivator s)
          _key(s): i.onSelectedIntent,
    };
    final shortcuts = tester
        .widgetList<Shortcuts>(
          find.descendant(
            of: find.byType(DesktopShortcuts),
            matching: find.byType(Shortcuts),
          ),
        )
        .first;
    final fromKeys = {
      for (final MapEntry(:key, :value) in shortcuts.shortcuts.entries)
        if (key case final SingleActivator s) _key(s): value,
    };
    // Every command is a menu item with the key's own intent; the menu shows only
    // the ⌘ shortcuts (a bare key there could be taken from a text field by AppKit).
    expect(items.where((i) => i.onSelectedIntent != null), hasLength(15));
    expect(
      {for (final i in items) i.onSelectedIntent}..remove(null),
      fromKeys.values.toSet(),
    );
    expect(fromMenu.entries.every((e) => fromKeys[e.key] == e.value), isTrue);
    expect([
      for (final i in items)
        if (i.shortcut case final SingleActivator s) s.meta || s.control,
    ], everyElement(isTrue));
    expect(fromKeys, hasLength(ShellCommand.values.length));
    // A menu item runs the same action as its key.
    final refresh = items.firstWhere(
      (i) =>
          i.shortcut is SingleActivator &&
          (i.shortcut! as SingleActivator).trigger == LogicalKeyboardKey.keyR,
    );
    Actions.invoke(
      FocusManager.instance.primaryFocus!.context!,
      refresh.onSelectedIntent!,
    );
    await settle(tester);
    expect(r.names.last, #crateApiLibraryRefreshHome);
  }, variant: mac);

  testWidgets('window bounds are saved and restored', (tester) async {
    final r = Rig();
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (c) async {
        calls.add(c);
        return c.method == 'getBounds'
            ? {'x': 10.0, 'y': 20.0, 'width': 1000.0, 'height': 700.0}
            : null;
      },
    );
    final keeper = WindowKeeper();
    keeper.onWindowResized();
    keeper.onWindowMoved();
    await tester.pump(VDurations.debounce);
    await tester.pump();
    final saved = r.api.prefs['ui.window_bounds'];
    expect(jsonDecode(saved!), {
      'x': 10.0,
      'y': 20.0,
      'width': 1000.0,
      'height': 700.0,
    });
    expect(
      r.names.where((n) => n == #crateApiSettingsSetUiPref),
      hasLength(1),
      reason: 'debounced',
    );
    calls.clear();
    await WindowKeeper.restore();
    final set = calls.firstWhere((c) => c.method == 'setBounds');
    final a = set.arguments as Map;
    expect(
      [a['x'], a['y'], a['width'], a['height']],
      [10.0, 20.0, 1000.0, 700.0],
    );
  });
}

String _key(SingleActivator s) =>
    '${s.trigger.keyId}${s.meta}${s.control}${s.shift}${s.alt}';
