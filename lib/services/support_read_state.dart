import 'package:webapp/models/support_message.dart';
import 'package:webapp/models/support_thread.dart';
import 'package:webapp/utils/functions.dart';

String _token(String? value) {
  final text = value?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
  return text.length <= 120 ? text : text.substring(0, 120);
}

String supportThreadReadMarker(SupportThread thread) =>
    '${(thread.lastMessageAt ?? thread.updatedAt)?.toUtc().toIso8601String() ?? ''}'
    '|${normalizeId(thread.lastSenderUserId) ?? ''}|${_token(thread.lastMessageText)}';

String supportMessageReadMarker(SupportMessage message) {
  final text = message.text?.trim() ?? '';
  final preview = text.isNotEmpty
      ? text
      : switch (message.attachments.length) {
          0 => '',
          1 => 'Sent an attachment',
          final count => 'Sent $count attachments',
        };
  return '${(message.createdAt ?? message.updatedAt)?.toUtc().toIso8601String() ?? ''}'
      '|${normalizeId(message.senderUserId) ?? ''}|${_token(preview)}';
}

DateTime? supportMarkerMessageTime(String? marker) =>
    DateTime.tryParse((marker ?? '').split('|').first)?.toUtc();

/// A cached thread older than the message already read cannot become unread.
/// Missing read state means the incoming conversation has not yet been read.
bool isSupportThreadUnread({
  required SupportThread thread,
  required String? currentUserId,
  required String? savedMarker,
  bool markersResolved = true,
}) {
  final viewer = normalizeId(currentUserId);
  final sender = normalizeId(thread.lastSenderUserId);
  if (!markersResolved ||
      viewer == null ||
      normalizeId(thread.id) == null ||
      sender == null ||
      sender == viewer ||
      !thread.hasConversation) {
    return false;
  }
  final latest = supportThreadReadMarker(thread);
  if (savedMarker == null || savedMarker.trim().isEmpty) return true;
  if (savedMarker == latest) return false;
  final seenAt = supportMarkerMessageTime(savedMarker);
  final latestAt = supportMarkerMessageTime(latest);
  if (seenAt != null && latestAt != null) return latestAt.isAfter(seenAt);
  return true;
}

/// Message progress takes precedence over the time a delayed read was saved.
List<Map<String, dynamic>> mergeSupportReadDocuments(
  Iterable<Map<String, dynamic>> documents,
) {
  final merged = <String, Map<String, dynamic>>{};
  for (final document in documents) {
    final id =
        normalizeId(document['thread_id']) ?? normalizeId(document['id']);
    if (id == null) continue;
    final previous = merged[id];
    if (previous != null) {
      final incomingMessage = supportMarkerMessageTime(
        document['marker']?.toString(),
      );
      final previousMessage = supportMarkerMessageTime(
        previous['marker']?.toString(),
      );
      if (incomingMessage != null &&
          previousMessage != null &&
          incomingMessage.isBefore(previousMessage)) {
        continue;
      }
      if (incomingMessage == previousMessage ||
          incomingMessage == null ||
          previousMessage == null) {
        final incomingAt = DateTime.tryParse('${document['updated_at']}');
        final previousAt = DateTime.tryParse('${previous['updated_at']}');
        if (previousAt != null &&
            (incomingAt == null || !incomingAt.isAfter(previousAt))) {
          continue;
        }
      }
    }
    merged[id] = Map<String, dynamic>.from(document);
  }
  return merged.values.toList();
}

Map<String, String> mergeSupportReadMarkers(
  Map<String, String> existing,
  Map<String, String> incoming,
) {
  final merged = {...existing};
  for (final entry in incoming.entries) {
    final currentAt = supportMarkerMessageTime(merged[entry.key]);
    final incomingAt = supportMarkerMessageTime(entry.value);
    if (currentAt != null &&
        incomingAt != null &&
        incomingAt.isBefore(currentAt)) {
      continue;
    }
    merged[entry.key] = entry.value;
  }
  return merged;
}
