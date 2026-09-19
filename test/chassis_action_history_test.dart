import 'package:flutter/material.dart';
import 'package:webapp/widgets/shared/app_modal_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/widgets/shared/chassis_status_presentation.dart';
import 'package:webapp/models/chassis.dart';
import 'package:webapp/models/chassis_action_history.dart';
import 'package:webapp/widgets/shared/chassis_action_history_dialog.dart';

const chassis = Chassis(
  id: 3,
  name: 'Trailer 3',
  isActive: true,
  currentStatus: 'loaded',
  currentBookingId: 10,
);
final delivered = DateTime.utc(2026, 9, 19, 1);
Map<String, dynamic> action(String stage, DateTime at) => {
  'submitted_at': at.toIso8601String(),
  'submitted_by': '7',
  'submitted_role': 'driver',
  'status_form': {'next_status_key': stage},
  'fields': {'return_driver_id': '8', 'chassis_location': 'Depot'},
};
Booking booking(String stage, {DateTime? claim}) => Booking(
  id: '10',
  chassisId: '3',
  clientStatus: stage,
  deliveredAt: delivered,
  updatedAt: DateTime.utc(2026, 9, 20),
  statusOutputs: {
    'delivery': action('delivered', delivered),
    if (claim != null) 'return': action('return', claim),
  },
);
void main() {
  test('history uses the same chassis status mapping as lifecycle writes', () {
    final expected = {
      'assigned': 'ready',
      'ongoing': 'loaded',
      'delivered': 'loaded',
      'check': 'loaded',
      'empty': 'empty',
      'return': 'return',
      'confirm': 'ready',
      'cancelled': 'ready',
      'pending': null,
    };
    for (final entry in expected.entries) {
      expect(
        ChassisActionEvent(
          bookingId: '7',
          stage: entry.key,
          at: DateTime(2026),
        ).chassisStatus,
        entry.value,
      );
    }
  });
  test('duration omits zero hours but retains hour and day durations', () {
    final start = DateTime.utc(2026);
    final history = ChassisActionHistory([], deliveredAt: start, waiting: true);
    expect(history.elapsedLabel(start), 'Waiting for 0m');
    expect(
      history.elapsedLabel(start.add(const Duration(minutes: 59))),
      'Waiting for 59m',
    );
    expect(
      history.elapsedLabel(start.add(const Duration(hours: 1))),
      'Waiting for 1h 0m',
    );
  });

  for (final stage in ['delivered', 'check', 'empty']) {
    test('$stage waits from actual delivery time, not sync time', () {
      final history = ChassisActionHistory.fromBookings(chassis, [
        booking(stage),
      ]);
      expect(
        history.elapsedLabel(
          delivered.add(const Duration(hours: 2, minutes: 3, seconds: 4)),
        ),
        'Waiting for 2h 3m',
      );
      expect(history.waiting, isTrue);
    });
  }
  test('claim freezes duration and unrelated booking does not affect it', () {
    final history = ChassisActionHistory.fromBookings(chassis, [
      booking('return', claim: delivered.add(const Duration(minutes: 5))),
      Booking(id: '99', chassisId: '9', deliveredAt: delivered),
    ]);
    expect(
      history.elapsedLabel(delivered.add(const Duration(days: 3))),
      'Claimed in 5m',
    );
    expect(history.waiting, isFalse);
    expect(history.events, hasLength(2));
  });
  test(
    'released chassis retains recorded history without showing a live wait',
    () {
      final history = ChassisActionHistory.fromBookings(
        chassis.copyWith(clearCurrentBookingId: true),
        [booking('confirm', claim: delivered.add(const Duration(minutes: 5)))],
      );
      expect(history.events, hasLength(2));
      expect(history.elapsedLabel(DateTime.now()), isNull);
    },
  );
  test(
    'current location is labeled as fallback without replacing recorded location',
    () {
      final history = ChassisActionHistory.fromBookings(
        chassis.copyWith(location: 'garage'),
        [booking('delivered')],
      );
      expect(history.locationLabel(history.events.single), 'Depot');
      final legacy = ChassisActionHistory.fromBookings(
        chassis.copyWith(location: 'garage'),
        [
          Booking(
            id: '10',
            chassisId: '3',
            clientStatus: 'delivered',
            deliveredAt: delivered,
          ),
        ],
      );
      expect(legacy.locationLabel(legacy.events.single), 'garage (current)');
      expect(legacy.events.single.location, isNull);
    },
  );
  test('missing legacy timestamp does not fabricate a waiting duration', () {
    final history = ChassisActionHistory.fromBookings(chassis, [
      const Booking(id: '10', chassisId: '3', clientStatus: 'delivered'),
    ]);
    expect(history.elapsedLabel(DateTime.now()), isNull);
    expect(history.events, isEmpty);
  });
  test('hours exceed 24 and future dates cannot produce negative timers', () {
    final history = ChassisActionHistory.fromBookings(chassis, [
      booking('delivered'),
    ]);
    expect(
      history.elapsedLabel(delivered.add(const Duration(hours: 26))),
      'Waiting for 26h 0m',
    );
    expect(
      history.elapsedLabel(delivered.subtract(const Duration(seconds: 1))),
      'Timing unavailable',
    );
  });
  testWidgets('tapping outside chassis history dismisses the modal', (
    tester,
  ) async {
    final clock = ValueNotifier(DateTime.now());
    addTearDown(clock.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showAppDialog<void>(
                context: context,
                wrapInSelectionArea: false,
                builder: (_) => ChassisActionHistoryDialog(
                  name: '20-14',
                  history: ChassisActionHistory([]),
                  clock: clock,
                ),
              ),
              child: const Text('Open history'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open history'));
    await tester.pumpAndSettle();
    expect(find.text('Chassis 20-14 History'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Chassis 20-14 History'), findsNothing);
  });
  for (final width in [400.0, 1200.0]) {
    testWidgets('history dialog is selectable and fits width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final clock = ValueNotifier(delivered.add(const Duration(minutes: 1)));
      addTearDown(clock.dispose);
      final history = ChassisActionHistory.fromBookings(chassis, [
        booking('delivered'),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChassisActionHistoryDialog(
              name: 'Trailer 3',
              usersById: const {
                '7': UserModel(id: '7', role: 'admin', name: 'Juan Dela Cruz'),
              },
              history: history,
              clock: clock,
            ),
          ),
        ),
      );
      expect(find.byType(SelectionArea), findsWidgets);
      expect(find.text('Location'), findsWidgets);
      expect(find.text('Depot'), findsOneWidget);
      expect(find.byType(ChassisStatusPill), findsOneWidget);
      expect(
        find.textContaining('Delivered\nDriver 7 | Juan Dela Cruz'),
        findsOneWidget,
      );
      expect(find.textContaining('By user #'), findsNothing);
      expect(find.text('Waiting for 1m'), findsOneWidget);
      clock.value = clock.value.add(const Duration(minutes: 1));
      await tester.pump();
      expect(find.text('Waiting for 2m'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
