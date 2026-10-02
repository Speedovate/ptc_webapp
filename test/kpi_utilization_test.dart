import 'package:flutter/material.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/services/investor_reporting_scope.dart';
import 'package:webapp/services/kpi/kpi_utilization.dart';
import 'package:webapp/views/admin/kpi_utilization_view.dart';
import 'package:webapp/widgets/shared/admin_modal_record_list.dart';

final make = VehicleMake(id: '1', code: 'PM1');
Booking trip(
  String id,
  int day, {
  String status = 'delivered',
  String pm = '1',
}) => Booking(
  id: id,
  submissionKey: 'key$id',
  clientStatus: status,
  vehicleMake: VehicleMake(id: pm),
  deliveredAt: DateTime.utc(2026, 9, day, 4),
);
void main() {
  testWidgets(
    'Total includes every matching PM across pages and display modes',
    (tester) async {
      final makes = [
        for (var i = 1; i <= 16; i++) VehicleMake(id: '$i', code: 'Truck-$i'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KpiUtilizationView(
              selectedMonth: DateTime.utc(2026, 9),
              makes: makes,
              bookings: [for (var i = 1; i <= 16; i++) trip('$i', 1, pm: '$i')],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final mode in ['Daily', 'Weekly', 'Monthly']) {
        final filters = tester.widget<AdminListDynamicFiltersPanel>(
          find.byType(AdminListDynamicFiltersPanel),
        );
        (filters.filters.first as AdminListDropdownFilterConfig).onChanged(
          mode,
        );
        await tester.pumpAndSettle();
        final table = tester.widget<AdminModalRecordList>(
          find.byType(AdminModalRecordList),
        );
        expect(table.itemCount, 16); // Total plus 15 initially visible trucks.
        final total = table.valuesAt(0);
        expect(total.first, 'Total');
        expect(total.last, '16');
        expect(
          total[total.length - 2],
          mode == 'Monthly' ? '16/365' : '16/30',
        );
        expect(total[mode == 'Monthly' ? 9 : 1], '16');
        expect(table.valuesAt(1).first, 'Truck-1');
      }
      tester
          .widget<AdminListSearchField>(find.byType(AdminListSearchField))
          .onChanged('Truck-16');
      await tester.pumpAndSettle();
      final filtered = tester.widget<AdminModalRecordList>(
        find.byType(AdminModalRecordList),
      );
      expect(filtered.itemCount, 2);
      expect(filtered.valuesAt(0).last, '1');
      expect(filtered.valuesAt(0)[13], '1/365');
      await tester.tap(find.text('Total'));
      await tester.pumpAndSettle();
      expect(find.text('Total Trips · 2026'), findsOneWidget);
      final trips = tester
          .widgetList<AdminModalRecordList>(find.byType(AdminModalRecordList))
          .last;
      expect(trips.itemCount, 1);
      expect(trips.valuesAt(0).first, 'Booking 16');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shared month survives view switches and updates in both directions',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var month = DateTime.utc(2026, 9);
      var utilization = true;
      late StateSetter update;
      var notifications = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Scaffold(
                body: utilization
                    ? KpiUtilizationView(
                        makes: [make],
                        bookings: [trip('1', 1)],
                        selectedMonth: month,
                        onMonthChanged: (value) => setState(() {
                          month = value;
                          notifications++;
                        }),
                      )
                    : Text('Overview: ${month.year}-${month.month}'),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Daily · September 2026'), findsOneWidget);
      final filters = tester.widget<AdminListDynamicFiltersPanel>(
        find.byType(AdminListDynamicFiltersPanel),
      );
      filters.filters
          .whereType<AdminListDropdownFilterConfig>()
          .firstWhere((f) => f.label == 'Month')
          .onChanged('8');
      await tester.pumpAndSettle();
      expect(month.month, 8);
      expect(notifications, 1);
      update(() => utilization = false);
      await tester.pumpAndSettle();
      expect(find.text('Overview: 2026-8'), findsOneWidget);
      update(() {
        month = DateTime.utc(2027, 2);
        utilization = true;
      });
      await tester.pumpAndSettle();
      expect(find.text('Daily · February 2027'), findsOneWidget);
      update(() => month = DateTime.utc(2026, 9));
      await tester.pumpAndSettle();
      expect(find.text('Daily · September 2026'), findsOneWidget);
      expect(
        notifications,
        1,
        reason: 'Parent updates must not trigger callback loops',
      );
    },
  );

  test(
    'daily weekly monthly count unique delivered-onwards trips in Philippine time',
    () {
      final bookings = [
        trip('1', 1),
        trip('1', 1),
        trip('2', 7),
        trip('3', 8),
        trip('4', 14),
        trip('5', 15),
        trip('6', 21),
        trip('7', 22),
        trip('8', 30, status: 'empty'),
        trip('9', 9, status: 'pending'),
        trip('10', 9, status: 'cancelled'),
        Booking(
          id: '11',
          vehicleMake: VehicleMake(id: '1'),
          clientStatus: 'delivered',
          deliveredAt: DateTime.utc(2026, 8, 31, 16),
        ),
        Booking(
          id: '12',
          vehicleMake: VehicleMake(id: '1'),
          clientStatus: 'delivered',
          deliveredAt: DateTime.utc(2026, 9, 30, 16),
        ),
      ];
      KpiUtilization calculate(KpiUtilizationMode mode) =>
          KpiUtilization.calculate(
            bookings: bookings,
            makes: [make],
            mode: mode,
            year: 2026,
            month: 9,
          );
      final daily = calculate(KpiUtilizationMode.daily);
      expect(daily.columns, 30);
      expect(daily.counts['1']![0], 2);
      expect(daily.counts['1']!.reduce((a, b) => a + b), 9);
      expect(daily.totalDays['1'], 8);
      expect(calculate(KpiUtilizationMode.weekly).totalDays['1'], 8);
      expect(calculate(KpiUtilizationMode.weekly).counts['1'], [3, 2, 2, 2]);
      final monthly = calculate(KpiUtilizationMode.monthly);
      expect(monthly.counts['1']![8], 9);
      expect(monthly.counts['1']![9], 1);
      expect(monthly.totalDays['1'], 9);
    },
  );
  test('missing dates are not guessed and leap month has 29 days', () {
    final result = KpiUtilization.calculate(
      bookings: [
        Booking(
          id: '1',
          vehicleMake: VehicleMake(id: '1'),
          clientStatus: 'delivered',
        ),
      ],
      makes: [make],
      mode: KpiUtilizationMode.daily,
      year: 2024,
      month: 2,
    );
    expect(result.columns, 29);
    expect(result.unresolved, 1);
    expect(result.counts['1']!.every((v) => v == 0), true);
  });
  test(
    'investor scoped input excludes other investors crew even on same truck',
    () {
      const own = UserModel(id: '13', role: 'driver', parentClientId: '9');
      const other = UserModel(id: '14', role: 'driver', parentClientId: '10');
      final scope = InvestorReportingScope(
        const UserModel(id: '9', role: 'investor'),
        [own, other],
      );
      final makes = [
        VehicleMake(id: '1', code: 'PM1', driver: own),
        VehicleMake(id: '2', code: 'PM2', driver: other),
      ];
      final bookings = [
        for (final user in [own, other])
          Booking(
            id: user.id,
            vehicleMake: VehicleMake(id: '1'),
            driver: user,
            clientStatus: 'delivered',
            deliveredAt: DateTime.utc(2026, 9, 1),
          ),
      ];
      final result = KpiUtilization.calculate(
        bookings: bookings.where(scope.booking).toList(),
        makes: makes.where(scope.make).toList(),
        mode: KpiUtilizationMode.weekly,
        year: 2026,
        month: 9,
      );
      expect(result.counts.keys, ['1']);
      expect(result.counts['1'], [1, 0, 0, 0]);
    },
  );
  testWidgets('utilized counts open only their matching trips', (tester) async {
    Booking? openedBooking;
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final booking = Booking(
      id: '701',
      submissionKey: 'unique701',
      clientStatus: 'delivered',
      vehicleMake: make,
      deliveredAt: DateTime.utc(now.year, now.month, 1, 4),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KpiUtilizationView(
            makes: [make],
            onOpenBooking: (booking) => openedBooking = booking,
            bookings: [
              booking,
              booking,
              Booking(
                id: '702',
                clientStatus: 'pending',
                vehicleMake: make,
                deliveredAt: booking.deliveredAt,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final mode in ['Daily', 'Weekly', 'Monthly']) {
      final filters = tester.widget<AdminListDynamicFiltersPanel>(
        find.byType(AdminListDynamicFiltersPanel),
      );
      (filters.filters.first as AdminListDropdownFilterConfig).onChanged(mode);
      await tester.pumpAndSettle();
      final badge = find.byIcon(Icons.check_circle);
      await Scrollable.ensureVisible(tester.element(badge), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(badge);
      await tester.pumpAndSettle();
      expect(find.text('Booking 701'), findsOneWidget, reason: mode);
      expect(find.text('Booking 702'), findsNothing);
      expect(tester.takeException(), isNull);
      expect(find.text('Actions'), findsWidgets);
      final action = find.byTooltip('View booking');
      expect(action, findsOneWidget);
      if (mode == 'Monthly') {
        await Scrollable.ensureVisible(tester.element(action), alignment: 0.5);
        await tester.pumpAndSettle();
        await tester.tap(action);
      } else {
        await tester.tap(find.text('Close'));
      }
      await tester.pumpAndSettle();
    }
    expect(openedBooking?.id, '701');
    expect(find.text('Close'), findsNothing);
  });
  for (final width in [375.0, 1400.0]) {
    testWidgets('utilization filters and horizontal table at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KpiUtilizationView(makes: [make], bookings: const []),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      var table = tester.widget<AdminModalRecordList>(
        find.byType(AdminModalRecordList),
      );
      expect(table.titles.first, 'PM');
      expect(table.valuesAt(0).last, '0');
      final horizontal = find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      );
      if (horizontal.evaluate().isNotEmpty) {
        final icon = find.byIcon(Icons.bar_chart_rounded);
        final name = find.text(make.code!);
        final iconBefore = tester.getTopLeft(icon);
        final nameBefore = tester.getTopLeft(name);
        await tester.drag(horizontal.first, const Offset(-300, 0));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(icon).dx, closeTo(iconBefore.dx, 0.1));
        expect(tester.getTopLeft(name).dx, closeTo(nameBefore.dx, 0.1));
        expect(tester.takeException(), isNull);
      }

      for (final mode in ['Weekly', 'Monthly', 'Daily']) {
        final filters = tester.widget<AdminListDynamicFiltersPanel>(
          find.byType(AdminListDynamicFiltersPanel),
        );
        (filters.filters.first as AdminListDropdownFilterConfig).onChanged(
          mode,
        );
        await tester.pumpAndSettle();
        table = tester.widget<AdminModalRecordList>(
          find.byType(AdminModalRecordList),
        );
        if (mode == 'Weekly') {
          expect(table.titles, [
            'PM',
            'Week 1',
            'Week 2',
            'Week 3',
            'Week 4',
            'Total Days',
            'Total Trips',
          ]);
        }
        if (mode == 'Monthly') {
          expect(table.titles.length, 15);
        }
        expect(tester.takeException(), isNull);
      }
    });
  }
}
