import 'package:webapp/models/support_message.dart';

/// Match a send by identity, never by text or a timestamp window.
bool sameSupportMessage(SupportMessage a, SupportMessage b) {
  if ((a.threadId ?? '').trim() != (b.threadId ?? '').trim() ||
      (a.senderUserId ?? '').trim() != (b.senderUserId ?? '').trim()) {
    return false;
  }
  final id = a.id?.trim() ?? '';
  if (id.isNotEmpty && id == b.id?.trim()) {
    return true;
  }
  final key = a.localOrderKey?.trim() ?? '';
  return key.isNotEmpty && key == b.localOrderKey?.trim();
}

List<Map<String, dynamic>> reconcileSupportMessageDocuments(
  List<Map<String, dynamic>> documents,
) {
  final result = <Map<String, dynamic>>[];
  final byId = <(String, String, String), int>{};
  final bySend = <(String, String, String), int>{};
  for (final doc in documents) {
    final message = SupportMessage.fromMap(doc);
    final scope = (
      message.threadId?.trim() ?? '',
      message.senderUserId?.trim() ?? '',
    );
    final id = message.id?.trim() ?? '';
    final send = message.localOrderKey?.trim() ?? '';
    final index =
        (id.isEmpty ? null : byId[(scope.$1, scope.$2, id)]) ??
        (send.isEmpty ? null : bySend[(scope.$1, scope.$2, send)]);
    final target = index ?? result.length;
    if (index == null) {
      result.add(doc);
    } else if (!message.isPendingUpload ||
        SupportMessage.fromMap(result[index]).isPendingUpload) {
      result[index] = doc;
    }
    if (id.isNotEmpty) {
      byId[(scope.$1, scope.$2, id)] = target;
    }
    if (send.isNotEmpty) {
      bySend[(scope.$1, scope.$2, send)] = target;
    }
  }
  return result;
}
