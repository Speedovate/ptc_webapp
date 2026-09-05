import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:stacked/stacked.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/requests/booking.request.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/repositories/interfaces/booking_repository.dart';
import 'package:webapp/services/app_warmup_service.dart';
import 'package:webapp/utils/functions.dart';
import 'package:webapp/utils/performance_trace.dart';
import 'package:webapp/widgets/shared/booking_record_card.dart';

class AdminDashboardViewModel extends BaseViewModel {
  static const billingStatusAll = 'all';
  static const billingStatusBilled = 'billed';
  static const billingStatusUnbilled = 'unbilled';

  AdminDashboardViewModel({AuthRepository? authRepository})
    : _authRepository = authRepository ?? AuthRequest.instance,
      _bookingRepository = BookingRequest.instance {
    PerformanceTrace.event('admin-dashboard-vm', 'created');
    _completedBookings.addAll(_cachedCompletedBookings);
    _usersById.addAll(_cachedUsersById);
    _currentUser = _cachedCurrentUser;
    errorMessage = _cachedErrorMessage;
    _hasLoadedOnce = _cachedHasLoadedOnce;
    if (_completedBookings.isEmpty &&
        BookingRequest.hasResolvedBookings &&
        BookingRequest.hasAuthoritativeBookings) {
      _applyCompletedBookings(BookingRequest.hydratedBookingsSnapshot);
      _markInitialBookingsResolved();
    }
    _traceHandoff(
      'created localCompleted=${_completedBookings.length} '
      'pageCache=${_cachedCompletedBookings.length} '
      'shared=${BookingRequest.hydratedBookingCount} '
      'authoritative=${BookingRequest.hasAuthoritativeBookings} '
      'resolved=${BookingRequest.hasResolvedBookings}',
    );
  }

  final AuthRepository _authRepository;
  final BookingRepository _bookingRepository;
  final AppWarmupService _warmupService = AppWarmupService.instance;
  StreamSubscription<List<Booking>>? _bookingsSubscription;
  StreamSubscription<void>? _usersCacheUpdatesSubscription;
  Future<void>? _activeLoadFuture;
  bool _isRealtimeRefreshing = false;
  static List<Booking> _cachedCompletedBookings = const [];
  static Map<String, UserModel> _cachedUsersById = const {};
  static UserModel? _cachedCurrentUser;
  static String? _cachedErrorMessage;
  static bool _cachedHasLoadedOnce = false;
  static const Duration _loadStepTimeout = Duration(seconds: 8);

  static void clearCachedState() {
    _cachedCompletedBookings = const [];
    _cachedUsersById = const {};
    _cachedCurrentUser = null;
    _cachedErrorMessage = null;
    _cachedHasLoadedOnce = false;
  }

  final List<Booking> _completedBookings = [];
  final Map<String, UserModel> _usersById = {};
  UserModel? _currentUser;
  bool _hasLoadedOnce = false;

  List<Booking> get completedBookings => List.unmodifiable(_completedBookings);
  UserModel? get currentUser => _currentUser;
  bool get hasResolvedInitialBookings => _hasLoadedOnce;
  String? errorMessage;
  String busyMessage = 'Loading, please wait ...';
  String _searchQuery = '';
  DateTime? _startDate;
  DateTime? _endDate;
  DateTime? _createdStartDate;
  DateTime? _createdEndDate;
  DateTime? _updatedStartDate;
  DateTime? _updatedEndDate;
  String? _billingStatusFilter;
  bool _isExporting = false;
  int _exportTotalSteps = 0;
  int _exportCompletedSteps = 0;

  String get searchQuery => _searchQuery;
  DateTime? get startDate => _startDate;
  DateTime? get endDate => _endDate;
  DateTime? get createdStartDate => _createdStartDate;
  DateTime? get createdEndDate => _createdEndDate;
  DateTime? get updatedStartDate => _updatedStartDate;
  DateTime? get updatedEndDate => _updatedEndDate;
  String get billingStatusFilter => _billingStatusFilter ?? billingStatusAll;
  bool get isExporting => _isExporting;
  String get exportProgressLabel {
    if (!_isExporting || _exportTotalSteps <= 0) {
      return 'Export';
    }
    final percent = ((_exportCompletedSteps / _exportTotalSteps) * 100)
        .round()
        .clamp(0, 100);
    return '$percent%';
  }

  void beginExport(int totalSteps) {
    _isExporting = true;
    _exportTotalSteps = totalSteps <= 0 ? 1 : totalSteps;
    _exportCompletedSteps = 0;
    notifyListeners();
  }

  void advanceExport() {
    if (!_isExporting) {
      return;
    }
    if (_exportCompletedSteps < _exportTotalSteps) {
      _exportCompletedSteps += 1;
      notifyListeners();
    }
  }

  void completeExport() {
    if (!_isExporting) {
      return;
    }
    _exportCompletedSteps = _exportTotalSteps;
    notifyListeners();
  }

  void setExportProgress({
    required int completedSteps,
    required int totalSteps,
  }) {
    _isExporting = true;
    _exportTotalSteps = totalSteps <= 0 ? 1 : totalSteps;
    _exportCompletedSteps = completedSteps.clamp(0, _exportTotalSteps);
    notifyListeners();
  }

  void endExport() {
    if (!_isExporting && _exportTotalSteps == 0 && _exportCompletedSteps == 0) {
      return;
    }
    _isExporting = false;
    _exportTotalSteps = 0;
    _exportCompletedSteps = 0;
    notifyListeners();
  }

  void primeCurrentUser(UserModel? user) {
    if (user == null) {
      return;
    }
    final normalizedIncomingId = normalizeId(user.id);
    final normalizedCurrentId = normalizeId(_currentUser?.id);
    final roleChanged =
        normalizeRoleKey(_currentUser?.role) != normalizeRoleKey(user.role);
    final shouldUpdate =
        normalizedCurrentId != normalizedIncomingId ||
        roleChanged ||
        _currentUser == null;
    if (!shouldUpdate) {
      return;
    }
    _currentUser = user;
    _cachedCurrentUser = user;
    _log(
      'prime current user loggedIn=true user=${user.id ?? "-"} role=${user.role ?? "-"}',
    );
    notifyListeners();
  }

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
    final stopwatch = Stopwatch()..start();
    _ensureSupportingSubscriptions();
    busyMessage = 'Loading dashboard ...';
    var overlayHidden = false;
    var hasSharedBookings = BookingRequest.hasAuthoritativeBookings;
    final hasVisiblePrimaryData =
        _completedBookings.isNotEmpty ||
        _cachedCompletedBookings.isNotEmpty ||
        hasSharedBookings;
    final shouldShowLoadingState = !_hasLoadedOnce && !hasVisiblePrimaryData;
    _traceHandoff(
      'load start localCompleted=${_completedBookings.length} '
      'pageCache=${_cachedCompletedBookings.length} '
      'shared=${BookingRequest.hydratedBookingCount} '
      'authoritative=$hasSharedBookings loadedOnce=$_hasLoadedOnce '
      'showLoading=$shouldShowLoadingState',
    );
    if (shouldShowLoadingState) {
      setBusy(true);
      _log('overlay show section=dashboard');
    }
    _log(
      'load start loggedIn=${_currentUser != null} user=${_currentUser?.id ?? "-"} role=${_currentUser?.role ?? "-"} visibleBookings=${!shouldShowLoadingState} cachedCompleted=${_cachedCompletedBookings.length} localCompleted=${_completedBookings.length} sharedBookings=$hasSharedBookings',
    );
    PerformanceTrace.event(
      'admin-dashboard-vm',
      'load start cached=${_cachedCompletedBookings.length} local=${_completedBookings.length} authoritative=$hasSharedBookings',
    );
    if (!shouldShowLoadingState) {
      _log('silent load only section=dashboard');
    }
    errorMessage = null;
    try {
      if (hasSharedBookings && _completedBookings.isEmpty) {
        _applyCompletedBookings(BookingRequest.hydratedBookingsSnapshot);
        notifyListeners();
      }
      unawaited(
        _bookingRepository
            .initialize()
            .then((_) {})
            .catchError((error, stackTrace) {}),
      );
      await _ensureBookingsSubscription();
      hasSharedBookings = BookingRequest.hasAuthoritativeBookings;
      _traceHandoff(
        'subscription ready localCompleted=${_completedBookings.length} '
        'shared=${BookingRequest.hydratedBookingCount} '
        'authoritative=$hasSharedBookings '
        'resolved=${BookingRequest.hasResolvedBookings}',
      );
      if (!hasSharedBookings) {
        // Dashboard owns the shared booking read. The stream controls the
        // visible state, so a slow SDK request cannot hold this overlay.
        unawaited(
          _bookingRepository.getBookings().catchError((_) => <Booking>[]),
        );
      } else {
        _log(
          'bookings reused shared count=${BookingRequest.hydratedBookingsSnapshot.length}',
        );
      }
      unawaited(_reloadSupportingData());
      if (_currentUser != null) {
        unawaited(_warmupService.warmUpForUser(_currentUser));
      }
      if (hasSharedBookings) {
        _markInitialBookingsResolved();
      }
      _cachedCompletedBookings = List<Booking>.from(_completedBookings);
      _cachedErrorMessage = null;
    } catch (error) {
      _log('load error error=$error');
      errorMessage = userFacingErrorMessage(
        error,
        fallback: 'We could not load the completed bookings right now.',
      );
      _cachedErrorMessage = errorMessage;
      _markInitialBookingsResolved();
    } finally {
      if (shouldShowLoadingState && _hasLoadedOnce && !overlayHidden) {
        setBusy(false);
        _log('overlay hide section=dashboard reason=load-finish');
      }
      _log(
        'load finish busy=$isBusy completed=${_completedBookings.length} users=${_usersById.length} error=${errorMessage ?? "-"}',
      );
      PerformanceTrace.event(
        'admin-dashboard-vm',
        'load finish elapsedMs=${stopwatch.elapsedMilliseconds} completed=${_completedBookings.length} busy=$isBusy error=${errorMessage ?? "-"}',
      );
      _traceHandoff(
        'load finish localCompleted=${_completedBookings.length} busy=$isBusy '
        'loadedOnce=$_hasLoadedOnce error=${errorMessage ?? '-'}',
      );
      notifyListeners();
    }
  }

  void _ensureSupportingSubscriptions() {
    _usersCacheUpdatesSubscription ??= AuthRequest.instance
        .watchUsersCacheUpdates()
        .listen((_) {
          PerformanceTrace.event('admin-dashboard-vm', 'users cache signal');
          unawaited(_reloadSupportingData());
        });
  }

  Future<void> _reloadSupportingData() async {
    if (_isRealtimeRefreshing) {
      _log('supporting reload skipped already-running');
      PerformanceTrace.event(
        'admin-dashboard-vm',
        'supporting reload skipped in-flight',
      );
      return;
    }
    final stopwatch = Stopwatch()..start();
    PerformanceTrace.event('admin-dashboard-vm', 'supporting reload start');
    _isRealtimeRefreshing = true;
    _log('supporting reload start');
    try {
      final results = await Future.wait<dynamic>([
        _loadCurrentUserSafe(),
        _loadUsersSafe(),
      ]);
      _currentUser = results[0] as UserModel?;
      final users = results[1] as List<UserModel>;
      _usersById
        ..clear()
        ..addEntries(
          users
              .where((user) => (user.id ?? '').isNotEmpty)
              .map((user) => MapEntry(user.id!, user)),
        );
      _cachedUsersById = Map<String, UserModel>.from(_usersById);
      _cachedCurrentUser = _currentUser;
      _log(
        'supporting reload done loggedIn=${_currentUser != null} user=${normalizeId(_currentUser?.id) ?? "-"} role=${_currentUser?.role ?? "-"} users=${_usersById.length}',
      );
      notifyListeners();
    } catch (_) {
      // Keep current visible state if live support data refresh fails.
    } finally {
      _isRealtimeRefreshing = false;
      PerformanceTrace.event(
        'admin-dashboard-vm',
        'supporting reload finish elapsedMs=${stopwatch.elapsedMilliseconds} users=${_usersById.length}',
      );
    }
  }

  Future<UserModel?> _loadCurrentUserSafe() async {
    try {
      final currentUser = await _authRepository.getCurrentUser().timeout(
        _loadStepTimeout,
        onTimeout: () {
          return _cachedCurrentUser;
        },
      );
      return currentUser ?? _cachedCurrentUser;
    } catch (error) {
      return _cachedCurrentUser;
    }
  }

  Future<List<UserModel>> _loadUsersSafe() async {
    try {
      await _warmupService.warmUsers();
      final users = await _authRepository.getUsers().timeout(
        _loadStepTimeout,
        onTimeout: () {
          return List<UserModel>.from(_cachedUsersById.values);
        },
      );
      return users;
    } catch (error) {
      return List<UserModel>.from(_cachedUsersById.values);
    }
  }

  Future<void> _ensureBookingsSubscription() async {
    if (_bookingsSubscription != null) {
      return;
    }
    _bookingsSubscription = _bookingRepository.watchBookings().listen((
      liveBookings,
    ) {
      PerformanceTrace.event(
        'admin-dashboard-vm',
        'booking stream event count=${liveBookings.length} authoritative=${BookingRequest.hasAuthoritativeBookings}',
      );
      _traceHandoff(
        'stream event count=${liveBookings.length} '
        'authoritative=${BookingRequest.hasAuthoritativeBookings} '
        'localBefore=${_completedBookings.length}',
      );
      if (!BookingRequest.hasAuthoritativeBookings) {
        // The shared stream can emit an empty provisional cache while the
        // first server snapshot is still pending. Do not turn that into an
        // empty-state UI.
        return;
      }
      _applyCompletedBookings(liveBookings);
      errorMessage = null;
      _markInitialBookingsResolved();
      if (isBusy) {
        setBusy(false);
      }
      notifyListeners();
      _traceHandoff(
        'stream applied localCompletedAfter=${_completedBookings.length}',
      );
    });
  }

  void _traceHandoff(String message) {
    if (kDebugMode) {
      debugPrint('[BookingHandoffTrace][admin-dashboard] $message');
    }
  }

  void _markInitialBookingsResolved() {
    if (_hasLoadedOnce) {
      return;
    }
    _hasLoadedOnce = true;
    _cachedHasLoadedOnce = true;
  }

  void _applyCompletedBookings(List<Booking> bookings) {
    _completedBookings
      ..clear()
      ..addAll(
        bookings.where(
          (booking) => Booking.isDeliveredWorkflowStatus(booking.clientStatus),
        ),
      );

    _completedBookings.sort((left, right) {
      final leftDate = bookingEffectiveDate(left);
      final rightDate = bookingEffectiveDate(right);
      final dateComparison = _compareLatestFirst(leftDate, rightDate);
      if (dateComparison != 0) {
        return dateComparison;
      }
      final leftId = int.tryParse(left.id ?? '');
      final rightId = int.tryParse(right.id ?? '');
      if (leftId != null && rightId != null) {
        return rightId.compareTo(leftId);
      }
      return (right.id ?? '').compareTo(left.id ?? '');
    });
    _cachedCompletedBookings = List<Booking>.from(_completedBookings);
    _log(
      'apply completed loggedIn=${_currentUser != null} user=${_currentUser?.id ?? "-"} role=${_currentUser?.role ?? "-"} source=${bookings.length} delivered=${_completedBookings.length}',
    );
  }

  @override
  void dispose() {
    PerformanceTrace.event('admin-dashboard-vm', 'dispose');
    _usersCacheUpdatesSubscription?.cancel();
    _bookingsSubscription?.cancel();
    super.dispose();
  }

  String client(Booking booking) {
    final client = _usersById[booking.client?.id];
    final name = client?.name?.trim();
    return "${name?.isNotEmpty == true ? name! : 'Unknown client'} (${origin(booking)} - ${destination(booking)})"
        .toUpperCase();
  }

  List<Booking> filteredCompletedBookings() {
    final query = _searchQuery.trim().toLowerCase();
    return _completedBookings.where((booking) {
      final matchesBillingStatus =
          _billingStatusFilter == null ||
          billingStatusValue(booking) == _billingStatusFilter;
      if (!matchesBillingStatus) {
        return false;
      }
      final deliveredDate = bookingEffectiveDate(booking);
      final matchesStartDate =
          _startDate == null ||
          (deliveredDate != null &&
              !_dateOnly(deliveredDate).isBefore(_dateOnly(_startDate!)));
      final matchesEndDate =
          _endDate == null ||
          (deliveredDate != null &&
              !_dateOnly(deliveredDate).isAfter(_dateOnly(_endDate!)));
      final createdAt = booking.createdAt;
      final matchesCreatedStartDate =
          _createdStartDate == null ||
          (createdAt != null &&
              !_dateOnly(createdAt).isBefore(_dateOnly(_createdStartDate!)));
      final matchesCreatedEndDate =
          _createdEndDate == null ||
          (createdAt != null &&
              !_dateOnly(createdAt).isAfter(_dateOnly(_createdEndDate!)));
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
          !matchesCreatedStartDate ||
          !matchesCreatedEndDate ||
          !matchesUpdatedStartDate ||
          !matchesUpdatedEndDate) {
        return false;
      }

      if (query.isEmpty) {
        return true;
      }

      final values = <String>[
        booking.id ?? '',
        deliveryFormNumber(booking),
        waybillNumber(booking),
        vanNumber(booking),
        vanSize(booking),
        amount(booking),
        client(booking),
        origin(booking),
        destination(booking),
        booking.clientStatus ?? '',
        booking.createdAt?.toIso8601String() ?? '',
        deliveredDate?.toIso8601String() ?? '',
        ..._flattenBookingOutputValues(booking.statusOutputs),
      ];
      return values.join(' ').toLowerCase().contains(query);
    }).toList();
  }

  void setSearchQuery(String value) {
    if (_searchQuery == value) {
      return;
    }
    _searchQuery = value;
    notifyListeners();
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

  void updateCreatedStartDate(DateTime? value) {
    _createdStartDate = value;
    if (_createdStartDate != null &&
        _createdEndDate != null &&
        _createdEndDate!.isBefore(_createdStartDate!)) {
      _createdEndDate = _createdStartDate;
    }
    notifyListeners();
  }

  void updateCreatedEndDate(DateTime? value) {
    _createdEndDate = value;
    if (_createdStartDate != null &&
        _createdEndDate != null &&
        _createdStartDate!.isAfter(_createdEndDate!)) {
      _createdStartDate = _createdEndDate;
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

  void clearFilters() {
    var changed = false;
    if (_startDate != null) {
      _startDate = null;
      changed = true;
    }
    if (_endDate != null) {
      _endDate = null;
      changed = true;
    }
    if (_createdStartDate != null) {
      _createdStartDate = null;
      changed = true;
    }
    if (_createdEndDate != null) {
      _createdEndDate = null;
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
    if (_billingStatusFilter != null) {
      _billingStatusFilter = null;
      changed = true;
    }
    if (changed) {
      notifyListeners();
    }
  }

  void updateBillingStatusFilter(String? value) {
    final normalized = switch (value?.trim().toLowerCase()) {
      billingStatusBilled => billingStatusBilled,
      billingStatusUnbilled => billingStatusUnbilled,
      _ => null,
    };
    if (_billingStatusFilter == normalized) {
      return;
    }
    _billingStatusFilter = normalized;
    notifyListeners();
  }

  List<Booking> currentRangeExportBookings() {
    if (_startDate == null || _endDate == null) {
      return filteredCompletedBookings();
    }
    return _completedBookings.where((booking) {
      final deliveredDate = bookingEffectiveDate(booking);
      if (deliveredDate == null) {
        return false;
      }
      final dateOnly = _dateOnly(deliveredDate);
      return !dateOnly.isBefore(_dateOnly(_startDate!)) &&
          !dateOnly.isAfter(_dateOnly(_endDate!));
    }).toList();
  }

  List<Booking> pastUnbilledExportBookings() {
    final startDate = _startDate;
    return _completedBookings.where((booking) {
      if (billingStatusValue(booking) != billingStatusUnbilled) {
        return false;
      }
      if (startDate == null) {
        return true;
      }
      final deliveredDate = bookingEffectiveDate(booking);
      if (deliveredDate == null) {
        return false;
      }
      return _dateOnly(deliveredDate).isBefore(_dateOnly(startDate));
    }).toList();
  }

  List<Booking> mergedExportBookings({
    required bool includeCurrentRange,
    required bool includePastUnbilled,
  }) {
    final byId = <String, Booking>{};
    if (includeCurrentRange) {
      for (final booking in currentRangeExportBookings()) {
        final id = booking.id;
        if (id == null || id.isEmpty) {
          continue;
        }
        byId[id] = booking;
      }
    }
    if (includePastUnbilled) {
      for (final booking in pastUnbilledExportBookings()) {
        final id = booking.id;
        if (id == null || id.isEmpty) {
          continue;
        }
        byId.putIfAbsent(id, () => booking);
      }
    }
    final merged = byId.values.toList();
    merged.sort((left, right) {
      final leftDate = deliveredAt(left) ?? left.updatedAt ?? left.createdAt;
      final rightDate =
          deliveredAt(right) ?? right.updatedAt ?? right.createdAt;
      final dateComparison = _compareLatestFirst(leftDate, rightDate);
      if (dateComparison != 0) {
        return dateComparison;
      }
      final leftId = int.tryParse(left.id ?? '');
      final rightId = int.tryParse(right.id ?? '');
      if (leftId != null && rightId != null) {
        return rightId.compareTo(leftId);
      }
      return (right.id ?? '').compareTo(left.id ?? '');
    });
    return merged;
  }

  String billingStatusValue(Booking booking) {
    return booking.billingStatus?.trim().toLowerCase() == billingStatusBilled
        ? billingStatusBilled
        : billingStatusUnbilled;
  }

  String billingStatusLabel(Booking booking) {
    return billingStatusValue(booking) == billingStatusBilled
        ? 'Billed'
        : 'Unbilled';
  }

  Future<void> updateBookingBillingStatus(
    Booking booking,
    String billingStatus,
  ) async {
    final bookingId = booking.id?.trim();
    if (bookingId == null || bookingId.isEmpty) {
      throw Exception('We could not update the billing status right now.');
    }
    final updated = await _bookingRepository.updateBillingStatus(
      bookingId,
      billingStatus,
    );
    _replaceBooking(updated);
  }

  Future<void> updateBillingStatusesForExport({
    required Iterable<String> billedBookingIds,
    required Iterable<String> unbilledBookingIds,
  }) async {
    final statuses = <String, String>{};
    for (final bookingId in billedBookingIds) {
      final normalizedId = normalizeId(bookingId);
      if (normalizedId == null) {
        continue;
      }
      statuses[normalizedId] = billingStatusBilled;
    }
    for (final bookingId in unbilledBookingIds) {
      final normalizedId = normalizeId(bookingId);
      if (normalizedId == null) {
        continue;
      }
      statuses[normalizedId] = billingStatusUnbilled;
    }
    if (statuses.isEmpty) {
      return;
    }
    await _bookingRepository.updateBillingStatuses(statuses);
    for (final entry in statuses.entries) {
      final index = _completedBookings.indexWhere(
        (booking) => booking.id == entry.key,
      );
      if (index < 0) {
        continue;
      }
      _completedBookings[index] = _completedBookings[index].copyWith(
        billingStatus: entry.value,
      );
    }
    _cachedCompletedBookings = List<Booking>.from(_completedBookings);
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

  static String origin(Booking booking) => _dashboardRouteDisplayValue(
    primaryValue: BookingRecordCard.outputFieldDisplayValue(
      booking.statusOutputs,
      'origin',
    ),
    puertoPrincesaBarangayValue: BookingRecordCard.outputFieldDisplayValue(
      booking.statusOutputs,
      'origin_barangay',
    ),
  );

  static String destination(Booking booking) => _dashboardRouteDisplayValue(
    primaryValue: BookingRecordCard.outputFieldDisplayValue(
      booking.statusOutputs,
      'destination',
    ),
    puertoPrincesaBarangayValue: BookingRecordCard.outputFieldDisplayValue(
      booking.statusOutputs,
      'destination_barangay',
    ),
  );

  DateTime? deliveredAt(Booking booking) {
    if (booking.deliveredAt != null) {
      return booking.deliveredAt;
    }
    final section = booking.statusOutputs?['delivered'];
    if (section is! Map) {
      return null;
    }
    final submittedAt = section['submitted_at'];
    if (submittedAt == null) {
      return null;
    }
    return DateTime.tryParse(submittedAt.toString());
  }

  DateTime? bookingEffectiveDate(Booking booking) {
    final dropOffDate = BookingRecordCard.outputFieldDisplayValue(
      booking.statusOutputs,
      'drop_off_date',
    ).trim();
    if (dropOffDate.isNotEmpty) {
      final parsedDropOffDate = DateTime.tryParse(dropOffDate);
      if (parsedDropOffDate != null) {
        return parsedDropOffDate;
      }
    }
    return deliveredAt(booking) ?? booking.updatedAt ?? booking.createdAt;
  }

  static int _compareLatestFirst(DateTime? left, DateTime? right) {
    if (left == null && right == null) {
      return 0;
    }
    if (left == null) {
      return 1;
    }
    if (right == null) {
      return -1;
    }
    return right.compareTo(left);
  }

  void _log(String message) {
    // Temporary debug logging removed.
  }

  static String deliveryFormNumber(Booking booking) =>
      BookingRecordCard.outputFieldDisplayValue(
        booking.statusOutputs,
        'delivery_form_number',
      ).toUpperCase();

  static String waybillNumber(Booking booking) =>
      BookingRecordCard.outputFieldDisplayValue(
        booking.statusOutputs,
        'waybill_number',
      ).toUpperCase();

  static String vanNumber(Booking booking) =>
      BookingRecordCard.outputFieldDisplayValue(
        booking.statusOutputs,
        'van_number',
      ).toUpperCase();

  String vanSize(Booking booking) {
    final rawValue = BookingRecordCard.outputFieldDisplayValue(
      booking.statusOutputs,
      'van_size',
    );
    return VehicleRequest.instance.displayVehicleSizeLabel(
      rawValue,
      uppercase: true,
      preferSlug: true,
    );
  }

  static String _dashboardRouteDisplayValue({
    required String primaryValue,
    required String puertoPrincesaBarangayValue,
  }) {
    final normalizedPrimaryValue = primaryValue.trim();
    final normalizedBarangayValue = puertoPrincesaBarangayValue.trim();
    final shouldUseBarangay =
        normalizedPrimaryValue.toLowerCase().contains('puerto princesa') &&
        normalizedBarangayValue.isNotEmpty;
    return (shouldUseBarangay
            ? normalizedBarangayValue
            : normalizedPrimaryValue)
        .toUpperCase();
  }

  static String amount(Booking booking) =>
      BookingRecordCard.outputFieldDisplayValue(
        booking.statusOutputs,
        'amount',
      ).toUpperCase();

  static String dropOffDateDisplay(Booking booking) {
    final rawValue = BookingRecordCard.outputFieldDisplayValue(
      booking.statusOutputs,
      'drop_off_date',
    ).trim();
    if (rawValue.isEmpty) {
      return '-';
    }
    final parsedValue = DateTime.tryParse(rawValue);
    if (parsedValue == null) {
      return rawValue.toUpperCase();
    }
    final year = (parsedValue.year % 100).toString().padLeft(2, '0');
    return '${parsedValue.month}/${parsedValue.day}/$year';
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static List<String> _flattenBookingOutputValues(
    Map<String, dynamic>? outputs,
  ) {
    if (outputs == null || outputs.isEmpty) {
      return const [];
    }
    final values = <String>[];
    for (final section in outputs.values) {
      if (section is! Map) {
        continue;
      }
      final fields = section['fields'];
      if (fields is! Map) {
        continue;
      }
      for (final value in fields.values) {
        final normalized = value?.toString().trim();
        if (normalized != null && normalized.isNotEmpty) {
          values.add(normalized);
        }
      }
    }
    return values;
  }

  void _replaceBooking(Booking booking) {
    final index = _completedBookings.indexWhere(
      (item) => item.id == booking.id,
    );
    if (index < 0) {
      return;
    }
    _completedBookings[index] = booking;
    _cachedCompletedBookings = List<Booking>.from(_completedBookings);
    notifyListeners();
  }
}
