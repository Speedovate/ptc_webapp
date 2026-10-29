import 'package:flutter/foundation.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/models/status_form.dart';
import 'package:webapp/repositories/interfaces/status_form_repository.dart';
import 'package:webapp/requests/status.request.dart';
import 'package:webapp/services/status_field_option_resolver.dart';
import 'package:webapp/services/status_form_engine.dart';
import 'package:webapp/utils/functions.dart';

/// These keys already have dedicated controls in the booking editor.
const bookingEditDedicatedKeys = {
  'client_id',
  'driver_id',
  'helper_id',
  'chassis_id',
  'representative_name',
  'representative_phone',
  'waybill_photo',
  'waybill_number',
  'van_number',
  'van_size',
  'amount',
  'pick_up_date',
  'pick_up_time',
  'drop_off_date',
  'drop_off_time',
  'origin',
  'origin_barangay',
  'destination',
  'destination_barangay',
  'delivery_form_photo',
  'delivery_form_number',
};

List<StatusField> configuredBookingEditFields(
  List<StatusForm> forms,
  List<StatusField> library,
) {
  final byId = {
    for (final field in library)
      if (field.id != null) field.id!: field,
  };
  final byKey = <String, StatusField>{};
  for (final form in forms) {
    if (form.isActive == false) continue;
    for (final reference in form.fields) {
      final field = byId[reference.id] ?? reference;
      final key = field.key?.trim() ?? '';
      if (key.isEmpty ||
          field.isActive == false ||
          bookingEditDedicatedKeys.contains(key)) {
        continue;
      }
      final override = form.fieldOverrides[field.id];
      final resolved = field.copyWith(
        key: key,
        required: override?.required ?? field.required,
        placeholder: override?.placeholder ?? field.placeholder,
      );
      final previous = byKey[key];
      if (previous == null ||
          (resolved.updatedAt ?? DateTime(0)).isAfter(
            previous.updatedAt ?? DateTime(0),
          )) {
        byKey[key] = resolved;
      }
    }
  }
  return byKey.values.toList();
}

/// Compare nested field values so unchanged photos/lists are not resubmitted.
Map<String, dynamic> bookingEditFieldChanges({
  required Map<String, dynamic> before,
  required Map<String, dynamic> after,
  Set<String> clearableKeys = const {},
}) {
  bool equal(dynamic a, dynamic b) {
    if (a is String && b is String) return a.trim() == b.trim();
    if (a is List && b is List) {
      return a.length == b.length &&
          List.generate(
            a.length,
            (i) => equal(a[i], b[i]),
          ).every((value) => value);
    }
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every((key) => b.containsKey(key) && equal(a[key], b[key]));
    }
    return a == b;
  }

  bool empty(dynamic value) =>
      value == null ||
      (value is String && value.trim().isEmpty) ||
      (value is List && value.isEmpty) ||
      (value is Map && value.isEmpty);
  final changed = <String, dynamic>{};
  for (final key in {...before.keys, ...after.keys}) {
    if (equal(before[key], after[key])) continue;
    if (empty(after[key])) {
      // Explicit null suppresses an older value without deleting its history.
      if (clearableKeys.contains(key)) changed[key] = null;
    } else {
      changed[key] = after[key];
    }
  }
  return changed;
}

/// Owns additional configured fields without migrating existing booking data.
class BookingEditFields extends ChangeNotifier {
  BookingEditFields({
    required Map<String, dynamic> initialAnswers,
    List<StatusForm> seedForms = const [],
    List<StatusField> seedLibrary = const [],
    bool hasResolvedForms = false,
    StatusFormRepository? repository,
    StatusFieldOptionResolver? optionResolver,
  }) : _repository = repository ?? StatusRequest.instance,
       _resolver =
           optionResolver ??
           StatusFieldOptionResolver(statusFormRepository: repository),
       _hasSeed = hasResolvedForms,
       values = Map.from(initialAnswers)
         ..removeWhere((key, _) => bookingEditDedicatedKeys.contains(key)) {
    fields = _resolver.hydrateFieldsFromResolvedSnapshots(
      configuredBookingEditFields(seedForms, seedLibrary),
    );
  }

  final StatusFormRepository _repository;
  final StatusFieldOptionResolver _resolver;
  final bool _hasSeed;
  final Map<String, dynamic> values;
  final Set<String> touched = {};
  List<StatusField> fields = [];
  Map<String, String> errors = {};
  bool isLoading = false;
  String? loadError;
  bool _disposed = false;

  Future<void> load({bool refresh = false}) async {
    if (isLoading) return;
    isLoading = true;
    loadError = null;
    notifyListeners();
    try {
      var configured = fields;
      if (!_hasSeed || refresh) {
        final results = await Future.wait([
          _repository.getStatusForms(),
          _repository.getAllFields(),
        ]);
        if (_disposed) return;
        configured = configuredBookingEditFields(
          results[0] as List<StatusForm>,
          results[1] as List<StatusField>,
        );
      }
      final hydrated = await _resolver.hydrateFields(configured);
      if (_disposed) return;
      fields = hydrated;
    } catch (_) {
      if (_disposed) return;
      loadError = 'Additional booking fields could not load. Please retry.';
    } finally {
      if (!_disposed) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  List<StatusField> visibleFields(
    Map<String, dynamic> baseAnswers,
    String? clientId,
  ) {
    final answers = {...baseAnswers, ...values};
    return _resolver.withClientRepresentativeSuggestions(
      StatusFormEngine.visibleFields(fields, answers),
      clientId: clientId,
      answers: answers,
    );
  }

  void update(String key, dynamic value) {
    values[key] = value;
    touched.add(key);
    errors.remove(key);
    notifyListeners();
  }

  bool validate(Map<String, dynamic> baseAnswers, String? clientId) {
    // New required fields must not prevent editing an older completed booking
    // unless the office actually edits those fields.
    final edited = visibleFields(
      baseAnswers,
      clientId,
    ).where((field) => touched.contains(field.key)).toList();
    errors = StatusFormEngine(
      _repository,
    ).validateFields(edited, {...baseAnswers, ...values});
    notifyListeners();
    return errors.isEmpty;
  }

  Map<String, dynamic> changes(
    Map<String, dynamic> baseAnswers,
    String? clientId,
  ) {
    final result = <String, dynamic>{};
    for (final field in visibleFields(baseAnswers, clientId)) {
      final key = field.key!;
      if (!touched.contains(key)) continue;
      var value = values[key];
      if (value is String) value = value.trim();
      if (field.type == 'phone' && value is String && value.isNotEmpty) {
        value = normalizePhilippinePhone(value) ?? value;
      }
      result[key] =
          value == null ||
              (value is String && value.isEmpty) ||
              (value is List && value.isEmpty) ||
              (value is Map && value.isEmpty)
          ? null
          : value;
    }
    return result;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
