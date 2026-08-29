import 'firestore_public_document_fetcher_stub.dart'
    if (dart.library.html) 'firestore_public_document_fetcher_web.dart'
    as impl;

abstract class FirestorePublicDocumentFetcher {
  Future<List<Map<String, dynamic>>> fetchCollectionDocuments(
    String collectionPath, {
    int pageSize = 100,
  });

  Future<bool> deleteDocument(String documentPath);

  Future<bool> patchDocument(
    String documentPath, {
    required Map<String, dynamic> fields,
    List<String>? updateMaskFieldPaths,
  });
}

FirestorePublicDocumentFetcher createFirestorePublicDocumentFetcher() =>
    impl.createFirestorePublicDocumentFetcher();
