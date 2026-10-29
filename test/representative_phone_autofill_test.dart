import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/services/client_representative_suggestions.dart';
import 'package:webapp/widgets/status_form/status_form_runtime_fields.dart';

Booking contact(String client, String name, String phone) => Booking(
  client: UserModel(id: client),
  statusOutputs: {
    'pending': {
      'fields': {'representative_name': name, 'representative_phone': phone},
    },
  },
);
void main() {
  test(
    'phone lookup stays within the selected main client and normalizes numbers',
    () {
      final bookings = [
        contact('a', 'Alice', '+639171234567'),
        contact('b', 'Alice', '09179876543'),
      ];
      expect(clientRepresentativePhones(bookings, 'a'), {
        'alice': '+639171234567',
      });
      expect(clientRepresentativePhones(bookings, 'b'), {
        'alice': '+639179876543',
      });
      expect(clientRepresentativePhones(bookings, null), isEmpty);
    },
  );
  test('conflicting numbers and invalid numbers are not guessed', () {
    expect(
      clientRepresentativePhones([
        contact('a', 'Alice', '09171234567'),
        contact('a', 'ALICE', '09179876543'),
        contact('a', 'Bob', 'invalid'),
      ], 'a'),
      isEmpty,
    );
    final legacy = Booking(
      client: const UserModel(id: 'a'),
      statusOutputs: {
        'pending': {
          'fields': {
            'representative_name': 'Alice',
            'representative_phone': '09171234567',
          },
        },
        'delivered': {
          'fields': {
            'representative_name': 'Alice',
            'representative_phone': '09179876543',
          },
        },
      },
    );
    expect(clientRepresentativePhones([legacy], 'a'), isEmpty);
  });
  test(
    'latest dated phone wins across booking history regardless of order',
    () {
      Booking savedContact(String phone, String savedAt) =>
          contact('a', 'Dnb Enterprise', phone).copyWith(
            statusOutputs: {
              'book': {
                'submitted_at': savedAt,
                'fields': {
                  'representative_name': 'Dnb Enterprise',
                  'representative_phone': phone,
                },
              },
            },
          );
      final older = savedContact('09171234567', '2026-10-01T08:00:00Z');
      final newer = savedContact('09179876543', '2026-10-29T08:00:00Z');
      for (final history in [
        [older, newer],
        [newer, older],
      ]) {
        expect(clientRepresentativePhones(history, 'a'), {
          'dnb enterprise': '+639179876543',
        });
      }
      expect(
        clientRepresentativePhones([
          newer,
          savedContact('09171234567', '2026-10-29T08:00:00Z'),
        ], 'a'),
        isEmpty,
        reason: 'Equal-time conflicts cannot be ordered',
      );
    },
  );
  test('legacy pairs use booking dates when output timestamps are absent', () {
    final older = contact(
      'a',
      'Alice',
      '09171234567',
    ).copyWith(createdAt: DateTime.utc(2026, 10, 1));
    final newer = contact(
      'a',
      'Alice',
      '09179876543',
    ).copyWith(createdAt: DateTime.utc(2026, 10, 29));
    expect(clientRepresentativePhones([newer, older], 'a'), {
      'alice': '+639179876543',
    });
  });
  test(
    'chronological phone-only edits update the right representative; renamed people do not inherit phones',
    () {
      final booking = Booking(
        client: const UserModel(id: 'a'),
        statusOutputs: {
          // Deliberately out of insertion order, as Firestore maps are unordered.
          'third': {
            'submitted_at': '2026-10-29T09:03:00Z',
            'fields': {'representative_name': 'Bob'},
          },
          'second': {
            'submitted_at': '2026-10-29T09:02:00Z',
            'fields': {'representative_phone': '09179876543'},
          },
          'first': {
            'submitted_at': '2026-10-29T09:01:00Z',
            'fields': {
              'representative_name': 'Alice',
              'representative_phone': '09171234567',
            },
          },
        },
      );
      expect(clientRepresentativePhones([booking], 'a'), {
        'alice': '+639179876543',
      });
    },
  );
  test(
    'saved representative phones replace manual and previously autofilled values',
    () {
      final state = RepresentativePhoneAutofill();
      expect(
        state.valueForSelection(
          suggestedPhone: '09171234567',
          currentPhone: '',
        ),
        '09171234567',
      );
      expect(
        state.valueForSelection(
          suggestedPhone: '09179876543',
          currentPhone: '09171234567',
        ),
        '09179876543',
      );
      state.markManualEdit();
      expect(
        state.valueForSelection(
          suggestedPhone: '09171234567',
          currentPhone: '09175555555',
        ),
        '09171234567',
      );
      state.markManualEdit();
      expect(
        state.valueForSelection(
          suggestedPhone: null,
          currentPhone: '09175555555',
        ),
        isNull,
        reason: 'No saved number is available to replace manual input',
      );
      state.reset();
      expect(
        state.valueForSelection(
          suggestedPhone: null,
          currentPhone: '09179876543',
        ),
        '',
        reason: 'An unknown contact must not retain another contact’s phone',
      );
    },
  );
  testWidgets(
    'only explicit representative selection fires autofill; normal typing remains free text',
    (tester) async {
      String? selected;
      String? name;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatusFormRuntimeFieldInput(
              field: const StatusField(
                id: 'rep',
                key: 'representative_name',
                type: 'text',
                optionSourceKey: statusFieldOptionSourceClientRepresentatives,
                options: ['Alice'],
              ),
              initialValue: null,
              onChanged: (value) => name = value as String,
              onSuggestionSelected: (value) => selected = value,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Ali');
      await tester.pump();
      expect(name, 'Ali');
      expect(selected, isNull);
      await tester.tap(find.text('Alice'));
      await tester.pump();
      expect(name, 'Alice');
      expect(selected, 'Alice');
    },
  );
}
