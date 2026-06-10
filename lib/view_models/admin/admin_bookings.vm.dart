import 'package:stacked/stacked.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/status_definition.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/repositories/local/local_auth_repository.dart';
import 'package:webapp/repositories/local/local_booking_repository.dart';
import 'package:webapp/repositories/local/local_status_form_repository.dart';
import 'package:webapp/repositories/local/local_vehicle_catalog_repository.dart';

class AdminBookingsViewModel extends BaseViewModel {
  AdminBookingsViewModel({
    AuthRepository? authRepository,
  }) : _authRepository = authRepository ?? LocalAuthRepository.instance,
       _bookingRepository = LocalBookingRepository.instance,
       _statusRepository = LocalStatusFormRepository.instance,
       _vehicleCatalogRepository = LocalVehicleCatalogRepository.instance;

  final AuthRepository _authRepository;
  final LocalBookingRepository _bookingRepository;
  final LocalStatusFormRepository _statusRepository;
  final LocalVehicleCatalogRepository _vehicleCatalogRepository;

  final List<Booking> _bookings = [];
  final Map<String, UserModel> _usersById = {};
  final Map<String, StatusDefinition> _statusesByKey = {};
  List<VehicleCatalogItem> _vehicleSizes = const [];
  String _searchQuery = '';
  String _statusFilter = 'All';
  DateTime? _startDate;
  DateTime? _endDate;
  String? errorMessage;

  List<Booking> get bookings => List.unmodifiable(_bookings);
  String get searchQuery => _searchQuery;
  String get statusFilter => _statusFilter;
  DateTime? get startDate => _startDate;
  DateTime? get endDate => _endDate;
  List<String> get statusOptions => [
    'All',
    ..._statusesByKey.values
        .map((status) => status.label?.trim())
        .whereType<String>()
        .where((label) => label.isNotEmpty)
        .toSet(),
  ];

  Future<void> load() async {
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

      _bookings
        ..clear()
        ..addAll(await _bookingRepository.getBookings());
    } catch (_) {
      errorMessage = 'Failed to load bookings.';
    } finally {
      setBusy(false);
      notifyListeners();
    }
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
      final matchesStatus = _statusFilter == 'All' ||
          clientStatusLabel(booking) == _statusFilter;
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
      final client = _usersById[booking.clientId];
      final values = <String>[
        booking.id ?? '',
        booking.clientId ?? '',
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
    final client = _usersById[booking.clientId];
    final name = client?.name?.trim();
    return name?.isNotEmpty == true ? name! : 'Unknown client';
  }

  String clientPhone(Booking booking) {
    final client = _usersById[booking.clientId];
    final phone = client?.phone?.trim();
    return phone?.isNotEmpty == true ? phone! : '-';
  }

  String driverName(Booking booking) {
    final driver = _usersById[booking.driverId];
    final name = driver?.name?.trim();
    return name?.isNotEmpty == true ? name! : '-';
  }

  String driverPhone(Booking booking) {
    final driver = _usersById[booking.driverId];
    final phone = driver?.phone?.trim();
    return phone?.isNotEmpty == true ? phone! : '-';
  }

  String helperName(Booking booking) {
    final helper = _usersById[booking.helperId];
    final name = helper?.name?.trim();
    return name?.isNotEmpty == true ? name! : '-';
  }

  String helperPhone(Booking booking) {
    final helper = _usersById[booking.helperId];
    final phone = helper?.phone?.trim();
    return phone?.isNotEmpty == true ? phone! : '-';
  }

  String clientStatusLabel(Booking booking) {
    return statusLabelForKey(booking.clientStatus);
  }

  List<StatusDefinition> activeStatuses() {
    return _statusesByKey.values
        .where((status) => status.isActive ?? false)
        .toList()
      ..sort(
        (left, right) => (left.label ?? '').compareTo(right.label ?? ''),
      );
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
    return _vehicleSizes
        .where((size) => size.isActive ?? false)
        .toList()
      ..sort((left, right) => (left.name ?? '').compareTo(right.name ?? ''));
  }

  Future<Booking> saveEditedBooking(Booking booking) async {
    final updatedBooking = booking.copyWith(updatedAt: DateTime.now());
    return _bookingRepository.saveBooking(updatedBooking);
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

  static List<String> _flattenBookingOutputValues(Map<String, dynamic>? outputs) {
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
