// Fault injection for the otherwise unnecessary temporary-document SDK read.
// ignore_for_file: subtype_of_sealed_class
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/services/booking_id_resolver.dart';
import 'package:webapp/services/booking_offline_upload_queue_service.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/photo_storage_service.dart';
import 'package:webapp/services/firebase_console_diagnostic.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend;
import 'support/merge_aware_firestore.dart';

class _Db extends MergeAwareFirestore {
  int temporaryReads = 0;
  String? rejectIdentity;
  final identitySources = <Source?>[];
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(super.collection(path), this);
}

class _Collection implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.delegate, this.db);
  final CollectionReference<Map<String, dynamic>> delegate;
  final _Db db;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? id]) =>
      _Doc(delegate.doc(id), db);
  @override
  dynamic noSuchMethod(Invocation i) {
    if (i.memberName == #where) {
      return delegate.where(
        i.positionalArguments.first,
        isEqualTo: i.namedArguments[#isEqualTo],
      );
    }
    return super.noSuchMethod(i);
  }
}

class _Doc implements DocumentReference<Map<String, dynamic>> {
  _Doc(this.delegate, this.db);
  final DocumentReference<Map<String, dynamic>> delegate;
  final _Db db;
  @override
  String get path => delegate.path;
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([GetOptions? options]) {
    if (path.startsWith('bookings/offline_')) {
      db.temporaryReads++;
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
        message: 'Failed to get document because the client is offline.',
      );
    }
    if (path.startsWith('manage_id/') ||
        path.startsWith('booking_id_repairs/')) {
      db.identitySources.add(options?.source);
      if (db.rejectIdentity != null) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: db.rejectIdentity!,
        );
      }
    }
    return delegate.get(options);
  }

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) => delegate
      .set(jsonDecode(jsonEncode(data)) as Map<String, dynamic>, options);
  @override
  Future<void> update(Map<Object, Object?> data) => delegate.update(data);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Photos extends PhotoStorageService {
  int uploads = 0;
  @override
  Future<Map<String, dynamic>> uploadBookingPhoto({
    required Uint8List bytes,
    required String bookingId,
    required String statusKey,
    required String fieldKey,
    required String fileName,
    String? mimeType,
    int? size,
  }) async {
    uploads++;
    return {
      'name': fileName,
      'size': size,
      'mime_type': mimeType,
      'download_url': 'https://example.test/upload',
      'storage_path':
          'bookings/$bookingId/status_outputs/$statusKey/$fieldKey/photo.jpg',
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final reports =
      jsonDecode(
            File(
              'test/fixtures/oct15_six_photo_reports.json',
            ).readAsStringSync(),
          )
          as List;
  for (final report in reports) {
    final p = report['photo_upload'] as Map;
    final temporary = BookingIdResolver.isTemporary(p['booking_id']);
    for (final scenario
        in temporary
            ? [
                'canonical_without_reservation',
                'canonical_with_reservation',
                'missing',
                'unavailable',
                'permission-denied',
              ]
            : ['already_committed']) {
      test('Oct15 ${p['booking_id']}: $scenario', () async {
        final db = _Db();
        final disk = MemoryBackend();
        final photos = _Photos();
        const scope = 'booking_pending_upload_queue_v1::signed_out';
        final id = temporary ? '401' : p['booking_id'] as String;
        final key = temporary
            ? (p['booking_id'] as String).substring('offline_'.length)
            : null;
        final server = temporary
            ? <String, dynamic>{
                'id': id,
                'submission_key': key,
                'client_id': '9',
                'status_outputs': {
                  p['status_key']: {
                    'fields': {
                      p['field_key']: {
                        'pending_upload': true,
                        'pending_upload_id': report['queue_entry_id'],
                        'name': p['file_name'],
                        'size': p['size'],
                        'mime_type': p['mime_type'],
                      },
                    },
                  },
                },
              }
            : Map<String, dynamic>.from(report['server_document']);
        if (scenario != 'missing') {
          await db.collection('bookings').doc(id).set(server);
        }
        if (scenario == 'canonical_with_reservation') {
          await db
              .collection('manage_id')
              .doc(BookingIdResolver.reservationId(key!))
              .set({
                'resource_key': 'bookings',
                'submission_key': key,
                'document_id': id,
              });
        }
        if (scenario == 'unavailable' || scenario == 'permission-denied') {
          db.rejectIdentity = scenario;
        }
        disk.data[scope] = [
          jsonEncode({
            'id': report['queue_entry_id'],
            'booking_id': p['booking_id'],
            'status_key': p['status_key'],
            'field_key': p['field_key'],
            'file_name': p['file_name'],
            'size': p['size'],
            'mime_type': p['mime_type'],
            'bytes_base64': base64Encode(Uint8List(p['size'])),
            'created_at': report['action_at'],
            'waiting_for_commit': true,
            'wait_reason': p['wait_reason'],
            'wait_count': p['wait_count'],
            'retry_count': 1,
            'last_error': report['error'],
          }),
        ];
        final mutations = OfflineMutationQueueService(
          firestore: db,
          backend: disk,
          isOnline: () => false,
        );
        addTearDown(mutations.dispose);
        final uploader = BookingOfflineUploadQueueService(
          firestore: db,
          backend: disk,
          photoStorageService: photos,
          mutationQueue: mutations,
          flushMutations: () async {},
          cachedBookingReader: (_) async => null,
        );
        await uploader.flushPendingUploads();
        expect(db.temporaryReads, 0);
        if (temporary) expect(db.identitySources, everyElement(Source.server));
        final succeeds =
            scenario.startsWith('canonical') || scenario == 'already_committed';
        final diagnostic = disk.data[scope]!.isEmpty
            ? ''
            : '${jsonDecode(disk.data[scope]!.first)['error_diagnostics']}'
                  .split('Raw error:')
                  .last;
        expect(disk.data[scope]!.length, succeeds ? 0 : 1, reason: diagnostic);
        expect(photos.uploads, temporary && succeeds ? 1 : 0);
        if (!succeeds) {
          final retained = jsonDecode(disk.data[scope]!.single);
          expect(base64Decode(retained['bytes_base64']).length, p['size']);
          if (scenario == 'missing') {
            expect(
              retained['error_diagnostics'],
              contains('no_server_identity'),
            );
            final evidence = <String, dynamic>{};
            final resolver = BookingIdResolver(firestore: db);
            resolver.invalidate(p['booking_id']);
            expect(
              await resolver.resolve(p['booking_id'], lookupEvidence: evidence),
              isNull,
            );
            expect(evidence['canonical_match_count'], 0);
            expect(
              firebaseConsoleDiagnostic({
                'error': report['error'],
                'details': {'identity_lookup': evidence},
              })['category'],
              'local_sync_dependency_or_conflict',
            );
          }
          expect(
            (await db.collection('bookings').doc(id).get()).data(),
            scenario == 'missing' ? isNull : server,
          );
        } else if (!temporary) {
          expect(
            (await db.collection('bookings').doc(id).get()).data(),
            server,
          );
        }
        await uploader.flushPendingUploads();
        expect(photos.uploads, temporary && succeeds ? 1 : 0);
      });
    }
  }
}
