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
}

FirestorePublicDocumentFetcher createFirestorePublicDocumentFetcher() =>
    _NoopFirestorePublicDocumentFetcher();
