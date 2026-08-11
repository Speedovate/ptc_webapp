import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/main.dart';

void main() {
  testWidgets('shows bootstrap loading screen while app is starting', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MyApp(bootstrapFuture: Future<void>.delayed(const Duration(seconds: 1))),
    );

    expect(find.text('Starting app and loading offline data ...'), findsOneWidget);
  });
}
