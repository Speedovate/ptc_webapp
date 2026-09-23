@TestOn('browser')
library;

// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/widgets/shared/native_date_input.dart';

void main() {
  testWidgets('native browser date input initializes, edits and disposes', (
    tester,
  ) async {
    final registry = _DateInputRegistry();
    ui_web.debugOverridePlatformViewRegistry(registry);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
          if (call.method == 'create') {
            final args = call.arguments as Map;
            registry.elements[args['id'] as int] = html.InputElement();
          } else if (call.method == 'dispose') {
            registry.elements.remove(call.arguments);
          }
          return null;
        });
    addTearDown(() {
      ui_web.debugOverridePlatformViewRegistry(null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform_views, null);
    });
    DateTime? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NativeDateInput(
            label: 'From',
            value: DateTime(2026, 9, 19),
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Widget tests create platform elements without attaching them to document.
    final surface = tester.widget<PlatformViewSurface>(
      find.byType(PlatformViewSurface),
    );
    final input =
        ui_web.platformViewRegistry.getViewById(surface.controller.viewId)
            as html.InputElement;
    expect(input.type, 'date');
    expect(input.value, '2026-09-19');
    input.value = '2026-09-20';
    input.dispatchEvent(html.Event('input'));
    expect(selected, DateTime.utc(2026, 9, 20));
    input.value = '';
    input.dispatchEvent(html.Event('input'));
    expect(selected, isNull);
    await tester.pumpWidget(const SizedBox());
    input.value = '2026-09-21';
    input.dispatchEvent(html.Event('input'));
    expect(selected, isNull);
  });
}

class _DateInputRegistry implements ui_web.PlatformViewRegistry {
  final elements = <int, html.InputElement>{};
  @override
  Object getViewById(int id) => elements[id]!;
  @override
  bool registerViewFactory(
    String viewType,
    Function viewFactory, {
    bool isVisible = true,
  }) => true;
}
