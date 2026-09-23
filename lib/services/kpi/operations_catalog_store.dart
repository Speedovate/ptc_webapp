import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:webapp/models/dispatcher_access_config.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/requests/firestore_cache_store.dart';
import 'package:webapp/services/kpi/location_option_registry.dart';
import 'package:webapp/services/kpi/operations_catalog.dart';
import 'package:webapp/services/network_status_events.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/role_access_service.dart';

class OperationsCatalogStore {
  OperationsCatalogStore({
    FirebaseFirestore? firestore,
    OfflineMutationQueueService? queue,
    FirestoreCacheStore? cache,
    Future<String?> Function()? owner,
    bool Function()? editPermission,
    bool Function()? online,
  }) : _providedFirestore = firestore,
       _queue = queue ?? OfflineMutationQueueService.instance,
       _cache = cache ?? FirestoreCacheStore.instance,
       _ownerProvider = owner,
       _editPermission = editPermission,
       _online = online ?? currentNetworkStatus;
  final FirebaseFirestore? _providedFirestore;
  FirebaseFirestore get _firestore =>
      _providedFirestore ?? FirebaseFirestore.instance;
  final Future<String?> Function()? _ownerProvider;
  final bool Function()? _editPermission;
  final bool Function() _online;
  Future<String?> _accountId() async => _ownerProvider != null
      ? await _ownerProvider()
      : (await AuthRequest.instance.getCurrentUser())?.id;

  static final instance = OperationsCatalogStore();
  static const collection = 'operations_catalog';
  OperationsCatalog current = OperationsCatalog({});
  Future<OperationsCatalog>? _loading;
  String? _owner;
  DateTime? _loadedAt;
  bool get canRead => RoleAccessService.instance.canAccess(
    DispatcherAccessCapability.operationsCatalogRead,
  );
  bool get canEdit =>
      _editPermission?.call() ??
      RoleAccessService.instance.canAccess(
        DispatcherAccessCapability.operationsCatalogUpdate,
      );
  final OfflineMutationQueueService _queue;
  final FirestoreCacheStore _cache;

  Future<void> restore() async {
    final owner = await _accountId();
    if (owner == null) {
      _owner = null;
      _loadedAt = null;
      _apply({});
      return;
    }
    if (owner == _owner && _loadedAt != null) {
      return;
    }
    if (owner != _owner) {
      _loadedAt = null;
      _apply({});
      _owner = owner;
    }
    final cached = (await _cache.readDocumentMaps(
      'operations_catalog:$owner',
    ))?.firstOrNull;
    if ((await _accountId()) != owner) {
      return;
    }
    if (cached != null) {
      _apply(cached);
    }
  }

  Future<OperationsCatalog?> readCached() async {
    final owner = await _accountId();
    if (owner == null) return null;
    final cached = await _cache.readDocumentMaps('operations_catalog:$owner');
    if (cached == null) return null;
    return _load(true, localOnly: true);
  }

  Future<OperationsCatalog> load({bool force = false}) {
    return _loading ??= _load(force).whenComplete(() => _loading = null);
  }

  Future<OperationsCatalog> _load(bool force, {bool localOnly = false}) async {
    final owner = await _accountId();
    if (owner == null) {
      _owner = null;
      _loadedAt = null;
      _apply({});
      return current;
    }
    if (!force &&
        current.document['local_sync_status'] == null &&
        owner == _owner &&
        _loadedAt != null &&
        DateTime.now().difference(_loadedAt!) < const Duration(seconds: 30)) {
      return current;
    }
    if (owner != _owner) {
      _loadedAt = null;
      _apply({});
      _owner = owner;
    }
    final key = 'operations_catalog:$owner';
    var document =
        (await _cache.readDocumentMaps(key))?.firstOrNull ??
        <String, dynamic>{};
    _apply(document); // cached choices are visible before network finishes
    if (!localOnly && _online()) {
      try {
        final collectionRef = _firestore.collection(collection);
        final responses = await Future.wait([
          collectionRef
              .doc('settings')
              .get(const GetOptions(source: Source.server)),
          collectionRef
              .where(FieldPath.documentId, isGreaterThanOrEqualTo: 'matrix_')
              .where(FieldPath.documentId, isLessThan: 'matrix`')
              .get(const GetOptions(source: Source.server)),
        ]).timeout(const Duration(seconds: 5));
        final snapshot = responses[0] as DocumentSnapshot<Map<String, dynamic>>;
        final versions = responses[1] as QuerySnapshot<Map<String, dynamic>>;
        final settingsDocument = snapshot.data() ?? <String, dynamic>{};
        final ids = (settingsDocument['matrix_version_ids'] as List? ?? [])
            .map((id) => id.toString())
            .toSet();
        final loadedVersions = {
          for (final v in versions.docs.map((v) => v.data()))
            v['id'].toString(): v,
        };
        // The two initial reads may straddle a publish transaction. Fetch any
        // newly referenced immutable snapshots once before exposing the catalog.
        final missing = ids.difference(loadedVersions.keys.toSet());
        if (missing.isNotEmpty) {
          final recovered = await Future.wait(
            missing.map(
              (id) => collectionRef
                  .doc('matrix_$id')
                  .get(const GetOptions(source: Source.server)),
            ),
          ).timeout(const Duration(seconds: 5));
          for (final v in recovered) {
            if (!v.exists) {
              throw StateError('Trip matrix version is unavailable.');
            }
            loadedVersions[v.data()!['id'].toString()] = v.data()!;
          }
        }
        document = {
          ...settingsDocument,
          'matrix_versions': [
            ...(settingsDocument['matrix_versions'] as List? ?? []),
            ...loadedVersions.entries
                .where((e) => ids.contains(e.key))
                .map((e) => e.value),
          ],
        };
        await _cache.writeDocumentMaps(key, [document]);
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied' || e.code == 'unauthenticated') {
          rethrow;
        }
      } catch (_) {
        /* retain last known choices */
      }
    }
    final pending = await _queue.readQueuedCollectionDocuments(
      collectionKey: collection,
    );
    if (pending.isNotEmpty) {
      final versions = <String, dynamic>{
        for (final v
            in (document['matrix_versions'] as List? ?? []).whereType<Map>())
          v['id'].toString(): v,
        for (final v
            in (pending.last['matrix_versions'] as List? ?? [])
                .whereType<Map>())
          v['id'].toString(): v,
      };
      document = {...pending.last, 'matrix_versions': versions.values.toList()};
    }
    if ((await _accountId()) != owner) {
      _owner = null;
      _loadedAt = null;
      _apply({});
      return current;
    }
    _apply(document);
    if (!localOnly) _loadedAt = DateTime.now();
    return current;
  }

  void _apply(Map<String, dynamic> document) {
    current = OperationsCatalog(document);
    LocationOptionRegistry.apply(
      current.options,
      current.retired,
      labels: current.labelsFor(
        DateTime.now().toUtc().add(const Duration(hours: 8)),
      ),
    );
  }

  Future<void> save(
    Map<String, dynamic> next,
    Map<String, dynamic> previous,
  ) async {
    final owner = await _accountId();
    if (owner == null || !canEdit) {
      throw StateError('You do not have access to edit operations settings.');
    }
    final data =
        {
            ...next,
            'id': 'settings',
            'updated_by': owner,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }
          ..remove('local_sync_status')
          ..remove('queued_entry_id')
          ..remove('queued_created_at');
    final existingPending = await _queue.readQueuedCollectionDocuments(
      collectionKey: collection,
    );
    final knownIds = (previous['matrix_version_ids'] as List? ?? [])
        .map((v) => v.toString())
        .toSet();
    final allVersions = (next['matrix_versions'] as List? ?? [])
        .whereType<Map>()
        .toList();
    final toPublish = <String, Map>{
      for (final entry in existingPending)
        for (final v
            in (entry['matrix_versions'] as List? ?? []).whereType<Map>())
          v['id'].toString(): v,
      for (final v in allVersions.where(
        (v) => !knownIds.contains(v['id'].toString()),
      ))
        v['id'].toString(): v,
    };
    for (final version in toPublish.values) {
      if (utf8.encode(jsonEncode(version)).length > 800000) {
        throw StateError(
          'This matrix is too large. Reduce the number of routes before saving.',
        );
      }
    }
    final payload = {
      ...data,
      'matrix_versions': toPublish.values.toList(),
      'matrix_version_ids': allVersions.map((v) => v['id']).toList(),
    };
    final savedOnline = await _queue.saveCollectionDocumentOnlineFirst(
      collectionKey: collection,
      documentId: 'settings',
      document: payload,
      baseUpdatedAt: previous['updated_at']?.toString(),
    );
    final cached = {
      ...data,
      'matrix_version_ids': payload['matrix_version_ids'],
    };
    await _cache.writeDocumentMaps('operations_catalog:$owner', [cached]);
    _apply({...cached, if (!savedOnline) 'local_sync_status': 'queued'});
    _loadedAt = null;
  }
}
