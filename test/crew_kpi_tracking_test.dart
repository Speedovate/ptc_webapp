import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/services/kpi/crew_kpi_store.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:webapp/views/shared/crew_kpi_tracking.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/admin_modal_record_list.dart';
import 'package:webapp/widgets/shared/app_page_loading.dart';
import 'package:webapp/widgets/shared/record_text_link.dart';
import 'crew_kpi_store_test.dart' show crewBooking;

class ViewStore extends CrewKpiStore {
  Map<String, dynamic>? snapshot;
  int calls = 0;
  bool fail = false;
  Completer<Map<String, dynamic>?>? waiting;
  @override
  Future<Map<String, dynamic>?> readCached(UserModel user) async => snapshot;
  @override
  Future<Map<String, dynamic>?> load(UserModel user) async {
    calls++;
    if (fail) throw StateError('network failure');
    return waiting?.future ?? snapshot;
  }
}

Map<String, dynamic> sample() => {
  'bookings': [crewBooking('1'), crewBooking('2', driver: '99', helper: '77')],
  'makes': [],
  'records': [],
  'catalog': {},
  'incidents': [],
};
void main() {
  for (final width in [375.0, 1400.0]) {
    testWidgets(
      'personal KPI uses responsive shared rows, filters and day expansion at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = ViewStore()..snapshot = sample();
        String? opened;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CrewKpiTrackingView(
                user: const UserModel(id: '13', role: 'driver', name: 'Mainar'),
                store: store,
                onOpenBooking: (id) => opened = id,
                network: const Stream.empty(),
                bookingChanges: const Stream.empty(),
                allowed: () => true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final filters = tester.widget<AdminListDynamicFiltersPanel>(
          find.byType(AdminListDynamicFiltersPanel),
        );
        (filters.filters.first as AdminListDropdownFilterConfig).onChanged(
          'All Time',
        );
        await tester.pumpAndSettle();
        var list = tester.widget<AdminModalRecordList>(
          find.byType(AdminModalRecordList),
        );
        expect(list.itemCount, 1);
        expect(list.valuesAt(0)[1], '₱555');
        expect(list.showTitlesRow, width >= 900);
        expect(find.text('Mainar'), findsNothing);
        expect(find.text('13 | Mainar'), findsOneWidget);
        expect(find.text('Fuel'), findsNothing);
        expect(find.text('Revenue'), findsNothing);
        expect(find.text('Rules'), findsNothing);
        final action = list.cellBuilder!(0, 5) as AdminListActionButton;
        action.onTap!();
        await tester.pumpAndSettle();
        list = tester.widget<AdminModalRecordList>(
          find.byType(AdminModalRecordList),
        );
        expect(list.itemCount, 3);
        final values = List.generate(list.itemCount, list.valuesAt);
        expect(values.expand((v) => v), contains('Booking 1'));
        final bookingIndex = List.generate(
          list.itemCount,
          (i) => i,
        ).firstWhere((i) => list.valuesAt(i)[0] == 'Booking 1');
        final link = list.cellBuilder!(bookingIndex, 0) as RecordTextLink;
        link.onTap!();
        expect(opened, '1');
        expect(values.expand((v) => v), isNot(contains('Booking 2')));
        expect(store.calls, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'empty, loading, retained cache on error, reconnect and permission revoke',
    (tester) async {
      final network = StreamController<bool>.broadcast();
      final changes = StreamController<void>.broadcast();
      addTearDown(network.close);
      addTearDown(changes.close);
      final store = ViewStore()..waiting = Completer();
      var allowed = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CrewKpiTrackingView(
              user: const UserModel(id: '13', role: 'driver'),
              store: store,
              network: network.stream,
              bookingChanges: changes.stream,
              allowed: () => allowed,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(AppPageLoading), findsOneWidget);
      store.waiting!.complete({'bookings': []});
      store.waiting = null;
      await tester.pumpAndSettle();
      expect(find.text('No delivered trips in this period.'), findsOneWidget);
      final day = kpiDate(DateTime.now());
      store.snapshot = {
        ...sample(),
        'bookings': [crewBooking('1', time: day.toIso8601String())],
      };
      network.add(true);
      await tester.pumpAndSettle();
      expect(find.text('₱555'), findsWidgets);
      store.fail = true;
      changes.add(null);
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('₱555'), findsWidgets);
      expect(find.byType(AppPageLoading), findsNothing);
      store.fail = false;
      network.add(false);
      await tester.pumpAndSettle();
      network.add(true);
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsNothing);
      allowed = false;
      RoleAccessService.instance.setCurrentUser(
        const UserModel(id: '99', role: 'client'),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('You do not have access to KPI Tracking.'),
        findsOneWidget,
      );
      expect(find.text('₱555'), findsNothing);
      final calls = store.calls;
      await tester.pumpWidget(const SizedBox());
      network.add(true);
      changes.add(null);
      await tester.pump();
      expect(store.calls, calls);
      expect(tester.takeException(), isNull);
    },
  );
}
