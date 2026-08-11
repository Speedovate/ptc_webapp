import 'persistent_image_cache_store_stub.dart'
    if (dart.library.html) 'persistent_image_cache_store_web.dart'
    as impl;

abstract class PersistentImageCacheStore {
  Future<void> initialize();
  Future<String?> readString(String key);
  Future<void> writeString(String key, String value);
  Future<void> remove(String key);
}

PersistentImageCacheStore createPersistentImageCacheStore() =>
    impl.createPersistentImageCacheStore();
