// Fault-injection doubles implement the Firestore query interface.
// ignore_for_file: subtype_of_sealed_class
import 'dart:convert';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/views/admin/admin_error_logs.dart';
import 'package:webapp/widgets/shared/admin_modal_record_list.dart';
import 'package:webapp/widgets/shared/app_page_loading.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';

/// Stalls only the newest-first read, the way a slow composite index behaves.
/// The cheap un-ordered read still answers, which is what the fallback uses.
class _StalledOrderedReadFirestore extends FakeFirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    final ref = super.collection(path);
    return path == 'sync_error_logs' ? _StalledOrderedCollection(ref) : ref;
  }
}

/// Stalls every read on the collection, so neither path can answer.
class _StalledReadFirestore extends FakeFirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    final ref = super.collection(path);
    return path == 'sync_error_logs' ? _StalledCollection(ref) : ref;
  }
}

class _StalledOrderedCollection
    implements CollectionReference<Map<String, dynamic>> {
  _StalledOrderedCollection(this.ref);
  final CollectionReference<Map<String, dynamic>> ref;
  @override
  Query<Map<String, dynamic>> orderBy(
    Object field, {
    bool descending = false,
  }) => _StalledQuery(ref);
  @override
  AggregateQuery count() => ref.count();
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) => ref.doc(path);
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #where) {
      return _StallsOnOrderQuery(
        ref.where(
          invocation.positionalArguments.first,
          isEqualTo: invocation.namedArguments[#isEqualTo],
        ),
      );
    }
    return super.noSuchMethod(invocation);
  }
}

/// Answers an un-ordered read normally, but stalls the moment an order is
/// requested - the way a slow composite index behaves.
class _StallsOnOrderQuery implements Query<Map<String, dynamic>> {
  _StallsOnOrderQuery(this.ref);
  final Query<Map<String, dynamic>> ref;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    // Chained filters must keep working; only ordering stalls.
    if (invocation.memberName == #where) {
      return _StallsOnOrderQuery(
        ref.where(
          invocation.positionalArguments.first,
          isEqualTo: invocation.namedArguments[#isEqualTo],
        ),
      );
    }
    return super.noSuchMethod(invocation);
  }

  @override
  Query<Map<String, dynamic>> orderBy(
    Object field, {
    bool descending = false,
  }) => _StalledQuery(ref);
  @override
  AggregateQuery count() => ref.count();
  @override
  Query<Map<String, dynamic>> limit(int count) => this;
  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) =>
      ref.get(options);
}

class _StalledCollection implements CollectionReference<Map<String, dynamic>> {
  _StalledCollection(this.ref);
  final CollectionReference<Map<String, dynamic>> ref;
  @override
  Query<Map<String, dynamic>> orderBy(
    Object field, {
    bool descending = false,
  }) => _StalledQuery(ref);
  @override
  AggregateQuery count() => ref.count();
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) => ref.doc(path);
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #where) {
      return _StalledQuery(
        ref.where(
          invocation.positionalArguments.first,
          isEqualTo: invocation.namedArguments[#isEqualTo],
        ),
      );
    }
    return super.noSuchMethod(invocation);
  }
}

class _StalledQuery implements Query<Map<String, dynamic>> {
  _StalledQuery(this.ref);
  final Query<Map<String, dynamic>> ref;
  @override
  Query<Map<String, dynamic>> orderBy(
    Object field, {
    bool descending = false,
  }) => this;
  @override
  AggregateQuery count() => ref.count();
  @override
  Query<Map<String, dynamic>> limit(int count) => this;
  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) =>
      Completer<QuerySnapshot<Map<String, dynamic>>>().future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailedCountFirestore extends FakeFirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    final ref = super.collection(path);
    return path == 'sync_error_logs' ? _FailedCountCollection(ref) : ref;
  }
}

class _FailedCountCollection extends _StalledOrderedCollection {
  _FailedCountCollection(super.ref);
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #where) {
      return _FailedCountQuery(
        ref.where(
          invocation.positionalArguments.first,
          isEqualTo: invocation.namedArguments[#isEqualTo],
        ),
      );
    }
    return super.noSuchMethod(invocation);
  }
}

class _FailedCountQuery extends _StallsOnOrderQuery {
  _FailedCountQuery(super.ref);
  @override
  AggregateQuery count() => throw StateError('Count query unavailable');
  @override
  Query<Map<String, dynamic>> orderBy(
    Object field, {
    bool descending = false,
  }) => ref.orderBy(field, descending: descending);
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #where) {
      return _FailedCountQuery(
        ref.where(
          invocation.positionalArguments.first,
          isEqualTo: invocation.namedArguments[#isEqualTo],
        ),
      );
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  testWidgets(
    'deletes KPI diagnostics across devices but retains queued failures',
    (tester) async {
      final db = FakeFirebaseFirestore();
      const warning =
          'Booking 124: No PM assigned; no PM has Driver 16 + Helper 19';
      for (final id in ['old', 'new', 'mixed', 'queue']) {
        await db.collection('sync_error_logs').doc(id).set({
          'attention_required': true,
          'user_id': '8',
          'device_id': id,
          'kind': id == 'queue' ? 'queue_failure' : 'kpi_diagnostic',
          'operation': 'Validate KPI data',
          'error': id == 'new'
              ? 'Booking 109: Truck not recorded. Select the truck used for this booking.'
              : '$warning${id == 'mixed' ? "\nBooking 78: No active trip rate" : ""}',
          'last_failed_at': '2026-10-02T00:00:00Z',
        });
      }
      await db.collection('bookings').doc('124').set({'status': 'delivered'});
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminErrorLogsView(
              user: const UserModel(role: 'admin'),
              firestore: db,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final remaining = await db.collection('sync_error_logs').get();
      expect(remaining.docs.map((doc) => doc.id), unorderedEquals(['queue']));
      expect(find.text('1 Error'), findsOneWidget);
      expect((await db.collection('bookings').doc('124').get()).data(), {
        'status': 'delivered',
      });
    },
  );

  for (final count in [1, 17]) {
    testWidgets('complete read provides exact counts, reports=$count', (
      tester,
    ) async {
      final db = _FailedCountFirestore();
      for (var i = 0; i < count; i++) {
        await db.collection('sync_error_logs').doc('$i').set({
          'attention_required': true,
          'user_id': '8',
          'device_id': 'device-A',
          'user_name': 'Test User',
          'role': 'dispatcher',
          'error': 'Upload failed',
          'operation': 'Action $i',
          'last_failed_at': DateTime.utc(2026, 10, 2, 0, i).toIso8601String(),
        });
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminErrorLogsView(
              user: const UserModel(role: 'admin'),
              firestore: db,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final label = count == 1 ? '1 Error' : '17 Errors';
      expect(find.text(label), findsOneWidget);
      expect(find.text('— Errors'), findsNothing);
      await tester.tap(find.byTooltip('Expand errors'));
      await tester.pumpAndSettle();
      expect(find.text(label), findsNWidgets(2));
      await tester.tap(find.byTooltip('Expand device errors'));
      await tester.pumpAndSettle();
      final records = tester.widget<AdminModalRecordList>(
        find.byType(AdminModalRecordList),
      );
      expect(records.itemCount, count + 2);
      expect(
        records.valuesAt(2)[1],
        'Action ${count - 1} • Version unavailable',
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final removed in [false, true]) {
    testWidgets('copy missing-device reports; removed after display=$removed', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      await db.collection('sync_error_logs').doc('timeout').set({
        'attention_required': true,
        'user_id': '8',
        'role': 'dispatcher',
        'last_failed_at': '2026-09-24T00:00:00Z',
        'error': 'TimeoutException after 0:00:10.000000: Future not completed',
        'details': {'operation': 'bookingPhotoUpload', 'target': 'bookings/83'},
      });
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'];
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminErrorLogsView(
              user: const UserModel(role: 'admin'),
              firestore: db,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Expand errors'));
      await tester.pumpAndSettle();
      if (removed) {
        await db.collection('sync_error_logs').doc('timeout').delete();
      }
      await tester.tap(find.byTooltip('Copy all device errors'));
      await tester.pumpAndSettle();
      expect(copied, isNot('[]'));
      expect(copied, contains('TimeoutException'));
      expect(copied, contains('bookingPhotoUpload'));
      final data = jsonDecode(copied!);
      if (removed) {
        expect(data['server_reports_verified'], false);
        expect(data['displayed_reports'], hasLength(1));
      } else {
        expect(data, hasLength(1));
        expect(
          data.first['firestore_data']['details']['target'],
          'bookings/83',
        );
      }
    });
  }
  testWidgets('device copy fetches all 117 server documents and every field', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    for (var i = 0; i < 117; i++) {
      await db.collection('sync_error_logs').doc('error$i').set({
        'attention_required': true,
        'user_id': '8',
        'device_id': 'A',
        'user_name': 'Alexis',
        'role': 'dispatcher',
        'last_failed_at': '2026-09-23T01:00:00Z',
        'error': 'Failure $i',
        'id': 'stored-id-$i',
        'extra_field': {
          'list': [1, 2, 'three'],
        },
        'received_at': Timestamp(100, 123456789),
      });
    }
    await db.collection('sync_error_logs').doc('other-device').set({
      'attention_required': true,
      'user_id': '8',
      'device_id': 'B',
      'last_failed_at': '2026-09-01T01:00:00Z',
    });
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminErrorLogsView(
            user: const UserModel(role: 'admin'),
            firestore: db,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Expand errors'));
    await tester.pumpAndSettle();
    expect(find.text('A'), findsOneWidget);
    await db.collection('sync_error_logs').doc('error0').update({
      'added_after_open': true,
    });
    await tester.tap(find.byTooltip('Copy all device errors').first);
    await tester.pumpAndSettle();
    final records = jsonDecode(copied!) as List;
    expect(records, hasLength(117));
    expect(
      records.every((r) => r['firestore_data']['device_id'] == 'A'),
      isTrue,
    );
    final first = records.firstWhere((r) => r['document_id'] == 'error0');
    expect(first['document_path'], 'sync_error_logs/error0');
    expect(first['firestore_data']['id'], 'stored-id-0');
    expect(first['firestore_data']['extra_field']['list'], [1, 2, 'three']);
    expect(first['firestore_data']['received_at']['nanoseconds'], 123456789);
    expect(first['firestore_data']['added_after_open'], true);
  });
  for (final hasLogs in [false, true]) {
    testWidgets('a stalled ordered read still shows the reports, '
        'hasLogs=$hasLogs', (tester) async {
      // The newest-first read stalls, but the reports exist and the cheaper
      // read answers. The page must show them rather than an error - the old
      // fallback only checked emptiness, so it failed precisely when there was
      // something to show.
      final db = _StalledOrderedReadFirestore();
      if (hasLogs) {
        await db.collection('sync_error_logs').doc('existing').set({
          'attention_required': true,
          'user_id': '8',
          'role': 'dispatcher',
          'last_failed_at': '2026-09-24T00:00:00Z',
          'error': 'saved',
        });
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminErrorLogsView(
              user: const UserModel(role: 'admin'),
              firestore: db,
            ),
          ),
        ),
      );
      expect(find.byType(AppPageLoading), findsOneWidget);
      await tester.pump(const Duration(seconds: 13));
      await tester.pumpAndSettle();

      expect(
        find.text('Retry'),
        findsNothing,
        reason: 'a slow read must not become an error the admin has to retry',
      );
      if (hasLogs) {
        expect(
          find.textContaining('quick unsorted read'),
          findsNothing,
          reason: 'all reports are sorted locally without a fallback notice',
        );
        expect(
          find.textContaining('No error logs'),
          findsNothing,
          reason: 'a report exists and must not be shown as an empty list',
        );
        expect(find.byType(AdminModalRecordList), findsOneWidget);
      } else {
        expect(find.textContaining('No error logs'), findsOneWidget);
      }
    });
  }

  testWidgets('when no read can answer, the failure is diagnosable', (
    tester,
  ) async {
    // Both the ordered read and the cheap read stall. The page has nothing to
    // show, so it must say so - and name the actual failure so the next report
    // is not a dead end.
    final db = _StalledReadFirestore();
    await db.collection('sync_error_logs').doc('existing').set({
      'attention_required': true,
      'error': 'saved',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminErrorLogsView(
            user: const UserModel(role: 'admin'),
            firestore: db,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 22));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
    expect(
      find.textContaining('TimeoutException'),
      findsOneWidget,
      reason: 'the real failure must reach the admin, not a generic message',
    );
  });

  testWidgets('initial loading resolves to the shared empty card', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminErrorLogsView(
            user: const UserModel(role: 'admin'),
            firestore: FakeFirebaseFirestore(),
          ),
        ),
      ),
    );
    expect(find.byType(AppPageLoading), findsOneWidget);
    expect(find.text('No error logs.'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byType(AppPageLoading), findsNothing);
    expect(find.text('No error logs.'), findsOneWidget);
    expect(find.byType(AdminListItemCard), findsOneWidget);
    expect(find.byTooltip('Refresh'), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });
  for (final width in [390.0, 1400.0]) {
    testWidgets('groups and copies full diagnostics at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('13').set({
        'name': 'Jonami',
        'role': 'driver',
      });
      for (var i = 0; i < 2; i++) {
        await db.collection('sync_error_logs').doc('error$i').set({
          'attention_required': true,
          'user_id': '13',
          'device_id': 'device-A',
          'operation': 'Save booking $i',
          'error': 'Precise failure $i',
          'stack_trace': 'source.dart:123',
          'first_failed_at': '2026-09-20T01:00:0${i}Z',
          'last_failed_at': '2026-09-23T01:00:0${i}Z',
          'details': {'queue_entry_id': 'offline_$i'},
        });
      }
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminErrorLogsView(
              user: const UserModel(id: '1', role: 'admin'),
              firestore: db,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Jonami'), findsOneWidget);
      void expectRightmost(String tooltip) {
        final button = find.byTooltip(tooltip);
        final card = find
            .ancestor(
              of: button,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is CustomPaint &&
                    widget.key is ValueKey<String> &&
                    (widget.key! as ValueKey<String>).value.startsWith(
                      'admin-record-group-row-',
                    ),
              ),
            )
            .first;
        expect(
          tester.getTopRight(button).dx,
          closeTo(tester.getTopRight(card).dx - 17, 0.01),
        );
      }

      expectRightmost('Expand errors');
      expect(find.text('Save booking 1 • Version unavailable'), findsNothing);
      await tester.tap(find.byTooltip('Copy all user errors'));
      await tester.pumpAndSettle();
      final copied = jsonDecode(clipboard!) as List;
      expect(copied.length, 2);
      expect(copied.first['document_id'], 'error0');
      expect(copied.first['firestore_data']['stack_trace'], 'source.dart:123');
      expect(
        copied.first['firestore_data']['details']['queue_entry_id'],
        'offline_0',
      );
      await tester.tap(find.byTooltip('Expand errors'));
      await tester.pumpAndSettle();
      expect(find.text('Save booking 1 • Version unavailable'), findsNothing);
      expectRightmost('Collapse errors');
      expectRightmost('Expand device errors');
      await tester.ensureVisible(find.byTooltip('Expand device errors'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Expand device errors'));
      await tester.pumpAndSettle();
      expect(find.text('Save booking 1 • Version unavailable'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (width > 900) {
        await tester.tap(find.byTooltip('View error details').first);
        await tester.pumpAndSettle();
        expect(find.text('Error Details'), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, 'Copy'));
        await tester.pumpAndSettle();
        expect(jsonDecode(clipboard!)['document_id'], 'error1');
        expect(
          jsonDecode(clipboard!)['firestore_data']['stack_trace'],
          'source.dart:123',
        );
        await tester.tapAt(const Offset(2, 2));
        await tester.pumpAndSettle();
        expect(find.text('Error Details'), findsNothing);
        expect(tester.takeException(), isNull);
      }
      await tester.ensureVisible(find.byTooltip('Collapse errors'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Collapse errors'));
      await tester.pumpAndSettle();
      expect(find.text('Save booking 1 • Version unavailable'), findsNothing);
      expect((await db.collection('sync_error_logs').get()).docs.length, 2);
    });
  }

  testWidgets('same user has independent device groups and device-only copy', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = FakeFirebaseFirestore();
    for (final device in ['A', 'B']) {
      await db.collection('sync_error_logs').doc(device).set({
        'attention_required': true,
        'user_id': '8',
        'user_name': 'Alexis',
        'role': 'dispatcher',
        'device_id': device,
        'operation': 'Action $device',
        'error': 'Same error',
        'first_failed_at': '2026-09-22T01:00:00Z',
        'last_failed_at': '2026-09-23T01:00:00Z',
      });
    }
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminErrorLogsView(
            user: const UserModel(role: 'admin'),
            firestore: db,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Expand errors'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Expand device errors'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Copy all device errors').first);
    await tester.pumpAndSettle();
    final records = jsonDecode(copied!) as List;
    expect(records, hasLength(1));
    final device = records.single['firestore_data']['device_id'];
    await tester.tap(find.byTooltip('Expand device errors').first);
    await tester.pumpAndSettle();
    expect(find.text('Action $device • Version unavailable'), findsOneWidget);
    final userLeft = tester.getTopLeft(find.text('8')).dx;
    expect(tester.getTopLeft(find.text('$device')).dx, userLeft);
    expect(
      tester.getTopLeft(find.text('Action $device • Version unavailable')).dx,
      userLeft,
    );
    expect(
      tester.getTopLeft(find.text('1 Error').first).dx,
      tester.getTopLeft(find.text('2 Errors')).dx,
    );
    expect(
      find.text('Action ${device == 'A' ? 'B' : 'A'} • Version unavailable'),
      findsNothing,
    );
    expect(find.byTooltip('Collapse device errors'), findsOneWidget);
    await tester.tap(find.byTooltip('Collapse device errors'));
    await tester.pumpAndSettle();
    expect(find.text('Action $device • Version unavailable'), findsNothing);
    expect(find.byTooltip('Expand device errors'), findsNWidgets(2));
    expect(find.byTooltip('Collapse errors'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('non-admin cannot read diagnostic page', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminErrorLogsView(
            user: const UserModel(role: 'driver'),
            firestore: FakeFirebaseFirestore(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Admin access required'), findsOneWidget);
    expect(find.byTooltip('Refresh'), findsNothing);
  });

  testWidgets(
    'loads all active reports with exact totals and refreshes deletions',
    (tester) async {
      final db = FakeFirebaseFirestore();
      final refresh = ValueNotifier<int>(0);
      addTearDown(refresh.dispose);
      for (final kind in ['legacy', 'stalled']) {
        await db.collection('sync_error_logs').doc(kind).set({
          'user_id': '13',
          'device_id': 'device-A',
          'error': kind,
          'last_failed_at': '2026-09-24T00:00:00Z',
          if (kind == 'stalled') 'attention_required': false,
        });
      }
      for (var i = 0; i < 17; i++) {
        await db.collection('sync_error_logs').doc('error$i').set({
          'attention_required': true,
          'user_id': '13',
          'device_id': 'device-A',
          'user_name': 'Stored Name',
          'role': 'driver',
          'error': 'Error $i',
          'first_failed_at': DateTime.utc(
            2026,
            9,
            i == 0 ? 1 : 2,
            0,
            i,
          ).toIso8601String(),
          'last_failed_at': DateTime.utc(2026, 9, 23, 0, i).toIso8601String(),
        });
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminErrorLogsView(
              user: const UserModel(role: 'admin'),
              firestore: db,
              refreshSignal: refresh,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      int loadedDeviceCount() {
        final list = tester.widget<AdminModalRecordList>(
          find.byType(AdminModalRecordList),
        );
        return list.itemCount;
      }

      expect(find.textContaining('loaded reports'), findsNothing);
      expect(find.text('Pull up to load more'), findsNothing);
      expect(find.text('17 Errors'), findsOneWidget);
      await tester.tap(find.byTooltip('Expand errors'));
      await tester.pumpAndSettle();
      expect(find.text('device-A'), findsOneWidget);
      await tester.tap(find.byTooltip('Collapse errors'));
      await tester.pumpAndSettle();
      expect(find.text('Created'), findsNothing);
      expect(find.text('Updated'), findsNothing);
      await tester.dragFrom(
        tester.getBottomRight(find.byType(Scrollable).first) -
            const Offset(12, 12),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      scroll.position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.textContaining('loaded reports'), findsNothing);
      expect(find.text('Stored Name'), findsOneWidget);
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text('All reports loaded'), findsNothing);
      scroll.position.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Expand errors'));
      await tester.pumpAndSettle();
      expect(find.text('device-A'), findsOneWidget);
      await tester.tap(find.byTooltip('Expand device errors'));
      await tester.pumpAndSettle();
      expect(loadedDeviceCount(), 19);
      for (var i = 0; i < 17; i++) {
        await db.collection('sync_error_logs').doc('error$i').delete();
      }
      refresh.value++;
      await tester.pumpAndSettle();
      expect(find.text('No error logs.'), findsOneWidget);
    },
  );
}
