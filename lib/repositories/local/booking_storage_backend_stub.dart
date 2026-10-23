import 'package:shared_preferences/shared_preferences.dart';

import 'booking_storage_backend.dart';

BookingStorageBackend createBookingStorageBackend() =>
    _SharedPreferencesBookingStorageBackend();

class _SharedPreferencesBookingStorageBackend implements BookingStorageBackend {
  SharedPreferences? _prefs;

  @override
  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  @override
  Future<List<String>> readStringList(String key) async {
    await initialize();
    return _prefs!.getStringList(key) ?? const [];
  }

  @override
  Future<void> writeStringList(String key, List<String> values) async {
    await initialize();
    if (!await _prefs!.setStringList(key, values)) {
      throw StateError('Local booking storage did not accept the write.');
    }
  }
}
