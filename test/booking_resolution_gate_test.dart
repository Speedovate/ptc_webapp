import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/booking_resolution_gate.dart';

void main() {
  test('default lookup waits two minutes for weak connections', () {
    expect(BookingResolutionGate().timeout, const Duration(minutes: 2));
  });

  test(
    'response after former 30s deadline completes without a timeout',
    () async {
      final gate = BookingResolutionGate();
      final evidence = <String, dynamic>{};
      var calls = 0;
      final lookup = gate.resolve('temp', 'slow-but-successful', () async {
        calls++;
        await Future<void>.delayed(const Duration(seconds: 35));
        return '700';
      }, evidence: evidence);
      final shared = gate.resolve('temp', 'slow-but-successful', () async {
        calls++;
        return 'unexpected';
      });
      expect(await lookup, '700');
      expect(await shared, '700');
      expect(calls, 1);
      expect(evidence['gate_reason'], isNull);
      expect(gate.activeCount, 0);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
  test(
    'timeout records network at request start and deadline without releasing read',
    () async {
      final gate = BookingResolutionGate(
        timeout: const Duration(milliseconds: 10),
      );
      final pending = Completer<String?>();
      final evidence = <String, dynamic>{'stage': 'reservation_read'};
      expect(
        await gate.resolve(
          'temp',
          'network-proof',
          () => pending.future,
          evidence: evidence,
        ),
        isNull,
      );
      expect(evidence['stage'], 'reservation_read');
      expect(evidence['gate_reason'], 'request_timeout');
      expect(evidence['network_at_lookup_start'], isA<Map>());
      expect(evidence['network_at_lookup_timeout'], isA<Map>());
      expect(evidence['lookup_elapsed_ms'], greaterThanOrEqualTo(10));
      expect(evidence['lookup_timeout_ms'], 10);
      expect(gate.activeCount, 1);
      pending.complete(null);
      await Future<void>.delayed(Duration.zero);
      expect(gate.activeCount, 0);
    },
  );
  test(
    'deferred lookup explains backoff and preserves last SDK failure evidence',
    () async {
      final now = DateTime.utc(2026, 10, 21, 5, 27);
      final gate = BookingResolutionGate(now: () => now);
      var calls = 0;
      Future<String?> lookup() async {
        calls++;
        throw StateError('[cloud_firestore/unavailable] Connection failed.');
      }

      await expectLater(
        gate.resolve('temp', 'identity', lookup),
        throwsStateError,
      );
      final evidence = <String, dynamic>{};
      expect(
        await gate.resolve('temp', 'identity', lookup, evidence: evidence),
        isNull,
      );
      expect(calls, 1);
      expect(evidence['gate_reason'], 'backoff');
      expect(
        evidence['gate_retry_at'],
        now.add(const Duration(seconds: 30)).toIso8601String(),
      );
      expect(
        evidence['gate_last_lookup_error'],
        contains('cloud_firestore/unavailable'),
      );
      expect(evidence['gate_last_lookup_finished_at'], now.toIso8601String());
      expect(
        evidence['stage'],
        isNull,
        reason: 'Deferred lookup is not fresh server absence proof',
      );
    },
  );

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
