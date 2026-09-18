import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/widgets/shared/app_resume_recovery.dart';

void main() {
  testWidgets('startup and focus changes never trigger recovery', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      AppResumeRecovery(
        recover: () async {
          calls++;
        },
        child: const SizedBox(),
      ),
    );
    for (var i = 0; i < 5; i++) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 1));
    }
    expect(calls, 0);
  });

  testWidgets('success or failure cannot schedule its own recovery loop', (
    tester,
  ) async {
    for (final shouldFail in [false, true]) {
      var calls = 0;
      await tester.pumpWidget(
        AppResumeRecovery(
          key: ValueKey(shouldFail),
          recover: () async {
            calls++;
            if (shouldFail) throw StateError('offline');
          },
          child: const SizedBox(),
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 10));
      }
      expect(calls, 1);
    }
  });

  testWidgets('disposing the page cancels a queued recovery', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      AppResumeRecovery(
        recover: () async {
          calls++;
        },
        child: const SizedBox(),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 0);
  });

  testWidgets('resume preserves drafts and coalesces duplicate resume events', (
    tester,
  ) async {
    final pending = Completer<void>();
    var calls = 0;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(
        home: AppResumeRecovery(
          settleDelay: const Duration(milliseconds: 10),
          recover: () {
            calls++;
            return pending.future;
          },
          child: const Scaffold(body: TextField()),
        ),
      ),
    );
    await tester.enterText(
      find.byType(TextField),
      'unsaved delivery instructions',
    );
    expect(calls, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 11));
    expect(calls, 1);
    expect(find.text('unsaved delivery instructions'), findsOneWidget);
    // Another background cycle while recovering must not start concurrent work.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 11));
    expect(calls, 1);
    pending.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 11));
    expect(calls, 2);
    expect(find.text('unsaved delivery instructions'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('backgrounding again cancels scheduled recovery', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      AppResumeRecovery(
        recover: () async {
          calls++;
        },
        child: const SizedBox(),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 0);
    await tester.pumpWidget(const SizedBox());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets(
    'failed recovery leaves the page usable and retries next resume',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        AppResumeRecovery(
          recover: () async {
            calls++;
            throw StateError('offline');
          },
          child: const SizedBox(key: ValueKey('existing-page')),
        ),
      );
      for (var i = 0; i < 2; i++) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
      }
      expect(calls, 2);
      expect(find.byKey(const ValueKey('existing-page')), findsOneWidget);
    },
  );
}
