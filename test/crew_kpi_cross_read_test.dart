import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/dispatcher_access_config.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/services/kpi/crew_kpi_store.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:webapp/views/shared/profile_view.dart';

class _Store extends CrewKpiStore {
  _Store({this.bookings = const []});

  /// Bookings handed to the view. The store scopes these to the crew member in
  /// production, so the stub supplies the matching driver_id/helper_id.
  final List<Map<String, dynamic>> bookings;

  @override
  Future<Map<String, dynamic>?> readCached(UserModel user) async => {
    'records': <Map<String, dynamic>>[],
    'incidents': <Map<String, dynamic>>[],
    'makes': <Map<String, dynamic>>[],
    'bookings': bookings,
    'catalog': <String, dynamic>{},
  };

  @override
  Future<Map<String, dynamic>?> load(UserModel user) => readCached(user);
}

Map<String, dynamic> _trip(
  String id, {
  required String role,
  required String ownerId,
  String status = 'delivered',
  String? deliveredAt,
}) => {
  'id': id,
  '${role}_id': ownerId,
  'client_status': status,
  'created_at': '2026-09-02T02:00:00.000Z',
  'delivered_at': ?deliveredAt,
};

UserModel _crew(String id, String role) =>
    UserModel(id: id, name: 'Crew $id', role: role, isActive: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => RoleAccessService.instance.setCurrentUser(null));

  group('cross-crew KPI permission defaults', () {
    test('admin is the only role enabled out of the box', () {
      final defaults = <String, Map<String, bool>>{
        for (final role in [
          'admin',
          'manager',
          'dispatcher',
          'driver',
          'helper',
        ])
          role: defaultAccessCapabilitiesForRole(role),
      };
      expect(
        defaults['admin']![DispatcherAccessCapability.crewKpiRead],
        isTrue,
        reason: 'admin is the role the office audits from',
      );
      for (final role in ['manager', 'dispatcher', 'driver', 'helper']) {
        expect(
          defaults[role]![DispatcherAccessCapability.crewKpiRead],
          isFalse,
          reason: '$role must be granted the permission deliberately',
        );
      }
    });

    test('the permission is listed in the role access values', () {
      expect(
        DispatcherAccessCapability.values,
        contains(DispatcherAccessCapability.crewKpiRead),
      );
    });
  });

  group('CrewKpiStore.canReadAs', () {
    test('admin may read a driver and a helper', () {
      final admin = UserModel(id: '1', name: 'Admin', role: 'admin');
      expect(CrewKpiStore.canReadAs(admin, _crew('12', 'driver')), isTrue);
      expect(CrewKpiStore.canReadAs(admin, _crew('23', 'helper')), isTrue);
    });

    test('a crew member always reads their own record', () {
      final driver = _crew('12', 'driver');
      expect(CrewKpiStore.canReadAs(driver, driver), isTrue);
      expect(CrewKpiStore.canView(driver), isTrue);
    });

    test('a crew member cannot read another crew member', () {
      final driver = _crew('12', 'driver');
      expect(CrewKpiStore.canReadAs(driver, _crew('23', 'helper')), isFalse);
      expect(
        CrewKpiStore.canReadAs(driver, _crew('13', 'driver')),
        isFalse,
        reason: 'own_kpi.read must not become cross-crew access',
      );
    });

    test('manager and dispatcher are refused until the role is granted', () {
      for (final role in ['manager', 'dispatcher']) {
        final viewer = UserModel(id: '8', name: role, role: role);
        expect(
          CrewKpiStore.canReadAs(viewer, _crew('12', 'driver')),
          isFalse,
          reason: '$role has no cross-crew KPI permission by default',
        );
      }
    });

    test('a KPI record never belongs to a non-crew account', () {
      final admin = UserModel(id: '1', name: 'Admin', role: 'admin');
      expect(CrewKpiStore.isCrewMember(_crew('12', 'driver')), isTrue);
      expect(CrewKpiStore.isCrewMember(_crew('23', 'helper')), isTrue);
      expect(
        CrewKpiStore.canReadAs(admin, UserModel(id: '9', role: 'client')),
        isFalse,
      );
      expect(
        CrewKpiStore.canReadAs(admin, UserModel(id: '1', role: 'admin')),
        isFalse,
        reason: 'there is no KPI record for an admin to read',
      );
    });

    test('an anonymous viewer is refused', () {
      final anonymous = UserModel(id: null, role: null);
      expect(CrewKpiStore.canReadAs(anonymous, _crew('12', 'driver')), isFalse);
    });
  });

  group('profile page visibility', () {
    Future<void> pumpProfile(
      WidgetTester tester, {
      required UserModel viewer,
      required UserModel subject,
      bool isCurrentUserView = false,
      _Store? store,
    }) async {
      RoleAccessService.instance.setCurrentUser(viewer);
      // The KPI card makes the profile taller than the default 600px surface.
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileView(
              user: subject,
              scrollable: false,
              padding: EdgeInsets.zero,
              kpiStore: store ?? _Store(),
              isCurrentUserView: isCurrentUserView,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('an admin sees the booking count and KPIs on a crew profile', (
      tester,
    ) async {
      await pumpProfile(
        tester,
        viewer: UserModel(id: '1', name: 'Admin', role: 'admin'),
        subject: _crew('12', 'driver'),
      );

      expect(find.text('KPI summary'), findsOneWidget);
      expect(find.text('Bookings'), findsOneWidget);
      expect(find.text('Shares'), findsOneWidget);
      expect(find.text('Salary'), findsOneWidget);
    });

    testWidgets('a manager sees no KPI data until the role is granted', (
      tester,
    ) async {
      await pumpProfile(
        tester,
        viewer: UserModel(id: '8', name: 'Manager', role: 'manager'),
        subject: _crew('12', 'driver'),
      );

      expect(find.text('KPI summary'), findsNothing);
      expect(find.text('Bookings'), findsNothing);
      // The rest of the profile is untouched.
      expect(find.text('Vehicle assignment'), findsOneWidget);
    });

    testWidgets('the driver still sees their own KPI summary', (tester) async {
      final driver = _crew('12', 'driver');
      await pumpProfile(
        tester,
        viewer: driver,
        subject: driver,
        isCurrentUserView: true,
      );

      expect(find.text('KPI summary'), findsOneWidget);
      expect(find.text('Bookings'), findsOneWidget);
    });

    testWidgets('shows delivered out of total bookings', (tester) async {
      final today = DateTime.now();
      final stamp = DateTime.utc(today.year, today.month, today.day, 3);
      await pumpProfile(
        tester,
        viewer: UserModel(id: '1', name: 'Admin', role: 'admin'),
        subject: _crew('12', 'driver'),
        store: _Store(
          bookings: [
            _trip(
              '1',
              role: 'driver',
              ownerId: '12',
              deliveredAt: stamp.toIso8601String(),
            ),
            _trip(
              '2',
              role: 'driver',
              ownerId: '12',
              deliveredAt: stamp.toIso8601String(),
            ),
            _trip(
              '3',
              role: 'driver',
              ownerId: '12',
              deliveredAt: stamp.toIso8601String(),
            ),
            _trip('4', role: 'driver', ownerId: '12', status: 'ongoing'),
          ],
        ),
      );

      // Three of the four assigned trips were delivered.
      expect(find.text('3/4'), findsOneWidget);
    });

    testWidgets('another driver trip never lands in these numbers', (
      tester,
    ) async {
      final today = DateTime.now();
      final stamp = DateTime.utc(today.year, today.month, today.day, 3);
      await pumpProfile(
        tester,
        viewer: UserModel(id: '1', name: 'Admin', role: 'admin'),
        subject: _crew('12', 'driver'),
        store: _Store(
          bookings: [
            _trip(
              '1',
              role: 'driver',
              ownerId: '12',
              deliveredAt: stamp.toIso8601String(),
            ),
            _trip(
              '2',
              role: 'driver',
              ownerId: '13',
              deliveredAt: stamp.toIso8601String(),
            ),
            _trip(
              '3',
              role: 'driver',
              ownerId: '13',
              deliveredAt: stamp.toIso8601String(),
            ),
          ],
        ),
      );

      expect(find.text('1/1'), findsOneWidget);
      expect(find.text('3/3'), findsNothing);
    });

    testWidgets('a helper profile is not offered to a non-crew subject', (
      tester,
    ) async {
      await pumpProfile(
        tester,
        viewer: UserModel(id: '1', name: 'Admin', role: 'admin'),
        subject: UserModel(id: '9', name: 'Client', role: 'client'),
      );

      expect(find.text('KPI summary'), findsNothing);
    });
  });

  test('kpi day key helper stays available for fixtures', () {
    expect(kpiDayKey(DateTime(2026, 9, 25)), '2026-09-25');
  });
}
