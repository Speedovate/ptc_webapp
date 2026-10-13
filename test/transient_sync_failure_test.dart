import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/transient_sync_failure.dart';

void main() {
  test('connectivity codes survive missing or misleading messages', () {
    for (final code in [
      'unavailable',
      'deadline-exceeded',
      'network-request-failed',
    ]) {
      expect(
        isTransientSyncFailure(
          FirebaseException(plugin: 'cloud_firestore', code: code),
        ),
        isTrue,
      );
    }
    expect(isTransientSyncFailure(TimeoutException('stalled')), isTrue);
  });
  test('persisted offline failures are recoverable', () {
    for (final error in [
      'Failed to get document because the client is offline.',
      '[cloud_firestore/unavailable] Failed to get document because the client is offline.',
      '[cloud_firestore/deadline-exceeded] Request expired.',
      'Connection failed.',
    ]) {
      expect(isTransientSyncFailure(error), isTrue);
    }
  });
  test('permission, identity and payload failures must not auto-unblock', () {
    for (final code in [
      'permission-denied',
      'unauthenticated',
      'invalid-argument',
      'not-found',
    ]) {
      expect(
        isTransientSyncFailure(
          FirebaseException(
            plugin: 'cloud_firestore',
            code: code,
            message: 'Failed to get document because the client is offline.',
          ),
        ),
        isFalse,
      );
    }
    for (final message in [
      'Sync conflict: booking changed remotely. Client is offline.',
      '[cloud_firestore/permission-denied] Client is offline.',
      'Document exceeds the maximum allowed size',
      'Sync conflict: booking reservation identity is inconsistent.',
    ]) {
      expect(isTransientSyncFailure(message), isFalse);
    }
  });
}
