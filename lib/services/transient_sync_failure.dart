import 'dart:async';

import 'package:firebase_core/firebase_core.dart';

/// Preserve SDK codes before user-facing normalization removes their prefix.
/// Text checks also recover queues persisted by releases without this policy.
bool isTransientSyncFailure(Object error) {
  if (error is TimeoutException) return true;
  if (error is FirebaseException) {
    return const {
      'unavailable',
      'deadline-exceeded',
      'network-request-failed',
    }.contains(error.code);
  }
  final message = error.toString().trim().toLowerCase();
  if (message.contains('sync conflict') ||
      message.contains('permission-denied') ||
      message.contains('permission denied') ||
      message.contains('unauthenticated')) {
    return false;
  }
  return message.contains('client is offline') ||
      message.contains('[cloud_firestore/unavailable]') ||
      message.contains('[cloud_firestore/deadline-exceeded]') ||
      message == 'connection failed.';
}
