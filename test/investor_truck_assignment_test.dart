import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/services/investor_scope.dart';
import 'package:webapp/views/admin/admin_vehicle_makes.dart';

/// A truck has no owner field. Who owns it is read off whoever is crewed on it,
/// so these pin that the dialog and the list both agree with that, and that the
/// free-text Investor ID box is genuinely gone.
const investor = UserModel(id: 'inv-1', role: 'investor', name: 'Dela Cruz');
const otherInvestor = UserModel(id: 'inv-2', role: 'investor', name: 'Reyes');
const ben = UserModel(
  id: '8',
  role: 'driver',
  name: 'Ben',
  parentClientId: 'inv-1',
);
const ana = UserModel(
  id: '9',
  role: 'helper',
  name: 'Ana',
  parentClientId: 'inv-1',
);
const pio = UserModel(id: '12', role: 'driver', name: 'Pio');
const liza = UserModel(id: '13', role: 'helper', name: 'Liza');

const type = VehicleCatalogItem(id: '1', name: 'Truck');

final ownedTruck = VehicleMake(
  id: '4',
  code: 'PM 4',
  type: type,
  driver: ben,
  helper: ana,
);
final companyTruck = VehicleMake(
  id: '7',
  code: 'PM 7',
  type: type,
  driver: pio,
  helper: liza,
);
const crew = [ben, ana, pio, liza];
const allUsers = [investor, otherInvestor, ben, ana, pio, liza];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ownership is read off the crew', () {
    test('an investor truck resolves to its investor', () {
      final byId = {for (final u in allUsers) u.id!: u};
      expect(InvestorScope.investorForMake(ownedTruck, byId), 'inv-1');
    });

    test('a company truck resolves to nobody', () {
      final byId = {for (final u in allUsers) u.id!: u};
      expect(InvestorScope.investorForMake(companyTruck, byId), isNull);
    });
  });

  group('the make dialog', () {
    testWidgets('has no free-text investor field to mistype', (tester) async {
      VehicleMake? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  saved = await showVehicleMakeDialog(
                    context,
                    title: 'Edit Make',
                    initialItem: ownedTruck,
                    types: const [type],
                    drivers: const [ben, pio],
                    helpers: const [ana, liza],
                    investors: const [investor, otherInvestor],
                    onSaveAsync: (item) async => saved = item,
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

      // The field is gone: an investor is an account, not something typed.
      expect(
        find.textContaining('Investor ID'),
        findsNothing,
        reason: 'an investor is chosen from accounts, never typed',
      );
      // The crew fields that decide ownership are still there. The dropdown
      // shows its prompt rather than a label until something is chosen.
      expect(find.text('Code'), findsOneWidget);
      expect(find.text('Select Driver'), findsWidgets);
      expect(find.text('Select Helper'), findsWidgets);

      // Saving keeps the crew, and with it the ownership.
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved?.driver?.id, '8');
      expect(saved?.helper?.id, '9');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
    });

    testWidgets('a truck already crewed across two owners cannot be saved', (
      tester,
    ) async {
      // A company driver on an investor's helper: the truck would have no owner,
      // so both would be billed. The crew stays visible so it can be corrected,
      // but it cannot be saved back unchanged.
      final mixed = VehicleMake(
        id: '5',
        code: 'PM 5',
        type: type,
        driver: pio,
        helper: ana,
      );
      VehicleMake? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  saved = await showVehicleMakeDialog(
                    context,
                    title: 'Edit Make',
                    initialItem: mixed,
                    types: const [type],
                    drivers: const [ben, pio],
                    helpers: const [ana, liza],
                    investors: const [investor, otherInvestor],
                    onSaveAsync: (item) async => saved = item,
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
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(find.textContaining('not from the same owner'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
    });
  });

  group('persistence', () {
    test('a make writes exactly the fields it always did', () {
      // The whole key set, not a check that one field is missing. A future
      // field would fail this, and the shape is pinned to what the office has
      // always stored - which is the point: an investor is an account, not a
      // thing bolted onto a truck.
      expect(ownedTruck.toMap().keys.toSet(), {
        'id',
        'code',
        'type',
        'driver',
        'helper',
        'is_active',
        'created_at',
        'updated_at',
      });
    });

    test('a user writes exactly the fields it always did', () {
      expect(ben.toMap().keys.toSet(), {
        'id',
        'role',
        'parent_client_id',
        'email',
        'name',
        'photo',
        'phone',
        'position',
        'is_active',
        'is_online',
        'password',
        'created_at',
        'updated_at',
      });
    });

    test('a round trip keeps the crew that decides ownership', () {
      final restored = VehicleMake.fromJson(ownedTruck.toJson());
      final byId = {for (final u in allUsers) u.id!: u};
      expect(InvestorScope.investorForMake(restored, byId), 'inv-1');
      expect(restored.copyWith(isActive: false).driver?.id, '8');
    });

    test('the crew link is the one that survives a round trip', () {
      expect(UserModel.fromJson(ben.toJson()).parentClientId, 'inv-1');
    });
  });
}
