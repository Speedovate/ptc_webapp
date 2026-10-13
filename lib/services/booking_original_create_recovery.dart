import 'booking_id_resolver.dart';
import 'booking_status_continuation.dart';

/// Recover only a complete original client submission, never a photo or an
/// arbitrary temporary snapshot. Later edits remain separate queued work.
Map<String, dynamic>? originalBookingCreateForRecovery({
  required Map<String, dynamic> document,
  required String temporaryId,
  required String owner,
  String? baseUpdatedAt,
}) {
  final key = document['submission_key'];
  if (key is! String ||
      document['id'] != temporaryId ||
      BookingIdResolver.temporaryId(key) != temporaryId) {
    return null;
  }
  final parts = RegExp(
    r'^booking_([0-9]+)_([0-9]+)_([0-9]+)_([0-9]+)$',
  ).firstMatch(key);
  if (parts == null || parts[1] != owner || document['client_id'] != parts[2]) {
    return null;
  }
  final created = parseBookingSyncTimestamp(document['created_at']);
  final updated = parseBookingSyncTimestamp(document['updated_at']);
  final keyTime = DateTime.fromMicrosecondsSinceEpoch(
    int.parse(parts[4]!),
    isUtc: true,
  );
  if (created == null ||
      updated == null ||
      updated.isBefore(created) ||
      keyTime.isBefore(created) ||
      keyTime.difference(created) > const Duration(seconds: 1)) {
    return null;
  }
  final base = parseBookingSyncTimestamp(baseUpdatedAt);
  if (baseUpdatedAt != null && base == null) return null;
  final outputs = document['status_outputs'];
  if (outputs is! Map) return null;
  if (baseUpdatedAt == null &&
      (outputs.length != 1 ||
          document['client_status'] != 'pending' ||
          document['driver_status'] != 'pending' ||
          document['helper_status'] != 'pending' ||
          [
            'driver_id',
            'helper_id',
            'vehicle_make_id',
            'chassis_id',
            'delivered_at',
          ].any((field) => document[field] != null))) {
    return null;
  }
  final submissions = outputs.entries
      .where(
        (event) => event.value is Map && event.value['status_key'] == 'book',
      )
      .toList();
  if (submissions.length != 1) return null;
  final submission = submissions.single;
  final event = submission.value as Map;
  final form = event['status_form'];
  final at = parseBookingSyncTimestamp(event['submitted_at']);
  final fields = event['fields'];
  final eventKey = RegExp(r'^book__([0-9]+)$').firstMatch('${submission.key}');
  if (eventKey == null ||
      event['submitted_by'] != parts[1] ||
      event['submitted_role'] != 'client' ||
      form is! Map ||
      form['id'] != parts[3] ||
      form['is_main_form'] != true ||
      form['current_status_key'] != 'book' ||
      form['next_status_key'] != 'pending' ||
      fields is! Map ||
      fields.isEmpty ||
      at == null ||
      at.isBefore(created) ||
      at.difference(created) > const Duration(seconds: 1) ||
      (at.microsecondsSinceEpoch - int.parse(eventKey[1]!)).abs() > 1000000) {
    return null;
  }
  if (baseUpdatedAt != null && base != created && base != at) return null;
  if (baseUpdatedAt == null && updated != created && updated != at) return null;
  // A photo alone cannot reconstruct the customer's original booking.
  if ([
    'representative_name',
    'representative_phone',
    'origin',
    'destination',
    'van_size',
  ].any((field) => '${fields[field] ?? ''}'.trim().isEmpty)) {
    return null;
  }
  if (fields.keys.any(
    (key) => const {
      'driver_id',
      'helper_id',
      'vehicle_make_id',
      'chassis_id',
    }.contains(key),
  )) {
    return null;
  }
  const allowed = {
    'id',
    'submission_key',
    'client_id',
    'created_at',
    'updated_at',
    'client_status',
    'driver_status',
    'helper_status',
    'billing_status',
    'driver_id',
    'helper_id',
    'vehicle_make_id',
    'chassis_id',
    'delivered_at',
    'status_outputs',
    'local_sync_status',
    'queued_entry_id',
    'queued_created_at',
    'photo_cleanup_paths',
    'photo_cleanup_claims',
    'media_synced_at',
  };
  if (document.keys.any((key) => !allowed.contains(key))) return null;
  final original = <String, dynamic>{
    ...document,
    'client_status': 'pending',
    'driver_status': 'pending',
    'helper_status': 'pending',
    'billing_status': 'unbilled',
    'driver_id': null,
    'helper_id': null,
    'vehicle_make_id': null,
    'chassis_id': null,
    'delivered_at': null,
    'updated_at': baseUpdatedAt ?? document['updated_at'],
    'status_outputs': {'${submission.key}': event},
  };
  for (final field in [
    'local_sync_status',
    'queued_entry_id',
    'queued_created_at',
    'photo_cleanup_paths',
    'photo_cleanup_claims',
    'media_synced_at',
  ]) {
    original.remove(field);
  }
  return original;
}
