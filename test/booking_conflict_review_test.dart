import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/booking_id_resolver.dart';
import 'package:webapp/services/booking_conflict_review_service.dart';
import 'package:webapp/view_models/admin/booking_conflict_review.vm.dart';
import 'package:webapp/views/admin/booking_conflict_review_dialog.dart';

const key = 'booking_8_9_1_1789534355769000';
final temp = BookingIdResolver.temporaryId(key);
Map<String, dynamic> numeric() => {
  'id': '84',
  'submission_key': key,
  'created_at': '2026-09-16T12:52:35',
  'updated_at': 'old',
  'client_status': 'assigned',
  'driver_status': 'assigned',
  'helper_status': 'assigned',
  'chassis_id': '7',
  'driver_id': '13',
  'status_outputs': {
    'assign': {
      'fields': {'chassis_id': '7'},
    },
  },
};
Future<FakeFirebaseFirestore> seed() async {
  final db = FakeFirebaseFirestore();
  await db.collection('users').doc('8').set({
    'role': 'admin',
    'is_active': true,
  });
  await db.collection('bookings').doc('84').set(numeric());
  await db.collection('bookings').doc(temp).set({
    ...numeric(),
    'id': temp,
    'client_status': 'cancelled',
    'driver_status': 'cancelled',
    'helper_status': 'cancelled',
    'chassis_id': null,
    'status_outputs': {
      'cancel': {
        'fields': {'reason': 'doubled booking'},
      },
    },
  });
  await db
      .collection('manage_id')
      .doc(BookingIdResolver.reservationId(key))
      .set({
        'resource_key': 'bookings',
        'submission_key': key,
        'document_id': '84',
      });
  await db.collection('booking_id_repairs').doc(temp).set({
    'status': 'needs_review',
    'source_id': temp,
    'target_id': '84',
    'reason': 'Booking contents differ',
  });
  await db.collection('chassis').doc('7').set({
    'current_booking_id': 84,
    'current_driver_id': 13,
    'current_status': 'ready',
  });
  await db.collection('support').doc('thread').set({
    'booking_id': temp,
    'text': temp,
  });
  return db;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'preview exposes live status, assignment and history without writes',
    () async {
      final db = await seed();
      final service = BookingConflictReviewService(firestore: db);
      expect(await service.listConflicts(), [temp]);
      final p = await service.preview(temp);
      expect(p.canApply, true);
      expect(p.source?['client_status'], 'cancelled');
      expect(p.canonical?['chassis_id'], '7');
      expect((await db.collection('bookings').get()).docs, hasLength(2));
    },
  );
  test(
    'keep numeric archives both copies and preserves canonical data and assignment',
    () async {
      final db = await seed();
      final service = BookingConflictReviewService(firestore: db);
      await service.apply(
        await service.preview(temp),
        BookingConflictChoice.keepNumeric,
        adminId: '8',
      );
      expect(
        (await db.collection('bookings').doc('84').get()).data(),
        numeric(),
      );
      expect((await db.collection('bookings').doc(temp).get()).exists, false);
      expect((await db.collection('chassis').doc('7').get()).data(), {
        'current_booking_id': 84,
        'current_driver_id': 13,
        'current_status': 'ready',
      });
      expect((await db.collection('support').doc('thread').get()).data(), {
        'booking_id': '84',
        'text': temp,
      });
      final report = db.collection('booking_id_repairs').doc(temp);
      expect((await report.get()).data()?['resolved_by'], '8');
      expect(
        (await report.collection('decision_snapshots').get()).docs,
        hasLength(2),
      );
    },
  );
  test(
    'explicit temporary cancellation updates statuses and releases only owned chassis',
    () async {
      final db = await seed();
      final service = BookingConflictReviewService(firestore: db);
      await db.collection('chassis').doc('2').set({'current_booking_id': 71});
      await service.apply(
        await service.preview(temp),
        BookingConflictChoice.useTemporary,
        adminId: '8',
      );
      final saved = (await db.collection('bookings').doc('84').get()).data()!;
      expect(saved['client_status'], 'cancelled');
      expect(saved['id'], '84');
      expect(saved['created_at'], numeric()['created_at']);
      expect(
        (await db.collection('chassis').doc('7').get()).data()?.containsKey(
          'current_booking_id',
        ),
        false,
      );
      expect(
        (await db.collection('chassis').doc('2').get())
            .data()?['current_booking_id'],
        71,
      );
    },
  );
  test(
    'same-timestamp changes invalidate preview rather than overwriting data',
    () async {
      final db = await seed();
      final service = BookingConflictReviewService(firestore: db);
      final p = await service.preview(temp);
      await db.collection('bookings').doc('84').update({
        'driver_id': 'new_driver',
      });
      await expectLater(
        service.apply(p, BookingConflictChoice.keepNumeric, adminId: '8'),
        throwsStateError,
      );
      expect((await db.collection('bookings').doc(temp).get()).exists, true);
      expect(
        (await db.collection('bookings').doc('84').get()).data()?['driver_id'],
        'new_driver',
      );
    },
  );
  test(
    'changed chassis ownership and changed reservation both reject stale decisions',
    () async {
      for (final path in [
        'chassis/7',
        'manage_id/${BookingIdResolver.reservationId(key)}',
      ]) {
        final db = await seed();
        final service = BookingConflictReviewService(firestore: db);
        final p = await service.preview(temp);
        await db
            .doc(path)
            .update(
              path.startsWith('chassis')
                  ? {'current_booking_id': 99}
                  : {'document_id': '99'},
            );
        await expectLater(
          service.apply(p, BookingConflictChoice.useTemporary, adminId: '8'),
          throwsStateError,
        );
        expect(
          (await db.collection('bookings').doc('84').get()).data(),
          numeric(),
        );
        expect((await db.collection('bookings').doc(temp).get()).exists, true);
      }
    },
  );
  test('non-admin and repeated application cannot change records', () async {
    final db = await seed();
    final service = BookingConflictReviewService(firestore: db);
    await db.collection('users').doc('9').set({
      'role': 'driver',
      'is_active': true,
    });
    final p = await service.preview(temp);
    await expectLater(
      service.apply(p, BookingConflictChoice.keepNumeric, adminId: '9'),
      throwsStateError,
    );
    await service.apply(p, BookingConflictChoice.keepNumeric, adminId: '8');
    await expectLater(
      service.apply(p, BookingConflictChoice.useTemporary, adminId: '8'),
      throwsStateError,
    );
    expect((await db.collection('bookings').doc('84').get()).data(), numeric());
  });
  test('view model requires deliberate version and acknowledgement', () async {
    final db = await seed();
    final vm = BookingConflictReviewViewModel(
      service: BookingConflictReviewService(firestore: db),
      adminId: '8',
    );
    await vm.load();
    await vm.select(temp);
    expect(vm.canApply, false);
    await vm.apply();
    expect((await db.collection('bookings').doc(temp).get()).exists, true);
    vm.choose(BookingConflictChoice.keepNumeric);
    expect(vm.canApply, false);
    vm.acknowledge(true);
    expect(vm.canApply, true);
    await vm.apply();
    expect(vm.preview, isNull);
    expect(vm.conflicts, isEmpty);
    expect(vm.success, contains('#84'));
    vm.dispose();
  });
  testWidgets('dialog displays comparison and starts with apply disabled', (
    tester,
  ) async {
    final db = await seed();
    final vm = BookingConflictReviewViewModel(
      service: BookingConflictReviewService(firestore: db),
      adminId: '8',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BookingConflictReviewDialog(viewModel: vm)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review $temp'));
    await tester.pumpAndSettle();
    expect(find.text('Temporary copy → Booking #84'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('client status'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('client status'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Full records and workflow history'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Full records and workflow history'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Apply selected version'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    final apply = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Apply selected version'),
    );
    expect(apply.onPressed, isNull);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
