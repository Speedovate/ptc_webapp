// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'auth_camera_service.dart';
import 'auth_image_picker_service.dart';

bool get authCameraSupported => html.window.navigator.mediaDevices != null;

AuthCameraSession createAuthCameraSession() => _WebAuthCameraSession();

class _WebAuthCameraSession implements AuthCameraSession {
  _WebAuthCameraSession() : _viewType = 'auth-camera-${DateTime.now().microsecondsSinceEpoch}' {
    _container = html.DivElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.backgroundColor = '#1A1333'
      ..style.borderRadius = '18px'
      ..style.overflow = 'hidden'
      ..style.display = 'flex'
      ..style.alignItems = 'center'
      ..style.justifyContent = 'center';
    _video = html.VideoElement()
      ..autoplay = true
      ..muted = true
      ..setAttribute('playsinline', 'true')
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover'
      ..style.transform = 'scaleX(-1)'
      ..style.transformOrigin = 'center center'
      ..style.display = 'block';
    _container.append(_video);
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (viewId) => _container);
  }

  late final html.DivElement _container;
  late final html.VideoElement _video;
  final String _viewType;
  html.MediaStream? _stream;
  bool _initialized = false;
  bool _disposed = false;
  StreamSubscription<html.Event>? _metadataSubscription;
  StreamSubscription<html.Event>? _canPlaySubscription;
  StreamSubscription<html.Event>? _errorSubscription;

  @override
  String get viewType => _viewType;

  @override
  Future<void> initialize() async {
    if (_disposed || _initialized) {
      return;
    }
    final mediaDevices = html.window.navigator.mediaDevices;
    if (mediaDevices == null) {
      throw StateError('Camera is not supported on this browser.');
    }
    try {
      _stream = await mediaDevices.getUserMedia(<String, dynamic>{
        'video': <String, dynamic>{
          'facingMode': <String, String>{'ideal': 'environment'},
        },
        'audio': false,
      });
    } catch (_) {
      _stream = await mediaDevices.getUserMedia(<String, dynamic>{
        'video': true,
        'audio': false,
      });
    }
    if (_disposed) {
      await dispose();
      return;
    }
    _video.srcObject = _stream;
    await _video.play();
    await _waitUntilReady();
    if (_disposed) {
      await dispose();
      return;
    }
    _initialized = true;
  }

  Future<void> _waitUntilReady() async {
    if (_video.videoWidth > 0 && _video.videoHeight > 0) {
      return;
    }
    final completer = Completer<void>();

    void complete() {
      _cancelReadyListeners();
      if (!completer.isCompleted) {
        completer.complete();
      }
    }

    void fail(Object error) {
      _cancelReadyListeners();
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }

    _metadataSubscription = _video.onLoadedMetadata.listen((_) => complete());
    _canPlaySubscription = _video.onCanPlay.listen((_) => complete());
    _errorSubscription = _video.onError.listen(
      (_) => fail(StateError('Camera preview failed to initialize.')),
    );

    await completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        _cancelReadyListeners();
        throw TimeoutException('Camera preview timed out.');
      },
    );
  }

  void _cancelReadyListeners() {
    _metadataSubscription?.cancel();
    _metadataSubscription = null;
    _canPlaySubscription?.cancel();
    _canPlaySubscription = null;
    _errorSubscription?.cancel();
    _errorSubscription = null;
  }

  @override
  Future<AuthPickedImage?> capture() async {
    if (_disposed || !_initialized) {
      throw StateError('Camera is not ready.');
    }
    final width = _video.videoWidth;
    final height = _video.videoHeight;
    if (width <= 0 || height <= 0) {
      throw StateError('Camera preview is not ready.');
    }
    final canvas = html.CanvasElement(width: width, height: height);
    canvas.context2D
      ..translate(width.toDouble(), 0)
      ..scale(-1, 1)
      ..drawImageScaled(_video, 0, 0, width, height)
      ..setTransform(1, 0, 0, 1, 0, 0);
    final bytes = _canvasToJpegBytes(canvas);
    if (bytes.isEmpty) {
      throw StateError('Camera capture produced an empty image.');
    }
    return AuthPickedImage(
      bytes: Uint8List.fromList(bytes),
      fileName: 'camera_${DateTime.now().millisecondsSinceEpoch}.jpg',
      size: bytes.length,
      mimeType: 'image/jpeg',
    );
  }

  Uint8List _canvasToJpegBytes(html.CanvasElement canvas) {
    final dataUrl = canvas.toDataUrl('image/jpeg', 0.92);
    final commaIndex = dataUrl.indexOf(',');
    if (commaIndex < 0 || commaIndex >= dataUrl.length - 1) {
      return Uint8List(0);
    }
    final base64Payload = dataUrl.substring(commaIndex + 1);
    return Uint8List.fromList(base64Decode(base64Payload));
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _cancelReadyListeners();
    final tracks = _stream?.getTracks() ?? const <html.MediaStreamTrack>[];
    for (final track in tracks) {
      track.stop();
    }
    try {
      _video.pause();
    } catch (_) {}
    _video.srcObject = null;
    _video.remove();
    _container.children.clear();
    _container.remove();
    _stream = null;
    _initialized = false;
  }
}
