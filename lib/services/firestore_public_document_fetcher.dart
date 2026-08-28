import 'firestore_public_document_fetcher_stub.dart'
    if (dart.library.html) 'firestore_public_document_fetcher_web.dart'
    as impl;

abstract class FirestorePublicDocumentFetcher {
  Future<List<Map<String, dynamic>>> fetchCollectionDocuments(
    String collectionPath, {
    int pageSize = 100,
  });
}

FirestorePublicDocumentFetcher createFirestorePublicDocumentFetcher() =>
    impl.createFirestorePublicDocumentFetcher();
