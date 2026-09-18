import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/foreground_refresh_gate.dart';

void main() {
  test(
    'listener confirmation during resume avoids fallback collection read',
    () async {
      final gate = ForegroundRefreshGate(
        gracePeriod: const Duration(milliseconds: 20),
      );
      var reads = 0;
      final recovery = gate.recover(
        canRefresh: () => true,
        refresh: () async {
          reads++;
        },
      );
      gate.confirmedSnapshot();
      await recovery;
      expect(reads, 0);
    },
  );

  test(
    'recent confirmation skips fallback without waiting for another event',
    () async {
      final gate = ForegroundRefreshGate();
      gate.confirmedSnapshot();
      await gate.recover(
        canRefresh: () => true,
        refresh: () async {
          fail('unexpected full read');
        },
      );
    },
  );

  test(
    'silent listener triggers one fallback shared by repeated resumes',
    () async {
      final gate = ForegroundRefreshGate(
        gracePeriod: const Duration(milliseconds: 10),
      );
      final pending = Completer<void>();
      var reads = 0;
      Future<void> refresh() {
        reads++;
        return pending.future;
      }

      final first = gate.recover(canRefresh: () => true, refresh: refresh);
      final second = gate.recover(canRefresh: () => true, refresh: refresh);
      expect(identical(first, second), isTrue);
      await expectLater(
        first.timeout(const Duration(milliseconds: 30)),
        throwsA(isA<TimeoutException>()),
      );
      final third = gate.recover(canRefresh: () => true, refresh: refresh);
      expect(identical(first, third), isTrue);
      expect(reads, 1);
      pending.complete();
      await third;
    },
  );

  test(
    'hiding browser or going offline during grace cancels fallback',
    () async {
      final gate = ForegroundRefreshGate(
        gracePeriod: const Duration(milliseconds: 10),
      );
      var onlineAndVisible = true;
      final future = gate.recover(
        canRefresh: () => onlineAndVisible,
        refresh: () async {
          fail('unexpected read');
        },
      );
      onlineAndVisible = false;
      await future;
    },
  );

  test(
    'failure releases ownership for next explicitly requested recovery',
    () async {
      final gate = ForegroundRefreshGate(gracePeriod: Duration.zero);
      await expectLater(
        gate.recover(
          canRefresh: () => true,
          refresh: () async {
            throw StateError('offline');
          },
        ),
        throwsStateError,
      );
      var reads = 0;
      await gate.recover(
        canRefresh: () => true,
        refresh: () async {
          reads++;
        },
      );
      expect(reads, 1);
    },
  );
}
