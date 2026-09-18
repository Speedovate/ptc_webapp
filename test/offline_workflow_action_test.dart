import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/status_form.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/repositories/interfaces/booking_repository.dart';
import 'package:webapp/view_models/shared/booking_workflow.vm.dart';
import 'package:webapp/widgets/shared/admin_action_confirmation.dart';

class _Bookings extends Fake implements BookingRepository {
  final attempts = <Booking>[];
  bool fail = true;
  Completer<void>? wait;
  @override
  Future<Booking> saveBooking(Booking booking) async {
    attempts.add(booking);
    await wait?.future;
    if (fail) {
      throw StateError('Local storage unavailable');
    }
    return booking.copyWith(
      localSyncStatus: 'queued',
      pendingActionAt: null,
      pendingBaseUpdatedAt: null,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final role in ['driver', 'helper']) {
    for (final status in ['complete', 'finish', 'delivered']) {
      test(
        '$role $status retains action event and timestamp on failed-save retry',
        () async {
          final repo = _Bookings();
          final vm = BookingWorkflowViewModel(bookingRepository: repo);
          addTearDown(vm.dispose);
          final created = DateTime(2026, 9, 14);
          final base = DateTime(2026, 9, 16);
          vm.user = UserModel(id: '12', role: role);
          vm.booking = Booking(
            id: '84',
            createdAt: created,
            updatedAt: base,
            clientStatus: 'ongoing',
            submissionKey: 'booking_84',
          );
          final form = StatusForm(
            id: 'deliver',
            currentStatusKey: 'ongoing',
            nextStatusKey: status,
            role: role,
          );
          await expectLater(
            vm.submitSpecificForm(form, {'notes': 'offline action'}),
            throwsStateError,
          );
          expect(vm.isSubmitting, false);
          final first = repo.attempts.single;
          repo.fail = false;
          final saved = await vm.submitSpecificForm(form, {
            'notes': 'offline action',
          });
          expect(repo.attempts.last.toMap(), first.toMap());
          expect(saved!.createdAt, created);
          expect(saved.localSyncStatus, 'queued');
          expect(first.pendingBaseUpdatedAt, base);
          expect(first.pendingActionAt, first.updatedAt);
          expect(
            (saved.statusOutputs!.values.single as Map)['submitted_at'],
            first.pendingActionAt!.toIso8601String(),
          );
          if (status == 'delivered') {
            expect(saved.deliveredAt, first.pendingActionAt);
          }
          expect(vm.isSubmitting, false);
        },
      );
    }
  }
  test(
    'double submit shares one workflow action rather than creating another event',
    () async {
      final repo = _Bookings()
        ..fail = false
        ..wait = Completer<void>();
      final vm = BookingWorkflowViewModel(bookingRepository: repo);
      addTearDown(vm.dispose);
      vm.user = const UserModel(id: '12', role: 'driver');
      vm.booking = const Booking(id: '84');
      const form = StatusForm(
        id: '1',
        currentStatusKey: 'ongoing',
        nextStatusKey: 'delivered',
      );
      final first = vm.submitSpecificForm(form, {});
      expect(await vm.submitSpecificForm(form, {}), null);
      repo.wait!.complete();
      await first;
      expect(repo.attempts, hasLength(1));
    },
  );

  testWidgets(
    'failed confirmation displays error and releases loading for retry',
    (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAdminActionConfirmation(
                  context,
                  title: 'Deliver booking',
                  message: 'Confirm delivery',
                  confirmLabel: 'Deliver',
                  onConfirmAsync: () async {
                    attempts++;
                    if (attempts == 1) {
                      throw StateError('Local save failed');
                    }
                    return true;
                  },
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deliver'));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Cancel'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Deliver'))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('Deliver'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
}
