import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vehicoule/design/design.dart';
import 'package:vehicoule/design/gallery.dart';
import 'package:vehicoule/l10n/app_localizations.dart';

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
        FlutterError.onError = old;
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
          // The M3 set the app uses (spec UI §4, §5.4, §5.8, §6).
          VFab,
          VExtendedFab,
          VFabMenu,
          VChoiceGroup<PlayerStyle>,
          VIconButton,
          VToolbar,
          VStandardSheet,
          VCarousel,
          VChip,
          VSwitch,
          VBadge,
          VRichTooltip,
          VListGroup,
          VNavigationBar,
          VNavigationRail,
          VSearchBar,
          VLargeAppBar,
          VCircularProgress,
          VVolume,
          VSkeleton,
          VRefresh,
          VAsyncList<String>,
          VSlider,
          VExtentFlight,
        ]) {
          expect(
            find.byType(type, skipOffstage: false),
            findsWidgets,
            reason: '$type',
          );
        }
        // Large and medium × 2 styles × 3 views, the immersive view, the mini player
        // playing, paused and loading, the strip.
        expect(
          find.byType(VNowPlaying, skipOffstage: false).evaluate().length,
          greaterThanOrEqualTo(18),
        );
        // Every section, reachable from the jump list.
        final l = lookupAppLocalizations(const Locale('fr'));
        for (final title in [
          l.galleryArtwork,
          l.galleryMiniPlayer,
          l.galleryFabs,
          l.galleryButtonGroups,
          l.galleryToolbars,
          l.galleryMenus,
          l.gallerySheets,
          l.galleryNavigation,
          l.gallerySearch,
          l.galleryCarousels,
          l.gallerySettings,
          l.galleryStates,
        ]) {
          expect(
            find.text(title, skipOffstage: false),
            findsAtLeastNWidgets(2),
            reason: '$title: a jump chip and a heading',
          );
        }
        for (final e in errors) {
          debugPrint(e.toString());
        }
        expect(errors.map((e) => e.exceptionAsString()), isEmpty);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
