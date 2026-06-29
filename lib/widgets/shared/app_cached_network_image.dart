import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_cached_network_image_online_listener.dart';

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
  int _reloadToken = 0;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _onlineSubscription = onlineEvents().listen((_) {
        if (!mounted || !_hasError) {
          return;
        }
        setState(() {
          _hasError = false;
          _reloadToken++;
        });
      });
    }
  }

  @override
  void didUpdateWidget(covariant AppCachedNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _hasError = false;
      _reloadToken = 0;
    }
  }

  @override
  void dispose() {
    _onlineSubscription?.cancel();
    super.dispose();
  }

  void _handleError(Object error) {
    if (!_hasError && mounted) {
      setState(() {
        _hasError = true;
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

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
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
