import 'persistent_image_fetcher_stub.dart'
    if (dart.library.html) 'persistent_image_fetcher_web.dart'
    as impl;

class PersistentFetchedImage {
  const PersistentFetchedImage({required this.bytes, required this.mimeType});

  final List<int> bytes;
  final String mimeType;
}

Future<PersistentFetchedImage?> fetchPersistentImage(String url) {
  return impl.fetchPersistentImage(url);
}
