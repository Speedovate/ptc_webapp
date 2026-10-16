import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/orphan_photo_recovery_service.dart';
import 'package:webapp/widgets/shared/orphan_photo_recovery_dialog.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend;
import 'booking254_pending_preview_recovery_test.dart' show Photos;
import 'support/merge_aware_firestore.dart';

void main() {
  testWidgets(
    'photo recovery requires reviewing a destination and confirming the photo',
    (tester) async {
      final disk = MemoryBackend();
      final db = MergeAwareFirestore();
      final photos = Photos();
      const id = 'booking_upload_review', owner = '8';
      disk.data[OrphanPhotoRecoveryService.queueKey(owner)] = [
        jsonEncode({
          'id': id,
          'booking_id': 'offline_booking_8_9_1_1791957845495000',
          'status_key': 'book__1791957845495000',
          'field_key': 'waybill_photo',
          'file_name': 'saved.jpg',
          'mime_type': 'image/jpeg',
          'size': 3,
          'bytes_base64': 'AQID',
          'created_at': '2026-10-14T06:04:10.527Z',
          'wait_reason': 'temporary_booking_id',
        }),
      ];
      await db.collection('bookings').doc('600').set({
        'id': '600',
        'submission_key': 'other',
        'client_id': '9',
        'client_status': 'delivered',
        'status_outputs': <String, dynamic>{},
      });
      final service = OrphanPhotoRecoveryService(
        backend: disk,
        firestore: db,
        photos: photos,
        requireOwner: (_) async {},
        hasPending: (_, _) async => false,
        withQueueLock: (action) => action(),
        onResolved: (_, _) async {},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => OrphanPhotoRecoveryDialog(
                    service: service,
                    owner: owner,
                    entryId: id,
                  ),
                ),
                child: const Text('Open recovery'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open recovery'));
      await tester.pumpAndSettle();
      expect(find.text('Recover to booking history'), findsNothing);
      await tester.enterText(find.byType(TextField), '600');
      await tester.tap(find.text('Review photo and booking'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Destination: Booking 600'), findsOneWidget);
      final button = find.widgetWithText(
        FilledButton,
        'Recover to booking history',
      );
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      expect(photos.uploads, 0);
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(photos.uploads, 1);
      expect(
        disk.data[OrphanPhotoRecoveryService.queueKey(owner)]?.length,
        0,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data)
            .join('\n'),
      );
      expect(
        disk.data[OrphanPhotoRecoveryService.archiveKey(owner, id)],
        isNotEmpty,
      );
      expect(find.text('Recover saved photo'), findsNothing);
    },
  );
}
