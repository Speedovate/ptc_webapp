import 'package:webapp/utils/location_display.dart';
import 'package:webapp/services/booking_chassis_lifecycle.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/chassis.dart';

class ChassisActionEvent {
  const ChassisActionEvent({
    required this.bookingId,
    required this.stage,
    required this.at,
    this.actor,
    this.actorRole,
    this.driverId,
    this.location,
  });
  final String bookingId;
  final String stage;
  final DateTime at;
  final String? actor;
  final String? actorRole;
  final String? driverId;
  final String? location;

  /// Use the same projection as actual chassis updates, not the booking label.
  String? get chassisStatus => isChassisReservation(stage)
      ? null
      : chassisLifecycleInstruction(
          previousBookingStatus: null,
          nextBookingStatus: stage,
          bookingDocument: const {},
        )?.status;
}

/// Read-only projection of recorded workflow actions; never use sync/update time
/// as a substitute for the time an action occurred.
class ChassisActionHistory {
  ChassisActionHistory(
    this.events, {
    this.deliveredAt,
    this.currentLocation,
    this.claimedAt,
    this.waiting = false,
    this.assignments = const [],
    this.activeBookingId,
  });

  /// All linked bookings, including advance bookings with no workflow actions.
  /// Crew is the saved booking assignment, not a historical crew snapshot.
  final List<Booking> assignments;
  final String? activeBookingId;

  String assignmentLabel(Booking booking) {
    if (isChassisReservation(booking.clientStatus)) return 'Reserved';
    if (booking.id == activeBookingId) return 'Active';
    return 'Historical';
  }

  final List<ChassisActionEvent> events;
  final String? currentLocation;
  final DateTime? deliveredAt;
  final DateTime? claimedAt;
  final bool waiting;

  String locationLabel(ChassisActionEvent event) {
    final recorded = event.location?.trim();
    if (recorded != null && recorded.isNotEmpty) {
      return locationDisplayLabel(recorded);
    }
    final current = currentLocation?.trim();
    return current == null || current.isEmpty
        ? '—'
        : locationDisplayLabel(current);
  }

  String? elapsedLabel(DateTime now) {
    final start = deliveredAt;
    if (start == null || (!waiting && claimedAt == null)) return null;
    final elapsed = (claimedAt ?? now).difference(start);
    if (elapsed.isNegative) return 'Timing unavailable';
    final hours = elapsed.inHours;
    final minutes = (elapsed.inMinutes % 60);
    final duration = hours == 0 ? '${minutes}m' : '${hours}h ${minutes}m';
    return '${claimedAt == null ? 'Waiting for' : 'Claimed in'} $duration';
  }

  String? claimLabel(ChassisActionEvent event) {
    if (event.stage != 'return') return null;
    final delivery = events
        .where(
          (candidate) =>
              candidate.bookingId == event.bookingId &&
              candidate.stage == 'delivered' &&
              !candidate.at.isAfter(event.at),
        )
        .firstOrNull;
    if (delivery == null) return null;
    return ChassisActionHistory(
      const [],
      deliveredAt: delivery.at,
      claimedAt: event.at,
    ).elapsedLabel(event.at);
  }

  factory ChassisActionHistory.fromBookings(
    Chassis chassis,
    Iterable<Booking> bookings,
  ) {
    final events = <ChassisActionEvent>[];
    final assignments = <Booking>[];
    Booking? current;
    for (final booking in bookings) {
      if (booking.id == chassis.bookingReferenceId) current = booking;
      if (booking.chassisId != '${chassis.id}' &&
          booking.id != chassis.bookingReferenceId) {
        continue;
      }
      final bookingEvents = <ChassisActionEvent>[];
      assignments.add(booking);
      for (final raw in booking.statusOutputs?.values ?? const []) {
        if (raw is! Map) continue;
        final at = DateTime.tryParse(raw['submitted_at']?.toString() ?? '');
        final form = raw['status_form'];
        final stage = form is Map
            ? form['next_status_key']?.toString().trim().toLowerCase()
            : null;
        if (at == null || stage == null || stage.isEmpty) continue;
        final fields = raw['fields'];
        bookingEvents.add(
          ChassisActionEvent(
            bookingId: booking.id ?? '-',
            stage: stage,
            at: at,
            actor: raw['submitted_by']?.toString(),
            actorRole: raw['submitted_role']?.toString(),
            driverId: fields is Map
                ? fields['return_driver_id']?.toString()
                : null,
            location: fields is Map
                ? fields['chassis_location']?.toString()
                : null,
          ),
        );
      }
      if (booking.deliveredAt != null &&
          !bookingEvents.any((event) => event.stage == 'delivered')) {
        bookingEvents.add(
          ChassisActionEvent(
            bookingId: booking.id ?? '-',
            stage: 'delivered',
            at: booking.deliveredAt!,
          ),
        );
      }
      events.addAll(bookingEvents);
    }
    events.sort((a, b) => b.at.compareTo(a.at));
    final currentEvents = events
        .where((event) => event.bookingId == chassis.bookingReferenceId)
        .toList();
    final delivered = currentEvents
        .where((event) => event.stage == 'delivered')
        .firstOrNull
        ?.at;
    final claims =
        currentEvents
            .where(
              (event) =>
                  delivered != null &&
                  event.stage == 'return' &&
                  !event.at.isBefore(delivered),
            )
            .map((event) => event.at)
            .toList()
          ..sort();
    final claimedAt = claims.firstOrNull;
    final stage = current?.clientStatus?.trim().toLowerCase();
    var location = chassis.location?.trim();
    if (location == null || location.isEmpty) {
      if (current != null) {
        final instruction = chassisLifecycleInstruction(
          previousBookingStatus: null,
          nextBookingStatus: current.clientStatus,
          bookingDocument: {'status_outputs': current.statusOutputs},
        );
        if (instruction?.status == chassis.currentStatus.trim().toLowerCase()) {
          location = instruction?.location;
        }
      }
      if (location == null || location.isEmpty) {
        // Never imply a loaded/assigned chassis is in Garage just because
        // legacy data has no saved location or booking history is unavailable.
        location =
            events.isEmpty &&
                assignments.isEmpty &&
                chassis.bookingReferenceId == null &&
                chassis.currentStatus.trim().toLowerCase() == Chassis.ready
            ? 'Garage'
            : '—';
      }
    }
    return ChassisActionHistory(
      List.unmodifiable(events),
      assignments: List.unmodifiable(assignments),
      activeBookingId: chassis.bookingReferenceId,
      currentLocation: location,
      deliveredAt: delivered,
      claimedAt: claimedAt,
      waiting:
          delivered != null &&
          claimedAt == null &&
          ['delivered', 'check', 'empty'].contains(stage),
    );
  }
}
