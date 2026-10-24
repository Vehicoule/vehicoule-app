import 'package:material_ui/material_ui.dart';

import '../../bridge/error.dart';
import '../../l10n/app_localizations.dart';
import '../symbols.dart';
import 'controls.dart';
import 'empty_state.dart';
import 'loading.dart';

/// A list's four states in one place (spec UI §2.8): loading, [empty], an error (one
/// sentence and "Retry") and offline. A sliver; [builder] gets the loaded items.
class VAsyncList<T> extends StatefulWidget {
  const VAsyncList({
    super.key,
    required this.load,
    required this.builder,
    required this.empty,
    required this.errorText,
  });

  final Future<List<T>> Function() load;
  final Widget Function(BuildContext context, List<T> items) builder;
  final Widget empty;

  /// The sentence for an error (usually `errorMessage(l, e)`).
  final String Function(Object error) errorText;

  @override
  State<VAsyncList<T>> createState() => _VAsyncListState<T>();
}

class _VAsyncListState<T> extends State<VAsyncList<T>> {
  late Future<List<T>> _items = widget.load();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    Widget fill(Widget child) =>
        SliverFillRemaining(hasScrollBody: false, child: Center(child: child));
    return FutureBuilder<List<T>>(
      future: _items,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) {
          return fill(const VLoading());
        }
        final e = s.error;
        if (e is CoreError_Offline) {
          return fill(
            VEmptyState(icon: VIcons.cloudOff, message: l.errorOffline),
          );
        }
        if (e != null) {
          return fill(
            VEmptyState(
              icon: VIcons.error,
              message: widget.errorText(e),
              action: VButton(
                label: l.actionRetry,
                style: VButtonStyle.tonal,
                onPressed: () => setState(() {
                  _items = widget.load();
                }),
              ),
            ),
          );
        }
        final items = s.data!;
        return items.isEmpty
            ? fill(widget.empty)
            : widget.builder(context, items);
      },
    );
  }
}
