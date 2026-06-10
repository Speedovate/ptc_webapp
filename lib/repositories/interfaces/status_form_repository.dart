import 'package:webapp/models/status_field.dart';
import 'package:webapp/models/status.dart';
import 'package:webapp/models/status_form.dart';

abstract class StatusFormRepository {
  Future<List<StatusForm>> getStatusForms();
  Future<List<StatusField>> getAllFields();
  Future<List<Status>> getStatuses();
  Future<StatusForm?> getStatusFormByRoleAndStatus(
    String role,
    String currentStatusKey,
  );
  Future<List<StatusForm>> getStatusFormsByRoleAndStatus(
    String role,
    String currentStatusKey,
  );
  Future<List<StatusField>> getFields(String statusFormId);
  Future<void> saveStatusForm(StatusForm form);
  Future<void> saveFields(String statusFormId, List<StatusField> fields);
  Future<void> saveField(StatusField field);
  Future<void> saveStatus(Status status);
  Future<void> deleteField(String fieldId);
  Future<void> deleteStatus(String statusId);
  Future<void> deleteStatusForm(String formId);
  Future<void> deactivateStatusForm(String formId);
}
