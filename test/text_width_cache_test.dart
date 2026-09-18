import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/utils/text_width_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  double measure(
    TextWidthCache cache,
    String text, {
    double scale = 1,
    double fontSize = 14,
  }) => cache.measure(
    text: text,
    style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
    textScaler: TextScaler.linear(scale),
    textDirection: TextDirection.ltr,
  );

  test('107 identifiers across 50 rebuilds require only 107 text layouts', () {
    final cache = TextWidthCache();
    for (var rebuild = 0; rebuild < 50; rebuild++) {
      for (var row = 0; row < 107; row++) {
        measure(cache, 'MSLU${3557430 + row}');
      }
    }
    expect(cache.measurementCount, 107);
    expect(cache.length, 107);
  });

  test('text, font and accessibility scale changes invalidate metrics', () {
    final cache = TextWidthCache();
    final base = measure(cache, 'MSLU3557430');
    expect(measure(cache, 'MSLU3557430', scale: 2), greaterThan(base));
    expect(measure(cache, 'MSLU3557430', fontSize: 20), greaterThan(base));
    measure(cache, 'IPXU3721382');
    expect(cache.measurementCount, 4);
    expect(measure(cache, 'MSLU3557430'), base);
    expect(cache.measurementCount, 4);
  });

  test(
    'cache size stays bounded and recently used metrics survive eviction',
    () {
      final cache = TextWidthCache(capacity: 2);
      measure(cache, 'a');
      measure(cache, 'b');
      measure(cache, 'a');
      measure(cache, 'c');
      expect(cache.length, 2);
      measure(cache, 'a');
      expect(cache.measurementCount, 3);
      measure(cache, 'b');
      expect(cache.measurementCount, 4);
      expect(cache.length, 2);
    },
  );
}
