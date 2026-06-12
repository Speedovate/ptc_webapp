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
import 'package:webapp/utils/functions.dart';

class AdminBookingsViewModel extends BaseViewModel {
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
    errorMessage = _cachedErrorMessage;
  }

  final AuthRepository _authRepository;
  final BookingRepository _bookingRepository;
  final StatusFormRepository _statusRepository;
  final VehicleCatalogRepository _vehicleCatalogRepository;
  StreamSubscription<List<Booking>>? _bookingsSubscription;
  static List<Booking> _cachedBookings = const [];
  static Map<String, UserModel> _cachedUsersById = const {};
  static Map<String, Status> _cachedStatusesByKey = const {};
  static List<VehicleCatalogItem> _cachedVehicleSizes = const [];
  static String? _cachedErrorMessage;

  static void clearCachedState() {
    _cachedBookings = const [];
    _cachedUsersById = const {};
    _cachedStatusesByKey = const {};
    _cachedVehicleSizes = const [];
    _cachedErrorMessage = null;
  }

  final List<Booking> _bookings = [];
  final Map<String, UserModel> _usersById = {};
  final Map<String, Status> _statusesByKey = {};
  List<VehicleCatalogItem> _vehicleSizes = const [];
  String _searchQuery = '';
  String _statusFilter = 'All';
  DateTime? _startDate;
  DateTime? _endDate;
  String? errorMessage;
  String _busyMessage = 'Loading, please wait ...';

  List<Booking> get bookings => List.unmodifiable(_bookings);
  String get searchQuery => _searchQuery;
  String get statusFilter => _statusFilter;
  DateTime? get startDate => _startDate;
  DateTime? get endDate => _endDate;
  String get busyMessage => _busyMessage;
  List<String> get statusOptions => [
    'All',
    ..._statusesByKey.values
        .map((status) => status.label?.trim())
        .whereType<String>()
        .where((label) => label.isNotEmpty)
        .toSet(),
  ];

  Future<void> load() async {
    _busyMessage = 'Loading bookings ...';
    setBusy(true);
    errorMessage = null;
    try {
      await _bookingRepository.initialize();
      final users = await _authRepository.getUsers();
      final statuses = await _statusRepository.getStatuses();
      _vehicleSizes = await _vehicleCatalogRepository.getSizes();
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

      await _bookingsSubscription?.cancel();
      _applyBookings(await _bookingRepository.getBookings());
      _bookingsSubscription = _bookingRepository.watchBookings().listen((
        bookings,
      ) {
        _applyBookings(bookings);
        notifyListeners();
      });
      _cachedUsersById = Map<String, UserModel>.from(_usersById);
      _cachedStatusesByKey = Map<String, Status>.from(_statusesByKey);
      _cachedVehicleSizes = List<VehicleCatalogItem>.from(_vehicleSizes);
      _cachedErrorMessage = null;
    } catch (error) {
      errorMessage = userFacingErrorMessage(
        error,
        fallback: 'We could not load the bookings right now.',
      );
      _cachedErrorMessage = errorMessage;
    } finally {
      setBusy(false);
      notifyListeners();
    }
  }

  void _applyBookings(List<Booking> bookings) {
    _bookings
      ..clear()
      ..addAll(bookings);
    _cachedBookings = List<Booking>.from(_bookings);
  }

  void setSearchQuery(String value) {
    if (_searchQuery == value) {
      return;
    }
    _searchQuery = value;
    notifyListeners();
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
      if (!matchesStartDate || !matchesEndDate) {
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
    return statusLabelForKey(booking.clientStatus);
  }

  List<Status> activeStatuses() {
    return _statusesByKey.values
        .where((status) => status.isActive ?? false)
        .toList()
      ..sort((left, right) => (left.label ?? '').compareTo(right.label ?? ''));
  }

  List<UserModel> roleUsers(String role) {
    final normalizedRole = role.trim().toLowerCase();
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
    return _vehicleSizes.where((size) => size.isActive ?? false).toList()
      ..sort((left, right) => (left.name ?? '').compareTo(right.name ?? ''));
  }

  Future<Booking> saveEditedBooking(Booking booking) async {
    _busyMessage = 'Saving booking ...';
    setBusy(true);
    try {
      final updatedBooking = booking.copyWith(updatedAt: DateTime.now());
      return await _bookingRepository.saveBooking(updatedBooking);
    } finally {
      setBusy(false);
    }
  }

  @override
  void dispose() {
    _bookingsSubscription?.cancel();
    super.dispose();
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
    return _usersById.values
        .where(
          (user) =>
              (user.role ?? '').trim() == 'client' && (user.isActive ?? false),
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
