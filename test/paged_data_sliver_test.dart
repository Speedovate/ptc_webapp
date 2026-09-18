import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/widgets/shared/lazy_data_scroll_view.dart';
import 'package:webapp/widgets/shared/paged_data_sliver.dart';

void main() {
  testWidgets(
    'loads 15 per pull, stays idle between gestures and preserves/reset windows',
    (tester) async {
      final all = List.generate(1000, (i) => i);
      var filter = '';
      var detail = false;
      var presented = <int>[];
      late StateSetter update;
      final bucket = PageStorageBucket();
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Scaffold(
                body: PageStorage(
                  bucket: bucket,
                  child: detail
                      ? const Text('Detail')
                      : PagedScrollObserver(
                          child: LazyDataScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: PagedDataSliver<int>(
                              items: filter.isEmpty
                                  ? all
                                  : all.where((i) => '$i' == filter).toList(),
                              resetKey: filter,
                              storageId: 'bookings',
                              builder: (context, items) {
                                presented = items;
                                return LazySliverList(
                                  items: items,
                                  itemBuilder: (context, item) => SizedBox(
                                    height: 80,
                                    child: Text('Row $item'),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                ),
              );
            },
          ),
        ),
      );
      expect(presented.length, 15);
      expect(find.byType(OutlinedButton), findsNothing);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(presented.length, 30);
      await tester.pump(const Duration(seconds: 2));
      expect(presented.length, 30);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 200));
      await tester.pumpAndSettle();
      expect(presented.length, 30);
      expect(all.length, 1000);
      update(() => detail = true);
      await tester.pump();
      update(() => detail = false);
      await tester.pump();
      expect(presented.length, 30);
      update(() => filter = '999');
      await tester.pumpAndSettle();
      expect(presented, [999]);
      expect(find.text('Load more'), findsNothing);
      update(() => filter = '');
      await tester.pumpAndSettle();
      expect(presented.length, 15);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'short batches respond to wheel input, clamp final batch and stop after disposal',
    (tester) async {
      var count = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PagedScrollObserver(
              child: LazyDataScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: PagedDataSliver<int>(
                  items: List.generate(31, (i) => i),
                  resetKey: '',
                  builder: (context, items) {
                    count = items.length;
                    return LazySliverList(
                      items: items,
                      itemBuilder: (context, i) =>
                          SizedBox(height: 8, child: Text('$i')),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      expect(count, 15);
      await tester.pump(const Duration(seconds: 1));
      expect(count, 15);
      for (final expected in [30, 31, 31]) {
        tester.binding.handlePointerEvent(
          const PointerScrollEvent(
            position: Offset(100, 100),
            scrollDelta: Offset(0, 200),
          ),
        );
        await tester.pumpAndSettle();
        expect(count, expected);
      }
      expect(find.text('Pull up to load more'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      tester.binding.handlePointerEvent(
        const PointerScrollEvent(
          position: Offset(100, 100),
          scrollDelta: Offset(0, 200),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('restoring scroll offset does not load but another pull does', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var count = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PagedScrollObserver(
            child: LazyDataScrollView(
              controller: controller,
              physics: const AlwaysScrollableScrollPhysics(),
              child: PagedDataSliver<int>(
                items: List.generate(100, (i) => i),
                resetKey: '',
                builder: (context, items) {
                  count = items.length;
                  return LazySliverList(
                    items: items,
                    itemBuilder: (context, i) =>
                        SizedBox(height: 80, child: Text('$i')),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(count, 15);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(count, 30);
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(count, 30);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(count, 45);
    expect(tester.takeException(), isNull);
  });
}
