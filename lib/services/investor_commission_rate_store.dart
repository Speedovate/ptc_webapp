import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:webapp/models/dispatcher_access_config.dart';
import 'package:webapp/requests/firestore_cache_store.dart';
import 'package:webapp/services/network_status_events.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/role_access_service.dart';

/// The standing share of every trip that stays with Paltranco.
///
/// This is the one number an investor cannot check for themselves. Everything
/// else on a statement is arithmetic they can redo; the split is simply
/// asserted, so it has to be a setting they were told about rather than a
/// constant buried in a screen.
///
/// A percentage the office can set, validated once, stored once, and read by
/// every statement. The alternative - passing it in at generate time - lets two
/// statements for the same investor disagree, which is the one thing a
/// statement cannot afford.
class InvestorCommissionRateStore {
  static final instance = InvestorCommissionRateStore();

  InvestorCommissionRateStore({
    FirebaseFirestore? firestore,
    OfflineMutationQueueService? queue,
    FirestoreCacheStore? cache,
    Future<String> Function()? accountProvider,
    bool Function()? editPermission,
    bool Function()? online,
  }) : _providedFirestore = firestore,
       _queue = queue ?? OfflineMutationQueueService.instance,
       _cache = cache ?? FirestoreCacheStore.instance,
       _accountProvider = accountProvider,
       _editPermission = editPermission,
       _online = online ?? currentNetworkStatus;

  final FirebaseFirestore? _providedFirestore;
  FirebaseFirestore get _firestore =>
      _providedFirestore ?? FirebaseFirestore.instance;
  final Future<String> Function()? _accountProvider;
  final bool Function()? _editPermission;
  final bool Function() _online;
  final OfflineMutationQueueService _queue;
  final FirestoreCacheStore _cache;

  /// Shares the KPI collection, the way fleet rating rules already do. The
  /// record queries are bounded by a vehicle's document-id range, so a reserved
  /// settings id is never read as a trip.
  static const collection = 'pm_kpi_records';

  /// Reserved settings namespace, like `PmKpiStore.fleetRulesId`. This is not
  /// a vehicle document.
  static const reservedId = 'investor_commission';

  /// What the platform takes when nobody has ever set it. Production behaves
  /// identically whether or not the office touches this screen.
  static const double defaultRate = 0.10;

  bool get canRead => RoleAccessService.instance.canAccess(
    DispatcherAccessCapability.investorEarningsRead,
  );
  bool get canEdit =>
      _editPermission?.call() ??
      RoleAccessService.instance.canAccess(
        DispatcherAccessCapability.investorCommissionRateUpdate,
      );

  static String _prefix(String reservedId) =>
      '${base64Url.encode(utf8.encode(reservedId)).replaceAll('=', '')}_';

  String _documentId() => '${_prefix(reservedId)}settings';

  String _cacheKey(String account) => 'investor:$account:commission';

  /// Reads a stored rate, falling back to the default.
  ///
  /// Anything unparseable, out of range, or absent resolves to [defaultRate]
  /// rather than throwing: a bad number must not stop the office from reading
  /// a statement, and it must never be silently treated as 0% or 100%.
  static double rateFrom(Object? raw) {
    final value = switch (raw) {
      num n => n.toDouble(),
      String s => double.tryParse(s.trim()),
      _ => null,
    };
    if (value == null || !value.isFinite || value <= 0 || value >= 1) {
      return defaultRate;
    }
    return value;
  }

  /// The rate as a percentage, for display and entry.
  static double toPercent(double rate) => rate * 100;

  /// Rejects anything that is not a real share before it can be stored.
  ///
  /// 0% would hand every trip to the investor and 100% would take all of it;
  /// both produce a statement that is arithmetically valid and practically
  /// meaningless. Rejected outright rather than clamped, so a typo surfaces
  /// instead of becoming a silent 10%.
  static double validatePercent(double percent) {
    if (!percent.isFinite) {
      throw StateError('Enter the platform share as a number.');
    }
    final rate = percent / 100;
    if (rate <= 0 || rate >= 1) {
      throw StateError(
        'The platform share must be more than 0% and less than 100%.',
      );
    }
    return rate;
  }

  /// The current rate, cached and queued like every other setting here.
  Future<double> loadRate({bool localOnly = false}) async {
    final account = await _account();
    final documentId = _documentId();
    final cacheKey = _cacheKey(account);
    var document =
        (await _cache.readDocumentMaps(cacheKey))?.firstOrNull ??
        <String, dynamic>{};
    if (!localOnly && _online()) {
      try {
        final snapshot = await _firestore
            .collection(collection)
            .doc(documentId)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 10));
        if (snapshot.exists) {
          document = {...snapshot.data()!, 'id': documentId};
          await _cache.writeDocumentMaps(cacheKey, [document]);
        }
      } on FirebaseException catch (error) {
        if (error.code == 'permission-denied' ||
            error.code == 'unauthenticated') {
          rethrow;
        }
      } catch (_) {
        // Keep the cached rate through an interrupted connection rather than
        // falling back to the default and understating the platform's share.
      }
    }
    // An edit made offline on this device outranks anything still on the
    // server, exactly as it does for the fleet rules.
    final pending = await _queue.readQueuedCollectionDocuments(
      collectionKey: collection,
    );
    for (final item in pending.where((item) => item['id'] == documentId)) {
      document = item;
    }
    return rateFrom(document['commission_rate']);
  }

  /// Records the new rate, with who set it and when.
  ///
  /// Written through the same versioned queue as every other edit, so a change
  /// made offline is queued rather than lost, and one that raced someone else's
  /// newer save is reported as a conflict instead of overwriting it.
  Future<void> saveRate(double rate) async {
    if (!canEdit) {
      throw StateError('You do not have access to change the platform share.');
    }
    if (!rate.isFinite || rate <= 0 || rate >= 1) {
      throw StateError(
        'The platform share must be more than 0% and less than 100%.',
      );
    }
    final account = await _account();
    final documentId = _documentId();
    final cacheKey = _cacheKey(account);
    final now = DateTime.now().toUtc().toIso8601String();
    final previous =
        (await _cache.readDocumentMaps(cacheKey))?.firstOrNull ??
        <String, dynamic>{};
    final document = {
      ...previous,
      'id': documentId,
      'kind': 'settings',
      'commission_rate': rate,
      'updated_at': now,
      'updated_by': account,
    };
    await _queue.saveCollectionDocumentOnlineFirst(
      collectionKey: collection,
      documentId: documentId,
      document: document,
      baseUpdatedAt: previous['updated_at']?.toString(),
    );
    await _cache.writeDocumentMaps(cacheKey, [document]);
  }

  Future<String> _account() async {
    if (_accountProvider != null) {
      return _accountProvider();
    }
    return 'shared';
  }
}
