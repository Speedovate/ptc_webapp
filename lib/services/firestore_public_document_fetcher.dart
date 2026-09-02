import 'firestore_public_document_fetcher_stub.dart' as impl;

abstract class FirestorePublicDocumentFetcher {
  Future<List<Map<String, dynamic>>> fetchCollectionDocuments(
    String collectionPath, {
    int pageSize = 100,
  });

  Future<Map<String, dynamic>?> fetchDocument(String documentPath);

  Future<bool> deleteDocument(String documentPath);

  Future<bool> patchDocument(
    String documentPath, {
    required Map<String, dynamic> fields,
    List<String>? updateMaskFieldPaths,
  });
}

/// Firestore SDK is the only online transport. The noop implementation keeps
/// legacy fallback call sites from issuing direct REST/XHR browser requests.
FirestorePublicDocumentFetcher createFirestorePublicDocumentFetcher() =>
    impl.createFirestorePublicDocumentFetcher();
