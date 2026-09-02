import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/booking.request.dart';
import 'package:webapp/utils/functions.dart';

/// Plays one foreground alert when a chassis booking newly reaches `check`.
/// Existing check records seed the baseline and never replay on app startup.
class ChassisCheckAlertService {
  ChassisCheckAlertService._();

  static final ChassisCheckAlertService instance = ChassisCheckAlertService._();

  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<List<Booking>>? _bookingsSubscription;
  final Set<String> _knownCheckBookingIds = <String>{};
  String? _activeSessionKey;
  bool _hasAuthoritativeBaseline = false;

  Future<void> startForUser(UserModel? user) async {
    final userId = normalizeId(user?.id);
    final role = normalizeRoleKey(user?.role);
    if (userId == null || !_canReceiveAlert(role)) {
      await stop();
      return;
    }

    final sessionKey = '$userId:$role';
    if (_activeSessionKey == sessionKey && _bookingsSubscription != null) {
      return;
    }

    await stop();
    _activeSessionKey = sessionKey;
    _bookingsSubscription = BookingRequest.instance.watchBookings().listen(
      _handleBookings,
    );
  }

  Future<void> stop() async {
    await _bookingsSubscription?.cancel();
    _bookingsSubscription = null;
    _activeSessionKey = null;
    _hasAuthoritativeBaseline = false;
    _knownCheckBookingIds.clear();
    try {
      await _player.stop();
    } catch (_) {
      // Audio is optional. Some browsers do not expose the player channel
      // until a user gesture has occurred.
    }
  }

  bool _canReceiveAlert(String role) {
    return role == 'admin' || role == 'manager' || role == 'dispatcher';
  }

  void _handleBookings(List<Booking> bookings) {
    // Ignore provisional cache emissions so the first authoritative snapshot
    // becomes the silent baseline after a page/app restart.
    if (!BookingRequest.hasAuthoritativeBookings) {
      return;
    }

    final currentCheckIds = bookings
        .where(_isChassisCheckBooking)
        .map((booking) => normalizeId(booking.id))
        .whereType<String>()
        .toSet();

    if (!_hasAuthoritativeBaseline) {
      _knownCheckBookingIds
        ..clear()
        ..addAll(currentCheckIds);
      _hasAuthoritativeBaseline = true;
      return;
    }

    final hasNewCheck = currentCheckIds.any(
      (bookingId) => !_knownCheckBookingIds.contains(bookingId),
    );
    _knownCheckBookingIds
      ..clear()
      ..addAll(currentCheckIds);
    if (hasNewCheck) {
      unawaited(_playAlert());
    }
  }

  bool _isChassisCheckBooking(Booking booking) {
    return normalizeId(booking.chassisId) != null &&
        normalizeRoleKey(booking.clientStatus) == 'check';
  }

  Future<void> _playAlert() async {
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/alert.mp3'));
    } catch (_) {
      // Web browsers can block audio until the user has interacted with the
      // page; the booking status remains available even in that case.
    }
  }
}
