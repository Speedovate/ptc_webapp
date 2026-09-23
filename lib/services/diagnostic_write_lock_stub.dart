Future<void> _tail = Future<void>.value();

Future<void> withDiagnosticWriteLock(Future<void> Function() action) {
  final task = _tail.then((_) => action());
  _tail = task.then<void>((_) {}, onError: (Object _) {});
  return task;
}
