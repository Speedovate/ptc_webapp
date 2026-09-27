import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/views/admin/admin_vehicle_makes.dart';

import 'booking_id_resolver_test.dart' show MemoryBackend;
import 'support/merge_aware_firestore.dart';

const investorDriver = UserModel(id: '8', role: 'driver', name: 'Ben');
const companyTruck = VehicleMake(
  id: '4',
  code: 'PM 4',
  type: VehicleCatalogItem(id: '1', name: 'Truck'),
  driver: investorDriver,
);

/// The ownership field is free text on purpose, so these tests exercise the two
/// ends that matter: marking a truck as somebody's, and taking it back.
Future<VehicleMake?> _editMake(
  WidgetTester tester,
  VehicleMake initial, {
  required Future<void> Function(VehicleMake item) onSave,
}) async {
  VehicleMake? saved;
  // Left at the default test viewport on purpose: this dialog used to overflow
  // here once it carried a fifth field.
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
                types: [companyTruck.type!],
                drivers: [investorDriver],
                onSaveAsync: onSave,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  // The modal guard debounces real time between openings.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 400)),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return saved;
}

Finder _investorField() => find.widgetWithText(
  TextField,
  'Investor ID (blank = Paltranco owns this truck)',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('truck ownership', () {
    testWidgets('marking a truck as an investor lands on the saved make', (
      tester,
    ) async {
      VehicleMake? saved;
      var finished = false;
      // `onSaveAsync` closes the dialog, so capture through it and keep the
      // handle the caller normally reads after the fact.
      await _editMake(
        tester,
        companyTruck,
        onSave: (item) async {
          saved = item;
          finished = true;
        },
      );
      expect(_investorField(), findsOneWidget);
      await tester.enterText(_investorField(), 'inv-001');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(finished, isTrue);
      expect(saved?.investorId, 'inv-001');
      // The rest of the make is untouched by ownership.
      expect(saved?.code, 'PM 4');
      expect(saved?.driver?.id, '8');
      expect(tester.takeException(), isNull);
    });

    testWidgets('blank text hands the truck back to Paltranco', (tester) async {
      final owned = companyTruck.copyWith(investorId: 'inv-001');
      VehicleMake? saved;
      var finished = false;
      await _editMake(
        tester,
        owned,
        onSave: (item) async {
          saved = item;
          finished = true;
        },
      );
      // The existing owner is shown, so this is a visible state to clear.
      expect(
        tester.widget<TextField>(_investorField()).controller!.text,
        'inv-001',
      );
      await tester.enterText(_investorField(), '');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(finished, isTrue);
      expect(saved?.investorId, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a company truck starts blank rather than carrying an owner', (
      tester,
    ) async {
      VehicleMake? saved;
      var finished = false;
      await _editMake(
        tester,
        companyTruck,
        onSave: (item) async {
          saved = item;
          finished = true;
        },
      );
      expect(tester.widget<TextField>(_investorField()).controller!.text, '');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(finished, isTrue);
      expect(saved?.investorId, isNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('ownership persistence', () {
    test('the owner id is written to the make document', () async {
      final db = MergeAwareFirestore();
      final backend = MemoryBackend();
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => true,
      );
      final request = VehicleRequest(
        firestore: db,
        offlineMutationQueueService: queue,
        offlineQueueInitializer: () async {},
      );
      await request.saveMake(companyTruck.copyWith(investorId: 'inv-001'));
      final saved = (await db.collection('vehicle_makes').doc('4').get())
          .data()!;
      expect(saved['investor_id'], 'inv-001');

      // Clearing it must not leave a stale owner behind on the document, or
      // the statement keeps attributing trips to an investor who gave it up.
      await request.saveMake(companyTruck.copyWith(id: '4'));
      final cleared = (await db.collection('vehicle_makes').doc('4').get())
          .data()!;
      expect(cleared['investor_id'] == null, isTrue);
    });

    test('ownership survives a copyWith that does not mention it', () {
      final owned = companyTruck.copyWith(investorId: 'inv-001');
      expect(owned.copyWith(isActive: false).investorId, 'inv-001');
      expect(owned.copyWith(driver: null).investorId, 'inv-001');
      expect(owned.copyWith(id: '4').investorId, 'inv-001');
      expect(VehicleMake.fromJson(owned.toJson()).investorId, 'inv-001');
    });
  });
}
