import 'package:stacked/stacked.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/status_definition.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/repositories/local/local_auth_repository.dart';
import 'package:webapp/repositories/local/local_booking_repository.dart';
import 'package:webapp/repositories/local/local_status_form_repository.dart';

class ClientBookingHistoryViewModel extends BaseViewModel {
  ClientBookingHistoryViewModel()
      : _bookingRepository = LocalBookingRepository.instance,
        _authRepository = LocalAuthRepository.instance,
        _statusRepository = LocalStatusFormRepository.instance;

  final LocalBookingRepository _bookingRepository;
  final AuthRepository _authRepository;
  final LocalStatusFormRepository _statusRepository;
  final Map<String, UserModel> _usersById = {};
  final Map<String, StatusDefinition> _statusesByKey = {};

  List<Booking> bookings = [];
  bool isLoading = false;
  String? errorMessage;

  Future<void> load(UserModel user) async {
    if (isLoading) {
      return;
    }
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      await _bookingRepository.initialize();
      final users = await _authRepository.getUsers();
      final statuses = await _statusRepository.getStatuses();
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

      final allBookings = await _bookingRepository.getBookings();
      final currentUserId = user.id ?? '';
      bookings = switch (user.role) {
        'client' => allBookings
            .where((booking) => booking.clientId == currentUserId)
            .toList(),
        'driver' => allBookings
            .where((booking) => booking.driverId == currentUserId)
            .toList(),
        'helper' => allBookings
            .where((booking) => booking.helperId == currentUserId)
            .toList(),
        _ => const [],
      };
    } catch (_) {
      errorMessage = 'Failed to load booking history.';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  String clientName(Booking booking) => _userName(booking.clientId, 'Unknown client');

  String clientPhone(Booking booking) => _userPhone(booking.clientId);

  String driverName(Booking booking) => _userName(booking.driverId, '-');

  String driverPhone(Booking booking) => _userPhone(booking.driverId);

  String helperName(Booking booking) => _userName(booking.helperId, '-');

  String helperPhone(Booking booking) => _userPhone(booking.helperId);

  String statusLabelForRole(String? role, Booking booking) {
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
}
