import 'package:flutter/material.dart';

/// A polished, reusable list widget that adds two pieces of UI polish that
/// were requested on top of the plain [ListView.builder] lists used across
/// the app (farmers list, drafts, pending sync, etc.):
///
///  1. "Infinite scroll" - rather than rendering every already-fetched item
///     at once, items are revealed in small batches as the inspector nears
///     the bottom of the list. This keeps first paint fast and gives a
///     smooth progressive-loading feel, with zero backend changes required
///     (the backend does not currently support pagination on GET /farmers,
///     so this batches the *reveal* of an already fully-fetched list).
///  2. "Snap-to-item" - once the user lifts their finger, the list settles
///     on the nearest item boundary instead of stopping at an arbitrary
///     half-scrolled offset, similar to a card carousel. This relies on
///     every item having the same fixed [itemExtent].
///
/// Each item also gets a subtle fade + slide-in entrance animation the
/// first time it is revealed, which is what gives the list its "pretty"
/// feel without needing any extra packages.
class SnappingListView<T> extends StatefulWidget {
  const SnappingListView({
    super.key,
    required this.items,
    required this.itemBuilder,
    required this.itemExtent,
    this.initialBatchSize = 10,
    this.batchSize = 8,
    this.padding,
    this.onRefresh,
    this.keyOf,
  });

  final List<T> items;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;

  /// Fixed height of every row. Required for reliable item-boundary
  /// snapping - keep card content within this height.
  final double itemExtent;

  /// How many items are revealed immediately on first build.
  final int initialBatchSize;

  /// How many additional items are revealed each time the user scrolls
  /// near the bottom of the currently revealed set.
  final int batchSize;

  final EdgeInsetsGeometry? padding;

  /// Pull-to-refresh callback. When provided, the list is wrapped in a
  /// [RefreshIndicator].
  final Future<void> Function()? onRefresh;

  /// Optional stable key extractor (e.g. `(f) => f.id`) used so the
  /// entrance animation only plays once per item, even if [items] is
  /// rebuilt with a new list instance (e.g. after a search filter).
  final Object Function(T item)? keyOf;

  @override
  State<SnappingListView<T>> createState() => _SnappingListViewState<T>();
}

class _SnappingListViewState<T> extends State<SnappingListView<T>> {
  final ScrollController _controller = ScrollController();
  final Set<Object> _animatedKeys = {};
  late int _visibleCount;
  bool _snapping = false;

  @override
  void initState() {
    super.initState();
    _visibleCount = widget.initialBatchSize.clamp(0, widget.items.length);
  }

  @override
  void didUpdateWidget(covariant SnappingListView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items.length != oldWidget.items.length) {
      // Underlying data set changed (new search filter, refresh, etc.) -
      // reset how much is revealed so short filtered results show in full
      // and long lists still reveal progressively.
      _visibleCount = widget.initialBatchSize.clamp(0, widget.items.length);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _maybeRevealMore(ScrollMetrics metrics) {
    if (_visibleCount >= widget.items.length) return;
    final threshold = widget.itemExtent * 3;
    if (metrics.pixels >= metrics.maxScrollExtent - threshold) {
      setState(() {
        _visibleCount = (_visibleCount + widget.batchSize).clamp(
          0,
          widget.items.length,
        );
      });
    }
  }

  void _snapToNearestItem(ScrollMetrics metrics) {
    if (_snapping || !_controller.hasClients) return;
    final extent = widget.itemExtent;
    if (extent <= 0) return;

    final current = metrics.pixels;
    final nearestIndex = (current / extent).round();
    final target = (nearestIndex * extent).clamp(0.0, metrics.maxScrollExtent);

    if ((target - current).abs() < 1.0) return;

    _snapping = true;
    _controller
        .animateTo(
          target,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() => _snapping = false);
  }

  @override
  Widget build(BuildContext context) {
    final shownCount = _visibleCount.clamp(0, widget.items.length);
    final hasMore = shownCount < widget.items.length;

    Widget list = NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification) {
          _snapToNearestItem(notification.metrics);
        } else if (notification is ScrollUpdateNotification) {
          _maybeRevealMore(notification.metrics);
        }
        return false;
      },
      child: ListView.builder(
        controller: _controller,
        padding: widget.padding,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: shownCount + (hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= shownCount) {
            return SizedBox(
              height: widget.itemExtent,
              child: const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            );
          }

          final item = widget.items[index];
          final itemKey = widget.keyOf?.call(item) ?? index;
          final alreadyAnimated = _animatedKeys.contains(itemKey);
          _animatedKeys.add(itemKey);

          final child = SizedBox(
            height: widget.itemExtent,
            child: widget.itemBuilder(context, item, index),
          );

          if (alreadyAnimated) return child;

          return TweenAnimationBuilder<double>(
            key: ValueKey(itemKey),
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: 240 + (index % 8) * 35),
            curve: Curves.easeOutCubic,
            builder: (context, value, animChild) => Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, (1 - value) * 18),
                child: animChild,
              ),
            ),
            child: child,
          );
        },
      ),
    );

    if (widget.onRefresh != null) {
      list = RefreshIndicator(onRefresh: widget.onRefresh!, child: list);
    }

    return list;
  }
}
