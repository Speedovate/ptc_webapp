import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/chassis.dart';
import 'package:webapp/models/status.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/chassis.request.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/repositories/interfaces/booking_repository.dart';
import 'package:webapp/repositories/interfaces/status_form_repository.dart';
import 'package:webapp/services/app_warmup_service.dart';
import 'package:webapp/view_models/shared/role_assigned_home.vm.dart';

class _Bookings extends Fake implements BookingRepository {
  final stream = StreamController<List<Booking>>.broadcast();
  final read = Completer<List<Booking>>();
  @override
  Future<void> initialize() async {}
  @override
  Future<List<Booking>> getBookings() => read.future;
  @override
  Stream<List<Booking>> watchBookings() => stream.stream;
}

class _Chassis extends Fake implements ChassisRequest {
  final stream = StreamController<List<Chassis>>.broadcast();
  final read = Completer<List<Chassis>>();
  bool resolved = false;
  int reads = 0;
  @override
  bool get hasResolvedChassis => resolved;
  @override
  Future<List<Chassis>> getChassis() {
    reads++;
    return read.future;
  }

  @override
  Stream<List<Chassis>> watchChassis() => stream.stream;
}

class _Auth extends Fake implements AuthRepository {
  final read = Completer<List<UserModel>>();
  @override
  Future<List<UserModel>> getUsers() => read.future;
}

class _Statuses extends Fake implements StatusFormRepository {
  final read = Completer<List<Status>>();
  @override
  Future<List<Status>> getStatuses() => read.future;
}

class _Warmup extends Fake implements AppWarmupService {
  int calls = 0;
  @override
  Future<void> warmUpForUser(UserModel? user) async {
    calls++;
  }
}

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  const driver = UserModel(id: '1', role: 'driver');
  const helper = UserModel(id: '2', role: 'helper');
  late _Bookings bookings;
  late _Chassis chassis;
  late _Auth auth;
  late _Statuses statuses;
  late _Warmup warmup;
  late RoleAssignedHomeViewModel vm;

  setUp(() {
    RoleAssignedHomeViewModel.clearCachedState();
    bookings = _Bookings();
    chassis = _Chassis();
    auth = _Auth();
    statuses = _Statuses();
    warmup = _Warmup();
    vm = RoleAssignedHomeViewModel(
      bookingRepository: bookings,
      chassisRequest: chassis,
      authRepository: auth,
      statusRepository: statuses,
      warmupService: warmup,
    );
  });
  tearDown(() async {
    vm.dispose();
    await bookings.stream.close();
    await chassis.stream.close();
  });

  test(
    'home shows only today pickup schedules, earliest first, without changing assignments',
    () {
      Booking scheduled(
        String id,
        String date,
        String time,
        DateTime created,
      ) => Booking(
        id: id,
        createdAt: created,
        statusOutputs: {
          'pending': {
            'fields': {'pick_up_date': date, 'pick_up_time': time},
          },
        },
      );
      vm.assignedBookings = [
        scheduled('late', '2026-09-20', '4:00 PM', DateTime(2020)),
        scheduled('tomorrow', '2026-09-21', '06:00', DateTime(2020)),
        scheduled('early', '2026-09-20', '08:00', DateTime(2026)),
        scheduled('yesterday', '2026-09-19', '23:59', DateTime(2020)),
        const Booking(id: 'missing'),
        scheduled('noon', '2026-09-20', '12:00 PM', DateTime(2025)),
      ];
      expect(vm.bookingsForToday(now: DateTime(2026, 9, 20)).map((b) => b.id), [
        'early',
        'noon',
        'late',
      ]);
      expect(vm.bookingsForToday(now: DateTime(2026, 9, 21)).map((b) => b.id), [
        'tomorrow',
      ]);
      expect(vm.assignedBookings.length, 6);
    },
  );

  test(
    'driver waits for chassis, but not users, statuses or pending get',
    () async {
      final load = vm.load(driver);
      await flush();
      bookings.stream.add([
        const Booking(id: '1', driver: driver, clientStatus: 'pending'),
        const Booking(id: '2', clientStatus: 'return'),
        const Booking(id: '3', driver: driver, clientStatus: 'cancelled'),
        const Booking(id: '4', driver: driver, clientStatus: 'delivered'),
        const Booking(
          id: '5',
          driver: UserModel(id: '9'),
          clientStatus: 'pending',
        ),
      ]);
      chassis.stream.add(
        [],
      ); // unresolved initial memory must not release startup
      await flush();
      expect(vm.isBusy, isTrue);
      expect(vm.hasResolvedInitialBookings, isFalse);
      expect(warmup.calls, 0);
      chassis.resolved = true;
      chassis.stream.add([
        const Chassis(
          id: 1,
          name: 'C',
          isActive: true,
          currentStatus: Chassis.returning,
          currentBookingId: 2,
          currentDriverId: 1,
        ),
      ]);
      await load;
      expect(vm.isBusy, isFalse);
      expect(vm.assignedBookings.map((b) => b.id), ['1', '2']);
      expect(auth.read.isCompleted, isFalse);
      expect(statuses.read.isCompleted, isFalse);
      expect(bookings.read.isCompleted, isFalse);
      // A late get result must not overwrite the newer stream state.
      bookings.read.complete([]);
      chassis.read.complete([]);
      await flush();
      expect(vm.assignedBookings.map((b) => b.id), ['1', '2']);
      chassis.stream.add([]);
      await flush();
      expect(vm.assignedBookings.map((b) => b.id), ['1']);
    },
  );

  test('helper resolves confirmed empty without reading chassis', () async {
    final load = vm.load(helper);
    await flush();
    expect(vm.hasResolvedInitialBookings, isFalse);
    bookings.read.complete([]);
    await load;
    expect(vm.hasResolvedInitialBookings, isTrue);
    expect(vm.isBusy, isFalse);
    expect(vm.assignedBookings, isEmpty);
    expect(chassis.reads, 0);
  });

  test('essential failure releases startup and realtime can recover', () async {
    final load = vm.load(driver);
    await flush();
    bookings.read.complete([]);
    chassis.read.completeError(StateError('offline without cache'));
    await load;
    expect(vm.errorMessage, isNotNull);
    expect(vm.hasResolvedInitialBookings, isTrue);
    expect(vm.isBusy, isFalse);
    chassis.resolved = true;
    chassis.stream.add([]);
    await flush();
    expect(vm.errorMessage, isNull);
    expect(vm.assignedBookings, isEmpty);
  });

  test('supporting failure does not discard usable assignments', () async {
    final load = vm.load(helper);
    await flush();
    bookings.read.complete([
      const Booking(id: '7', helper: helper, clientStatus: 'pending'),
    ]);
    await load;
    auth.read.completeError(StateError('users unavailable'));
    statuses.read.complete([]);
    await flush();
    expect(vm.errorMessage, isNull);
    expect(vm.assignedBookings.single.id, '7');
  });

  test('account change clears old assignments before new result', () async {
    final load = vm.load(helper);
    await flush();
    bookings.stream.add([
      const Booking(id: '7', helper: helper, clientStatus: 'pending'),
    ]);
    await load;
    final second = vm.load(const UserModel(id: '3', role: 'helper'));
    expect(vm.assignedBookings, isEmpty);
    expect(vm.isBusy, isTrue);
    await flush();
    bookings.stream.add([]);
    await second;
    auth.read.complete([helper]);
    statuses.read.complete([]);
    await flush();
    expect(vm.currentUser?.id, '3');
    expect(vm.assignedBookings, isEmpty);
  });

  test('disposed home ignores late requests', () async {
    final load = vm.load(driver);
    await flush();
    vm.dispose();
    await load;
    bookings.read.complete([const Booking(id: '7', driver: driver)]);
    chassis.read.complete([]);
    await flush();
    expect(vm.assignedBookings, isEmpty);
    // Avoid disposing the same ChangeNotifier twice in tearDown.
    vm = RoleAssignedHomeViewModel(
      bookingRepository: bookings,
      chassisRequest: chassis,
      authRepository: auth,
      statusRepository: statuses,
      warmupService: warmup,
    );
  });
}
