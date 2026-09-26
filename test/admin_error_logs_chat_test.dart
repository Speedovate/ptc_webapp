import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/views/admin/admin_error_logs.dart';
import 'package:webapp/widgets/shared/support_section_navigation_scope.dart';

/// An admin reading an error often needs to ask the person about it. The chat
/// action sits right after copy on every row that names a user, and it opens
/// that user's support thread rather than a blank conversation.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<FakeFirebaseFirestore> seed({
    String? userId = '8',
    String userName = 'Alexis',
  }) async {
    final db = FakeFirebaseFirestore();
    await db.collection('sync_error_logs').doc('e1').set({
      'attention_required': true,
      'user_id': userId,
      'user_name': userName,
      'role': 'dispatcher',
      'device_id': 'A',
      'operation': 'Flush queue',
      'error': 'Boom',
      'first_failed_at': '2026-09-22T01:00:00Z',
      'last_failed_at': '2026-09-23T01:00:00Z',
    });
    return db;
  }

  Future<void> pumpLogs(
    WidgetTester tester,
    FakeFirebaseFirestore db, {
    UserModel? viewer,
    void Function({String? initialUserId})? onOpenSupport,
  }) async {
    tester.view.physicalSize = const Size(1800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Widget app = AdminErrorLogsView(
      user: viewer ?? const UserModel(role: 'admin'),
      firestore: db,
    );
    if (onOpenSupport != null) {
      app = SupportSectionNavigationScope(
        onOpenSupport:
            ({
              String? initialTopicKey,
              String? initialBookingId,
              String? initialUserId,
            }) => onOpenSupport(initialUserId: initialUserId),
        child: app,
      );
    }
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: app)));
    await tester.pumpAndSettle();
  }

  testWidgets('a row naming a user offers a chat action beside copy', (
    tester,
  ) async {
    await pumpLogs(tester, await seed());

    expect(find.byTooltip('Chat with Alexis'), findsOneWidget);

    // It sits after the copy action, in the same action cluster.
    final copy = tester.getTopLeft(find.byTooltip('Copy all user errors'));
    final chat = tester.getTopLeft(find.byTooltip('Chat with Alexis'));
    expect(chat.dx, greaterThan(copy.dx));
    expect((chat.dy - copy.dy).abs(), lessThan(4));

    expect(tester.takeException(), isNull);
  });

  testWidgets('the chat action opens the support thread of that user', (
    tester,
  ) async {
    String? openedFor;
    await pumpLogs(
      tester,
      await seed(),
      onOpenSupport: ({initialUserId}) => openedFor = initialUserId,
    );

    await tester.tap(find.byTooltip('Chat with Alexis'));
    await tester.pumpAndSettle();

    expect(openedFor, '8');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a signed out row has nobody to chat with', (tester) async {
    await pumpLogs(tester, await seed(userId: null, userName: 'Signed out'));

    expect(find.text('Signed out'), findsOneWidget);
    expect(find.byTooltip('Chat with Signed out'), findsNothing);
    // The copy action is still there, so diagnostics never regress.
    expect(find.byTooltip('Copy all user errors'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('each user row chats with its own user, not the first one', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    for (final entry in {'8': 'Alexis', '12': 'Ben'}.entries) {
      await db.collection('sync_error_logs').doc('e${entry.key}').set({
        'attention_required': true,
        'user_id': entry.key,
        'user_name': entry.value,
        'role': 'dispatcher',
        'device_id': 'A',
        'operation': 'Flush queue',
        'error': 'Boom',
        'first_failed_at': '2026-09-22T01:00:00Z',
        'last_failed_at': '2026-09-23T01:00:00Z',
      });
    }
    final opened = <String?>[];
    await pumpLogs(
      tester,
      db,
      onOpenSupport: ({initialUserId}) => opened.add(initialUserId),
    );

    await tester.tap(find.byTooltip('Chat with Ben'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Chat with Alexis'));
    await tester.pumpAndSettle();

    expect(opened, ['12', '8']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a device row still chats with its user, not the device', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    for (final device in ['A', 'B']) {
      await db.collection('sync_error_logs').doc(device).set({
        'attention_required': true,
        'user_id': '8',
        'user_name': 'Alexis',
        'role': 'dispatcher',
        'device_id': device,
        'operation': 'Flush queue',
        'error': 'Boom',
        'first_failed_at': '2026-09-22T01:00:00Z',
        'last_failed_at': '2026-09-23T01:00:00Z',
      });
    }
    final opened = <String?>[];
    await pumpLogs(
      tester,
      db,
      onOpenSupport: ({initialUserId}) => opened.add(initialUserId),
    );

    await tester.tap(find.byTooltip('Expand errors'));
    await tester.pumpAndSettle();

    // One chat action per row: the user group plus each device row.
    expect(find.byTooltip('Chat with Alexis'), findsNWidgets(3));
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byTooltip('Chat with Alexis').at(i));
      await tester.pumpAndSettle();
    }

    // Never a device id, and never empty.
    expect(opened, ['8', '8', '8']);
    expect(tester.takeException(), isNull);
  });
}
