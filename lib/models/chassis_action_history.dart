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
  });
  final List<ChassisActionEvent> events;
  final String? currentLocation;
  final DateTime? deliveredAt;
  final DateTime? claimedAt;
  final bool waiting;

  String locationLabel(ChassisActionEvent event) {
    final recorded = event.location?.trim();
    if (recorded != null && recorded.isNotEmpty) return recorded;
    final current = currentLocation?.trim();
    return current == null || current.isEmpty ? '—' : '$current (current)';
  }

  String? elapsedLabel(DateTime now) {
    final start = deliveredAt;
    if (start == null || (!waiting && claimedAt == null)) return null;
    final elapsed = (claimedAt ?? now).difference(start);
    if (elapsed.isNegative) return 'Timing unavailable';
    final hours = elapsed.inHours;
    final minutes = (elapsed.inMinutes % 60);
    return '${claimedAt == null ? 'Waiting for' : 'Claimed in'} ${hours}h ${minutes}m';
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
    Booking? current;
    for (final booking in bookings) {
      if (booking.id == chassis.bookingReferenceId) current = booking;
      if (booking.chassisId != '${chassis.id}' &&
          booking.id != chassis.bookingReferenceId) {
        continue;
      }
      final bookingEvents = <ChassisActionEvent>[];
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
    return ChassisActionHistory(
      List.unmodifiable(events),
      currentLocation: chassis.location,
      deliveredAt: delivered,
      claimedAt: claimedAt,
      waiting:
          delivered != null &&
          claimedAt == null &&
          ['delivered', 'check', 'empty'].contains(stage),
    );
  }
}
