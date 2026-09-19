import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'app_cached_network_image_online_listener.dart';
import '../../services/persistent_image_cache_service.dart';
import '../../services/network_status_events.dart';
import '../../utils/performance_trace.dart';

class AppCachedNetworkImage extends StatefulWidget {
  const AppCachedNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.errorBuilder,
    this.cacheWidth,
    this.cacheHeight,
  });

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Alignment alignment;
  final Widget Function(BuildContext context, Object error)? errorBuilder;
  // Physical-pixel decode targets. The original file remains in persistent
  // storage for offline use; this only bounds the in-memory Flutter texture.
  final int? cacheWidth;
  final int? cacheHeight;

  @override
  State<AppCachedNetworkImage> createState() => _AppCachedNetworkImageState();
}

class _AppCachedNetworkImageState extends State<AppCachedNetworkImage> {
  // MemoryImage keys use byte-list identity. Reusing the same decoded bytes
  // lets Flutter share one decode among repeated avatars in a support thread.
  static final Map<String, Uint8List> _decodedDataUrls = <String, Uint8List>{};
  static final List<String> _decodedDataUrlRecency = <String>[];
  static const int _maximumDecodedDataUrlEntries = 6;
  static const int _maximumDecodedDataUrlBytes = 4 * 1024 * 1024;

  StreamSubscription<void>? _onlineSubscription;
  bool _hasError = false;
  Object? _lastError;
  bool _isRecoveringCachedImage = false;
  int _reloadToken = 0;
  String? _cachedImageDataUrl;
  bool _keepsInitialNetworkImage = false;
  int _webImageLoadSerial = 0;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _cachedImageDataUrl = PersistentImageCacheService.instance
          .peekMemoryImageDataUrl(widget.imageUrl);
      _keepsInitialNetworkImage = _cachedImageDataUrl == null;
      _traceImageSource(
        _cachedImageDataUrl == null ? 'network-fallback' : 'memory-hit',
      );
      if (_cachedImageDataUrl == null) {
        unawaited(_refreshWebImageSource());
      }
      _onlineSubscription = onlineEvents().listen((_) {
        // A browser can dispatch duplicate `online` events without an actual
        // failed image. Retrying every visible image changes its URL and
        // causes needless network, decode, and rebuild work.
        if (!mounted || !_hasError) {
          return;
        }
        setState(() {
          _hasError = false;
          _lastError = null;
          _reloadToken++;
        });
        unawaited(_refreshWebImageSource(forceRefresh: true));
      });
    }
  }

  @override
  void didUpdateWidget(covariant AppCachedNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _hasError = false;
      _lastError = null;
      _isRecoveringCachedImage = false;
      _reloadToken = 0;
      _cachedImageDataUrl = PersistentImageCacheService.instance
          .peekMemoryImageDataUrl(widget.imageUrl);
      _keepsInitialNetworkImage = _cachedImageDataUrl == null;
      _traceImageSource(
        _cachedImageDataUrl == null
            ? 'url-change-network-fallback'
            : 'url-change-memory-hit',
      );
      if (kIsWeb) {
        if (_cachedImageDataUrl == null) {
          unawaited(_refreshWebImageSource());
        }
      }
    }
  }

  @override
  void dispose() {
    _onlineSubscription?.cancel();
    super.dispose();
  }

  void _setStateSafely(VoidCallback fn) {
    if (!mounted) {
      return;
    }
    final schedulerPhase = SchedulerBinding.instance.schedulerPhase;
    if (schedulerPhase == SchedulerPhase.persistentCallbacks ||
        schedulerPhase == SchedulerPhase.midFrameMicrotasks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(fn);
      });
      return;
    }
    setState(fn);
  }

  void _handleError(Object error) {
    _lastError = error;
    if (kIsWeb) {
      unawaited(_recoverCachedImageAfterError());
    }
    if (!_hasError && mounted) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _hasError) {
          return;
        }
        setState(() {
          _hasError = true;
        });
      });
    }
  }

  String get _resolvedImageUrl {
    if (_reloadToken == 0) {
      return widget.imageUrl;
    }
    final separator = widget.imageUrl.contains('?') ? '&' : '?';
    return '${widget.imageUrl}${separator}img_retry=$_reloadToken';
  }

  void _traceImageSource(String source) {
    if (!PerformanceTrace.enabled) {
      return;
    }
    final cacheKey = widget.imageUrl
        .trim()
        .hashCode
        .toUnsigned(32)
        .toRadixString(16);
    PerformanceTrace.event('image-source', 'key=$cacheKey source=$source');
  }

  Future<void> _recoverCachedImageAfterError() async {
    if (!kIsWeb || _isRecoveringCachedImage) {
      return;
    }
    if (mounted) {
      _setStateSafely(() {
        _isRecoveringCachedImage = true;
      });
    } else {
      _isRecoveringCachedImage = true;
    }
    try {
      await _refreshWebImageSource();
    } finally {
      final isMounted = mounted;
      if (!isMounted) {
        _isRecoveringCachedImage = false;
      } else {
        _setStateSafely(() {
          _isRecoveringCachedImage = false;
        });
      }
    }
  }

  Future<void> _refreshWebImageSource({bool forceRefresh = false}) async {
    if (!kIsWeb) {
      return;
    }
    final normalizedUrl = widget.imageUrl.trim();
    if (normalizedUrl.isEmpty || normalizedUrl.startsWith('data:')) {
      if (mounted && _cachedImageDataUrl != normalizedUrl) {
        _setStateSafely(() {
          _cachedImageDataUrl = normalizedUrl.isEmpty ? null : normalizedUrl;
        });
      }
      return;
    }
    final requestSerial = ++_webImageLoadSerial;
    String? cachedDataUrl;
    try {
      cachedDataUrl = await PersistentImageCacheService.instance
          .getImageDataUrl(
            cacheKey: normalizedUrl,
            fetchUrl: _resolvedImageUrl,
            forceRefresh: forceRefresh,
          );
    } catch (_) {
      // The normal network image below remains a fallback when persistent
      // browser storage is unavailable.
    }
    if (!mounted || requestSerial != _webImageLoadSerial) {
      return;
    }
    if (_keepsInitialNetworkImage &&
        !forceRefresh &&
        !_hasError &&
        !_isRecoveringCachedImage &&
        currentNetworkStatus()) {
      // Let the first browser image remain visible while its bytes are saved
      // for the next mount. Swapping it to a data URL mid-render causes the
      // white flash seen when selecting support users.
      return;
    }
    if (_cachedImageDataUrl == cachedDataUrl) {
      return;
    }
    _setStateSafely(() {
      _cachedImageDataUrl = cachedDataUrl;
      _keepsInitialNetworkImage = false;
    });
  }

  Widget _buildMemoryImage(String dataUrl) {
    final cacheWidth = _resolvedCacheWidth(context);
    final cacheHeight = _resolvedCacheHeight(context);
    return Image.memory(
      _decodeDataUrlBytes(dataUrl),
      // Do not retain an entire base64 image in the widget key.
      key: ValueKey<String>(
        'mem:${dataUrl.hashCode}|${widget.width}|${widget.height}',
      ),
      width: widget.width,
      height: widget.height,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      fit: widget.fit,
      alignment: widget.alignment,
      errorBuilder: (context, error, stackTrace) {
        _handleError(error);
        if (widget.errorBuilder != null) {
          return widget.errorBuilder!(context, error);
        }
        return const SizedBox.shrink();
      },
    );
  }

  Uint8List _decodeDataUrlBytes(String dataUrl) {
    final cached = _decodedDataUrls[dataUrl];
    if (cached != null) {
      _touchDecodedDataUrl(dataUrl);
      return cached;
    }
    final commaIndex = dataUrl.indexOf(',');
    final encoded = commaIndex >= 0
        ? dataUrl.substring(commaIndex + 1)
        : dataUrl;
    final decoded = base64Decode(encoded);
    _decodedDataUrls[dataUrl] = decoded;
    _touchDecodedDataUrl(dataUrl);
    while (_decodedDataUrls.length > _maximumDecodedDataUrlEntries ||
        _decodedDataUrlBytes > _maximumDecodedDataUrlBytes) {
      final oldest = _decodedDataUrlRecency.removeAt(0);
      _decodedDataUrls.remove(oldest);
    }
    return decoded;
  }

  void _touchDecodedDataUrl(String dataUrl) {
    _decodedDataUrlRecency.remove(dataUrl);
    _decodedDataUrlRecency.add(dataUrl);
  }

  static int get _decodedDataUrlBytes => _decodedDataUrls.values.fold<int>(
    0,
    (total, bytes) => total + bytes.length,
  );

  static const int _maximumDecodeDimension = 1280;

  int? _resolvedCacheWidth(BuildContext context) {
    return widget.cacheWidth ??
        _physicalDimension(context, widget.width) ??
        _maximumDecodeDimension;
  }

  int? _resolvedCacheHeight(BuildContext context) {
    return widget.cacheHeight ?? _physicalDimension(context, widget.height);
  }

  int? _physicalDimension(BuildContext context, double? logicalDimension) {
    if (logicalDimension == null ||
        !logicalDimension.isFinite ||
        logicalDimension <= 0) {
      return null;
    }
    final physical = (logicalDimension * MediaQuery.devicePixelRatioOf(context))
        .round();
    return physical.clamp(1, _maximumDecodeDimension).toInt();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      final directDataUrl = widget.imageUrl.trim();
      if (directDataUrl.startsWith('data:')) {
        return _buildMemoryImage(directDataUrl);
      }
      final cachedImageDataUrl = _cachedImageDataUrl;
      if (cachedImageDataUrl != null && cachedImageDataUrl.isNotEmpty) {
        return _buildMemoryImage(cachedImageDataUrl);
      }
      if (_hasError) {
        return _buildErrorFallback(_lastError);
      }
      return Image.network(
        _resolvedImageUrl,
        key: ValueKey<String>(
          '$_resolvedImageUrl|${widget.width}|${widget.height}',
        ),
        width: widget.width,
        height: widget.height,
        cacheWidth: _resolvedCacheWidth(context),
        cacheHeight: _resolvedCacheHeight(context),
        fit: widget.fit,
        alignment: widget.alignment,
        errorBuilder: (context, error, stackTrace) {
          _handleError(error);
          final recoveredDataUrl = _cachedImageDataUrl;
          if (recoveredDataUrl != null && recoveredDataUrl.isNotEmpty) {
            return _buildMemoryImage(recoveredDataUrl);
          }
          if (_isRecoveringCachedImage) {
            return const SizedBox.shrink();
          }
          if (widget.errorBuilder != null) {
            return widget.errorBuilder!(context, error);
          }
          return const SizedBox.shrink();
        },
      );
    }

    if (_hasError) {
      return _buildErrorFallback(_lastError);
    }

    return CachedNetworkImage(
      imageUrl: _resolvedImageUrl,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      alignment: widget.alignment,
      placeholder: (context, url) => const SizedBox.shrink(),
      errorWidget: (context, url, error) {
        _handleError(error);
        if (widget.errorBuilder != null) {
          return widget.errorBuilder!(context, error);
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildErrorFallback(Object? error) {
    if (widget.errorBuilder != null) {
      return widget.errorBuilder!(
        context,
        error ?? StateError('Image could not be loaded.'),
      );
    }
    return const SizedBox.shrink();
  }
}
