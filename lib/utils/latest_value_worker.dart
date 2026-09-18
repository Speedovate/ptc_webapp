import 'dart:async';

/// Serializes full-state updates, retaining only the newest waiting snapshot.
/// Do not use for incremental changes or user mutations.
class LatestValueWorker<T extends Object> {
  LatestValueWorker({required this.apply, required this.onError});

  final Future<void> Function(T value) apply;
  final void Function(Object error, StackTrace stack) onError;
  T? _pending;
  bool _running = false;

  void add(T value) {
    _pending = value;
    if (_running) return;
    _running = true;
    unawaited(_drain());
  }

  Future<void> _drain() async {
    try {
      while (_pending != null) {
        // Yield between snapshots so browser input/frames can run after resume.
        await Future<void>.delayed(Duration.zero);
        final value = _pending!;
        _pending = null;
        try {
          await apply(value);
        } catch (error, stack) {
          onError(error, stack);
        }
      }
    } finally {
      _running = false;
    }
  }
}
