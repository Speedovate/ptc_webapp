import 'diagnostic_write_lock_stub.dart'
    if (dart.library.html) 'diagnostic_write_lock_web.dart'
    as impl;

/// Serialize index mutations across outbox instances and, on web, origin tabs.
Future<void> withDiagnosticWriteLock(Future<void> Function() action) =>
    impl.withDiagnosticWriteLock(action);
