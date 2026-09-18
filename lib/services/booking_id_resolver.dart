import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'booking_resolution_gate.dart';

/// Resolves identity, never booking contents or assignments.
class BookingIdResolver {
  BookingIdResolver({required FirebaseFirestore firestore})
    : _firestore = firestore;
  final FirebaseFirestore _firestore;
  static final _gates = Expando<BookingResolutionGate>();
  BookingResolutionGate get _gate =>
      _gates[_firestore] ??= BookingResolutionGate();

  void invalidate(String id) => _gate.invalidate(id);

  static bool isTemporary(String? id) => id?.startsWith('offline_') == true;
  static bool isNumeric(String? id) =>
      RegExp(r'^[1-9][0-9]*$').hasMatch(id ?? '');
  static String temporaryId(String key) =>
      'offline_${key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}';
  static String reservationId(String key) =>
      'bookings_${base64UrlEncode(utf8.encode(key))}';

  Future<String?> resolve(String id, {String? submissionKey}) {
    if (!isTemporary(id)) return Future.value(id);
    // Include the supplied key: never share a result with a different identity.
    return _gate.resolve(
      id,
      jsonEncode([id, submissionKey?.trim()]),
      () => _resolveOnce(id, submissionKey: submissionKey),
    );
  }

  Future<String?> _resolveOnce(String id, {String? submissionKey}) async {
    var key = submissionKey?.trim();
    if (key == null || key.isEmpty) {
      final legacy = await _firestore.collection('bookings').doc(id).get();
      key = legacy.data()?['submission_key']?.toString().trim();
      // Historical client keys use this exact reversible format. This is only
      // a lookup candidate; both reservation and final document must verify it.
      final candidate = id.substring('offline_'.length);
      if ((key == null || key.isEmpty) &&
          RegExp(
            r'^booking_(?:[0-9]+|[0-9]+_[0-9]+_[0-9]+_[0-9]+)$',
          ).hasMatch(candidate)) {
        key = candidate;
      }
    }
    if (key == null || key.isEmpty) return null;
    if (temporaryId(key) != id) {
      throw StateError(
        'Sync conflict: temporary booking identity does not match its submission key.',
      );
    }
    final repair = await _firestore
        .collection('booking_id_repairs')
        .doc(id)
        .get();
    final migration = repair.data();
    if (migration?['resolution'] == 'keep_both_new_id') {
      final targetKey = migration?['target_submission_key']?.toString();
      final targetId = migration?['target_id']?.toString();
      if (migration?['status'] != 'repaired' ||
          migration?['source_id'] != id ||
          migration?['submission_key'] != key ||
          targetKey != 'booking_split_$id' ||
          !isNumeric(targetId)) {
        throw StateError(
          'Sync conflict: separate booking mapping is inconsistent.',
        );
      }
      final reserved = await _firestore
          .collection('manage_id')
          .doc(reservationId(targetKey!))
          .get();
      final target = await _firestore
          .collection('bookings')
          .doc(targetId)
          .get();
      if (reserved.data()?['resource_key'] != 'bookings' ||
          reserved.data()?['submission_key'] != targetKey ||
          reserved.data()?['document_id']?.toString() != targetId ||
          target.data()?['submission_key'] != targetKey ||
          reserved.data()?['original_submission_key'] != key) {
        throw StateError(
          'Sync conflict: separate booking identity cannot be verified.',
        );
      }
      return targetId;
    }
    final reservation = await _firestore
        .collection('manage_id')
        .doc(reservationId(key))
        .get();
    if (!reservation.exists) return null;
    final data = reservation.data()!;
    final finalId = data['document_id']?.toString();
    if (data['resource_key'] != 'bookings' ||
        data['submission_key'] != key ||
        !isNumeric(finalId)) {
      throw StateError(
        'Sync conflict: booking reservation identity is inconsistent.',
      );
    }
    final confirmed = await _firestore
        .collection('bookings')
        .doc(finalId)
        .get();
    if (!confirmed.exists) {
      return null; // A reserved number is not a saved booking.
    }
    if (confirmed.data()?['submission_key'] != key) {
      throw StateError(
        'Sync conflict: reserved booking belongs to another submission.',
      );
    }
    return finalId;
  }

  /// Drop only identical temporary cache copies, never divergent legacy rows.
  static List<Map<String, dynamic>> reconcileCopies(
    List<Map<String, dynamic>> documents,
  ) {
    if (!documents.any((doc) => isTemporary(doc['id']?.toString()))) {
      return documents;
    }
    final byKey = <String, List<Map<String, dynamic>>>{};
    for (final doc in documents) {
      final key = doc['submission_key']?.toString();
      if (key != null && key.isNotEmpty && isNumeric(doc['id']?.toString())) {
        byKey.putIfAbsent(key, () => []).add(doc);
      }
    }
    return documents
        .where((doc) {
          final id = doc['id']?.toString();
          final key = doc['submission_key']?.toString();
          if (!isTemporary(id) || key == null || temporaryId(key) != id) {
            return true;
          }
          final candidates = byKey[key];
          if (candidates == null || candidates.length != 1) return true;
          return !_equal(_content(doc), _content(candidates.single));
        })
        .toList(growable: false);
  }

  static Map<String, dynamic> _content(Map<String, dynamic> document) =>
      Map<String, dynamic>.from(document)
        ..remove('id')
        ..remove('local_sync_status')
        ..remove('queued_entry_id')
        ..remove('queued_created_at');

  static bool _equal(Object? left, Object? right) {
    if (left is Map && right is Map) {
      return left.length == right.length &&
          left.keys.every(
            (key) => right.containsKey(key) && _equal(left[key], right[key]),
          );
    }
    if (left is List && right is List) {
      if (left.length != right.length) {
        return false;
      }
      for (var index = 0; index < left.length; index++) {
        if (!_equal(left[index], right[index])) {
          return false;
        }
      }
      return true;
    }
    return left == right;
  }
}
