import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/view_models/admin/admin_dashboard.vm.dart';

void main() {
  const moreta = UserModel(id: 'moreta', name: 'MORETA SHIPPING LINES');
  const other = UserModel(id: 'other', name: 'OTHER SHIPPING LINES');
  const bookings = [
    Booking(id: '1', client: moreta),
    Booking(id: '2', client: other),
    Booking(id: '3', client: moreta),
    Booking(id: '4'),
  ];

  test(
    'main client choices are unique and sorted, including offline snapshots',
    () {
      final vm = AdminDashboardViewModel();
      addTearDown(vm.dispose);
      expect(vm.exportMainClients(bookings).map((client) => client.id), [
        'moreta',
        'other',
      ]);
    },
  );

  test(
    'export is limited to the selected main client, using IDs not names',
    () {
      expect(
        AdminDashboardViewModel.exportBookingsForClient(
          bookings,
          'moreta',
        ).map((booking) => booking.id),
        ['1', '3'],
      );
      expect(
        AdminDashboardViewModel.exportBookingsForClient(
          bookings,
          'other',
        ).map((booking) => booking.id),
        ['2'],
      );
      expect(
        AdminDashboardViewModel.exportBookingsForClient(bookings, null),
        isEmpty,
      );
      expect(
        AdminDashboardViewModel.exportBookingsForClient(bookings, 'missing'),
        isEmpty,
      );
      expect(
        AdminDashboardViewModel.exportBookingsForClient([
          const Booking(
            id: '5',
            client: UserModel(id: 'another-id', name: 'MORETA SHIPPING LINES'),
          ),
          ...bookings,
        ], 'moreta').map((booking) => booking.id),
        ['1', '3'],
      );
    },
  );

  test('export uses latest trip representative with its route', () {
    final booking = Booking(
      statusOutputs: {
        'pending': {
          'submitted_at': '2026-10-06T08:00:00Z',
          'fields': {
            'representative_name': 'Old sub-client',
            'origin': 'Bagong Pag-asa',
            'destination': 'San Manuel',
          },
        },
        'delivered__edit': {
          'submitted_at': '2026-10-29T08:00:00Z',
          'fields': {'representative_name': 'Updated sub-client'},
        },
      },
    );
    expect(
      AdminDashboardViewModel.exportTripClient(booking),
      'UPDATED SUB-CLIENT (BAGONG PAG-ASA - SAN MANUEL)',
    );
  });

  test('missing trip representative does not substitute main client', () {
    expect(
      AdminDashboardViewModel.exportTripClient(const Booking()),
      '- (- - -)',
    );
  });
}
