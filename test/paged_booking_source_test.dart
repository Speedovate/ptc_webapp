import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/paged_booking_source.dart';

void main() {
  test(
    'paged reads include legacy and temporary IDs without a created_at field',
    () async {
      final ref = FakeFirebaseFirestore().collection('bookings');
      for (final id in ['1', '2', '10', '11', '90', 'offline_booking_1']) {
        await ref.doc(id).set({'id': id, 'notes': id});
      }
      final source = PagedBookingSource(ref, pageSize: 2, online: () => true);
      final result = await source.read(const GetOptions(source: Source.server));
      expect(result.docs.map((d) => d.id).toList(), [
        '1',
        '10',
        '11',
        '2',
        '90',
        'offline_booking_1',
      ]);
      expect(result.metadata.isFromCache, isFalse);
    },
  );

  test(
    'bounded live ranges retain other pages on edits, deletion and overflow',
    () async {
      final ref = FakeFirebaseFirestore().collection('bookings');
      for (final id in ['10', '20', '30', '40', '50']) {
        await ref.doc(id).set({'id': id, 'amount': 1});
      }
      final source = PagedBookingSource(ref, pageSize: 2, online: () => true);
      final received = <BookingDataSnapshot>[];
      final sub = source.watch().listen(received.add);
      addTearDown(sub.cancel);
      Future<void> until(bool Function(BookingDataSnapshot) matches) async {
        for (var i = 0; i < 100; i++) {
          if (received.isNotEmpty && matches(received.last)) return;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        fail('No matching complete snapshot');
      }

      await until((s) => s.docs.length == 5);
      expect(received.every((s) => s.docs.length == 5), isTrue);
      await ref.doc('30').update({'amount': 12});
      await until(
        (s) => s.docs.firstWhere((d) => d.id == '30').data()['amount'] == 12,
      );
      await ref.doc('20').delete();
      await until((s) => s.docs.length == 4);
      // Inserting inside an already full range forces a bounded repartition.
      await ref.doc('35').set({'id': '35', 'amount': 7});
      await until((s) => s.docs.length == 5 && s.docs.any((d) => d.id == '35'));
      expect(received.last.docs.map((d) => d.id).toSet(), {
        '10',
        '30',
        '35',
        '40',
        '50',
      });
      await sub.cancel();
      final count = received.length;
      await ref.doc('60').set({'id': '60'});
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(received.length, count);
    },
  );
}
