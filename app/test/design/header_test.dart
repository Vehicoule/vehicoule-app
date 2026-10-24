import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vehicoule/design/design.dart';

import 'harness.dart';

Widget page() => CustomScrollView(
  slivers: [
    VFlexibleHeader(
      artwork: const VArtwork(itemId: 'album:RAM', size: 240, playing: false),
      title: 'Random Access Memories',
      subtitle: 'Daft Punk',
      actions: [TextButton(onPressed: () {}, child: const Text('Lire'))],
      fab: VPlayPauseFab(playing: false, loading: false, onPressed: () {}),
    ),
    SliverList.builder(
      itemCount: 60,
      itemBuilder: (_, i) =>
          SizedBox(height: VSize.trackRow, child: Text('row $i')),
    ),
  ],
);

void main() {
  testWidgets('flexible header docks the artwork into the app bar on scroll', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness(page(), reduce: true));
    final art = find.byType(VArtwork);
    expect(tester.getSize(art).height, greaterThan(150));
    expect(find.text('Lire'), findsOneWidget);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
    await tester.pumpAndSettle();
    final docked = tester.getRect(art);
    expect(docked.height, lessThanOrEqualTo(VSize.compactArt));
    final bar = tester.getRect(find.byKey(VFlexibleHeader.barKey));
    expect(bar.height, lessThan(120));
    expect(
      bar.contains(docked.center),
      isTrue,
      reason: 'the artwork sits in the app bar',
    );
    expect(
      bar.contains(tester.getCenter(find.text('Random Access Memories'))),
      isTrue,
    );
    // The extended actions became the FAB.
    expect(find.byType(VPlayPauseFab), findsOneWidget);
  });

  testWidgets('flexible header is horizontal on wide windows', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness(page(), reduce: true));
    final art = tester.getRect(find.byType(VArtwork));
    final title = tester.getRect(find.text('Random Access Memories'));
    expect(
      title.left,
      greaterThan(art.right),
      reason: 'artwork left, title right',
    );
  });
}
