import 'dart:collection';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/offline_reference_mapper.dart';
import 'package:webapp/utils/copy_document_fields.dart';
import 'package:webapp/utils/functions.dart';

// Test double for a document whose map cannot dispatch forEach.
// ignore: subtype_of_sealed_class
class _Snapshot extends Fake implements DocumentSnapshot<Map<String, dynamic>> {
  _Snapshot(this.fields);
  final Map<String, dynamic> fields;
  @override
  String get id => 'thread_7';
  @override
  Map<String, dynamic> data() => fields;
}

// Models the observed unavailable forEach dispatch, not the entire hot-restart
// runtime. Keys and indexed access must still work for this recovery path.
class _WithoutForEach extends MapBase<String, dynamic> {
  _WithoutForEach(this.valuesByKey);
  final Map<String, dynamic> valuesByKey;
  @override
  dynamic operator [](Object? key) => valuesByKey[key];
  @override
  void operator []=(String key, dynamic value) => valuesByKey[key] = value;
  @override
  Iterable<String> get keys => valuesByKey.keys;
  @override
  void clear() => valuesByKey.clear();
  @override
  dynamic remove(Object? key) => valuesByKey.remove(key);
  @override
  void forEach(void Function(String, dynamic) action) =>
      throw UnsupportedError('forEach dispatch unavailable');
}

void main() {
  test('snapshot conversion preserves fields without forEach dispatch', () {
    final at = Timestamp.fromDate(DateTime.utc(2026, 9, 19));
    final data = documentData(
      _Snapshot(
        _WithoutForEach({'last_message_at': at, 'requester_user_id': '7'}),
      ),
    );
    expect(data['id'], 'thread_7');
    expect(data['requester_user_id'], '7');
    expect(identical(data['last_message_at'], at), isTrue);
    expect(
      documentData(_Snapshot(_WithoutForEach({'id': 'stored'})))['id'],
      'stored',
    );
  });
  test(
    'reference check and no-alias resolver avoid forEach dispatch',
    () async {
      final document = _WithoutForEach({'sender_user_id': '7'});
      expect(() => Map<String, dynamic>.from(document), throwsUnsupportedError);
      expect(OfflineReferenceMapper.hasTemporaryReferences(document), isFalse);
      final resolved = await OfflineMutationQueueService()
          .resolveResourceReferences(document, scope: '7');
      expect(resolved, {'sender_user_id': '7'});
      resolved['sender_user_id'] = '8';
      expect(document['sender_user_id'], '7');
    },
  );

  test('nested aliases preserve action time and arbitrary user fields', () {
    final at = Timestamp.fromDate(DateTime.utc(2026, 9, 19));
    final document = _WithoutForEach({
      'sender_user_id': 'offline_users_sender',
      'created_at': at,
      'text': 'offline_users_sender',
      'document': _WithoutForEach({'driver_id': 'offline_users_sender'}),
    });
    expect(OfflineReferenceMapper.hasTemporaryReferences(document), isTrue);
    expect(
      () => OfflineReferenceMapper.mapDocument(document, {}),
      throwsStateError,
    );
    final resolved = OfflineReferenceMapper.mapDocument(document, {
      'offline_users_sender': '7',
    });
    expect(resolved['sender_user_id'], '7');
    expect(resolved['document'], {'driver_id': '7'});
    expect(identical(resolved['created_at'], at), isTrue);
    expect(resolved['text'], 'offline_users_sender');
    expect(document['sender_user_id'], 'offline_users_sender');
    expect(document['document']['driver_id'], 'offline_users_sender');
  });

  test('invalid document keys fail instead of silently dropping data', () {
    expect(() => copyDocumentFields({1: 'bad key'}), throwsA(isA<TypeError>()));
  });
}
