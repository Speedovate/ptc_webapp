import 'package:stacked/stacked.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/repositories/local/local_auth_repository.dart';
import 'package:webapp/repositories/local/local_booking_repository.dart';
import 'package:webapp/widgets/shared/booking_record_card.dart';

class AdminDashboardViewModel extends BaseViewModel {
  AdminDashboardViewModel({AuthRepository? authRepository})
    : _authRepository = authRepository ?? LocalAuthRepository.instance,
      _bookingRepository = LocalBookingRepository.instance;

  final AuthRepository _authRepository;
  final LocalBookingRepository _bookingRepository;

  final List<Booking> _completedBookings = [];
  final Map<String, UserModel> _usersById = {};

  List<Booking> get completedBookings => List.unmodifiable(_completedBookings);
  String? errorMessage;

  Future<void> load() async {
    setBusy(true);
    errorMessage = null;
    try {
      await _bookingRepository.initialize();
      final users = await _authRepository.getUsers();
      final bookings = await _bookingRepository.getBookings();

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
    } catch (_) {
      errorMessage = 'Failed to load completed bookings.';
    } finally {
      setBusy(false);
      notifyListeners();
    }
  }

  String client(Booking booking) {
    final client = _usersById[booking.clientId];
    final name = client?.name?.trim();
    return "${name?.isNotEmpty == true ? name! : 'Unknown client'} (${start(booking)} - ${end(booking)})"
        .toUpperCase();
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

  static String vanSize(Booking booking) =>
      BookingRecordCard.outputFieldDisplayValue(
        booking.statusOutputs,
        'van_size',
      ).toUpperCase();

  static String amount(Booking booking) =>
      BookingRecordCard.outputFieldDisplayValue(
        booking.statusOutputs,
        'amount',
      ).toUpperCase();
}
