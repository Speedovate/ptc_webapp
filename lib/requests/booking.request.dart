import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/repositories/interfaces/booking_repository.dart';
import 'package:webapp/utils/functions.dart';

class BookingRequest implements BookingRepository {
  BookingRequest({
    FirebaseFirestore? firestore,
    AuthRequest? authRequest,
    VehicleRequest? vehicleRequest,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _authRequest = authRequest ?? AuthRequest.instance,
       _vehicleRequest = vehicleRequest ?? VehicleRequest.instance;

  static final BookingRequest instance = BookingRequest();

  final FirebaseFirestore _firestore;
  final AuthRequest _authRequest;
  final VehicleRequest _vehicleRequest;

  CollectionReference<Map<String, dynamic>> get _bookingsCollection =>
      _firestore.collection('bookings');

  @override
  Future<void> initialize() async {}

  @override
  Future<List<Booking>> getBookings() async {
    final snapshot = await _bookingsCollection.get();
    return _inflateBookings(snapshot.docs.map(documentData).toList());
  }

  @override
  Stream<List<Booking>> watchBookings() {
    return _bookingsCollection.snapshots().asyncMap((snapshot) {
      return _inflateBookings(snapshot.docs.map(documentData).toList());
    });
  }

  @override
  Future<List<Booking>> getBookingsForClient(String clientId) async {
    final bookings = await getBookings();
    return bookings.where((booking) => booking.client?.id == clientId).toList();
  }

  @override
  Future<Booking> saveBooking(Booking booking) async {
    final existingBookings = await getBookings();
    final nextId = normalizeId(booking.id) ?? _nextBookingId(existingBookings);
    final now = DateTime.now();
    final saved = booking.copyWith(
      id: nextId,
      createdAt: booking.createdAt ?? now,
      updatedAt: now,
    );
    await _bookingsCollection.doc(nextId).set(_toFirestoreMap(saved));
    return saved;
  }

  Future<List<Booking>> _inflateBookings(
    List<Map<String, dynamic>> documents,
  ) async {
    final users = await _authRequest.getUsers();
    final makes = await _vehicleRequest.getMakes();
    final userById = {for (final item in users) item.id ?? '': item};
    final makeById = {for (final item in makes) item.id ?? '': item};
    final bookings = documents
        .map(
          (doc) => _bookingFromFirestoreMap(
            doc,
            userById: userById,
            makeById: makeById,
          ),
        )
        .toList();
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

  Map<String, dynamic> _toFirestoreMap(Booking booking) {
    return {
      'id': booking.id,
      'client_id': booking.client?.id,
      'client_status': booking.clientStatus,
      'driver_status': booking.driverStatus,
      'helper_status': booking.helperStatus,
      'truck_id': booking.truck?.id,
      'driver_id': booking.driver?.id,
      'helper_id': booking.helper?.id,
      'status_outputs': booking.statusOutputs,
      'created_at': booking.createdAt?.toIso8601String(),
      'updated_at': booking.updatedAt?.toIso8601String(),
    };
  }

  Booking _bookingFromFirestoreMap(
    Map<String, dynamic> map, {
    required Map<String, UserModel> userById,
    required Map<String, VehicleMake> makeById,
  }) {
    return Booking(
      id: map['id']?.toString(),
      client: userById[map['client_id']?.toString()],
      clientStatus: map['client_status']?.toString(),
      driverStatus: map['driver_status']?.toString(),
      helperStatus: map['helper_status']?.toString(),
      truck: makeById[map['truck_id']?.toString()],
      driver: userById[map['driver_id']?.toString()],
      helper: userById[map['helper_id']?.toString()],
      statusOutputs: map['status_outputs'] is Map
          ? Map<String, dynamic>.from(map['status_outputs'] as Map)
          : null,
      createdAt: _toDateTime(map['created_at']),
      updatedAt: _toDateTime(map['updated_at']),
    );
  }

  String _nextBookingId(List<Booking> bookings) {
    final highest = bookings
        .map((item) => int.tryParse(item.id ?? ''))
        .whereType<int>()
        .fold<int>(0, (max, value) => value > max ? value : max);
    return '${highest + 1}';
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

  DateTime? _toDateTime(dynamic value) {
    if (value == null) {
      return null;
    }
    return DateTime.tryParse(value.toString());
  }
}
