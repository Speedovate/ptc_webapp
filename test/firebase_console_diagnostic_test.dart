import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/firebase_console_diagnostic.dart';
import 'package:webapp/services/sync_error_log_service.dart';
import 'sync_error_log_service_test.dart' show MemoryLogs;

void main() {
  test('pinpoints lookup stage without claiming a proven carrier cause', () {
    final diagnostic = firebaseConsoleDiagnostic({
      'error': 'Server booking identity check timed out',
      'network_at_capture': {'connection_type': 'cellular'},
      'network_observation_scope': 'recovery_capture_not_original_failure',
      'details': {
        'identity_lookup': {
          'gate_reason': 'request_timeout',
          'stage': 'reservation_read',
          'lookup_elapsed_ms': 30000,
          'network_at_lookup_start': {'connection_type': 'wifi'},
          'network_at_lookup_timeout': {'connection_type': 'cellular'},
        },
      },
    });
    final cause = diagnostic['root_cause_assessment'] as Map;
    expect(cause['failure_stage'], 'reservation_read');
    expect(
      cause['confirmed_failure'],
      'server_identity_lookup_deadline_exceeded',
    );
    expect(cause['carrier_cause_confirmed'], false);
    expect(
      diagnostic['evidence']['network_observation_scope'],
      'recovery_capture_not_original_failure',
    );
    expect(
      diagnostic['evidence']['identity_lookup']['network_at_lookup_start']['connection_type'],
      'wifi',
    );
  });
  test('offline SDK evidence does not claim a Console configuration failure', () {
    final diagnostic = firebaseConsoleDiagnostic({
      'error':
          '[cloud_firestore/unavailable] Failed to get document because the client is offline.',
      'online_at_failure': true,
      'target': 'bookings/offline_1',
      'details': {
        'recent_network_transitions': [
          {'to_online': false},
        ],
      },
    });
    expect(diagnostic['console_action'], 'not_indicated');
    expect(diagnostic['evidence']['firebase_code'], 'unavailable');
    expect(diagnostic['evidence']['code_source'], 'error_text');
    expect(diagnostic['evidence']['console_state_verified'], false);
    expect(
      diagnostic['evidence']['browser_online_is_server_reachability_proof'],
      false,
    );
  });

  test('local dependency takes precedence over historical offline evidence', () {
    final diagnostic = firebaseConsoleDiagnostic({
      'error':
          'This photo is still waiting: the booking changes are still queued.',
      'stack_trace':
          'Firebase plugin: cloud_firestore\nFirebase code: unavailable\nRaw error:\n[cloud_firestore/unavailable] offline',
    });
    expect(diagnostic['category'], 'local_sync_dependency_or_conflict');
    expect(diagnostic['evidence']['code_source'], 'persisted_stack_trace');
    expect(diagnostic['console_action'], 'not_indicated');
  });

  test(
    'access and quota codes request verification rather than claiming a cause',
    () {
      for (final code in [
        'permission-denied',
        'unauthenticated',
        'resource-exhausted',
        'quota-exceeded',
      ]) {
        final diagnostic = firebaseConsoleDiagnostic({
          'error': 'Rejected request',
          'details': {
            'firebase_code': code,
            'firebase_plugin': 'cloud_firestore',
          },
        });
        expect(diagnostic['console_action'], 'review_required');
        expect(diagnostic['console_checks'], isNotEmpty);
        expect(diagnostic['evidence']['console_state_verified'], false);
      }
    },
  );

  test('only explicit missing-index messages recommend index review', () {
    expect(
      firebaseConsoleDiagnostic({
        'error':
            '[cloud_firestore/failed-precondition] The query requires an index.',
      })['category'],
      'firestore_index',
    );
    expect(
      firebaseConsoleDiagnostic({
        'error': '[cloud_firestore/failed-precondition] Transaction rejected.',
      })['console_action'],
      'unknown',
    );
    expect(
      firebaseConsoleDiagnostic({
        'error': 'Service is temporarily unavailable. Please try again.',
      })['console_action'],
      'unknown',
    );
  });

  test(
    'uploaded and copied reports retain sanitized evidence despite large queue details',
    () async {
      final disk = MemoryLogs();
      final writes = <Map<String, dynamic>>[];
      var online = false;
      final service = SyncErrorLogService(
        backend: disk,
        online: () => online,
        metadata: (_) async => {'firebase_project_id': 'test-project'},
        writer: (_, data) async => writes.add(data),
      );
      await service.start();
      await service.capture(
        source: 'offline_mutation_queue_service.dart',
        operation: 'bookingCreate',
        entryId: 'entry',
        target: 'bookings/offline_1',
        owner: '8',
        error:
            '[cloud_firestore/permission-denied] Rejected token=private-secret',
        stack: '',
        attempt: 1,
        details: {'oversized_context': 'x' * 40000},
      );
      online = true;
      await service.flush();
      expect(writes, hasLength(1));
      final diagnostic = writes.single['firebase_console_diagnostic'];
      expect(diagnostic['console_action'], 'review_required');
      expect(diagnostic['evidence']['project_id'], 'test-project');
      expect(
        jsonDecode(writes.single['copy_report'])['firebase_console_diagnostic'],
        diagnostic,
      );
      expect(jsonEncode(writes.single), isNot(contains('private-secret')));
    },
  );
}
