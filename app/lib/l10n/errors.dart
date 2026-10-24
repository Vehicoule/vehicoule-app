import '../bridge/error.dart';
import 'app_localizations.dart';

/// The one sentence the UI shows for a core error (voice: docs/voice.md). The switch is
/// exhaustive, so a new bridge variant fails to compile until it has a message.
String errorMessage(AppLocalizations l, CoreError e) => switch (e) {
  CoreError_Network() => l.errorNetwork,
  CoreError_ProviderWall() => l.errorProviderWall,
  CoreError_RateLimited() => l.errorRateLimited,
  CoreError_BudgetExceeded() => l.errorBudgetExceeded,
  CoreError_NotFound() => l.errorNotFound,
  CoreError_Expired() => l.errorExpired,
  // The detail goes to diagnostics and telemetry, never on screen.
  CoreError_Internal() => l.errorInternal,
  CoreError_Offline() => l.errorOffline,
  CoreError_InvalidFeed() => l.errorInvalidFeed,
  CoreError_NoPlugin(field0: final c) => switch (c) {
    Capability.search || Capability.suggest => l.errorNoSourceSearch,
    Capability.entity => l.errorNoSourceEntity,
    Capability.resolve => l.errorNoSourcePlay,
    Capability.lyrics => l.errorNoSourceLyrics,
    Capability.radio => l.errorNoSourceRadio,
    Capability.browse => l.errorNoSourceBrowse,
  },
};
