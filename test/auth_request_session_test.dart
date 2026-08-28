import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/requests/auth.request.dart';
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
    test('initialize remembers stored current and quick-login session ids', () async {
      SharedPreferences.setMockInitialValues({
        'paltranco_current_user_id': '7',
        'paltranco_quick_login_source_user_id': '1',
      });

      final firestore = FakeFirebaseFirestore();
      final mutationService = OfflineMutationQueueService(
        firestore: firestore,
        backend: _MemoryBookingStorageBackend(),
      );
      final bridgeService = FirebaseAuthBridgeService(
        firestore: firestore,
      );
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

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getStringList('paltranco_known_session_user_ids'),
        <String>['1', '7'],
      );
    });

    test('getCurrentUser remembers the active cached session id', () async {
      SharedPreferences.setMockInitialValues({
        'paltranco_current_user_id': '7',
      });

      final firestore = FakeFirebaseFirestore();
      final mutationService = OfflineMutationQueueService(
        firestore: firestore,
        backend: _MemoryBookingStorageBackend(),
      );
      final bridgeService = FirebaseAuthBridgeService(
        firestore: firestore,
      );
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

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getStringList('paltranco_known_session_user_ids'),
        contains('7'),
      );
      expect(
        prefs.getString('paltranco_current_session_auth_snapshot'),
        isNotEmpty,
      );
    });

    test('loginAsUser keeps previous current user as quick-login source', () async {
      SharedPreferences.setMockInitialValues({
        'paltranco_current_user_id': '1',
      });

      final firestore = FakeFirebaseFirestore();
      final mutationService = OfflineMutationQueueService(
        firestore: firestore,
        backend: _MemoryBookingStorageBackend(),
      );
      final bridgeService = FirebaseAuthBridgeService(
        firestore: firestore,
      );
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

      await request.loginAsUser('7');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('paltranco_current_user_id'), '7');
      expect(prefs.getString('paltranco_quick_login_source_user_id'), '1');
      expect(
        prefs.getStringList('paltranco_known_session_user_ids'),
        <String>['7', '1'],
      );
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
