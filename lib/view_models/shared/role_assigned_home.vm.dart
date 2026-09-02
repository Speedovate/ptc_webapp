import 'dart:async';

import 'package:stacked/stacked.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/chassis.dart';
import 'package:webapp/models/status.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/requests/booking.request.dart';
import 'package:webapp/requests/chassis.request.dart';
import 'package:webapp/requests/status.request.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/repositories/interfaces/booking_repository.dart';
import 'package:webapp/repositories/interfaces/status_form_repository.dart';
import 'package:webapp/services/app_warmup_service.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:webapp/utils/functions.dart';

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
    _hasLoadedOnce = _cachedHasLoadedOnce;
  }

  final AuthRepository _authRepository;
  final BookingRepository _bookingRepository;
  final StatusFormRepository _statusRepository;
  final RoleAccessService _roleAccessService = RoleAccessService.instance;
  final AppWarmupService _warmupService = AppWarmupService.instance;
  StreamSubscription<List<Booking>>? _bookingsSubscription;
  StreamSubscription<List<Chassis>>? _chassisSubscription;
  StreamSubscription<void>? _usersCacheUpdatesSubscription;
  StreamSubscription<void>? _statusCacheUpdatesSubscription;
  static List<Booking> _cachedAssignedBookings = const [];
  static UserModel? _cachedCurrentUser;
  static String? _cachedErrorMessage;
  static Map<String, UserModel> _cachedUsersById = const {};
  static Map<String, Status> _cachedStatusesByKey = const {};
  static bool _cachedHasLoadedOnce = false;

  static void clearCachedState() {
    _cachedAssignedBookings = const [];
    _cachedCurrentUser = null;
    _cachedErrorMessage = null;
    _cachedUsersById = const {};
    _cachedStatusesByKey = const {};
    _cachedHasLoadedOnce = false;
  }

  final Map<String, UserModel> _usersById = {};
  final Map<String, Status> _statusesByKey = {};

  List<Booking> assignedBookings = [];
  List<Booking> _latestBookings = const [];
  Set<String> _returnBookingIds = const {};
  UserModel? currentUser;
  String? errorMessage;
  String busyMessage = 'Loading, please wait ...';
  bool _isRealtimeRefreshing = false;
  bool _hasLoadedOnce = false;

  Future<void> load(UserModel user) async {
    _log(
      'load start loggedIn=${user.id != null} user=${user.id ?? "-"} role=${user.role ?? "-"} visiblePrimary=${assignedBookings.isNotEmpty || _cachedAssignedBookings.isNotEmpty || currentUser != null || _cachedCurrentUser != null || _usersById.isNotEmpty || _cachedUsersById.isNotEmpty || _statusesByKey.isNotEmpty || _cachedStatusesByKey.isNotEmpty}',
    );
    _ensureSupportingSubscriptions();
    busyMessage = 'Loading assigned bookings ...';
    final hasVisiblePrimaryData =
        assignedBookings.isNotEmpty ||
        _cachedAssignedBookings.isNotEmpty ||
        BookingRequest.hasResolvedBookings ||
        currentUser != null ||
        _cachedCurrentUser != null ||
        _usersById.isNotEmpty ||
        _cachedUsersById.isNotEmpty ||
        _statusesByKey.isNotEmpty ||
        _cachedStatusesByKey.isNotEmpty;
    final shouldShowLoadingState = !_hasLoadedOnce && !hasVisiblePrimaryData;
    if (shouldShowLoadingState) {
      setBusy(true);
      _log('overlay show section=assigned-home');
    }
    if (!shouldShowLoadingState) {
      _log('silent load only section=assigned-home');
    }
    errorMessage = null;
    try {
      if (BookingRequest.hasResolvedBookings && assignedBookings.isEmpty) {
        _applyAssignedBookings(BookingRequest.hydratedBookingsSnapshot);
        notifyListeners();
      }
      await _bookingRepository.initialize();
      final results = await Future.wait([
        _authRepository.getUsers(),
        _statusRepository.getStatuses(),
        if (BookingRequest.hasResolvedBookings)
          Future<List<Booking>>.value(BookingRequest.hydratedBookingsSnapshot)
        else
          _bookingRepository.getBookings(),
        ChassisRequest.instance.getChassis(),
      ]);
      final users = results[0] as List<UserModel>;
      final statuses = results[1] as List<Status>;
      final bookings = results[2] as List<Booking>;
      final chassis = results[3] as List<Chassis>;

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
      await _chassisSubscription?.cancel();
      _latestBookings = List<Booking>.from(bookings);
      _returnBookingIds = _returnBookingIdsFor(chassis, currentUser?.id);
      _applyAssignedBookings(bookings);
      _bookingsSubscription = _bookingRepository.watchBookings().listen((
        liveBookings,
      ) {
        _latestBookings = List<Booking>.from(liveBookings);
        _applyAssignedBookings(liveBookings);
        notifyListeners();
      });
      _chassisSubscription = ChassisRequest.instance.watchChassis().listen((
        liveChassis,
      ) {
        _returnBookingIds = _returnBookingIdsFor(liveChassis, currentUser?.id);
        _applyAssignedBookings(_latestBookings);
        notifyListeners();
      });
      _cachedCurrentUser = currentUser;
      _cachedErrorMessage = null;
      _cachedUsersById = Map<String, UserModel>.from(_usersById);
      _cachedStatusesByKey = Map<String, Status>.from(_statusesByKey);
      _hasLoadedOnce = true;
      _cachedHasLoadedOnce = true;
      _log(
        'load success user=${currentUser?.id ?? user.id ?? "-"} role=${currentUser?.role ?? user.role ?? "-"} bookings=${assignedBookings.length} users=${_usersById.length} statuses=${_statusesByKey.length}',
      );
      unawaited(_warmupService.warmUpForUser(currentUser));
    } catch (error) {
      _log(
        'load error user=${user.id ?? "-"} role=${user.role ?? "-"} error=$error',
      );
      errorMessage = userFacingErrorMessage(
        error,
        fallback: 'We could not load the assigned bookings right now.',
      );
      _cachedErrorMessage = errorMessage;
      _hasLoadedOnce = true;
      _cachedHasLoadedOnce = true;
    } finally {
      if (shouldShowLoadingState) {
        setBusy(false);
        _log('overlay hide section=assigned-home reason=load-finish');
      }
      _log(
        'load finish user=${currentUser?.id ?? user.id ?? "-"} role=${currentUser?.role ?? user.role ?? "-"} busy=$isBusy bookings=${assignedBookings.length} error=${errorMessage ?? "-"}',
      );
      notifyListeners();
    }
  }

  void _ensureSupportingSubscriptions() {
    _usersCacheUpdatesSubscription ??= AuthRequest.instance
        .watchUsersCacheUpdates()
        .listen((_) {
          unawaited(_reloadSupportingData());
        });
    _statusCacheUpdatesSubscription ??= StatusRequest.instance
        .watchStatusCacheUpdates()
        .listen((_) {
          unawaited(_reloadSupportingData());
        });
  }

  Future<void> _reloadSupportingData() async {
    if (_isRealtimeRefreshing || currentUser == null) {
      return;
    }
    _isRealtimeRefreshing = true;
    _log(
      'realtime reload start user=${currentUser?.id ?? "-"} role=${currentUser?.role ?? "-"}',
    );
    try {
      final results = await Future.wait<dynamic>([
        _authRepository.getUsers(),
        _statusRepository.getStatuses(),
      ]);
      final users = results[0] as List<UserModel>;
      final statuses = results[1] as List<Status>;
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
      currentUser = _usersById[currentUser?.id] ?? currentUser;
      _cachedCurrentUser = currentUser;
      _cachedUsersById = Map<String, UserModel>.from(_usersById);
      _cachedStatusesByKey = Map<String, Status>.from(_statusesByKey);
      _applyAssignedBookings(_latestBookings);
      _log(
        'realtime reload done user=${currentUser?.id ?? "-"} role=${currentUser?.role ?? "-"} bookings=${assignedBookings.length}',
      );
      notifyListeners();
    } catch (_) {
      // Keep current visible state if live support data refresh fails.
    } finally {
      _isRealtimeRefreshing = false;
    }
  }

  void _applyAssignedBookings(List<Booking> bookings) {
    final currentUserId = currentUser?.id ?? '';
    final normalizedRole = normalizeRoleKey(currentUser?.role);
    assignedBookings = bookings.where((booking) {
      final statusKey = (booking.clientStatus ?? '').trim().toLowerCase();
      if (statusKey == 'cancelled') {
        return false;
      }
      if (!_roleAccessService.isAssignedBookingRole(normalizedRole)) {
        return false;
      }
      return switch (normalizedRole) {
        'driver' =>
          statusKey == 'return'
              ? _returnBookingIds.contains(booking.id)
              : !Booking.isDeliveredWorkflowStatus(statusKey) &&
                    booking.driver?.id == currentUserId,
        'helper' =>
          !Booking.isDeliveredWorkflowStatus(statusKey) &&
              booking.helper?.id == currentUserId,
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
    if (!_roleAccessService.isOnlineEligibleRole(user.role)) {
      throw const AuthFailure(
        'Online availability is only available for Driver and Helper roles.',
      );
    }
    busyMessage = isOnline
        ? 'Turning availability on ...'
        : 'Turning availability off ...';
    setBusy(true);
    try {
      final savedUser = await _authRepository.saveUser(
        user.copyWith(isOnline: isOnline, updatedAt: DateTime.now()),
      );
      currentUser = savedUser;
      notifyListeners();
      return savedUser;
    } finally {
      setBusy(false);
    }
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

  @override
  void dispose() {
    _usersCacheUpdatesSubscription?.cancel();
    _statusCacheUpdatesSubscription?.cancel();
    _bookingsSubscription?.cancel();
    _chassisSubscription?.cancel();
    super.dispose();
  }

  Set<String> _returnBookingIdsFor(List<Chassis> chassis, String? userId) {
    final normalizedUserId = userId?.trim();
    if (normalizedUserId == null || normalizedUserId.isEmpty) {
      return const {};
    }
    return chassis
        .where(
          (item) =>
              item.currentStatus == Chassis.returning &&
              item.currentDriverId?.toString() == normalizedUserId &&
              item.currentBookingId != null,
        )
        .map((item) => item.currentBookingId.toString())
        .toSet();
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

  void _log(String message) {
    // Temporary debug logging removed.
  }
}
