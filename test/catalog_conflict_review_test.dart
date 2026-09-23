import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/widgets/shared/catalog_conflict_review_dialog.dart';

const review = CatalogConflictReview(
  id: 'queued',
  storageKey: 'manager',
  pending: {},
  proposed: {
    'locations': [
      {'name': 'Narra', 'active': false},
    ],
  },
  server: {
    'locations': [
      {'name': 'Narra', 'active': true},
    ],
  },
  serverVersions: [],
);

void main() {
  test('comparison identifies the location and exact changed field', () {
    expect(catalogConflictRows(review), [
      ['locations / Narra / active', 'false', 'true'],
    ]);
  });
  for (final width in [375.0, 1200.0]) {
    testWidgets('review requires explicit apply at $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var applied = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => CatalogConflictReviewDialog(
                    review: review,
                    onApply: () async {
                      applied++;
                    },
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('locations / Narra / active'), findsOneWidget);
      expect(applied, 0);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Apply pending changes'));
      await tester.pumpAndSettle();
      expect(applied, 1);
      expect(find.byType(CatalogConflictReviewDialog), findsNothing);
    });
  }
}
