import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/view_models/admin/admin_flow.vm.dart';
import 'package:webapp/views/admin/admin_fields.dart';
import 'package:webapp/widgets/shared/admin_modal_form_primitives.dart';

class _Flow extends AdminFlowViewModel {
  StatusField? saved;
  @override
  bool get canCreateFields => true;
  @override
  bool get canUpdateFields => true;
  @override
  Future<void> saveLibraryField(StatusField field) async {
    saved = field;
  }
}

Finder input(String label) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is AdminModalValueTextField && widget.label == label,
  ),
  matching: find.byType(TextFormField),
);

void main() {
  testWidgets('shared value field emits typed changes to its owning form', (
    tester,
  ) async {
    String? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminModalValueTextField(
            label: 'Field Key',
            onChanged: (value) => changed = value,
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField), 'booking_type');
    expect(changed, 'booking_type');
  });
  for (final editing in [false, true]) {
    testWidgets(
      '${editing ? 'Edit' : 'New'} Field saves typed key, title and dropdown options',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1000, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final vm = _Flow();
        addTearDown(vm.dispose);
        const initial = StatusField(
          id: 'draft',
          type: 'dropdown',
          isActive: true,
        );
        if (!editing) vm.draftNewField = initial;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => AdminFieldsView.openFieldDialog(
                    context,
                    vm,
                    title: editing ? 'Edit Field' : 'New Field',
                    initialField: editing
                        ? initial.copyWith(
                            key: 'old_key',
                            title: 'Old title',
                            options: ['Old'],
                          )
                        : null,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        // The shared modal guard debounces presentations using wall-clock time.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 400)),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        for (final entry in {
          'Options': 'Regular, Husting',
          'Title': 'Booking Type',
          'Field Key': 'booking_type',
        }.entries) {
          final field = input(entry.key);
          await tester.ensureVisible(field);
          await tester.enterText(field, entry.value);
          await tester.pump();
        }
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();
        expect(find.text('Field key is required.'), findsNothing);
        expect(vm.saved?.key, 'booking_type');
        expect(vm.saved?.title, 'Booking Type');
        expect(vm.saved?.options, ['Regular', 'Husting']);
        expect(find.text(editing ? 'Edit Field' : 'New Field'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
