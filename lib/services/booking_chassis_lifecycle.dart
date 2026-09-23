/// Project the final booking stage onto its chassis. Queued edits can coalesce
/// several transitions, and retries can start at the same stage. Never infer
/// the physical state solely from the immediately preceding server stage.
///
/// Booking status tracks the workflow, while chassis status tracks the physical
/// asset. In particular, `check` is a booking-only status and leaves the
/// chassis `loaded` until staff confirms it is empty.
enum ChassisDriverLink { preserve, clear, deliveryDriver, returnDriver }

class ChassisLifecycleInstruction {
  const ChassisLifecycleInstruction({
    required this.status,
    required this.keepBookingLink,
    required this.driverLink,
    this.location,
  });

  final String status;
  final bool keepBookingLink;
  final ChassisDriverLink driverLink;
  final String? location;
}

ChassisLifecycleInstruction? chassisLifecycleInstruction({
  required String? previousBookingStatus,
  required String? nextBookingStatus,
  required Map<String, dynamic> bookingDocument,
}) {
  final next = nextBookingStatus?.trim().toLowerCase() ?? '';

  return switch (next) {
    'assigned' => const ChassisLifecycleInstruction(
      status: 'ready',
      keepBookingLink: true,
      driverLink: ChassisDriverLink.deliveryDriver,
    ),
    'ongoing' => ChassisLifecycleInstruction(
      status: 'loaded',
      keepBookingLink: true,
      driverLink: ChassisDriverLink.deliveryDriver,
      location: _bookingLocation(bookingDocument, 'origin'),
    ),
    'cancelled' => const ChassisLifecycleInstruction(
      status: 'ready',
      keepBookingLink: false,
      driverLink: ChassisDriverLink.clear,
      location: 'Garage',
    ),
    'delivered' || 'check' => ChassisLifecycleInstruction(
      status: 'loaded',
      keepBookingLink: true,
      driverLink: ChassisDriverLink.clear,
      location: _bookingLocation(bookingDocument, 'destination'),
    ),
    'empty' => ChassisLifecycleInstruction(
      status: 'empty',
      keepBookingLink: true,
      driverLink: ChassisDriverLink.clear,
      location:
          _latestOutputField(bookingDocument, 'chassis_location') ??
          _bookingLocation(bookingDocument, 'destination'),
    ),
    'return' => ChassisLifecycleInstruction(
      status: 'return',
      keepBookingLink: true,
      driverLink: ChassisDriverLink.returnDriver,
      location:
          _latestOutputField(bookingDocument, 'chassis_location') ??
          _bookingLocation(bookingDocument, 'destination'),
    ),
    'confirm' => const ChassisLifecycleInstruction(
      status: 'ready',
      keepBookingLink: false,
      driverLink: ChassisDriverLink.clear,
      location: 'Garage',
    ),
    _ => null,
  };
}

String? chassisReturnDriverId(Map<String, dynamic> bookingDocument) =>
    _latestOutputField(bookingDocument, 'return_driver_id');

String? _latestOutputField(Map<String, dynamic> bookingDocument, String key) {
  final outputs = bookingDocument['status_outputs'];
  if (outputs is! Map) return null;

  Map<String, dynamic>? latest;
  DateTime? latestAt;
  for (final rawSection in outputs.values) {
    if (rawSection is! Map) continue;
    final section = Map<String, dynamic>.from(rawSection);
    final fields = section['fields'];
    if (fields is! Map || !fields.containsKey(key)) continue;
    final submittedAt = DateTime.tryParse(
      section['submitted_at']?.toString() ?? '',
    );
    if (latest == null ||
        (submittedAt != null &&
            (latestAt == null || submittedAt.isAfter(latestAt)))) {
      latest = Map<String, dynamic>.from(fields);
      latestAt = submittedAt;
    }
  }
  final value = latest?[key]?.toString().trim();
  return value == null || value.isEmpty ? null : value;
}

String? _bookingLocation(Map<String, dynamic> document, String key) {
  String? clean(String? value) {
    final text = value
        ?.replaceFirst(RegExp(r'\s*\|\s*(CP|OT)$', caseSensitive: false), '')
        .trim();
    return text == null || text.isEmpty || text == '-' || text == '—'
        ? null
        : text;
  }

  final place = clean(_latestOutputField(document, key));
  final barangay = clean(_latestOutputField(document, '${key}_barangay'));
  if (barangay == null) return place;
  if (place == null || place.toLowerCase() == barangay.toLowerCase()) {
    return barangay;
  }
  return '$barangay, $place';
}

/// Advance reservations live on booking.chassis_id. They do not acquire the
/// physical chassis. Old ready/assigned pointers remain readable and can be
/// replaced when a reserved booking actually starts.
bool isChassisReservation(String? status) =>
    const {'pending', 'assigned'}.contains(status?.trim().toLowerCase());

bool shouldProjectBookingOntoChassis({
  required String bookingId,
  required Map<String, dynamic> booking,
  required Map<String, dynamic> chassis,
  Map<String, dynamic>? ownerBooking,
}) {
  final owner = chassis['current_booking_id']?.toString();
  final status = booking['client_status']?.toString();
  if (isChassisReservation(status)) {
    // Compatibility with existing ready assignments, without displacing one.
    return owner == bookingId && chassis['current_status'] == 'ready';
  }
  final lifecycle = chassisLifecycleInstruction(
    previousBookingStatus: null,
    nextBookingStatus: status,
    bookingDocument: booking,
  );
  if (lifecycle?.keepBookingLink == false && owner != bookingId) return false;
  if (owner == null || owner.isEmpty || owner == bookingId) return true;
  if (chassis['current_status'] == 'ready' &&
      isChassisReservation(ownerBooking?['client_status']?.toString())) {
    return true;
  }
  throw StateError(
    'Sync conflict: chassis is active on another booking. Its advance reservation is preserved; release the active booking before starting this one.',
  );
}

void preserveChassisPhysicalAssignment(
  Map<String, dynamic> document,
  Map<String, dynamic> current,
) {
  for (final key in [
    'current_booking_id',
    'current_driver_id',
    'current_status',
    'location',
  ]) {
    if (current.containsKey(key)) {
      document[key] = current[key];
    } else if (key == 'current_status') {
      document[key] = 'ready';
    } else {
      document.remove(key);
    }
  }
}
