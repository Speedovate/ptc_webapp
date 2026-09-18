import 'package:flutter/widgets.dart';

/// Bounded cache of layout metrics only; never retains widgets or contexts.
class TextWidthCache {
  TextWidthCache({this.capacity = 256}) : assert(capacity > 0);

  final int capacity;
  final _widths =
      <(String, TextStyle, TextScaler, TextDirection, Locale?), double>{};
  int _measurementCount = 0;

  int get measurementCount => _measurementCount;
  int get length => _widths.length;

  double measure({
    required String text,
    required TextStyle style,
    required TextScaler textScaler,
    required TextDirection textDirection,
    Locale? locale,
  }) {
    final key = (text, style, textScaler, textDirection, locale);
    final cached = _widths.remove(key);
    if (cached != null) {
      _widths[key] = cached;
      return cached;
    }
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      textScaler: textScaler,
      locale: locale,
      maxLines: 1,
    );
    try {
      painter.layout();
      _measurementCount++;
      final width = painter.width.ceilToDouble();
      if (_widths.length >= capacity) {
        _widths.remove(_widths.keys.first);
      }
      _widths[key] = width;
      return width;
    } finally {
      painter.dispose();
    }
  }
}
