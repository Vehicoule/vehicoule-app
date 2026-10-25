import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vehicoule/design/design.dart';

import 'harness.dart';

/// The splash's transforms, as matrices.
Iterable<Matrix4> _moves(WidgetTester t) => t
    .widgetList<Transform>(
      find.descendant(
        of: find.byKey(SplashOverlay.overlayKey),
        matching: find.byType(Transform),
      ),
    )
    .map((w) => w.transform);

double _opacity(WidgetTester t) => t
    .widget<FadeTransition>(
      find
          .descendant(
            of: find.byKey(SplashOverlay.overlayKey),
            matching: find.byType(FadeTransition),
          )
          .first,
    )
    .opacity
    .value;

void main() {
  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

  testWidgets('splash is static with reduce motion', (t) async {
    await t.pumpWidget(
      harness(const SplashOverlay(child: Text('home')), reduce: true),
    );
    expect(find.text('home'), findsOneWidget);
    expect(find.byKey(SplashOverlay.overlayKey), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      // The fixed icon: nothing moves, the whole splash only fades.
      expect(_moves(t), everyElement(Matrix4.identity()));
      await t.pump(VDurations.splashFade ~/ 4);
    }
    await t.pump(VDurations.splashFade);
    expect(find.byKey(SplashOverlay.overlayKey), findsNothing);
    expect(find.text('home'), findsOneWidget);
  }, variant: desktop);

  testWidgets('splash bounces the Mochi, then fades within 900 ms', (t) async {
    await t.pumpWidget(harness(const SplashOverlay(child: Text('home'))));
    await t.pump(VDurations.splash * 0.35);
    expect(_moves(t).any((m) => m != Matrix4.identity()), isTrue);
    expect(_opacity(t), 1);
    await t.pump(VDurations.splash * 0.55);
    expect(_opacity(t), lessThan(1));
    await t.pump(VDurations.splash * 0.1 + const Duration(milliseconds: 1));
    await t.pump();
    expect(find.byKey(SplashOverlay.overlayKey), findsNothing);
    expect(
      VDurations.splash,
      lessThanOrEqualTo(const Duration(milliseconds: 900)),
    );
  }, variant: desktop);

  testWidgets('no splash on Android (the system shows it)', (t) async {
    await t.pumpWidget(harness(const SplashOverlay(child: Text('home'))));
    expect(find.byKey(SplashOverlay.overlayKey), findsNothing);
    expect(find.text('home'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
