@TestOn('browser')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/main.dart';

void main() {
  testWidgets('shows bootstrap loading screen while app is starting', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MyApp(bootstrapFuture: Completer<void>().future),
    );

    expect(
      find.text('Starting PALTRANCO and preparing offline data ...'),
      findsOneWidget,
    );
  });
}
