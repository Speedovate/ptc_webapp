import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';

// Foreground timeout does not cancel Firestore. Replays of the same action
// must await that original transaction instead of starting concurrent copies.
final _writes = Expando<Map<String, Future<void>>>('support read writes');

/// Both direct writes and offline replay use the original action timestamp.
Future<void> writeSupportReadMarker(
  FirebaseFirestore firestore,
  DocumentReference<Map<String, dynamic>> reference,
  Map<String, dynamic> document,
) {
  final writes = _writes[firestore] ??= <String, Future<void>>{};
  final key = jsonEncode([reference.path, document]);
  return writes.putIfAbsent(key, () async {
    try {
      await _write(firestore, reference, document);
    } finally {
      writes.remove(key);
    }
  });
}

Future<void> _write(
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
