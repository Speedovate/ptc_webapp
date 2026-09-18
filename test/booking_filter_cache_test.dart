import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/view_models/admin/admin_bookings.vm.dart';
import 'package:webapp/view_models/admin/admin_dashboard.vm.dart';

void main() {
  test('booking filters reuse results until data or criteria changes', () {
    AdminBookingsViewModel.clearCachedState();
    final vm = AdminBookingsViewModel();
    addTearDown(vm.dispose);
    vm.ingestSubmittedBooking(const Booking(id: '1'));
    final initial = vm.filteredBookings();
    expect(vm.filteredBookings(), same(initial));
    vm.setSearchQuery('999');
    expect(vm.filteredBookings(), isEmpty);
    vm.ingestSubmittedBooking(const Booking(id: '999'));
    expect(vm.filteredBookings().single.id, '999');
    final updated = vm.filteredBookings();
    expect(vm.filteredBookings(), same(updated));
    vm.clearFilters();
    vm.setSearchQuery('');
    expect(vm.filteredBookings().length, 2);
  });
  test(
    'dashboard result is reused and invalidated by filter and notifications',
    () {
      AdminDashboardViewModel.clearCachedState();
      final vm = AdminDashboardViewModel();
      addTearDown(vm.dispose);
      final initial = vm.filteredCompletedBookings();
      expect(vm.filteredCompletedBookings(), same(initial));
      vm.setSearchQuery('changed');
      final filtered = vm.filteredCompletedBookings();
      expect(filtered, isNot(same(initial)));
      expect(vm.filteredCompletedBookings(), same(filtered));
      vm.notifyListeners();
      expect(vm.filteredCompletedBookings(), isNot(same(filtered)));
    },
  );
}
