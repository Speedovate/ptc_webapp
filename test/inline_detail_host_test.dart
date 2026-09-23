import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/widgets/shared/inline_detail_host.dart';

void main() {
  testWidgets(
    'related details keep shell and source scroll without pushing routes',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      var returned = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('Existing shell')),
            body: InlineDetailHost(
              child: Builder(
                builder: (context) => Column(
                  children: [
                    TextButton(
                      onPressed: () async {
                        await InlineDetailHost.open(
                          context,
                          (userContext) => Column(
                            children: [
                              const Text('Client details'),
                              TextButton(
                                onPressed: () => InlineDetailHost.open(
                                  userContext,
                                  (bookingContext) => TextButton(
                                    onPressed: () =>
                                        InlineDetailHost.close(bookingContext),
                                    child: const Text('Back from booking'),
                                  ),
                                ),
                                child: const Text('View booking'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    InlineDetailHost.close(userContext),
                                child: const Text('Back to chassis'),
                              ),
                            ],
                          ),
                        );
                        returned = true;
                      },
                      child: const Text('Open client'),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: scroll,
                        itemExtent: 60,
                        itemCount: 100,
                        itemBuilder: (_, index) => Text('Chassis $index'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.drag(find.byType(ListView), const Offset(0, -800));
      await tester.pumpAndSettle();
      final offset = scroll.offset;
      await tester.tap(find.text('Open client'));
      await tester.pumpAndSettle();
      expect(find.text('Existing shell'), findsOneWidget);
      expect(find.text('Client details'), findsOneWidget);
      expect(
        Navigator.of(tester.element(find.text('Client details'))).canPop(),
        isFalse,
      );
      await tester.tap(find.text('View booking'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back from booking'));
      await tester.pumpAndSettle();
      expect(find.text('Client details'), findsOneWidget);
      await tester.tap(find.text('Back to chassis'));
      await tester.pumpAndSettle();
      expect(returned, isTrue);
      expect(scroll.offset, offset);
      expect(find.text('Open client'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
