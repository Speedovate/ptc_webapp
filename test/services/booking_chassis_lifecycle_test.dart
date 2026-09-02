import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/booking_chassis_lifecycle.dart';

void main() {
  test('check remains booking-only while the chassis stays loaded', () {
    final instruction = chassisLifecycleInstruction(
      previousBookingStatus: 'delivered',
      nextBookingStatus: 'check',
      bookingDocument: const {},
    );

    expect(instruction, isNull);
  });

  test('applies the agreed physical chassis lifecycle', () {
    final assigned = chassisLifecycleInstruction(
      previousBookingStatus: 'pending',
      nextBookingStatus: 'assigned',
      bookingDocument: const {},
    );
    final ongoing = chassisLifecycleInstruction(
      previousBookingStatus: 'assigned',
      nextBookingStatus: 'ongoing',
      bookingDocument: const {},
    );
    final empty = chassisLifecycleInstruction(
      previousBookingStatus: 'check',
      nextBookingStatus: 'empty',
      bookingDocument: const {},
    );
    final returning = chassisLifecycleInstruction(
      previousBookingStatus: 'empty',
      nextBookingStatus: 'return',
      bookingDocument: const {},
    );
    final confirmed = chassisLifecycleInstruction(
      previousBookingStatus: 'return',
      nextBookingStatus: 'confirm',
      bookingDocument: const {},
    );

    expect(assigned?.status, 'ready');
    expect(ongoing?.status, 'loaded');
    expect(empty?.status, 'empty');
    expect(returning?.status, 'return');
    expect(confirmed?.status, 'ready');
    expect(confirmed?.keepBookingLink, isFalse);
  });
}
