import 'booking_storage_backend_stub.dart'
    if (dart.library.html) 'booking_storage_backend_web.dart' as impl;

abstract class BookingStorageBackend {
  Future<void> initialize();
  Future<List<String>> readStringList(String key);
  Future<void> writeStringList(String key, List<String> values);
}

BookingStorageBackend createBookingStorageBackend() =>
    impl.createBookingStorageBackend();
