import 'package:webapp/utils/functions.dart';

const supportTopicBooking = 'booking';
const supportTopicAdmin = 'admin';
const supportTopicClient = 'client';
const supportTopicDriver = 'driver';
const supportTopicHelper = 'helper';
const supportTopicGeneral = 'general';

const supportTopicKeys = <String>[
  supportTopicBooking,
  supportTopicAdmin,
  supportTopicClient,
  supportTopicDriver,
  supportTopicHelper,
  supportTopicGeneral,
];

String supportTopicLabel(String? topicKey) {
  return switch ((topicKey ?? '').trim().toLowerCase()) {
    supportTopicBooking => 'Booking',
    supportTopicAdmin => 'Admin',
    supportTopicClient => 'Client',
    supportTopicDriver => 'Driver',
    supportTopicHelper => 'Helper',
    supportTopicGeneral => 'General',
    _ => 'Support',
  };
}

String supportRoleSectionLabel(String? role) {
  return switch (normalizeRoleKey(role)) {
    'admin' => 'Admins',
    'driver' => 'Drivers',
    'helper' => 'Helpers',
    'client' => 'Clients',
    _ => 'Others',
  };
}

class SupportAttachment {
  const SupportAttachment({
    this.name,
    this.downloadUrl,
    this.storagePath,
    this.mimeType,
    this.size,
    this.width,
    this.height,
  });

  final String? name;
  final String? downloadUrl;
  final String? storagePath;
  final String? mimeType;
  final int? size;
  final int? width;
  final int? height;

  bool get isImage {
    final normalizedMime = mimeType?.trim().toLowerCase() ?? '';
    if (normalizedMime.startsWith('image/')) {
      return true;
    }
    final normalizedName = name?.trim().toLowerCase() ?? '';
    return normalizedName.endsWith('.png') ||
        normalizedName.endsWith('.jpg') ||
        normalizedName.endsWith('.jpeg') ||
        normalizedName.endsWith('.gif') ||
        normalizedName.endsWith('.webp') ||
        normalizedName.endsWith('.bmp');
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'download_url': downloadUrl,
      'storage_path': storagePath,
      'mime_type': mimeType,
      'size': size,
      'width': width,
      'height': height,
    };
  }

  factory SupportAttachment.fromMap(Map<String, dynamic> map) {
    return SupportAttachment(
      name: map['name']?.toString(),
      downloadUrl: map['download_url']?.toString(),
      storagePath: map['storage_path']?.toString(),
      mimeType: map['mime_type']?.toString(),
      size: _toInt(map['size']),
      width: _toInt(map['width']),
      height: _toInt(map['height']),
    );
  }
}

class SupportThread {
  const SupportThread({
    this.id,
    this.requesterUserId,
    this.requesterRole,
    this.requesterName,
    this.requesterPhoto,
    this.requesterParentClientId,
    this.topicKey,
    this.topicLabel,
    this.bookingId,
    this.bookingLabel,
    this.lastMessageText,
    this.lastMessageAt,
    this.lastSenderUserId,
    this.lastSenderRole,
    this.createdAt,
    this.updatedAt,
    this.isActive,
  });

  final String? id;
  final String? requesterUserId;
  final String? requesterRole;
  final String? requesterName;
  final String? requesterPhoto;
  final String? requesterParentClientId;
  final String? topicKey;
  final String? topicLabel;
  final String? bookingId;
  final String? bookingLabel;
  final String? lastMessageText;
  final DateTime? lastMessageAt;
  final String? lastSenderUserId;
  final String? lastSenderRole;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool? isActive;

  String get resolvedTopicLabel => topicLabel?.trim().isNotEmpty == true
      ? topicLabel!.trim()
      : supportTopicLabel(topicKey);

  bool get isBookingThread =>
      (topicKey ?? '').trim().toLowerCase() == supportTopicBooking;

  bool get hasConversation {
    return (lastMessageText?.trim().isNotEmpty == true) ||
        ((lastSenderUserId?.trim().isNotEmpty == true) &&
            (lastMessageAt != null));
  }

  SupportThread copyWith({
    String? id,
    String? requesterUserId,
    String? requesterRole,
    String? requesterName,
    String? requesterPhoto,
    String? requesterParentClientId,
    String? topicKey,
    String? topicLabel,
    String? bookingId,
    String? bookingLabel,
    String? lastMessageText,
    DateTime? lastMessageAt,
    String? lastSenderUserId,
    String? lastSenderRole,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isActive,
  }) {
    return SupportThread(
      id: id ?? this.id,
      requesterUserId: requesterUserId ?? this.requesterUserId,
      requesterRole: requesterRole ?? this.requesterRole,
      requesterName: requesterName ?? this.requesterName,
      requesterPhoto: requesterPhoto ?? this.requesterPhoto,
      requesterParentClientId:
          requesterParentClientId ?? this.requesterParentClientId,
      topicKey: topicKey ?? this.topicKey,
      topicLabel: topicLabel ?? this.topicLabel,
      bookingId: bookingId ?? this.bookingId,
      bookingLabel: bookingLabel ?? this.bookingLabel,
      lastMessageText: lastMessageText ?? this.lastMessageText,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastSenderUserId: lastSenderUserId ?? this.lastSenderUserId,
      lastSenderRole: lastSenderRole ?? this.lastSenderRole,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'requester_user_id': requesterUserId,
      'requester_role': requesterRole,
      'requester_name': requesterName,
      'requester_photo': requesterPhoto,
      'requester_parent_client_id': requesterParentClientId,
      'topic_key': topicKey,
      'topic_label': topicLabel,
      'booking_id': bookingId,
      'booking_label': bookingLabel,
      'last_message_text': lastMessageText,
      'last_message_at': lastMessageAt?.toIso8601String(),
      'last_sender_user_id': lastSenderUserId,
      'last_sender_role': lastSenderRole,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'is_active': isActive,
    };
  }

  factory SupportThread.fromMap(Map<String, dynamic> map) {
    return SupportThread(
      id: map['id']?.toString(),
      requesterUserId: map['requester_user_id']?.toString(),
      requesterRole: map['requester_role']?.toString(),
      requesterName: map['requester_name']?.toString(),
      requesterPhoto: map['requester_photo']?.toString(),
      requesterParentClientId: map['requester_parent_client_id']?.toString(),
      topicKey: map['topic_key']?.toString(),
      topicLabel: map['topic_label']?.toString(),
      bookingId: map['booking_id']?.toString(),
      bookingLabel: map['booking_label']?.toString(),
      lastMessageText: map['last_message_text']?.toString(),
      lastMessageAt: _toDateTime(map['last_message_at']),
      lastSenderUserId: map['last_sender_user_id']?.toString(),
      lastSenderRole: map['last_sender_role']?.toString(),
      createdAt: _toDateTime(map['created_at']),
      updatedAt: _toDateTime(map['updated_at']),
      isActive: map['is_active'] as bool? ?? true,
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

int? _toInt(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value.toString());
}
