import 'dart:async';

import 'package:stacked/stacked.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/status.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/requests/booking.request.dart';
import 'package:webapp/requests/status.request.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/repositories/interfaces/booking_repository.dart';
import 'package:webapp/repositories/interfaces/status_form_repository.dart';
import 'package:webapp/repositories/interfaces/vehicle_catalog_repository.dart';
import 'package:webapp/services/app_warmup_service.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:webapp/utils/functions.dart';

class AdminBookingsViewModel extends BaseViewModel {
  static const Duration _loadStepTimeout = Duration(seconds: 8);
  AdminBookingsViewModel({
    AuthRepository? authRepository,
    BookingRepository? bookingRepository,
    StatusFormRepository? statusRepository,
    VehicleCatalogRepository? vehicleCatalogRepository,
  }) : _authRepository = authRepository ?? AuthRequest.instance,
       _bookingRepository = bookingRepository ?? BookingRequest.instance,
       _statusRepository = statusRepository ?? StatusRequest.instance,
       _vehicleCatalogRepository =
           vehicleCatalogRepository ?? VehicleRequest.instance {
    _bookings.addAll(_cachedBookings);
    _usersById.addAll(_cachedUsersById);
    _statusesByKey.addAll(_cachedStatusesByKey);
    _vehicleSizes = List<VehicleCatalogItem>.from(_cachedVehicleSizes);
    if (_usersById.isEmpty && AuthRequest.hasResolvedUsers) {
      _usersById.addEntries(
        AuthRequest.hydratedUsersSnapshot
            .where((user) => (user.id ?? '').isNotEmpty)
            .map((user) => MapEntry(user.id!, user)),
      );
      _cachedUsersById = Map<String, UserModel>.from(_usersById);
    }
    if (_statusesByKey.isEmpty && StatusRequest.hasResolvedStatuses) {
      _statusesByKey.addEntries(
        StatusRequest.hydratedStatusesSnapshot
            .where((status) => (status.key ?? '').isNotEmpty)
            .map((status) => MapEntry(status.key!, status)),
      );
      _cachedStatusesByKey = Map<String, Status>.from(_statusesByKey);
    }
    if (_vehicleSizes.isEmpty && VehicleRequest.hasResolvedSizes) {
      _vehicleSizes = List<VehicleCatalogItem>.from(
        VehicleRequest.hydratedSizesSnapshot,
      );
      _cachedVehicleSizes = List<VehicleCatalogItem>.from(_vehicleSizes);
    }
    errorMessage = _cachedErrorMessage;
    _hasLoadedOnce = _cachedHasLoadedOnce;
  }

  final AuthRepository _authRepository;
  final BookingRepository _bookingRepository;
  final StatusFormRepository _statusRepository;
  final VehicleCatalogRepository _vehicleCatalogRepository;
  final RoleAccessService _roleAccessService = RoleAccessService.instance;
  final AppWarmupService _warmupService = AppWarmupService.instance;
  StreamSubscription<List<Booking>>? _bookingsSubscription;
  StreamSubscription<void>? _usersCacheUpdatesSubscription;
  StreamSubscription<void>? _statusCacheUpdatesSubscription;
  StreamSubscription<void>? _catalogCacheUpdatesSubscription;
  Future<void>? _activeLoadFuture;
  bool _isRealtimeRefreshing = false;
  static List<Booking> _cachedBookings = const [];
  static Map<String, UserModel> _cachedUsersById = const {};
  static Map<String, Status> _cachedStatusesByKey = const {};
  static List<VehicleCatalogItem> _cachedVehicleSizes = const [];
  static String? _cachedErrorMessage;
  static bool _cachedHasLoadedOnce = false;

  static void clearCachedState() {
    _cachedBookings = const [];
    _cachedUsersById = const {};
    _cachedStatusesByKey = const {};
    _cachedVehicleSizes = const [];
    _cachedErrorMessage = null;
    _cachedHasLoadedOnce = false;
  }

  final List<Booking> _bookings = [];
  final Map<String, UserModel> _usersById = {};
  final Map<String, Status> _statusesByKey = {};
  List<VehicleCatalogItem> _vehicleSizes = const [];
  String _searchQuery = '';
  String _statusFilter = 'All';
  DateTime? _startDate;
  DateTime? _endDate;
  DateTime? _updatedStartDate;
  DateTime? _updatedEndDate;
  String? errorMessage;
  String _busyMessage = 'Loading, please wait ...';
  bool _hasLoadedOnce = false;

  List<Booking> get bookings => List.unmodifiable(_bookings);
  String get searchQuery => _searchQuery;
  String get statusFilter => _statusFilter;
  DateTime? get startDate => _startDate;
  DateTime? get endDate => _endDate;
  DateTime? get updatedStartDate => _updatedStartDate;
  DateTime? get updatedEndDate => _updatedEndDate;
  String get busyMessage => _busyMessage;
  bool get hasResolvedInitialBookings => _hasLoadedOnce;
  List<String> get statusOptions => [
    'All',
    if (_bookings.any(
      (booking) =>
          (booking.localSyncStatus ?? '').trim().toLowerCase() == 'queued',
    ))
      'Queued',
    ..._statusesByKey.values
        .map((status) => status.label?.trim())
        .whereType<String>()
        .where((label) => label.isNotEmpty)
        .toSet(),
  ];

  Future<void> load() async {
    final existingLoad = _activeLoadFuture;
    if (existingLoad != null) {
      _log('load join-inflight');
      await existingLoad;
      return;
    }
    final loadFuture = _loadInternal();
    _activeLoadFuture = loadFuture;
    try {
      await loadFuture;
    } finally {
      if (identical(_activeLoadFuture, loadFuture)) {
        _activeLoadFuture = null;
      }
    }
  }

  Future<void> _loadInternal() async {
    _ensureSupportingSubscriptions();
    _busyMessage = 'Loading bookings ...';
    var hasSharedBookings = BookingRequest.hasAuthoritativeBookings;
    final hasVisiblePrimaryData =
        _bookings.isNotEmpty || _cachedBookings.isNotEmpty || hasSharedBookings;
    final shouldShowLoadingState = !_hasLoadedOnce && !hasVisiblePrimaryData;
    if (shouldShowLoadingState) {
      setBusy(true);
      _log('overlay show section=bookings');
    }
    _log(
      'load start visibleBookings=${!shouldShowLoadingState} cachedBookings=${_cachedBookings.length} localBookings=${_bookings.length} sharedBookings=$hasSharedBookings',
    );
    if (!shouldShowLoadingState) {
      _log('silent load only section=bookings');
    }
    errorMessage = null;
    try {
      if (hasSharedBookings && _bookings.isEmpty) {
        _applyBookings(BookingRequest.hydratedBookingsSnapshot);
        notifyListeners();
      }
      await _bookingRepository.initialize();
      await _ensureBookingsSubscription();
      hasSharedBookings = BookingRequest.hasAuthoritativeBookings;
      if (!hasSharedBookings) {
        // Dashboard owns the shared booking read. This page subscribes only,
        // avoiding another request whenever the menu is opened.
      } else {
        _log(
          'primary bookings reused shared count=${BookingRequest.hydratedBookingsSnapshot.length}',
        );
      }

      // Supporting catalogs populate silently and must not extend the booking
      // list's visible loading state.
      unawaited(_reloadSupportingData());
      if (hasSharedBookings) {
        _markInitialBookingsResolved();
      }
      _cachedErrorMessage = null;
    } catch (error) {
      _log('load error error=$error');
      errorMessage = userFacingErrorMessage(
        error,
        fallback: 'We could not load the bookings right now.',
      );
      _cachedErrorMessage = errorMessage;
      _markInitialBookingsResolved();
    } finally {
      if (shouldShowLoadingState && _hasLoadedOnce) {
        setBusy(false);
        _log('overlay hide section=bookings reason=load-finish');
      }
      _log(
        'load finish busy=$isBusy bookings=${_bookings.length} users=${_usersById.length} statuses=${_statusesByKey.length} sizes=${_vehicleSizes.length} error=${errorMessage ?? "-"}',
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
    _catalogCacheUpdatesSubscription ??= VehicleRequest.instance
        .watchCatalogCacheUpdates()
        .listen((_) {
          unawaited(_reloadSupportingData());
        });
  }

  Future<void> _reloadSupportingData() async {
    if (_isRealtimeRefreshing) {
      _log('supporting reload skipped already-running');
      return;
    }
    _isRealtimeRefreshing = true;
    _log('supporting reload start');
    try {
      final results = await Future.wait<dynamic>([
        _loadUsersSafe(),
        _loadStatusesSafe(),
        _loadVehicleSizesSafe(),
      ]);
      final users = results[0] as List<UserModel>;
      final statuses = results[1] as List<Status>;
      _vehicleSizes = results[2] as List<VehicleCatalogItem>;
      _usersById
        ..clear()
        ..addEntries(
          users
              .where((user) => (user.id ?? '').isNotEmpty)
              .map((user) => MapEntry(user.id!, user)),
        );
      _statusesByKey
        ..clear()
        ..addEntries(
          statuses
              .where((status) => (status.key ?? '').isNotEmpty)
              .map((status) => MapEntry(status.key!, status)),
        );
      _cachedUsersById = Map<String, UserModel>.from(_usersById);
      _cachedStatusesByKey = Map<String, Status>.from(_statusesByKey);
      _cachedVehicleSizes = List<VehicleCatalogItem>.from(_vehicleSizes);
      _log(
        'supporting reload done users=${_usersById.length} statuses=${_statusesByKey.length} sizes=${_vehicleSizes.length}',
      );
      notifyListeners();
    } catch (_) {
      // Keep current visible state if live support data refresh fails.
    } finally {
      _isRealtimeRefreshing = false;
    }
  }

  Future<void> _ensureBookingsSubscription() async {
    if (_bookingsSubscription != null) {
      return;
    }
    _bookingsSubscription = _bookingRepository.watchBookings().listen((
      bookings,
    ) {
      if (!BookingRequest.hasAuthoritativeBookings) {
        // Wait for the first server-confirmed snapshot instead of briefly
        // rendering an empty list from the provisional local cache.
        return;
      }
      _applyBookings(bookings);
      errorMessage = null;
      _markInitialBookingsResolved();
      if (isBusy) {
        setBusy(false);
      }
      notifyListeners();
    });
  }

  void _markInitialBookingsResolved() {
    if (_hasLoadedOnce) {
      return;
    }
    _hasLoadedOnce = true;
    _cachedHasLoadedOnce = true;
  }

  Future<List<UserModel>> _loadUsersSafe() async {
    try {
      await _warmupService.warmUsers();
      final users = await _authRepository.getUsers().timeout(
        _loadStepTimeout,
        onTimeout: () => List<UserModel>.from(_cachedUsersById.values),
      );
      return users;
    } catch (_) {
      return List<UserModel>.from(_cachedUsersById.values);
    }
  }

  Future<List<Status>> _loadStatusesSafe() async {
    try {
      await _warmupService.warmStatuses();
      final statuses = await _statusRepository.getStatuses().timeout(
        _loadStepTimeout,
        onTimeout: () => List<Status>.from(_cachedStatusesByKey.values),
      );
      return statuses;
    } catch (_) {
      return List<Status>.from(_cachedStatusesByKey.values);
    }
  }

  Future<List<VehicleCatalogItem>> _loadVehicleSizesSafe() async {
    try {
      await _warmupService.warmVehicleSizes();
      final sizes = await _vehicleCatalogRepository.getSizes().timeout(
        _loadStepTimeout,
        onTimeout: () => List<VehicleCatalogItem>.from(_cachedVehicleSizes),
      );
      return sizes;
    } catch (_) {
      return List<VehicleCatalogItem>.from(_cachedVehicleSizes);
    }
  }

  void _applyBookings(List<Booking> bookings) {
    _bookings
      ..clear()
      ..addAll(bookings);
    _cachedBookings = List<Booking>.from(_bookings);
    _log(
      'apply bookings count=${_bookings.length} ids=${_bookings.map((booking) => normalizeId(booking.id) ?? "-").join(",")} statuses=${_bookings.map((booking) => booking.clientStatus?.trim().toLowerCase() ?? "-").join(",")}',
    );
  }

  void ingestSubmittedBooking(Booking booking) {
    final bookingId = (booking.id ?? '').trim();
    if (bookingId.isEmpty) {
      return;
    }
    final existingIndex = _bookings.indexWhere(
      (item) => (item.id ?? '').trim() == bookingId,
    );
    if (existingIndex >= 0) {
      _bookings[existingIndex] = booking;
    } else {
      _bookings.insert(0, booking);
    }
    _bookings.sort((left, right) {
      final leftDate = left.updatedAt ?? left.createdAt;
      final rightDate = right.updatedAt ?? right.createdAt;
      if (leftDate == null && rightDate == null) {
        return (right.id ?? '').compareTo(left.id ?? '');
      }
      if (leftDate == null) {
        return 1;
      }
      if (rightDate == null) {
        return -1;
      }
      return rightDate.compareTo(leftDate);
    });
    _cachedBookings = List<Booking>.from(_bookings);
    notifyListeners();
  }

  @override
  void dispose() {
    _usersCacheUpdatesSubscription?.cancel();
    _statusCacheUpdatesSubscription?.cancel();
    _catalogCacheUpdatesSubscription?.cancel();
    _bookingsSubscription?.cancel();
    super.dispose();
  }

  void setSearchQuery(String value) {
    if (_searchQuery == value) {
      return;
    }
    _searchQuery = value;
    notifyListeners();
  }

  void _log(String message) {
    // Temporary debug logging removed.
  }

  void setStatusFilter(String value) {
    if (_statusFilter == value) {
      return;
    }
    _statusFilter = value;
    notifyListeners();
  }

  void clearFilters() {
    var changed = false;
    if (_statusFilter != 'All') {
      _statusFilter = 'All';
      changed = true;
    }
    if (_startDate != null) {
      _startDate = null;
      changed = true;
    }
    if (_endDate != null) {
      _endDate = null;
      changed = true;
    }
    if (_updatedStartDate != null) {
      _updatedStartDate = null;
      changed = true;
    }
    if (_updatedEndDate != null) {
      _updatedEndDate = null;
      changed = true;
    }
    if (changed) {
      notifyListeners();
    }
  }

  List<Booking> filteredBookings() {
    final query = _searchQuery.trim().toLowerCase();
    return bookings.where((booking) {
      final matchesStatus =
          _statusFilter == 'All' || clientStatusLabel(booking) == _statusFilter;
      if (!matchesStatus) {
        return false;
      }
      final createdAt = booking.createdAt;
      final matchesStartDate =
          _startDate == null ||
          (createdAt != null &&
              !_dateOnly(createdAt).isBefore(_dateOnly(_startDate!)));
      final matchesEndDate =
          _endDate == null ||
          (createdAt != null &&
              !_dateOnly(createdAt).isAfter(_dateOnly(_endDate!)));
      final updatedAt = booking.updatedAt;
      final matchesUpdatedStartDate =
          _updatedStartDate == null ||
          (updatedAt != null &&
              !_dateOnly(updatedAt).isBefore(_dateOnly(_updatedStartDate!)));
      final matchesUpdatedEndDate =
          _updatedEndDate == null ||
          (updatedAt != null &&
              !_dateOnly(updatedAt).isAfter(_dateOnly(_updatedEndDate!)));
      if (!matchesStartDate ||
          !matchesEndDate ||
          !matchesUpdatedStartDate ||
          !matchesUpdatedEndDate) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      final client = _usersById[booking.client?.id];
      final values = <String>[
        booking.id ?? '',
        booking.client?.id ?? '',
        booking.clientStatus ?? '',
        booking.driverStatus ?? '',
        booking.helperStatus ?? '',
        client?.name ?? '',
        client?.phone ?? '',
        booking.createdAt?.toIso8601String() ?? '',
        ..._flattenBookingOutputValues(booking.statusOutputs),
      ];
      return values.join(' ').toLowerCase().contains(query);
    }).toList();
  }

  void updateStartDate(DateTime? value) {
    _startDate = value;
    if (_startDate != null &&
        _endDate != null &&
        _endDate!.isBefore(_startDate!)) {
      _endDate = _startDate;
    }
    notifyListeners();
  }

  void updateEndDate(DateTime? value) {
    _endDate = value;
    if (_startDate != null &&
        _endDate != null &&
        _startDate!.isAfter(_endDate!)) {
      _startDate = _endDate;
    }
    notifyListeners();
  }

  void updateUpdatedStartDate(DateTime? value) {
    _updatedStartDate = value;
    if (_updatedStartDate != null &&
        _updatedEndDate != null &&
        _updatedEndDate!.isBefore(_updatedStartDate!)) {
      _updatedEndDate = _updatedStartDate;
    }
    notifyListeners();
  }

  void updateUpdatedEndDate(DateTime? value) {
    _updatedEndDate = value;
    if (_updatedStartDate != null &&
        _updatedEndDate != null &&
        _updatedStartDate!.isAfter(_updatedEndDate!)) {
      _updatedStartDate = _updatedEndDate;
    }
    notifyListeners();
  }

  String formatDate(DateTime? value) {
    if (value == null) {
      return 'All';
    }

    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$month/$day/${value.year}';
  }

  String clientName(Booking booking) {
    final client = _usersById[booking.client?.id];
    final name = client?.name?.trim();
    return name?.isNotEmpty == true ? name! : 'Unknown client';
  }

  String clientPhone(Booking booking) {
    final client = _usersById[booking.client?.id];
    final phone = client?.phone?.trim();
    return phone?.isNotEmpty == true ? phone! : '-';
  }

  String driverName(Booking booking) {
    final driver = _usersById[booking.driver?.id];
    final name = driver?.name?.trim();
    return name?.isNotEmpty == true ? name! : '-';
  }

  String driverPhone(Booking booking) {
    final driver = _usersById[booking.driver?.id];
    final phone = driver?.phone?.trim();
    return phone?.isNotEmpty == true ? phone! : '-';
  }

  String helperName(Booking booking) {
    final helper = _usersById[booking.helper?.id];
    final name = helper?.name?.trim();
    return name?.isNotEmpty == true ? name! : '-';
  }

  String helperPhone(Booking booking) {
    final helper = _usersById[booking.helper?.id];
    final phone = helper?.phone?.trim();
    return phone?.isNotEmpty == true ? phone! : '-';
  }

  String clientStatusLabel(Booking booking) {
    if ((booking.localSyncStatus ?? '').trim().toLowerCase() == 'queued') {
      return 'Queued';
    }
    return statusLabelForKey(booking.clientStatus);
  }

  List<Status> activeStatuses() {
    return _statusesByKey.values
        .where((status) => status.isActive ?? false)
        .toList()
      ..sort((left, right) {
        final leftId = left.id?.trim() ?? '';
        final rightId = right.id?.trim() ?? '';
        final leftNumeric = int.tryParse(leftId);
        final rightNumeric = int.tryParse(rightId);
        if (leftNumeric != null && rightNumeric != null) {
          return leftNumeric.compareTo(rightNumeric);
        }
        return leftId.compareTo(rightId);
      });
  }

  List<UserModel> roleUsers(String role) {
    final normalizedRole = role.trim().toLowerCase();
    if (!_roleAccessService.isOnlineEligibleRole(normalizedRole)) {
      return const [];
    }
    return _usersById.values
        .where(
          (user) =>
              (user.role ?? '').trim().toLowerCase() == normalizedRole &&
              (user.isActive ?? false) &&
              (user.isOnline ?? false),
        )
        .toList()
      ..sort((left, right) => (left.name ?? '').compareTo(right.name ?? ''));
  }

  List<VehicleCatalogItem> activeVehicleSizes() {
    return _vehicleSizes.where((size) => size.isActive != false).toList()
      ..sort((left, right) => (left.name ?? '').compareTo(right.name ?? ''));
  }

  Future<Booking> saveEditedBooking(Booking booking) async {
    _busyMessage = 'Saving booking ...';
    setBusy(true);
    try {
      final updatedBooking = booking.copyWith(updatedAt: DateTime.now());
      final saved = await _bookingRepository.saveBooking(updatedBooking);
      return saved;
    } catch (error) {
      rethrow;
    } finally {
      setBusy(false);
    }
  }

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

  List<UserModel> clientUsers() {
    final sourceUsers = _usersById.isNotEmpty
        ? _usersById.values
        : AuthRequest.hasResolvedUsers
        ? AuthRequest.hydratedUsersSnapshot
        : const <UserModel>[];
    return sourceUsers
        .where(
          (user) =>
              normalizeRoleKey(user.role) == 'client' &&
              (user.isActive ?? false),
        )
        .toList()
      ..sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
  }

  static List<String> _flattenBookingOutputValues(
    Map<String, dynamic>? outputs,
  ) {
    if (outputs == null || outputs.isEmpty) {
      return const [];
    }
    final values = <String>[];
    for (final value in outputs.values) {
      if (value is Map && value['fields'] is Map) {
        for (final fieldValue in (value['fields'] as Map).values) {
          if (fieldValue == null) {
            continue;
          }
          if (fieldValue is List) {
            values.add(fieldValue.join(' '));
          } else if (fieldValue is Map) {
            values.addAll(fieldValue.values.map((item) => item.toString()));
          } else {
            values.add(fieldValue.toString());
          }
        }
      }
    }
    return values;
  }

  static DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }
}
