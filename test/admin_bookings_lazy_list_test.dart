import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/views/admin/admin_bookings.dart';

void main() {
  for (final width in [400.0, 2400.0]) {
    testWidgets(
      'bookings at width $width build only visible rows and remain scrollable',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final bookings = List.generate(1000, (i) => Booking(id: '${i + 1}'));
        String? opened;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CustomScrollView(
                slivers: [
                  AdminBookingsListSliver(
                    bookings: bookings,
                    availableWidth: width,
                    statusLabelFor: (_) => 'Pending',
                    onView: (booking) => opened = booking.id,
                  ),
                ],
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('1000'), findsNothing);
        expect(find.byType(Text).evaluate().length, lessThan(300));
        final viewAction = find.byIcon(Icons.visibility_rounded);
        expect(viewAction, findsWidgets);
        await tester.tap(viewAction.first);
        expect(opened, '1');
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -650));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(Text).evaluate().length, lessThan(300));
        final scroll = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        expect(scroll.position.pixels, greaterThan(0));
      },
    );
  }
}
