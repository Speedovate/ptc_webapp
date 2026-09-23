import 'diagnostic_write_lock_stub.dart'
    if (dart.library.html) 'diagnostic_write_lock_web.dart'
    as impl;

/// Serialize index mutations across outbox instances and, on web, origin tabs.
Future<void> withDiagnosticWriteLock(
  Future<void> Function() action, {
  String name = 'paltranco_sync_diagnostic_outbox_v2',
}) => impl.withDiagnosticWriteLock(action, name: name);
