import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'app_cached_network_image_online_listener.dart';
import '../../services/persistent_image_cache_service.dart';

class AppCachedNetworkImage extends StatefulWidget {
  const AppCachedNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.errorBuilder,
  });

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Alignment alignment;
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  @override
  State<AppCachedNetworkImage> createState() => _AppCachedNetworkImageState();
}

class _AppCachedNetworkImageState extends State<AppCachedNetworkImage> {
  StreamSubscription<void>? _onlineSubscription;
  bool _hasError = false;
  bool _isRecoveringCachedImage = false;
  int _reloadToken = 0;
  String? _cachedImageDataUrl;
  int _webImageLoadSerial = 0;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      unawaited(_refreshWebImageSource());
      _onlineSubscription = onlineEvents().listen((_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _hasError = false;
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
      _isRecoveringCachedImage = false;
      _reloadToken = 0;
      _cachedImageDataUrl = null;
      if (kIsWeb) {
        unawaited(_refreshWebImageSource());
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
    final cachedDataUrl = await PersistentImageCacheService.instance
        .getImageDataUrl(
          cacheKey: normalizedUrl,
          fetchUrl: _resolvedImageUrl,
          forceRefresh: forceRefresh,
        );
    if (!mounted || requestSerial != _webImageLoadSerial) {
      return;
    }
    if (_cachedImageDataUrl == cachedDataUrl) {
      return;
    }
    _setStateSafely(() {
      _cachedImageDataUrl = cachedDataUrl;
    });
  }

  Widget _buildMemoryImage(String dataUrl) {
    return Image.memory(
      _decodeDataUrlBytes(dataUrl),
      key: ValueKey<String>('mem:$dataUrl|${widget.width}|${widget.height}'),
      width: widget.width,
      height: widget.height,
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
    final commaIndex = dataUrl.indexOf(',');
    final encoded = commaIndex >= 0
        ? dataUrl.substring(commaIndex + 1)
        : dataUrl;
    return base64Decode(encoded);
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
      return Image.network(
        _resolvedImageUrl,
        key: ValueKey<String>(
          '$_resolvedImageUrl|${widget.width}|${widget.height}',
        ),
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        alignment: widget.alignment,
        webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
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
}
