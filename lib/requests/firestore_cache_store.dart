import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FirestoreCacheStore {
  FirestoreCacheStore._();

  static final FirestoreCacheStore instance = FirestoreCacheStore._();

  SharedPreferences? _prefs;
  final Map<String, List<Map<String, dynamic>>> _documentMemoryCache = {};
  final Map<String, String> _versionMemoryCache = {};

  Future<void> _ensurePrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<List<Map<String, dynamic>>?> readDocumentMaps(
    String resourceKey,
  ) async {
    final memoryValue = _documentMemoryCache[resourceKey];
    if (memoryValue != null) {
      return memoryValue
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    await _ensurePrefs();
    final raw = _prefs!.getString(_dataKey(resourceKey));
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final decoded = json.decode(raw);
    if (decoded is! List) {
      return null;
    }
    final documents = decoded
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    _documentMemoryCache[resourceKey] = documents
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    return documents;
  }

  Future<void> writeDocumentMaps(
    String resourceKey,
    List<Map<String, dynamic>> documents,
  ) async {
    _documentMemoryCache[resourceKey] = documents
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    await _ensurePrefs();
    await _prefs!.setString(_dataKey(resourceKey), json.encode(documents));
  }

  Future<String?> readVersion(String resourceKey) async {
    final memoryValue = _versionMemoryCache[resourceKey];
    if (memoryValue != null) {
      return memoryValue;
    }
    await _ensurePrefs();
    final value = _prefs!.getString(_versionKey(resourceKey));
    if (value != null) {
      _versionMemoryCache[resourceKey] = value;
    }
    return value;
  }

  Future<void> writeVersion(String resourceKey, String version) async {
    _versionMemoryCache[resourceKey] = version;
    await _ensurePrefs();
    await _prefs!.setString(_versionKey(resourceKey), version);
  }

  Future<void> clearResource(String resourceKey) async {
    _documentMemoryCache.remove(resourceKey);
    _versionMemoryCache.remove(resourceKey);
    await _ensurePrefs();
    await _prefs!.remove(_dataKey(resourceKey));
    await _prefs!.remove(_versionKey(resourceKey));
  }

  String _dataKey(String resourceKey) => 'firestore_cache_data_$resourceKey';
  String _versionKey(String resourceKey) =>
      'firestore_cache_version_$resourceKey';
}

class FirestoreCollectionCache {
  FirestoreCollectionCache({
    FirebaseFirestore? firestore,
    FirestoreCacheStore? store,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _store = store ?? FirestoreCacheStore.instance;

  final FirebaseFirestore _firestore;
  final FirestoreCacheStore _store;

  CollectionReference<Map<String, dynamic>> get _versionsCollection =>
      _firestore.collection('app_cache_versions');

  Future<List<Map<String, dynamic>>> getDocuments({
    required String resourceKey,
    required Future<List<Map<String, dynamic>>> Function() fetchDocuments,
  }) async {
    final cachedDocuments = await _store.readDocumentMaps(resourceKey);
    final cachedVersion = await _store.readVersion(resourceKey);
    if (cachedDocuments != null) {
      unawaited(
        _refreshInBackground(
          resourceKey: resourceKey,
          fetchDocuments: fetchDocuments,
          cachedVersion: cachedVersion,
        ),
      );
      return cachedDocuments;
    }

    final freshDocuments = await fetchDocuments();
    final remoteVersion = await _tryReadRemoteVersion(resourceKey);
    final resolvedVersion = remoteVersion ?? _bootstrapVersion(freshDocuments);

    await Future.wait([
      _store.writeDocumentMaps(resourceKey, freshDocuments),
      _store.writeVersion(resourceKey, resolvedVersion),
    ]);

    if (remoteVersion == null) {
      await _tryWriteRemoteVersion(resourceKey, resolvedVersion);
    }

    return freshDocuments;
  }

  Future<void> touch(String resourceKey) async {
    final nextVersion = DateTime.now().toUtc().toIso8601String();
    await _store.clearResource(resourceKey);
    await _tryWriteRemoteVersion(resourceKey, nextVersion);
  }

  Future<void> touchMany(Iterable<String> resourceKeys) async {
    final keys = resourceKeys.toSet().toList();
    for (final resourceKey in keys) {
      await touch(resourceKey);
    }
  }

  Future<String?> _readRemoteVersion(String resourceKey) async {
    final snapshot = await _versionsCollection.doc(resourceKey).get();
    if (!snapshot.exists) {
      return null;
    }
    return snapshot.data()?['version']?.toString();
  }

  Future<String?> _tryReadRemoteVersion(String resourceKey) async {
    try {
      return await _readRemoteVersion(resourceKey);
    } on FirebaseException {
      return null;
    }
  }

  Future<void> _refreshInBackground({
    required String resourceKey,
    required Future<List<Map<String, dynamic>>> Function() fetchDocuments,
    required String? cachedVersion,
  }) async {
    try {
      final remoteVersion = await _tryReadRemoteVersion(resourceKey);
      if (cachedVersion != null &&
          remoteVersion != null &&
          cachedVersion == remoteVersion) {
        return;
      }

      final freshDocuments = await fetchDocuments();
      final resolvedVersion =
          remoteVersion ?? _bootstrapVersion(freshDocuments);

      await Future.wait([
        _store.writeDocumentMaps(resourceKey, freshDocuments),
        _store.writeVersion(resourceKey, resolvedVersion),
      ]);

      if (remoteVersion == null) {
        await _tryWriteRemoteVersion(resourceKey, resolvedVersion);
      }
    } catch (_) {
      // Background refresh should never block or break cached UI rendering.
    }
  }

  Future<void> _tryWriteRemoteVersion(
    String resourceKey,
    String version,
  ) async {
    try {
      await _versionsCollection.doc(resourceKey).set({
        'version': version,
        'updated_at': version,
      }, SetOptions(merge: true));
    } on FirebaseException {
      // Keep the app usable even if the cache-version collection is blocked.
    }
  }

  String _bootstrapVersion(List<Map<String, dynamic>> documents) {
    String latestUpdatedAt = 'none';
    for (final document in documents) {
      final value = document['updated_at']?.toString().trim() ?? '';
      if (value.isEmpty) {
        continue;
      }
      if (latestUpdatedAt == 'none' || value.compareTo(latestUpdatedAt) > 0) {
        latestUpdatedAt = value;
      }
    }
    return '$latestUpdatedAt|${documents.length}';
  }
}
