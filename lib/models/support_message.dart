import 'package:webapp/models/support_thread.dart';

class SupportMessage {
  const SupportMessage({
    this.id,
    this.localOrderKey,
    this.threadId,
    this.senderUserId,
    this.senderRole,
    this.senderName,
    this.senderPhoto,
    this.text,
    this.attachments = const [],
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String? localOrderKey;
  final String? threadId;
  final String? senderUserId;
  final String? senderRole;
  final String? senderName;
  final String? senderPhoto;
  final String? text;
  final List<SupportAttachment> attachments;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get hasText => text?.trim().isNotEmpty == true;
  bool get hasAttachments => attachments.isNotEmpty;
  bool get isPendingUpload => (id?.trim().startsWith('local_') ?? false);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'local_order_key': localOrderKey,
      'thread_id': threadId,
      'sender_user_id': senderUserId,
      'sender_role': senderRole,
      'sender_name': senderName,
      'sender_photo': senderPhoto,
      'text': text,
      'attachments': attachments.map((item) => item.toMap()).toList(),
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory SupportMessage.fromMap(Map<String, dynamic> map) {
    return SupportMessage(
      id: map['id']?.toString(),
      localOrderKey: map['local_order_key']?.toString(),
      threadId: map['thread_id']?.toString(),
      senderUserId: map['sender_user_id']?.toString(),
      senderRole: map['sender_role']?.toString(),
      senderName: map['sender_name']?.toString(),
      senderPhoto: map['sender_photo']?.toString(),
      text: map['text']?.toString(),
      attachments: (map['attachments'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                SupportAttachment.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList(),
      createdAt: _toDateTime(map['created_at']),
      updatedAt: _toDateTime(map['updated_at']),
    );
  }
}

DateTime? _toDateTime(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value;
  }
  return DateTime.tryParse(value.toString());
}
