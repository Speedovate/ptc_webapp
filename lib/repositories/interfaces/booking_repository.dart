import 'package:webapp/models/booking.dart';

abstract class BookingRepository {
  Future<void> initialize();
  Future<List<Booking>> getBookings();
  Stream<List<Booking>> watchBookings();
  Future<List<Booking>> getBookingsForClient(String clientId);
  Future<Booking> saveBooking(Booking booking);
}
