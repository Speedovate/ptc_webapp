import 'package:flutter/material.dart';

/// Explicit marker for widgets that produce a sliver, rather than a box.
abstract interface class SliverContent {}

Widget _asSliver(Widget child) =>
    child is SliverContent ? child : SliverToBoxAdapter(child: child);

/// A single viewport for toolbars, empty states and lazy data sections.
class LazyDataScrollView extends StatelessWidget {
  const LazyDataScrollView({
    super.key,
    required this.child,
    this.padding,
    this.controller,
    this.physics,
  });
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final ScrollController? controller;
  final ScrollPhysics? physics;
  @override
  Widget build(BuildContext context) => CustomScrollView(
    controller: controller,
    physics: physics,
    slivers: [
      SliverPadding(
        padding: padding ?? EdgeInsets.zero,
        sliver: _asSliver(child),
      ),
    ],
  );
}

class SliverSection extends StatelessWidget implements SliverContent {
  const SliverSection({
    super.key,
    required this.children,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });
  final List<Widget> children;
  final CrossAxisAlignment crossAxisAlignment;
  @override
  Widget build(BuildContext context) => SliverMainAxisGroup(
    slivers: children.map(_asSliver).toList(growable: false),
  );
}

class LazySliverList<T> extends StatelessWidget implements SliverContent {
  LazySliverList({
    super.key,
    required Iterable<T> items,
    required this.itemBuilder,
  }) : items = items.toList(growable: false);
  final List<T> items;
  final Widget Function(BuildContext, T) itemBuilder;
  @override
  Widget build(BuildContext context) => SliverList.builder(
    itemCount: items.length,
    itemBuilder: (context, index) => itemBuilder(context, items[index]),
  );
}

/// Cache width-dependent table construction across scroll-offset changes.
/// Data, theme, text scale and width changes invalidate the cached section.
class SliverWidthBuilder extends StatefulWidget implements SliverContent {
  const SliverWidthBuilder({super.key, required this.builder});
  final Widget Function(BuildContext, BoxConstraints) builder;
  @override
  State<SliverWidthBuilder> createState() => _SliverWidthBuilderState();
}

class _SliverWidthBuilderState extends State<SliverWidthBuilder> {
  Widget? _section;
  double? _width;
  @override
  void didUpdateWidget(covariant SliverWidthBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    _section = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _section = null;
  }

  @override
  Widget build(BuildContext context) {
    // Register inherited sizing dependencies outside the layout callback.
    MediaQuery.textScalerOf(context);
    DefaultTextStyle.of(context);
    Directionality.of(context);
    Theme.of(context);
    Localizations.maybeLocaleOf(context);
    return SliverLayoutBuilder(
      builder: (_, constraints) {
        final width = constraints.crossAxisExtent;
        if (_section == null || width != _width) {
          _width = width;
          _section = _asSliver(
            widget.builder(
              context,
              BoxConstraints(minWidth: width, maxWidth: width),
            ),
          );
        }
        return _section!;
      },
    );
  }
}

class SliverListenableBuilder extends StatelessWidget implements SliverContent {
  const SliverListenableBuilder({
    super.key,
    required this.listenable,
    required this.builder,
  });
  final Listenable listenable;
  final Widget Function(BuildContext, Widget?) builder;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: listenable,
    builder: (context, child) => _asSliver(builder(context, child)),
  );
}
