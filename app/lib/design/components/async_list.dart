import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../bridge/error.dart';
import '../../l10n/app_localizations.dart';
import '../symbols.dart';
import 'controls.dart';
import 'empty_state.dart';
import 'loading.dart';

/// A list's four states in one place (spec UI §2.8): loading, [empty], an error (one
/// sentence and "Retry") and offline. A sliver, in three forms:
///
/// - a future ([VAsyncList.new]): [builder] gets the loaded items;
/// - a stream ([VAsyncList.stream]): the queue, downloads, live library lists;
/// - pages ([VAsyncList.paged]): long lists, [pageSize] items at a time as the user
///   scrolls near the end (a 10,000-track playlist never loads at once).
///
/// It loads again when [reloadKey] changes, not on every rebuild (screens pass new
/// closures each build). A screen whose query can change (a sort, a filter, another
/// playlist) must pass it in [reloadKey]: a new `load` alone is ignored.
class VAsyncList<T> extends StatefulWidget {
  const VAsyncList({
    super.key,
    required Future<List<T>> Function() this.load,
    required Widget Function(BuildContext context, List<T> items) this.builder,
    required this.empty,
    required this.errorText,
    this.reloadKey,
  }) : watch = null,
       page = null,
       itemBuilder = null,
       pageSize = 0;

  const VAsyncList.stream({
    super.key,
    required Stream<List<T>> Function() this.watch,
    required Widget Function(BuildContext context, List<T> items) this.builder,
    required this.empty,
    required this.errorText,
    this.reloadKey,
  }) : load = null,
       page = null,
       itemBuilder = null,
       pageSize = 0;

  const VAsyncList.paged({
    super.key,
    required Future<List<T>> Function(int offset, int limit) this.page,
    required Widget Function(BuildContext context, T item, int index)
    this.itemBuilder,
    required this.empty,
    required this.errorText,
    this.reloadKey,
    this.pageSize = 100,
  }) : load = null,
       watch = null,
       builder = null;

  final Future<List<T>> Function()? load;
  final Stream<List<T>> Function()? watch;
  final Future<List<T>> Function(int offset, int limit)? page;
  final Widget Function(BuildContext context, List<T> items)? builder;
  final Widget Function(BuildContext context, T item, int index)? itemBuilder;
  final Widget empty;

  /// The sentence for an error (usually `errorMessage(l, e)`).
  final String Function(Object error) errorText;
  final Object? reloadKey;
  final int pageSize;

  @override
  State<VAsyncList<T>> createState() => _VAsyncListState<T>();
}

class _VAsyncListState<T> extends State<VAsyncList<T>> {
  StreamSubscription<List<T>>? _sub;
  List<T>? _items;
  Object? _error;
  bool _loading = false, _done = false;

  /// Bumped on every (re)load: an answer from an older load is dropped.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(VAsyncList<T> old) {
    super.didUpdateWidget(old);
    if (old.reloadKey != widget.reloadKey) setState(_start);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _start() {
    final gen = ++_generation;
    _sub?.cancel();
    _sub = null;
    _items = null;
    _error = null;
    _done = false;
    _loading = false;
    if (widget.watch case final watch?) {
      _sub = watch().listen(
        (items) => setState(() {
          _items = items;
          _error = null;
        }),
        onError: (Object e) => setState(() => _error = e),
        // Closed without a word: nothing to show, rather than loading forever.
        onDone: () {
          if (mounted && _items == null && _error == null) {
            setState(() => _items = <T>[]);
          }
        },
      );
    } else if (widget.load case final load?) {
      _await(gen, load(), replace: true);
    } else {
      _nextPage();
    }
  }

  void _nextPage() {
    if (_loading || _done) return;
    final offset = _items?.length ?? 0;
    _await(_generation, widget.page!(offset, widget.pageSize), replace: false);
  }

  void _await(int gen, Future<List<T>> answer, {required bool replace}) {
    _loading = true;
    answer.then(
      (items) {
        if (!mounted || gen != _generation) return;
        setState(() {
          _loading = false;
          _error = null;
          if (replace) {
            _items = items;
          } else {
            _items = [...?_items, ...items];
            _done = items.length < widget.pageSize;
          }
        });
      },
      onError: (Object e) {
        if (!mounted || gen != _generation) return;
        setState(() {
          _loading = false;
          _error = e;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    Widget fill(Widget child) =>
        SliverFillRemaining(hasScrollBody: false, child: Center(child: child));
    final items = _items;
    final e = _error;
    if (e != null && (items == null || items.isEmpty)) {
      if (e is CoreError_Offline) {
        return fill(
          VEmptyState(icon: VIcons.cloudOff, message: l.errorOffline),
        );
      }
      return fill(
        VEmptyState(
          icon: VIcons.error,
          message: widget.errorText(e),
          action: VButton(
            label: l.actionRetry,
            style: VButtonStyle.tonal,
            onPressed: () => setState(_start),
          ),
        ),
      );
    }
    if (items == null) return fill(const VLoading());
    if (items.isEmpty) return fill(widget.empty);
    if (widget.page == null) return widget.builder!(context, items);

    // Paged: ask for the next page as the end comes near; the last row is a loading
    // indicator (or "Retry" after a failed page) until the list is complete.
    final more = !_done;
    return SliverList.builder(
      itemCount: items.length + (more ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= items.length - widget.pageSize ~/ 4 && more && e == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _nextPage();
          });
        }
        if (i < items.length) return widget.itemBuilder!(context, items[i], i);
        return Center(
          child: e == null
              ? const VLoading()
              : VButton(
                  label: l.actionRetry,
                  style: VButtonStyle.text,
                  onPressed: () => setState(() {
                    _error = null;
                    _nextPage();
                  }),
                ),
        );
      },
    );
  }
}
