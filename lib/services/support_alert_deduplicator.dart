import 'dart:convert';

/// Bounded session history shared by live thread updates and foreground push.
class SupportAlertDeduplicator {
  final _seen = <String>{};

  bool accept({
    required String threadId,
    required String senderId,
    required DateTime messageAt,
    required String preview,
  }) {
    final key = jsonEncode([
      threadId,
      senderId,
      messageAt.toUtc().toIso8601String(),
      preview.length > 200 ? preview.substring(0, 200) : preview,
    ]);
    if (!_seen.add(key)) {
      return false;
    }
    if (_seen.length > 256) {
      _seen.remove(_seen.first);
    }
    return true;
  }

  void clear() => _seen.clear();
}
