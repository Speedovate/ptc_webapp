import 'dart:async';

import 'package:stacked/stacked.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/status.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/requests/booking.request.dart';
import 'package:webapp/requests/status.request.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/repositories/interfaces/booking_repository.dart';
import 'package:webapp/repositories/interfaces/status_form_repository.dart';

class RoleAssignedHomeViewModel extends BaseViewModel {
  RoleAssignedHomeViewModel({
    AuthRepository? authRepository,
    BookingRepository? bookingRepository,
    StatusFormRepository? statusRepository,
  }) : _authRepository = authRepository ?? AuthRequest.instance,
       _bookingRepository = bookingRepository ?? BookingRequest.instance,
       _statusRepository = statusRepository ?? StatusRequest.instance {
    assignedBookings = List<Booking>.from(_cachedAssignedBookings);
    currentUser = _cachedCurrentUser;
    errorMessage = _cachedErrorMessage;
    _usersById.addAll(_cachedUsersById);
    _statusesByKey.addAll(_cachedStatusesByKey);
  }

  final AuthRepository _authRepository;
  final BookingRepository _bookingRepository;
  final StatusFormRepository _statusRepository;
  StreamSubscription<List<Booking>>? _bookingsSubscription;
  static List<Booking> _cachedAssignedBookings = const [];
  static UserModel? _cachedCurrentUser;
  static String? _cachedErrorMessage;
  static Map<String, UserModel> _cachedUsersById = const {};
  static Map<String, Status> _cachedStatusesByKey = const {};

  static void clearCachedState() {
    _cachedAssignedBookings = const [];
    _cachedCurrentUser = null;
    _cachedErrorMessage = null;
    _cachedUsersById = const {};
    _cachedStatusesByKey = const {};
  }

  final Map<String, UserModel> _usersById = {};
  final Map<String, Status> _statusesByKey = {};

  List<Booking> assignedBookings = [];
  UserModel? currentUser;
  String? errorMessage;

  Future<void> load(UserModel user) async {
    setBusy(true);
    errorMessage = null;
    try {
      await _bookingRepository.initialize();
      final users = await _authRepository.getUsers();
      final statuses = await _statusRepository.getStatuses();
      final bookings = await _bookingRepository.getBookings();

      _usersById
        ..clear()
        ..addEntries(
          users
              .where((item) => (item.id ?? '').isNotEmpty)
              .map((item) => MapEntry(item.id!, item)),
        );
      _statusesByKey
        ..clear()
        ..addEntries(
          statuses
              .where((item) => (item.key ?? '').isNotEmpty)
              .map((item) => MapEntry(item.key!, item)),
        );

      currentUser = _usersById[user.id] ?? user;
      await _bookingsSubscription?.cancel();
      _applyAssignedBookings(bookings);
      _bookingsSubscription = _bookingRepository.watchBookings().listen((
        liveBookings,
      ) {
        _applyAssignedBookings(liveBookings);
        notifyListeners();
      });
      _cachedCurrentUser = currentUser;
      _cachedErrorMessage = null;
      _cachedUsersById = Map<String, UserModel>.from(_usersById);
      _cachedStatusesByKey = Map<String, Status>.from(_statusesByKey);
    } catch (_) {
      errorMessage = 'Failed to load assigned bookings.';
      _cachedErrorMessage = errorMessage;
    } finally {
      setBusy(false);
      notifyListeners();
    }
  }

  void _applyAssignedBookings(List<Booking> bookings) {
    final currentUserId = currentUser?.id ?? '';
    final normalizedRole = (currentUser?.role ?? '').trim().toLowerCase();
    assignedBookings = bookings.where((booking) {
      final statusKey = (booking.clientStatus ?? '').trim().toLowerCase();
      if (statusKey == 'cancelled' || statusKey == 'delivered') {
        return false;
      }
      return switch (normalizedRole) {
        'driver' => booking.driver?.id == currentUserId,
        'helper' => booking.helper?.id == currentUserId,
        _ => false,
      };
    }).toList();
    assignedBookings.sort((left, right) {
      final leftDate = left.createdAt;
      final rightDate = right.createdAt;
      final dateComparison = _compareOldestFirst(leftDate, rightDate);
      if (dateComparison != 0) {
        return dateComparison;
      }
      final leftId = int.tryParse(left.id ?? '');
      final rightId = int.tryParse(right.id ?? '');
      if (leftId != null && rightId != null) {
        return leftId.compareTo(rightId);
      }
      return (left.id ?? '').compareTo(right.id ?? '');
    });
    _cachedAssignedBookings = List<Booking>.from(assignedBookings);
  }

  Future<UserModel?> setOnline(bool isOnline) async {
    final user = currentUser;
    if (user == null) {
      return null;
    }
    final savedUser = await _authRepository.saveUser(
      user.copyWith(isOnline: isOnline, updatedAt: DateTime.now()),
    );
    currentUser = savedUser;
    notifyListeners();
    return savedUser;
  }

  String clientName(Booking booking) =>
      _userName(booking.client?.id, 'Unknown client');

  String clientPhone(Booking booking) => _userPhone(booking.client?.id);

  String driverName(Booking booking) => _userName(booking.driver?.id, '-');

  String driverPhone(Booking booking) => _userPhone(booking.driver?.id);

  String helperName(Booking booking) => _userName(booking.helper?.id, '-');

  String helperPhone(Booking booking) => _userPhone(booking.helper?.id);

  String statusLabelForKey(String? statusKey) {
    final key = statusKey?.trim();
    if (key == null || key.isEmpty) {
      return '-';
    }
    final label = _statusesByKey[key]?.label?.trim();
    if (label != null && label.isNotEmpty) {
      return label;
    }
    return key
        .split('_')
        .where((part) => part.isNotEmpty)
        .map(
          (part) => part.length == 1
              ? part.toUpperCase()
              : '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  String _userName(String? userId, String fallback) {
    final user = _usersById[userId];
    final name = user?.name?.trim();
    return name?.isNotEmpty == true ? name! : fallback;
  }

  String _userPhone(String? userId) {
    final user = _usersById[userId];
    final phone = user?.phone?.trim();
    return phone?.isNotEmpty == true ? phone! : '-';
  }

  static int _compareOldestFirst(DateTime? left, DateTime? right) {
    if (left == null && right == null) {
      return 0;
    }
    if (left == null) {
      return 1;
    }
    if (right == null) {
      return -1;
    }
    return left.compareTo(right);
  }

  @override
  void dispose() {
    _bookingsSubscription?.cancel();
    super.dispose();
  }
}
