import 'package:shared_preferences/shared_preferences.dart';

import 'auth_storage_backend.dart';

AuthStorageBackend createAuthStorageBackend() =>
    _SharedPreferencesAuthStorageBackend();

class _SharedPreferencesAuthStorageBackend implements AuthStorageBackend {
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
    await _prefs!.setStringList(key, values);
  }

  @override
  Future<String?> readString(String key) async {
    await initialize();
    return _prefs!.getString(key);
  }

  @override
  Future<void> writeString(String key, String value) async {
    await initialize();
    await _prefs!.setString(key, value);
  }

  @override
  Future<void> remove(String key) async {
    await initialize();
    await _prefs!.remove(key);
  }
}
