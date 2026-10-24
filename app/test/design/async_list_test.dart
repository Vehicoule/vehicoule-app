import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vehicoule/bridge/error.dart';
import 'package:vehicoule/design/design.dart';

import 'harness.dart';

void main() {
  testWidgets(
    'a list has its four states: loading, empty, error with retry, offline',
    (tester) async {
      late Future<List<String>> Function() next;
      var loads = 0;
      Future<void> show() async {
        await tester.pumpWidget(harness(const SizedBox()));
        await tester.pumpWidget(
          harness(
            CustomScrollView(
              slivers: [
                VAsyncList<String>(
                  load: () {
                    loads++;
                    return next();
                  },
                  builder: (context, items) => SliverList.builder(
                    itemCount: items.length,
                    itemBuilder: (_, i) => Text(items[i]),
                  ),
                  empty: VEmptyState(
                    icon: VIcons.favorite,
                    message: fr().emptyLikes,
                  ),
                  errorText: (e) => 'broken',
                ),
              ],
            ),
            reduce: true,
          ),
        );
        await tester.pump();
      }

      final pending = Completer<List<String>>();
      next = () => pending.future;
      await show();
      expect(find.byType(VLoading), findsOneWidget);
      pending.complete(['Get Lucky']);
      await tester.pump();
      await tester.pump();
      expect(find.text('Get Lucky'), findsOneWidget);

      next = () async => [];
      await show();
      expect(find.text(fr().emptyLikes), findsOneWidget);

      next = () async => throw const CoreError.network();
      await show();
      expect(find.text('broken'), findsOneWidget);
      next = () async => ['Get Lucky'];
      final before = loads;
      await tester.tap(find.text(fr().actionRetry));
      // M3E buttons fire after their press feedback.
      await tester.pump(VDurations.short);
      await tester.pump(VDurations.short);
      expect(loads, before + 1);
      expect(find.text('Get Lucky'), findsOneWidget);

      next = () async => throw const CoreError.offline();
      await show();
      expect(find.text(fr().errorOffline), findsOneWidget);
      expect(find.text('broken'), findsNothing);
    },
  );
}
