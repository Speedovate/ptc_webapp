import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/services/kpi/crew_kpi_store.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:webapp/views/shared/crew_kpi_tracking.dart';

/// A store whose durable read never completes, standing in for a slow or
/// unavailable cache. The screen must still paint from memory.
class _StalledStore extends CrewKpiStore {
  _StalledStore(this.snapshot);

  final Map<String, dynamic> snapshot;

  @override
  Future<Map<String, dynamic>?> readCached(UserModel user) =>
      Completer<Map<String, dynamic>?>().future;

  @override
  Future<Map<String, dynamic>?> load(UserModel user) =>
      Completer<Map<String, dynamic>?>().future;
}

Map<String, dynamic> _snapshot(String driverId) {
  final now = DateTime.now();
  final stamp = DateTime.utc(now.year, now.month, now.day, 3);
  return {
    'records': [
      {
        'day': kpiDayKey(kpiDate(stamp)),
        'type': 'Share',
        'amount': 150,
        'booking_id': 'booking-1',
        'label': 'Booking 1',
        'created_at': stamp.toIso8601String(),
      },
    ],
    'incidents': <Map<String, dynamic>>[],
    'makes': <Map<String, dynamic>>[],
    'fuel': <Map<String, dynamic>>[],
    'bookings': [
      {
        'id': 'booking-1',
        'driver_id': driverId,
        'client_status': 'delivered',
        'created_at': stamp.toIso8601String(),
        'delivered_at': stamp.toIso8601String(),
      },
      {
        'id': 'booking-2',
        'driver_id': driverId,
        'client_status': 'ongoing',
        'created_at': stamp.toIso8601String(),
      },
    ],
    'catalog': <String, dynamic>{},
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    RoleAccessService.instance.setCurrentUser(null);
    CrewKpiStore.forgetAll();
  });

  testWidgets('KPI tracking paints its numbers without waiting for a read', (
    tester,
  ) async {
    final driver = const UserModel(id: '12', name: 'Driver 12', role: 'driver');
    RoleAccessService.instance.setCurrentUser(driver);
    // What the device already holds from a previous visit.
    CrewKpiStore.remember(driver, _snapshot('12'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CrewKpiTrackingView(
            user: driver,
            store: _StalledStore(_snapshot('12')),
            bookingChanges: const Stream<void>.empty(),
            network: const Stream<bool>.empty(),
          ),
        ),
      ),
    );
    // A single frame: nothing has been awaited yet.
    await tester.pump();

    expect(
      find.text('Loading KPI ...'),
      findsNothing,
      reason: 'the screen already had the numbers and must not show a spinner',
    );
    expect(
      find.text('1/2'),
      findsOneWidget,
      reason: 'delivered out of assigned',
    );

    // Let the stalled read time out so the test ends with no pending timers.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  test('peek only returns a snapshot the store itself recorded', () {
    const driver = UserModel(id: '13', name: 'Driver 13', role: 'driver');
    expect(CrewKpiStore.peek(driver), isNull);
    CrewKpiStore.remember(driver, _snapshot('13'));
    expect(CrewKpiStore.peek(driver), isNotNull);
    CrewKpiStore.forgetAll();
    expect(
      CrewKpiStore.peek(driver),
      isNull,
      reason: 'signing out must not leave numbers behind in memory',
    );
  });
}
