@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/repositories/local/booking_storage_backend.dart';
import 'package:webapp/services/booking_id_resolver.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/utils/functions.dart';

import '../support/merge_aware_firestore.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('staged booking photo survives browser storage reopening', () async {
    final scope = 'browser_stage_${DateTime.now().microsecondsSinceEpoch}';
    final storageKey = 'offline_mutation_queue_v1::$scope';
    final auth = createAuthStorageBackend();
    await auth.initialize();
    await auth.writeString('paltranco_current_user_id', scope);
    final backend = createBookingStorageBackend();
    await backend.initialize();
    addTearDown(() async {
      await backend.writeStringList(storageKey, []);
      await auth.remove('paltranco_current_user_id');
      await auth.remove('offline_mutation_queue_aliases_v1::$storageKey');
    });
    final db = MergeAwareFirestore();
    var online = false;
    final key = 'booking_$scope';
    final id = BookingIdResolver.temporaryId(key);
    const actionAt = '2026-10-14T06:06:16.112Z';
    final queue = OfflineMutationQueueService(
      firestore: db,
      backend: backend,
      isOnline: () => online,
    );
    await queue.stageOfflineBookingCreate(
      provisionalId: id,
      submissionKey: key,
      document: {
        'id': id,
        'submission_key': key,
        'created_at': actionAt,
        'updated_at': actionAt,
        'status_outputs': {
          'book': {
            'submitted_at': actionAt,
            'fields': {
              'waybill_photo': {
                'bytes': Uint8List.fromList([1, 2, 3, 255]),
              },
            },
          },
        },
      },
    );
    final reopened = OfflineMutationQueueService(
      firestore: db,
      backend: createBookingStorageBackend(),
      isOnline: () => online,
    );
    final staged = await reopened.readStagedOfflineBookingCreates();
    expect(staged, hasLength(1));
    final source = Map<String, dynamic>.from(staged.single['document'] as Map);
    final photo =
        ((source['status_outputs'] as Map)['book']
            as Map)['fields']['waybill_photo'];
    expect(decodePhotoBytes(photo), Uint8List.fromList([1, 2, 3, 255]));
    online = true;
    await reopened.flushPendingMutations();
    expect((await db.collection('bookings').get()).docs, isEmpty);
    (photo as Map).remove('bytes');
    photo['pending_upload'] = true;
    await reopened.queueOfflineBookingCreate(
      provisionalId: id,
      submissionKey: key,
      document: source,
      onlyIfStaged: true,
    );
    await reopened.flushPendingMutations();
    final saved = (await db.collection('bookings').get()).docs.single.data();
    expect(saved['created_at'], actionAt);
    expect((saved['status_outputs'] as Map)['book']['submitted_at'], actionAt);
  });
}
