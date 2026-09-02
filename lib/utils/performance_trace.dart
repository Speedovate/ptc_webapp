import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Temporary, structured performance diagnostics for browser and terminal logs.
/// Remove this file and its call sites after the lag investigation is complete.
class PerformanceTrace {
  PerformanceTrace._();

  // Diagnostics are retained for future investigations but disabled for releases.
  static const bool enabled = false;
  static final Stopwatch _session = Stopwatch()..start();
  static final Map<String, int> _buildCounts = <String, int>{};
  static final Map<String, DateTime> _lastBuildLogAt = <String, DateTime>{};
  static bool _frameTracingInstalled = false;
  static int _slowFrameCount = 0;
  static int _slowestFrameMs = 0;
  static DateTime _lastFrameReportAt = DateTime.fromMillisecondsSinceEpoch(0);

  static void event(String area, String message) {
    if (!enabled) return;
    debugPrint(
      '[PerfTrace][+${_session.elapsedMilliseconds}ms][$area] $message',
    );
  }

  static void build(String area, {String details = ''}) {
    if (!enabled) return;
    final count = (_buildCounts[area] ?? 0) + 1;
    _buildCounts[area] = count;
    final now = DateTime.now();
    final previous = _lastBuildLogAt[area];
    // Log the first build and bursts, but avoid one line per animation frame.
    if (count == 1 ||
        previous == null ||
        now.difference(previous).inSeconds >= 2) {
      _lastBuildLogAt[area] = now;
      event(area, 'build count=$count${details.isEmpty ? '' : ' $details'}');
    }
  }

  static Future<T> track<T>(
    String area,
    String operation,
    Future<T> Function() action,
  ) async {
    final stopwatch = Stopwatch()..start();
    event(area, '$operation start');
    try {
      final result = await action();
      event(area, '$operation done elapsedMs=${stopwatch.elapsedMilliseconds}');
      return result;
    } catch (error) {
      event(
        area,
        '$operation error elapsedMs=${stopwatch.elapsedMilliseconds} error=$error',
      );
      rethrow;
    }
  }

  static void installFrameTracing() {
    if (!enabled || _frameTracingInstalled) return;
    _frameTracingInstalled = true;
    SchedulerBinding.instance.addTimingsCallback((timings) {
      for (final timing in timings) {
        final frameMs = timing.totalSpan.inMilliseconds;
        if (frameMs <= 16) continue;
        _slowFrameCount += 1;
        if (frameMs > _slowestFrameMs) _slowestFrameMs = frameMs;
      }
      final now = DateTime.now();
      if (_slowFrameCount == 0 ||
          now.difference(_lastFrameReportAt).inSeconds < 2) {
        return;
      }
      event(
        'frames',
        'slowFrames=$_slowFrameCount/2s slowestMs=$_slowestFrameMs thresholdMs=16',
      );
      _slowFrameCount = 0;
      _slowestFrameMs = 0;
      _lastFrameReportAt = now;
    });
    event('frames', 'timings callback installed');
  }
}
