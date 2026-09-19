import 'package:flutter/widgets.dart';

/// Keep the last successful view on transient stream errors. An explicit empty
/// value is still a successful update and must replace earlier records.
class RetainedStreamBuilder<T> extends StatefulWidget {
  const RetainedStreamBuilder({
    super.key,
    required this.stream,
    required this.builder,
    this.initialData,
  });
  final Stream<T>? stream;
  final T? initialData;
  final AsyncWidgetBuilder<T> builder;
  @override
  State<RetainedStreamBuilder<T>> createState() =>
      _RetainedStreamBuilderState<T>();
}

class _RetainedStreamBuilderState<T> extends State<RetainedStreamBuilder<T>> {
  T? _lastData;
  @override
  void initState() {
    super.initState();
    _lastData = widget.initialData;
  }

  @override
  void didUpdateWidget(covariant RetainedStreamBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stream != widget.stream) {
      _lastData = widget.initialData;
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<T>(
    // Drop the old stream's retained snapshot when changing conversations.
    key: ObjectKey(widget.stream),
    stream: widget.stream,
    initialData: widget.initialData,
    builder: (context, snapshot) {
      if (snapshot.hasData && !snapshot.hasError) {
        _lastData = snapshot.data;
      }
      final retained = _lastData;
      return widget.builder(
        context,
        snapshot.hasError && retained != null
            ? AsyncSnapshot<T>.withData(snapshot.connectionState, retained)
            : snapshot,
      );
    },
  );
}
