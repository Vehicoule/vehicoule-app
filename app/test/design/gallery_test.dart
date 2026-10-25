import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vehicoule/design/design.dart';
import 'package:vehicoule/design/gallery.dart';

void main() {
  for (final width in [400.0, 1280.0]) {
    testWidgets(
      'gallery renders every component without overflow at $width dp',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final errors = <FlutterErrorDetails>[];
        final old = FlutterError.onError;
        FlutterError.onError = errors.add;
        addTearDown(() => FlutterError.onError = old);

        await tester.pumpWidget(const GalleryApp());
        await tester.pump(const Duration(milliseconds: 500));
        for (final type in [
          VArtwork,
          VDecor,
          VWaveArtwork,
          VWaveProgress,
          VDownloadIcon,
          VControls,
          VPlayPauseFab,
          VViewSelector,
          VNowPlaying,
          VTrackRow,
          VShelf,
          VHeroCard,
          VSplitButton,
          VConnectedGroup,
          VLoading,
          VEmptyState,
          VOfflineChip,
          VSideSheet,
          VFlexibleHeader,
        ]) {
          expect(
            find.byType(type, skipOffstage: false),
            findsWidgets,
            reason: '$type',
          );
        }
        // 3 sizes × 2 styles × 3 views, then playing, paused and loading.
        expect(
          find.byType(VNowPlaying, skipOffstage: false).evaluate().length,
          greaterThanOrEqualTo(18),
        );
        FlutterError.onError = old;
        for (final e in errors) {
          debugPrint(e.toString());
        }
        expect(errors.map((e) => e.exceptionAsString()), isEmpty);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
