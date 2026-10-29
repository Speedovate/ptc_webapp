import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/status_form_engine.dart';
import 'package:webapp/widgets/shared/booking_record_card.dart';

void main() {
  for (final status in ['delivered', 'completed']) {
    test('$status edits override Pending fields after serialization', () {
      final original = <String, dynamic>{
        'pending': {
          'submitted_at': '2026-10-27T00:00:00Z',
          'fields': {
            'amount': '5000',
            'waybill_number': 'WB-OLD',
            'delivery_form_number': 'DF-OLD',
            'van_number': 'VAN-OLD',
            'van_size': 'small',
            'pick_up_date': '10/27/2026',
            'pick_up_time': '08:00',
            'drop_off_date': '10/28/2026',
            'drop_off_time': '10:00',
            'representative_name': 'Old contact',
            'representative_phone': '09171234567',
            'origin': 'Roxas',
            'destination': 'Taytay',
            'unmodified_field': 'keep this',
          },
        },
      };
      final edits = <String, dynamic>{
        'amount': '6000',
        'waybill_number': 'WB-NEW',
        'delivery_form_number': 'DF-NEW',
        'van_number': 'VAN-NEW',
        'van_size': 'large',
        'pick_up_date': '10/28/2026',
        'pick_up_time': '09:00',
        'drop_off_date': '10/29/2026',
        'drop_off_time': '11:00',
        'representative_name': 'New contact',
        'representative_phone': '09179876543',
        'origin': 'El Nido',
        'destination': 'Aborlan',
      };
      final updated = StatusFormEngine.appendStatusOutputSection(
        original,
        displayStatusKey: status,
        statusFormReference: null,
        submittedRole: 'dispatcher',
        submittedRoles: ['dispatcher'],
        submittedBy: '1',
        fields: edits,
        submittedAt: DateTime.utc(2026, 10, 29),
      );
      // Firestore map key order must not determine the current values.
      final persisted = jsonDecode(jsonEncode({
        for (final entry in updated.entries.toList().reversed)
          entry.key: entry.value,
      })) as Map<String, dynamic>;
      for (final edit in edits.entries) {
        expect(
          BookingRecordCard.outputFieldValue(persisted, edit.key),
          edit.value,
          reason: '${edit.key} should use the latest $status edit',
        );
      }
      expect(
        BookingRecordCard.outputFieldValue(persisted, 'unmodified_field'),
        'keep this',
      );
      expect(original['pending']['fields']['waybill_number'], 'WB-OLD');
    });
  }
}
