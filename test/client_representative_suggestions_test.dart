import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/repositories/interfaces/booking_repository.dart';
import 'package:webapp/repositories/interfaces/status_form_repository.dart';
import 'package:webapp/services/client_representative_suggestions.dart';
import 'package:webapp/services/status_field_option_resolver.dart';
import 'package:webapp/services/status_form_engine.dart';
import 'package:webapp/services/field_type_history_service.dart';
import 'package:webapp/widgets/status_form/status_form_runtime_fields.dart';
import 'package:webapp/widgets/status_form/status_field_editor_card.dart';
import 'package:webapp/widgets/admin_form_controls.dart';

class _Bookings implements BookingRepository {
  _Bookings(this.values, {this.fail = false});
  final List<Booking> values;
  final bool fail;
  @override
  Future<List<Booking>> getBookings() async {
    if (fail) throw StateError('offline');
    return values;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Forms implements StatusFormRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const scoped = StatusField(
  id: 'rep',
  key: 'representative_name',
  type: 'text',
  title: 'Representative Name',
  optionSourceKey: statusFieldOptionSourceClientRepresentatives,
);
Booking booking(String client, String name, {String? previous}) => Booking(
  client: UserModel(id: client),
  statusOutputs: {
    'pending': {
      'fields': {'representative_name': previous ?? name},
    },
    'delivered': {
      'fields': {'representative_name': name},
    },
  },
);
void main() {
  test(
    'legacy client-name selections resolve only unambiguous client accounts',
    () {
      const users = [
        UserModel(id: 'a', role: 'client', name: 'MORETA'),
        UserModel(id: 'b', role: 'client', name: 'Other'),
      ];
      expect(representativeClientSelectionId('a', users), 'a');
      expect(representativeClientSelectionId('moreta', users), 'a');
      expect(representativeClientSelectionId('', users), isNull);
      expect(
        representativeClientSelectionId('MORETA', [
          ...users,
          const UserModel(id: 'c', role: 'client', name: 'MORETA'),
        ]),
        isNull,
      );
    },
  );
  testWidgets(
    'text field editor offers the optional representative suggestion source',
    (tester) async {
      final changes = <String, dynamic>{};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatusFieldEditorCard(
                field: const StatusField(
                  id: 'rep',
                  key: 'representative_name',
                  type: 'text',
                ),
                index: 0,
                fieldTypeOptions: const ['text', 'dropdown'],
                onUpdate: (key, value) => changes[key] = value,
              ),
            ),
          ),
        ),
      );
      final source = find.byWidgetPredicate(
        (widget) =>
            widget is AdminDropdownFormField<String> &&
            widget.items?.any(
                  (item) =>
                      item.value ==
                      statusFieldOptionSourceClientRepresentatives,
                ) ==
                true,
      );
      expect(source, findsOneWidget);
      tester.widget<AdminDropdownFormField<String>>(source).onChanged!(
        statusFieldOptionSourceClientRepresentatives,
      );
      expect(
        changes['optionSourceKey'],
        statusFieldOptionSourceClientRepresentatives,
      );
      expect(changes.containsKey('type'), isFalse);
    },
  );

  test(
    'saved names are isolated by client, trimmed, and deduplicated across history',
    () {
      final bookings = [
        booking('a', ' Alice  Santos ', previous: 'Ana Cruz'),
        booking('a', 'alice santos'),
        booking('b', 'Bob Reyes'),
        booking('a', '-'),
      ];
      expect(clientRepresentativeSuggestions(bookings, 'a'), [
        'Alice Santos',
        'Ana Cruz',
      ]);
      expect(clientRepresentativeSuggestions(bookings, 'b'), ['Bob Reyes']);
      expect(clientRepresentativeSuggestions(bookings, null), isEmpty);
      expect(clientRepresentativeSuggestions(bookings, 'missing'), isEmpty);
    },
  );
  test(
    'new source round-trips without changing existing text field schema or history',
    () {
      const legacy = StatusField(
        id: 'old',
        key: 'representative_name',
        type: 'text',
        options: ['Legacy option'],
      );
      final restored = StatusField.fromMap(legacy.toMap());
      expect(restored, legacy);
      expect(restored.usesClientRepresentativeSuggestions, isFalse);
      expect(FieldTypeHistoryService.fieldKey(restored), 'flow:old');
      final enhanced = StatusField.fromMap(scoped.toMap());
      expect(enhanced.type, 'text');
      expect(enhanced.key, 'representative_name');
      expect(enhanced.usesClientRepresentativeSuggestions, isTrue);
      expect(FieldTypeHistoryService.fieldKey(enhanced), isNull);
    },
  );
  test(
    'resolver refreshes suggestions for client selection without overwriting legacy fields',
    () async {
      final resolver = StatusFieldOptionResolver(
        bookingRepository: _Bookings([
          booking('a', 'Alice'),
          booking('b', 'Bob'),
        ]),
      );
      const legacy = StatusField(
        id: 'plain',
        key: 'notes',
        type: 'text',
        options: ['Unchanged'],
      );
      final fields = await resolver.hydrateFields([scoped, legacy]);
      expect(
        fields.first.options,
        isEmpty,
        reason: 'No client is selected in the field library',
      );
      final forA = resolver.withClientRepresentativeSuggestions(
        fields,
        clientId: 'a',
      );
      expect(forA.first.options, ['Alice']);
      expect(forA.last, legacy);
      expect(
        resolver
            .withClientRepresentativeSuggestions(fields, clientId: 'b')
            .first
            .options,
        ['Bob'],
      );
      expect(
        resolver
            .withClientRepresentativeSuggestions(fields, clientId: null)
            .first
            .options,
        isEmpty,
      );
      expect(
        fields.first.options,
        isEmpty,
        reason: 'Runtime names are not written into the saved schema',
      );
    },
  );
  test(
    'unavailable suggestion history does not block new manual values',
    () async {
      final resolver = StatusFieldOptionResolver(
        bookingRepository: _Bookings([], fail: true),
      );
      final fields = await resolver.hydrateFields([scoped]);
      expect(
        resolver
            .withClientRepresentativeSuggestions(fields, clientId: 'a')
            .first
            .options,
        isEmpty,
      );
      final engine = StatusFormEngine(_Forms());
      expect(
        engine.validateFields(
          [
            scoped.copyWith(required: true, options: ['Alice']),
          ],
          {'representative_name': 'A brand new representative'},
        ),
        isEmpty,
      );
    },
  );
  testWidgets(
    'suggestion selection saves its text and still accepts a new custom name',
    (tester) async {
      String? answer;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatusFormRuntimeFieldInput(
              field: scoped.copyWith(options: ['Alice Santos', 'Ana Cruz']),
              initialValue: null,
              onChanged: (value) => answer = value as String,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(find.text('Alice Santos'), findsNothing);
      expect(find.text('Ana Cruz'), findsNothing);
      await tester.enterText(find.byType(TextField), 'Ali');
      await tester.pump();
      expect(find.text('Alice Santos'), findsOneWidget);
      expect(find.text('Ana Cruz'), findsNothing);
      await tester.tap(find.text('Alice Santos'));
      await tester.pump();
      expect(answer, 'Alice Santos');
      await tester.enterText(find.byType(TextField), 'Brand New Name');
      expect(answer, 'Brand New Name');
    },
  );
  testWidgets(
    'changing client options drops previous client suggestions without clearing typed text',
    (tester) async {
      var options = ['Alice'];
      late StateSetter update;
      String? answer;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return StatusFormRuntimeFieldInput(
                  field: scoped.copyWith(options: options),
                  initialValue: answer,
                  onChanged: (value) => answer = value as String,
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(find.text('Alice'), findsNothing);
      await tester.enterText(find.byType(TextField), 'o');
      await tester.pump();
      update(() => options = ['Bob']);
      await tester.pump();
      expect(find.text('Alice'), findsNothing);
      expect(find.text('Bob'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Custom Name');
      update(() => options = ['Alice']);
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Custom Name',
      );
      expect(answer, 'Custom Name');
    },
  );
}
