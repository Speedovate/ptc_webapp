import 'dart:async';
import 'dart:math';
import 'sync_error_environment.dart';

/// Demand-driven lookup limiting: no subscriptions or periodic timers.
/// A timed-out Firestore read keeps its slot until the SDK actually completes,
/// so repeated queue flushes cannot accumulate abandoned reads.
class BookingResolutionGate {
  BookingResolutionGate({
    DateTime Function()? now,
    this.timeout = const Duration(seconds: 30),
  }) : _now = now ?? DateTime.now;

  static const maxStates = 256;
  static const maxConcurrent = 4;
  static const maxStartsPerMinute = 16;
  final DateTime Function() _now;
  final Duration timeout;
  final _states = <String, _LookupState>{};
  int _active = 0;
  int _starts = 0;
  DateTime? _window;

  int get trackedCount => _states.length;
  int get activeCount => _active;

  /// Clear backoff only after confirmed creation or an explicit user retry.
  /// Never release ownership of an unfinished read.
  void invalidate(String id) {
    _states.removeWhere((key, state) => state.id == id && state.active == null);
  }

  Future<String?> resolve(
    String id,
    String identity,
    Future<String?> Function() lookup, {
    Map<String, dynamic>? evidence,
  }) {
    final existing = _states[identity];
    void explain(String reason, {DateTime? retryAt}) {
      evidence?.addAll({
        'gate_reason': reason,
        'gate_retry_at': (retryAt ?? existing?.retryAt)
            ?.toUtc()
            .toIso8601String(),
        'gate_active_requests': _active,
        'gate_last_lookup_error': existing?.lastError,
        'gate_last_lookup_finished_at': existing?.finishedAt
            ?.toUtc()
            .toIso8601String(),
      });
    }

    if (existing?.active != null) {
      explain('shared_in_flight');
      return existing!.active!;
    }
    final now = _now();
    if (existing?.retryAt != null && now.isBefore(existing!.retryAt!)) {
      explain('backoff');
      return Future.value(null);
    }
    if (_window == null ||
        now.difference(_window!) >= const Duration(minutes: 1)) {
      _window = now;
      _starts = 0;
    }
    if (_active >= maxConcurrent || _starts >= maxStartsPerMinute) {
      explain(
        _active >= maxConcurrent ? 'concurrency_limit' : 'rate_limit',
        retryAt: _window?.add(const Duration(minutes: 1)),
      );
      return Future.value(null);
    }
    if (existing == null && _states.length >= maxStates) {
      final oldestIdle = _states.keys.firstWhere(
        (key) => _states[key]!.active == null,
      );
      _states.remove(oldestIdle);
    }
    final state = existing ?? _LookupState(id);
    _states.remove(identity);
    _states[identity] = state;
    _active++;
    _starts++;
    final completed = Completer<String?>();
    final stopwatch = Stopwatch()..start();
    evidence?.addAll({'network_at_lookup_start': syncNetworkEnvironment()});
    var timedOut = false;
    state.active = completed.future.timeout(
      timeout,
      onTimeout: () {
        timedOut = true;
        _defer(state);
        explain('request_timeout', retryAt: state.retryAt);
        evidence?.addAll({
          'lookup_elapsed_ms': stopwatch.elapsedMilliseconds,
          'lookup_timeout_ms': timeout.inMilliseconds,
          'network_at_lookup_timeout': syncNetworkEnvironment(),
        });
        return null;
      },
    );
    final result = state.active!;
    unawaited(() async {
      var succeeded = false;
      try {
        final value = await lookup();
        state.lastError = null;
        if (!timedOut) {
          if (value == null) {
            _defer(state);
          } else {
            succeeded = true;
          }
        }
        completed.complete(value);
      } catch (error, stack) {
        state.lastError = error.toString();
        if (!timedOut) _defer(state);
        completed.completeError(error, stack);
      } finally {
        stopwatch.stop();
        state.finishedAt = _now();
        state.active = null;
        _active--;
        if (succeeded) _states.remove(identity);
      }
    }());
    return result;
  }

  void _defer(_LookupState state) {
    state.failures = min(state.failures + 1, 6);
    // 30s, 60s, 120s, 240s, 480s, then at most once per 15 minutes.
    final seconds = min(30 * (1 << (state.failures - 1)), 900);
    state.retryAt = _now().add(Duration(seconds: seconds));
  }
}

class _LookupState {
  _LookupState(this.id);
  final String id;
  int failures = 0;
  DateTime? retryAt;
  Future<String?>? active;
  String? lastError;
  DateTime? finishedAt;
}
