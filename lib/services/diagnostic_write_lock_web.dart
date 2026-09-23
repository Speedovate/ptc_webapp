import 'dart:js_interop';

@JS('navigator.locks')
external _LockManager? get _locks;

extension type _LockManager(JSObject _) implements JSObject {
  external JSPromise<JSAny?> request(JSString name, JSFunction callback);
}

Future<void> withDiagnosticWriteLock(Future<void> Function() action) async {
  final locks = _locks;
  if (locks == null) {
    // Never silently use an isolate-only lock for shared browser storage.
    throw StateError('Diagnostic persistence requires browser Web Locks.');
  }
  await locks
      .request(
        'paltranco_sync_diagnostic_outbox_v2'.toJS,
        ((JSAny? lock) => action().then<JSAny?>((_) => null).toJS).toJS,
      )
      .toDart;
}
