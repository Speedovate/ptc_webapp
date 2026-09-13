import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/status_field.dart';

void main() {
  test('legacy fields keep a null text case', () {
    final field = StatusField.fromMap(const {
      'id': 1,
      'key': 'van_number',
      'type': 'text',
    });

    expect(field.textCase, isNull);
    expect(field.toMap()['text_case'], isNull);
  });

  test('configured text case survives Firestore serialization', () {
    final field = StatusField.fromMap(const {
      'id': 2,
      'key': 'van_number',
      'type': 'text',
      'text_case': 'uppercase',
    });

    expect(field.textCase, statusFieldTextCaseUppercase);
    expect(field.toMap()['text_case'], statusFieldTextCaseUppercase);
  });

  test('all supported text cases are preserved', () {
    for (final textCase in statusFieldTextCaseOptions) {
      final field = StatusField.fromMap({
        'id': textCase,
        'key': 'sample',
        'type': 'text',
        'text_case': textCase,
      });

      expect(field.textCase, textCase);
    }
  });

  test('unknown legacy text case falls back to default behavior', () {
    final field = StatusField.fromMap(const {
      'id': 3,
      'key': 'representative_name',
      'type': 'text',
      'text_case': 'mixed_case',
    });

    expect(field.textCase, isNull);
  });
}
