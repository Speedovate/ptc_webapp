import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/widgets/shared/retained_section_stack.dart';

void main() {
  for (final background in [Colors.white, AppColors.primaryColor]) {
    for (final gesture in ['drag', 'double click', 'long press']) {
      testWidgets(
        'visible retained page highlights and copies with $gesture on $background',
        (tester) async {
          String? copied;
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'Clipboard.setData') {
                copied = (call.arguments as Map)['text'] as String;
              }
              if (call.method == 'Clipboard.hasStrings') {
                return {'value': copied != null};
              }
              return null;
            },
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null),
          );
          Widget app(int index) => MaterialApp(
            theme: ThemeData(
              platform: TargetPlatform.macOS,
              textSelectionTheme: const TextSelectionThemeData(
                selectionColor: AppColors.selectionHighlight,
              ),
            ),
            home: Scaffold(
              body: SelectionArea(
                child: RetainedSectionStack(
                  index: index,
                  children: [
                    Align(
                      alignment: Alignment.topLeft,
                      child: Text('Hidden dashboard'),
                    ),
                    Align(
                      alignment: Alignment.topLeft,
                      child: ColoredBox(
                        color: background,
                        child: Text(
                          'Revenue 12345',
                          style: TextStyle(
                            color: background == Colors.white
                                ? Colors.black
                                : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpWidget(app(0));
          await tester.pumpAndSettle();
          await tester.pumpWidget(app(1));
          await tester.pumpAndSettle();
          final text = find.text('Revenue 12345');
          final rect = tester.getRect(text);
          final start = rect.centerLeft + const Offset(2, 0);
          if (gesture == 'drag') {
            final pointer = await tester.startGesture(
              start,
              kind: PointerDeviceKind.mouse,
            );
            await pointer.moveTo(rect.centerRight - const Offset(2, 0));
            await pointer.up();
          } else if (gesture == 'double click') {
            await tester.tapAt(start, kind: PointerDeviceKind.mouse);
            await tester.pump(const Duration(milliseconds: 100));
            await tester.tapAt(start, kind: PointerDeviceKind.mouse);
          } else {
            await tester.longPressAt(start);
          }
          await tester.pumpAndSettle();
          final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(of: text, matching: find.byType(RichText)),
          );
          expect(paragraph.selections.any((s) => !s.isCollapsed), isTrue);
          expect(paragraph.selectionColor, AppColors.selectionHighlight);
          final highlighted = Color.alphaBlend(
            paragraph.selectionColor!,
            background,
          );
          expect(
            (highlighted.computeLuminance() - background.computeLuminance())
                .abs(),
            greaterThan(0.1),
          );
          final hidden = tester.renderObject<RenderParagraph>(
            find.descendant(
              of: find.text('Hidden dashboard', skipOffstage: false),
              matching: find.byType(RichText, skipOffstage: false),
              skipOffstage: false,
            ),
          );
          expect(hidden.selections.where((s) => !s.isCollapsed), isEmpty);
          if (find.text('Copy').evaluate().isEmpty) {
            final menu = await tester.startGesture(
              start,
              kind: PointerDeviceKind.mouse,
              buttons: kSecondaryMouseButton,
            );
            await menu.up();
            await tester.pumpAndSettle();
          }
          await tester.tap(find.text('Copy').last);
          await tester.pumpAndSettle();
          expect(copied, gesture == 'drag' ? 'Revenue 12345' : 'Revenue');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
