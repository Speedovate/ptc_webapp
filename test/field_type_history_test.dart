import 'package:webapp/widgets/status_form/status_form_runtime_fields.dart';
import 'package:webapp/widgets/shared/admin_modal_form_primitives.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/services/field_type_history_service.dart';
import 'package:webapp/widgets/shared/type_history_input.dart';

class HistoryMemory extends AuthStorageBackend {
  String account = '7';
  bool fail = false;
  final lists = <String, List<String>>{};
  @override
  Future<void> initialize() async {}
  @override
  Future<String?> readString(String key) async => account;
  @override
  Future<List<String>> readStringList(String key) async {
    if (fail) throw StateError('storage unavailable');
    return List.of(lists[key] ?? []);
  }

  @override
  Future<void> writeStringList(String key, List<String> values) async {
    if (fail) throw StateError('quota');
    lists[key] = List.of(values);
  }

  @override
  Future<void> writeString(String key, String value) async {}
  @override
  Future<void> remove(String key) async {
    lists.remove(key);
  }
}

void main() {
  for (final legacy in [false, true]) {
    testWidgets(
      'booking chassis claiming field offers matrix locations (legacy: $legacy)',
      (tester) async {
        dynamic selected;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatusFormRuntimeFieldCard(
                field: StatusField(
                  key: legacy ? 'location' : 'chassis_location',
                  placeholder: legacy
                      ? 'Enter location or Google Maps link'
                      : null,
                  type: 'text',
                  title: 'Location',
                ),
                initialValue: '',
                onChanged: (value) => selected = value,
              ),
            ),
          ),
        );
        expect(find.text('Enter location'), findsWidgets);
        expect(find.text('Enter location or Google Maps link'), findsNothing);
        await tester.tap(find.text('Enter location').first);
        await tester.pumpAndSettle();
        expect(find.text('Garage'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'Rox');
        await tester.pumpAndSettle();
        expect(find.text('Garage'), findsNothing);
        await tester.tap(find.text('Roxas'));
        await tester.pumpAndSettle();
        expect(selected, 'Roxas');
        await tester.tap(find.text('Roxas'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'New depot');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Use "New depot"'));
        await tester.pumpAndSettle();
        expect(selected, 'New depot');
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'prefilled chassis location browses choices then filters typing',
    (tester) async {
      final controller = TextEditingController(text: 'Garage');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TypeHistoryInput(
              controller: controller,
              historyKey: 'chassis:location',
              browseOptionsOnFocus: true,
              service: FieldTypeHistoryService(storage: HistoryMemory()),
              options: const ['Garage', 'Roxas', 'Sicsican'],
              child: TextField(controller: controller),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(find.text('Roxas'), findsOneWidget);
      expect(find.text('Sicsican'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Roxas'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Si');
      await tester.pump();
      expect(find.text('Roxas'), findsNothing);
      expect(find.text('Sicsican'), findsOneWidget);
      await tester.tap(find.text('Sicsican'));
      await tester.pump();
      expect(controller.text, 'Sicsican');
      expect(find.byType(TextButton), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'default policy enables text-like fields but excludes identities/secrets',
    () {
      for (final type in ['text', 'email', 'phone', 'number']) {
        expect(
          FieldTypeHistoryService.fieldKey(
            StatusField(id: '8', type: type, key: 'shipping_location'),
          ),
          'flow:8',
        );
      }
      for (final key in [
        'waybill_number',
        'delivery_form_number',
        'password',
        'secret',
        'driver_id',
        'security_pin',
      ]) {
        expect(
          FieldTypeHistoryService.fieldKey(
            StatusField(id: '8', type: 'text', key: key),
          ),
          isNull,
        );
      }
      expect(
        FieldTypeHistoryService.fieldKey(
          const StatusField(id: 'offline_field_8', type: 'text', key: 'name'),
        ),
        isNull,
      );
    },
  );

  test(
    'history is scoped, bounded, deduplicated and preserves action date',
    () async {
      final storage = HistoryMemory();
      final service = FieldTypeHistoryService(storage: storage);
      final at = DateTime.utc(2026, 9, 19);
      await service.record('7', {'flow:8': 'Garage'}, at);
      await service.record('8', {'flow:8': 'Other account'}, at);
      await service.record('7', {'flow:9': 'Other field'}, at);
      await service.record('7', {
        'flow:8': 'garage',
      }, at.subtract(const Duration(days: 1)));
      expect(await service.suggestions('flow:8', 'gar'), ['Garage']);
      final saved = storage.lists['field_type_history_v1::7']!
          .map((s) => jsonDecode(s) as Map)
          .firstWhere((e) => e['field'] == 'flow:8');
      expect(saved['at'], at.toIso8601String());
      storage.account = '8';
      expect(await service.suggestions('flow:8', ''), ['Other account']);
      storage.account = '7';
      await Future.wait(
        List.generate(
          40,
          (i) => service.record('7', {
            'flow:8': 'value$i',
          }, at.add(Duration(seconds: i + 1))),
        ),
      );
      expect(await service.suggestions('flow:8', ''), hasLength(10));
      expect(
        storage.lists['field_type_history_v1::7']!
            .map((s) => jsonDecode(s))
            .where((e) => e['field'] == 'flow:8'),
        hasLength(30),
      );
      storage.fail = true;
      expect(await service.suggestions('flow:8', ''), isEmpty);
      await service.record('7', {'flow:8': 'safe failure'}, at);
    },
  );

  testWidgets('chassis options touch the input border with spacing below', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TypeHistoryInput(
            controller: controller,
            historyKey: 'chassis:location',
            service: FieldTypeHistoryService(storage: HistoryMemory()),
            options: const ['Garage'],
            optionsBottomSpacing: 12,
            child: AdminModalTextField(
              controller: controller,
              label: 'Location',
              bottomPadding: 0,
              minHeight: 0,
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Gar');
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pump();
    final border = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_BorderContainer',
    );
    final options = find
        .ancestor(of: find.byType(ListView), matching: find.byType(Container))
        .first;
    expect(border, findsOneWidget);
    expect(tester.getTopLeft(options).dy, tester.getBottomLeft(border).dy);
    expect(
      tester.getBottomLeft(find.byType(TypeHistoryInput)).dy -
          tester.getBottomLeft(options).dy,
      12,
    );
  });

  testWidgets(
    'existing chassis locations appear with no typing history and update while focused',
    (tester) async {
      final storage = HistoryMemory();
      final service = FieldTypeHistoryService(storage: storage);
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      Widget field(List<String> options) => MaterialApp(
        home: Scaffold(
          body: TypeHistoryInput(
            controller: controller,
            historyKey: 'chassis:location',
            service: service,
            options: options,
            child: TextField(controller: controller),
          ),
        ),
      );
      await tester.pumpWidget(field(const []));
      await tester.enterText(find.byType(TextField), 'Gar');
      await tester.pump(const Duration(milliseconds: 301));
      await tester.pumpWidget(field(const ['Garage', 'Garage', 'Port']));
      await tester.pump(const Duration(milliseconds: 301));
      await tester.pump();
      expect(find.text('Garage'), findsOneWidget);
      expect(find.text('Port'), findsNothing);
      await tester.tap(find.text('Garage'));
      await tester.pump();
      expect(controller.text, 'Garage');
      expect(storage.lists, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'suggestions do not write on typing; selecting applies formatter and emits change',
    (tester) async {
      final storage = HistoryMemory();
      final service = FieldTypeHistoryService(storage: storage);
      await service.record('7', {
        'chassis:location': 'Garage',
      }, DateTime.utc(2026));
      final original = List.of(storage.lists['field_type_history_v1::7']!);
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var changed = '';
      controller.addListener(() {
        changed = controller.text;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TypeHistoryInput(
              controller: controller,
              historyKey: 'chassis:location',
              service: service,
              options: const ['Garage', 'Garden'],
              inputFormatters: [
                TextInputFormatter.withFunction(
                  (old, next) => next.copyWith(text: next.text.toUpperCase()),
                ),
              ],
              child: TextField(controller: controller),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Gar');
      await tester.pump(const Duration(milliseconds: 301));
      await tester.pump();
      expect(find.text('Garage'), findsOneWidget);
      expect(find.text('Garden'), findsOneWidget);
      await tester.tap(find.text('Garage'));
      await tester.pump();
      expect(controller.text, 'GARAGE');
      expect(changed, 'GARAGE');
      expect(storage.lists['field_type_history_v1::7'], original);
      await tester.enterText(find.byType(TextField), 'new');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );
}
