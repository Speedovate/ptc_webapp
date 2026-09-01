import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/services/network_status_events.dart';

class FirestoreCacheStore {
  FirestoreCacheStore._();

  static final FirestoreCacheStore instance = FirestoreCacheStore._();
  static const _dataPrefix = 'firestore_cache_data_';
  static const _versionPrefix = 'firestore_cache_version_';

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

  Future<void> clearAll() async {
    _documentMemoryCache.clear();
    _versionMemoryCache.clear();
    await _ensurePrefs();
    final keysToRemove = _prefs!.getKeys().where((key) {
      return key.startsWith(_dataPrefix) || key.startsWith(_versionPrefix);
    }).toList();
    for (final key in keysToRemove) {
      await _prefs!.remove(key);
    }
  }

  String _dataKey(String resourceKey) => '$_dataPrefix$resourceKey';
  String _versionKey(String resourceKey) => '$_versionPrefix$resourceKey';
}

class FirestoreCollectionCache {
  FirestoreCollectionCache({
    FirebaseFirestore? firestore,
    FirestoreCacheStore? store,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _store = store ?? FirestoreCacheStore.instance;

  final FirebaseFirestore _firestore;
  final FirestoreCacheStore _store;
  static const Duration _remoteVersionTimeout = Duration(seconds: 1);

  CollectionReference<Map<String, dynamic>> get _versionsCollection =>
      _firestore.collection('app_cache_versions');

  Stream<String?> watchResourceVersion(String resourceKey) {
    return _versionsCollection.doc(resourceKey).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        return null;
      }
      return snapshot.data()?['version']?.toString();
    });
  }

  Future<bool> hasRemoteVersionMismatch(
    String resourceKey,
    String? remoteVersion,
  ) async {
    if (remoteVersion == null || remoteVersion.isEmpty) {
      return false;
    }
    final localVersion = await _store.readVersion(resourceKey);
    return localVersion != remoteVersion;
  }

  Future<String?> readStoredVersion(String resourceKey) {
    return _store.readVersion(resourceKey);
  }

  Future<String?> readRemoteVersionSafe(String resourceKey) {
    return _tryReadRemoteVersion(resourceKey);
  }

  Future<List<Map<String, dynamic>>> getDocuments({
    required String resourceKey,
    required Future<List<Map<String, dynamic>>> Function() fetchDocuments,
  }) async {
    final cachedDocuments = await _store.readDocumentMaps(resourceKey);
    final cachedVersion = await _store.readVersion(resourceKey);
    if (cachedDocuments != null) {
      if (cachedDocuments.isEmpty) {
        try {
          final freshDocuments = await fetchDocuments();
          final remoteVersion = await _tryReadRemoteVersion(resourceKey);
          final resolvedVersion =
              remoteVersion ?? _bootstrapVersion(freshDocuments);

          await Future.wait([
            _store.writeDocumentMaps(resourceKey, freshDocuments),
            _store.writeVersion(resourceKey, resolvedVersion),
          ]);

          return freshDocuments;
        } catch (_) {
          return cachedDocuments;
        }
      }
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

    return freshDocuments;
  }

  Future<List<Map<String, dynamic>>> getDocumentsVerifiedOnlineFirst({
    required String resourceKey,
    required Future<List<Map<String, dynamic>>> Function() fetchDocuments,
  }) async {
    final cachedDocuments = await _store.readDocumentMaps(resourceKey);

    if (currentNetworkStatus()) {
      try {
        final freshDocuments = await fetchDocuments();
        final remoteVersion = await _tryReadRemoteVersion(resourceKey);
        final resolvedVersion =
            remoteVersion ?? _bootstrapVersion(freshDocuments);

        await Future.wait([
          _store.writeDocumentMaps(resourceKey, freshDocuments),
          _store.writeVersion(resourceKey, resolvedVersion),
        ]);

        return freshDocuments;
      } catch (_) {
        if (cachedDocuments != null) {
          return cachedDocuments;
        }
      }
    }

    if (cachedDocuments != null) {
      return cachedDocuments;
    }

    final freshDocuments = await fetchDocuments();
    final remoteVersion = await _tryReadRemoteVersion(resourceKey);
    final resolvedVersion = remoteVersion ?? _bootstrapVersion(freshDocuments);

    await Future.wait([
      _store.writeDocumentMaps(resourceKey, freshDocuments),
      _store.writeVersion(resourceKey, resolvedVersion),
    ]);

    return freshDocuments;
  }

  Future<void> touch(String resourceKey) async {
    final nextVersion = DateTime.now().toUtc().toIso8601String();
    await _store.clearResource(resourceKey);
    if (currentNetworkStatus()) {
      await _tryWriteRemoteVersion(resourceKey, nextVersion);
    } else {
      unawaited(_tryWriteRemoteVersion(resourceKey, nextVersion));
    }
  }

  Future<void> upsertDocument({
    required String resourceKey,
    required Map<String, dynamic> document,
  }) async {
    final documentId = document['id']?.toString().trim() ?? '';
    if (documentId.isEmpty) {
      await touch(resourceKey);
      return;
    }

    final currentDocuments =
        await _store.readDocumentMaps(resourceKey) ?? <Map<String, dynamic>>[];
    final nextDocuments = currentDocuments
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final existingIndex = nextDocuments.indexWhere(
      (item) => (item['id']?.toString().trim() ?? '') == documentId,
    );
    final normalizedDocument = Map<String, dynamic>.from(document);
    if (existingIndex >= 0) {
      nextDocuments[existingIndex] = normalizedDocument;
    } else {
      nextDocuments.add(normalizedDocument);
    }

    await _writeLocalAndRemoteVersion(
      resourceKey: resourceKey,
      documents: nextDocuments,
    );
  }

  Future<void> removeDocument({
    required String resourceKey,
    required String documentId,
  }) async {
    final normalizedId = documentId.trim();
    if (normalizedId.isEmpty) {
      await touch(resourceKey);
      return;
    }

    final currentDocuments = await _store.readDocumentMaps(resourceKey);
    if (currentDocuments == null) {
      await touch(resourceKey);
      return;
    }

    final nextDocuments = currentDocuments
        .where((item) => (item['id']?.toString().trim() ?? '') != normalizedId)
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    await _writeLocalAndRemoteVersion(
      resourceKey: resourceKey,
      documents: nextDocuments,
    );
  }

  Future<void> touchMany(Iterable<String> resourceKeys) async {
    final keys = resourceKeys.toSet().toList();
    for (final resourceKey in keys) {
      await touch(resourceKey);
    }
  }

  Future<List<Map<String, dynamic>>?> readDocuments(String resourceKey) {
    return _store.readDocumentMaps(resourceKey);
  }

  Future<void> writeDocuments({
    required String resourceKey,
    required List<Map<String, dynamic>> documents,
  }) async {
    // Realtime snapshots and collection reads must never publish a new remote
    // version. Doing so feeds the version listener back into another refresh.
    final localVersion = await _store.readVersion(resourceKey);
    final resolvedVersion = localVersion ?? _bootstrapVersion(documents);
    await Future.wait([
      _store.writeDocumentMaps(
        resourceKey,
        documents
            .map((document) => Map<String, dynamic>.from(document))
            .toList(),
      ),
      _store.writeVersion(resourceKey, resolvedVersion),
    ]);
  }

  Future<void> clearResource(String resourceKey) {
    return _store.clearResource(resourceKey);
  }

  Future<String?> _readRemoteVersion(String resourceKey) async {
    final snapshot = await _versionsCollection
        .doc(resourceKey)
        .get()
        .timeout(
          _remoteVersionTimeout,
          onTimeout: () => throw TimeoutException('cache version read timeout'),
        );
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
    } on TimeoutException {
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
    } catch (_) {
      // Background refresh should never block or break cached UI rendering.
    }
  }

  Future<void> _writeLocalAndRemoteVersion({
    required String resourceKey,
    required List<Map<String, dynamic>> documents,
  }) async {
    final nextVersion = DateTime.now().toUtc().toIso8601String();
    await Future.wait([
      _store.writeDocumentMaps(resourceKey, documents),
      _store.writeVersion(resourceKey, nextVersion),
    ]);
    unawaited(_tryWriteRemoteVersion(resourceKey, nextVersion));
  }

  Future<void> _tryWriteRemoteVersion(
    String resourceKey,
    String version,
  ) async {
    try {
      await _versionsCollection
          .doc(resourceKey)
          .set({
            'version': version,
            'updated_at': version,
          }, SetOptions(merge: true))
          .timeout(_remoteVersionTimeout);
    } on FirebaseException {
      // Keep the app usable even if the cache-version collection is blocked.
    } on TimeoutException {
      // Keep the app usable even if the cache-version collection is slow.
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
