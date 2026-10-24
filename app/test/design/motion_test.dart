import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vehicoule/design/design.dart';

import 'harness.dart';

typedef PageMaker = Page<void> Function(Widget child);

final makers = <String, PageMaker>{
  'container transform': (c) =>
      vContainerTransformPage(key: const ValueKey('p'), child: c, heroTag: 'h'),
  'fade through': (c) => vFadeThroughPage(key: const ValueKey('p'), child: c),
};

Future<void> pushOnto(
  WidgetTester tester,
  PageMaker make, {
  required bool reduce,
}) async {
  final pages = ValueNotifier<List<Page<void>>>([
    const MaterialPage(key: ValueKey('home'), child: SizedBox.shrink()),
  ]);
  await tester.pumpWidget(
    harness(
      ValueListenableBuilder(
        valueListenable: pages,
        builder: (context, p, _) =>
            Navigator(key: inner, pages: p, onDidRemovePage: (_) {}),
      ),
      reduce: reduce,
    ),
  );
  pages.value = [
    ...pages.value,
    make(const Text('next', key: ValueKey('next'))),
  ];
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

final inner = GlobalKey<NavigatorState>();

/// Transitions between [scope] and [child] (the app's own route transitions are outside).
Finder between(Key scope, Finder child, Type t) => find.descendant(
  of: find.byKey(scope),
  matching: find.ancestor(of: child, matching: find.byType(t)),
);

List<Type> transitionsAbove(WidgetTester tester) => [
  for (final t in [ScaleTransition, SlideTransition])
    if (between(
      inner,
      find.byKey(const ValueKey('next')),
      t,
    ).evaluate().isNotEmpty)
      t,
];

void main() {
  testWidgets('reduce motion turns every page transition into a fade', (
    tester,
  ) async {
    for (final MapEntry(key: name, value: make) in makers.entries) {
      await pushOnto(tester, make, reduce: true);
      expect(transitionsAbove(tester), isEmpty, reason: name);
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('next')),
          matching: find.byType(FadeTransition),
        ),
        findsWidgets,
        reason: name,
      );
      await tester.pump(VDurations.reduced);
      expect(
        tester.binding.hasScheduledFrame,
        isFalse,
        reason: '$name lasts 150 ms',
      );
    }
    // Self-check: without reduce motion, fade through also scales.
    await pushOnto(tester, makers['fade through']!, reduce: false);
    expect(transitionsAbove(tester), contains(ScaleTransition));
    await tester.pumpAndSettle();
  });

  testWidgets('shared axis slides, or fades with reduce motion', (
    tester,
  ) async {
    for (final reduce in [false, true]) {
      final key = ValueNotifier<int>(0);
      await tester.pumpWidget(
        harness(
          KeyedSubtree(
            key: const ValueKey('axis'),
            child: ValueListenableBuilder(
              valueListenable: key,
              builder: (context, k, _) =>
                  vSharedAxis(key: k, child: Text('view $k')),
            ),
          ),
          reduce: reduce,
        ),
      );
      key.value = 1;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      final slides = between(
        const ValueKey('axis'),
        find.text('view 1'),
        SlideTransition,
      );
      expect(slides.evaluate().isEmpty, reduce);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('entrances stagger, and show at once with reduce motion', (
    tester,
  ) async {
    double opacity(String t) => tester
        .widget<FadeTransition>(
          find
              .ancestor(of: find.text(t), matching: find.byType(FadeTransition))
              .first,
        )
        .opacity
        .value;
    Widget shelves() => Column(
      children: [vEntrance(0, const Text('a')), vEntrance(6, const Text('b'))],
    );
    await tester.pumpWidget(harness(shelves()));
    await tester.pump(VDurations.medium * 0.6);
    expect(
      opacity('a'),
      greaterThan(opacity('b')),
      reason: 'the later one is behind',
    );
    await tester.pumpAndSettle();
    expect(opacity('b'), 1);
    await tester.pumpWidget(harness(const SizedBox()));
    await tester.pumpWidget(harness(shelves(), reduce: true));
    expect(opacity('b'), 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  test('haptics are silent on desktop', () {
    final calls = <MethodCall>[];
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
    for (final p in [
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      debugDefaultTargetPlatformOverride = p;
      VHaptics.light();
      VHaptics.selection();
      VHaptics.medium();
    }
    expect(calls.where((c) => c.method.startsWith('HapticFeedback')), isEmpty);
    // Self-check: the same calls reach the channel on a phone.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    VHaptics.light();
    VHaptics.selection();
    VHaptics.medium();
    expect(
      calls.where((c) => c.method.startsWith('HapticFeedback')),
      hasLength(3),
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('reduce motion settles in one frame', (tester) async {
    await tester.pumpWidget(
      harness(
        Center(
          child: Builder(
            builder: (context) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                VArtwork(
                  itemId: 'a',
                  size: 200,
                  playing: true,
                  progress: 0.3,
                  onSeek: (_) {},
                ),
                // A plain detector: a button's ink ripple would be motion of its own.
                GestureDetector(
                  onTap: () => showVMenu(
                    context,
                    anchor: const Rect.fromLTWH(10, 10, 100, 40),
                    quick: [VAction('Lire ensuite', VIcons.playNext, () {})],
                    groups: [
                      [VAction("Aller à l'album", VIcons.album, () {})],
                    ],
                  ),
                  child: const Text('open'),
                ),
              ],
            ),
          ),
        ),
        reduce: true,
      ),
    );
    await tester.pump();
    expect(
      tester.binding.hasScheduledFrame,
      isFalse,
      reason: 'the ring and cookie are still',
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump();
    expect(find.text("Aller à l'album"), findsOneWidget);
    expect(
      tester.binding.hasScheduledFrame,
      isFalse,
      reason: 'the menu is open, nothing moves',
    );
  });
}
