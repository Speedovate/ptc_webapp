import 'dart:async';
import 'dart:convert';
import 'sync_error_log_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Conflict metadata captured in the same transaction that rejected the write.
class OfflineSyncConflict extends StateError {
  OfflineSyncConflict(super.message, this.context);
  final Map<String, dynamic> context;
}

/// One latest failure per action, with sanitized queue/conflict context.
Future<String> offlineErrorDiagnostics({
  required Object error,
  required StackTrace stack,
  required String source,
  required String operation,
  required String entryId,
  required String target,
  required int attempt,
  String? owner,
  String? actionAt,
  Map<String, dynamic> context = const {},
}) async {
  final failedAt = DateTime.now().toUtc().toIso8601String();
  final diagnosticContext = {
    ...context,
    if (error is OfflineSyncConflict) ...error.context,
  };
  final diagnostics = [
    'Source: $source',
    'Operation: $operation',
    'Queue entry: $entryId',
    'Target: $target',
    'Attempt: $attempt',
    'Failed at (UTC): $failedAt',
    'Platform: ${kIsWeb ? 'web' : defaultTargetPlatform.name}',
    'Build mode: ${kReleaseMode
        ? 'release'
        : kProfileMode
        ? 'profile'
        : 'debug'}',
    'Error type: ${error.runtimeType}',
    'Context:\n${jsonEncode(SyncErrorLogService.sanitizeDetails(diagnosticContext))}',
    if (error is FirebaseException) ...[
      'Firebase plugin: ${error.plugin}',
      'Firebase code: ${error.code}',
    ],
    'Raw error:\n$error',
    'Stack trace:\n${stack.toString().isEmpty ? 'Not provided by runtime.' : stack}',
  ].join('\n');
  unawaited(
    SyncErrorLogService.instance.capture(
      source: source,
      operation: operation,
      entryId: entryId,
      target: target,
      error: error.toString(),
      stack: stack.toString(),
      attempt: attempt,
      owner: owner,
      actionAt: actionAt,
      failedAt: failedAt,
      details: {
        ...diagnosticContext,
        'error_type': error.runtimeType.toString(),
        if (error is FirebaseException) 'firebase_code': error.code,
        if (error is FirebaseException) 'firebase_plugin': error.plugin,
      },
    ),
  );
  return diagnostics;
}
