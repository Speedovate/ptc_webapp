import 'dart:async';
import 'package:webapp/widgets/shared/app_snackbar.dart';
import 'package:webapp/services/support_alert_deduplicator.dart';

import 'package:audioplayers/audioplayers.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/support_thread.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/booking.request.dart';
import 'package:webapp/requests/support.request.dart';
import 'package:webapp/utils/functions.dart';

/// Plays one foreground sound for a new relevant booking or incoming chat.
/// The first snapshot is always a silent baseline, including persisted data.
class BookingChatAlertService {
  BookingChatAlertService._();

  static final BookingChatAlertService instance = BookingChatAlertService._();

  final AudioPlayer _player = AudioPlayer();
  final _supportAlerts = SupportAlertDeduplicator();
  StreamSubscription<List<Booking>>? _bookingsSubscription;
  StreamSubscription<List<SupportThread>>? _threadsSubscription;
  final Set<String> _knownRelevantBookingIds = <String>{};
  final Map<String, String> _knownAssignmentSignatures = <String, String>{};
  final Map<String, String> _knownThreadSignatures = <String, String>{};
  String? _activeSessionKey;
  String? _userId;
  String? _role;
  DateTime? _sessionStartedAt;
  bool _hasBookingBaseline = false;
  bool _hasThreadBaseline = false;

  Future<void> startForUser(UserModel? user) async {
    final userId = normalizeId(user?.id);
    final role = normalizeRoleKey(user?.role);
    if (userId == null || role.isEmpty) {
      await stop();
      return;
    }

    final sessionKey = '$userId:$role';
    if (_activeSessionKey == sessionKey &&
        _bookingsSubscription != null &&
        _threadsSubscription != null) {
      return;
    }

    await stop();
    _activeSessionKey = sessionKey;
    _userId = userId;
    _role = role;
    _sessionStartedAt = DateTime.now().toUtc();
    _bookingsSubscription = BookingRequest.instance.watchBookings().listen(
      _handleBookings,
    );
    _threadsSubscription = _watchThreadsForRole(
      userId,
      role,
    ).listen(_handleThreads);
  }

  Future<void> stop() async {
    await _bookingsSubscription?.cancel();
    await _threadsSubscription?.cancel();
    _bookingsSubscription = null;
    _threadsSubscription = null;
    _activeSessionKey = null;
    _userId = null;
    _role = null;
    _sessionStartedAt = null;
    _hasBookingBaseline = false;
    _hasThreadBaseline = false;
    _knownRelevantBookingIds.clear();
    _knownAssignmentSignatures.clear();
    _knownThreadSignatures.clear();
    _supportAlerts.clear();
    try {
      await _player.stop();
    } catch (_) {
      // Browser audio is optional until a user gesture has occurred.
    }
  }

  Stream<List<SupportThread>> _watchThreadsForRole(String userId, String role) {
    if (role == 'admin' || role == 'manager' || role == 'dispatcher') {
      return SupportRequest.instance.watchAllThreads();
    }
    return SupportRequest.instance.watchThreadsForUser(userId);
  }

  void _handleBookings(List<Booking> bookings) {
    if (!BookingRequest.hasAuthoritativeBookings) {
      return;
    }
    final userId = _userId;
    final role = _role;
    if (userId == null || role == null) {
      return;
    }
    final relevantIds = bookings
        .where((booking) => _isRelevantBooking(booking, userId, role))
        .map((booking) => normalizeId(booking.id))
        .whereType<String>()
        .toSet();
    final assignmentSignatures = _assignmentSignatures(bookings, userId, role);

    if (!_hasBookingBaseline) {
      _knownRelevantBookingIds
        ..clear()
        ..addAll(relevantIds);
      _knownAssignmentSignatures
        ..clear()
        ..addAll(assignmentSignatures);
      _hasBookingBaseline = true;
      return;
    }

    final hasNewBooking = relevantIds.any(
      (bookingId) => !_knownRelevantBookingIds.contains(bookingId),
    );
    _knownRelevantBookingIds
      ..clear()
      ..addAll(relevantIds);
    final hasNewAssignment = assignmentSignatures.entries.any(
      (entry) => _knownAssignmentSignatures[entry.key] != entry.value,
    );
    _knownAssignmentSignatures
      ..clear()
      ..addAll(assignmentSignatures);
    if (hasNewAssignment) {
      // Booking assignment uses the same foreground sound as a chassis check.
      unawaited(_playAssignmentSound());
    } else if (hasNewBooking) {
      // Staff need the booking alert, not the incoming-chat sound.
      unawaited(_playAssignmentSound());
    }
  }

  Map<String, String> _assignmentSignatures(
    List<Booking> bookings,
    String userId,
    String role,
  ) {
    if (role != 'client' && role != 'driver' && role != 'helper') {
      return const <String, String>{};
    }

    final signatures = <String, String>{};
    for (final booking in bookings) {
      if (normalizeRoleKey(booking.clientStatus) != 'assigned') {
        continue;
      }
      final isRecipient = switch (role) {
        'client' => normalizeId(booking.client?.id) == userId,
        'driver' => normalizeId(booking.driver?.id) == userId,
        'helper' => normalizeId(booking.helper?.id) == userId,
        _ => false,
      };
      final bookingId = normalizeId(booking.id);
      if (!isRecipient || bookingId == null) {
        continue;
      }
      signatures[bookingId] = [
        normalizeRoleKey(booking.clientStatus),
        normalizeId(booking.driver?.id) ?? '',
        normalizeId(booking.helper?.id) ?? '',
        normalizeId(booking.chassisId) ?? '',
      ].join('|');
    }
    return signatures;
  }

  bool _isRelevantBooking(Booking booking, String userId, String role) {
    final status = normalizeRoleKey(booking.clientStatus);
    if (status == 'cancelled') {
      return false;
    }
    return switch (role) {
      'admin' || 'manager' || 'dispatcher' => status == 'pending',
      'driver' =>
        booking.driver?.id == userId &&
            !Booking.isDeliveredWorkflowStatus(status),
      'helper' =>
        booking.helper?.id == userId &&
            !Booking.isDeliveredWorkflowStatus(status),
      _ => false,
    };
  }

  void _handleThreads(List<SupportThread> threads) {
    final userId = _userId;
    final sessionStartedAt = _sessionStartedAt;
    if (userId == null || sessionStartedAt == null) {
      return;
    }
    final currentSignatures = <String, String>{};
    for (final thread in threads) {
      final threadId = normalizeId(thread.id);
      if (threadId == null || !thread.hasConversation) {
        continue;
      }
      currentSignatures[threadId] = _threadSignature(thread);
    }

    if (!_hasThreadBaseline) {
      _knownThreadSignatures
        ..clear()
        ..addAll(currentSignatures);
      _hasThreadBaseline = true;
      return;
    }

    final incomingMessages = threads.where((thread) {
      final threadId = normalizeId(thread.id);
      if (threadId == null || !thread.hasConversation) {
        return false;
      }
      final senderId = normalizeId(thread.lastSenderUserId);
      final messageAt = thread.lastMessageAt?.toUtc();
      return senderId != null &&
          senderId != userId &&
          messageAt != null &&
          !messageAt.isBefore(sessionStartedAt) &&
          _knownThreadSignatures[threadId] != _threadSignature(thread);
    }).toList();
    _knownThreadSignatures
      ..clear()
      ..addAll(currentSignatures);
    var shouldAlert = false;
    for (final thread in incomingMessages) {
      shouldAlert =
          _supportAlerts.accept(
            threadId: thread.id!,
            senderId: thread.lastSenderUserId!,
            messageAt: thread.lastMessageAt!,
            preview: thread.lastMessageText ?? '',
          ) ||
          shouldAlert;
    }
    if (shouldAlert) {
      _notifySupportMessage();
    }
  }

  void handleSupportPush(Map<String, dynamic> data) {
    if (_userId == null ||
        data['recipientId'] != _userId ||
        data['senderId'] == _userId) {
      return;
    }
    final threadId = normalizeId(data['threadId']?.toString());
    final senderId = normalizeId(data['senderId']?.toString());
    final at = DateTime.tryParse(data['messageAt']?.toString() ?? '');
    if (threadId == null || senderId == null || at == null) {
      return;
    }
    if (_supportAlerts.accept(
      threadId: threadId,
      senderId: senderId,
      messageAt: at,
      preview: data['preview']?.toString() ?? '',
    )) {
      _notifySupportMessage();
    }
  }

  void _notifySupportMessage() {
    AppSnackbar.showSupportNotification();
    unawaited(_playChatSound());
  }

  String _threadSignature(SupportThread thread) {
    return '${thread.lastMessageAt?.toUtc().toIso8601String() ?? ''}|'
        '${normalizeId(thread.lastSenderUserId) ?? ''}|'
        '${thread.lastMessageText ?? ''}';
  }

  Future<void> _playChatSound() async {
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/sound.mp3'));
    } catch (_) {
      // Web browsers can block playback before a user interacts with the app.
    }
  }

  Future<void> _playAssignmentSound() async {
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/alert.mp3'));
    } catch (_) {
      // Web browsers can block playback before a user interacts with the app.
    }
  }
}
