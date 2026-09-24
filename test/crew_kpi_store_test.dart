import 'dart:convert';
import 'kpi_dynamic_role_access_test.dart' show RoleDocuments;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/models/dispatcher_access_config.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/requests/firestore_cache_store.dart';
import 'package:webapp/services/kpi/crew_kpi_store.dart';
import 'package:webapp/services/role_access_service.dart';

Map<String, dynamic> crewBooking(
  String id, {
  String driver = '13',
  String helper = '18',
  String status = 'delivered',
  String time = '2026-09-19T10:00:00Z',
}) => {
  'id': id,
  'driver_id': driver,
  'helper_id': helper,
  'vehicle_make_id': '4',
  'client_status': status,
  'delivered_at': time,
  'created_at': '2026-09-18T10:00:00Z',
  'submission_key': 'submission-$id',
  'status_outputs': {
    'book__1': {
      'status_key': 'book',
      'submitted_at': '2026-09-18T10:00:00Z',
      'fields': {
        'origin': 'Puerto Princesa City',
        'destination': 'Puerto Princesa City',
        'destination_barangay': 'San Jose',
        'waybill_photo': {'download_url': 'secret-photo'},
        'representative_phone': 'private-phone',
      },
    },
  },
};
Future<void> seedCrew(FakeFirebaseFirestore db) async {
  await db.collection('operations_catalog').doc('settings').set({});
  await db.collection('pm_kpi_records').doc('ZmxlZXQ_settings').set({
    'kind': 'settings',
  });
  for (final b in [
    crewBooking('1'),
    crewBooking('2', driver: '17', helper: '19'),
    crewBooking('3', status: 'pending'),
  ]) {
    await db.collection('bookings').doc(b['id']).set(b);
  }
  await db.collection('vehicle_makes').doc('4').set({
    'code': 'PM7',
    'driver_id': '13',
    'helper_id': '18',
  });
  await db.collection('pm_kpi_records').doc('NA_settings').set({
    'kind': 'settings',
    'user_incident_counts': {
      '13': {
        '2026-09-19': {'complaints': 1, 'accidents': 0},
      },
      '18': {
        '2026-09-19': {'complaints': 0, 'accidents': 1},
      },
      '17': {
        '2026-09-19': {'complaints': 99, 'accidents': 99},
      },
    },
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final role in ['driver', 'helper']) {
    test(
      '$role own KPI permission saves and restores without fleet access',
      () async {
        final request = RoleDocuments();
        final service = RoleAccessService(request: request);
        service.setCurrentUser(UserModel(id: '13', role: role));
        await service.initialize();
        final config = DispatcherAccessConfig.defaults(roleKey: role);
        expect(
          service.canAccess(DispatcherAccessCapability.ownKpiRead),
          isTrue,
        );
        await service.saveRoleAccess(
          config.copyWith(
            capabilities: {
              ...config.capabilities,
              DispatcherAccessCapability.ownKpiRead: false,
            },
          ),
        );
        final reopened = RoleAccessService(request: request);
        reopened.setCurrentUser(UserModel(id: '13', role: role));
        await reopened.initialize();
        expect(
          reopened.canAccess(DispatcherAccessCapability.ownKpiRead),
          isFalse,
        );
        await service.saveRoleAccess(config);
        await reopened.refresh();
        expect(
          reopened.canAccess(DispatcherAccessCapability.ownKpiRead),
          isTrue,
        );
        expect(
          reopened.canAccess(DispatcherAccessCapability.pmKpiRead),
          isFalse,
        );
        service.dispose();
        reopened.dispose();
        await request.updates.close();
      },
    );
  }
  test(
    'own permission defaults never grant driver/helper fleet access or admin shell',
    () {
      for (final role in ['driver', 'helper']) {
        final config = DispatcherAccessConfig.fromMap({
          'role': role,
          'capabilities': {'bookings.read': true},
        });
        expect(config.isEnabled(DispatcherAccessCapability.ownKpiRead), isTrue);
        expect(config.isEnabled(DispatcherAccessCapability.pmKpiRead), isFalse);
        expect(RoleAccessService.instance.usesAdminShell(role: role), isFalse);
        expect(
          config
              .copyWith(
                capabilities: {
                  ...config.capabilities,
                  DispatcherAccessCapability.ownKpiRead: false,
                },
              )
              .isEnabled(DispatcherAccessCapability.ownKpiRead),
          isFalse,
        );
      }
      expect(
        DispatcherAccessConfig.defaults(
          roleKey: 'client',
        ).isEnabled(DispatcherAccessCapability.ownKpiRead),
        isFalse,
      );
    },
  );
  for (final role in ['driver', 'helper']) {
    test(
      '$role own data survives fresh store offline then reconnect, no remote writes',
      () async {
        final db = FakeFirebaseFirestore();
        await seedCrew(db);
        var online = true;
        var allowed = true;
        final user = UserModel(id: role == 'driver' ? '13' : '18', role: role);
        UserModel? current = user;
        var pending = <Map<String, dynamic>>[];
        CrewKpiStore store() => CrewKpiStore(
          firestore: db,
          cache: FirestoreCacheStore(),
          currentUser: () async => current,
          allowed: (_) => allowed,
          online: () => online,
          pending: () async => pending,
        );
        final before = db.dump();
        final first = (await store().load(user))!;
        final rows = crewKpiTransactions(user, first);
        expect(rows.map((r) => r['label']), contains('Booking 1'));
        expect(rows.map((r) => r['label']), isNot(contains('Booking 2')));
        expect(rows.map((r) => r['label']), isNot(contains('Booking 3')));
        expect(
          rows.firstWhere((r) => r['type'] == 'Share')['amount'],
          role == 'driver' ? 100 : 50,
        );
        expect(rows.firstWhere((r) => r['type'] == 'Salary')['amount'], 455);
        expect(
          (first['incidents'] as List).single['complaints'],
          role == 'driver' ? 1 : 0,
        );
        expect(jsonEncode(first), isNot(contains('secret-photo')));
        expect(jsonEncode(first), isNot(contains('private-phone')));
        expect(db.dump(), before);
        online = false;
        expect(crewKpiTransactions(user, (await store().load(user))!), rows);
        pending = [
          crewBooking('3', status: 'delivered', time: '2026-09-20T03:00:00Z'),
        ];
        expect(
          crewKpiTransactions(
            user,
            (await store().load(user))!,
          ).where((r) => r['type'] == 'Share'),
          hasLength(2),
        );
        pending = [];
        online = true;
        await db.collection('bookings').doc('3').update({
          'client_status': 'delivered',
          'delivered_at': '2026-09-20T03:00:00Z',
        });
        final after = (await store().load(user))!;
        expect(
          crewKpiTransactions(user, after).where((r) => r['type'] == 'Share'),
          hasLength(2),
        );
        online = false;
        expect(
          crewKpiTransactions(user, (await store().load(user))!),
          crewKpiTransactions(user, after),
        );
        allowed = false;
        await expectLater(store().readCached(user), throwsStateError);
        allowed = true;
        current = const UserModel(id: '99', role: 'driver');
        await expectLater(store().readCached(user), throwsStateError);
      },
    );
  }
  test(
    'confirmed replacement pay is attributed by user, never entire PM salary',
    () async {
      final db = FakeFirebaseFirestore();
      await seedCrew(db);
      final second = crewBooking('2', driver: '17');
      await db.collection('bookings').doc('2').set(second);
      final rates = <Map<String, dynamic>>[];
      for (final raw in [crewBooking('1'), second]) {
        final trip = KpiTrip(
          Booking.fromMap({
            ...raw,
            'driver': {'id': raw['driver_id']},
            'helper': {'id': raw['helper_id']},
            'vehicle_make': {'id': '4'},
          }),
          DateTime.utc(2026, 9, 19),
        );
        rates.add({
          'signature': trip.signature,
          'booking_id': raw['id'],
          'driver_id': raw['driver_id'],
          'helper_id': raw['helper_id'],
          'driver': 100,
          'helper': 50,
          'route': 'San Jose',
        });
      }
      await db.collection('pm_kpi_records').doc('NA_2026-09-19').set({
        'kind': 'day',
        'day': '2026-09-19',
        'salary_confirmed': true,
        'trip_rates': rates,
        'daily_rate': 455,
        'driver_salary': 1110,
        'helper_salary': 555,
        'fuel': 9999,
      });
      for (final user in [
        const UserModel(id: '13', role: 'driver'),
        const UserModel(id: '18', role: 'helper'),
      ]) {
        final store = CrewKpiStore(
          firestore: db,
          currentUser: () async => user,
          allowed: (_) => true,
          online: () => true,
          pending: () async => [],
        );
        final data = (await store.load(user))!;
        final rows = crewKpiTransactions(user, data);
        expect(rows.every((r) => r['status'] == 'Confirmed'), isTrue);
        expect(rows.firstWhere((r) => r['type'] == 'Salary')['amount'], 455);
        expect(
          rows.where((r) => r['type'] == 'Share'),
          hasLength(user.role == 'driver' ? 1 : 2),
        );
        expect(jsonEncode(data['records']), isNot(contains('1110')));
        expect(jsonEncode(data['records']), isNot(contains('9999')));
      }
    },
  );
  test(
    'empty online result persists; new account cannot inherit old cache',
    () async {
      final db = FakeFirebaseFirestore();
      var online = true;
      var user = const UserModel(id: '13', role: 'driver');
      CrewKpiStore store() => CrewKpiStore(
        firestore: db,
        currentUser: () async => user,
        allowed: (_) => true,
        online: () => online,
        pending: () async => [],
      );
      expect(crewKpiTransactions(user, (await store().load(user))!), isEmpty);
      online = false;
      expect(await store().readCached(user), isNotNull);
      user = const UserModel(id: '17', role: 'driver');
      expect(await store().readCached(user), isNull);
    },
  );
  test(
    'duplicate submission counted once; replacement does not inherit old crew income',
    () async {
      const user = UserModel(id: '13', role: 'driver');
      final a = crewBooking('1');
      final data = <String, dynamic>{
        'bookings': [
          a,
          {...a, 'id': 'duplicate'},
          crewBooking('2', driver: '17'),
        ],
        'makes': [],
        'records': [],
        'catalog': {},
      };
      final rows = crewKpiTransactions(user, data);
      expect(rows, hasLength(2));
      expect(rows.where((r) => r['type'] == 'Salary'), hasLength(1));
    },
  );
}
