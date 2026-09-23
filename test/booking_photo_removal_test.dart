import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/status_form_engine.dart';
import 'package:webapp/widgets/shared/booking_form_primitives.dart';
import 'package:webapp/widgets/shared/booking_record_card.dart';

void main() {
  testWidgets('photo action changes to X, clears draft and returns to upload', (
    tester,
  ) async {
    dynamic draft = {'name': 'waybill.jpg'};
    var changes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => BookingPhotoFieldInput(
              initialValue: draft,
              onChanged: (value) => setState(() {
                draft = value;
                changes++;
              }),
            ),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.byIcon(Icons.upload_rounded), findsNothing);
    expect(changes, 0);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(draft, isNull);
    expect(changes, 1);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
    expect(find.byIcon(Icons.upload_rounded), findsOneWidget);
    expect(find.text('waybill.jpg'), findsNothing);
  });

  for (final key in ['waybill_photo', 'delivery_form_photo']) {
    test(
      '$key saved removal survives offline serialization without deleting history',
      () {
        final original = <String, dynamic>{
          'pending': {
            'submitted_at': '2026-09-19T00:00:00Z',
            'fields': {key: 'https://example.test/old.jpg'},
          },
        };
        final removed = StatusFormEngine.appendStatusOutputSection(
          original,
          displayStatusKey: 'delivered',
          statusFormReference: null,
          submittedRole: 'admin',
          submittedRoles: const ['admin'],
          submittedBy: '1',
          fields: {key: null},
          submittedAt: DateTime.utc(2026, 9, 20),
        );
        final persisted =
            jsonDecode(jsonEncode(removed)) as Map<String, dynamic>;
        expect(BookingRecordCard.outputFieldValue(persisted, key), isNull);
        expect(
          BookingRecordCard.outputFieldValue(original, key),
          'https://example.test/old.jpg',
        );
        expect(
          persisted['pending']['fields'][key],
          'https://example.test/old.jpg',
        );
        final replaced = StatusFormEngine.appendStatusOutputSection(
          persisted,
          displayStatusKey: 'delivered',
          statusFormReference: null,
          submittedRole: 'admin',
          submittedRoles: const ['admin'],
          submittedBy: '1',
          fields: {key: 'https://example.test/new.jpg'},
          submittedAt: DateTime.utc(2026, 9, 21),
        );
        expect(
          BookingRecordCard.outputFieldValue(replaced, key),
          'https://example.test/new.jpg',
        );
      },
    );
  }
}
