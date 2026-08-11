import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:webapp/models/status.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/models/status_form.dart';
import 'package:webapp/requests/firestore_cache_store.dart';
import 'package:webapp/repositories/interfaces/status_form_repository.dart';
import 'package:webapp/services/network_status_events.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/utils/functions.dart';

class StatusRequest implements StatusFormRepository {
  StatusRequest({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  static final StatusRequest instance = StatusRequest();
  static const _statusFormsResourceKey = 'status_forms';
  static const _statusFieldsResourceKey = 'status_fields';
  static const _statusesResourceKey = 'statuses';

  final FirebaseFirestore _firestore;
  final OfflineMutationQueueService _offlineMutationQueueService =
      OfflineMutationQueueService.instance;
  late final FirestoreCollectionCache _cache = FirestoreCollectionCache(
    firestore: _firestore,
  );

  CollectionReference<Map<String, dynamic>> get _formsCollection =>
      _firestore.collection('status_forms');
  CollectionReference<Map<String, dynamic>> get _fieldsCollection =>
      _firestore.collection('status_fields');
  CollectionReference<Map<String, dynamic>> get _statusesCollection =>
      _firestore.collection('statuses');

  @override
  Future<List<StatusForm>> getStatusForms() async {
    return _runRequest(() async {
      final forms = await _getHydratedForms();
      forms.sort(_compareFormsForStatus);
      return forms;
    }, fallback: 'We could not load the flows right now.');
  }

  @override
  Future<List<StatusField>> getAllFields() async {
    return _runRequest(() async {
      final documents = await _cache.getDocuments(
        resourceKey: _statusFieldsResourceKey,
        fetchDocuments: () async {
          final snapshot = await _fieldsCollection.get();
          return snapshot.docs.map(documentData).toList();
        },
      );
      final fields = documents.map(StatusField.fromMap).toList();
      fields.sort(
        (a, b) =>
            (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)),
      );
      return fields;
    }, fallback: 'We could not load the fields right now.');
  }

  @override
  Future<List<Status>> getStatuses() async {
    return _runRequest(() async {
      final documents = await _cache.getDocuments(
        resourceKey: _statusesResourceKey,
        fetchDocuments: () async {
          final snapshot = await _statusesCollection.get();
          return snapshot.docs.map(documentData).toList();
        },
      );
      final statuses = documents.map(Status.fromMap).toList();
      return statuses;
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
    final normalizedRole = effectiveBackOfficeRoleKey(role);
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
              form.resolvedRoles.contains(normalizedRole) &&
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
        return form.fields
            .map((field) => field.copyWith(statusForm: form.toReferenceForm()))
            .toList();
      }
    }
    return [];
  }

  @override
  Future<void> saveStatusForm(StatusForm form) async {
    await _runRequest(() async {
      final now = DateTime.now();
      final nextId = normalizeId(form.id) ?? await _nextId(_formsCollection);
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
        await _formsCollection.doc(nextId).set(document);
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
        await _formsCollection.doc(statusFormId).set(updatedFormDocument);
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
      final nextId = normalizeId(field.id) ?? await _nextId(_fieldsCollection);
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
        await _fieldsCollection.doc(nextId).set(document);
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
      final nextId =
          normalizeId(status.id) ?? await _nextId(_statusesCollection);
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
        await _statusesCollection.doc(nextId).set(document);
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
      if (currentNetworkStatus()) {
        await _fieldsCollection.doc(normalized).delete();
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
      final forms = await _getHydratedForms();
      for (final form in forms) {
        if (!form.fields.any((field) => field.id == normalized)) {
          continue;
        }
        final updatedFormDocument = _formToFirestoreMap(
          form.copyWith(
            fields: form.fields
                .where((field) => field.id != normalized)
                .toList(),
            fieldOverrides: Map<String, StatusFieldOverride>.from(
              form.fieldOverrides,
            )..remove(normalized),
            updatedAt: DateTime.now(),
          ),
        );
        if (currentNetworkStatus()) {
          await _formsCollection.doc(form.id).set(updatedFormDocument);
        } else {
          await _offlineMutationQueueService.queueCollectionDocumentUpsert(
            collectionKey: _statusFormsResourceKey,
            documentId: form.id ?? '',
            document: updatedFormDocument,
            baseUpdatedAt: form.updatedAt?.toUtc().toIso8601String(),
          );
        }
        await _cache.upsertDocument(
          resourceKey: _statusFormsResourceKey,
          document: updatedFormDocument,
        );
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
      if (currentNetworkStatus()) {
        await _statusesCollection.doc(normalized).delete();
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
    }, fallback: 'We could not delete the status right now.');
  }

  @override
  Future<void> deleteStatusForm(String formId) async {
    await _runRequest(() async {
      final normalized = normalizeId(formId);
      if (normalized == null) {
        return;
      }
      if (currentNetworkStatus()) {
        await _formsCollection.doc(normalized).delete();
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
    }, fallback: 'We could not delete the flow right now.');
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
            await _formsCollection.doc(normalized).set(updatedFormDocument);
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

  Future<List<StatusForm>> _getHydratedForms() async {
    final snapshots = await Future.wait([
      _cache.getDocuments(
        resourceKey: _statusFormsResourceKey,
        fetchDocuments: () async {
          final snapshot = await _formsCollection.get();
          return snapshot.docs.map(documentData).toList();
        },
      ),
      _cache.getDocuments(
        resourceKey: _statusFieldsResourceKey,
        fetchDocuments: () async {
          final snapshot = await _fieldsCollection.get();
          return snapshot.docs.map(documentData).toList();
        },
      ),
    ]);
    final fieldById = {
      for (final doc in snapshots[1])
        doc['id']?.toString() ?? '': StatusField.fromMap(doc),
    };
    final forms = snapshots[0]
        .map((doc) => _formFromFirestoreMap(doc, fieldsById: fieldById))
        .toList();
    return forms;
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
