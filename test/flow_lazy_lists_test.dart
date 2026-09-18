import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/status.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/models/status_form.dart';
import 'package:webapp/view_models/admin/admin_flow.vm.dart';
import 'package:webapp/views/admin/admin_fields.dart';
import 'package:webapp/views/admin/admin_forms.dart';
import 'package:webapp/views/admin/admin_statuses.dart';

class _Flow extends AdminFlowViewModel {
  @override
  Future<void> loadFormsPage() async {}
  @override
  Future<void> loadFieldsPage() async {}
  @override
  Future<void> loadStatusesPage() async {}
}

void main() {
  for (final width in [400.0, 2400.0]) {
    for (final page in ['fields', 'forms', 'statuses']) {
      testWidgets(
        '$page uses lazy rows at $width and responds to filtering/data updates',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 800));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final vm = _Flow();
          addTearDown(vm.dispose);
          vm.fieldLibrary = List.generate(
            1000,
            (i) => StatusField(
              id: '$i',
              key: 'field_$i',
              title: 'Record $i',
              type: 'text',
              isActive: true,
            ),
          );
          vm.forms = List.generate(
            1000,
            (i) => StatusForm(
              id: '$i',
              statusText: 'Record $i',
              role: 'admin',
              isActive: true,
            ),
          );
          vm.statuses = List.generate(
            1000,
            (i) => Status(
              id: '$i',
              key: 'status_$i',
              label: 'Record $i',
              isActive: true,
            ),
          );
          final screen = switch (page) {
            'fields' => AdminFieldsView(viewModel: vm),
            'forms' => AdminFormsView(viewModel: vm),
            _ => AdminStatusesView(viewModel: vm),
          };
          await tester.pumpWidget(MaterialApp(home: Scaffold(body: screen)));
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(find.text('Record 999'), findsNothing);
          expect(find.byType(Text).evaluate().length, lessThan(350));
          await tester.drag(
            find.byType(CustomScrollView).first,
            const Offset(0, -550),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byType(Text).evaluate().length, lessThan(350));
          final scroll = tester.state<ScrollableState>(
            find.byType(Scrollable).first,
          );
          scroll.position.jumpTo(0);
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField).first, 'Record 999');
          await tester.pumpAndSettle();
          expect(find.text('Record 999'), findsWidgets);
          vm.fieldLibrary = [];
          vm.forms = [];
          vm.statuses = [];
          vm.notifyListeners();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
