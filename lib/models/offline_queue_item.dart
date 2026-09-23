/// Read-only presentation of a persisted action; excludes payloads and media bytes.
class OfflineQueueItem {
  const OfflineQueueItem({
    required this.title,
    required this.recordLabel,
    required this.createdAt,
    this.conflictId,
    this.collectionKey,
    this.hasError = false,
    this.isBlocked = false,
    this.errorMessage,
    this.diagnostics,
    this.nextRetryAt,
  });
  final String? conflictId;
  final String? collectionKey;
  final String title;
  final String recordLabel;
  final DateTime? createdAt;
  final bool hasError;
  final bool isBlocked;
  final String? errorMessage;
  final String? diagnostics;
  final DateTime? nextRetryAt;

  String get statusLabel => isBlocked
      ? 'Needs review'
      : hasError
      ? 'Waiting to retry'
      : 'Saved on this device · Waiting to sync';

  static String record(String collection, String id) {
    final label = switch (collection) {
      'bookings' => 'Booking',
      'users' => 'User',
      'chassis' => 'Chassis',
      'vehicle_makes' => 'Vehicle make',
      'pm_kpi_records' => 'PM KPI',
      'pm_fuel_entries' => 'Fuel entry',
      'operations_catalog' => 'Locations and trip-share matrix',
      'vehicle_types' => 'Vehicle type',
      'vehicle_sizes' => 'Vehicle size',
      'status_forms' => 'Flow form',
      'status_fields' => 'Flow field',
      'statuses' => 'Status',
      'role_access' => 'Role permission',
      _ => 'Record',
    };
    if (id.startsWith('offline_') || id.startsWith('-')) {
      return 'New ${label.toLowerCase()} · ID pending sync';
    }
    if (id.isEmpty) return label;
    return collection == 'bookings' ? '$label $id' : '$label #$id';
  }

  static String action(String kind) => switch (kind) {
    'bookingCreate' => 'Create booking',
    'userUpsert' => 'Save user profile',
    'userDelete' => 'Remove user',
    'bookingBillingStatusUpdate' => 'Update booking billing',
    'supportThreadReadMarkerUpsert' => 'Mark support conversation read',
    'chassisAssignment' => 'Save chassis assignment',
    'chassisDelete' => 'Remove chassis',
    'collectionDocumentCreate' => 'Create record',
    'collectionDocumentDelete' => 'Remove record',
    _ => 'Save record changes',
  };
}
