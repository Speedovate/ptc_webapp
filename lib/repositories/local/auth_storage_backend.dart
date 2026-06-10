import 'auth_storage_backend_stub.dart'
    if (dart.library.html) 'auth_storage_backend_web.dart'
    as impl;

abstract class AuthStorageBackend {
  Future<void> initialize();
  Future<List<String>> readStringList(String key);
  Future<void> writeStringList(String key, List<String> values);
  Future<String?> readString(String key);
  Future<void> writeString(String key, String value);
  Future<void> remove(String key);
}

AuthStorageBackend createAuthStorageBackend() =>
    impl.createAuthStorageBackend();
