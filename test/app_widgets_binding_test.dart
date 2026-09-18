import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/app_widgets_binding.dart';

class _View extends Fake implements ui.FlutterView {
  _View(this.viewId);
  @override
  final int viewId;
}

void main() {
  test('only the actual registered view may submit frames', () {
    final old = _View(0);
    final replacement = _View(0);
    final registered = <int, ui.FlutterView>{0: old};
    ui.FlutterView? lookup(int id) => registered[id];
    expect(areFlutterViewsRegistered([old], lookup), isTrue);
    registered.clear();
    expect(areFlutterViewsRegistered([old], lookup), isFalse);
    registered[0] = replacement;
    expect(areFlutterViewsRegistered([old], lookup), isFalse);
    expect(areFlutterViewsRegistered([replacement], lookup), isTrue);
  });

  test('an unregistered secondary view also blocks frame submission', () {
    final first = _View(0);
    final second = _View(1);
    final registered = <int, ui.FlutterView>{0: first};
    ui.FlutterView? lookup(int id) => registered[id];
    expect(areFlutterViewsRegistered([first, second], lookup), isFalse);
    registered[1] = second;
    expect(areFlutterViewsRegistered([first, second], lookup), isTrue);
    expect(areFlutterViewsRegistered([], lookup), isTrue);
  });
}
