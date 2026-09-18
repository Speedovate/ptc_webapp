import 'package:cloud_firestore/cloud_firestore.dart';

/// Both direct writes and offline replay use the original action timestamp.
Future<void> writeSupportReadMarker(
  FirebaseFirestore firestore,
  DocumentReference<Map<String, dynamic>> reference,
  Map<String, dynamic> document,
) async {
  await firestore.runTransaction((transaction) async {
    final existing = await transaction.get(reference);
    final previous = existing.data();
    final incomingTime = DateTime.tryParse(
      document['updated_at']?.toString() ?? '',
    );
    final previousTime = DateTime.tryParse(
      previous?['updated_at']?.toString() ?? '',
    );
    // Equal times are retries/ambiguous ordering, not authority to replace data.
    if (existing.exists &&
        previousTime != null &&
        (incomingTime == null || !incomingTime.isAfter(previousTime))) {
      return;
    }
    transaction.set(reference, document, SetOptions(merge: true));
  });
}
