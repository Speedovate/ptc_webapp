import 'dart:async';

/// Gives the existing listener a chance to recover before one fallback read.
/// Ownership lasts until the underlying read ends, even if a caller times out.
class ForegroundRefreshGate {
  ForegroundRefreshGate({this.gracePeriod = const Duration(seconds: 2)});

  final Duration gracePeriod;
  int _revision = 0;
  DateTime? _lastConfirmation;
  Future<void>? _active;

  void confirmedSnapshot() {
    _revision++;
    _lastConfirmation = DateTime.now();
  }

  Future<void> recover({
    required bool Function() canRefresh,
    required Future<void> Function() refresh,
  }) {
    return _active ??= _recover(canRefresh, refresh).whenComplete(() {
      _active = null;
    });
  }

  Future<void> _recover(
    bool Function() canRefresh,
    Future<void> Function() refresh,
  ) async {
    if (!canRefresh()) {
      return;
    }
    final revision = _revision;
    final recent = _lastConfirmation;
    if (recent != null && DateTime.now().difference(recent) < gracePeriod) {
      return;
    }
    await Future<void>.delayed(gracePeriod);
    if (!canRefresh() || revision != _revision) {
      return;
    }
    await refresh();
  }
}
