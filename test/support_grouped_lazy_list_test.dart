import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/support_thread.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/views/shared/support_center_view.dart';

void main() {
  for (final role in ['client', 'driver', 'helper']) {
    testWidgets(
      '$role topic groups keep lazy rows and conversation selection',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        String? selected;
        final threads = List.generate(
          1000,
          (i) => SupportThread(
            id: '$i',
            requesterName: 'Chat $i',
            topicKey: i < 500 ? supportTopicBooking : supportTopicGeneral,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: UserSupportSidebar(
                currentUser: UserModel(id: 'user', role: role),
                threads: threads,
                selectedThreadId: null,
                isThreadUnread: (_) => true,
                selectedTopicKey: supportTopicGeneral,
                selectedBookingId: null,
                accessibleBookings: const [],
                onSelectThread: (thread) => selected = thread.id,
                onTopicChanged: (_) {},
                onBookingChanged: (_) {},
                onOpenThread: () async {},
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Chat 999'), findsNothing);
        expect(find.byType(Text).evaluate().length, lessThan(100));
        await tester.tap(find.text('Chat 0'));
        expect(selected, '0');
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(Text).evaluate().length, lessThan(100));
      },
    );
  }
}
