import 'persistent_image_cache_store.dart';

PersistentImageCacheStore createPersistentImageCacheStore() =>
    _MemoryPersistentImageCacheStore();

class _MemoryPersistentImageCacheStore implements PersistentImageCacheStore {
  final Map<String, String> _values = {};

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> readString(String key) async => _values[key];

  @override
  Future<void> writeString(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }
}
