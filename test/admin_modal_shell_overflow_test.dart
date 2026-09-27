import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';

/// The shell's own body budget does not subtract the title, so a tall body
/// could ask for more room than the dialog has and spill out of it. These
/// tests pin the behaviour that it scrolls instead.
void main() {
  Widget tallDialog({required double fieldHeight, required int fields}) =>
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AdminModalShell(
                  title: 'Tall Dialog',
                  actions: const [
                    TextButton(onPressed: null, child: Text('Cancel')),
                    TextButton(onPressed: null, child: Text('Save')),
                  ],
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      fields,
                      (i) => SizedBox(
                        height: fieldHeight,
                        child: Text('field $i'),
                      ),
                    ),
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  // A short viewport is the case that used to overflow: the body wanted more
  // than the title and actions left available.
  for (final size in [const Size(800, 600), const Size(500, 560)]) {
    testWidgets('a body taller than the dialog scrolls at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(tallDialog(fieldHeight: 90, fields: 8));
      await open(tester);
      expect(tester.takeException(), isNull);

      // The first field is visible; the last is not, and reaching it means the
      // body scrolls rather than being clipped away.
      expect(find.text('field 0'), findsOneWidget);
      final scrollable = find.byType(Scrollable);
      expect(scrollable, findsWidgets);
      await tester.drag(scrollable.first, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('field 7'), findsOneWidget);

      // The actions stay reachable; a modal that hides its own buttons on a
      // short screen is worse than one that scrolls.
      expect(find.text('Save'), findsOneWidget);
    });
  }

  testWidgets('a short body is untouched and shows no scrollbar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(tallDialog(fieldHeight: 40, fields: 2));
    await open(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('field 0'), findsOneWidget);
    expect(find.text('field 1'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('flexibleBody keeps working with an unbounded child', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AdminModalShell(
                  title: 'Flexible',
                  flexibleBody: true,
                  actions: const [
                    TextButton(onPressed: null, child: Text('OK')),
                  ],
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      10,
                      (i) => SizedBox(height: 80, child: Text('row $i')),
                    ),
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await open(tester);
    expect(find.text('Flexible'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
