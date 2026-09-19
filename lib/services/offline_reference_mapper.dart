import 'package:webapp/utils/copy_document_fields.dart';

/// Remaps schema-owned references only. User-entered strings are never IDs.
class OfflineReferenceMapper {
  static bool hasTemporaryReferences(Map<String, dynamic> document) {
    try {
      mapDocument(document, const {});
      return false;
    } on StateError {
      return true;
    }
  }

  static Map<String, dynamic> mapDocument(
    Map<String, dynamic> document,
    Map<String, String> aliases, {
    bool mapId = true,
  }) {
    Object? resolve(Object? value) {
      final id = value?.toString();
      if (id == null) return value;
      final resolved = aliases[id];
      if (resolved != null) {
        return value is int ? int.parse(resolved) : resolved;
      }
      if (id.startsWith('offline_') || ((int.tryParse(id) ?? 0) < 0)) {
        throw StateError(
          'Referenced record is temporarily unavailable. Try again after its create syncs.',
        );
      }
      return value;
    }

    final result = copyDocumentFields(document);
    for (final key in [
      if (mapId) 'id',
      'client_id',
      'parent_client_id',
      'driver_id',
      'helper_id',
      'vehicle_make_id',
      'vehicle_type_id',
      'type_id',
      'chassis_id',
      'current_driver_id',
      'booking_id',
      'current_booking_id',
      'next_booking_id',
      'previous_booking_id',
      'user_id',
      'requester_user_id',
      'requester_parent_client_id',
      'last_sender_user_id',
      'sender_user_id',
    ]) {
      if (result.containsKey(key)) result[key] = resolve(result[key]);
    }
    if (result['field_ids'] is List) {
      result['field_ids'] = (result['field_ids'] as List).map(resolve).toList();
    }
    if (result['field_overrides'] is Map) {
      result['field_overrides'] = (result['field_overrides'] as Map).map(
        (key, value) => MapEntry(resolve(key).toString(), value),
      );
    }
    // These are queue envelopes, not arbitrary nested form answers.
    for (final key in ['chassis', 'document']) {
      if (result[key] is Map) {
        result[key] = mapDocument(
          copyDocumentFields(result[key] as Map),
          aliases,
          mapId: key == 'chassis' ? false : mapId,
        );
      }
    }
    return result;
  }
}
