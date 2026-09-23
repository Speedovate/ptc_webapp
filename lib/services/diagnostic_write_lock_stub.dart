final _tails = <String, Future<void>>{};
Future<void> withDiagnosticWriteLock(
  Future<void> Function() action, {
  String name = 'paltranco_sync_diagnostic_outbox_v2',
}) {
  final task = (_tails[name] ?? Future<void>.value()).then((_) => action());
  _tails[name] = task.then<void>((_) {}, onError: (Object _) {});
  return task;
}
