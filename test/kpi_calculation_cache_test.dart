import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/kpi/kpi_calculation_cache.dart';

void main() {
  test(
    'presentation rebuild reuses periods; changed data invalidates every period',
    () {
      final cache = KpiCalculationCache<int>();
      var calls = 0;
      int calculate() => ++calls;
      final data = Object();
      for (var rebuild = 0; rebuild < 20; rebuild++) {
        for (var week = 0; week < 5; week++) {
          expect(cache.get((data, 'September'), week, calculate), week + 1);
        }
      }
      expect(calls, 5);
      final edited = Object();
      expect(cache.get((edited, 'September'), 0, calculate), 6);
      expect(cache.get((edited, 'September'), 1, calculate), 7);
      expect(cache.get((edited, 'October'), 0, calculate), 8);
    },
  );
}
