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

  testWidgets('a stream-backed list follows its stream', (tester) async {
    final items = StreamController<List<String>>();
    addTearDown(items.close);
    await tester.pumpWidget(
      harness(
        CustomScrollView(
          slivers: [
            VAsyncList<String>.stream(
              watch: () => items.stream,
              builder: (context, list) => SliverList.builder(
                itemCount: list.length,
                itemBuilder: (_, i) => Text(list[i]),
              ),
              empty: VEmptyState(icon: VIcons.queue, message: fr().emptyLikes),
              errorText: (e) => 'broken',
            ),
          ],
        ),
        reduce: true,
      ),
    );
    expect(find.byType(VLoading), findsOneWidget);
    items.add(['Get Lucky']);
    await tester.pump();
    expect(find.text('Get Lucky'), findsOneWidget);
    items.add(['Get Lucky', 'Je veux']);
    await tester.pump();
    await tester.pump();
    expect(find.text('Je veux'), findsOneWidget);
    items.add([]);
    await tester.pump();
    await tester.pump();
    expect(find.text(fr().emptyLikes), findsOneWidget);
  });

  testWidgets('a new reload key loads again, the same key does not', (
    tester,
  ) async {
    var loads = 0;
    Widget list(Object key) => CustomScrollView(
      slivers: [
        VAsyncList<String>(
          reloadKey: key,
          load: () async {
            loads++;
            return ['Get Lucky'];
          },
          builder: (context, list) => SliverList.builder(
            itemCount: list.length,
            itemBuilder: (_, i) => Text(list[i]),
          ),
          empty: const SizedBox(),
          errorText: (e) => 'broken',
        ),
      ],
    );
    await tester.pumpWidget(harness(list('a'), reduce: true));
    await tester.pump();
    await tester.pumpWidget(harness(list('a'), reduce: true));
    await tester.pump();
    expect(loads, 1, reason: 'a rebuild with new closures is not a reload');
    await tester.pumpWidget(harness(list('b'), reduce: true));
    await tester.pump();
    expect(loads, 2);
  });

  testWidgets('a long list loads page by page, 100 at a time', (tester) async {
    final asked = <(int, int)>[];
    await tester.pumpWidget(
      harness(
        CustomScrollView(
          slivers: [
            VAsyncList<int>.paged(
              page: (offset, limit) async {
                asked.add((offset, limit));
                final end = (offset + limit).clamp(0, 250);
                return [for (var i = offset; i < end; i++) i];
              },
              itemBuilder: (context, n, i) =>
                  SizedBox(height: VSize.trackRow, child: Text('row $n')),
              empty: const SizedBox(),
              errorText: (e) => 'broken',
            ),
          ],
        ),
        reduce: true,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(asked, [(0, 100)], reason: 'one page to start');
    expect(find.text('row 0'), findsOneWidget);
    // Scrolling near the end of what is loaded asks for the next page, until the end.
    for (var i = 0; i < 30; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
      await tester.pump();
      await tester.pump();
    }
    expect(asked, [(0, 100), (100, 100), (200, 100)]);
    expect(find.text('row 249'), findsOneWidget);
  });

  testWidgets('a stream that ends without items is empty, not loading', (tester) async {
    await tester.pumpWidget(harness(CustomScrollView(slivers: [
      VAsyncList<String>.stream(
        watch: () => const Stream<List<String>>.empty(),
        builder: (context, list) => SliverList.builder(itemCount: list.length, itemBuilder: (_, i) => Text(list[i])),
        empty: VEmptyState(icon: VIcons.queue, message: fr().emptyLikes),
        errorText: (e) => 'broken',
      ),
    ]), reduce: true));
    await tester.pump();
    await tester.pump();
    expect(find.byType(VLoading), findsNothing);
    expect(find.text(fr().emptyLikes), findsOneWidget);
  });
}
