import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:webapp/models/dispatcher_access_config.dart';
import 'package:webapp/requests/firestore_cache_store.dart';
import 'package:webapp/services/firestore_public_document_fetcher.dart';
import 'package:webapp/services/network_status_events.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/offline_queue_coordinator_service.dart';
import 'package:webapp/utils/functions.dart';

class RoleAccessRequest {
  RoleAccessRequest({
    FirebaseFirestore? firestore,
    FirestorePublicDocumentFetcher? firestorePublicDocumentFetcher,
  }) : _providedFirestore = firestore,
       _firestorePublicDocumentFetcher =
           firestorePublicDocumentFetcher ??
           createFirestorePublicDocumentFetcher();

  static final RoleAccessRequest instance = RoleAccessRequest();
  static const dispatcherResourceKey = 'role_access_dispatcher';
  static const roleAccessResourceKey = 'role_access';
  static const Duration _startupTimeout = Duration(seconds: 6);
  static const Duration _saveTimeout = Duration(seconds: 12);
  static bool _didKickOffBackgroundQueueInitialization = false;
  static bool _didStartRealtimeCacheSync = false;
  static bool _isRefreshingFromVersionSignal = false;

  final FirebaseFirestore? _providedFirestore;
  FirebaseFirestore get _firestore =>
      _providedFirestore ?? FirebaseFirestore.instance;
  final FirestorePublicDocumentFetcher _firestorePublicDocumentFetcher;
  final OfflineMutationQueueService _offlineMutationQueueService =
      OfflineMutationQueueService.instance;
  late final FirestoreCollectionCache _cache = FirestoreCollectionCache(
    firestore: _firestore,
  );
  final StreamController<void> _roleAccessCacheUpdates =
      StreamController<void>.broadcast();

  CollectionReference<Map<String, dynamic>> get _roleAccessCollection =>
      _firestore.collection('role_access');

  void _writeDocumentsInBackground({
    required String resourceKey,
    required List<Map<String, dynamic>> documents,
  }) {
    unawaited(
      _cache
          .writeDocuments(resourceKey: resourceKey, documents: documents)
          .catchError((error, stackTrace) {}),
    );
  }

  Future<void> initialize() async {
    if (_didKickOffBackgroundQueueInitialization) {
      return;
    }
    _didKickOffBackgroundQueueInitialization = true;
    _ensureRealtimeCacheSync();
    unawaited(
      OfflineQueueCoordinatorService.instance
          .initialize()
          .then((_) {})
          .catchError((error, stackTrace) {}),
    );
  }

  void _ensureRealtimeCacheSync() {
    if (_didStartRealtimeCacheSync) {
      return;
    }
    _didStartRealtimeCacheSync = true;
    _cache.watchResourceVersion(roleAccessResourceKey).listen((version) {
      unawaited(_handleRoleAccessVersionSignal(version));
    }, onError: (_, _) {});
  }

  Stream<void> watchRoleAccessCacheUpdates() async* {
    await initialize();
    yield* _roleAccessCacheUpdates.stream;
  }

  Future<void> _handleRoleAccessVersionSignal(String? remoteVersion) async {
    final shouldRefresh = await _cache.hasRemoteVersionMismatch(
      roleAccessResourceKey,
      remoteVersion,
    );
    if (!shouldRefresh || _isRefreshingFromVersionSignal) {
      return;
    }
    _isRefreshingFromVersionSignal = true;
    try {
      await _refreshRoleAccessFromSourceOfTruth();
      _roleAccessCacheUpdates.add(null);
    } finally {
      _isRefreshingFromVersionSignal = false;
    }
  }

  Future<List<DispatcherAccessConfig>> getAllRoleAccessConfigs() async {
    await initialize();
    try {
      final documents = await _cache.getDocumentsVerifiedOnlineFirst(
        resourceKey: roleAccessResourceKey,
        fetchDocuments: () async {
          final sdkCachedDocuments = await _readRoleAccessSdkCacheOnly();
          if (sdkCachedDocuments.isNotEmpty && !currentNetworkStatus()) {
            return sdkCachedDocuments;
          }
          final snapshot = await _roleAccessCollection.get().timeout(
            _startupTimeout,
            onTimeout: () {
              throw TimeoutException('role_access fetch timeout');
            },
          );
          return snapshot.docs
              .map((doc) => {'id': doc.id, ...doc.data()})
              .toList(growable: false);
        },
      );
      return documents
          .map(DispatcherAccessConfig.fromMap)
          .toList(growable: false);
    } catch (error) {
      final documents = await _fetchCollectionDocumentsViaPublicRest(
        'role_access',
      );
      if (documents.isEmpty) {
        rethrow;
      }
      _writeDocumentsInBackground(
        resourceKey: roleAccessResourceKey,
        documents: documents,
      );
      return documents
          .map(DispatcherAccessConfig.fromMap)
          .toList(growable: false);
    }
  }

  Future<DispatcherAccessConfig> getDispatcherAccess() async {
    await initialize();
    final documents = await _cache.getDocumentsVerifiedOnlineFirst(
      resourceKey: dispatcherResourceKey,
      fetchDocuments: () async {
        final snapshot = await _roleAccessCollection.doc('dispatcher').get();
        if (!snapshot.exists) {
          return const <Map<String, dynamic>>[];
        }
        return <Map<String, dynamic>>[
          {'id': snapshot.id, ...?snapshot.data()},
        ];
      },
    );
    if (documents.isEmpty) {
      return DispatcherAccessConfig.defaults();
    }
    return DispatcherAccessConfig.fromMap(documents.first);
  }

  Future<List<Map<String, dynamic>>> _readRoleAccessSdkCacheOnly() async {
    try {
      final snapshot = await _roleAccessCollection
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(seconds: 1));
      return snapshot.docs.map(documentData).toList(growable: false);
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchCollectionDocumentsViaPublicRest(
    String collectionPath,
  ) async {
    final documents = await _firestorePublicDocumentFetcher
        .fetchCollectionDocuments(collectionPath)
        .timeout(
          _startupTimeout,
          onTimeout: () {
            throw TimeoutException('public rest $collectionPath fetch timeout');
          },
        );
    return documents;
  }

  Future<void> _refreshRoleAccessFromSourceOfTruth() async {
    final snapshot = await _roleAccessCollection.get().timeout(
      _startupTimeout,
      onTimeout: () => throw TimeoutException('role_access refresh timeout'),
    );
    final documents = snapshot.docs
        .map((doc) => {'id': doc.id, ...doc.data()})
        .toList(growable: false);
    await _cache.writeDocuments(
      resourceKey: roleAccessResourceKey,
      documents: documents,
    );
    final dispatcherDocument = documents
        .where((item) => (item['id']?.toString() ?? '') == 'dispatcher')
        .toList(growable: false);
    await _cache.writeDocuments(
      resourceKey: dispatcherResourceKey,
      documents: dispatcherDocument,
    );
  }

  Future<DispatcherAccessConfig> saveDispatcherAccess(
    DispatcherAccessConfig config,
  ) {
    return saveRoleAccess(
      config.copyWith(id: 'dispatcher', role: 'dispatcher'),
    );
  }

  Future<DispatcherAccessConfig> saveRoleAccess(
    DispatcherAccessConfig config,
  ) async {
    await initialize();
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final normalizedRole = config.role.trim().toLowerCase().replaceAll(
      '_',
      '-',
    );
    final next = config.copyWith(
      id: normalizedRole,
      role: normalizedRole,
      createdAtIso: config.createdAtIso ?? nowIso,
      updatedAtIso: nowIso,
    );
    final document = next.toMap();
    if (currentNetworkStatus()) {
      try {
        await _writeRoleAccessOnline(next.id, document);
      } catch (error) {
        await _offlineMutationQueueService.queueRoleAccessUpsert(
          roleKey: next.id,
          document: document,
          baseUpdatedAt: config.updatedAtIso,
        );
      }
    } else {
      await _offlineMutationQueueService.queueRoleAccessUpsert(
        roleKey: next.id,
        document: document,
        baseUpdatedAt: config.updatedAtIso,
      );
    }
    await _cache.writeDocuments(
      resourceKey: roleAccessResourceKey,
      documents: [
        for (final item
            in [
                ...(await _cache.readDocuments(roleAccessResourceKey) ??
                    const <Map<String, dynamic>>[]),
              ]
              ..removeWhere((item) => item['id']?.toString() == next.id)
              ..add(document))
          item,
      ],
    );
    if (next.id == 'dispatcher') {
      await _cache.writeDocuments(
        resourceKey: dispatcherResourceKey,
        documents: [document],
      );
    }
    return next;
  }

  Future<void> _writeRoleAccessOnline(
    String roleId,
    Map<String, dynamic> document,
  ) async {
    if (kIsWeb) {
      try {
        final patched = await _firestorePublicDocumentFetcher
            .patchDocument(
              'role_access/$roleId',
              fields: document,
              updateMaskFieldPaths: document.keys.toList(growable: false),
            )
            .timeout(
              const Duration(seconds: 4),
              onTimeout: () => throw TimeoutException(
                'role_access rest patch timeout for $roleId',
              ),
            );
        if (patched) {
          return;
        }
      } catch (_) {}
    }

    try {
      await _roleAccessCollection
          .doc(roleId)
          .set(document)
          .timeout(
            _saveTimeout,
            onTimeout: () => throw TimeoutException('role_access save timeout'),
          );
      return;
    } catch (error) {
      if (!kIsWeb) {
        rethrow;
      }
    }

    final patched = await _firestorePublicDocumentFetcher
        .patchDocument(
          'role_access/$roleId',
          fields: document,
          updateMaskFieldPaths: document.keys.toList(growable: false),
        )
        .timeout(
          const Duration(seconds: 4),
          onTimeout: () => throw TimeoutException(
            'role_access rest patch timeout for $roleId',
          ),
        );
    if (!patched) {
      throw Exception('role_access rest patch returned false for $roleId');
    }
  }
}
