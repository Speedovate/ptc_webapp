import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:webapp/models/chassis.dart';
import 'package:webapp/requests/firestore_cache_store.dart';
import 'package:webapp/services/network_status_events.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/offline_queue_coordinator_service.dart';
import 'package:webapp/utils/functions.dart';

class ChassisRequest {
  ChassisRequest({
    FirebaseFirestore? firestore,
    OfflineMutationQueueService? offlineMutationQueueService,
  }) : _providedFirestore = firestore,
       _offlineMutationQueueService =
           offlineMutationQueueService ?? OfflineMutationQueueService.instance;

  static final ChassisRequest instance = ChassisRequest();
  static const resourceKey = 'chassis';
  // Catalog reads must never hold the UI warmup for the write timeout.
  static const _readTimeout = Duration(seconds: 8);
  static const _writeTimeout = Duration(seconds: 30);

  final FirebaseFirestore? _providedFirestore;
  FirebaseFirestore get _firestore =>
      _providedFirestore ?? FirebaseFirestore.instance;
  final OfflineMutationQueueService _offlineMutationQueueService;
  late final FirestoreCollectionCache _cache = FirestoreCollectionCache(
    firestore: _firestore,
  );
  final StreamController<List<Chassis>> _updates =
      StreamController<List<Chassis>>.broadcast();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  StreamSubscription<String?>? _versionSubscription;
  List<Chassis> _memory = const <Chassis>[];
  bool _hasResolved = false;
  bool _initialized = false;
  bool _isRefreshingFromVersionSignal = false;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(resourceKey);

  bool get hasResolvedChassis => _hasResolved;
  List<Chassis> get hydratedChassisSnapshot =>
      List<Chassis>.unmodifiable(_memory);

  String displayChassisLabel(String value) {
    final id = int.tryParse(value.trim());
    if (id == null) {
      return value;
    }
    final chassis = _memory.where((item) => item.id == id).firstOrNull;
    final name = chassis?.name.trim() ?? '';
    return name.isEmpty ? 'Chassis $id' : name;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    unawaited(
      OfflineQueueCoordinatorService.instance.initialize().catchError((_) {}),
    );
    _subscription = _collection.snapshots(includeMetadataChanges: true).listen((
      snapshot,
    ) {
      if (!currentNetworkStatus() && snapshot.metadata.isFromCache) return;
      // Preserve the Firestore document ID when legacy/manual records do not
      // also store an `id` field. This matches the other catalog requests.
      unawaited(_applyRemoteDocuments(snapshot.docs.map(documentData)));
    }, onError: (_, _) {});
    _versionSubscription = _cache.watchResourceVersion(resourceKey).listen((
      version,
    ) {
      unawaited(_refreshForVersionSignal(version));
    }, onError: (_, _) {});
  }

  Future<void> _refreshForVersionSignal(String? remoteVersion) async {
    final shouldRefresh = await _cache.hasRemoteVersionMismatch(
      resourceKey,
      remoteVersion,
    );
    if (!shouldRefresh || _isRefreshingFromVersionSignal) return;
    _isRefreshingFromVersionSignal = true;
    try {
      await getChassis();
    } catch (_) {
      // A realtime snapshot remains the fallback source for this collection.
    } finally {
      _isRefreshingFromVersionSignal = false;
    }
  }

  Stream<List<Chassis>> watchChassis() async* {
    await initialize();
    yield List<Chassis>.unmodifiable(_memory);
    yield* _updates.stream;
  }

  Future<List<Chassis>> getChassis() async {
    await initialize();
    // Match the other vehicle catalogs: render persisted data immediately and
    // let the realtime listener keep it current in the background.
    final documents = await _cache.getDocuments(
      resourceKey: resourceKey,
      fetchDocuments: () async {
        final snapshot = currentNetworkStatus()
            ? await _collection.get().timeout(_readTimeout)
            : await _collection
                  .get(const GetOptions(source: Source.cache))
                  .timeout(_readTimeout);
        return snapshot.docs.map(documentData).toList(growable: false);
      },
    );
    return _applyDocuments(
      await _mergeQueuedDocuments(documents),
      writeCache: false,
    );
  }

  Future<Chassis> saveChassis(Chassis chassis, {int? previousBookingId}) async {
    await initialize();
    final isCreate = chassis.id <= 0;
    final submissionKey =
        chassis.submissionKey ??
        'chassis:${DateTime.now().toUtc().microsecondsSinceEpoch}:${chassis.name.toLowerCase()}';
    final now = DateTime.now();
    final online = currentNetworkStatus();
    final id = isCreate
        ? (online
              ? int.parse(
                  await _offlineMutationQueueService.reserveNumericDocumentId(
                    collectionKey: resourceKey,
                    submissionKey: submissionKey,
                  ),
                )
              : -DateTime.now().microsecondsSinceEpoch)
        : chassis.id;
    final saved = chassis.copyWith(
      id: id,
      createdAt: chassis.createdAt ?? now,
      updatedAt: now,
      submissionKey: submissionKey,
    );
    final document = saved.toMap();
    if (online) {
      await _writeAssignmentOnline(
        chassis: saved,
        document: document,
        previousBookingId: previousBookingId,
      );
    } else {
      await _offlineMutationQueueService.queueChassisAssignment(
        documentId: '$id',
        submissionKey: submissionKey,
        chassisDocument: document,
        previousBookingId: previousBookingId?.toString(),
        nextBookingId: saved.currentBookingId?.toString(),
      );
    }
    await _cache.upsertDocument(resourceKey: resourceKey, document: document);
    _upsertMemory(saved);
    return saved;
  }

  Future<void> deleteChassis(Chassis chassis) async {
    await initialize();
    final id = chassis.id;
    if (id <= 0) return;
    final now = DateTime.now().toUtc().toIso8601String();
    if (currentNetworkStatus()) {
      await _firestore.runTransaction<void>((transaction) async {
        if (chassis.currentBookingId != null) {
          transaction.set(
            _firestore
                .collection('bookings')
                .doc('${chassis.currentBookingId}'),
            {'chassis_id': FieldValue.delete(), 'updated_at': now},
            SetOptions(merge: true),
          );
        }
        transaction.delete(_collection.doc('$id'));
      });
    } else {
      await _offlineMutationQueueService.queueChassisDelete(
        documentId: '$id',
        bookingId: chassis.currentBookingId?.toString(),
      );
    }
    await _cache.removeDocument(resourceKey: resourceKey, documentId: '$id');
    _memory = _memory.where((item) => item.id != id).toList(growable: false);
    _updates.add(List<Chassis>.unmodifiable(_memory));
  }

  Future<void> _writeAssignmentOnline({
    required Chassis chassis,
    required Map<String, dynamic> document,
    required int? previousBookingId,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _firestore
        .runTransaction<void>((transaction) async {
          DocumentSnapshot<Map<String, dynamic>>? priorChassisSnapshot;
          if (chassis.currentBookingId != null) {
            final targetBooking = _firestore
                .collection('bookings')
                .doc('${chassis.currentBookingId}');
            final targetSnapshot = await transaction.get(targetBooking);
            if (!targetSnapshot.exists) {
              throw StateError('The selected booking no longer exists.');
            }
            final priorChassisId = int.tryParse(
              targetSnapshot.data()?['chassis_id']?.toString() ?? '',
            );
            if (priorChassisId != null && priorChassisId != chassis.id) {
              priorChassisSnapshot = await transaction.get(
                _collection.doc('$priorChassisId'),
              );
            }
          }
          if (previousBookingId != null &&
              previousBookingId != chassis.currentBookingId) {
            transaction.set(
              _firestore.collection('bookings').doc('$previousBookingId'),
              {'chassis_id': FieldValue.delete(), 'updated_at': now},
              SetOptions(merge: true),
            );
          }
          if (chassis.currentBookingId != null) {
            transaction.set(
              _firestore
                  .collection('bookings')
                  .doc('${chassis.currentBookingId}'),
              <String, dynamic>{
                'chassis_id': '${chassis.id}',
                'updated_at': now,
              },
              SetOptions(merge: true),
            );
          }
          if (priorChassisSnapshot?.exists == true) {
            transaction.set(priorChassisSnapshot!.reference, {
              'current_booking_id': FieldValue.delete(),
              'current_driver_id': FieldValue.delete(),
              'current_status': Chassis.ready,
              'updated_at': now,
            }, SetOptions(merge: true));
          }
          transaction.set(_collection.doc('${chassis.id}'), document);
        })
        .timeout(_writeTimeout);
  }

  Future<List<Chassis>> _applyRemoteDocuments(
    Iterable<Map<String, dynamic>> documents,
  ) async {
    final values = documents
        .map((document) => Map<String, dynamic>.from(document))
        .toList(growable: false);
    final merged = await _mergeQueuedDocuments(values);
    await _cache.writeDocuments(resourceKey: resourceKey, documents: merged);
    return _applyDocuments(merged, writeCache: false);
  }

  Future<List<Map<String, dynamic>>> _mergeQueuedDocuments(
    List<Map<String, dynamic>> documents,
  ) async {
    final next = <String, Map<String, dynamic>>{
      for (final document in documents)
        document['id']?.toString() ?? '': Map<String, dynamic>.from(document),
    };
    final queued = await _offlineMutationQueueService
        .readQueuedCollectionDocuments(collectionKey: resourceKey);
    for (final document in queued) {
      final id = document['id']?.toString() ?? '';
      if (id.isNotEmpty) next[id] = document;
    }
    return next.values.toList(growable: false);
  }

  Future<List<Chassis>> _applyDocuments(
    List<Map<String, dynamic>> documents, {
    required bool writeCache,
  }) async {
    if (writeCache) {
      await _cache.writeDocuments(
        resourceKey: resourceKey,
        documents: documents,
      );
    }
    final chassis =
        documents.map(Chassis.fromMap).where((item) => item.id != 0).toList()
          ..sort((a, b) => b.id.compareTo(a.id));
    _memory = List<Chassis>.unmodifiable(chassis);
    _hasResolved = true;
    _updates.add(_memory);
    return _memory;
  }

  void _upsertMemory(Chassis chassis) {
    final next = List<Chassis>.from(_memory);
    final index = next.indexWhere((item) => item.id == chassis.id);
    if (index < 0) {
      next.add(chassis);
    } else {
      next[index] = chassis;
    }
    next.sort((a, b) => b.id.compareTo(a.id));
    _memory = List<Chassis>.unmodifiable(next);
    _hasResolved = true;
    _updates.add(_memory);
  }

  void dispose() {
    _subscription?.cancel();
    _versionSubscription?.cancel();
    _updates.close();
  }
}
