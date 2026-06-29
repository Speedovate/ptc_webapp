import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:webapp/models/support_message.dart';
import 'package:webapp/models/support_thread.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/repositories/local/booking_storage_backend.dart';
import 'package:webapp/services/photo_storage_service.dart';
import 'package:webapp/services/support_storage_service.dart';
import 'package:webapp/utils/functions.dart';

class OfflineMediaSyncService {
  OfflineMediaSyncService({
    BookingStorageBackend? backend,
    FirebaseFirestore? firestore,
    PhotoStorageService? photoStorageService,
    SupportStorageService? supportStorageService,
  }) : _backend = backend ?? createBookingStorageBackend(),
       _firestore = firestore ?? FirebaseFirestore.instance,
       _photoStorageService = photoStorageService ?? PhotoStorageService.instance,
       _supportStorageService =
           supportStorageService ?? SupportStorageService.instance;

  static final OfflineMediaSyncService instance = OfflineMediaSyncService();

  static const _storageKey = 'offline_media_sync_queue_v1';
  static const _retryInterval = Duration(seconds: 20);

  final BookingStorageBackend _backend;
  final FirebaseFirestore _firestore;
  final PhotoStorageService _photoStorageService;
  final SupportStorageService _supportStorageService;

  bool _isInitialized = false;
  bool _isFlushing = false;
  Timer? _retryTimer;

  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      _firestore.collection('users');

  CollectionReference<Map<String, dynamic>> get _supportCollection =>
      _firestore.collection('support');

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }
    await _backend.initialize();
    _retryTimer ??= Timer.periodic(_retryInterval, (_) {
      unawaited(flushPendingOperations());
    });
    _isInitialized = true;
    unawaited(flushPendingOperations());
  }

  Future<QueuedUserMediaResult> queueUserPhotoUpload({
    required String userId,
    required String fieldKey,
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
    int? size,
    required String? originalValue,
  }) async {
    await initialize();
    final entry = _OfflineMediaQueueEntry.userUpload(
      id: _nextEntryId('user_upload'),
      createdAtIso: DateTime.now().toUtc().toIso8601String(),
      userId: userId,
      fieldKey: fieldKey,
      fileName: fileName,
      mimeType: mimeType,
      size: size ?? bytes.length,
      bytesBase64: base64Encode(bytes),
      originalValue: originalValue,
    );
    final entries = await _readEntries();
    entries.add(entry);
    await _writeEntries(entries);
    unawaited(flushPendingOperations());

    return QueuedUserMediaResult(
      previewUrl: _dataUrlForBytes(
        bytes: bytes,
        mimeType: mimeType,
      ),
      queuedAt: DateTime.now(),
    );
  }

  Future<void> queueSupportMessage({
    required String threadId,
    required UserModel sender,
    String? text,
    required List<QueuedSupportAttachmentInput> attachments,
  }) async {
    await initialize();
    final entry = _OfflineMediaQueueEntry.supportMessage(
      id: _nextEntryId('support_message'),
      createdAtIso: DateTime.now().toUtc().toIso8601String(),
      threadId: threadId,
      senderUserId: normalizeId(sender.id),
      senderRole: sender.role,
      senderName: sender.name,
      senderPhoto: sender.photo,
      text: text?.trim(),
      attachments: attachments
          .map(
            (attachment) => _QueuedAttachmentPayload(
              bytesBase64: base64Encode(attachment.bytes),
              fileName: attachment.fileName,
              mimeType: attachment.mimeType,
              size: attachment.size ?? attachment.bytes.length,
            ),
          )
          .toList(),
    );
    final entries = await _readEntries();
    entries.add(entry);
    await _writeEntries(entries);
    unawaited(flushPendingOperations());
  }

  Future<void> flushPendingOperations() async {
    await initialize();
    if (_isFlushing) {
      return;
    }
    _isFlushing = true;
    try {
      final entries = await _readEntries();
      if (entries.isEmpty) {
        return;
      }

      final remaining = <_OfflineMediaQueueEntry>[];

      for (final entry in entries) {
        try {
          switch (entry.kind) {
            case _OfflineMediaQueueKind.userUpload:
              final applied = await _flushUserUpload(entry);
              if (!applied) {
                continue;
              }
            case _OfflineMediaQueueKind.supportMessage:
              await _flushSupportMessage(entry);
          }
        } catch (error) {
          final normalizedError = normalizeUserErrorText(
            error.toString(),
            fallback: 'Something went wrong. Please try again.',
          );
          if (_isRetryable(normalizedError)) {
            remaining.add(
              entry.copyWith(
                retryCount: entry.retryCount + 1,
                lastError: normalizedError,
              ),
            );
          }
        }
      }

      await _writeEntries(remaining);
    } finally {
      _isFlushing = false;
    }
  }

  Future<bool> _flushUserUpload(_OfflineMediaQueueEntry entry) async {
    final bytesBase64 = entry.bytesBase64;
    final userId = entry.userId;
    final fieldKey = entry.fieldKey;
    if (bytesBase64 == null || userId == null || fieldKey == null) {
      return true;
    }

    final uploaded = await _photoStorageService.uploadUserPhoto(
      bytes: base64Decode(bytesBase64),
      userId: userId,
      fieldKey: fieldKey,
      fileName: entry.fileName ?? 'photo',
      mimeType: entry.mimeType,
      size: entry.size,
    );

    var applied = false;
    await _firestore.runTransaction((transaction) async {
      final userRef = _usersCollection.doc(userId);
      final snapshot = await transaction.get(userRef);
      if (!snapshot.exists) {
        return;
      }
      final data = documentData(snapshot);
      final currentValue = fieldKey == 'license_photo'
          ? data['license']?.toString()
          : data['photo']?.toString();
      if ((currentValue ?? '') != (entry.originalValue ?? '')) {
        return;
      }

      final patch = <String, dynamic>{
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (fieldKey == 'license_photo') {
        patch['license'] = uploaded['download_url']?.toString();
      } else {
        patch['photo'] = uploaded['download_url']?.toString();
      }
      transaction.update(userRef, patch);
      applied = true;
    });

    if (!applied) {
      await _photoStorageService.deleteByPath(uploaded['storage_path']?.toString());
    }
    return true;
  }

  Future<void> _flushSupportMessage(_OfflineMediaQueueEntry entry) async {
    final threadId = entry.threadId;
    final senderUserId = entry.senderUserId;
    if (threadId == null || senderUserId == null) {
      return;
    }

    final uploadedAttachments = <SupportAttachment>[];
    for (final attachment in entry.attachments) {
      uploadedAttachments.add(
        await _supportStorageService.uploadAttachment(
          bytes: base64Decode(attachment.bytesBase64),
          threadId: threadId,
          fileName: attachment.fileName,
          mimeType: attachment.mimeType,
          size: attachment.size,
        ),
      );
    }

    final threadDoc = _supportCollection.doc(threadId);
    final messageDoc = threadDoc.collection('messages').doc();
    final now = DateTime.now().toUtc();
    final message = SupportMessage(
      id: messageDoc.id,
      threadId: threadId,
      senderUserId: senderUserId,
      senderRole: entry.senderRole,
      senderName: entry.senderName,
      senderPhoto: entry.senderPhoto,
      text: entry.text,
      attachments: uploadedAttachments,
      createdAt: now,
      updatedAt: now,
    );
    await messageDoc.set(message.toMap());

    final lastPreview =
        entry.text?.trim().isNotEmpty == true
            ? entry.text!.trim()
            : uploadedAttachments.length == 1
            ? 'Sent an attachment'
            : 'Sent ${uploadedAttachments.length} attachments';

    await threadDoc.set({
      'last_message_text': lastPreview,
      'last_message_at': now.toIso8601String(),
      'last_sender_user_id': senderUserId,
      'last_sender_role': entry.senderRole,
      'updated_at': now.toIso8601String(),
      'is_active': true,
    }, SetOptions(merge: true));
  }

  Future<List<_OfflineMediaQueueEntry>> _readEntries() async {
    final rawEntries = await _backend.readStringList(_storageKey);
    return rawEntries
        .map((item) => jsonDecode(item) as Map<String, dynamic>)
        .map(_OfflineMediaQueueEntry.fromMap)
        .toList();
  }

  Future<void> _writeEntries(List<_OfflineMediaQueueEntry> entries) {
    return _backend.writeStringList(
      _storageKey,
      entries.map((entry) => jsonEncode(entry.toMap())).toList(),
    );
  }

  bool _isRetryable(String message) {
    final normalized = message.trim().toLowerCase();
    return normalized.contains('internet connection') ||
        normalized.contains('temporarily unavailable') ||
        normalized.contains('request took too long') ||
        normalized.contains('try again');
  }

  String _nextEntryId(String prefix) {
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final randomSuffix = Random().nextInt(1 << 32).toRadixString(16);
    return '${prefix}_${timestamp}_$randomSuffix';
  }

  String _dataUrlForBytes({
    required Uint8List bytes,
    String? mimeType,
  }) {
    final resolvedMimeType =
        (mimeType?.trim().isNotEmpty == true)
            ? mimeType!.trim()
            : 'image/jpeg';
    return 'data:$resolvedMimeType;base64,${base64Encode(bytes)}';
  }
}

class QueuedSupportAttachmentInput {
  const QueuedSupportAttachmentInput({
    required this.bytes,
    required this.fileName,
    this.mimeType,
    this.size,
  });

  final Uint8List bytes;
  final String fileName;
  final String? mimeType;
  final int? size;
}

class QueuedUserMediaResult {
  const QueuedUserMediaResult({
    required this.previewUrl,
    required this.queuedAt,
  });

  final String previewUrl;
  final DateTime queuedAt;
}

enum _OfflineMediaQueueKind { userUpload, supportMessage }

class _OfflineMediaQueueEntry {
  const _OfflineMediaQueueEntry({
    required this.id,
    required this.kind,
    required this.createdAtIso,
    required this.retryCount,
    this.lastError,
    this.userId,
    this.fieldKey,
    this.fileName,
    this.mimeType,
    this.size,
    this.bytesBase64,
    this.originalValue,
    this.threadId,
    this.senderUserId,
    this.senderRole,
    this.senderName,
    this.senderPhoto,
    this.text,
    this.attachments = const [],
  });

  factory _OfflineMediaQueueEntry.userUpload({
    required String id,
    required String createdAtIso,
    required String userId,
    required String fieldKey,
    required String fileName,
    String? mimeType,
    int? size,
    required String bytesBase64,
    required String? originalValue,
  }) {
    return _OfflineMediaQueueEntry(
      id: id,
      kind: _OfflineMediaQueueKind.userUpload,
      createdAtIso: createdAtIso,
      retryCount: 0,
      userId: userId,
      fieldKey: fieldKey,
      fileName: fileName,
      mimeType: mimeType,
      size: size,
      bytesBase64: bytesBase64,
      originalValue: originalValue,
    );
  }

  factory _OfflineMediaQueueEntry.supportMessage({
    required String id,
    required String createdAtIso,
    required String threadId,
    required String? senderUserId,
    required String? senderRole,
    required String? senderName,
    required String? senderPhoto,
    required String? text,
    required List<_QueuedAttachmentPayload> attachments,
  }) {
    return _OfflineMediaQueueEntry(
      id: id,
      kind: _OfflineMediaQueueKind.supportMessage,
      createdAtIso: createdAtIso,
      retryCount: 0,
      threadId: threadId,
      senderUserId: senderUserId,
      senderRole: senderRole,
      senderName: senderName,
      senderPhoto: senderPhoto,
      text: text,
      attachments: attachments,
    );
  }

  final String id;
  final _OfflineMediaQueueKind kind;
  final String createdAtIso;
  final int retryCount;
  final String? lastError;
  final String? userId;
  final String? fieldKey;
  final String? fileName;
  final String? mimeType;
  final int? size;
  final String? bytesBase64;
  final String? originalValue;
  final String? threadId;
  final String? senderUserId;
  final String? senderRole;
  final String? senderName;
  final String? senderPhoto;
  final String? text;
  final List<_QueuedAttachmentPayload> attachments;

  _OfflineMediaQueueEntry copyWith({
    int? retryCount,
    String? lastError,
  }) {
    return _OfflineMediaQueueEntry(
      id: id,
      kind: kind,
      createdAtIso: createdAtIso,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
      userId: userId,
      fieldKey: fieldKey,
      fileName: fileName,
      mimeType: mimeType,
      size: size,
      bytesBase64: bytesBase64,
      originalValue: originalValue,
      threadId: threadId,
      senderUserId: senderUserId,
      senderRole: senderRole,
      senderName: senderName,
      senderPhoto: senderPhoto,
      text: text,
      attachments: attachments,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'kind': kind.name,
      'created_at': createdAtIso,
      'retry_count': retryCount,
      'last_error': lastError,
      'user_id': userId,
      'field_key': fieldKey,
      'file_name': fileName,
      'mime_type': mimeType,
      'size': size,
      'bytes_base64': bytesBase64,
      'original_value': originalValue,
      'thread_id': threadId,
      'sender_user_id': senderUserId,
      'sender_role': senderRole,
      'sender_name': senderName,
      'sender_photo': senderPhoto,
      'text': text,
      'attachments': attachments.map((item) => item.toMap()).toList(),
    };
  }

  factory _OfflineMediaQueueEntry.fromMap(Map<String, dynamic> map) {
    final kindName = map['kind']?.toString() ?? '';
    return _OfflineMediaQueueEntry(
      id: map['id']?.toString() ?? '',
      kind: kindName == _OfflineMediaQueueKind.supportMessage.name
          ? _OfflineMediaQueueKind.supportMessage
          : _OfflineMediaQueueKind.userUpload,
      createdAtIso: map['created_at']?.toString() ?? '',
      retryCount: map['retry_count'] is num
          ? (map['retry_count'] as num).toInt()
          : int.tryParse(map['retry_count']?.toString() ?? '') ?? 0,
      lastError: map['last_error']?.toString(),
      userId: map['user_id']?.toString(),
      fieldKey: map['field_key']?.toString(),
      fileName: map['file_name']?.toString(),
      mimeType: map['mime_type']?.toString(),
      size: map['size'] is num
          ? (map['size'] as num).toInt()
          : int.tryParse(map['size']?.toString() ?? ''),
      bytesBase64: map['bytes_base64']?.toString(),
      originalValue: map['original_value']?.toString(),
      threadId: map['thread_id']?.toString(),
      senderUserId: map['sender_user_id']?.toString(),
      senderRole: map['sender_role']?.toString(),
      senderName: map['sender_name']?.toString(),
      senderPhoto: map['sender_photo']?.toString(),
      text: map['text']?.toString(),
      attachments: (map['attachments'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => _QueuedAttachmentPayload.fromMap(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(),
    );
  }
}

class _QueuedAttachmentPayload {
  const _QueuedAttachmentPayload({
    required this.bytesBase64,
    required this.fileName,
    this.mimeType,
    this.size,
  });

  final String bytesBase64;
  final String fileName;
  final String? mimeType;
  final int? size;

  Map<String, dynamic> toMap() {
    return {
      'bytes_base64': bytesBase64,
      'file_name': fileName,
      'mime_type': mimeType,
      'size': size,
    };
  }

  factory _QueuedAttachmentPayload.fromMap(Map<String, dynamic> map) {
    return _QueuedAttachmentPayload(
      bytesBase64: map['bytes_base64']?.toString() ?? '',
      fileName: map['file_name']?.toString() ?? 'attachment',
      mimeType: map['mime_type']?.toString(),
      size: map['size'] is num
          ? (map['size'] as num).toInt()
          : int.tryParse(map['size']?.toString() ?? ''),
    );
  }
}
