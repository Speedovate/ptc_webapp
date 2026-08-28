// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:html' as html;

import 'auth_storage_backend.dart';

const _storagePrefix = 'flutter.';

AuthStorageBackend createAuthStorageBackend() =>
    _LocalStorageAuthStorageBackend();

class _LocalStorageAuthStorageBackend implements AuthStorageBackend {
  @override
  Future<void> initialize() async {}

  @override
  Future<List<String>> readStringList(String key) async {
    final raw = html.window.localStorage['$_storagePrefix$key'];
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((item) => item.toString()).toList(growable: false);
      }
      if (decoded is String && decoded.isNotEmpty) {
        return <String>[decoded];
      }
    } catch (_) {
      return <String>[raw];
    }
    return const [];
  }

  @override
  Future<void> writeStringList(String key, List<String> values) async {
    html.window.localStorage['$_storagePrefix$key'] = jsonEncode(values);
  }

  @override
  Future<String?> readString(String key) async {
    final raw = html.window.localStorage['$_storagePrefix$key'];
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      return decoded?.toString();
    } catch (_) {
      return raw;
    }
  }

  @override
  Future<void> writeString(String key, String value) async {
    html.window.localStorage['$_storagePrefix$key'] = jsonEncode(value);
  }

  @override
  Future<void> remove(String key) async {
    html.window.localStorage.remove('$_storagePrefix$key');
  }
}
