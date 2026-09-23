import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/views/admin/admin_error_logs.dart';

void main() {
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
      expect(find.text('Save booking 1'), findsNothing);
      await tester.tap(find.byTooltip('Copy loaded user errors'));
      await tester.pumpAndSettle();
      final copied = jsonDecode(clipboard!) as List;
      expect(copied.length, 2);
      expect(copied.first['id'], 'error1');
      expect(copied.first['stack_trace'], 'source.dart:123');
      expect(copied.first['details']['queue_entry_id'], 'offline_1');
      await tester.tap(find.byTooltip('Expand errors'));
      await tester.pumpAndSettle();
      expect(find.text('Save booking 1'), findsNothing);
      await tester.ensureVisible(find.byTooltip('Expand device errors'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Expand device errors'));
      await tester.pumpAndSettle();
      expect(find.text('Save booking 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (width > 900) {
        await tester.tap(find.byTooltip('View error details').first);
        await tester.pumpAndSettle();
        expect(find.text('Error Details'), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, 'Copy'));
        await tester.pumpAndSettle();
        expect(jsonDecode(clipboard!)['id'], 'error1');
        expect(jsonDecode(clipboard!)['stack_trace'], 'source.dart:123');
        await tester.tapAt(const Offset(2, 2));
        await tester.pumpAndSettle();
        expect(find.text('Error Details'), findsNothing);
        expect(tester.takeException(), isNull);
      }
      await tester.ensureVisible(find.byTooltip('Collapse errors'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Collapse errors'));
      await tester.pumpAndSettle();
      expect(find.text('Save booking 1'), findsNothing);
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
    await tester.tap(find.byTooltip('Copy loaded device errors').first);
    await tester.pumpAndSettle();
    final records = jsonDecode(copied!) as List;
    expect(records, hasLength(1));
    final device = records.single['device_id'];
    await tester.tap(find.byTooltip('Expand device errors').first);
    await tester.pumpAndSettle();
    expect(find.text('Action $device'), findsOneWidget);
    expect(find.text('Action ${device == 'A' ? 'B' : 'A'}'), findsNothing);
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

  testWidgets('loads only 15 reports then pulls up for next page', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    for (var i = 0; i < 17; i++) {
      await db.collection('sync_error_logs').doc('error$i').set({
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
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('15 loaded reports'), findsWidgets);
    expect(find.text('17'), findsOneWidget);
    expect(find.textContaining('Sep 1, 2026'), findsOneWidget);
    expect(find.textContaining('Sep 23, 2026'), findsOneWidget);
    await tester.dragFrom(
      tester.getBottomRight(find.byType(Scrollable).first) -
          const Offset(12, 12),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scroll.position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('17 loaded reports'), findsWidgets);
    expect(find.text('Stored Name'), findsOneWidget);
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('All reports loaded'), findsOneWidget);
  });
}
