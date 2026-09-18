import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/widgets/shared/startup_splash_handoff.dart';

void main() {
  testWidgets('dismisses only after a ready frame, once per home', (
    tester,
  ) async {
    var calls = 0;
    Widget home(bool ready) => StartupSplashHandoff(
      ready: ready,
      onReady: () => calls++,
      child: const SizedBox(),
    );
    await tester.pumpWidget(home(false));
    expect(calls, 0);
    await tester.pumpWidget(home(true));
    expect(calls, 1);
    await tester.pumpWidget(home(false));
    await tester.pumpWidget(home(true));
    expect(calls, 1);
  });
}
