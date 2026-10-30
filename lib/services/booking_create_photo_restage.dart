import 'booking_status_continuation.dart';

/// An offline create can commit before its locally restaged photo and next
/// workflow action reach the server. Keep the later local photo marker only
/// when the committed first event is otherwise exactly the same.
bool canContinueRestagedBookingCreate(
  Map<String, dynamic> server,
  Map<String, dynamic> pending, {
  required String? baseUpdatedAt,
  Map<String, dynamic>? verifiedMake,
}) {
  final before = server['status_outputs'];
  final after = pending['status_outputs'];
  if (before is! Map ||
      after is! Map ||
      before.length != 1 ||
      after.length != 2 ||
      server['client_status'] != 'pending' ||
      pending['client_status'] != 'assigned' ||
      server['created_at']?.toString() != baseUpdatedAt ||
      server['submission_key'] != pending['submission_key'] ||
      server['id'] != pending['id']) {
    return false;
  }
  final eventKey = before.keys.single.toString();
  if (!eventKey.startsWith('book__')) return false;
  final oldEvent = before[eventKey];
  final newEvent = after[eventKey];
  if (oldEvent is! Map ||
      newEvent is! Map ||
      oldEvent['fields'] is! Map ||
      newEvent['fields'] is! Map) {
    return false;
  }
  if (oldEvent['submitted_at'] != server['updated_at']) return false;
  final oldFields = Map<String, dynamic>.from(oldEvent['fields'] as Map);
  final newFields = Map<String, dynamic>.from(newEvent['fields'] as Map);
  final oldPhoto = oldFields.remove('waybill_photo');
  final newPhoto = newFields.remove('waybill_photo');
  if (oldPhoto is! Map ||
      newPhoto is! Map ||
      oldPhoto['pending_upload'] != true ||
      newPhoto['pending_upload'] != true ||
      '${oldPhoto['pending_upload_id'] ?? ''}'.isEmpty ||
      '${newPhoto['pending_upload_id'] ?? ''}'.isEmpty ||
      oldPhoto['pending_upload_id'] == newPhoto['pending_upload_id'] ||
      oldPhoto['name'] != newPhoto['name'] ||
      oldPhoto['size'] != newPhoto['size'] ||
      oldPhoto['mime_type'] != newPhoto['mime_type'] ||
      !deepBookingCreateValueEqual(oldFields, newFields) ||
      !deepBookingCreateValueEqual(
        {...oldEvent, 'fields': oldFields},
        {...newEvent, 'fields': newFields},
      )) {
    return false;
  }
  final normalized = Map<String, dynamic>.from(pending)
    ..['status_outputs'] = {...after, eventKey: oldEvent};
  return reconcileBookingHistory(
        server,
        normalized,
        baseUpdatedAt: baseUpdatedAt,
        verifiedMake: verifiedMake,
      ) !=
      null;
}

bool deepBookingCreateValueEqual(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every(
          (key) =>
              b.containsKey(key) && deepBookingCreateValueEqual(a[key], b[key]),
        );
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        List.generate(
          a.length,
          (i) => i,
        ).every((i) => deepBookingCreateValueEqual(a[i], b[i]));
  }
  return a == b;
}
