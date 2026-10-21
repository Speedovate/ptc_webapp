/// Evidence-based guidance only: client errors do not expose deployed rules,
/// quota usage, billing status, or App Check enforcement.
Map<String, dynamic> firebaseConsoleDiagnostic(Map<String, dynamic> report) {
  final details = report['details'] is Map
      ? report['details'] as Map
      : const {};
  final error = '${report['error'] ?? ''}';
  final stack = '${report['stack_trace'] ?? ''}';
  final text = error.toLowerCase();
  final identityLookup = details['identity_lookup'];
  final lookupTimedOut =
      identityLookup is Map &&
      identityLookup['gate_reason'] == 'request_timeout';
  final missingIdentity =
      identityLookup is Map &&
      identityLookup['stage'] == 'completed' &&
      const {
        'no_server_identity',
        'ambiguous_server_identity',
        'reserved_booking_missing',
      }.contains(identityLookup['result']);
  final local =
      text.contains('sync conflict') ||
      text.contains('booking identity is temporarily unavailable') ||
      text.contains('photo is still waiting') ||
      text.contains('original booking submission is missing') ||
      text.contains('queued booking photo made no progress') ||
      missingIdentity;
  final bracket = RegExp(
    r'\[(cloud_firestore|firebase_storage|firebase_auth|firebase_app_check)/([a-z-]+)\]',
  );
  final direct = bracket.firstMatch(error);
  final historical = bracket.firstMatch(stack);
  final codeLine = RegExp(r'Firebase code: ([a-z-]+)').firstMatch(stack);
  final pluginLine = RegExp(r'Firebase plugin: ([a-z_]+)').firstMatch(stack);
  final structuredCode = details['firebase_code']?.toString();
  final code = structuredCode ?? direct?[2] ?? historical?[2] ?? codeLine?[1];
  final plugin =
      details['firebase_plugin']?.toString() ??
      direct?[1] ??
      historical?[1] ??
      pluginLine?[1];
  final source = structuredCode != null
      ? 'structured_sdk_error'
      : direct != null
      ? 'error_text'
      : code != null
      ? 'persisted_stack_trace'
      : 'not_available';
  final evidence = <String, dynamic>{
    'firebase_code': code,
    'firebase_plugin': plugin,
    'code_source': source,
    'error_excerpt': error.length > 1600 ? error.substring(0, 1600) : error,
    'operation': report['operation'],
    'target': report['target'],
    'failed_at': report['last_failed_at'],
    'browser_online_at_failure': report['online_at_failure'],
    'browser_online_is_server_reachability_proof': false,
    'recent_network_transitions': details['recent_network_transitions'],
    'blocked': details['blocked'],
    'wait_reason':
        details['wait_reason'] ??
        (details['queue_snapshot'] is Map
            ? details['queue_snapshot']['photo_upload'] is Map
                  ? details['queue_snapshot']['photo_upload']['wait_reason']
                  : null
            : null),
    'project_id': report['firebase_project_id'],
    'app_origin': report['app_origin'],
    'console_state_verified': false,
    if (report['network_at_capture'] is Map)
      'network_at_capture': report['network_at_capture'],
    'network_observation_scope': report['network_observation_scope'],
    if (report['firestore_transport'] is Map)
      'firestore_transport': report['firestore_transport'],
    if (identityLookup is Map) 'identity_lookup': identityLookup,
  };
  String status = 'unknown';
  String category = 'insufficient_evidence';
  String reason =
      'No specific Firebase failure code was captured; Console changes cannot be determined.';
  List<String> checks = [];
  if (lookupTimedOut) {
    status = 'not_indicated';
    category = 'connection_or_service_availability';
    reason =
        'The server identity read exceeded its deadline. It did not confirm that the booking is missing. Console configuration and the mobile network cause remain unverified.';
    checks = [
      'If persistent, compare networks and review Firestore request metrics at the recorded failure time.',
    ];
  } else if (local) {
    status = 'not_indicated';
    category = 'local_sync_dependency_or_conflict';
    reason =
        'The current failure describes a booking dependency or data conflict. Any persisted SDK error is historical evidence, not proof of a current Console problem.';
  } else if (code == 'unavailable' ||
      code == 'deadline-exceeded' ||
      text.contains('failed to get document because the client is offline')) {
    status = 'not_indicated';
    category = 'connection_or_service_availability';
    reason =
        'The request could not reach or complete against the backend. This alone does not prove a rules, index, billing, or App Check configuration error.';
    checks = [
      'If persistent across devices and networks, review service availability and Firestore request metrics at the failure time.',
    ];
  } else if (code == 'failed-precondition' &&
      (text.contains('requires an index') ||
          text.contains('index is currently building'))) {
    status = 'review_required';
    category = 'firestore_index';
    reason =
        'The server message explicitly identifies a required or building index; verify that index before retrying.';
    checks = [
      'Firestore > Indexes: check the index identified in the original error. Create it only if missing, or wait for its build.',
    ];
  } else if (code == 'permission-denied' ||
      code == 'unauthorized' ||
      code == 'unauthenticated') {
    status = 'review_required';
    category = 'access_rejected';
    reason =
        'Access was rejected. The code does not identify which rule, authentication state, App Check setting, or project restriction caused it.';
    checks = [
      'Verify the failing request authentication and the deployed rules for its target.',
      'Check App Check rejected-request metrics if enforcement is enabled.',
      'Check project restrictions and quota alerts if rules and authentication are valid.',
    ];
  } else if (code == 'resource-exhausted' || code == 'quota-exceeded') {
    status = 'review_required';
    category = 'quota_or_rate_limit';
    reason =
        'The SDK reported exhausted resources or quota. Usage and quota metrics are needed to distinguish project limits from request-rate limits.';
    checks = [
      'Review Firestore or Storage usage, API quotas, and billing alerts for the failure time.',
    ];
  } else if (code != null) {
    reason =
        'A Firebase code was captured, but it does not establish a specific Console change. Review the raw error and request context.';
  }
  return {
    'schema_version': 1,
    'console_action': status,
    'category': category,
    'reason': reason,
    'evidence': evidence,
    'console_checks': checks,
    'root_cause_assessment': {
      'confirmed_failure': lookupTimedOut
          ? 'server_identity_lookup_deadline_exceeded'
          : category,
      'failure_stage': identityLookup is Map ? identityLookup['stage'] : null,
      'underlying_network_cause': 'unverified',
      'carrier_cause_confirmed': false,
      'required_evidence':
          'Compare the same operation on the same device across Wi-Fi and cellular, including lookup stage, SDK error, transport settings and timestamps; correlate backend request metrics. A timeout alone cannot distinguish carrier routing, proxy buffering, DNS/TLS failure, or backend availability.',
    },
    'unverified': [
      'deployed_rules',
      'indexes',
      'quota_usage',
      'billing_status',
      'app_check_enforcement',
      'service_outage',
    ],
  };
}
