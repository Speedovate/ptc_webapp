import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/widgets/shared/retained_section_stack.dart';

class _Section extends StatefulWidget {
  const _Section({super.key});
  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation;
  final draft = TextEditingController();
  int ticks = 0;
  @override
  void initState() {
    super.initState();
    animation =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..addListener(() => ticks++)
          ..repeat();
  }

  @override
  void dispose() {
    animation.dispose();
    draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(controller: draft);
}

void main() {
  testWidgets(
    'viewport resize lays out only the selected page and activates hidden pages on demand',
    (tester) async {
      var firstLayouts = 0;
      var secondLayouts = 0;
      final pages = [
        LayoutBuilder(
          builder: (context, constraints) {
            firstLayouts++;
            return const SizedBox.expand();
          },
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            secondLayouts++;
            return const SizedBox.expand();
          },
        ),
      ];
      Widget app(int selected, double width) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            height: 400,
            child: RetainedSectionStack(index: selected, children: pages),
          ),
        ),
      );
      await tester.pumpWidget(app(0, 600));
      expect(firstLayouts, 1);
      expect(secondLayouts, 0);
      await tester.pumpWidget(app(0, 400));
      expect(firstLayouts, 2);
      expect(
        secondLayouts,
        0,
        reason: 'Hidden page must not be laid out on viewport changes',
      );
      await tester.pumpWidget(app(1, 400));
      expect(firstLayouts, 2);
      expect(secondLayouts, 1);
      await tester.pumpWidget(app(1, 300));
      expect(firstLayouts, 2);
      expect(secondLayouts, 2);
      await tester.pumpWidget(app(0, 300));
      expect(firstLayouts, 3);
      expect(secondLayouts, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('unbounded hosts retain normal content sizing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RetainedSectionStack(
              index: 0,
              children: [SizedBox(height: 80), SizedBox(height: 160)],
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(RetainedSectionStack)).height, 160);
    expect(tester.takeException(), isNull);
  });
  testWidgets('hidden animation pauses, draft and state survive switching', (
    tester,
  ) async {
    final a = GlobalKey<_SectionState>();
    final b = GlobalKey<_SectionState>();
    Widget app(int selected) => MaterialApp(
      home: Scaffold(
        body: RetainedSectionStack(
          index: selected,
          children: [
            _Section(key: a),
            _Section(key: b),
          ],
        ),
      ),
    );
    await tester.pumpWidget(app(0));
    await tester.pump(const Duration(milliseconds: 100));
    final original = a.currentState!;
    original.draft.text = 'unsaved draft';
    final ticksA = original.ticks;
    final ticksB = b.currentState!.ticks;
    await tester.pump(const Duration(milliseconds: 100));
    expect(original.ticks, greaterThan(ticksA));
    expect(b.currentState!.ticks, ticksB);
    await tester.pumpWidget(app(1));
    final paused = original.ticks;
    final active = b.currentState!.ticks;
    await tester.pump(const Duration(milliseconds: 100));
    expect(original.ticks, paused);
    expect(b.currentState!.ticks, greaterThan(active));
    await tester.pumpWidget(app(0));
    expect(a.currentState, same(original));
    expect(a.currentState!.draft.text, 'unsaved draft');
    await tester.pump(const Duration(milliseconds: 100));
    expect(original.ticks, greaterThan(paused));
    await tester.pumpWidget(const SizedBox());
  });
}
