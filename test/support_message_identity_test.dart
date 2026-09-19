import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/utils/support_message_identity.dart';

Map<String, dynamic> message(
  String id,
  String key, {
  String sender = 'driver',
}) => {
  'id': id,
  'local_order_key': key,
  'thread_id': 'thread',
  'sender_user_id': sender,
  'text': 'Hello',
  'created_at': '2026-09-19T01:02:03Z',
};
void main() {
  test('cached pending and queue copies produce one bubble', () {
    final local = message('local_1', 'send1');
    expect(reconcileSupportMessageDocuments([local, local]), hasLength(1));
  });
  for (final confirmedFirst in [true, false]) {
    test('confirmed bubble wins in either arrival order: $confirmedFirst', () {
      final pending = message('local_1', 'send1');
      final confirmed = message('support_message_1', 'send1');
      final result = reconcileSupportMessageDocuments(
        confirmedFirst
            ? [confirmed, pending, pending]
            : [pending, pending, confirmed],
      );
      expect(result, [confirmed]);
      expect(result.single['created_at'], '2026-09-19T01:02:03Z');
    });
  }
  test('identical text does not combine independent sends or accounts', () {
    expect(
      reconcileSupportMessageDocuments([
        message('local_1', 'send1'),
        message('local_2', 'send2'),
        message('local_3', 'send1', sender: 'other'),
      ]),
      hasLength(3),
    );
  });
  test('legacy messages without an identity key are not guessed from text', () {
    expect(
      reconcileSupportMessageDocuments([
        message('local_old', ''),
        message('remote_old', ''),
      ]),
      hasLength(2),
    );
  });
}
