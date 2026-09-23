import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/views/admin/admin_vehicle_makes.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend, storageKey;
import 'support/merge_aware_firestore.dart';

const helper = UserModel(id: '9', role: 'helper', name: 'Ana');
const driver = UserModel(id: '8', role: 'driver', name: 'Ben');
const make = VehicleMake(
  id: '4',
  code: 'PM 4',
  type: VehicleCatalogItem(id: '1', name: 'Truck'),
  driver: driver,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'legacy and cached make records round-trip without losing helper on updates',
    () {
      expect(VehicleMake.fromMap({'id': '4', 'code': 'PM 4'}).helper, isNull);
      final assigned = make.copyWith(helper: helper);
      final restored = VehicleMake.fromJson(assigned.toJson());
      expect(restored.helper?.id, '9');
      expect(restored.copyWith(isActive: false).helper?.id, '9');
      expect(restored.copyWith(clearHelper: true).helper, isNull);
      expect(restored.driver?.id, '8');
    },
  );
  test(
    'request queues provisional helper reference and resolves it on replay',
    () async {
      final db = MergeAwareFirestore();
      final backend = MemoryBackend();
      var online = false;
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => online,
      );
      const temporary = 'offline_users_helper_make_test';
      await queue.queueOfflineCollectionDocumentCreate(
        collectionKey: 'users',
        provisionalId: temporary,
        submissionKey: 'helper-make-test',
        document: {
          'id': temporary,
          'name': 'Ana',
          'role': 'helper',
          'updated_at': '2026-09-20T00:00:00Z',
        },
      );
      final request = VehicleRequest(
        firestore: db,
        offlineMutationQueueService: queue,
        offlineQueueInitializer: () async {},
      );
      await request.saveMake(
        make.copyWith(
          helper: const UserModel(id: temporary, role: 'helper'),
        ),
      );
      final pending = (await backend.readStringList(
        storageKey,
      )).map(jsonDecode).toList();
      final pendingMake = pending
          .where((e) => e['collection_key'] == 'vehicle_makes')
          .single;
      expect(pendingMake['payload']['helper_id'], temporary);
      final actionTime = pendingMake['payload']['updated_at'];
      online = true;
      await queue.flushPendingMutations();
      await queue.flushPendingMutations();
      final users = (await db.collection('users').get()).docs;
      expect(users, hasLength(1));
      final saved = (await db.collection('vehicle_makes').doc('4').get())
          .data()!;
      expect(saved['helper_id'], users.single.id);
      expect(saved['driver_id'], '8');
      expect(saved['updated_at'], actionTime);
      expect(await backend.readStringList(storageKey), isEmpty);
    },
  );
  for (final width in [375.0, 1200.0]) {
    testWidgets('assign, retain unavailable helper, and unassign at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      VehicleMake? saved;
      var initial = make;
      var helpers = [helper];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  saved = await showVehicleMakeDialog(
                    context,
                    title: 'Edit Make',
                    initialItem: initial,
                    types: [make.type!],
                    drivers: [driver],
                    helpers: helpers,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not assigned'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Helper 9 | Ana').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved?.helper?.id, '9');
      initial = saved!;
      helpers = [];
      // The modal guard intentionally debounces real time between openings.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Helper 9 | Ana'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved?.helper?.id, '9');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Helper 9 | Ana'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not assigned').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved?.helper, isNull);
      expect(saved?.driver?.id, '8');
      expect(tester.takeException(), isNull);
    });
  }
}
