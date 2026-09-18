import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/booking_resolution_gate.dart';

void main() {
  test('coalesces concurrent lookups and releases completed state', () async {
    final gate = BookingResolutionGate();
    final pending = Completer<String?>();
    var calls = 0;
    Future<String?> lookup() {
      calls++;
      return pending.future;
    }

    final first = gate.resolve('temp', 'identity', lookup);
    final others = List.generate(
      20,
      (_) => gate.resolve('temp', 'identity', lookup),
    );
    expect(calls, 1);
    expect(gate.activeCount, 1);
    pending.complete('84');
    expect(await first, '84');
    expect(await Future.wait(others), everyElement('84'));
    expect(gate.activeCount, 0);
    expect(gate.trackedCount, 0);
  });

  test(
    'missing mappings back off without scheduling their own retries',
    () async {
      var now = DateTime.utc(2026);
      final gate = BookingResolutionGate(now: () => now);
      var calls = 0;
      Future<String?> lookup() async {
        calls++;
        return null;
      }

      for (final seconds in [30, 60, 120, 240, 480, 900, 900]) {
        await gate.resolve('temp', 'identity', lookup);
        final before = calls;
        for (var i = 0; i < 100; i++) {
          await gate.resolve('temp', 'identity', lookup);
        }
        expect(calls, before);
        now = now.add(Duration(seconds: seconds - 1));
        await gate.resolve('temp', 'identity', lookup);
        expect(calls, before);
        now = now.add(const Duration(seconds: 1));
        // Advancing time alone does not start any work.
        expect(calls, before);
      }
      expect(calls, 7);
    },
  );

  test(
    'confirmed create clears backoff; failed lookups are also throttled',
    () async {
      final gate = BookingResolutionGate();
      var calls = 0;
      Future<String?> lookup() async {
        calls++;
        throw StateError('identity conflict');
      }

      await expectLater(
        gate.resolve('temp', 'identity', lookup),
        throwsStateError,
      );
      expect(await gate.resolve('temp', 'identity', lookup), isNull);
      expect(calls, 1);
      gate.invalidate('temp');
      expect(await gate.resolve('temp', 'identity', () async => '84'), '84');
      expect(gate.trackedCount, 0);
    },
  );

  test(
    'timeout and invalidation cannot spawn overlapping abandoned reads',
    () async {
      final gate = BookingResolutionGate(timeout: Duration.zero);
      final pending = Completer<String?>();
      var calls = 0;
      Future<String?> lookup() {
        calls++;
        return pending.future;
      }

      expect(await gate.resolve('temp', 'identity', lookup), isNull);
      for (var i = 0; i < 50; i++) {
        gate.invalidate('temp');
        expect(await gate.resolve('temp', 'identity', lookup), isNull);
      }
      expect(calls, 1);
      expect(gate.activeCount, 1);
      pending.completeError(StateError('late SDK error'));
      await Future<void>.delayed(Duration.zero);
      expect(gate.activeCount, 0);
    },
  );

  test('bounds concurrency and rate even for different IDs', () async {
    var now = DateTime.utc(2026);
    final gate = BookingResolutionGate(now: () => now);
    final pending = List.generate(4, (_) => Completer<String?>());
    final active = List.generate(
      4,
      (i) => gate.resolve('$i', '$i', () => pending[i].future),
    );
    var calls = 0;
    Future<String?> lookup() async {
      calls++;
      return '84';
    }

    expect(await gate.resolve('fifth', 'fifth', lookup), isNull);
    expect(calls, 0);
    for (final p in pending) {
      p.complete('84');
    }
    await Future.wait(active);
    for (var i = 0; i < 100; i++) {
      await gate.resolve('next$i', 'next$i', lookup);
    }
    expect(calls, 12); // Four earlier reads also consume the minute's budget.
    now = now.add(const Duration(minutes: 1));
    expect(await gate.resolve('new', 'new', lookup), '84');
  });

  test('bounded memory for long sessions with many unresolved IDs', () async {
    var now = DateTime.utc(2026);
    final gate = BookingResolutionGate(now: () => now);
    for (var i = 0; i < 600; i++) {
      await gate.resolve('$i', '$i', () async => null);
      now = now.add(const Duration(minutes: 1));
    }
    expect(gate.trackedCount, BookingResolutionGate.maxStates);
    expect(gate.activeCount, 0);
  });
}
