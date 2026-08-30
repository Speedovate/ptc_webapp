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
import 'package:webapp/utils/functions.dart';

class ClientBookingHistoryViewModel extends BaseViewModel {
  ClientBookingHistoryViewModel({
    BookingRepository? bookingRepository,
    AuthRepository? authRepository,
    StatusFormRepository? statusRepository,
  }) : _bookingRepository = bookingRepository ?? BookingRequest.instance,
       _authRepository = authRepository ?? AuthRequest.instance,
       _statusRepository = statusRepository ?? StatusRequest.instance {
    bookings = List<Booking>.from(_cachedBookings);
    isLoading = false;
    errorMessage = _cachedErrorMessage;
    _usersById.addAll(_cachedUsersById);
    _statusesByKey.addAll(_cachedStatusesByKey);
    _hasLoadedOnce = _cachedHasLoadedOnce;
  }

  final BookingRepository _bookingRepository;
  final AuthRepository _authRepository;
  final StatusFormRepository _statusRepository;
  StreamSubscription<List<Booking>>? _bookingsSubscription;
  final Map<String, UserModel> _usersById = {};
  final Map<String, Status> _statusesByKey = {};
  static List<Booking> _cachedBookings = const [];
  static String? _cachedErrorMessage;
  static Map<String, UserModel> _cachedUsersById = const {};
  static Map<String, Status> _cachedStatusesByKey = const {};
  static bool _cachedHasLoadedOnce = false;

  static void clearCachedState() {
    _cachedBookings = const [];
    _cachedErrorMessage = null;
    _cachedUsersById = const {};
    _cachedStatusesByKey = const {};
    _cachedHasLoadedOnce = false;
  }

  List<Booking> bookings = [];
  bool isLoading = false;
  String? errorMessage;
  String _searchQuery = '';
  String _statusFilter = 'All';
  DateTime? _startDate;
  DateTime? _endDate;
  DateTime? _updatedStartDate;
  DateTime? _updatedEndDate;
  bool _hasLoadedOnce = false;

  String get searchQuery => _searchQuery;
  String get statusFilter => _statusFilter;
  DateTime? get startDate => _startDate;
  DateTime? get endDate => _endDate;
  DateTime? get updatedStartDate => _updatedStartDate;
  DateTime? get updatedEndDate => _updatedEndDate;
  List<String> get statusOptions => [
    'All',
    if (bookings.any(
      (booking) => (booking.localSyncStatus ?? '').trim().toLowerCase() == 'queued',
    ))
      'Queued',
    ..._statusesByKey.values
        .map((status) => status.label?.trim())
        .whereType<String>()
        .where((label) => label.isNotEmpty)
        .toSet(),
  ];

  Future<void> load(UserModel user) async {
    if (isLoading) {
      return;
    }
    final hasVisiblePrimaryData =
        bookings.isNotEmpty ||
        BookingRequest.hasResolvedBookings ||
        _cachedBookings.isNotEmpty ||
        _usersById.isNotEmpty ||
        _cachedUsersById.isNotEmpty ||
        _statusesByKey.isNotEmpty ||
        _cachedStatusesByKey.isNotEmpty;
    isLoading = !_hasLoadedOnce && !hasVisiblePrimaryData;
    errorMessage = null;
    notifyListeners();

    try {
      await _bookingRepository.initialize();
      final sharedBookings = BookingRequest.hasResolvedBookings
          ? BookingRequest.hydratedBookingsSnapshot
          : null;
      final results = await Future.wait([
        _authRepository.getUsers(),
        _statusRepository.getStatuses(),
        if (sharedBookings != null)
          Future<List<Booking>>.value(sharedBookings)
        else
          _bookingRepository.getBookings(),
      ]);
      final users = results[0] as List<UserModel>;
      final statuses = results[1] as List<Status>;
      final allBookings = results[2] as List<Booking>;
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

      await _bookingsSubscription?.cancel();
      _applyBookingsForUser(user, allBookings);
      _bookingsSubscription = _bookingRepository.watchBookings().listen((
        liveBookings,
      ) {
        _applyBookingsForUser(user, liveBookings);
        notifyListeners();
      });
      _cachedErrorMessage = null;
      _cachedUsersById = Map<String, UserModel>.from(_usersById);
      _cachedStatusesByKey = Map<String, Status>.from(_statusesByKey);
      _hasLoadedOnce = true;
      _cachedHasLoadedOnce = true;
    } catch (error) {
      errorMessage = userFacingErrorMessage(
        error,
        fallback: 'We could not load your booking history right now.',
      );
      _cachedErrorMessage = errorMessage;
      _hasLoadedOnce = true;
      _cachedHasLoadedOnce = true;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void _applyBookingsForUser(UserModel user, List<Booking> allBookings) {
    final currentUserId = user.id ?? '';
    bookings = switch (normalizeRoleKey(user.role)) {
      'client' =>
        allBookings
            .where((booking) => booking.client?.id == currentUserId)
            .toList(),
      'driver' =>
        allBookings
            .where((booking) => booking.driver?.id == currentUserId)
            .toList(),
      'helper' =>
        allBookings
            .where((booking) => booking.helper?.id == currentUserId)
            .toList(),
      _ => const [],
    };
    _cachedBookings = List<Booking>.from(bookings);
  }

  String clientName(Booking booking) =>
      _userName(booking.client?.id, 'Unknown client');

  String clientPhone(Booking booking) => _userPhone(booking.client?.id);

  String driverName(Booking booking) => _userName(booking.driver?.id, '-');

  String driverPhone(Booking booking) => _userPhone(booking.driver?.id);

  String helperName(Booking booking) => _userName(booking.helper?.id, '-');

  String helperPhone(Booking booking) => _userPhone(booking.helper?.id);

  String statusLabelForRole(String? role, Booking booking) {
    if ((booking.localSyncStatus ?? '').trim().toLowerCase() == 'queued') {
      return 'Queued';
    }
    return statusLabelForKey(booking.clientStatus);
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

  bool matchesBooking(Booking booking, String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return true;
    }

    final values = <String>[
      booking.id ?? '',
      booking.clientStatus ?? '',
      booking.driverStatus ?? '',
      booking.helperStatus ?? '',
      booking.createdAt?.toIso8601String() ?? '',
      clientName(booking),
      clientPhone(booking),
      driverName(booking),
      driverPhone(booking),
      helperName(booking),
      helperPhone(booking),
      ..._flattenBookingOutputValues(booking.statusOutputs),
    ];
    return values.join(' ').toLowerCase().contains(normalizedQuery);
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

  List<Booking> filteredBookings() {
    final query = _searchQuery.trim().toLowerCase();
    return bookings.where((booking) {
      final matchesStatus =
          _statusFilter == 'All' ||
          statusLabelForRole(null, booking) == _statusFilter;
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
      return matchesBooking(booking, query);
    }).toList();
  }

  String _userName(String? userId, String fallback) {
    final user = _usersById[userId];
    final name = user?.name?.trim();
    return name?.isNotEmpty == true ? name! : fallback;
  }

  @override
  void dispose() {
    _bookingsSubscription?.cancel();
    super.dispose();
  }

  String _userPhone(String? userId) {
    final user = _usersById[userId];
    final phone = user?.phone?.trim();
    return phone?.isNotEmpty == true ? phone! : '-';
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

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
}
