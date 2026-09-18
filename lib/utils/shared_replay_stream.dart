import 'dart:async';

/// Shares one source subscription while observed, replaying its latest value to
/// additional observers. The source and replay value are released at zero
/// observers, so a new session cannot receive stale data from the previous one.
class SharedReplayStream<T> {
  SharedReplayStream(this._source);

  final Stream<T> Function() _source;
  _ReplaySession<T>? _session;

  late final Stream<T> stream = Stream<T>.multi((output) {
    final session = _session ??= _ReplaySession<T>();
    session.observers++;
    final subscription = session.events.stream.listen(
      output.add,
      onError: output.addError,
      onDone: output.close,
    );
    if (session.hasValue) {
      output.add(session.value as T);
    }
    output.onCancel = () async {
      await subscription.cancel();
      session.observers--;
      if (session.observers == 0) {
        session.active = false;
        if (identical(_session, session)) {
          _session = null;
        }
        await session.source?.cancel();
        await session.events.close();
        session.value = null;
      }
    };
    if (!session.started) {
      session.started = true;
      try {
        session.source = _source().listen(
          (value) {
            if (!session.active) {
              return;
            }
            session.value = value;
            session.hasValue = true;
            session.events.add(value);
          },
          onError: (Object error, StackTrace stack) {
            if (session.active) {
              session.events.addError(error, stack);
            }
          },
          onDone: () {
            session.active = false;
            if (identical(_session, session)) {
              _session = null;
            }
            unawaited(session.events.close());
          },
        );
      } catch (error, stack) {
        session.events.addError(error, stack);
        session.active = false;
        if (identical(_session, session)) {
          _session = null;
        }
        unawaited(session.events.close());
      }
    }
  });
}

class _ReplaySession<T> {
  final events = StreamController<T>.broadcast(sync: true);
  StreamSubscription<T>? source;
  T? value;
  bool hasValue = false;
  bool started = false;
  bool active = true;
  int observers = 0;
}
