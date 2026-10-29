import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/models/status_form.dart';
import 'package:webapp/repositories/interfaces/status_form_repository.dart';
import 'package:webapp/services/booking_edit_fields.dart';
import 'package:webapp/widgets/shared/booking_additional_fields_editor.dart';
import 'package:webapp/widgets/admin_form_controls.dart';

const bookingType = StatusField(
  id: 'type',
  key: 'booking_type',
  type: 'dropdown',
  title: 'Booking Type',
  options: ['Regular', 'Husting'],
  required: true,
);
const note = StatusField(
  id: 'note',
  key: 'office_note',
  type: 'text',
  title: 'Office Note',
  visibilityControllerKey: 'booking_type',
  visibilityOptionValues: ['Husting'],
);
const count = StatusField(
  id: 'count',
  key: 'trip_count',
  type: 'number',
  title: 'Trip Count',
);
const photo = StatusField(
  id: 'photo',
  key: 'custom_photo',
  type: 'photo',
  title: 'Custom Photo',
);
const choices = StatusField(
  id: 'choices',
  key: 'services',
  type: 'checkbox',
  title: 'Services',
  options: ['One', 'Two'],
);
const forms = [
  StatusForm(
    id: 'book',
    isActive: true,
    fields: [
      bookingType,
      count,
      photo,
      choices,
      StatusField(id: 'amount', key: 'amount'),
    ],
  ),
  StatusForm(id: 'assign', isActive: true, fields: [bookingType, note]),
  StatusForm(
    id: 'inactive',
    isActive: false,
    fields: [StatusField(key: 'inactive_form_field')],
  ),
];

class _Forms extends Fake implements StatusFormRepository {
  @override
  Future<List<StatusForm>> getStatusForms() async => forms;
  @override
  Future<List<StatusField>> getAllFields() async => [
    bookingType,
    note,
    count,
    photo,
    choices,
  ];
}

BookingEditFields controller([Map<String, dynamic> values = const {}]) =>
    BookingEditFields(
      initialAnswers: values,
      seedForms: forms,
      hasResolvedForms: true,
      repository: _Forms(),
    );
void main() {
  test(
    'collects assigned active fields across forms, resolves library references and deduplicates keys',
    () {
      final result = configuredBookingEditFields(
        [
          ...forms,
          const StatusForm(
            isActive: true,
            fields: [
              StatusField(id: 'library-reference'),
              StatusField(key: 'retired', isActive: false),
            ],
          ),
        ],
        const [
          StatusField(
            id: 'library-reference',
            key: 'added_field',
            type: 'text',
            title: 'Added',
          ),
          StatusField(id: 'unused', key: 'unused'),
        ],
      );
      expect(result.map((f) => f.key), [
        'booking_type',
        'trip_count',
        'custom_photo',
        'services',
        'office_note',
        'added_field',
      ]);
      expect(result.first.options, ['Regular', 'Husting']);
    },
  );
  test('loads form configuration when shared snapshots are absent', () async {
    final model = BookingEditFields(initialAnswers: {}, repository: _Forms());
    addTearDown(model.dispose);
    await model.load();
    expect(model.loadError, isNull);
    expect(model.fields.map((f) => f.key), contains('booking_type'));
  });
  test(
    'typed values, photos, checkboxes and explicit clears produce deltas while untouched historical values remain intact',
    () {
      final model = controller({
        'booking_type': 'Regular',
        'office_note': 'Original',
        'unassigned_legacy': {'keep': true},
      });
      addTearDown(model.dispose);
      expect(model.changes({}, 'client'), isEmpty);
      model.update('booking_type', 'Husting');
      model.update('office_note', '');
      model.update('trip_count', '3');
      model.update('custom_photo', {
        'download_url': 'https://example.test/photo.jpg',
      });
      model.update('services', ['One']);
      expect(model.validate({}, 'client'), isTrue);
      expect(model.changes({}, 'client'), {
        'booking_type': 'Husting',
        'office_note': null,
        'trip_count': '3',
        'custom_photo': {'download_url': 'https://example.test/photo.jpg'},
        'services': ['One'],
      });
      expect(model.values['unassigned_legacy'], {'keep': true});
      model.update('trip_count', 'not a number');
      expect(model.validate({}, 'client'), isFalse);
      expect(model.errors, contains('trip_count'));
    },
  );
  test(
    'new required fields do not block old bookings until edited; hidden field values are preserved',
    () {
      final model = controller({'office_note': 'Keep'});
      addTearDown(model.dispose);
      expect(model.validate({}, 'client'), isTrue);
      model.update('booking_type', '');
      expect(model.validate({}, 'client'), isFalse);
      model.update('booking_type', 'Regular');
      model.update('office_note', 'Do not save hidden edit');
      expect(model.changes({}, 'client'), {'booking_type': 'Regular'});
    },
  );
  test(
    'save deltas preserve untouched nested history and explicitly clear edited values',
    () {
      final before = <String, dynamic>{
        'booking_type': 'Regular',
        'office_note': 'Old note',
        'custom_photo': {'download_url': 'old'},
        'legacy': {
          'nested': ['keep', 1],
        },
        'services': ['One'],
      };
      final model = controller(before);
      addTearDown(model.dispose);
      model.update('booking_type', 'Husting');
      model.update('office_note', '');
      model.update('custom_photo', null);
      final after = {...before, ...model.changes({}, 'client')};
      expect(
        bookingEditFieldChanges(
          before: before,
          after: after,
          clearableKeys: model.touched,
        ),
        {'booking_type': 'Husting', 'office_note': null, 'custom_photo': null},
      );
      expect(
        bookingEditFieldChanges(
          before: before,
          after: {
            ...before,
            'legacy': {
              'nested': ['keep', 1],
            },
            'services': ['One'],
          },
        ),
        isEmpty,
      );
    },
  );
  testWidgets(
    'additional booking editor shows saved dropdown and conditional custom inputs',
    (tester) async {
      final model = controller({
        'booking_type': 'Regular',
        'office_note': 'Saved office note',
        'trip_count': 2,
      });
      addTearDown(model.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 600,
                child: BookingAdditionalFieldsEditor(
                  controller: model,
                  baseAnswers: const {},
                  clientId: 'client',
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Regular'), findsOneWidget);
      expect(find.text('Saved office note'), findsNothing);
      final dropdown = tester.widget<AdminDropdownFormField<String>>(
        find.byType(AdminDropdownFormField<String>),
      );
      dropdown.onChanged!('Husting');
      await tester.pump();
      expect(find.text('Saved office note'), findsOneWidget);
      final noteInput = find.widgetWithText(TextField, 'Saved office note');
      await tester.ensureVisible(noteInput);
      await tester.enterText(noteInput, 'Updated office note');
      await tester.pump();
      expect(model.changes({}, 'client')['office_note'], 'Updated office note');
      expect(model.changes({}, 'client')['booking_type'], 'Husting');
      await tester.pumpWidget(const SizedBox());
    },
  );
}
