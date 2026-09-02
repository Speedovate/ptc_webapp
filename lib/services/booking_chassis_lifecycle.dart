/// Shared interpretation of booking workflow transitions that affect a chassis.
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
  final previous = previousBookingStatus?.trim().toLowerCase() ?? '';
  final next = nextBookingStatus?.trim().toLowerCase() ?? '';
  final transition = '$previous->$next';

  return switch (transition) {
    'pending->assigned' => const ChassisLifecycleInstruction(
      status: 'ready',
      keepBookingLink: true,
      driverLink: ChassisDriverLink.deliveryDriver,
    ),
    'assigned->ongoing' => const ChassisLifecycleInstruction(
      status: 'loaded',
      keepBookingLink: true,
      driverLink: ChassisDriverLink.deliveryDriver,
    ),
    'assigned->cancelled' => const ChassisLifecycleInstruction(
      status: 'ready',
      keepBookingLink: false,
      driverLink: ChassisDriverLink.clear,
    ),
    'ongoing->delivered' => const ChassisLifecycleInstruction(
      status: 'loaded',
      keepBookingLink: true,
      driverLink: ChassisDriverLink.clear,
    ),
    // `check` is intentionally omitted: it is a booking-only state.
    'check->empty' => ChassisLifecycleInstruction(
      status: 'empty',
      keepBookingLink: true,
      driverLink: ChassisDriverLink.clear,
      location: _latestOutputField(bookingDocument, 'chassis_location'),
    ),
    'empty->return' => const ChassisLifecycleInstruction(
      status: 'return',
      keepBookingLink: true,
      driverLink: ChassisDriverLink.returnDriver,
    ),
    'return->confirm' => const ChassisLifecycleInstruction(
      status: 'ready',
      keepBookingLink: false,
      driverLink: ChassisDriverLink.clear,
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
