import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:webapp/services/network_status_events.dart';
import 'package:webapp/services/persistent_image_fetcher.dart';
import 'package:webapp/services/persistent_image_cache_store.dart';
import 'package:webapp/utils/performance_trace.dart';

class PersistentImageCacheService {
  PersistentImageCacheService({PersistentImageCacheStore? store})
    : _store = store ?? createPersistentImageCacheStore();

  static final PersistentImageCacheService instance =
      PersistentImageCacheService();

  final PersistentImageCacheStore _store;
  final Map<String, String> _memoryCache = {};
  final List<String> _memoryCacheRecency = <String>[];
  final Map<String, Future<String?>> _inflightLoads = {};
  final Queue<_QueuedImageFetch> _networkFetchQueue =
      Queue<_QueuedImageFetch>();
  bool _isInitialized = false;
  Future<void>? _initializationFuture;
  int _activeNetworkFetches = 0;

  // A data URL costs more than its original image bytes and CanvasKit decodes
  // it again. Keep this tiny on mobile Safari, which can terminate the web
  // process instead of surfacing an out-of-memory error.
  static const int _maximumMemoryCacheEntries = 6;
  static const int _maximumMemoryCacheBytes = 6 * 1024 * 1024;
  static const int _maximumConcurrentNetworkFetches = 2;

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }
    await (_initializationFuture ??= _initializeStore());
  }

  Future<void> _initializeStore() async {
    try {
      await _store.initialize();
      _isInitialized = true;
    } finally {
      _initializationFuture = null;
    }
  }

  /// Returns an already-hydrated image without an asynchronous storage read.
  /// Widgets use this during their first build to avoid briefly rendering the
  /// network image again when switching between cached support conversations.
  String? peekMemoryImageDataUrl(String cacheKey) {
    final normalizedCacheKey = cacheKey.trim();
    final value = _memoryCache[normalizedCacheKey];
    if (value == null || value.isEmpty) {
      return null;
    }
    _touchMemoryCacheKey(normalizedCacheKey);
    return value;
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
      _trace(cacheKey, 'persistent-hit');
      return cached;
    }
    if (!currentNetworkStatus()) {
      _trace(cacheKey, 'offline-miss');
      return cached;
    }
    _trace(cacheKey, forceRefresh ? 'network-refresh' : 'network-fetch');
    final fetched = await _fetchWithConcurrency(fetchUrl ?? cacheKey);
    if (fetched == null || fetched.bytes.isEmpty) {
      _trace(cacheKey, 'network-miss');
      return cached;
    }
    final dataUrl = _toDataUrl(
      bytes: fetched.bytes,
      mimeType: fetched.mimeType,
    );
    _putMemoryCache(cacheKey, dataUrl);
    await _store.writeString(
      _storageKey(cacheKey),
      jsonEncode({
        'data_url': dataUrl,
        'cached_at': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    _trace(cacheKey, 'network-cached bytes=${fetched.bytes.length}');
    return dataUrl;
  }

  void _trace(String cacheKey, String message) {
    if (!PerformanceTrace.enabled) {
      return;
    }
    final key = cacheKey.hashCode.toUnsigned(32).toRadixString(16);
    PerformanceTrace.event('image-cache', 'key=$key $message');
  }

  Future<PersistentFetchedImage?> _fetchWithConcurrency(String url) {
    final completer = Completer<PersistentFetchedImage?>();
    _networkFetchQueue.add(_QueuedImageFetch(url: url, completer: completer));
    _drainNetworkFetchQueue();
    return completer.future;
  }

  void _drainNetworkFetchQueue() {
    while (_activeNetworkFetches < _maximumConcurrentNetworkFetches &&
        _networkFetchQueue.isNotEmpty) {
      final next = _networkFetchQueue.removeFirst();
      _activeNetworkFetches++;
      unawaited(() async {
        try {
          next.completer.complete(await fetchPersistentImage(next.url));
        } catch (_) {
          next.completer.complete(null);
        } finally {
          _activeNetworkFetches--;
          _drainNetworkFetchQueue();
        }
      }());
    }
  }

  Future<String?> _readCachedDataUrl(String cacheKey) async {
    final memoryValue = _memoryCache[cacheKey];
    if (memoryValue != null && memoryValue.isNotEmpty) {
      _touchMemoryCacheKey(cacheKey);
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
          _putMemoryCache(cacheKey, dataUrl);
          return dataUrl;
        }
      }
    } catch (_) {
      if (raw.startsWith('data:image/')) {
        _putMemoryCache(cacheKey, raw);
        return raw;
      }
    }
    return null;
  }

  String _storageKey(String cacheKey) => 'persistent_image_cache:$cacheKey';

  void _putMemoryCache(String cacheKey, String dataUrl) {
    _memoryCache[cacheKey] = dataUrl;
    _touchMemoryCacheKey(cacheKey);
    while (_memoryCache.length > _maximumMemoryCacheEntries ||
        _memoryCacheBytes > _maximumMemoryCacheBytes) {
      final oldestKey = _memoryCacheRecency.removeAt(0);
      _memoryCache.remove(oldestKey);
    }
  }

  void _touchMemoryCacheKey(String cacheKey) {
    _memoryCacheRecency.remove(cacheKey);
    _memoryCacheRecency.add(cacheKey);
  }

  int get _memoryCacheBytes =>
      _memoryCache.values.fold<int>(0, (total, value) => total + value.length);

  String _toDataUrl({required List<int> bytes, required String mimeType}) {
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  }
}

class _QueuedImageFetch {
  const _QueuedImageFetch({required this.url, required this.completer});

  final String url;
  final Completer<PersistentFetchedImage?> completer;
}
