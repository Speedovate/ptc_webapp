import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/widgets/shared/app_mouse_pressable.dart';
import 'package:webapp/view_models/admin/admin_dashboard.vm.dart';
import 'package:webapp/views/admin/admin_dashboard.dart';
import 'package:webapp/widgets/shared/lazy_data_scroll_view.dart';

void main() {
  for (final width in [400.0, 2400.0]) {
    testWidgets(
      'completed dashboard bookings at $width are lazy and actions work',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final vm = AdminDashboardViewModel();
        addTearDown(vm.dispose);
        final bookings = List.generate(1000, (i) => Booking(id: '$i'));
        String? opened;
        String? toggled;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LazyDataScrollView(
                child: AdminDashboardCompletedBookingsSliver(
                  bookings: bookings,
                  vm: vm,
                  onView: (b) => opened = b.id,
                  onToggleBillingStatus: (b) => toggled = b.id,
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(Text).evaluate().length, lessThan(350));
        await tester.tap(find.byIcon(Icons.visibility_rounded).first);
        expect(opened, '0');
        await tester.tap(find.byIcon(Icons.check_rounded).first);
        expect(toggled, '0');
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(Text).evaluate().length, lessThan(350));
      },
    );
  }
  testWidgets('export list is bounded, lazy and keeps exclusion callbacks', (
    tester,
  ) async {
    final vm = AdminDashboardViewModel();
    addTearDown(vm.dispose);
    String? excluded;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                const TextField(),
                DashboardExportCandidateList(
                  title: 'Candidates',
                  bookings: List.generate(1000, (i) => Booking(id: '$i')),
                  vm: vm,
                  excludedBookingIds: const {},
                  onToggleExcluded: (b) => excluded = b.id,
                ),
                const TextField(),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      find.byType(AppMousePressable).evaluate().length,
      inExclusiveRange(0, 30),
    );
    await tester.tap(find.byType(AppMousePressable).first);
    expect(excluded, '0');
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.byType(AppMousePressable).evaluate().length,
      inExclusiveRange(0, 30),
    );
  });
}
