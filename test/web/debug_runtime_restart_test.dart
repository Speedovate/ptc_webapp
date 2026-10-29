@TestOn('browser')
library;

import 'dart:js_interop';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/debug_runtime_restart_web.dart';

@JS('globalThis.__paltrancoDebugRuntimeStarted')
external JSBoolean? get started;
@JS('globalThis.__paltrancoDebugRuntimeStarted')
external set started(JSBoolean? value);

void main() {
  setUp(() => started = null);
  tearDown(() => started = null);

  test('debug restart reloads before a second runtime starts services', () {
    var reloads = 0;
    void reload() => reloads++;
    expect(prepareAppRuntime(debug: true, reload: reload), isTrue);
    expect(reloads, 0);
    expect(started?.toDart, isTrue);
    expect(prepareAppRuntime(debug: true, reload: reload), isFalse);
    expect(reloads, 1);
  });

  test('production startup never reloads or changes the debug marker', () {
    started = true.toJS;
    var reloads = 0;
    expect(prepareAppRuntime(debug: false, reload: () => reloads++), isTrue);
    expect(reloads, 0);
    expect(started?.toDart, isTrue);
    started = null;
    expect(prepareAppRuntime(debug: false, reload: () => reloads++), isTrue);
    expect(started, isNull);
  });
}
