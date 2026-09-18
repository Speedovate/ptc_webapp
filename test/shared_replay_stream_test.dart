import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/utils/shared_replay_stream.dart';

Future<void> flush() => Future<void>.delayed(Duration.zero);
void main() {
  test(
    'many pages share processing, late pages replay and last cancel releases source',
    () async {
      var listens = 0, cancels = 0, processing = 0;
      final source = StreamController<int>.broadcast(
        onListen: () => listens++,
        onCancel: () => cancels++,
      );
      final shared = SharedReplayStream(
        () => source.stream.map((n) {
          processing++;
          return n;
        }),
      );
      final a = <int>[], b = <int>[], c = <int>[];
      final sa = shared.stream.listen(a.add);
      final sb = shared.stream.listen(b.add);
      source.add(1);
      await flush();
      final sc = shared.stream.listen(c.add);
      await flush();
      expect(listens, 1);
      expect(processing, 1);
      expect(a, [1]);
      expect(b, [1]);
      expect(c, [1]);
      await sa.cancel();
      source.add(2);
      await flush();
      expect(b, [1, 2]);
      expect(c, [1, 2]);
      expect(processing, 2);
      await sb.cancel();
      expect(cancels, 0);
      await sc.cancel();
      expect(cancels, 1);
      final fresh = <int>[];
      final sd = shared.stream.listen(fresh.add);
      await flush();
      expect(fresh, isEmpty);
      source.add(3);
      await flush();
      expect(fresh, [3]);
      expect(listens, 2);
      await sd.cancel();
      await source.close();
    },
  );
  test('errors propagate to every page without losing later data', () async {
    final source = StreamController<int>();
    final shared = SharedReplayStream(() => source.stream);
    final errors = <Object>[], values = <int>[];
    final a = shared.stream.listen(values.add, onError: errors.add);
    final b = shared.stream.listen(values.add, onError: errors.add);
    source.addError(StateError('retryable'));
    source.add(7);
    await flush();
    expect(errors.length, 2);
    expect(values, [7, 7]);
    await a.cancel();
    await b.cancel();
    await source.close();
  });
  test(
    'a completed source can restart without replaying an old session',
    () async {
      var sessions = 0;
      final shared = SharedReplayStream(() => Stream.value(++sessions));
      expect(await shared.stream.toList(), [1]);
      expect(await shared.stream.toList(), [2]);
    },
  );
  test(
    'source factory errors are delivered and do not wedge later sessions',
    () async {
      var attempts = 0;
      final shared = SharedReplayStream<int>(() {
        if (++attempts == 1) {
          throw StateError('failed');
        }
        return Stream.value(9);
      });
      await expectLater(shared.stream, emitsError(isA<StateError>()));
      expect(await shared.stream.toList(), [9]);
    },
  );
}
