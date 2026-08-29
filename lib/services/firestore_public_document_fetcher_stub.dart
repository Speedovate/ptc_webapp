import 'firestore_public_document_fetcher.dart';

class _NoopFirestorePublicDocumentFetcher
    implements FirestorePublicDocumentFetcher {
  @override
  Future<List<Map<String, dynamic>>> fetchCollectionDocuments(
    String collectionPath, {
    int pageSize = 100,
  }) async {
    return const <Map<String, dynamic>>[];
  }

  @override
  Future<bool> deleteDocument(String documentPath) async {
    return false;
  }

  @override
  Future<bool> patchDocument(
    String documentPath, {
    required Map<String, dynamic> fields,
    List<String>? updateMaskFieldPaths,
  }) async {
    return false;
  }
}

FirestorePublicDocumentFetcher createFirestorePublicDocumentFetcher() =>
    _NoopFirestorePublicDocumentFetcher();
