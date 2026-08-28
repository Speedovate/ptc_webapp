import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
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
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _firestorePublicDocumentFetcher =
           firestorePublicDocumentFetcher ??
           createFirestorePublicDocumentFetcher();

  static final RoleAccessRequest instance = RoleAccessRequest();
  static const dispatcherResourceKey = 'role_access_dispatcher';
  static const roleAccessResourceKey = 'role_access';
  static const Duration _startupTimeout = Duration(seconds: 6);
  static bool _didKickOffBackgroundQueueInitialization = false;

  final FirebaseFirestore _firestore;
  final FirestorePublicDocumentFetcher _firestorePublicDocumentFetcher;
  final OfflineMutationQueueService _offlineMutationQueueService =
      OfflineMutationQueueService.instance;
  late final FirestoreCollectionCache _cache = FirestoreCollectionCache(
    firestore: _firestore,
  );

  CollectionReference<Map<String, dynamic>> get _roleAccessCollection =>
      _firestore.collection('role_access');

  void _writeDocumentsInBackground({
    required String resourceKey,
    required List<Map<String, dynamic>> documents,
  }) {
    unawaited(
      _cache.writeDocuments(
        resourceKey: resourceKey,
        documents: documents,
      ).catchError((error, stackTrace) {
      }),
    );
  }

  Future<void> initialize() async {
    if (_didKickOffBackgroundQueueInitialization) {
      return;
    }
    _didKickOffBackgroundQueueInitialization = true;
    unawaited(
      OfflineQueueCoordinatorService.instance.initialize().then((_) {
      }).catchError((error, stackTrace) {
      }),
    );
  }

  Future<List<DispatcherAccessConfig>> getAllRoleAccessConfigs() async {
    await initialize();
    final cachedDocuments = await _cache.readDocuments(roleAccessResourceKey);
    if (cachedDocuments != null && cachedDocuments.isNotEmpty) {
      if (currentNetworkStatus()) {
        unawaited(_refreshRoleAccessCacheInBackground());
      }
      return cachedDocuments
          .map(DispatcherAccessConfig.fromMap)
          .toList(growable: false);
    }
    final sdkCachedDocuments = await _readRoleAccessSdkCacheOnly();
    if (sdkCachedDocuments.isNotEmpty) {
      _writeDocumentsInBackground(
        resourceKey: roleAccessResourceKey,
        documents: sdkCachedDocuments,
      );
      if (currentNetworkStatus()) {
        unawaited(_refreshRoleAccessCacheInBackground());
      }
      return sdkCachedDocuments
          .map(DispatcherAccessConfig.fromMap)
          .toList(growable: false);
    }
    final snapshot = await _roleAccessCollection
        .get()
        .timeout(_startupTimeout, onTimeout: () {
          throw TimeoutException('role_access fetch timeout');
        });
    try {
      final documents = snapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .toList(growable: false);
      _writeDocumentsInBackground(
        resourceKey: roleAccessResourceKey,
        documents: documents,
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
    final cachedDocuments = await _cache.readDocuments(dispatcherResourceKey);
    if (cachedDocuments != null && cachedDocuments.isNotEmpty) {
      if (currentNetworkStatus()) {
        unawaited(_refreshDispatcherCacheInBackground());
      }
      return DispatcherAccessConfig.fromMap(cachedDocuments.first);
    }
    final snapshot = await _roleAccessCollection.doc('dispatcher').get();
    if (!snapshot.exists) {
      return DispatcherAccessConfig.defaults();
    }
    final documents = <Map<String, dynamic>>[
      {
        'id': snapshot.id,
        ...?snapshot.data(),
      },
    ];
    await _cache.writeDocuments(
      resourceKey: dispatcherResourceKey,
      documents: documents,
    );
    if (documents.isEmpty) {
      return DispatcherAccessConfig.defaults();
    }
    return DispatcherAccessConfig.fromMap(documents.first);
  }

  Future<void> _refreshRoleAccessCacheInBackground() async {
    try {
      final snapshot = await _roleAccessCollection.get().timeout(_startupTimeout);
      await _cache.writeDocuments(
        resourceKey: roleAccessResourceKey,
        documents: snapshot.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .toList(growable: false),
      );
    } catch (_) {}
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
        .timeout(_startupTimeout, onTimeout: () {
          throw TimeoutException('public rest $collectionPath fetch timeout');
        });
    return documents;
  }

  Future<void> _refreshDispatcherCacheInBackground() async {
    try {
      final snapshot = await _roleAccessCollection.doc('dispatcher').get();
      if (!snapshot.exists) {
        return;
      }
      await _cache.writeDocuments(
        resourceKey: dispatcherResourceKey,
        documents: [
          {
            'id': snapshot.id,
            ...?snapshot.data(),
          },
        ],
      );
    } catch (_) {}
  }

  Future<DispatcherAccessConfig> saveDispatcherAccess(
    DispatcherAccessConfig config,
  ) {
    return saveRoleAccess(config.copyWith(id: 'dispatcher', role: 'dispatcher'));
  }

  Future<DispatcherAccessConfig> saveRoleAccess(
    DispatcherAccessConfig config,
  ) async {
    await initialize();
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final normalizedRole = config.role.trim().toLowerCase().replaceAll('_', '-');
    final next = config.copyWith(
      id: normalizedRole,
      role: normalizedRole,
      createdAtIso: config.createdAtIso ?? nowIso,
      updatedAtIso: nowIso,
    );
    final document = next.toMap();
    if (currentNetworkStatus()) {
      await _roleAccessCollection.doc(next.id).set(document);
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
        for (final item in [
          ...(await _cache.readDocuments(roleAccessResourceKey) ??
              const <Map<String, dynamic>>[]),
        ]..removeWhere((item) => item['id']?.toString() == next.id)
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
}
