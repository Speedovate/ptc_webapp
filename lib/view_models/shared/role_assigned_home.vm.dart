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
import 'package:webapp/utils/performance_trace.dart';

class RoleAssignedHomeViewModel extends BaseViewModel {
  RoleAssignedHomeViewModel({
    AuthRepository? authRepository,
    BookingRepository? bookingRepository,
    StatusFormRepository? statusRepository,
    ChassisRequest? chassisRequest,
    AppWarmupService? warmupService,
  }) : _authRepository = authRepository ?? AuthRequest.instance,
       _bookingRepository = bookingRepository ?? BookingRequest.instance,
       _statusRepository = statusRepository ?? StatusRequest.instance,
       _chassisRequest = chassisRequest ?? ChassisRequest.instance,
       _warmupService = warmupService ?? AppWarmupService.instance {
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
  final AppWarmupService _warmupService;
  final ChassisRequest _chassisRequest;
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
  int _loadEpoch = 0;
  bool _isDisposed = false;

  bool get hasResolvedInitialBookings => _hasLoadedOnce;
  bool _hasPrimarySnapshot = false;
  Completer<void>? _initialLoad;

  Future<void> load(UserModel user) async {
    final loadEpoch = ++_loadEpoch;
    _completeInitialLoad();
    final initialLoad = Completer<void>();
    _initialLoad = initialLoad;
    bool isCurrent() => !_isDisposed && loadEpoch == _loadEpoch;

    // Page caches must never carry another account's assignments into a frame.
    if (currentUser?.id != user.id || currentUser?.role != user.role) {
      assignedBookings = [];
      _usersById.clear();
      _statusesByKey.clear();
      _hasLoadedOnce = false;
      clearCachedState();
    }
    currentUser = user;
    _cachedCurrentUser = user;
    _latestBookings = [];
    _returnBookingIds = {};
    _hasPrimarySnapshot = false;
    errorMessage = null;
    busyMessage = 'Loading assigned bookings ...';
    setBusy(!_hasLoadedOnce);
    await _bookingsSubscription?.cancel();
    await _chassisSubscription?.cancel();
    if (!isCurrent()) return;
    _ensureSupportingSubscriptions();

    var bookingsReady = false;
    final needsChassis = normalizeRoleKey(user.role) == 'driver';
    var chassisReady = !needsChassis;
    var receivedBookingEvent = false;
    var receivedChassisEvent = false;

    void publish() {
      if (!isCurrent() || !bookingsReady || !chassisReady) return;
      _hasPrimarySnapshot = true;
      _applyAssignedBookings(_latestBookings);
      errorMessage = null;
      _cachedErrorMessage = null;
      _cachedCurrentUser = currentUser;
      if (!_hasLoadedOnce) setBusy(false);
      _hasLoadedOnce = true;
      _cachedHasLoadedOnce = true;
      if (!initialLoad.isCompleted) initialLoad.complete();
      notifyListeners();
    }

    void fail(Object error) {
      if (!isCurrent() || _hasPrimarySnapshot) return;
      errorMessage = userFacingErrorMessage(
        error,
        fallback: 'We could not load the assigned bookings right now.',
      );
      _cachedErrorMessage = errorMessage;
      _hasLoadedOnce = true;
      _cachedHasLoadedOnce = true;
      setBusy(false);
      if (!initialLoad.isCompleted) initialLoad.complete();
    }

    // Subscribe before fetching: a valid realtime result can release startup
    // even when the separate SDK get() is still pending.
    try {
      _bookingsSubscription = _bookingRepository.watchBookings().listen((
        bookings,
      ) {
        if (!isCurrent()) return;
        if (_bookingRepository is BookingRequest &&
            !BookingRequest.hasAuthoritativeBookings) {
          return;
        }
        receivedBookingEvent = true;
        bookingsReady = true;
        _latestBookings = List<Booking>.from(bookings);
        publish();
      }, onError: fail);
      if (needsChassis) {
        _chassisSubscription = _chassisRequest.watchChassis().listen((chassis) {
          // watchChassis initially yields its memory, which may still be an
          // unresolved empty list. It cannot confirm no return assignments.
          if (!isCurrent() || !_chassisRequest.hasResolvedChassis) return;
          receivedChassisEvent = true;
          chassisReady = true;
          _returnBookingIds = _returnBookingIdsFor(chassis, user.id);
          publish();
        }, onError: fail);
        unawaited(() async {
          try {
            final chassis = await _chassisRequest.getChassis();
            if (!isCurrent() || receivedChassisEvent) return;
            chassisReady = true;
            _returnBookingIds = _returnBookingIdsFor(chassis, user.id);
            publish();
          } catch (error) {
            if (!chassisReady) fail(error);
          }
        }());
      }
      unawaited(() async {
        try {
          await _bookingRepository.initialize();
          if (!isCurrent()) return;
          final bookings = await _bookingRepository.getBookings();
          if (!isCurrent() || receivedBookingEvent) return;
          bookingsReady = true;
          _latestBookings = List<Booking>.from(bookings);
          publish();
        } catch (error) {
          if (!bookingsReady) fail(error);
        }
      }());
    } catch (error) {
      fail(error);
    }

    await initialLoad.future;
    if (!isCurrent()) return;
    // Labels and catalogs enrich a usable home; they do not gate assignments.
    unawaited(_reloadSupportingData());
    unawaited(_warmupService.warmUpForUser(user).catchError((_, _) {}));
  }

  void _completeInitialLoad() {
    final pending = _initialLoad;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  void _ensureSupportingSubscriptions() {
    if (_authRepository is AuthRequest) {
      _usersCacheUpdatesSubscription ??= _authRepository
          .watchUsersCacheUpdates()
          .listen((_) {
            unawaited(_reloadSupportingData());
          });
    }
    if (_statusRepository is StatusRequest) {
      _statusCacheUpdatesSubscription ??= _statusRepository
          .watchStatusCacheUpdates()
          .listen((_) {
            unawaited(_reloadSupportingData());
          });
    }
  }

  Future<void> _reloadSupportingData() async {
    if (_isRealtimeRefreshing || currentUser == null) {
      return;
    }
    final loadEpoch = _loadEpoch;
    _isRealtimeRefreshing = true;
    _log(
      'realtime reload start user=${currentUser?.id ?? "-"} role=${currentUser?.role ?? "-"}',
    );
    try {
      final results = await Future.wait<dynamic>([
        _authRepository.getUsers(),
        _statusRepository.getStatuses(),
      ]);
      if (_isDisposed || loadEpoch != _loadEpoch) return;
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
      if (_hasPrimarySnapshot) _applyAssignedBookings(_latestBookings);
      _log(
        'realtime reload done user=${currentUser?.id ?? "-"} role=${currentUser?.role ?? "-"} bookings=${assignedBookings.length}',
      );
      notifyListeners();
    } catch (_) {
      // Keep current visible state if live support data refresh fails.
    } finally {
      _isRealtimeRefreshing = false;
      if (!_isDisposed && loadEpoch != _loadEpoch && _hasPrimarySnapshot) {
        unawaited(_reloadSupportingData());
      }
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
      _log('availability skipped reason=no-current-user');
      return null;
    }
    if (!_roleAccessService.isOnlineEligibleRole(user.role)) {
      throw const AuthFailure(
        'Online availability is only available for Driver and Helper roles.',
      );
    }
    if (user.isActive != true) {
      throw const AuthFailure(
        'Your account must be active before you can change availability.',
      );
    }
    _log(
      'availability save start user=${user.id ?? "-"} role=${user.role ?? "-"} from=${user.isOnline ?? false} to=$isOnline',
    );
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
      _log(
        'availability save success user=${savedUser.id ?? "-"} persisted=${savedUser.isOnline ?? false}',
      );
      return savedUser;
    } catch (error) {
      _log('availability save error user=${user.id ?? "-"} error=$error');
      rethrow;
    } finally {
      setBusy(false);
      _log('availability save finish user=${user.id ?? "-"} busy=$isBusy');
    }
  }

  String clientName(Booking booking) =>
      _userName(booking.client?.id, 'Loading ...');

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
    _isDisposed = true;
    _loadEpoch++;
    _completeInitialLoad();
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
              item.driverReferenceId?.toString() == normalizedUserId &&
              item.bookingReferenceId != null,
        )
        .map((item) => item.bookingReferenceId.toString())
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
    PerformanceTrace.event('assigned-home-vm', message);
  }
}
