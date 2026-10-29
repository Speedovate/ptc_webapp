import 'debug_runtime_restart_stub.dart'
    if (dart.library.html) 'debug_runtime_restart_web.dart'
    as impl;

/// A web debug restart needs a new JS realm before background services start.
/// Otherwise browser-owned callbacks can resume with the previous Dart runtime.
bool prepareAppRuntime() => impl.prepareAppRuntime();
