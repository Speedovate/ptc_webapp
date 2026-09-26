import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/repositories/local/booking_storage_backend.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/services/firebase_auth_bridge_service.dart';
import 'package:webapp/services/offline_cleanup_queue_service.dart';
import 'package:webapp/services/offline_media_sync_service.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/photo_storage_service.dart';
import 'package:webapp/services/support_storage_service.dart';

/// A driver signs up with the vehicle they bring. The truck has to exist as a
/// real make from that moment, carrying the new driver and no helper, because
/// the helper is the office's decision. A code already in use is refused before
/// anything is written, so a rejected signup never leaves an orphan driver.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  DriverModel driverModel({
    String email = 'driver@example.com',
    String phone = '09171230001',
  }) {
    return DriverModel(
      role: 'driver',
      email: email,
      name: 'Ben Driver',
      phone: phone,
      password: 'secret123',
      license: null,
      vehicleType: const VehicleCatalogItem(id: '1', name: 'Truck'),
      isActive: false,
      isOnline: false,
    );
  }

  ({AuthRequest request, FakeFirebaseFirestore firestore}) build() {
    final firestore = FakeFirebaseFirestore();
    final mutationService = OfflineMutationQueueService(
      firestore: firestore,
      backend: _MemoryBookingStorageBackend(),
    );
    return (
      request: AuthRequest(
        firestore: firestore,
        vehicleRequest: VehicleRequest(
          firestore: firestore,
          offlineMutationQueueService: mutationService,
          offlineQueueInitializer: () async {},
        ),
        firebaseAuthBridgeService: FirebaseAuthBridgeService(
          firestore: firestore,
        ),
        photoStorageService: _FakeUserPhotoStorageService(),
        offlineMutationQueueService: mutationService,
        offlineMediaSyncService: OfflineMediaSyncService(
          firestore: firestore,
          backend: _MemoryBookingStorageBackend(),
          photoStorageService: _FakeUserPhotoStorageService(),
          supportStorageService: _FakeSupportStorageService(),
        ),
        offlineQueueInitializer: () async {},
        offlineQueueFlusher: () async {},
      ),
      firestore: firestore,
    );
  }

  test(
    'a driver signup opens the vehicle make with no helper assigned',
    () async {
      final harness = build();

      final user = await harness.request.register(
        driverModel(),
        vehicleCode: 'PM1',
      );

      final makes = await harness.firestore.collection('vehicle_makes').get();
      expect(makes.docs, hasLength(1));
      final make = makes.docs.single;
      expect(make.get('code'), 'PM1');
      expect(make.get('driver_id'), user.id);
      expect(make.data()['helper_id'], isNull);
      // The make points at the same catalog entry the driver picked at signup.
      expect(make.get('type_id'), '1');
      expect(make.get('is_active'), isTrue);
    },
  );

  test('the code is normalized to uppercase before it is stored', () async {
    final harness = build();

    final user = await harness.request.register(
      driverModel(email: 'other@example.com', phone: '09171230007'),
      vehicleCode: '  pm 7 ',
    );

    final make =
        (await harness.firestore.collection('vehicle_makes').get()).docs.single;
    expect(make.get('code'), 'PM 7');
    expect(make.get('driver_id'), user.id);
  });

  test('a taken code is refused and no driver is created', () async {
    final harness = build();
    await harness.firestore.collection('vehicle_makes').doc('4').set({
      'id': '4',
      'code': 'PM1',
      'driver_id': '8',
      'is_active': true,
    });

    await expectLater(
      harness.request.register(
        driverModel(email: 'third@example.com', phone: '09171230003'),
        vehicleCode: 'pm1',
      ),
      throwsA(
        isA<AuthFailure>().having(
          (failure) => failure.message,
          'message',
          contains('already taken'),
        ),
      ),
    );

    // Nothing partial survives a rejected signup.
    expect((await harness.firestore.collection('users').get()).docs, isEmpty);
    expect(
      (await harness.firestore.collection('vehicle_makes').get()).docs,
      hasLength(1),
    );
  });

  test('a non-driver signup never opens a vehicle make', () async {
    final harness = build();

    await harness.request.register(
      const UserModel(
        role: 'helper',
        email: 'helper@example.com',
        name: 'Ana Helper',
        phone: '09171230004',
        password: 'secret123',
      ),
      vehicleCode: 'PM9',
    );

    expect(
      (await harness.firestore.collection('vehicle_makes').get()).docs,
      isEmpty,
    );
    expect(
      (await harness.firestore.collection('users').get()).docs,
      hasLength(1),
    );
  });

  test(
    'a code stored before the uppercase rule still counts as taken',
    () async {
      final harness = build();
      await harness.firestore.collection('vehicle_makes').doc('4').set({
        'id': '4',
        'code': 'pm 5',
        'driver_id': '8',
        'is_active': true,
      });

      await expectLater(
        harness.request.register(
          driverModel(email: 'legacy@example.com', phone: '09171230005'),
          vehicleCode: 'PM 5',
        ),
        throwsA(isA<AuthFailure>()),
      );
    },
  );

  group('the makes badge counts trucks the office still has to finish', () {
    const ben = UserModel(id: '8', role: 'driver', name: 'Ben');
    const ana = UserModel(id: '9', role: 'helper', name: 'Ana');

    test('a driver-only make, a helper-only make and an empty make count', () {
      const driverOnly = VehicleMake(
        id: '1',
        code: 'PM1',
        driver: ben,
        isActive: true,
      );
      const helperOnly = VehicleMake(
        id: '2',
        code: 'PM2',
        helper: ana,
        isActive: true,
      );
      const empty = VehicleMake(id: '3', code: 'PM3', isActive: true);

      expect(
        [driverOnly, helperOnly, empty].where((m) => m.needsCrew),
        hasLength(3),
      );
    });

    test('a fully crewed make does not count', () {
      const crewed = VehicleMake(
        id: '4',
        code: 'PM4',
        driver: ben,
        helper: ana,
        isActive: true,
      );
      expect(crewed.needsCrew, isFalse);
    });

    test('a retired truck is not the office to finish', () {
      const retired = VehicleMake(
        id: '5',
        code: 'PM5',
        driver: ben,
        isActive: false,
      );
      expect(retired.needsCrew, isFalse);
    });
  });
}

class _MemoryBookingStorageBackend implements BookingStorageBackend {
  final Map<String, List<String>> _store = {};

  @override
  Future<void> initialize() async {}

  @override
  Future<List<String>> readStringList(String key) async {
    return List<String>.from(_store[key] ?? const []);
  }

  @override
  Future<void> writeStringList(String key, List<String> values) async {
    _store[key] = List<String>.from(values);
  }
}

class _FakeFirebaseStorage implements FirebaseStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUserPhotoStorageService extends PhotoStorageService {
  _FakeUserPhotoStorageService()
    : super(
        storage: _FakeFirebaseStorage(),
        offlineCleanupQueueService: OfflineCleanupQueueService(
          backend: _MemoryBookingStorageBackend(),
          storage: _FakeFirebaseStorage(),
        ),
      );
}

class _FakeSupportStorageService extends SupportStorageService {
  _FakeSupportStorageService() : super(storage: _FakeFirebaseStorage());
}
