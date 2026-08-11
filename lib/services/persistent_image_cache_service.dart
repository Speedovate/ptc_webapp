import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:webapp/services/network_status_events.dart';
import 'package:webapp/services/persistent_image_fetcher.dart';
import 'package:webapp/services/persistent_image_cache_store.dart';

class PersistentImageCacheService {
  PersistentImageCacheService({PersistentImageCacheStore? store})
    : _store = store ?? createPersistentImageCacheStore();

  static final PersistentImageCacheService instance =
      PersistentImageCacheService();

  final PersistentImageCacheStore _store;
  final Map<String, String> _memoryCache = {};
  final Map<String, Future<String?>> _inflightLoads = {};
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }
    await _store.initialize();
    _isInitialized = true;
  }

  Future<String?> getImageDataUrl({
    required String cacheKey,
    String? fetchUrl,
    bool forceRefresh = false,
  }) async {
    if (!kIsWeb) {
      return null;
    }
    await initialize();
    final normalizedCacheKey = cacheKey.trim();
    if (normalizedCacheKey.isEmpty) {
      return null;
    }
    final inflightKey =
        '$normalizedCacheKey|${fetchUrl ?? normalizedCacheKey}|$forceRefresh';
    final inflight = _inflightLoads[inflightKey];
    if (inflight != null) {
      return inflight;
    }
    final future = _loadImageDataUrl(
      cacheKey: normalizedCacheKey,
      fetchUrl: fetchUrl,
      forceRefresh: forceRefresh,
    );
    _inflightLoads[inflightKey] = future;
    try {
      return await future;
    } finally {
      _inflightLoads.remove(inflightKey);
    }
  }

  Future<String?> _loadImageDataUrl({
    required String cacheKey,
    String? fetchUrl,
    required bool forceRefresh,
  }) async {
    final cached = await _readCachedDataUrl(cacheKey);
    if (!forceRefresh && cached != null) {
      return cached;
    }
    if (!currentNetworkStatus()) {
      return cached;
    }
    final fetched = await fetchPersistentImage(fetchUrl ?? cacheKey);
    if (fetched == null || fetched.bytes.isEmpty) {
      return cached;
    }
    final dataUrl = _toDataUrl(
      bytes: fetched.bytes,
      mimeType: fetched.mimeType,
    );
    _memoryCache[cacheKey] = dataUrl;
    await _store.writeString(
      _storageKey(cacheKey),
      jsonEncode({
        'data_url': dataUrl,
        'cached_at': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    return dataUrl;
  }

  Future<String?> _readCachedDataUrl(String cacheKey) async {
    final memoryValue = _memoryCache[cacheKey];
    if (memoryValue != null && memoryValue.isNotEmpty) {
      return memoryValue;
    }
    final raw = await _store.readString(_storageKey(cacheKey));
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final dataUrl = decoded['data_url']?.toString();
        if (dataUrl != null && dataUrl.isNotEmpty) {
          _memoryCache[cacheKey] = dataUrl;
          return dataUrl;
        }
      }
    } catch (_) {
      if (raw.startsWith('data:image/')) {
        _memoryCache[cacheKey] = raw;
        return raw;
      }
    }
    return null;
  }

  String _storageKey(String cacheKey) => 'persistent_image_cache:$cacheKey';

  String _toDataUrl({required List<int> bytes, required String mimeType}) {
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  }
}
