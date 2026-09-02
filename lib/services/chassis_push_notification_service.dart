import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/utils/functions.dart';

/// Registers this browser for chassis-check notifications when permission exists.
class ChassisPushNotificationService {
  ChassisPushNotificationService._();

  static final ChassisPushNotificationService instance =
      ChassisPushNotificationService._();

  static const _eligibleRoles = {'admin', 'manager', 'dispatcher'};
  static const _vapidKey = String.fromEnvironment(
    'FIREBASE_WEB_PUSH_VAPID_KEY',
    defaultValue:
        'BHzxTtoWODv0lZf9ZWQrKWsPkb2W2YfbYkcNx8GEjrDXO5EjFgZpabS5tq5IBeoEtGs3kD-EI88KU6O8CDi_hTw',
  );

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription<String>? _tokenRefreshSubscription;
  String? _userId;
  String? _role;
  String? _token;

  Future<void> startForUser(UserModel? user) async {
    if (!kIsWeb) return;

    final userId = normalizeId(user?.id);
    final role = (user?.role ?? '').trim().toLowerCase();
    if (userId == null || !_eligibleRoles.contains(role)) {
      await stop();
      return;
    }
    if (_vapidKey.isEmpty) return;

    _userId = userId;
    _role = role;
    try {
      final permission = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (permission.authorizationStatus != AuthorizationStatus.authorized &&
          permission.authorizationStatus != AuthorizationStatus.provisional) {
        return;
      }

      final token = await _messaging.getToken(vapidKey: _vapidKey);
      if (token == null || token.isEmpty) return;
      await _saveToken(token);
      _tokenRefreshSubscription ??= _messaging.onTokenRefresh.listen((token) {
        unawaited(_saveToken(token));
      });
    } catch (_) {
      // Permission can be declined or blocked by the browser without affecting the app.
    }
  }

  Future<void> stop() async {
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;

    final userId = _userId;
    final token = _token;
    _userId = null;
    _role = null;
    _token = null;
    if (userId == null || token == null) return;

    try {
      await _firestore
          .collection('manage_notifications')
          .doc(_documentId(userId, token))
          .delete();
    } catch (_) {
      // A stale token document is harmless and will be overwritten on the next login.
    }
  }

  Future<void> _saveToken(String token) async {
    final userId = _userId;
    final role = _role;
    if (userId == null || role == null || token.isEmpty) return;
    _token = token;
    await _firestore
        .collection('manage_notifications')
        .doc(_documentId(userId, token))
        .set({
          'user_id': userId,
          'role': role,
          'token': token,
          'platform': 'web',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
  }

  String _documentId(String userId, String token) {
    final encodedToken = base64Url
        .encode(utf8.encode(token))
        .replaceAll('=', '');
    return 'web_${userId}_$encodedToken';
  }
}
