/// Small revision-scoped cache. Presentation changes reuse calculations; callers
/// replace the revision when any financial input changes.
class KpiCalculationCache<T> {
  Object? _revision;
  final _values = <Object, T>{};

  T get(Object revision, Object period, T Function() calculate) {
    if (_revision != revision) {
      _revision = revision;
      _values.clear();
    }
    return _values.putIfAbsent(period, calculate);
  }
}
