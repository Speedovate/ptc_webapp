import 'package:webapp/models/status_field.dart';
import 'package:webapp/models/status_definition.dart';
import 'package:webapp/models/status_form.dart';
import 'package:webapp/repositories/interfaces/status_form_repository.dart';

class FirebaseStatusFormRepository implements StatusFormRepository {
  @override
  Future<void> deleteField(String fieldId) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteStatus(String statusId) {
    throw UnimplementedError();
  }

  @override
  Future<void> deactivateStatusForm(String formId) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteStatusForm(String formId) {
    throw UnimplementedError();
  }

  @override
  Future<List<StatusField>> getFields(String statusFormId) {
    throw UnimplementedError();
  }

  @override
  Future<List<StatusField>> getAllFields() {
    throw UnimplementedError();
  }

  @override
  Future<List<StatusDefinition>> getStatuses() {
    throw UnimplementedError();
  }

  @override
  Future<StatusForm?> getStatusFormByRoleAndStatus(
    String role,
    String currentStatusKey,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<List<StatusForm>> getStatusFormsByRoleAndStatus(
    String role,
    String currentStatusKey,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<List<StatusForm>> getStatusForms() {
    throw UnimplementedError();
  }

  @override
  Future<void> saveFields(String statusFormId, List<StatusField> fields) {
    throw UnimplementedError();
  }

  @override
  Future<void> saveField(StatusField field) {
    throw UnimplementedError();
  }

  @override
  Future<void> saveStatus(StatusDefinition status) {
    throw UnimplementedError();
  }

  @override
  Future<void> saveStatusForm(StatusForm form) {
    throw UnimplementedError();
  }
}
