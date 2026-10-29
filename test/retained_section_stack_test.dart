import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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
    'hidden pages handle deferred updates after unbounded to bounded layout',
    (tester) async {
      final height = ValueNotifier<double>(80);
      addTearDown(height.dispose);
      final pages = [
        const SizedBox(height: 100),
        ValueListenableBuilder<double>(
          valueListenable: height,
          builder: (_, value, _) => SizedBox(
            height: value,
            child: LayoutBuilder(
              builder: (_, constraints) => const Text('Background page'),
            ),
          ),
        ),
      ];
      Widget app(bool bounded, int selected) {
        final stack = RetainedSectionStack(index: selected, children: pages);
        return MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: bounded
                    ? const BoxConstraints.tightFor(width: 600, height: 400)
                    : const BoxConstraints.tightFor(width: 600),
                child: stack,
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(app(false, 0));
      await tester.pumpWidget(app(true, 0));
      for (final value in [120.0, 160.0, 200.0]) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => height.value = value,
        );
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(app(true, 1));
      expect(tester.takeException(), isNull);
      expect(find.text('Background page'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('scrollbar hover exit during menu switches keeps layout valid', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final pages = [
      Scrollbar(
        controller: scroll,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: scroll,
          child: const SizedBox(
            height: 2000,
            width: 600,
            child: Text('Scrollable page'),
          ),
        ),
      ),
      const Text('Other page'),
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
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(598, 20));
    addTearDown(mouse.removePointer);
    for (var i = 0; i < 5; i++) {
      await tester.pumpWidget(app(0, 600));
      await mouse.moveTo(const Offset(598, 40));
      await tester.pump();
      await tester.pumpWidget(app(1, 500));
      await tester.pump();
      await mouse.moveTo(const Offset(300, 40));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'repeated background layout updates survive hiding and restoring a page',
    (tester) async {
      final height = ValueNotifier<double>(80);
      addTearDown(height.dispose);
      final pages = [
        ValueListenableBuilder<double>(
          valueListenable: height,
          builder: (_, value, _) =>
              SizedBox(height: value, child: const Text('Draft')),
        ),
        const SizedBox(height: 100, child: Text('Other page')),
      ];
      Widget app(int selected) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: RetainedSectionStack(index: selected, children: pages),
          ),
        ),
      );
      await tester.pumpWidget(app(0));
      await tester.pumpWidget(app(1));
      for (final value in [120.0, 160.0, 200.0]) {
        height.value = value;
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(app(0));
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.text('Draft')).height, 200);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'framework layout keeps retained pages consistent through resizing and switching',
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
      expect(secondLayouts, 1);
      await tester.pumpWidget(app(0, 400));
      expect(firstLayouts, 2);
      expect(
        secondLayouts,
        2,
        reason: 'Hidden layout must finish so deferred updates remain valid',
      );
      await tester.pumpWidget(app(1, 400));
      expect(firstLayouts, 2);
      expect(secondLayouts, 2);
      await tester.pumpWidget(app(1, 300));
      expect(firstLayouts, 3);
      expect(secondLayouts, 3);
      await tester.pumpWidget(app(0, 300));
      expect(firstLayouts, 3);
      expect(secondLayouts, 3);
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
