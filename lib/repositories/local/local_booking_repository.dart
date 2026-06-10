import 'package:webapp/models/booking.dart';
import 'package:webapp/repositories/interfaces/booking_repository.dart';

import 'booking_storage_backend.dart';

class LocalBookingRepository implements BookingRepository {
  LocalBookingRepository._();

  static final LocalBookingRepository instance = LocalBookingRepository._();

  static const _bookingsKey = 'paltranco_bookings';
  final BookingStorageBackend _storage = createBookingStorageBackend();

  @override
  Future<void> initialize() async {
    await _storage.initialize();
  }

  @override
  Future<List<Booking>> getBookings() async {
    await initialize();
    final raw = await _storage.readStringList(_bookingsKey);
    final bookings = raw.map(Booking.fromJson).toList();
    bookings.sort((a, b) {
      final createdComparison = _compareLatestFirst(a.createdAt, b.createdAt);
      if (createdComparison != 0) {
        return createdComparison;
      }

      final aId = int.tryParse(a.id ?? '');
      final bId = int.tryParse(b.id ?? '');
      if (aId != null && bId != null) {
        return bId.compareTo(aId);
      }
      return (b.id ?? '').compareTo(a.id ?? '');
    });
    return bookings;
  }

  @override
  Future<List<Booking>> getBookingsForClient(String clientId) async {
    final bookings = await getBookings();
    return bookings.where((booking) => booking.clientId == clientId).toList();
  }

  @override
  Future<Booking> saveBooking(Booking booking) async {
    await initialize();
    final bookings = await getBookings();
    final index = bookings.indexWhere((item) => item.id == booking.id);
    late final Booking savedBooking;

    if (index == -1) {
      final nextId = bookings
              .map((item) => int.tryParse(item.id ?? ''))
              .whereType<int>()
              .fold<int>(0, (max, value) => value > max ? value : max) +
          1;
      savedBooking = booking.copyWith(id: '$nextId');
      bookings.add(savedBooking);
    } else {
      savedBooking = booking;
      bookings[index] = savedBooking;
    }

    await _storage.writeStringList(
      _bookingsKey,
      bookings.map((item) => item.toJson()).toList(),
    );
    return savedBooking;
  }

  int _compareLatestFirst(DateTime? a, DateTime? b) {
    if (a == null && b == null) {
      return 0;
    }
    if (a == null) {
      return 1;
    }
    if (b == null) {
      return -1;
    }
    return b.compareTo(a);
  }
}
