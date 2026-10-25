import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vehicoule/design/design.dart';

import 'harness.dart';

void main() {
  testWidgets('material_ui widgets speak French with our delegates', (
    tester,
  ) async {
    await tester.pumpWidget(harness(const Center(child: CloseButton())));
    expect(find.bySemanticsLabel('Fermer'), findsOneWidget);
    final l = MaterialLocalizations.of(
      tester.element(find.byType(CloseButton)),
    );
    expect(l.closeButtonTooltip, 'Fermer');
    await tester.pumpWidget(
      harness(const Center(child: CloseButton()), locale: const Locale('en')),
    );
    expect(find.bySemanticsLabel('Close'), findsOneWidget);
  });

  testWidgets('accessibility guidelines see material_ui and design widgets', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      harness(
        Center(
          child: VPlayPauseFab(playing: true, loading: false, onPressed: () {}),
        ),
      ),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    // Self-check: the guideline does catch a small material_ui target.
    await tester.pumpWidget(
      harness(
        Center(
          child: SizedBox.square(
            dimension: VSpace.s16,
            child: IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {},
              icon: const VSymbol(VIcons.close, size: VSpace.s12),
              tooltip: 'x',
            ),
          ),
        ),
      ),
    );
    final result = await androidTapTargetGuideline.evaluate(tester);
    expect(result.passed, isFalse);
    handle.dispose();
  });

  testWidgets('the shipped fonts are on the licences page', (tester) async {
    await tester.runAsync(() async {
      vRegisterFontLicenses();
      final packages = <String>{
        await for (final l in LicenseRegistry.licenses) ...l.packages,
      };
      expect(
        packages,
        containsAll([
          'Google Sans Flex',
          'Noto Sans JP',
          'Material Symbols Rounded',
        ]),
      );
    });
  });
}
