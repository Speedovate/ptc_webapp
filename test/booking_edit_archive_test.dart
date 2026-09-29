import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/services/booking_edit_archive.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend, storageKey;
import 'support/merge_aware_firestore.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final photo = {
    'name': 'waybill.jpg',
    'size': 3,
    'download_url': 'data:image/jpeg;base64,AQID',
  };
  Map<String, dynamic> event(String at, Object image) => {
    'submitted_at': at,
    'submitted_by': '8',
    'submitted_role': 'dispatcher',
    'status_key': 'assigned',
    'status_form': null,
    'fields': {'amount': '4695', 'waybill_photo': image},
  };
  Map<String, dynamic> pending() => {
    'id': '163',
    'submission_key': 'original',
    'client_status': 'assigned',
    'updated_at': '2026-09-29T15:42:17.484',
    'status_outputs': {
      'book': event('2026-09-29T15:41:24', photo),
      'old-edit': event('2026-09-29T15:42:17.482', {
        ...photo,
        'pending_upload': true,
        'pending_upload_id': 'upload1',
      }),
    },
  };
  Map<String, dynamic> server() => {
    ...pending(),
    'updated_at': '2026-09-29T18:01:57.378',
    'status_outputs': {
      'book': event('2026-09-29T15:41:24', {
        'download_url': 'https://example.test/new',
      }),
      'new-edit': event('2026-09-29T18:01:57.369', {
        'download_url': 'https://example.test/new',
      }),
    },
    'photo_cleanup_paths': [],
    'photo_cleanup_claims': [],
  };
  test(
    'archives original photo and timestamp without changing latest event, idempotently',
    () {
      final remote = server();
      final local = pending();
      final result = archiveSupersededBookingEdit(remote, local)!;
      expect(result['updated_at'], remote['updated_at']);
      expect(
        result['status_outputs']['old-edit'],
        local['status_outputs']['old-edit'],
      );
      expect(
        result['status_outputs']['new-edit'],
        remote['status_outputs']['new-edit'],
      );
      expect(
        result['status_outputs']['book'],
        remote['status_outputs']['book'],
      );
      expect(archiveSupersededBookingEdit(result, local), result);
      expect(remote, server());
      expect(local, pending());
    },
  );
  test(
    'rejects unrelated identity, amount, actor, chassis and workflow differences',
    () {
      for (final key in ['submission_key', 'chassis_id', 'client_status']) {
        expect(
          archiveSupersededBookingEdit(server(), {...pending(), key: 'other'}),
          isNull,
        );
      }
      for (final key in ['submitted_by', 'status_form']) {
        final local = pending();
        local['status_outputs']['old-edit'][key] = 'other';
        expect(archiveSupersededBookingEdit(server(), local), isNull);
      }
      final local = pending();
      local['status_outputs']['old-edit']['fields']['amount'] = '9999';
      expect(archiveSupersededBookingEdit(server(), local), isNull);
    },
  );
  test(
    'persisted Connection failed entry recovers once and leaves current booking untouched',
    () async {
      final db = MergeAwareFirestore();
      final backend = MemoryBackend();
      await db.collection('bookings').doc('163').set(server());
      backend.data[storageKey] = [
        jsonEncode({
          'id': 'entry163',
          'kind': 'collectionDocumentUpsert',
          'collection_key': 'bookings',
          'target_id': '163',
          'payload': pending(),
          'base_updated_at': '2026-09-29T15:41:24.028',
          'created_at': '2026-09-29T07:42:17.484Z',
          'is_blocked': true,
          'last_error': 'Connection failed.',
          'conflict_recovery_attempted': true,
        }),
      ];
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => true,
      );
      await queue.flushPendingMutations();
      expect(backend.data[storageKey], isEmpty);
      final saved = (await db.collection('bookings').doc('163').get()).data()!;
      expect(saved, archiveSupersededBookingEdit(server(), pending()));
      await queue.flushPendingMutations();
      expect((await db.collection('bookings').doc('163').get()).data(), saved);
    },
  );
}
