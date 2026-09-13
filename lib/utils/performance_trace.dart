/// Kept as a compatibility shim while historical trace call sites are retired.
/// It intentionally emits no logs and schedules no diagnostic work.
class PerformanceTrace {
  PerformanceTrace._();

  static const bool enabled = false;

  static void event(String area, String message) {}

  static void build(String area, {String details = ''}) {}

  static Future<T> track<T>(
    String area,
    String operation,
    Future<T> Function() action,
  ) => action();

  static void installFrameTracing() {}
}
