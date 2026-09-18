import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/services/pending_booking_submission.dart';

void main() {
  test(
    'mutating source photo starts a fresh submission without changing old bytes',
    () {
      final pending = PendingBookingSubmission();
      final bytes = Uint8List.fromList([1, 2, 3]);
      var count = 0;
      Booking create() => Booking(
        submissionKey: '${++count}',
        statusOutputs: {
          'photo': {'bytes': bytes},
        },
      );
      final first = pending.resolve({'photo': bytes}, create);
      bytes[0] = 9;
      final changed = pending.resolve({'photo': bytes}, create);
      expect(changed.submissionKey, isNot(first.submissionKey));
      expect((first.statusOutputs!['photo'] as Map)['bytes'], [1, 2, 3]);
      expect((changed.statusOutputs!['photo'] as Map)['bytes'], [9, 2, 3]);
    },
  );
  test(
    'retained photo bytes keep their upload-compatible type and contents',
    () {
      final pending = PendingBookingSubmission();
      final bytes = Uint8List.fromList([1, 2, 3]);
      final first = pending.resolve(
        {'photo': bytes},
        () => Booking(
          statusOutputs: {
            'photo': {'bytes': bytes},
          },
        ),
      );
      final stored = (first.statusOutputs!['photo'] as Map)['bytes'];
      expect(stored, isA<Uint8List>());
      expect(() => stored[0] = 99, throwsUnsupportedError);
      final retry = pending.resolve({
        'photo': bytes,
      }, () => throw StateError('must reuse'));
      expect((retry.statusOutputs!['photo'] as Map)['bytes'], [1, 2, 3]);
      expect(
        identical((retry.statusOutputs!['photo'] as Map)['bytes'], stored),
        isTrue,
      );
      expect(identical(stored, bytes), isFalse);
    },
  );
  test(
    'failed submission retry retains creation time, key and original event',
    () {
      final pending = PendingBookingSubmission();
      var creates = 0;
      Booking create() => Booking(
        submissionKey: 'booking_${++creates}',
        createdAt: DateTime.utc(2026, 9, 14),
        statusOutputs: {
          'book': {
            'event': creates,
            'fields': {'amount': 100},
          },
        },
      );
      final first = pending.resolve({'client': '9', 'amount': 100}, create);
      final retry = pending.resolve({'amount': 100, 'client': '9'}, create);
      expect(retry.toMap(), first.toMap());
      expect(creates, 1);
    },
  );

  test('changed answers or client get a new submission identity', () {
    final pending = PendingBookingSubmission();
    var creates = 0;
    Booking create() => Booking(submissionKey: 'booking_${++creates}');
    final inputs = <String, dynamic>{
      'client': '9',
      'answers': {'amount': 100},
    };
    final first = pending.resolve(inputs, create);
    (inputs['answers'] as Map)['amount'] = 200;
    final changed = pending.resolve(inputs, create);
    inputs['client'] = '10';
    final otherClient = pending.resolve(inputs, create);
    expect(first.submissionKey, 'booking_1');
    expect(changed.submissionKey, 'booking_2');
    expect(otherClient.submissionKey, 'booking_3');
  });

  test('explicit clear gives identical new booking a fresh identity', () {
    final pending = PendingBookingSubmission();
    var creates = 0;
    Booking create() => Booking(submissionKey: 'booking_${++creates}');
    pending.resolve({'amount': 100}, create);
    pending.clear();
    expect(pending.resolve({'amount': 100}, create).submissionKey, 'booking_2');
  });

  test('repository mutations cannot change the retained retry document', () {
    final pending = PendingBookingSubmission();
    final first = pending.resolve(
      {},
      () => const Booking(
        submissionKey: 'booking_1',
        statusOutputs: {
          'book': {
            'fields': {'amount': 100},
          },
        },
      ),
    );
    ((first.statusOutputs!['book'] as Map)['fields'] as Map)['amount'] = 999;
    final retry = pending.resolve({}, () => throw StateError('must reuse'));
    expect((retry.statusOutputs!['book'] as Map)['fields'], {'amount': 100});
  });

  test(
    'latest created sorts first regardless of numeric ID and updated time',
    () {
      final records = [
        Booking(
          id: '100',
          createdAt: DateTime.utc(2026, 9, 14),
          updatedAt: DateTime.utc(2026, 9, 20),
        ),
        Booking(id: '2', createdAt: DateTime.utc(2026, 9, 18)),
        Booking(id: 'offline_booking_1', createdAt: DateTime.utc(2026, 9, 17)),
        Booking(id: '999', updatedAt: DateTime.utc(2026, 9, 21)),
      ]..sort(Booking.compareCreatedLatestFirst);
      expect(records.map((record) => record.id), [
        '2',
        'offline_booking_1',
        '100',
        '999',
      ]);
      records[1] = records[1].copyWith(
        id: '101',
        updatedAt: DateTime.utc(2026, 9, 22),
      );
      records.sort(Booking.compareCreatedLatestFirst);
      expect(records.map((record) => record.id), ['2', '101', '100', '999']);
    },
  );

  test(
    'equal or missing creation times have deterministic ID tie breakers',
    () {
      final records = [const Booking(id: '9'), const Booking(id: '10')]
        ..sort(Booking.compareCreatedLatestFirst);
      expect(records.map((record) => record.id), ['10', '9']);
    },
  );
}
