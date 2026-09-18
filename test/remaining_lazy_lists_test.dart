import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/booking_conflict_review_service.dart';
import 'package:webapp/view_models/admin/booking_conflict_review.vm.dart';
import 'package:webapp/views/admin/admin_access.dart';
import 'package:webapp/views/admin/booking_conflict_review_dialog.dart';
import 'package:webapp/widgets/shared/lazy_data_scroll_view.dart';

class _Service extends Fake implements BookingConflictReviewService {}

class _Review extends BookingConflictReviewViewModel {
  _Review() : super(service: _Service(), adminId: '1');
  String? selected;
  @override
  Future<void> load() async {}
  @override
  Future<void> select(String id) async {
    selected = id;
  }
}

void main() {
  for (final width in [400.0, 1100.0, 2400.0]) {
    testWidgets('Access roles are lazy at $width with working edit actions', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LazyDataScrollView(
              child: AccessRoleListSliver(
                roles: List.generate(
                  1000,
                  (i) => AccessRoleEntry(
                    id: '$i',
                    roleKey: 'role_$i',
                    label: 'Role $i',
                    permissionCount: 2,
                    createdAt: null,
                    updatedAt: null,
                  ),
                ),
                errorMessage: null,
                isLoading: false,
                hasCompletedInitialLoad: true,
                onEditPressed: (role) => selected = role.id,
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Role 999'), findsNothing);
      expect(find.byType(Text).evaluate().length, lessThan(300));
      await tester.tap(find.byIcon(Icons.edit_rounded).first);
      expect(selected, '0');
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(Text).evaluate().length, lessThan(300));
    });
  }
  testWidgets(
    'conflict dialog has one bounded viewport and lazy conflict buttons',
    (tester) async {
      final vm = _Review()..conflicts = List.generate(1000, (i) => '$i');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BookingConflictReviewDialog(viewModel: vm)),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(
        find.byType(OutlinedButton).evaluate().length,
        inExclusiveRange(0, 30),
      );
      expect(find.text('Review 999'), findsNothing);
      await tester.tap(find.text('Review 0'));
      expect(vm.selected, '0');
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(OutlinedButton).evaluate().length, lessThan(30));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('large conflict comparisons render only visible fields', (
    tester,
  ) async {
    final vm = _Review()
      ..preview = BookingConflictPreview(
        id: 'offline_example',
        report: {'target_id': '1'},
        source: {for (var i = 0; i < 1000; i++) 'field_$i': 'temporary'},
        canonical: {for (var i = 0; i < 1000; i++) 'field_$i': 'numeric'},
        reservation: null,
        references: {},
      );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BookingConflictReviewDialog(viewModel: vm)),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('field 999'), findsNothing);
    expect(find.byType(Text).evaluate().length, lessThan(150));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(Text).evaluate().length, lessThan(150));
    await tester.pumpWidget(const SizedBox());
  });
}
