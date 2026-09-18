import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:webapp/widgets/shared/lazy_data_scroll_view.dart';

/// Observes only this viewport's user scrolling, including wheel input when a
/// short first batch does not yet fill a tall browser window.
class PagedScrollObserver extends StatefulWidget {
  const PagedScrollObserver({super.key, required this.child});
  final Widget child;
  @override
  State<PagedScrollObserver> createState() => _PagedScrollObserverState();
}

class _PagedScrollObserverState extends State<PagedScrollObserver> {
  final _wheel = ValueNotifier<int>(0);
  @override
  void dispose() {
    _wheel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _PagingWheelScope(
    signal: _wheel,
    child: Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent &&
            event.scrollDelta.dy > 0 &&
            event.scrollDelta.dy.abs() >= event.scrollDelta.dx.abs()) {
          _wheel.value++;
        }
      },
      child: ScrollNotificationObserver(child: widget.child),
    ),
  );
}

class _PagingWheelScope extends InheritedWidget {
  const _PagingWheelScope({required this.signal, required super.child});
  final ValueNotifier<int> signal;
  @override
  bool updateShouldNotify(_PagingWheelScope oldWidget) =>
      signal != oldWidget.signal;
}

/// Bounds list-wide presentation work without truncating the repository cache.
/// Filtering and exports must use the full dataset before passing items here.
class PagedDataSliver<T> extends StatefulWidget implements SliverContent {
  const PagedDataSliver({
    super.key,
    required this.items,
    required this.builder,
    required this.resetKey,
    this.pageSize = 15,
    this.storageId,
  }) : assert(pageSize > 0);

  final List<T> items;
  final Widget Function(BuildContext, List<T>) builder;
  final Object? resetKey;
  final int pageSize;
  final String? storageId;

  @override
  State<PagedDataSliver<T>> createState() => _PagedDataSliverState<T>();
}

class _PagedDataSliverState<T> extends State<PagedDataSliver<T>> {
  late int _visibleCount = widget.pageSize;
  bool _restored = false;
  ScrollNotificationObserverState? _observer;
  ValueNotifier<int>? _wheel;
  bool _loadedForGesture = false;
  bool _userScrolling = false;
  bool _scheduled = false;
  int _generation = 0;

  void _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return;
    }
    if (notification is UserScrollNotification) {
      _userScrolling = notification.direction != ScrollDirection.idle;
      return;
    }
    if (notification is ScrollEndNotification) {
      _userScrolling = false;
      return;
    }
    if (notification is ScrollStartNotification) {
      _loadedForGesture = false;
      return;
    }
    final delta = switch (notification) {
      ScrollUpdateNotification() => notification.scrollDelta ?? 0,
      OverscrollNotification() => notification.overscroll,
      _ => 0.0,
    };
    if (!_userScrolling ||
        delta <= 0 ||
        notification.metrics.extentAfter > 120 ||
        _loadedForGesture ||
        _scheduled ||
        _visibleCount >= widget.items.length) {
      return;
    }
    _requestNextPage();
  }

  void _onWheel() {
    final position = Scrollable.maybeOf(context)?.position;
    if (position == null ||
        !position.hasContentDimensions ||
        position.extentAfter > 0) {
      return;
    }
    // A wheel event is an explicit user request even when no scroll extent exists.
    _loadedForGesture = false;
    _requestNextPage();
  }

  void _requestNextPage() {
    if (_loadedForGesture ||
        _scheduled ||
        _visibleCount >= widget.items.length) {
      return;
    }
    _loadedForGesture = true;
    _scheduled = true;
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _visibleCount = math.min(
          _visibleCount + widget.pageSize,
          widget.items.length,
        );
        _remember();
      });
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    _observer?.removeListener(_onScroll);
    _wheel?.removeListener(_onWheel);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final wheel = context
        .dependOnInheritedWidgetOfExactType<_PagingWheelScope>()
        ?.signal;
    if (!identical(wheel, _wheel)) {
      _wheel?.removeListener(_onWheel);
      _wheel = wheel;
      _wheel?.addListener(_onWheel);
    }
    final observer = ScrollNotificationObserver.maybeOf(context);
    if (!identical(observer, _observer)) {
      _observer?.removeListener(_onScroll);
      _observer = observer;
      _observer?.addListener(_onScroll);
    }
    if (!_restored && widget.storageId != null) {
      final saved = PageStorage.maybeOf(
        context,
      )?.readState(context, identifier: widget.storageId);
      if (saved is _PageWindow &&
          saved.resetKey == widget.resetKey &&
          saved.pageSize == widget.pageSize) {
        _visibleCount = saved.count;
      }
    }
    _restored = true;
  }

  void _remember() {
    if (widget.storageId != null) {
      PageStorage.maybeOf(context)?.writeState(
        context,
        _PageWindow(widget.resetKey, _visibleCount, widget.pageSize),
        identifier: widget.storageId,
      );
    }
  }

  @override
  void didUpdateWidget(covariant PagedDataSliver<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resetKey != oldWidget.resetKey ||
        widget.pageSize != oldWidget.pageSize) {
      _generation++;
      _loadedForGesture = false;
      _visibleCount = widget.pageSize;
      _remember();
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = math.min(_visibleCount, widget.items.length);
    return SliverMainAxisGroup(
      slivers: [
        widget.builder(context, widget.items.sublist(0, count)),
        if (count < widget.items.length)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Text('Showing $count of ${widget.items.length}'),
                  const SizedBox(height: 8),
                  const Text('Pull up to load more'),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _PageWindow {
  const _PageWindow(this.resetKey, this.count, this.pageSize);
  final Object? resetKey;
  final int count;
  final int pageSize;
}
