import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/support_alert_deduplicator.dart';

void main() {
  test(
    'thread and push alert once regardless of arrival order or timezone',
    () {
      final seen = SupportAlertDeduplicator();
      bool accept(String at, {String thread = '1', String text = 'hello'}) =>
          seen.accept(
            threadId: thread,
            senderId: '2',
            messageAt: DateTime.parse(at),
            preview: text,
          );
      expect(accept('2026-09-19T00:00:00Z'), isTrue);
      expect(accept('2026-09-19T08:00:00+08:00'), isFalse);
      expect(accept('2026-09-19T00:00:00Z', thread: '2'), isTrue);
      expect(accept('2026-09-19T00:00:01Z'), isTrue);
      seen.clear();
      expect(accept('2026-09-19T00:00:00Z'), isTrue);
    },
  );
  test('bounded payload preview deduplicates long foreground messages', () {
    final seen = SupportAlertDeduplicator();
    final at = DateTime.utc(2026);
    final long = List.filled(1000, 'a').join();
    expect(
      seen.accept(threadId: '1', senderId: '2', messageAt: at, preview: long),
      isTrue,
    );
    expect(
      seen.accept(
        threadId: '1',
        senderId: '2',
        messageAt: at,
        preview: long.substring(0, 200),
      ),
      isFalse,
    );
  });
  test('history is bounded for a long-running session', () {
    final seen = SupportAlertDeduplicator();
    bool accept(int i) => seen.accept(
      threadId: '$i',
      senderId: '2',
      messageAt: DateTime.utc(2026),
      preview: 'hello',
    );
    for (var i = 0; i < 257; i++) {
      expect(accept(i), isTrue);
    }
    expect(accept(256), isFalse);
    expect(accept(0), isTrue);
  });
}
