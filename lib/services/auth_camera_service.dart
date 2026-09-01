import 'auth_camera_service_stub.dart'
    if (dart.library.html) 'auth_camera_service_web.dart'
    as impl;
import 'auth_image_picker_service.dart';

abstract class AuthCameraSession {
  String? get viewType;

  Future<void> initialize();

  Future<void> switchCamera();

  bool get isFrontCamera;

  Future<AuthPickedImage?> capture();

  Future<void> dispose();
}

bool get authCameraSupported => impl.authCameraSupported;

AuthCameraSession createAuthCameraSession() => impl.createAuthCameraSession();
