// ☰ on a phone (spec UI §4.1): the expanded rail, modal, in place of a drawer: the
// domains (Musique for now), then the global sections, Sources and Téléchargements.
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../design/design.dart';
import '../l10n/app_localizations.dart';
import 'mobile_shell.dart';

class DomainRail extends StatelessWidget {
  const DomainRail({super.key});

  static const _routes = ['/home', '/settings/sources', '/downloads'];

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final at = GoRouterState.of(context).uri.path;
    final selected = _routes.lastIndexWhere((r) => at.startsWith(r));
    void close() => Scaffold.of(context).closeDrawer();
    // The modal rail's sheet: under the status bar too, its end corners rounded.
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadiusDirectional.horizontal(
          end: Radius.circular(VRadius.medium),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        child: SizedBox(
          width: VSize.railExpanded,
          child: VNavigationRail(
            destinations: [
              VDestination(l.domainMusic, VIcons.musicNote),
              VDestination(l.sourcesTitle, VIcons.source),
              VDestination(l.downloadsTitle, VIcons.download),
            ],
            pinned: const [],
            selected: selected < 0 ? 0 : selected,
            expanded: true,
            onExpanded: (_) => close(),
            onSelected: (i) {
              close();
              // Musique keeps the current destination; the others are pages.
              if (i > 0) context.go(_routes[i]);
            },
          ),
        ),
      ),
    );
  }
}

/// ☰ for a destination's large app bar, on a phone only (a wider window has its rail).
Widget? domainMenuButton(BuildContext context) {
  final shell = MobileShell.maybeOf(context);
  if (shell == null || shell.widget.medium) return null;
  return VIconButton(
    icon: VIcons.menu,
    label: AppLocalizations.of(context).actionOpenMenu,
    onPressed: shell.openMenu,
  );
}
