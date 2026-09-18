import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/widgets/shared/lazy_data_scroll_view.dart';

void main() {
  testWidgets('large grouped lists build only visible rows and keep actions', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var builds = 0;
    int? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LazyDataScrollView(
            controller: controller,
            child: SliverSection(
              children: [
                const Text('Header'),
                for (var group = 0; group < 3; group++) ...[
                  Text('Group $group'),
                  LazySliverList(
                    items: List.generate(1000, (i) => group * 1000 + i),
                    itemBuilder: (context, i) {
                      builds++;
                      return SizedBox(
                        height: 80,
                        child: TextButton(
                          onPressed: () => selected = i,
                          child: Text('Row $i'),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(builds, lessThan(50));
    expect(find.text('Row 999'), findsNothing);
    await tester.tap(find.text('Row 0'));
    expect(selected, 0);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
    expect(builds, lessThan(100));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'width builder caches scrolling and invalidates data, size and text scale',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      var measurements = 0;
      var generation = 0;
      var scale = 1.0;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: LazyDataScrollView(
                    controller: controller,
                    child: SliverWidthBuilder(
                      builder: (context, constraints) {
                        measurements++;
                        final snapshot = generation;
                        return SliverSection(
                          children: [
                            Text('Data $snapshot'),
                            LazySliverList(
                              items: List.generate(1000, (i) => i),
                              itemBuilder: (context, i) =>
                                  SizedBox(height: 80, child: Text('Item $i')),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      expect(measurements, 1);
      controller.jumpTo(300);
      await tester.pump();
      controller.jumpTo(600);
      await tester.pump();
      expect(measurements, 1);
      update(() => generation++);
      await tester.pump();
      expect(measurements, 2);
      update(() => scale = 1.5);
      await tester.pump();
      expect(measurements, 3);
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pump();
      expect(measurements, greaterThan(3));
      expect(tester.takeException(), isNull);
    },
  );
}
