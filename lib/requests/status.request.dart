import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:webapp/models/status.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/models/status_form.dart';
import 'package:webapp/requests/firestore_cache_store.dart';
import 'package:webapp/repositories/interfaces/status_form_repository.dart';
import 'package:webapp/services/firestore_public_document_fetcher.dart';
import 'package:webapp/services/network_status_events.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/offline_queue_coordinator_service.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:webapp/utils/functions.dart';

class StatusRequest implements StatusFormRepository {
  StatusRequest({
    FirebaseFirestore? firestore,
    FirestorePublicDocumentFetcher? firestorePublicDocumentFetcher,
  }) : _providedFirestore = firestore,
       _firestorePublicDocumentFetcher =
           firestorePublicDocumentFetcher ??
           createFirestorePublicDocumentFetcher();

  static final StatusRequest instance = StatusRequest();
  static const _statusFormsResourceKey = 'status_forms';
  static const _statusFieldsResourceKey = 'status_fields';
  static const _statusesResourceKey = 'statuses';
  static const Duration _startupTimeout = Duration(seconds: 6);
  static List<StatusForm> _hydratedFormsSnapshot = const [];
  static List<StatusField> _hydratedFieldsSnapshot = const [];
  static List<Status> _hydratedStatusesSnapshot = const [];
  static bool _hasResolvedForms = false;
  static bool _hasResolvedFields = false;
  static bool _hasResolvedStatuses = false;
  static bool _didStartBackgroundOfflineQueueInitialization = false;
  static bool _didStartRealtimeCacheSync = false;
  static bool _isRefreshingFromVersionSignal = false;

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

  final FirebaseFirestore? _providedFirestore;
  FirebaseFirestore get _firestore =>
      _providedFirestore ?? FirebaseFirestore.instance;
  final FirestorePublicDocumentFetcher _firestorePublicDocumentFetcher;
  final OfflineMutationQueueService _offlineMutationQueueService =
      OfflineMutationQueueService.instance;
  final RoleAccessService _roleAccessService = RoleAccessService.instance;
  late final FirestoreCollectionCache _cache = FirestoreCollectionCache(
    firestore: _firestore,
  );
  final StreamController<void> _statusCacheUpdates =
      StreamController<void>.broadcast();

  CollectionReference<Map<String, dynamic>> get _formsCollection =>
      _firestore.collection('status_forms');
  CollectionReference<Map<String, dynamic>> get _fieldsCollection =>
      _firestore.collection('status_fields');
  CollectionReference<Map<String, dynamic>> get _statusesCollection =>
      _firestore.collection('statuses');

  static bool get hasResolvedForms => _hasResolvedForms;
  static bool get hasResolvedFields => _hasResolvedFields;
  static bool get hasResolvedStatuses => _hasResolvedStatuses;
  static List<StatusForm> get hydratedFormsSnapshot =>
      List<StatusForm>.unmodifiable(_hydratedFormsSnapshot);
  static List<StatusField> get hydratedFieldsSnapshot =>
      List<StatusField>.unmodifiable(_hydratedFieldsSnapshot);
  static List<Status> get hydratedStatusesSnapshot =>
      List<Status>.unmodifiable(_hydratedStatusesSnapshot);

  Future<void> primeResolvedSnapshotsFromLocalCache() async {
    initialize();
    final formsDocuments =
        await _cache.readDocuments(_statusFormsResourceKey) ??
        await _readCollectionSdkCacheOnly(_formsCollection);
    final fieldsDocuments =
        await _cache.readDocuments(_statusFieldsResourceKey) ??
        await _readCollectionSdkCacheOnly(_fieldsCollection);
    final statusesDocuments =
        await _cache.readDocuments(_statusesResourceKey) ??
        await _readCollectionSdkCacheOnly(_statusesCollection);

    if (fieldsDocuments.isNotEmpty) {
      final fields = fieldsDocuments.map(StatusField.fromMap).toList()
        ..sort(
          (a, b) => (a.createdAt ?? DateTime(0)).compareTo(
            b.createdAt ?? DateTime(0),
          ),
        );
      _hydratedFieldsSnapshot = List<StatusField>.from(fields);
      _hasResolvedFields = true;
    }
    if (statusesDocuments.isNotEmpty) {
      final statuses = statusesDocuments.map(Status.fromMap).toList();
      _hydratedStatusesSnapshot = List<Status>.from(statuses);
      _hasResolvedStatuses = true;
    }
    if (formsDocuments.isNotEmpty && fieldsDocuments.isNotEmpty) {
      final forms = _inflateForms(
        formDocuments: formsDocuments,
        fieldDocuments: fieldsDocuments,
      );
      _hydratedFormsSnapshot = List<StatusForm>.from(forms);
      _hasResolvedForms = true;
    }
  }

  Future<void> initialize() async {
    if (_didStartBackgroundOfflineQueueInitialization) {
      return;
    }
    _didStartBackgroundOfflineQueueInitialization = true;
    _ensureRealtimeCacheSync();
    unawaited(
      OfflineQueueCoordinatorService.instance.initialize().catchError(
        (error, stackTrace) {},
      ),
    );
  }

  void _ensureRealtimeCacheSync() {
    if (_didStartRealtimeCacheSync) {
      return;
    }
    _didStartRealtimeCacheSync = true;
    _cache.watchResourceVersion(_statusFormsResourceKey).listen((version) {
      unawaited(_handleStatusVersionSignal(_statusFormsResourceKey, version));
    }, onError: (_, _) {});
    _cache.watchResourceVersion(_statusFieldsResourceKey).listen((version) {
      unawaited(_handleStatusVersionSignal(_statusFieldsResourceKey, version));
    }, onError: (_, _) {});
    _cache.watchResourceVersion(_statusesResourceKey).listen((version) {
      unawaited(_handleStatusVersionSignal(_statusesResourceKey, version));
    }, onError: (_, _) {});
  }

  Stream<void> watchStatusCacheUpdates() async* {
    await initialize();
    yield* _statusCacheUpdates.stream;
  }

  Future<void> _handleStatusVersionSignal(
    String resourceKey,
    String? remoteVersion,
  ) async {
    final shouldRefresh = await _cache.hasRemoteVersionMismatch(
      resourceKey,
      remoteVersion,
    );
    if (!shouldRefresh || _isRefreshingFromVersionSignal) {
      return;
    }
    _isRefreshingFromVersionSignal = true;
    try {
      await _refreshStatusCachesFromSourceOfTruth();
      _statusCacheUpdates.add(null);
    } finally {
      _isRefreshingFromVersionSignal = false;
    }
  }

  @override
  Future<List<StatusForm>> getStatusForms() async {
    return _runRequest(() async {
      initialize();
      final forms = await _getHydratedForms();
      forms.sort(_compareFormsForStatus);
      _hasResolvedForms = true;
      _hydratedFormsSnapshot = List<StatusForm>.from(forms);
      return forms;
    }, fallback: 'We could not load the flows right now.');
  }

  @override
  Future<List<StatusField>> getAllFields() async {
    return _runRequest(() async {
      initialize();
      if (!currentNetworkStatus() && _hasResolvedFields) {
        return List<StatusField>.from(_hydratedFieldsSnapshot);
      }
      try {
        final documents = await _cache.getDocuments(
          resourceKey: _statusFieldsResourceKey,
          fetchDocuments: () async {
            final sdkCachedDocuments = await _readCollectionSdkCacheOnly(
              _fieldsCollection,
            );
            if (sdkCachedDocuments.isNotEmpty && !currentNetworkStatus()) {
              return sdkCachedDocuments;
            }
            final snapshot = await _fieldsCollection.get().timeout(
              _startupTimeout,
              onTimeout: () =>
                  throw TimeoutException('status fields fetch timeout'),
            );
            return snapshot.docs.map(documentData).toList(growable: false);
          },
        );
        final fields = documents.map(StatusField.fromMap).toList();
        fields.sort(
          (a, b) => (a.createdAt ?? DateTime(0)).compareTo(
            b.createdAt ?? DateTime(0),
          ),
        );
        _hasResolvedFields = true;
        _hydratedFieldsSnapshot = List<StatusField>.from(fields);
        return fields;
      } catch (error) {
        final documents = await _fetchCollectionDocumentsViaPublicRest(
          'status_fields',
        );
        if (documents.isEmpty) {
          rethrow;
        }
        _writeDocumentsInBackground(
          resourceKey: _statusFieldsResourceKey,
          documents: documents,
        );
        final fields = documents.map(StatusField.fromMap).toList();
        fields.sort(
          (a, b) => (a.createdAt ?? DateTime(0)).compareTo(
            b.createdAt ?? DateTime(0),
          ),
        );
        _hasResolvedFields = true;
        _hydratedFieldsSnapshot = List<StatusField>.from(fields);
        return fields;
      }
    }, fallback: 'We could not load the fields right now.');
  }

  @override
  Future<List<Status>> getStatuses() async {
    return _runRequest(() async {
      initialize();
      if (!currentNetworkStatus() && _hasResolvedStatuses) {
        return List<Status>.from(_hydratedStatusesSnapshot);
      }
      try {
        final documents = await _cache.getDocuments(
          resourceKey: _statusesResourceKey,
          fetchDocuments: () async {
            final sdkCachedDocuments = await _readCollectionSdkCacheOnly(
              _statusesCollection,
            );
            if (sdkCachedDocuments.isNotEmpty && !currentNetworkStatus()) {
              return sdkCachedDocuments;
            }
            final snapshot = await _statusesCollection.get().timeout(
              _startupTimeout,
              onTimeout: () => throw TimeoutException('statuses fetch timeout'),
            );
            return snapshot.docs.map(documentData).toList(growable: false);
          },
        );
        final statuses = documents.map(Status.fromMap).toList();
        _hasResolvedStatuses = true;
        _hydratedStatusesSnapshot = List<Status>.from(statuses);
        return statuses;
      } catch (error) {
        final documents = await _fetchCollectionDocumentsViaPublicRest(
          'statuses',
        );
        if (documents.isEmpty) {
          rethrow;
        }
        _writeDocumentsInBackground(
          resourceKey: _statusesResourceKey,
          documents: documents,
        );
        final statuses = documents.map(Status.fromMap).toList();
        _hasResolvedStatuses = true;
        _hydratedStatusesSnapshot = List<Status>.from(statuses);
        return statuses;
      }
    }, fallback: 'We could not load the statuses right now.');
  }

  @override
  Future<StatusForm?> getStatusFormByRoleAndStatus(
    String role,
    String currentStatusKey,
  ) async {
    final forms = await getStatusFormsByRoleAndStatus(role, currentStatusKey);
    for (final form in forms) {
      if (form.resolvedIsMainForm) {
        return form;
      }
    }
    return null;
  }

  @override
  Future<List<StatusForm>> getStatusFormsByRoleAndStatus(
    String role,
    String currentStatusKey,
  ) async {
    final forms = await _getHydratedForms();
    final statuses = await getStatuses();
    final resolvedRoles = _roleAccessService.workflowResolutionRoles(role);
    final normalizedCurrentStatusKey = currentStatusKey.trim().toLowerCase();

    bool isKnownActiveStatus(String? statusKey) {
      final normalizedStatusKey = statusKey?.trim().toLowerCase() ?? '';
      if (normalizedStatusKey.isEmpty) {
        return false;
      }
      for (final status in statuses) {
        if ((status.key?.trim().toLowerCase() ?? '') == normalizedStatusKey) {
          return status.isActive != false;
        }
      }
      return false;
    }

    bool isKnownActiveStatusOrTerminal(String? statusKey) {
      final normalizedStatusKey = statusKey?.trim() ?? '';
      if (normalizedStatusKey.isEmpty) {
        return true;
      }
      return isKnownActiveStatus(normalizedStatusKey);
    }

    final matchingForms = forms
        .where(
          (form) =>
              resolvedRoles.any(form.resolvedRoles.contains) &&
              (form.currentStatusKey?.trim().toLowerCase() ?? '') ==
                  normalizedCurrentStatusKey &&
              isKnownActiveStatus(form.currentStatusKey) &&
              isKnownActiveStatusOrTerminal(form.nextStatusKey),
        )
        .toList();
    matchingForms.sort(_compareFormsForStatus);
    return matchingForms;
  }

  @override
  Future<List<StatusField>> getFields(String statusFormId) async {
    final forms = await _getHydratedForms();
    for (final form in forms) {
      if (form.id == statusFormId) {
        final fields = form.fields
            .map((field) => field.copyWith(statusForm: form.toReferenceForm()))
            .toList();
        for (final field in fields) {
          final type = (field.type ?? '').trim().toLowerCase();
          if (type != 'dropdown' && type != 'search_dropdown') {
            continue;
          }
        }
        return fields;
      }
    }
    return [];
  }

  @override
  Future<void> saveStatusForm(StatusForm form) async {
    await _runRequest(() async {
      final now = DateTime.now();
      final nextId = await _resolveSaveId(
        requestedId: form.id,
        collection: _formsCollection,
        resourceKey: _statusFormsResourceKey,
        submissionKey:
            'form:${(form.currentStatusKey ?? '').trim().toLowerCase()}:${(form.nextStatusKey ?? '').trim().toLowerCase()}:${(form.role ?? '').trim().toLowerCase()}',
      );
      final saved = form.copyWith(
        id: nextId,
        createdAt: form.createdAt ?? now,
        updatedAt: now,
      );
      final document = _formToFirestoreMap(saved);
      final baseUpdatedAtIso = await _cachedUpdatedAt(
        resourceKey: _statusFormsResourceKey,
        documentId: nextId,
      );
      if (currentNetworkStatus()) {
        await _writeCollectionDocumentOnline(
          collectionPath: _statusFormsResourceKey,
          documentId: nextId,
          document: document,
          collection: _formsCollection,
        );
      } else {
        await _offlineMutationQueueService.queueCollectionDocumentUpsert(
          collectionKey: _statusFormsResourceKey,
          documentId: nextId,
          document: document,
          baseUpdatedAt: baseUpdatedAtIso,
        );
      }
      await _cache.upsertDocument(
        resourceKey: _statusFormsResourceKey,
        document: document,
      );
    }, fallback: 'We could not save the flow right now.');
  }

  @override
  Future<void> saveFields(String statusFormId, List<StatusField> fields) async {
    await _runRequest(() async {
      final forms = await _getHydratedForms();
      final existingForm = forms
          .where((form) => form.id == statusFormId)
          .firstOrNull;
      if (existingForm == null) {
        return;
      }
      final updatedFormDocument = _formToFirestoreMap(
        existingForm.copyWith(fields: fields, updatedAt: DateTime.now()),
      );
      final baseUpdatedAtIso = await _cachedUpdatedAt(
        resourceKey: _statusFormsResourceKey,
        documentId: statusFormId,
      );
      if (currentNetworkStatus()) {
        await _writeCollectionDocumentOnline(
          collectionPath: _statusFormsResourceKey,
          documentId: statusFormId,
          document: updatedFormDocument,
          collection: _formsCollection,
        );
      } else {
        await _offlineMutationQueueService.queueCollectionDocumentUpsert(
          collectionKey: _statusFormsResourceKey,
          documentId: statusFormId,
          document: updatedFormDocument,
          baseUpdatedAt: baseUpdatedAtIso,
        );
      }
      await _cache.upsertDocument(
        resourceKey: _statusFormsResourceKey,
        document: updatedFormDocument,
      );
    }, fallback: 'We could not save the fields right now.');
  }

  @override
  Future<void> saveField(StatusField field) async {
    await _runRequest(() async {
      final now = DateTime.now();
      final nextId = await _resolveSaveId(
        requestedId: field.id,
        collection: _fieldsCollection,
        resourceKey: _statusFieldsResourceKey,
        submissionKey:
            'field:${(field.key ?? '').trim().toLowerCase()}:${(field.type ?? '').trim().toLowerCase()}',
      );
      final saved = field.copyWith(
        id: nextId,
        createdAt: field.createdAt ?? now,
        updatedAt: now,
      );
      final document = saved.toMap();
      final baseUpdatedAtIso = await _cachedUpdatedAt(
        resourceKey: _statusFieldsResourceKey,
        documentId: nextId,
      );
      if (currentNetworkStatus()) {
        await _writeCollectionDocumentOnline(
          collectionPath: _statusFieldsResourceKey,
          documentId: nextId,
          document: document,
          collection: _fieldsCollection,
        );
      } else {
        await _offlineMutationQueueService.queueCollectionDocumentUpsert(
          collectionKey: _statusFieldsResourceKey,
          documentId: nextId,
          document: document,
          baseUpdatedAt: baseUpdatedAtIso,
        );
      }
      await _cache.upsertDocument(
        resourceKey: _statusFieldsResourceKey,
        document: document,
      );
    }, fallback: 'We could not save the field right now.');
  }

  @override
  Future<void> saveStatus(Status status) async {
    await _runRequest(() async {
      final now = DateTime.now();
      final nextId = await _resolveSaveId(
        requestedId: status.id,
        collection: _statusesCollection,
        resourceKey: _statusesResourceKey,
        submissionKey: 'status:${(status.key ?? '').trim().toLowerCase()}',
      );
      final saved = status.copyWith(
        id: nextId,
        createdAt: status.createdAt ?? now,
        updatedAt: now,
      );
      final document = saved.toMap();
      final baseUpdatedAtIso = await _cachedUpdatedAt(
        resourceKey: _statusesResourceKey,
        documentId: nextId,
      );
      if (currentNetworkStatus()) {
        await _writeCollectionDocumentOnline(
          collectionPath: _statusesResourceKey,
          documentId: nextId,
          document: document,
          collection: _statusesCollection,
        );
      } else {
        await _offlineMutationQueueService.queueCollectionDocumentUpsert(
          collectionKey: _statusesResourceKey,
          documentId: nextId,
          document: document,
          baseUpdatedAt: baseUpdatedAtIso,
        );
      }
      await _cache.upsertDocument(
        resourceKey: _statusesResourceKey,
        document: document,
      );
    }, fallback: 'We could not save the status right now.');
  }

  @override
  Future<void> deleteField(String fieldId) async {
    await _runRequest(() async {
      final normalized = normalizeId(fieldId);
      if (normalized == null) {
        return;
      }
      final forms = await _getHydratedForms();
      if (currentNetworkStatus()) {
        await _deleteCollectionDocumentOnline(
          collectionPath: _statusFieldsResourceKey,
          documentId: normalized,
          collection: _fieldsCollection,
        );
      } else {
        await _offlineMutationQueueService.queueCollectionDocumentDelete(
          collectionKey: _statusFieldsResourceKey,
          documentId: normalized,
        );
      }
      await _cache.removeDocument(
        resourceKey: _statusFieldsResourceKey,
        documentId: normalized,
      );
      for (final form in forms) {
        final nextFields = form.fields
            .where((field) => normalizeId(field.id) != normalized)
            .toList(growable: false);
        final nextOverrides = Map<String, StatusFieldOverride>.from(
          form.fieldOverrides,
        )..remove(normalized);
        final didChange =
            nextFields.length != form.fields.length ||
            nextOverrides.length != form.fieldOverrides.length;
        if (!didChange || (form.id?.trim().isEmpty ?? true)) {
          continue;
        }
        final updatedForm = form.copyWith(
          fields: nextFields,
          fieldOverrides: nextOverrides,
          updatedAt: DateTime.now(),
        );
        await _upsertFormDocument(updatedForm);
      }
    }, fallback: 'We could not delete the field right now.');
  }

  @override
  Future<void> deleteStatus(String statusId) async {
    await _runRequest(() async {
      final normalized = normalizeId(statusId);
      if (normalized == null) {
        return;
      }
      final statuses = await getStatuses();
      final targetStatus = statuses.cast<Status?>().firstWhere(
        (status) => normalizeId(status?.id) == normalized,
        orElse: () => null,
      );
      final targetKey = targetStatus?.key?.trim().toLowerCase();
      final forms = targetKey == null || targetKey.isEmpty
          ? const <StatusForm>[]
          : await _getHydratedForms();
      if (currentNetworkStatus()) {
        await _deleteCollectionDocumentOnline(
          collectionPath: _statusesResourceKey,
          documentId: normalized,
          collection: _statusesCollection,
        );
      } else {
        await _offlineMutationQueueService.queueCollectionDocumentDelete(
          collectionKey: _statusesResourceKey,
          documentId: normalized,
        );
      }
      await _cache.removeDocument(
        resourceKey: _statusesResourceKey,
        documentId: normalized,
      );
      if (targetKey == null || targetKey.isEmpty) {
        return;
      }
      for (final form in forms) {
        final currentStatusMatches =
            form.currentStatusKey?.trim().toLowerCase() == targetKey;
        final nextStatusMatches =
            form.nextStatusKey?.trim().toLowerCase() == targetKey;
        final nextDependencies = form.dependencies
            .where(
              (dependency) =>
                  dependency.statusKey?.trim().toLowerCase() != targetKey,
            )
            .toList(growable: false);
        final dependenciesChanged =
            nextDependencies.length != form.dependencies.length;
        if (!currentStatusMatches &&
            !nextStatusMatches &&
            !dependenciesChanged) {
          continue;
        }
        final updatedForm = form.copyWith(
          currentStatusKey: currentStatusMatches ? null : form.currentStatusKey,
          nextStatusKey: nextStatusMatches ? null : form.nextStatusKey,
          dependencies: nextDependencies,
          updatedAt: DateTime.now(),
        );
        await _upsertFormDocument(updatedForm);
      }
    }, fallback: 'We could not delete the status right now.');
  }

  @override
  Future<void> deleteStatusForm(String formId) async {
    await _runRequest(() async {
      final normalized = normalizeId(formId);
      if (normalized == null) {
        return;
      }
      final fields = await getAllFields();
      if (currentNetworkStatus()) {
        await _deleteCollectionDocumentOnline(
          collectionPath: _statusFormsResourceKey,
          documentId: normalized,
          collection: _formsCollection,
        );
      } else {
        await _offlineMutationQueueService.queueCollectionDocumentDelete(
          collectionKey: _statusFormsResourceKey,
          documentId: normalized,
        );
      }
      await _cache.removeDocument(
        resourceKey: _statusFormsResourceKey,
        documentId: normalized,
      );
      for (final field in fields) {
        if (normalizeId(field.statusForm?.id) != normalized ||
            (field.id?.trim().isEmpty ?? true)) {
          continue;
        }
        final updatedField = field.copyWith(
          statusForm: null,
          updatedAt: DateTime.now(),
        );
        await _upsertFieldDocument(updatedField);
      }
    }, fallback: 'We could not delete the flow right now.');
  }

  Future<void> _upsertFormDocument(StatusForm form) async {
    final formId = normalizeId(form.id);
    if (formId == null) {
      return;
    }
    final document = _formToFirestoreMap(form.copyWith(id: formId));
    final baseUpdatedAtIso = await _cachedUpdatedAt(
      resourceKey: _statusFormsResourceKey,
      documentId: formId,
    );
    if (currentNetworkStatus()) {
      await _writeCollectionDocumentOnline(
        collectionPath: _statusFormsResourceKey,
        documentId: formId,
        document: document,
        collection: _formsCollection,
      );
    } else {
      await _offlineMutationQueueService.queueCollectionDocumentUpsert(
        collectionKey: _statusFormsResourceKey,
        documentId: formId,
        document: document,
        baseUpdatedAt: baseUpdatedAtIso,
      );
    }
    await _cache.upsertDocument(
      resourceKey: _statusFormsResourceKey,
      document: document,
    );
  }

  Future<void> _upsertFieldDocument(StatusField field) async {
    final fieldId = normalizeId(field.id);
    if (fieldId == null) {
      return;
    }
    final document = field.copyWith(id: fieldId).toMap();
    final baseUpdatedAtIso = await _cachedUpdatedAt(
      resourceKey: _statusFieldsResourceKey,
      documentId: fieldId,
    );
    if (currentNetworkStatus()) {
      await _writeCollectionDocumentOnline(
        collectionPath: _statusFieldsResourceKey,
        documentId: fieldId,
        document: document,
        collection: _fieldsCollection,
      );
    } else {
      await _offlineMutationQueueService.queueCollectionDocumentUpsert(
        collectionKey: _statusFieldsResourceKey,
        documentId: fieldId,
        document: document,
        baseUpdatedAt: baseUpdatedAtIso,
      );
    }
    await _cache.upsertDocument(
      resourceKey: _statusFieldsResourceKey,
      document: document,
    );
  }

  @override
  Future<void> deactivateStatusForm(String formId) async {
    await _runRequest(() async {
      final normalized = normalizeId(formId);
      if (normalized == null) {
        return;
      }
      final forms = await _getHydratedForms();
      for (final form in forms) {
        if (form.id == normalized) {
          final updatedFormDocument = _formToFirestoreMap(
            form.copyWith(isActive: false, updatedAt: DateTime.now()),
          );
          if (currentNetworkStatus()) {
            await _writeCollectionDocumentOnline(
              collectionPath: _statusFormsResourceKey,
              documentId: normalized,
              document: updatedFormDocument,
              collection: _formsCollection,
            );
          } else {
            await _offlineMutationQueueService.queueCollectionDocumentUpsert(
              collectionKey: _statusFormsResourceKey,
              documentId: normalized,
              document: updatedFormDocument,
              baseUpdatedAt: form.updatedAt?.toUtc().toIso8601String(),
            );
          }
          await _cache.upsertDocument(
            resourceKey: _statusFormsResourceKey,
            document: updatedFormDocument,
          );
          break;
        }
      }
    }, fallback: 'We could not deactivate the flow right now.');
  }

  Future<void> _writeCollectionDocumentOnline({
    required String collectionPath,
    required String documentId,
    required Map<String, dynamic> document,
    required CollectionReference<Map<String, dynamic>> collection,
  }) async {
    if (kIsWeb) {
      try {
        final patched = await _firestorePublicDocumentFetcher
            .patchDocument(
              '$collectionPath/$documentId',
              fields: document,
              updateMaskFieldPaths: document.keys.toList(growable: false),
            )
            .timeout(
              const Duration(seconds: 4),
              onTimeout: () => throw TimeoutException(
                '$collectionPath remote rest patch timeout for $documentId',
              ),
            );
        if (patched) {
          return;
        }
      } catch (_) {}
    }

    try {
      await collection
          .doc(documentId)
          .set(document)
          .timeout(
            const Duration(seconds: 8),
            onTimeout: () => throw TimeoutException(
              '$collectionPath remote write timeout for $documentId',
            ),
          );
      return;
    } catch (error) {
      if (!kIsWeb) {
        rethrow;
      }
    }

    final patched = await _firestorePublicDocumentFetcher
        .patchDocument(
          '$collectionPath/$documentId',
          fields: document,
          updateMaskFieldPaths: document.keys.toList(growable: false),
        )
        .timeout(
          const Duration(seconds: 4),
          onTimeout: () => throw TimeoutException(
            '$collectionPath remote rest patch timeout for $documentId',
          ),
        );
    if (!patched) {
      throw Exception(
        '$collectionPath remote rest patch returned false for $documentId',
      );
    }
  }

  Future<void> _deleteCollectionDocumentOnline({
    required String collectionPath,
    required String documentId,
    required CollectionReference<Map<String, dynamic>> collection,
  }) async {
    if (kIsWeb) {
      try {
        final deleted = await _firestorePublicDocumentFetcher
            .deleteDocument('$collectionPath/$documentId')
            .timeout(
              const Duration(seconds: 4),
              onTimeout: () => throw TimeoutException(
                '$collectionPath remote rest delete timeout for $documentId',
              ),
            );
        if (deleted) {
          return;
        }
      } catch (_) {}
    }

    try {
      await collection
          .doc(documentId)
          .delete()
          .timeout(
            const Duration(seconds: 8),
            onTimeout: () => throw TimeoutException(
              '$collectionPath remote delete timeout for $documentId',
            ),
          );
      return;
    } catch (error) {
      if (!kIsWeb) {
        rethrow;
      }
    }

    final deleted = await _firestorePublicDocumentFetcher
        .deleteDocument('$collectionPath/$documentId')
        .timeout(
          const Duration(seconds: 4),
          onTimeout: () => throw TimeoutException(
            '$collectionPath remote rest delete timeout for $documentId',
          ),
        );
    if (!deleted) {
      throw Exception(
        '$collectionPath remote rest delete returned false for $documentId',
      );
    }
  }

  Future<List<StatusForm>> _getHydratedForms() async {
    if (!currentNetworkStatus() && _hasResolvedForms && _hasResolvedFields) {
      return List<StatusForm>.from(_hydratedFormsSnapshot);
    }
    try {
      final results = await Future.wait([
        _cache.getDocuments(
          resourceKey: _statusFormsResourceKey,
          fetchDocuments: () async {
            final sdkCachedForms = await _readCollectionSdkCacheOnly(
              _formsCollection,
            );
            if (sdkCachedForms.isNotEmpty && !currentNetworkStatus()) {
              return sdkCachedForms;
            }
            final formsSnapshot = await _formsCollection.get().timeout(
              _startupTimeout,
              onTimeout: () =>
                  throw TimeoutException('status forms fetch timeout'),
            );
            return formsSnapshot.docs.map(documentData).toList(growable: false);
          },
        ),
        _cache.getDocuments(
          resourceKey: _statusFieldsResourceKey,
          fetchDocuments: () async {
            final sdkCachedFields = await _readCollectionSdkCacheOnly(
              _fieldsCollection,
            );
            if (sdkCachedFields.isNotEmpty && !currentNetworkStatus()) {
              return sdkCachedFields;
            }
            final fieldsSnapshot = await _fieldsCollection.get().timeout(
              _startupTimeout,
              onTimeout: () =>
                  throw TimeoutException('status fields fetch timeout'),
            );
            return fieldsSnapshot.docs
                .map(documentData)
                .toList(growable: false);
          },
        ),
      ]);
      final formDocuments = results[0];
      final fieldDocuments = results[1];
      final forms = _inflateForms(
        formDocuments: formDocuments,
        fieldDocuments: fieldDocuments,
      );
      _hasResolvedForms = true;
      _hydratedFormsSnapshot = List<StatusForm>.from(forms);
      final fields = fieldDocuments.map(StatusField.fromMap).toList();
      fields.sort(
        (a, b) =>
            (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)),
      );
      _hasResolvedFields = true;
      _hydratedFieldsSnapshot = List<StatusField>.from(fields);
      return forms;
    } catch (error) {
      final results = await Future.wait([
        _fetchCollectionDocumentsViaPublicRest('status_forms'),
        _fetchCollectionDocumentsViaPublicRest('status_fields'),
      ]);
      final formDocuments = results[0];
      final fieldDocuments = results[1];
      if (formDocuments.isEmpty) {
        rethrow;
      }
      _writeDocumentsInBackground(
        resourceKey: _statusFormsResourceKey,
        documents: formDocuments,
      );
      if (fieldDocuments.isNotEmpty) {
        _writeDocumentsInBackground(
          resourceKey: _statusFieldsResourceKey,
          documents: fieldDocuments,
        );
      }
      final forms = _inflateForms(
        formDocuments: formDocuments,
        fieldDocuments: fieldDocuments,
      );
      _hasResolvedForms = true;
      _hydratedFormsSnapshot = List<StatusForm>.from(forms);
      final fields = fieldDocuments.map(StatusField.fromMap).toList();
      fields.sort(
        (a, b) =>
            (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)),
      );
      _hasResolvedFields = true;
      _hydratedFieldsSnapshot = List<StatusField>.from(fields);
      return forms;
    }
  }

  List<StatusForm> _inflateForms({
    required List<Map<String, dynamic>> formDocuments,
    required List<Map<String, dynamic>> fieldDocuments,
  }) {
    final fieldById = {
      for (final doc in fieldDocuments)
        doc['id']?.toString() ?? '': StatusField.fromMap(doc),
    };
    final forms = formDocuments
        .map((doc) => _formFromFirestoreMap(doc, fieldsById: fieldById))
        .toList(growable: false);
    return forms;
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

  Future<void> _refreshStatusCachesFromSourceOfTruth() async {
    try {
      final results = await Future.wait([
        _formsCollection.get().timeout(_startupTimeout),
        _fieldsCollection.get().timeout(_startupTimeout),
        _statusesCollection.get().timeout(_startupTimeout),
      ]);
      final formsSnapshot = results[0];
      final fieldsSnapshot = results[1];
      final statusesSnapshot = results[2];
      await _cache.writeDocuments(
        resourceKey: _statusFormsResourceKey,
        documents: formsSnapshot.docs.map(documentData).toList(growable: false),
      );
      await _cache.writeDocuments(
        resourceKey: _statusFieldsResourceKey,
        documents: fieldsSnapshot.docs
            .map(documentData)
            .toList(growable: false),
      );
      await _cache.writeDocuments(
        resourceKey: _statusesResourceKey,
        documents: statusesSnapshot.docs
            .map(documentData)
            .toList(growable: false),
      );
      final forms = _inflateForms(
        formDocuments: formsSnapshot.docs
            .map(documentData)
            .toList(growable: false),
        fieldDocuments: fieldsSnapshot.docs
            .map(documentData)
            .toList(growable: false),
      );
      _hydratedFormsSnapshot = List<StatusForm>.from(forms);
      _hasResolvedForms = true;
      final fields =
          fieldsSnapshot.docs
              .map(documentData)
              .map(StatusField.fromMap)
              .toList(growable: false)
            ..sort(
              (a, b) => (a.createdAt ?? DateTime(0)).compareTo(
                b.createdAt ?? DateTime(0),
              ),
            );
      _hydratedFieldsSnapshot = List<StatusField>.from(fields);
      _hasResolvedFields = true;
      _hydratedStatusesSnapshot = statusesSnapshot.docs
          .map(documentData)
          .map(Status.fromMap)
          .toList(growable: false);
      _hasResolvedStatuses = true;
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _readCollectionSdkCacheOnly(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    try {
      final snapshot = await collection
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(seconds: 1));
      return snapshot.docs.map(documentData).toList(growable: false);
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  StatusForm _formFromFirestoreMap(
    Map<String, dynamic> map, {
    required Map<String, StatusField> fieldsById,
  }) {
    final fieldIds =
        ((map['field_ids'] as List<dynamic>?) ??
                (map['fields'] as List<dynamic>? ?? const []).map((item) {
                  if (item is Map) {
                    final fieldMap = Map<String, dynamic>.from(item);
                    return fieldMap['id'] ?? fieldMap['field_id'];
                  }
                  return item;
                }).toList())
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList();
    final fieldOverrides =
        (map['field_overrides'] as Map?)?.map(
          (key, value) => MapEntry(
            key.toString(),
            StatusFieldOverride.fromMap(
              Map<String, dynamic>.from(value as Map),
            ),
          ),
        ) ??
        const <String, StatusFieldOverride>{};
    final fields = fieldIds
        .map((fieldId) {
          final field = fieldsById[fieldId];
          if (field == null) {
            return null;
          }
          final override = fieldOverrides[fieldId];
          if (override == null) {
            return field;
          }
          return field.copyWith(
            required: override.required,
            placeholder: override.placeholder,
          );
        })
        .whereType<StatusField>()
        .toList();
    final dependencyMaps = map['dependencies'] as List<dynamic>? ?? const [];
    final parsedRoles = (map['roles'] as List<dynamic>? ?? const [])
        .map((item) => item.toString().trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .toList();
    final parsedRole = map['role']?.toString().trim().toLowerCase();
    return StatusForm(
      id: map['id']?.toString(),
      role: parsedRole?.isNotEmpty == true ? parsedRole : null,
      roles: parsedRoles.isNotEmpty
          ? parsedRoles
          : (parsedRole?.isNotEmpty == true ? [parsedRole!] : const []),
      isMainForm: map['is_main_form'] as bool?,
      currentStatusKey: map['current_status_key']
          ?.toString()
          .trim()
          .toLowerCase(),
      nextStatusKey: map['next_status_key']?.toString().trim().toLowerCase(),
      statusText: map['status_text']?.toString(),
      statusSubtext: map['status_subtext']?.toString(),
      buttonText: map['button_text']?.toString(),
      fields: fields,
      fieldOverrides: fieldOverrides,
      dependencies: dependencyMaps
          .map((item) => Map<String, dynamic>.from(item as Map))
          .map(StatusDependency.fromMap)
          .toList(),
      blockedMessage: map['blocked_message']?.toString(),
      isActive: map['is_active'] as bool?,
      createdAt: _toDateTime(map['created_at']),
      updatedAt: _toDateTime(map['updated_at']),
    );
  }

  Map<String, dynamic> _formToFirestoreMap(StatusForm form) {
    return {
      'id': form.id,
      'role': form.role,
      'roles': form.roles,
      'is_main_form': form.isMainForm,
      'current_status_key': form.currentStatusKey,
      'next_status_key': form.nextStatusKey,
      'status_text': form.statusText,
      'status_subtext': form.statusSubtext,
      'button_text': form.buttonText,
      'field_ids': form.fields
          .map((field) => field.id)
          .whereType<String>()
          .toList(),
      'field_overrides': form.fieldOverrides.map(
        (key, value) => MapEntry(key, value.toMap()),
      ),
      'dependencies': form.dependencies.map((item) => item.toMap()).toList(),
      'blocked_message': form.blockedMessage,
      'is_active': form.isActive,
      'created_at': form.createdAt?.toIso8601String(),
      'updated_at': form.updatedAt?.toIso8601String(),
    };
  }

  Future<String> _nextId(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    final snapshot = await collection.get();
    final highest = snapshot.docs
        .map((doc) => int.tryParse(documentData(doc)['id']?.toString() ?? ''))
        .whereType<int>()
        .fold<int>(0, (max, value) => value > max ? value : max);
    return '${highest + 1}';
  }

  Future<String> _nextCreateId({
    required CollectionReference<Map<String, dynamic>> collection,
    required String resourceKey,
    required String submissionKey,
  }) async {
    if (currentNetworkStatus()) {
      return _offlineMutationQueueService.reserveNumericDocumentId(
        collectionKey: resourceKey,
        submissionKey: submissionKey,
      );
    }
    return _nextId(collection);
  }

  Future<String> _resolveSaveId({
    required String? requestedId,
    required CollectionReference<Map<String, dynamic>> collection,
    required String resourceKey,
    required String submissionKey,
  }) async {
    final normalizedId = normalizeId(requestedId);
    if (!currentNetworkStatus() || normalizedId == null) {
      return _nextCreateId(
        collection: collection,
        resourceKey: resourceKey,
        submissionKey: submissionKey,
      );
    }
    final existing = await collection.doc(normalizedId).get();
    if (existing.exists) {
      return normalizedId;
    }
    return _nextCreateId(
      collection: collection,
      resourceKey: resourceKey,
      submissionKey: submissionKey,
    );
  }

  int _compareFormsForStatus(StatusForm a, StatusForm b) {
    final mainComparison = _compareBoolTrueFirst(
      a.resolvedIsMainForm,
      b.resolvedIsMainForm,
    );
    if (mainComparison != 0) {
      return mainComparison;
    }
    final parsedAId = int.tryParse(a.id ?? '');
    final parsedBId = int.tryParse(b.id ?? '');
    if (parsedAId != null && parsedBId != null) {
      return parsedAId.compareTo(parsedBId);
    }
    return (a.id ?? '').compareTo(b.id ?? '');
  }

  int _compareBoolTrueFirst(bool a, bool b) {
    if (a == b) {
      return 0;
    }
    return a ? -1 : 1;
  }

  DateTime? _toDateTime(dynamic value) {
    if (value == null) {
      return null;
    }
    return DateTime.tryParse(value.toString());
  }

  Future<String?> _cachedUpdatedAt({
    required String resourceKey,
    required String documentId,
  }) async {
    final documents = await _cache.readDocuments(resourceKey);
    if (documents == null) {
      return null;
    }
    for (final document in documents) {
      if ((document['id']?.toString().trim() ?? '') == documentId) {
        return document['updated_at']?.toString();
      }
    }
    return null;
  }

  Future<T> _runRequest<T>(
    Future<T> Function() action, {
    required String fallback,
  }) async {
    try {
      return await action();
    } on FirebaseException catch (error) {
      throw Exception(userFacingErrorMessage(error, fallback: fallback));
    } catch (error) {
      throw Exception(userFacingErrorMessage(error, fallback: fallback));
    }
  }
}
