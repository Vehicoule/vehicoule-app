// ☰ on a phone (spec UI §4.1, addendum §2.1): the expanded rail, modal, in place of a
// drawer: 1. the domains (Musique in v1), 2. the global sections (Téléchargements,
// Sources, Réglages).
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../design/design.dart';
import '../domains.dart';
import '../l10n/app_localizations.dart';
import '../router.dart';
import 'mobile_shell.dart';

class DomainRail extends StatelessWidget {
  const DomainRail({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final history = NavHistory.of(context);
    final globals = globalSections(l);
    final at = Uri.parse(history.location).path;
    final global = globals.indexWhere(
      (g) => at == g.$1 || at.startsWith('${g.$1}/'),
    );
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
              for (final d in domains)
                VDestination(domainLabel(l, d), domainIcon(d)),
            ],
            pinned: const [],
            selected: global < 0 ? domains.indexOf(history.domain) : -1,
            expanded: true,
            onExpanded: (_) => close(),
            // A domain: its last destination, its branch keeping its stack.
            onSelected: (i) {
              close();
              final shell = MobileShell.maybeOf(context)?.widget.shell;
              final path = history.destinationOf(domains[i]);
              if (shell != null) {
                goDestination(shell, path);
              } else {
                context.go(path);
              }
            },
            globals: [for (final g in globals) g.$2],
            globalSelected: global < 0 ? null : global,
            onGlobal: (i) {
              close();
              context.go(globals[i].$1);
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
