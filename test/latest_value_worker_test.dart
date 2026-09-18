import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/utils/latest_value_worker.dart';

void main() {
  test(
    'full snapshot bursts keep latest state without concurrent processing',
    () async {
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      final done = Completer<void>();
      final applied = <int>[];
      var active = 0;
      final worker = LatestValueWorker<int>(
        apply: (value) async {
          active++;
          expect(active, 1);
          applied.add(value);
          if (value == 1) {
            firstStarted.complete();
            await releaseFirst.future;
          }
          active--;
          if (value == 4) done.complete();
        },
        onError: (error, _) => fail('$error'),
      );
      worker.add(1);
      await firstStarted.future;
      worker.add(2);
      worker.add(3);
      worker.add(4);
      releaseFirst.complete();
      await done.future;
      expect(applied, [1, 4]);
    },
  );

  test('processing error does not wedge future updates', () async {
    final failed = Completer<void>();
    final recovered = Completer<void>();
    final worker = LatestValueWorker<int>(
      apply: (value) async {
        if (value == 1) throw StateError('cache failure');
        recovered.complete();
      },
      onError: (_, _) => failed.complete(),
    );
    worker.add(1);
    await failed.future;
    worker.add(2);
    await recovered.future;
  });
}
