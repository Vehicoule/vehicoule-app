/// The app's domains (addendum « navigation entre domaines » §2, §3, §11): music in v1;
/// videos (films, series, anime) and books join with their specs. The one list the branches, the bar, the rail,
/// the domain rail and the home chips are built from, and the one reading of the current
/// domain ([domainOf]).
library;

import 'package:material_ui/material_ui.dart';

import 'design/design.dart';
import 'l10n/app_localizations.dart';

/// Internal names, as the WIT packages (`vehicoule:music`).
enum Domain { music }

/// Every domain, in their order in the domain rail and the home chips.
const List<Domain> domains = [Domain.music];

/// A destination of a domain, after Accueil in the bar and the rail.
class DomainDestination {
  const DomainDestination({
    required this.path,
    required this.icon,
    required this.label,
  });

  final String path;
  final IconData icon;
  final String Function(AppLocalizations l) label;
}

/// Accueil: shared by every domain, always first.
final home = DomainDestination(
  path: '/home',
  icon: VIcons.home,
  label: (l) => l.navHome,
);

List<DomainDestination> destinationsOf(Domain d) => switch (d) {
  Domain.music => _music,
};

final _music = [
  DomainDestination(
    path: '/music/explore',
    icon: VIcons.explore,
    label: (l) => l.navExplore,
  ),
  DomainDestination(
    path: '/music/library',
    icon: VIcons.library,
    label: (l) => l.navLibrary,
  ),
];

/// The domain's search destination (Entrée in the title bar's search, ⌘F on a phone).
String searchRoot(Domain d) => switch (d) {
  Domain.music => '/music/explore',
};

/// The domain's library destination (the pinned items lead there).
String libraryRoot(Domain d) => switch (d) {
  Domain.music => '/music/library',
};

/// The entity kinds a page of [d] opens from Accueil (`/home/<d>/<kind>/:id`).
List<String> homeKinds(Domain d) => switch (d) {
  Domain.music => const ['album', 'artist', 'playlist', 'category'],
};

/// The entity kinds a destination opens inside its own branch.
List<String> kindsUnder(String root) => switch (root) {
  '/music/explore' => const ['album', 'artist', 'playlist', 'category'],
  '/music/library' => const ['album', 'artist', 'playlist'],
  _ => const [],
};

/// The domain's icon and name (the domain rail, its FAB menu, the home chips).
IconData domainIcon(Domain d) => switch (d) {
  Domain.music => VIcons.musicNote,
};

String domainLabel(AppLocalizations l, Domain d) => switch (d) {
  Domain.music => l.domainMusic,
};

/// The current domain: the location's (`/<domain>/…` or `/home/<domain>/…`), else
/// [stored] (`ui.domain`): Accueil alone and the global sections keep the last one.
Domain domainOf(String location, {required Domain stored}) =>
    _named(location) ?? stored;

/// The domain the location names, if it names one.
Domain? _named(String location) {
  final s = Uri.parse(location).pathSegments;
  final name = s.isEmpty
      ? null
      : s.first == 'home'
      ? (s.length > 1 ? s[1] : null)
      : s.first;
  return Domain.values.asNameMap()[name];
}

/// The domain a location explicitly names (to write `ui.domain`), or null.
Domain? namedDomain(String location) => _named(location);

/// The two playback sessions (addendum §5): music now, video with the videos spec.
enum PlaybackSession { music }

/// Tests: what [sessionTarget] answers.
@visibleForTesting
PlaybackSession Function(BuildContext context)? debugSessionTarget;

/// The session the playback keys and menu items act on (addendum §5.3). v1: music.
PlaybackSession sessionTarget(BuildContext context) =>
    debugSessionTarget?.call(context) ?? PlaybackSession.music;
