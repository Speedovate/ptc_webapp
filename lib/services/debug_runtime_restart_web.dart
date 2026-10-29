import 'dart:js_interop';
import 'package:flutter/foundation.dart';

// Store only a native JS boolean: Dart objects from an earlier debug runtime
// must never be reused by the next runtime.
@JS('globalThis.__paltrancoDebugRuntimeStarted')
external JSBoolean? get _started;
@JS('globalThis.__paltrancoDebugRuntimeStarted')
external set _started(JSBoolean? value);
@JS('window.location.reload')
external void _reloadPage();

bool prepareAppRuntime({bool debug = kDebugMode, VoidCallback? reload}) {
  if (!debug) return true;
  if (_started?.toDart == true) {
    if (reload != null) {
      reload();
    } else {
      _reloadPage();
    }
    return false;
  }
  _started = true.toJS;
  return true;
}
