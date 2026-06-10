import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/models/status_definition.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/models/status_form.dart';
import 'package:webapp/repositories/interfaces/status_form_repository.dart';

class LocalStatusFormRepository implements StatusFormRepository {
  LocalStatusFormRepository._();

  static final LocalStatusFormRepository instance =
      LocalStatusFormRepository._();
  static final DateTime _seededNow = DateTime.now();
  static final List<StatusForm> _devSeedForms = [
    ..._seedStatusForms(
      mainForms: _seedBookMainForms(),
      secondaryForms: const [],
    ),
    ..._seedStatusForms(
      mainForms: _seedPendingMainForms(),
      secondaryForms: _seedPendingSecondaryForms(),
    ),
    ..._seedStatusForms(
      mainForms: _seedAssignedMainForms(),
      secondaryForms: _seedAssignedSecondaryForms(),
    ),
    ..._seedStatusForms(
      mainForms: _seedOngoingMainForms(),
      secondaryForms: const [],
    ),
    ..._seedStatusForms(
      mainForms: _seedDeliveredMainForms(),
      secondaryForms: const [],
    ),
    ..._seedStatusForms(
      mainForms: _seedCancelledMainForms(),
      secondaryForms: const [],
    ),
  ];

  static List<StatusForm> _seedStatusForms({
    required List<StatusForm> mainForms,
    required List<StatusForm> secondaryForms,
  }) => [
    ...mainForms,
    ...secondaryForms,
  ];

  static List<StatusForm> _seedBookMainForms() => [
    StatusForm(
      id: '1',
      role: 'client',
      roles: const ['client'],
      isMainForm: true,
      currentStatusKey: 'book',
      nextStatusKey: 'pending',
      buttonText: 'Submit Booking',
      fieldIds: const ['1', '2', '3', '4', '8', '9', '10', '13'],
      fieldOverrides: const {
        '13': StatusFieldOverride(
          required: false,
          placeholder: 'Optional',
        ),
      },
      dependencies: const [],
      blockedMessage: null,
      isActive: true,
      createdAt: _seededNow,
      updatedAt: _seededNow,
    ),
  ];

  static List<StatusForm> _seedPendingMainForms() => [
    StatusForm(
      id: '2',
      role: 'admin',
      roles: const ['admin'],
      isMainForm: true,
      currentStatusKey: 'pending',
      nextStatusKey: 'assigned',
      buttonText: 'Assign Booking',
      fieldIds: const ['15', '14', '6', '7', '13', '10', '9', '8'],
      fieldOverrides: const {
        '14': StatusFieldOverride(
          required: true,
          placeholder: 'Ex. Puerto Princesa',
        ),
        '15': StatusFieldOverride(
          required: true,
          placeholder: 'Ex. El Nido',
        ),
        '13': StatusFieldOverride(
          required: true,
          placeholder: 'Ex. 1500',
        ),
        '8': StatusFieldOverride(
          required: true,
          placeholder: 'Ex. MCA00000000',
        ),
        '9': StatusFieldOverride(
          required: true,
          placeholder: 'Ex. MSLU0000000',
        ),
        '10': StatusFieldOverride(
          required: true,
          placeholder: 'Select Van Size',
        ),
      },
      dependencies: const [],
      blockedMessage: null,
      isActive: true,
      createdAt: _seededNow,
      updatedAt: _seededNow,
    ),
  ];

  static List<StatusForm> _seedPendingSecondaryForms() => [
    StatusForm(
      id: '3',
      role: 'client',
      roles: const ['client', 'admin'],
      isMainForm: false,
      currentStatusKey: 'pending',
      nextStatusKey: 'cancelled',
      statusText: 'Cancellation',
      statusSubtext: 'Please tell us your reason',
      buttonText: 'Cancel Booking',
      fieldIds: const ['12'],
      dependencies: const [],
      blockedMessage: null,
      isActive: true,
      createdAt: _seededNow,
      updatedAt: _seededNow,
    ),
  ];

  static List<StatusForm> _seedAssignedMainForms() => [
    StatusForm(
      id: '4',
      role: 'admin',
      roles: const ['admin', 'driver', 'helper'],
      isMainForm: true,
      currentStatusKey: 'assigned',
      nextStatusKey: 'ongoing',
      buttonText: 'Start Delivery',
      fieldIds: const [],
      dependencies: const [],
      blockedMessage: null,
      isActive: true,
      createdAt: _seededNow,
      updatedAt: _seededNow,
    ),
  ];

  static List<StatusForm> _seedAssignedSecondaryForms() => [
    StatusForm(
      id: '5',
      role: 'client',
      roles: const ['client', 'admin'],
      isMainForm: false,
      currentStatusKey: 'assigned',
      nextStatusKey: 'cancelled',
      statusText: 'Cancellation',
      statusSubtext: 'Please tell us your reason',
      buttonText: 'Cancel Booking',
      fieldIds: const ['12'],
      dependencies: const [],
      blockedMessage: null,
      isActive: true,
      createdAt: _seededNow,
      updatedAt: _seededNow,
    ),
  ];

  static List<StatusForm> _seedOngoingMainForms() => [
    StatusForm(
      id: '6',
      role: 'admin',
      roles: const ['admin', 'driver', 'helper'],
      isMainForm: true,
      currentStatusKey: 'ongoing',
      nextStatusKey: 'delivered',
      buttonText: 'Finish Delivery',
      fieldIds: const ['11', '16'],
      dependencies: const [],
      blockedMessage: null,
      isActive: true,
      createdAt: _seededNow,
      updatedAt: _seededNow,
    ),
  ];

  static List<StatusForm> _seedDeliveredMainForms() => [
    StatusForm(
      id: '7',
      role: 'client',
      roles: const ['client', 'admin', 'driver', 'helper'],
      isMainForm: true,
      currentStatusKey: 'delivered',
      nextStatusKey: null,
      buttonText: null,
      fieldIds: const [],
      dependencies: const [],
      blockedMessage: null,
      isActive: true,
      createdAt: _seededNow,
      updatedAt: _seededNow,
    ),
  ];

  static List<StatusForm> _seedCancelledMainForms() => [
    StatusForm(
      id: '8',
      role: 'client',
      roles: const ['client', 'admin', 'driver', 'helper'],
      isMainForm: true,
      currentStatusKey: 'cancelled',
      nextStatusKey: null,
      buttonText: null,
      fieldIds: const [],
      dependencies: const [],
      blockedMessage: null,
      isActive: true,
      createdAt: _seededNow,
      updatedAt: _seededNow,
    ),
  ];
  static final List<StatusDefinition> _devSeedStatuses = [
    StatusDefinition(
      id: '1',
      key: 'book',
      label: 'Book',
      description: 'Create a booking',
      applicableRoles: const ['client'],
      roleMessages: const {'client': 'Please fill the booking form'},
      isActive: true,
      createdAt: _seededNow,
      updatedAt: _seededNow,
    ),
    StatusDefinition(
      id: '2',
      key: 'pending',
      label: 'Pending',
      description: 'Booking has been created',
      applicableRoles: const ['client', 'admin'],
      roleMessages: const {
        'client': 'Wait for booking to be assigned',
        'admin': 'Please assign this booking',
      },
      isActive: true,
      createdAt: _seededNow,
      updatedAt: _seededNow,
    ),
    StatusDefinition(
      id: '3',
      key: 'assigned',
      label: 'Assigned',
      description: 'Booking has been assigned',
      applicableRoles: const ['client', 'admin', 'driver', 'helper'],
      roleMessages: const {
        'client': 'Please wait for booking to start',
        'admin': 'Please press start before moving',
        'driver': 'Please press start before moving',
        'helper': 'Please wait for booking to start',
      },
      isActive: true,
      createdAt: _seededNow,
      updatedAt: _seededNow,
    ),
    StatusDefinition(
      id: '4',
      key: 'ongoing',
      label: 'Ongoing',
      description: 'Delivery is now ongoing',
      applicableRoles: const ['client', 'admin', 'driver', 'helper'],
      roleMessages: const {
        'client': 'Please wait for delivery',
        'admin': 'Please upload delivery form',
        'driver': 'Please upload delivery form',
        'helper': 'Please upload delivery form',
      },
      isActive: true,
      createdAt: _seededNow,
      updatedAt: _seededNow,
    ),
    StatusDefinition(
      id: '5',
      key: 'delivered',
      label: 'Delivered',
      description: 'Delivery is completed',
      applicableRoles: const ['client', 'admin', 'driver', 'helper'],
      roleMessages: const {
        'client': 'Booking has been delivered',
        'admin': 'Booking has been delivered',
        'driver': 'Booking has been delivered',
        'helper': 'Booking has been delivered',
      },
      isActive: true,
      createdAt: _seededNow,
      updatedAt: _seededNow,
    ),
    StatusDefinition(
      id: '6',
      key: 'cancelled',
      label: 'Cancelled',
      description: 'Delivery was cancelled',
      applicableRoles: const ['client', 'admin', 'driver', 'helper'],
      roleMessages: const {
        'client': 'Booking has been cancelled',
        'admin': 'Booking has been cancelled',
        'driver': 'Booking has been cancelled',
        'helper': 'Booking has been cancelled',
      },
      isActive: true,
      createdAt: _seededNow,
      updatedAt: _seededNow,
    ),
  ];
  static final List<StatusField> _devSeedFields = [
    StatusField(
      id: '1',
      key: 'representative_name',
      type: 'text',
      title: 'Representative Name',
      placeholder: 'Ex. Juan Dela Cruz',
      required: true,
      options: const [],
      isActive: true,
      createdAt: _seededNow,
      updatedAt: _seededNow,
    ),
    StatusField(
      id: '2',
      key: 'representative_phone',
      type: 'phone',
      title: 'Representative Phone',
      placeholder: '+63**********',
      required: true,
      options: const [],
      isActive: true,
      createdAt: _seededNow,
      updatedAt: _seededNow,
    ),
    StatusField(
      id: '3',
      key: 'representative_position',
      type: 'text',
      title: 'Representative Position',
      placeholder: 'Ex. Manager',
      required: true,
      options: const [],
      isActive: true,
      createdAt: _seededNow,
      updatedAt: _seededNow,
    ),
    StatusField(
      id: '4',
      key: 'waybill_photo',
      type: 'photo',
      title: 'Waybill Photo',
      placeholder: 'Photo',
      required: true,
      options: const [],
      isActive: true,
      createdAt: _seededNow,
      updatedAt: _seededNow,
    ),
    StatusField(
      id: '5',
      key: 'truck_id',
      type: 'dropdown',
      title: 'Truck ID',
      placeholder: 'Select Truck ID',
      required: true,
      options: const [],
      optionSourceKey: statusFieldOptionSourceVehicleMakes,
      isActive: true,
      createdAt: _seededNow,
      updatedAt: _seededNow,
    ),
    StatusField(
      id: '8',
      key: 'waybill_number',
      type: 'text',
      title: 'Waybill Number',
      placeholder: 'Optional',
      required: false,
      options: const [],
      isActive: true,
      createdAt: _seededNow,
      updatedAt: _seededNow,
    ),
    StatusField(
      id: '9',
      key: 'van_number',
      type: 'text',
      title: 'Van Number',
      placeholder: 'Optional',
      required: false,
      options: const [],
      isActive: true,
      createdAt: _seededNow,
      updatedAt: _seededNow,
    ),
    StatusField(
      id: '10',
      key: 'van_size',
      type: 'dropdown',
      title: 'Van Size',
      placeholder: 'Optional',
      required: false,
      options: const [],
      optionSourceKey: statusFieldOptionSourceVehicleSizes,
      isActive: true,
      createdAt: _seededNow,
      updatedAt: _seededNow,
    ),
    StatusField(
      id: '6',
      key: 'driver_id',
      type: 'dropdown',
      title: 'Driver',
      placeholder: 'Select Driver',
      required: true,
      options: const [],
      optionSourceKey: statusFieldOptionSourceDrivers,
      isActive: true,
      createdAt: _seededNow,
      updatedAt: _seededNow,
    ),
    StatusField(
      id: '7',
      key: 'helper_id',
      type: 'dropdown',
      title: 'Helper',
      placeholder: 'Select Helper',
      required: true,
      options: const [],
      optionSourceKey: statusFieldOptionSourceHelpers,
      isActive: true,
      createdAt: _seededNow,
      updatedAt: _seededNow,
    ),
    StatusField(
      id: '11',
      key: 'delivery_form_photo',
      type: 'photo',
      title: 'Delivery Form',
      placeholder: 'Photo',
      required: true,
      options: const [],
      isActive: true,
      createdAt: _seededNow,
      updatedAt: _seededNow,
    ),
    StatusField(
      id: '12',
      key: 'cancellation_reason',
      type: 'text',
      title: 'Reason',
      placeholder: 'Why are you cancelling?',
      required: true,
      options: const [],
      isActive: true,
      createdAt: _seededNow,
      updatedAt: _seededNow,
    ),
    StatusField(
      id: '13',
      key: 'amount',
      type: 'number',
      title: 'Amount',
      placeholder: 'Ex. 1500',
      required: true,
      options: const [],
      isActive: true,
      createdAt: _seededNow,
      updatedAt: _seededNow,
    ),
    StatusField(
      id: '14',
      key: 'end',
      type: 'text',
      title: 'End',
      placeholder: 'Ex. El Nido',
      required: true,
      options: const [],
      isActive: true,
      createdAt: _seededNow,
      updatedAt: _seededNow,
    ),
    StatusField(
      id: '15',
      key: 'start',
      type: 'text',
      title: 'Start',
      placeholder: 'Ex. Puerto Princesa',
      required: true,
      options: const [],
      isActive: true,
      createdAt: _seededNow,
      updatedAt: _seededNow,
    ),
    StatusField(
      id: '16',
      key: 'delivery_form_number',
      type: 'number',
      title: 'Delivery Form Number',
      placeholder: 'Ex. 12345',
      required: true,
      options: const [],
      isActive: true,
      createdAt: _seededNow,
      updatedAt: _seededNow,
    ),
  ];

  static const _formsKey = 'paltranco_status_forms';
  static const _fieldsKey = 'paltranco_status_fields';
  static const _statusesKey = 'paltranco_status_definitions';
  static const _deletedFormIdsKey = 'paltranco_deleted_status_form_ids';
  static const _deletedFieldIdsKey = 'paltranco_deleted_status_field_ids';
  static const _deletedStatusIdsKey = 'paltranco_deleted_status_ids';

  SharedPreferences? _prefs;

  Future<void> _ensurePrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<void> _initialize() async {
    await _ensurePrefs();
    await _ensureDevSeedData();
  }

  Future<List<StatusForm>> _readForms() async {
    await _initialize();
    final raw = _prefs!.getStringList(_formsKey) ?? const [];
    return raw.map(StatusForm.fromJson).toList();
  }

  Future<List<StatusField>> _readFields() async {
    await _initialize();
    final raw = _prefs!.getStringList(_fieldsKey) ?? const [];
    return raw.map(StatusField.fromJson).toList();
  }

  Future<List<StatusDefinition>> _readStatuses() async {
    await _initialize();
    final raw = _prefs!.getStringList(_statusesKey) ?? const [];
    return raw.map(StatusDefinition.fromJson).toList();
  }

  Future<void> _writeForms(List<StatusForm> forms) async {
    await _initialize();
    await _prefs!.setStringList(
      _formsKey,
      forms.map((item) => item.toJson()).toList(),
    );
  }

  Future<void> _writeFields(List<StatusField> fields) async {
    await _initialize();
    await _prefs!.setStringList(
      _fieldsKey,
      fields.map((item) => item.toJson()).toList(),
    );
  }

  Future<void> _writeStatuses(List<StatusDefinition> statuses) async {
    await _initialize();
    await _prefs!.setStringList(
      _statusesKey,
      statuses.map((item) => item.toJson()).toList(),
    );
  }

  Future<Set<String>> _readDeletedIds(String key) async {
    await _ensurePrefs();
    return (_prefs!.getStringList(key) ?? const <String>[])
        .where((item) => item.trim().isNotEmpty)
        .toSet();
  }

  Future<void> _writeDeletedIds(String key, Set<String> ids) async {
    await _ensurePrefs();
    await _prefs!.setStringList(key, ids.toList());
  }

  Future<void> _markDeleted(String key, String id) async {
    if (id.trim().isEmpty) {
      return;
    }
    final ids = await _readDeletedIds(key);
    ids.add(id);
    await _writeDeletedIds(key, ids);
  }

  Future<void> _unmarkDeleted(String key, String id) async {
    if (id.trim().isEmpty) {
      return;
    }
    final ids = await _readDeletedIds(key);
    if (ids.remove(id)) {
      await _writeDeletedIds(key, ids);
    }
  }

  Future<void> _ensureDevSeedData() async {
    final currentForms = (_prefs!.getStringList(_formsKey) ?? const [])
        .map(StatusForm.fromJson)
        .toList();
    final currentFields = (_prefs!.getStringList(_fieldsKey) ?? const [])
        .map(StatusField.fromJson)
        .toList();
    final currentStatuses = (_prefs!.getStringList(_statusesKey) ?? const [])
        .map(StatusDefinition.fromJson)
        .toList();
    final deletedFormIds = await _readDeletedIds(_deletedFormIdsKey);
    final deletedFieldIds = await _readDeletedIds(_deletedFieldIdsKey);
    final deletedStatusIds = await _readDeletedIds(_deletedStatusIdsKey);

    final nextForms = _mergeSeededItems<StatusForm>(
      currentItems: currentForms,
      seededItems: _devSeedForms
          .where((item) => !deletedFormIds.contains(item.id ?? ''))
          .toList(),
      sameItem: (left, right) =>
          left.id == right.id ||
          ((left.primaryRole ?? left.role ?? '') ==
                  (right.primaryRole ?? right.role ?? '') &&
              (left.currentStatusKey ?? '') == (right.currentStatusKey ?? '') &&
              (left.nextStatusKey ?? '') == (right.nextStatusKey ?? '')),
      normalize: (item) => item,
    );
    final nextFields = _mergeSeededItems<StatusField>(
      currentItems: currentFields,
      seededItems: _devSeedFields
          .where((item) => !deletedFieldIds.contains(item.id ?? ''))
          .toList(),
      sameItem: (left, right) =>
          left.id == right.id || (left.key ?? '') == (right.key ?? ''),
      normalize: (item) => item,
    );
    final nextStatuses = _mergeSeededItems<StatusDefinition>(
      currentItems: currentStatuses,
      seededItems: _devSeedStatuses
          .where((item) => !deletedStatusIds.contains(item.id ?? ''))
          .toList(),
      sameItem: (left, right) =>
          left.id == right.id || (left.key ?? '') == (right.key ?? ''),
      normalize: (item) => item,
    );

    if (!_sameJsonList(currentForms, nextForms)) {
      await _prefs!.setStringList(
        _formsKey,
        nextForms.map((item) => item.toJson()).toList(),
      );
    }
    if (!_sameJsonList(currentFields, nextFields)) {
      await _prefs!.setStringList(
        _fieldsKey,
        nextFields.map((item) => item.toJson()).toList(),
      );
    }
    if (!_sameJsonList(currentStatuses, nextStatuses)) {
      await _prefs!.setStringList(
        _statusesKey,
        nextStatuses.map((item) => item.toJson()).toList(),
      );
    }
  }

  List<T> _mergeSeededItems<T extends Object>({
    required List<T> currentItems,
    required List<T> seededItems,
    required bool Function(T left, T right) sameItem,
    required T Function(T item) normalize,
  }) {
    final nextItems = [...currentItems];
    for (final seededItem in seededItems) {
      final normalizedSeededItem = normalize(seededItem);
      final index = nextItems.indexWhere(
        (item) => sameItem(item, normalizedSeededItem),
      );
      if (index == -1) {
        nextItems.add(normalizedSeededItem);
      } else if (_itemJson(nextItems[index]) != _itemJson(normalizedSeededItem)) {
        nextItems[index] = normalizedSeededItem;
      }
    }
    return nextItems;
  }

  bool _sameJsonList<T extends Object>(List<T> left, List<T> right) {
    if (identical(left, right)) {
      return true;
    }
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (_itemJson(left[index]) != _itemJson(right[index])) {
        return false;
      }
    }
    return true;
  }

  String _itemJson(Object item) {
    if (item is StatusForm) {
      return item.toJson();
    }
    if (item is StatusField) {
      return item.toJson();
    }
    if (item is StatusDefinition) {
      return item.toJson();
    }
    return '$item';
  }

  @override
  Future<void> deactivateStatusForm(String formId) async {
    final forms = await _readForms();
    final index = forms.indexWhere((form) => form.id == formId);
    if (index == -1) {
      return;
    }
    forms[index] = forms[index].copyWith(
      isActive: false,
      updatedAt: DateTime.now(),
    );
    await _writeForms(forms);
  }

  @override
  Future<void> deleteField(String fieldId) async {
    await _markDeleted(_deletedFieldIdsKey, fieldId);
    final fields = await _readFields()
      ..removeWhere((field) => field.id == fieldId);
    await _writeFields(fields);

    final forms = await _readForms();
    final updatedForms = forms
        .map(
          (form) => form.copyWith(
            fieldIds: form.fieldIds.where((id) => id != fieldId).toList(),
            fieldOverrides: Map<String, StatusFieldOverride>.from(
              form.fieldOverrides,
            )..remove(fieldId),
            updatedAt: DateTime.now(),
          ),
        )
        .toList();
    await _writeForms(updatedForms);
  }

  @override
  Future<void> deleteStatus(String statusId) async {
    await _markDeleted(_deletedStatusIdsKey, statusId);
    final statuses = await _readStatuses()
      ..removeWhere((status) => status.id == statusId);
    await _writeStatuses(statuses);
  }

  @override
  Future<void> deleteStatusForm(String formId) async {
    await _markDeleted(_deletedFormIdsKey, formId);
    final forms = await _readForms()
      ..removeWhere((form) => form.id == formId);
    await _writeForms(forms);
  }

  @override
  Future<List<StatusField>> getAllFields() async {
    final fields = await _readFields();
    fields.sort(
      (a, b) =>
          (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)),
    );
    return fields;
  }

  @override
  Future<List<StatusField>> getFields(String statusFormId) async {
    final forms = await _readForms();
    final matches = forms.where((form) => form.id == statusFormId);
    if (matches.isEmpty) {
      return [];
    }
    final form = matches.first;
    final allFields = await _readFields();
    final fieldsById = {for (final field in allFields) field.id ?? '': field};
    return form.fieldIds
        .map((fieldId) {
          final field = fieldsById[fieldId];
          if (field == null) {
            return null;
          }
          final override = form.fieldOverrides[fieldId];
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
  }

  @override
  Future<StatusForm?> getStatusFormByRoleAndStatus(
    String role,
    String currentStatusKey,
  ) async {
    final forms = await getStatusFormsByRoleAndStatus(role, currentStatusKey);
    return forms.where((form) => form.resolvedIsMainForm).firstOrNull ??
        (forms.isEmpty ? null : forms.first);
  }

  @override
  Future<List<StatusForm>> getStatusFormsByRoleAndStatus(
    String role,
    String currentStatusKey,
  ) async {
    final forms = await _readForms();
    final statuses = await _readStatuses();
    final normalizedRole = role.trim();
    final normalizedCurrentStatusKey = currentStatusKey.trim();

    bool isKnownActiveStatus(String? statusKey) {
      final normalizedStatusKey = statusKey?.trim() ?? '';
      if (normalizedStatusKey.isEmpty) {
        return false;
      }
      final matches = statuses.where(
        (status) => (status.key?.trim() ?? '') == normalizedStatusKey,
      );
      if (matches.isEmpty) {
        return false;
      }
      final status = matches.first;
      if (status.isActive == false) {
        return false;
      }
      return true;
    }

    bool isKnownActiveStatusOrTerminal(String? statusKey) {
      final normalizedStatusKey = statusKey?.trim() ?? '';
      if (normalizedStatusKey.isEmpty) {
        return true;
      }
      return isKnownActiveStatus(normalizedStatusKey);
    }

    final matchingForms = forms.where(
      (form) =>
          form.resolvedRoles.contains(normalizedRole) &&
          (form.currentStatusKey?.trim() ?? '') == normalizedCurrentStatusKey &&
          isKnownActiveStatus(form.currentStatusKey) &&
          isKnownActiveStatusOrTerminal(form.nextStatusKey),
    ).toList();
    matchingForms.sort(_compareFormsForStatus);
    return matchingForms;
  }

  @override
  Future<List<StatusDefinition>> getStatuses() async {
    return _readStatuses();
  }

  @override
  Future<List<StatusForm>> getStatusForms() async {
    final forms = await _readForms();
    forms.sort(_compareFormsForStatus);
    return forms;
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

  @override
  Future<void> saveField(StatusField field) async {
    final fields = await _readFields();
    final index = fields.indexWhere((item) => item.id == field.id);
    if (index == -1) {
      fields.add(field);
    } else {
      fields[index] = field;
    }
    await _writeFields(fields);
    await _unmarkDeleted(_deletedFieldIdsKey, field.id ?? '');
  }

  @override
  Future<void> saveFields(String statusFormId, List<StatusField> fields) async {
    final forms = await _readForms();
    final index = forms.indexWhere((form) => form.id == statusFormId);
    if (index == -1) {
      return;
    }
    forms[index] = forms[index].copyWith(
      fieldIds: fields.map((field) => field.id).whereType<String>().toList(),
      updatedAt: DateTime.now(),
    );
    await _writeForms(forms);
  }

  @override
  Future<void> saveStatus(StatusDefinition status) async {
    final statuses = await _readStatuses();
    final index = statuses.indexWhere((item) => item.id == status.id);
    if (index == -1) {
      statuses.add(status);
    } else {
      statuses[index] = status;
    }
    await _writeStatuses(statuses);
    await _unmarkDeleted(_deletedStatusIdsKey, status.id ?? '');
  }

  @override
  Future<void> saveStatusForm(StatusForm form) async {
    final forms = await _readForms();
    final index = forms.indexWhere((item) => item.id == form.id);
    if (index == -1) {
      forms.add(form);
    } else {
      forms[index] = form;
    }
    await _writeForms(forms);
    await _unmarkDeleted(_deletedFormIdsKey, form.id ?? '');
  }
}
