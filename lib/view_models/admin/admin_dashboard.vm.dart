import 'dart:async';

import 'package:stacked/stacked.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/requests/booking.request.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/repositories/interfaces/booking_repository.dart';
import 'package:webapp/repositories/interfaces/vehicle_catalog_repository.dart';
import 'package:webapp/services/network_status_events.dart';
import 'package:webapp/utils/functions.dart';
import 'package:webapp/widgets/shared/booking_record_card.dart';

class AdminDashboardViewModel extends BaseViewModel {
  static const billingStatusAll = 'all';
  static const billingStatusBilled = 'billed';
  static const billingStatusUnbilled = 'unbilled';

  AdminDashboardViewModel({
    AuthRepository? authRepository,
    VehicleCatalogRepository? vehicleRepository,
  })
    : _authRepository = authRepository ?? AuthRequest.instance,
      _vehicleRepository = vehicleRepository ?? VehicleRequest.instance,
      _bookingRepository = BookingRequest.instance {
    _completedBookings.addAll(_cachedCompletedBookings);
    _usersById.addAll(_cachedUsersById);
    _currentUser = _cachedCurrentUser;
    errorMessage = _cachedErrorMessage;
  }

  final AuthRepository _authRepository;
  final VehicleCatalogRepository _vehicleRepository;
  final BookingRepository _bookingRepository;
  StreamSubscription<List<Booking>>? _bookingsSubscription;
  bool _didScheduleWarmRetry = false;
  static List<Booking> _cachedCompletedBookings = const [];
  static Map<String, UserModel> _cachedUsersById = const {};
  static UserModel? _cachedCurrentUser;
  static String? _cachedErrorMessage;
  static const Duration _loadStepTimeout = Duration(seconds: 8);

  static void clearCachedState() {
    _cachedCompletedBookings = const [];
    _cachedUsersById = const {};
    _cachedCurrentUser = null;
    _cachedErrorMessage = null;
  }

  final List<Booking> _completedBookings = [];
  final Map<String, UserModel> _usersById = {};
  UserModel? _currentUser;

  List<Booking> get completedBookings => List.unmodifiable(_completedBookings);
  UserModel? get currentUser => _currentUser;
  String? errorMessage;
  String busyMessage = 'Loading, please wait ...';
  String _searchQuery = '';
  DateTime? _startDate;
  DateTime? _endDate;
  String? _billingStatusFilter;
  bool _isExporting = false;
  int _exportTotalSteps = 0;
  int _exportCompletedSteps = 0;

  String get searchQuery => _searchQuery;
  DateTime? get startDate => _startDate;
  DateTime? get endDate => _endDate;
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
    if (!_isExporting &&
        _exportTotalSteps == 0 &&
        _exportCompletedSteps == 0) {
      return;
    }
    _isExporting = false;
    _exportTotalSteps = 0;
    _exportCompletedSteps = 0;
    notifyListeners();
  }

  Future<void> load() async {
    busyMessage = 'Loading dashboard ...';
    final hasVisiblePrimaryData =
        _completedBookings.isNotEmpty ||
        _cachedCompletedBookings.isNotEmpty ||
        _usersById.isNotEmpty ||
        _cachedUsersById.isNotEmpty;
    final shouldShowLoadingState = !hasVisiblePrimaryData;
    if (shouldShowLoadingState) {
      setBusy(true);
    }
    errorMessage = null;
    try {
      unawaited(
        _bookingRepository.initialize().then((_) {
        }).catchError((error, stackTrace) {
        }),
      );
      await _ensureBookingsSubscription();

      final results = await Future.wait<dynamic>([
        _loadCurrentUserSafe(),
        _loadUsersSafe(),
        _loadBookingsSafe(),
        _warmVehicleSizesSafe(),
      ]);
      final currentUser = results[0] as UserModel?;
      final users = results[1] as List<UserModel>;
      final bookings = results[2] as List<Booking>;

      _currentUser = currentUser;

      _usersById
        ..clear()
        ..addEntries(
          users
              .where((user) => (user.id ?? '').isNotEmpty)
              .map((user) => MapEntry(user.id!, user)),
        );
      _applyCompletedBookings(bookings);
      _cachedCompletedBookings = List<Booking>.from(_completedBookings);
      _cachedUsersById = Map<String, UserModel>.from(_usersById);
      _cachedCurrentUser = _currentUser;
      _cachedErrorMessage = null;
      _scheduleWarmRetryIfNeeded();
    } catch (error) {
      errorMessage = userFacingErrorMessage(
        error,
        fallback: 'We could not load the completed bookings right now.',
      );
      _cachedErrorMessage = errorMessage;
    } finally {
      if (shouldShowLoadingState) {
        setBusy(false);
      }
      notifyListeners();
    }
  }

  Future<UserModel?> _loadCurrentUserSafe() async {
    try {
      final currentUser = await _authRepository
          .getCurrentUser()
          .timeout(_loadStepTimeout, onTimeout: () {
            return _cachedCurrentUser;
          });
      return currentUser ?? _cachedCurrentUser;
    } catch (error) {
      return _cachedCurrentUser;
    }
  }

  Future<List<UserModel>> _loadUsersSafe() async {
    try {
      final users = await _authRepository
          .getUsers()
          .timeout(_loadStepTimeout, onTimeout: () {
            return List<UserModel>.from(_cachedUsersById.values);
          });
      return users;
    } catch (error) {
      return List<UserModel>.from(_cachedUsersById.values);
    }
  }

  Future<List<Booking>> _loadBookingsSafe() async {
    try {
      final bookings = await _bookingRepository
          .getBookings()
          .timeout(_loadStepTimeout, onTimeout: () {
            return List<Booking>.from(_cachedCompletedBookings);
          });
      return bookings;
    } catch (error) {
      return List<Booking>.from(_cachedCompletedBookings);
    }
  }

  Future<void> _ensureBookingsSubscription() async {
    if (_bookingsSubscription != null) {
      return;
    }
    _bookingsSubscription = _bookingRepository.watchBookings().listen((
      liveBookings,
    ) {
      _applyCompletedBookings(liveBookings);
      errorMessage = null;
      if (isBusy && _completedBookings.isNotEmpty) {
        setBusy(false);
      }
      notifyListeners();
    });
  }

  void _scheduleWarmRetryIfNeeded() {
    if (_didScheduleWarmRetry ||
        !currentNetworkStatus() ||
        _completedBookings.isNotEmpty ||
        _cachedCompletedBookings.isNotEmpty) {
      return;
    }
    _didScheduleWarmRetry = true;
    unawaited(_retryLoadAfterWarmup());
  }

  Future<void> _retryLoadAfterWarmup() async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    try {
      final bookings = await _bookingRepository.getBookings();
      if (bookings.isEmpty) {
        return;
      }
      _applyCompletedBookings(bookings);
      _cachedCompletedBookings = List<Booking>.from(_completedBookings);
      notifyListeners();
    } catch (_) {}
  }

  void _applyCompletedBookings(List<Booking> bookings) {
    _completedBookings
      ..clear()
      ..addAll(
        bookings.where(
          (booking) =>
              (booking.clientStatus ?? '').trim().toLowerCase() == 'delivered',
        ),
      );

    _completedBookings.sort((left, right) {
      final leftDate = deliveredAt(left) ?? left.updatedAt ?? left.createdAt;
      final rightDate = deliveredAt(right) ?? right.updatedAt ?? right.createdAt;
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
  }

  Future<void> _warmVehicleSizesSafe() async {
    try {
      await _vehicleRepository.getSizes().timeout(_loadStepTimeout, onTimeout: () {
        return const [];
      });
    } catch (error) {
      // Warm-up should not block dashboard rendering.
    }
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
      final deliveredDate =
          deliveredAt(booking) ?? booking.updatedAt ?? booking.createdAt;
      final matchesStartDate =
          _startDate == null ||
          (deliveredDate != null &&
              !_dateOnly(deliveredDate).isBefore(_dateOnly(_startDate!)));
      final matchesEndDate =
          _endDate == null ||
          (deliveredDate != null &&
              !_dateOnly(deliveredDate).isAfter(_dateOnly(_endDate!)));
      if (!matchesStartDate || !matchesEndDate) {
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
      return const [];
    }
    return _completedBookings.where((booking) {
      final deliveredDate =
          deliveredAt(booking) ?? booking.updatedAt ?? booking.createdAt;
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
      final deliveredDate =
          deliveredAt(booking) ?? booking.updatedAt ?? booking.createdAt;
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
      final rightDate = deliveredAt(right) ?? right.updatedAt ?? right.createdAt;
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
    final index = _completedBookings.indexWhere((item) => item.id == booking.id);
    if (index < 0) {
      return;
    }
    _completedBookings[index] = booking;
    _cachedCompletedBookings = List<Booking>.from(_completedBookings);
    notifyListeners();
  }

  @override
  void dispose() {
    _bookingsSubscription?.cancel();
    super.dispose();
  }
}
