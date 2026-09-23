// Emulator-only release validation. Never uses a production project.
// ignore_for_file: depend_on_referenced_packages, deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:js_interop';
import 'dart:html' as html;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_web/firebase_core_web.dart';
import 'package:cloud_firestore_web/cloud_firestore_web.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:matcher/matcher.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/status_form.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/repositories/local/booking_storage_backend.dart';
import 'package:webapp/requests/booking.request.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/requests/firestore_cache_store.dart';
import 'package:webapp/services/booking_id_resolver.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/view_models/shared/booking_workflow.vm.dart';

@JS('ptcNetwork')
external JSPromise<JSAny?> _network(JSBoolean online);

// Real SDK/server operations; only unrelated global startup listeners are omitted.
class _Request extends BookingRequest {
  _Request(FirebaseFirestore db, OfflineMutationQueueService queue)
    : super(firestore: db, offlineMutationQueueService: queue);
  @override
  Future<void> initialize() async {}
}

final _messages = <String>[];
final disposers = <VoidCallback>[];
void log(String message) {
  _messages.add(message);
  debugPrint(message);
}

void expect(Object? actual, Object? expected, {String? reason}) {
  final matcher = expected is Matcher ? expected : equals(expected);
  if (!matcher.matches(actual, {})) {
    throw StateError(
      '${reason ?? "Expectation failed"}: $actual; expected ${matcher.describe(StringDescription())}',
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Text('Local emulator regression running')),
    ),
  );
  final report = <String, dynamic>{'passed': <String>[]};
  try {
    late FirebaseFirestore db;
    late BookingStorageBackend disk;
    var sequence = 0;
    late String account;
    final scenarios = <(String, Future<void> Function())>[];
    void scenario(String name, Future<void> Function() body) =>
        scenarios.add((name, body));
    Future<void> start() async {
      FirebaseCoreWeb.registerWith(webPluginRegistrar);
      FirebaseFirestoreWeb.registerWith(webPluginRegistrar);
      SharedPreferencesPlugin.registerWith(webPluginRegistrar);
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'emulator-only-api-key',
          appId: '1:123456789:web:emulator',
          messagingSenderId: '123456789',
          projectId: 'demo-paltranco-regression',
        ),
      );
      db = FirebaseFirestore.instance;
      db.settings = const Settings(persistenceEnabled: false);
      db.useFirestoreEmulator('127.0.0.1', 18081);
      expect(db.app.options.projectId, startsWith('demo-'));
      disk = createBookingStorageBackend();
      await disk.initialize();
    }

    Future<void> setOnline(bool online) async {
      await _network(online.toJS).toDart;
    }

    OfflineMutationQueueService makeQueue(bool Function() online) {
      final scope = account;
      // A reopened app no longer has the previous app's active retry timers.
      return OfflineMutationQueueService(
        firestore: db,
        backend: disk,
        isOnline: () => scope == account && online(),
      );
    }

    Future<void> reset() async {
      await setOnline(true);
      account =
          'emulator_${DateTime.now().microsecondsSinceEpoch}_${sequence++}';
      final auth = createAuthStorageBackend();
      await auth.initialize();
      await auth.writeString('paltranco_current_user_id', account);
      await auth.remove('paltranco_known_session_user_ids');
      await FirestoreCacheStore.instance.writeDocumentMaps('vehicle_makes', []);
    }

    Future<void> cleanup() async {
      await setOnline(true);
      await disk.writeStringList('offline_mutation_queue_v1::$account', []);
    }

    for (final role in ['driver', 'helper']) {
      for (final stage in ['finish', 'complete', 'delivered']) {
        scenario(
          '$role offline $stage -> reopen -> reconnect -> replay once',
          () async {
            var online = false;
            final queue = makeQueue(() => online);
            final request = _Request(db, queue);
            final id = '${800 + sequence}';
            final chassisId = '${900 + sequence}';
            final original = Booking(
              id: id,
              chassisId: chassisId,
              driver: const UserModel(id: '7'),
              helper: const UserModel(id: '8'),
              clientStatus: 'ongoing',
              driverStatus: 'ongoing',
              helperStatus: 'ongoing',
              createdAt: DateTime.utc(2026, 9, 1),
              updatedAt: DateTime.utc(2026, 9, 2),
              statusOutputs: {
                'book': {
                  'fields': {'destination': 'Roxas'},
                },
              },
            );
            log('Phase: seed booking');
            await db.collection('bookings').doc(id).set(original.toMap());
            await db.collection('chassis').doc(chassisId).set({
              'id': int.parse(chassisId),
              'current_status': 'loaded',
              'current_booking_id': int.parse(id),
              'current_driver_id': 7,
            });
            await FirestoreCacheStore.instance.writeDocumentMaps('bookings', [
              original.toMap(),
            ]);
            log('Phase: disable network');
            await setOnline(false);
            final vm = BookingWorkflowViewModel(bookingRepository: request);
            disposers.add(vm.dispose);
            vm.user = UserModel(id: role == 'driver' ? '7' : '8', role: role);
            vm.booking = original;
            log('Phase: submit');
            final saved = await vm
                .submitSpecificForm(
                  StatusForm(
                    id: 'delivery',
                    role: role,
                    currentStatusKey: 'ongoing',
                    nextStatusKey: stage,
                  ),
                  {'notes': 'emulator offline action'},
                )
                .timeout(const Duration(seconds: 5));
            expect(saved, isNotNull);
            expect(vm.isSubmitting, isFalse);
            expect(saved!.localSyncStatus, 'queued');
            expect(await queue.readPendingItems(account), hasLength(1));
            log('Phase: enable network');
            await setOnline(true);
            // Offline action has not silently reached the server yet.
            expect(
              (await db
                      .collection('bookings')
                      .doc(id)
                      .get(const GetOptions(source: Source.server)))
                  .data()!['client_status'],
              'ongoing',
            );
            log('Phase: server read completed');
            online = true;
            final reopened = makeQueue(() => true);
            log('Phase: queue initialize');
            await reopened.initialize();
            log('Phase: queue flush');
            await reopened.flushPendingMutations();
            expect(await reopened.readPendingItems(account), isEmpty);
            final remote =
                (await db
                        .collection('bookings')
                        .doc(id)
                        .get(const GetOptions(source: Source.server)))
                    .data()!;
            expect(remote['client_status'], stage);
            expect(remote['driver_status'], stage);
            expect(remote['helper_status'], stage);
            expect(
              DateTime.parse(remote['updated_at']).toUtc(),
              saved.updatedAt!.toUtc(),
            );
            expect(
              DateTime.parse(remote['created_at']).toUtc(),
              original.createdAt!.toUtc(),
            );
            final chassis =
                (await db
                        .collection('chassis')
                        .doc(chassisId)
                        .get(const GetOptions(source: Source.server)))
                    .data()!;
            expect(chassis['current_booking_id'].toString(), id);
            if (stage == 'delivered') {
              expect(chassis['current_driver_id'], isNull);
              expect(chassis['location'], 'Roxas');
              expect(chassis['current_status'], 'loaded');
              expect(
                DateTime.parse(remote['delivered_at']).toUtc(),
                saved.deliveredAt!.toUtc(),
              );
            }
            await reopened.flushPendingMutations();
            expect(
              (await db
                      .collection('bookings')
                      .doc(id)
                      .get(const GetOptions(source: Source.server)))
                  .data(),
              remote,
            );
          },
        );
      }
    }

    scenario(
      'real concurrent reservations skip occupied IDs and remain idempotent',
      () async {
        final queue = makeQueue(() => true);
        final counter = db
            .collection('manage_count')
            .doc('resource_counters')
            .collection('items')
            .doc('bookings');
        await counter.set({'next_id': 4000});
        const occupied = {'id': '4000', 'notes': 'must not overwrite'};
        await db.collection('bookings').doc('4000').set(occupied);
        final a = '$account-a', b = '$account-b';
        final ids = await Future.wait([
          queue.reserveNumericDocumentId(
            collectionKey: 'bookings',
            submissionKey: a,
          ),
          queue.reserveNumericDocumentId(
            collectionKey: 'bookings',
            submissionKey: b,
          ),
        ]);
        expect(ids.toSet(), {'4001', '4002'});
        expect(
          await queue.reserveNumericDocumentId(
            collectionKey: 'bookings',
            submissionKey: a,
          ),
          ids.first,
        );
        expect(
          (await db.collection('bookings').doc('4000').get()).data(),
          occupied,
        );
      },
    );

    scenario(
      'admin login, impersonate driver/helper, restore admin, then logout',
      () async {
        final queue = makeQueue(() => true);
        final auth = AuthRequest(
          firestore: db,
          offlineMutationQueueService: queue,
          vehicleRequest: VehicleRequest(
            firestore: db,
            offlineMutationQueueService: queue,
            offlineQueueInitializer: () async {},
          ),
          offlineQueueInitializer: () async {},
          offlineQueueFlusher: () async {},
        );
        for (final item in {
          '6100': 'admin',
          '6101': 'driver',
          '6102': 'helper',
        }.entries) {
          await db.collection('users').doc(item.key).set({
            'id': item.key,
            'role': item.value,
            'name': 'Emulator ${item.value}',
            'email': '${item.key}@example.test',
            'password': 'emulator-test-only',
            'is_active': true,
            'created_at': '2026-09-01T00:00:00.000Z',
            'updated_at': '2026-09-01T00:00:00.000Z',
          });
        }
        await FirestoreCacheStore.instance.writeDocumentMaps('users', []);
        final user = await auth.login(
          identifier: '6100@example.test',
          password: 'emulator-test-only',
        );
        expect(user.id, '6100');
        expect((await auth.getCurrentUser())?.id, '6100');
        await auth.loginAsUser('6101');
        expect((await auth.getCurrentUser())?.id, '6101');
        expect(await auth.hasQuickLoginSource(), isTrue);
        await auth.loginAsUser('6102');
        expect((await auth.getCurrentUser())?.id, '6102');
        expect((await auth.returnToQuickLoginSource())?.id, '6100');
        expect((await auth.getCurrentUser())?.id, '6100');
        expect(await auth.hasQuickLoginSource(), isFalse);
        await auth.logout();
        expect(await auth.getCurrentUser(), isNull);
      },
    );

    scenario(
      'remote edit conflict preserves server value and pending local action',
      () async {
        const old = '2026-09-20T01:00:00.000Z';
        const action = '2026-09-20T02:00:00.000Z';
        const remote = {
          'id': 'conflict',
          'updated_at': '2026-09-20T03:00:00.000Z',
          'notes': 'remote edit',
        };
        await db.collection('operations_catalog').doc('conflict').set(remote);
        final queue = makeQueue(() => false);
        await setOnline(false);
        await queue.queueCollectionDocumentUpsert(
          collectionKey: 'operations_catalog',
          documentId: 'conflict',
          document: {
            'id': 'conflict',
            'updated_at': action,
            'notes': 'offline edit',
          },
          baseUpdatedAt: old,
        );
        await setOnline(true);
        final reopened = makeQueue(() => true);
        await reopened.initialize();
        await reopened.flushPendingMutations();
        expect(
          (await db
                  .collection('operations_catalog')
                  .doc('conflict')
                  .get(const GetOptions(source: Source.server)))
              .data(),
          remote,
        );
        expect(await reopened.readPendingItems(account), hasLength(1));
      },
    );

    for (final role in ['admin', 'client']) {
      scenario(
        '$role queued create keeps action time and resolves unused numeric ID',
        () async {
          final queue = makeQueue(() => false);
          final key = 'booking_$account';
          final temp = BookingIdResolver.temporaryId(key);
          const at = '2026-09-20T01:02:03.000Z';
          await setOnline(false);
          await queue.queueOfflineBookingCreate(
            provisionalId: temp,
            submissionKey: key,
            document: {
              'id': temp,
              'submission_key': key,
              'created_at': at,
              'updated_at': at,
              'client_status': 'pending',
              'notes': '$role offline test',
            },
          );
          expect(await queue.readPendingItems(account), hasLength(1));
          await setOnline(true);
          final reopened = makeQueue(() => true);
          await reopened.initialize();
          await reopened.flushPendingMutations();
          expect(await reopened.readPendingItems(account), isEmpty);
          final resolved = await BookingIdResolver(
            firestore: db,
          ).resolve(temp, submissionKey: key);
          expect(int.tryParse(resolved ?? ''), isNotNull);
          final remote =
              (await db
                      .collection('bookings')
                      .doc(resolved)
                      .get(const GetOptions(source: Source.server)))
                  .data()!;
          expect(remote['created_at'], at);
          expect(remote['updated_at'], at);
          expect(remote['notes'], '$role offline test');
          await reopened.flushPendingMutations();
          expect(
            await BookingIdResolver(
              firestore: db,
            ).resolve(temp, submissionKey: key),
            resolved,
          );
        },
      );
    }

    await start();
    for (final entry in scenarios) {
      log('SCENARIO ${entry.$1}');
      await reset();
      try {
        await entry.$2().timeout(const Duration(seconds: 45));
        (report['passed'] as List<String>).add(entry.$1);
        log('PASSED ${entry.$1}');
      } finally {
        await cleanup();
      }
    }
    report['success'] = true;
  } catch (error, stack) {
    report['success'] = false;
    report['error'] = '$error';
    report['stack'] = '$stack';
  } finally {
    for (final dispose in disposers) {
      dispose();
    }
    report['messages'] = _messages;
    html.document.body!.setAttribute(
      'data-emulator-report',
      jsonEncode(report),
    );
    runApp(
      MaterialApp(home: Scaffold(body: SelectableText(jsonEncode(report)))),
    );
  }
}
