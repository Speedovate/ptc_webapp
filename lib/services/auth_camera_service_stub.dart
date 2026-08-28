import 'auth_camera_service.dart';
import 'auth_image_picker_service.dart';

bool get authCameraSupported => false;

AuthCameraSession createAuthCameraSession() => _UnsupportedAuthCameraSession();

class _UnsupportedAuthCameraSession implements AuthCameraSession {
  @override
  String? get viewType => null;

  @override
  Future<void> initialize() async {}

  @override
  Future<AuthPickedImage?> capture() async => null;

  @override
  Future<void> dispose() async {}
}
