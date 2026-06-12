import 'package:stacked/stacked.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/requests/booking.request.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/repositories/interfaces/booking_repository.dart';
import 'package:webapp/repositories/interfaces/vehicle_catalog_repository.dart';
import 'package:webapp/utils/functions.dart';
import 'package:webapp/widgets/shared/booking_record_card.dart';

class AdminDashboardViewModel extends BaseViewModel {
  AdminDashboardViewModel({
    AuthRepository? authRepository,
    VehicleCatalogRepository? vehicleRepository,
  })
    : _authRepository = authRepository ?? AuthRequest.instance,
      _vehicleRepository = vehicleRepository ?? VehicleRequest.instance,
      _bookingRepository = BookingRequest.instance {
    _completedBookings.addAll(_cachedCompletedBookings);
    _usersById.addAll(_cachedUsersById);
    errorMessage = _cachedErrorMessage;
  }

  final AuthRepository _authRepository;
  final VehicleCatalogRepository _vehicleRepository;
  final BookingRepository _bookingRepository;
  static List<Booking> _cachedCompletedBookings = const [];
  static Map<String, UserModel> _cachedUsersById = const {};
  static String? _cachedErrorMessage;

  static void clearCachedState() {
    _cachedCompletedBookings = const [];
    _cachedUsersById = const {};
    _cachedErrorMessage = null;
  }

  final List<Booking> _completedBookings = [];
  final Map<String, UserModel> _usersById = {};

  List<Booking> get completedBookings => List.unmodifiable(_completedBookings);
  String? errorMessage;
  String busyMessage = 'Loading, please wait ...';
  String _searchQuery = '';
  DateTime? _startDate;
  DateTime? _endDate;

  String get searchQuery => _searchQuery;
  DateTime? get startDate => _startDate;
  DateTime? get endDate => _endDate;

  Future<void> load() async {
    busyMessage = 'Loading dashboard ...';
    setBusy(true);
    errorMessage = null;
    try {
      await _bookingRepository.initialize();
      final results = await Future.wait([
        _authRepository.getUsers(),
        _bookingRepository.getBookings(),
        _vehicleRepository.getSizes(),
      ]);
      final users = results[0] as List<UserModel>;
      final bookings = results[1] as List<Booking>;
      final _ = results[2] as List;

      _usersById
        ..clear()
        ..addEntries(
          users
              .where((user) => (user.id ?? '').isNotEmpty)
              .map((user) => MapEntry(user.id!, user)),
        );

      _completedBookings
        ..clear()
        ..addAll(
          bookings.where(
            (booking) => (booking.clientStatus ?? '').trim() == 'delivered',
          ),
        );

      _completedBookings.sort((left, right) {
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
      _cachedCompletedBookings = List<Booking>.from(_completedBookings);
      _cachedUsersById = Map<String, UserModel>.from(_usersById);
      _cachedErrorMessage = null;
    } catch (error) {
      errorMessage = userFacingErrorMessage(
        error,
        fallback: 'We could not load the completed bookings right now.',
      );
      _cachedErrorMessage = errorMessage;
    } finally {
      setBusy(false);
      notifyListeners();
    }
  }

  String client(Booking booking) {
    final client = _usersById[booking.client?.id];
    final name = client?.name?.trim();
    return "${name?.isNotEmpty == true ? name! : 'Unknown client'} (${start(booking)} - ${end(booking)})"
        .toUpperCase();
  }

  List<Booking> filteredCompletedBookings() {
    final query = _searchQuery.trim().toLowerCase();
    return _completedBookings.where((booking) {
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
        start(booking),
        end(booking),
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
    if (changed) {
      notifyListeners();
    }
  }

  String formatDate(DateTime? value) {
    if (value == null) {
      return 'All';
    }
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$month/$day/${value.year}';
  }

  static String start(Booking booking) =>
      BookingRecordCard.outputFieldDisplayValue(
        booking.statusOutputs,
        'start',
      ).toUpperCase();

  static String end(Booking booking) =>
      BookingRecordCard.outputFieldDisplayValue(
        booking.statusOutputs,
        'end',
      ).toUpperCase();

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

  static String amount(Booking booking) =>
      BookingRecordCard.outputFieldDisplayValue(
        booking.statusOutputs,
        'amount',
      ).toUpperCase();

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
}
