import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/repositories/interfaces/booking_repository.dart';
import 'package:webapp/repositories/interfaces/status_form_repository.dart';
import 'package:webapp/view_models/client/client_booking_history.vm.dart';

class _Auth extends Fake implements AuthRepository {}

class _Bookings extends Fake implements BookingRepository {}

class _Statuses extends Fake implements StatusFormRepository {}

void main() {
  test(
    'crew history sorts all pickup dates ascending; client order stays unchanged',
    () {
      final vm = ClientBookingHistoryViewModel(
        authRepository: _Auth(),
        bookingRepository: _Bookings(),
        statusRepository: _Statuses(),
      );
      addTearDown(vm.dispose);
      Booking entry(String id, String day, String time) => Booking(
        id: id,
        statusOutputs: {
          'pending': {
            'fields': {'pick_up_date': day, 'pick_up_time': time},
          },
        },
      );
      vm.bookings = [
        entry('late', '2026-09-21', '09:00'),
        const Booking(id: 'unknown'),
        entry('pm', '2026-09-20', '2:00 PM'),
        entry('early', '2026-09-19', '10:00'),
        entry('am', '2026-09-20', '08:00'),
      ];
      for (final role in ['driver', 'helper']) {
        expect(vm.filteredBookings(role: role).map((b) => b.id), [
          'early',
          'am',
          'pm',
          'late',
          'unknown',
        ]);
      }
      expect(vm.filteredBookings(role: 'client').map((b) => b.id), [
        'late',
        'unknown',
        'pm',
        'early',
        'am',
      ]);
    },
  );
}
