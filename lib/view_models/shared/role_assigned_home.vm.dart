import 'package:stacked/stacked.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/status_definition.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/repositories/local/local_auth_repository.dart';
import 'package:webapp/repositories/local/local_booking_repository.dart';
import 'package:webapp/repositories/local/local_status_form_repository.dart';

class RoleAssignedHomeViewModel extends BaseViewModel {
  RoleAssignedHomeViewModel({AuthRepository? authRepository})
    : _authRepository = authRepository ?? LocalAuthRepository.instance,
      _bookingRepository = LocalBookingRepository.instance,
      _statusRepository = LocalStatusFormRepository.instance;

  final AuthRepository _authRepository;
  final LocalBookingRepository _bookingRepository;
  final LocalStatusFormRepository _statusRepository;

  final Map<String, UserModel> _usersById = {};
  final Map<String, StatusDefinition> _statusesByKey = {};

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
      final currentUserId = currentUser?.id ?? '';
      final normalizedRole = (currentUser?.role ?? '').trim().toLowerCase();

      assignedBookings = bookings.where((booking) {
        final statusKey = (booking.clientStatus ?? '').trim().toLowerCase();
        if (statusKey == 'cancelled' || statusKey == 'delivered') {
          return false;
        }
        return switch (normalizedRole) {
          'driver' => booking.driverId == currentUserId,
          'helper' => booking.helperId == currentUserId,
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
    } catch (_) {
      errorMessage = 'Failed to load assigned bookings.';
    } finally {
      setBusy(false);
      notifyListeners();
    }
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
      _userName(booking.clientId, 'Unknown client');

  String clientPhone(Booking booking) => _userPhone(booking.clientId);

  String driverName(Booking booking) => _userName(booking.driverId, '-');

  String driverPhone(Booking booking) => _userPhone(booking.driverId);

  String helperName(Booking booking) => _userName(booking.helperId, '-');

  String helperPhone(Booking booking) => _userPhone(booking.helperId);

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
}
