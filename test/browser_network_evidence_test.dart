@TestOn('browser')
library;

// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/sync_error_environment_web.dart';

JSObject _jsObject(Map<String, Object?> data) => data.jsify() as JSObject;

void main() {
  for (final type in ['wifi', 'cellular']) {
    test('records browser-reported $type separately from effective speed', () {
      final evidence = browserNetworkEvidence(
        _jsObject({
          'onLine': true,
          'connection': {
            'type': type,
            'effectiveType': '4g',
            'rtt': 150,
            'downlink': 2.5,
            'saveData': true,
          },
        }),
      );
      expect(evidence['connection_type'], type);
      expect(evidence['effective_type'], '4g');
      expect(evidence['estimated_rtt_ms'], 150);
      expect(evidence['estimated_downlink_mbps'], 2.5);
      expect(evidence['save_data'], true);
      expect(evidence['carrier'], 'unknown');
      expect(evidence['server_reachability_verified'], false);
      expect(() => jsonEncode(evidence), returnsNormally);
    });
  }

  test('4g without physical type does not fabricate cellular', () {
    final evidence = browserNetworkEvidence(
      _jsObject({
        'onLine': true,
        'connection': {'effectiveType': '4g'},
      }),
    );
    expect(evidence['connection_type'], 'unknown');
    expect(evidence['connection_type_available'], false);
    expect(evidence['effective_type_is_radio_generation'], false);
  });

  test('unsupported browser still produces serializable explicit unknowns', () {
    final evidence = browserNetworkEvidence(_jsObject({'onLine': false}));
    expect(evidence['network_information_supported'], false);
    expect(evidence['browser_online'], false);
    expect(evidence['connection_type'], 'unknown');
    expect(() => jsonEncode(evidence), returnsNormally);
  });

  test('invalid numeric estimates cannot break persisted diagnostic JSON', () {
    final evidence = browserNetworkEvidence(
      _jsObject({
        'connection': {'rtt': double.nan, 'downlink': double.infinity},
      }),
    );
    expect(evidence['estimated_rtt_ms'], isNull);
    expect(evidence['estimated_downlink_mbps'], isNull);
    expect(() => jsonEncode(evidence), returnsNormally);
  });
}
