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
