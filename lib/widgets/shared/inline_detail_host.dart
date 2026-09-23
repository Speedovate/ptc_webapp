import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webapp/widgets/shared/retained_section_stack.dart';

/// Opens related records inside the shell while retaining the source list.
class InlineDetailHost extends StatefulWidget {
  const InlineDetailHost({super.key, required this.child});
  final Widget child;

  static Future<void> open(BuildContext context, WidgetBuilder builder) {
    final host = context.findAncestorStateOfType<_InlineDetailHostState>();
    return host?._open(builder) ?? Future<void>.value();
  }

  static void close(BuildContext context) {
    context.findAncestorStateOfType<_InlineDetailHostState>()?._close();
  }

  @override
  State<InlineDetailHost> createState() => _InlineDetailHostState();
}

class _InlineDetailHostState extends State<InlineDetailHost> {
  final _details = <({Widget child, Completer<void> done})>[];

  Future<void> _open(WidgetBuilder builder) {
    final done = Completer<void>();
    setState(() {
      _details.add((
        child: Builder(key: UniqueKey(), builder: builder),
        done: done,
      ));
    });
    return done.future;
  }

  void _close() {
    if (_details.isEmpty) {
      return;
    }
    final entry = _details.last;
    setState(() => _details.removeLast());
    entry.done.complete();
  }

  @override
  void dispose() {
    for (final entry in _details) {
      entry.done.complete();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RetainedSectionStack(
    index: _details.length,
    children: [widget.child, for (final entry in _details) entry.child],
  );
}
