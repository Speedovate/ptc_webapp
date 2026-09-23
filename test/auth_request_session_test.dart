import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/repositories/local/booking_storage_backend.dart';
import 'package:webapp/services/offline_media_sync_service.dart';
import 'package:webapp/services/offline_cleanup_queue_service.dart';
import 'package:webapp/services/firebase_auth_bridge_service.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/photo_storage_service.dart';
import 'package:webapp/services/support_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthRequest session anchors', () {
    test(
      'initialize remembers stored current and quick-login session ids',
      () async {
        await _seedSession({
          'paltranco_current_user_id': '7',
          'paltranco_quick_login_source_user_id': '1',
        });

        final firestore = FakeFirebaseFirestore();
        final mutationService = OfflineMutationQueueService(
          firestore: firestore,
          backend: _MemoryBookingStorageBackend(),
        );
        final bridgeService = FirebaseAuthBridgeService(firestore: firestore);
        final mediaService = OfflineMediaSyncService(
          firestore: firestore,
          backend: _MemoryBookingStorageBackend(),
          photoStorageService: _FakeUserPhotoStorageService(),
          supportStorageService: _FakeSupportStorageService(),
        );
        final request = AuthRequest(
          firestore: firestore,
          vehicleRequest: VehicleRequest(
            firestore: firestore,
            offlineMutationQueueService: mutationService,
            offlineQueueInitializer: () async {},
          ),
          firebaseAuthBridgeService: bridgeService,
          photoStorageService: _FakeUserPhotoStorageService(),
          offlineMutationQueueService: mutationService,
          offlineMediaSyncService: mediaService,
          offlineQueueInitializer: () async {},
          offlineQueueFlusher: () async {},
        );

        await request.initialize();

        final prefs = createAuthStorageBackend();
        await prefs.initialize();
        expect(
          await prefs.readStringList('paltranco_known_session_user_ids'),
          <String>['1', '7'],
        );
      },
    );

    test('getCurrentUser remembers the active cached session id', () async {
      await _seedSession({'paltranco_current_user_id': '7'});

      final firestore = FakeFirebaseFirestore();
      final mutationService = OfflineMutationQueueService(
        firestore: firestore,
        backend: _MemoryBookingStorageBackend(),
      );
      final bridgeService = FirebaseAuthBridgeService(firestore: firestore);
      final mediaService = OfflineMediaSyncService(
        firestore: firestore,
        backend: _MemoryBookingStorageBackend(),
        photoStorageService: _FakeUserPhotoStorageService(),
        supportStorageService: _FakeSupportStorageService(),
      );
      await firestore.collection('users').doc('7').set({
        'id': '7',
        'role': 'client',
        'name': 'Juan Dela Cruz',
        'email': 'juan@example.com',
        'phone': '09171234567',
        'password': 'secret123',
        'is_active': true,
      });

      final request = AuthRequest(
        firestore: firestore,
        vehicleRequest: VehicleRequest(
          firestore: firestore,
          offlineMutationQueueService: mutationService,
          offlineQueueInitializer: () async {},
        ),
        firebaseAuthBridgeService: bridgeService,
        photoStorageService: _FakeUserPhotoStorageService(),
        offlineMutationQueueService: mutationService,
        offlineMediaSyncService: mediaService,
        offlineQueueInitializer: () async {},
        offlineQueueFlusher: () async {},
      );

      final currentUser = await request.getCurrentUser();

      expect(currentUser?.id, '7');

      final prefs = createAuthStorageBackend();
      await prefs.initialize();
      expect(
        await prefs.readStringList('paltranco_known_session_user_ids'),
        contains('7'),
      );
      expect(
        await prefs.readString('paltranco_current_session_auth_snapshot'),
        isNotEmpty,
      );
    });

    test(
      'impersonation preserves original account across switches, returns and logs out',
      () async {
        await _seedSession({'paltranco_current_user_id': '1'});

        final firestore = FakeFirebaseFirestore();
        final mutationService = OfflineMutationQueueService(
          firestore: firestore,
          backend: _MemoryBookingStorageBackend(),
        );
        final bridgeService = FirebaseAuthBridgeService(firestore: firestore);
        final mediaService = OfflineMediaSyncService(
          firestore: firestore,
          backend: _MemoryBookingStorageBackend(),
          photoStorageService: _FakeUserPhotoStorageService(),
          supportStorageService: _FakeSupportStorageService(),
        );
        await firestore.collection('users').doc('7').set({
          'id': '7',
          'role': 'dispatcher',
          'name': 'Dispatcher User',
          'email': 'dispatcher@example.com',
          'phone': '09179990000',
          'password': 'secret123',
          'is_active': true,
        });

        final request = AuthRequest(
          firestore: firestore,
          vehicleRequest: VehicleRequest(
            firestore: firestore,
            offlineMutationQueueService: mutationService,
            offlineQueueInitializer: () async {},
          ),
          firebaseAuthBridgeService: bridgeService,
          photoStorageService: _FakeUserPhotoStorageService(),
          offlineMutationQueueService: mutationService,
          offlineMediaSyncService: mediaService,
          offlineQueueInitializer: () async {},
          offlineQueueFlusher: () async {},
        );

        await firestore.collection('users').doc('1').set({
          'id': '1',
          'role': 'admin',
          'name': 'Original Admin',
          'is_active': true,
        });
        await firestore.collection('users').doc('8').set({
          'id': '8',
          'role': 'helper',
          'name': 'Helper',
          'is_active': true,
        });
        await request.loginAsUser('7');

        final prefs = createAuthStorageBackend();
        await prefs.initialize();
        expect(await prefs.readString('paltranco_current_user_id'), '7');
        expect(
          await prefs.readString('paltranco_quick_login_source_user_id'),
          '1',
        );
        expect(
          await prefs.readStringList('paltranco_known_session_user_ids'),
          <String>['7', '1'],
        );
        await request.loginAsUser('8');
        expect(await prefs.readString('paltranco_current_user_id'), '8');
        expect(
          await prefs.readString('paltranco_quick_login_source_user_id'),
          '1',
        );
        final restored = await request.returnToQuickLoginSource();
        expect(restored?.id, '1');
        expect(await prefs.readString('paltranco_current_user_id'), '1');
        expect(await request.hasQuickLoginSource(), isFalse);
        await request.logout();
        expect(await prefs.readString('paltranco_current_user_id'), isNull);
        expect(await request.hasQuickLoginSource(), isFalse);

        // A missing source must not turn Go Back into Logout or erase its anchor.
        await prefs.writeString('paltranco_current_user_id', '7');
        await prefs.writeString(
          'paltranco_quick_login_source_user_id',
          'missing',
        );
        await prefs.remove('paltranco_quick_login_source_snapshot');
        await expectLater(
          request.returnToQuickLoginSource(),
          throwsA(isA<AuthFailure>()),
        );
        expect(await prefs.readString('paltranco_current_user_id'), '7');
        expect(
          await prefs.readString('paltranco_quick_login_source_user_id'),
          'missing',
        );
      },
    );
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

Future<void> _seedSession(Map<String, String> values) async {
  SharedPreferences.setMockInitialValues({});
  final storage = createAuthStorageBackend();
  await storage.initialize();
  const keys = [
    'paltranco_current_user_id',
    'paltranco_quick_login_source_user_id',
    'paltranco_known_session_user_ids',
    'paltranco_current_session_auth_snapshot',
    'paltranco_quick_login_source_snapshot',
  ];
  for (final key in keys) {
    await storage.remove(key);
  }
  addTearDown(() async {
    for (final key in keys) {
      await storage.remove(key);
    }
  });
  for (final entry in values.entries) {
    await storage.writeString(entry.key, entry.value);
  }
}
