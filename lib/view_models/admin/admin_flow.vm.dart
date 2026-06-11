import 'package:stacked/stacked.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/models/status.dart';
import 'package:webapp/models/status_form.dart';
import 'package:webapp/requests/status.request.dart';
import 'package:webapp/repositories/interfaces/status_form_repository.dart';
import 'package:webapp/services/status_field_option_resolver.dart';
import 'package:webapp/services/status_form_engine.dart';
import 'package:webapp/utils/functions.dart';

class AdminFlowViewModel extends BaseViewModel {
  AdminFlowViewModel({StatusFormRepository? repository})
    : _repository = repository ?? StatusRequest.instance,
      _engine = StatusFormEngine(repository ?? StatusRequest.instance) {
    forms = List<StatusForm>.from(_cachedForms);
    selectedForm = _cachedSelectedForm;
    fields = List<StatusField>.from(_cachedFields);
    fieldLibrary = List<StatusField>.from(_cachedFieldLibrary);
    statuses = List<Status>.from(_cachedStatuses);
    errorMessage = _cachedErrorMessage;
    successMessage = _cachedSuccessMessage;
    isPreviewVisible = _cachedIsPreviewVisible;
    _fieldsByFormId.addAll(
      _cachedFieldsByFormId.map(
        (key, value) => MapEntry(key, List<StatusField>.from(value)),
      ),
    );
  }

  final StatusFormRepository _repository;
  final StatusFormEngine _engine;
  final StatusFieldOptionResolver _optionResolver = StatusFieldOptionResolver();
  static List<StatusForm> _cachedForms = const [];
  static StatusForm? _cachedSelectedForm;
  static List<StatusField> _cachedFields = const [];
  static List<StatusField> _cachedFieldLibrary = const [];
  static List<Status> _cachedStatuses = const [];
  static Map<String, List<StatusField>> _cachedFieldsByFormId = const {};
  static String? _cachedErrorMessage;
  static String? _cachedSuccessMessage;
  static bool _cachedIsPreviewVisible = true;

  static void clearCachedState() {
    _cachedForms = const [];
    _cachedSelectedForm = null;
    _cachedFields = const [];
    _cachedFieldLibrary = const [];
    _cachedStatuses = const [];
    _cachedFieldsByFormId = const {};
    _cachedErrorMessage = null;
    _cachedSuccessMessage = null;
    _cachedIsPreviewVisible = true;
  }

  static const roleOptions = ['client', 'driver', 'admin', 'helper'];
  static const dependencyStatusTypes = ['client_status'];
  static const formStatusOrder = [
    'book',
    'pending',
    'assigned',
    'ongoing',
    'delivered',
    'cancelled',
  ];
  static const fieldTypeOptions = [
    'text',
    'email',
    'phone',
    'photo',
    'number',
    'date',
    'time',
    'dropdown',
    'checkbox',
  ];
  static const fieldOptionSourceOptions = [
    statusFieldOptionSourceStatic,
    statusFieldOptionSourceUsers,
    statusFieldOptionSourceClients,
    statusFieldOptionSourceAdmins,
    statusFieldOptionSourceDrivers,
    statusFieldOptionSourceHelpers,
    statusFieldOptionSourceVehicleMakes,
    statusFieldOptionSourceVehicleTypes,
    statusFieldOptionSourceVehicleSizes,
    statusFieldOptionSourceStatuses,
    statusFieldOptionSourceForms,
    statusFieldOptionSourceFields,
    statusFieldOptionSourceBookings,
  ];

  List<StatusForm> forms = [];
  StatusForm? selectedForm;
  List<StatusField> fields = [];
  List<StatusField> fieldLibrary = [];
  List<Status> statuses = [];
  StatusField? draftNewField;
  Status? draftNewStatus;
  final Map<String, List<StatusField>> _fieldsByFormId = {};
  bool isLoading = false;
  String? errorMessage;
  String? successMessage;
  bool isPreviewVisible = true;
  String busyMessage = 'Loading, please wait ...';

  Future<void> loadForms() async {
    busyMessage = 'Loading flows...';
    isLoading = true;
    notifyListeners();

    try {
      forms = await _repository.getStatusForms();
      fieldLibrary = await _optionResolver.hydrateFields(
        (await _repository.getAllFields())
            .map((field) => field.copyWith())
            .toList(),
      );
      statuses = (await _repository.getStatuses())
          .map((status) => status.copyWith())
          .toList();
      _sortFormsLatestFirst();
      _sortFieldsLatestFirst();
      _sortStatusesLatestFirst();
      final nextFieldsByFormId = <String, List<StatusField>>{};
      final loadFieldsTasks = forms.map((form) async {
        final formId = form.id ?? '';
        if (formId.isEmpty) {
          return;
        }
        final loadedFields = await _repository.getFields(formId);
        nextFieldsByFormId[formId] = await _optionResolver.hydrateFields(
          loadedFields.map((field) => field.copyWith()).toList(),
        );
      });
      await Future.wait(loadFieldsTasks);
      _fieldsByFormId
        ..clear()
        ..addAll(nextFieldsByFormId);
      if (forms.isEmpty) {
        selectedForm = null;
        fields = [];
        isPreviewVisible = true;
      } else if (selectedForm == null) {
        await selectForm(forms.first, notify: false, notifyWhenLoaded: false);
      }
      errorMessage = null;
      _cacheSnapshot();
    } catch (error) {
      errorMessage = userFacingErrorMessage(
        error,
        fallback: 'We could not load the flows right now.',
      );
      _cachedErrorMessage = errorMessage;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> selectForm(
    StatusForm form, {
    bool notify = true,
    bool notifyWhenLoaded = true,
  }) async {
    final selectedId = form.id ?? '';
    selectedForm = form.copyWith(
      dependencies: form.dependencies
          .map((dependency) => dependency.copyWith())
          .toList(),
    );
    final cachedFields = _fieldsByFormId[selectedId];
    fields = cachedFields == null
        ? []
        : cachedFields.map((field) => field.copyWith()).toList();
    successMessage = null;
    errorMessage = null;
    if (notify) {
      notifyListeners();
    }

    if (cachedFields != null || selectedId.isEmpty) {
      return;
    }

    final loadedFields = await _optionResolver.hydrateFields(
      (await _repository.getFields(
        selectedId,
      )).map((field) => field.copyWith()).toList(),
    );

    if ((selectedForm?.id ?? '') != selectedId) {
      return;
    }

    _fieldsByFormId[selectedId] = loadedFields
        .map((field) => field.copyWith())
        .toList();
    fields = loadedFields;
    if (notifyWhenLoaded) {
      _cacheSnapshot();
      notifyListeners();
    }
  }

  void _cacheSnapshot() {
    _cachedForms = List<StatusForm>.from(forms);
    _cachedSelectedForm = selectedForm;
    _cachedFields = List<StatusField>.from(fields);
    _cachedFieldLibrary = List<StatusField>.from(fieldLibrary);
    _cachedStatuses = List<Status>.from(statuses);
    _cachedFieldsByFormId = _fieldsByFormId.map(
      (key, value) => MapEntry(key, List<StatusField>.from(value)),
    );
    _cachedErrorMessage = errorMessage;
    _cachedSuccessMessage = successMessage;
    _cachedIsPreviewVisible = isPreviewVisible;
  }

  void createNewForm({bool notify = true}) {
    final now = DateTime.now();
    selectedForm = StatusForm(
      id: _nextFormId(),
      roles: const [],
      isMainForm: true,
      dependencies: const [],
      blockedMessage: '',
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );
    fields = [];
    errorMessage = null;
    successMessage = null;
    isPreviewVisible = true;
    if (notify) {
      notifyListeners();
    }
  }

  bool get hasDraftNewForm {
    final form = selectedForm;
    if (form == null) {
      return false;
    }
    final selectedId = form.id ?? '';
    return forms.every((item) => (item.id ?? '') != selectedId);
  }

  void ensureNewFormDraft() {
    if (hasDraftNewForm) {
      notifyListeners();
      return;
    }
    createNewForm();
  }

  Future<void> duplicateForm(StatusForm form) async {
    final now = DateTime.now();
    final newId = _nextFormId();
    selectedForm = form.copyWith(
      id: newId,
      currentStatusKey: '${form.currentStatusKey ?? 'status'}_copy',
      roles: [...form.resolvedRoles],
      fields: form.fields.map((field) => field.copyWith()).toList(),
      dependencies: form.dependencies
          .map((dependency) => dependency.copyWith())
          .toList(),
      createdAt: now,
      updatedAt: now,
    );
    fields = await _optionResolver.hydrateFields(
      await _repository.getFields(form.id ?? ''),
    );
    successMessage = 'Status form duplicated. Review before saving.';
    errorMessage = null;
    notifyListeners();
  }

  String _nextFormId() {
    var maxId = 0;
    for (final form in forms) {
      final parsed = int.tryParse(form.id ?? '');
      if (parsed != null && parsed > maxId) {
        maxId = parsed;
      }
    }
    final selectedParsed = int.tryParse(selectedForm?.id ?? '');
    if (selectedParsed != null && selectedParsed > maxId) {
      maxId = selectedParsed;
    }
    return '${maxId + 1}';
  }

  String get nextFieldId {
    var maxId = 0;
    for (final field in fieldLibrary) {
      final parsed = int.tryParse(field.id ?? '');
      if (parsed != null && parsed > maxId) {
        maxId = parsed;
      }
    }
    return '${maxId + 1}';
  }

  void updateFormField(String field, dynamic value) {
    final form = selectedForm;
    if (form == null) {
      return;
    }
    final stringValue = value is String ? value : null;

    selectedForm = switch (field) {
      'role' => form.copyWith(
        role: stringValue,
        roles: stringValue == null || stringValue.trim().isEmpty
            ? const []
            : [stringValue.trim()],
      ),
      'isMainForm' => form.copyWith(isMainForm: value as bool?),
      'currentStatusKey' => form.copyWith(currentStatusKey: stringValue),
      'nextStatusKey' => form.copyWith(nextStatusKey: stringValue),
      'statusSubtext' => form.copyWith(statusSubtext: stringValue),
      'buttonText' => form.copyWith(buttonText: stringValue),
      'blockedMessage' => form.copyWith(blockedMessage: stringValue),
      'isActive' => form.copyWith(isActive: value as bool?),
      _ => form,
    };

    successMessage = null;
    errorMessage = null;
    notifyListeners();
  }

  void updateFormRoles(List<String> roles) {
    final form = selectedForm;
    if (form == null) {
      return;
    }
    final normalizedRoles = roles
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    selectedForm = form.copyWith(
      role: normalizedRoles.isEmpty ? null : normalizedRoles.first,
      roles: normalizedRoles,
    );
    successMessage = null;
    errorMessage = null;
    notifyListeners();
  }

  void addDependency() {
    final form = selectedForm;
    if (form == null) {
      return;
    }

    final nextDependencies = [...form.dependencies, const StatusDependency()];
    selectedForm = form.copyWith(dependencies: nextDependencies);
    notifyListeners();
  }

  void updateDependency(int index, {String? statusType, String? statusKey}) {
    final form = selectedForm;
    if (form == null || index < 0 || index >= form.dependencies.length) {
      return;
    }

    final nextDependencies = [...form.dependencies];
    nextDependencies[index] = nextDependencies[index].copyWith(
      statusType: statusType,
      statusKey: statusKey,
    );
    selectedForm = form.copyWith(dependencies: nextDependencies);
    notifyListeners();
  }

  void removeDependency(int index) {
    final form = selectedForm;
    if (form == null || index < 0 || index >= form.dependencies.length) {
      return;
    }

    final nextDependencies = [...form.dependencies]..removeAt(index);
    selectedForm = form.copyWith(dependencies: nextDependencies);
    notifyListeners();
  }

  void assignField(String fieldId) {
    final form = selectedForm;
    if (form == null || form.fields.any((field) => field.id == fieldId)) {
      return;
    }

    final assignedField = fieldById(fieldId);
    if (assignedField == null) {
      return;
    }

    final nextAssignedField = assignedField.copyWith(
      sortOrder: fields.length + 1,
    );
    selectedForm = form.copyWith(
      fields: [
        ...form.fields.map((field) => field.copyWith()),
        nextAssignedField,
      ],
    );
    fields = [...fields, nextAssignedField];
    notifyListeners();
  }

  void removeAssignedField(int index) {
    final form = selectedForm;
    if (form == null || index < 0 || index >= fields.length) {
      return;
    }

    final removedId = fields[index].id;
    fields = [...fields]..removeAt(index);
    selectedForm = form.copyWith(
      fields: form.fields
          .where((field) => field.id != removedId)
          .map((field) => field.copyWith())
          .toList(),
      fieldOverrides: Map<String, StatusFieldOverride>.from(form.fieldOverrides)
        ..remove(removedId),
    );
    notifyListeners();
  }

  void reorderAssignedField(int oldIndex, int newIndex) {
    final form = selectedForm;
    if (form == null || oldIndex < 0 || oldIndex >= fields.length) {
      return;
    }

    var targetIndex = newIndex;
    if (targetIndex > oldIndex) {
      targetIndex -= 1;
    }
    if (targetIndex < 0 || targetIndex >= fields.length) {
      return;
    }

    final nextFields = [...fields];
    final movedField = nextFields.removeAt(oldIndex);
    nextFields.insert(targetIndex, movedField);

    fields = nextFields
        .asMap()
        .entries
        .map((entry) => entry.value.copyWith(sortOrder: entry.key + 1))
        .toList();
    selectedForm = form.copyWith(
      fields: fields.map((field) => field.copyWith()).toList(),
    );
    notifyListeners();
  }

  void addLibraryField() {
    final fieldIndex = fieldLibrary.length + 1;
    fieldLibrary = [
      ...fieldLibrary,
      StatusField(
        id: nextFieldId,
        key: _generateFieldKey(fieldIndex),
        required: false,
        min: 0,
        max: 0,
        options: const [],
        sortOrder: fieldIndex,
        isActive: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];
    notifyListeners();
  }

  void updateLibraryField(int index, String property, dynamic value) {
    if (index < 0 || index >= fieldLibrary.length) {
      return;
    }

    final field = fieldLibrary[index];
    final updatedField = switch (property) {
      'key' => field.copyWith(key: value as String?),
      'type' => field.copyWith(type: value as String?),
      'title' => field.copyWith(title: value as String?),
      'subtitle' => field.copyWith(subtitle: value as String?),
      'instructions' => field.copyWith(instructions: value as String?),
      'placeholder' => field.copyWith(placeholder: value as String?),
      'required' => field.copyWith(required: value as bool?),
      'min' => field.copyWith(min: value as int?),
      'max' => field.copyWith(max: value as int?),
      'options' => field.copyWith(options: value as List<String>),
      'optionSourceKey' => field.copyWith(
        optionSourceKey: (value as String?) == statusFieldOptionSourceStatic
            ? null
            : value,
      ),
      'requiredError' => field.copyWith(requiredError: value as String?),
      'validationError' => field.copyWith(validationError: value as String?),
      'sortOrder' => field.copyWith(sortOrder: value as int?),
      'isActive' => field.copyWith(isActive: value as bool?),
      _ => field,
    };
    fieldLibrary[index] = _normalizeFieldPlaceholder(updatedField);
    notifyListeners();
  }

  StatusField _normalizeFieldPlaceholder(StatusField field) {
    final fieldType = (field.type ?? '').trim();
    if (fieldType == 'photo') {
      final currentPlaceholder = field.placeholder?.trim() ?? '';
      if (currentPlaceholder.isEmpty) {
        return field.copyWith(placeholder: 'Photo');
      }
      return field;
    }
    if (fieldType == 'dropdown') {
      final isRequired = field.required ?? false;
      if (isRequired) {
        return field.copyWith(placeholder: null);
      }

      final currentPlaceholder = field.placeholder?.trim() ?? '';
      if (currentPlaceholder.isEmpty) {
        return field.copyWith(placeholder: 'Optional');
      }
    }

    return field;
  }

  Future<void> saveLibraryField(StatusField field) async {
    busyMessage = 'Saving field...';
    isLoading = true;
    notifyListeners();
    try {
      final now = DateTime.now();
      await _repository.saveField(
        field.copyWith(updatedAt: now, createdAt: field.createdAt ?? now),
      );
      draftNewField = null;
      await loadForms();
    } finally {
      if (isLoading) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> deleteLibraryField(StatusField field) async {
    final fieldId = field.id ?? '';
    if (fieldId.isEmpty) {
      return;
    }
    busyMessage = 'Deleting field...';
    isLoading = true;
    notifyListeners();
    try {
      await _repository.deleteField(fieldId);
      await loadForms();
    } finally {
      if (isLoading) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> setLibraryFieldActive(StatusField field, bool isActive) async {
    final fieldId = field.id ?? '';
    if (fieldId.isEmpty) {
      return;
    }
    busyMessage = isActive ? 'Activating field...' : 'Deactivating field...';
    isLoading = true;
    notifyListeners();
    try {
      final now = DateTime.now();
      await _repository.saveField(
        field.copyWith(
          isActive: isActive,
          updatedAt: now,
          createdAt: field.createdAt ?? now,
        ),
      );
      await loadForms();
    } finally {
      if (isLoading) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> saveStatus(Status status) async {
    busyMessage = 'Saving status...';
    isLoading = true;
    notifyListeners();
    try {
      final now = DateTime.now();
      await _repository.saveStatus(
        status.copyWith(updatedAt: now, createdAt: status.createdAt ?? now),
      );
      draftNewStatus = null;
      await loadForms();
    } finally {
      if (isLoading) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> deleteStatus(Status status) async {
    final statusId = status.id ?? '';
    if (statusId.isEmpty) {
      return;
    }
    busyMessage = 'Deleting status...';
    isLoading = true;
    notifyListeners();
    try {
      await _repository.deleteStatus(statusId);
      await loadForms();
    } finally {
      if (isLoading) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> setStatusActive(Status status, bool isActive) async {
    final statusId = status.id ?? '';
    if (statusId.isEmpty) {
      return;
    }
    busyMessage = isActive ? 'Activating status...' : 'Deactivating status...';
    isLoading = true;
    notifyListeners();
    try {
      final now = DateTime.now();
      await _repository.saveStatus(
        status.copyWith(
          isActive: isActive,
          updatedAt: now,
          createdAt: status.createdAt ?? now,
        ),
      );
      await loadForms();
    } finally {
      if (isLoading) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  Status createDraftStatus() {
    final now = DateTime.now();
    final nextId =
        statuses
            .map((status) => int.tryParse(status.id ?? ''))
            .whereType<int>()
            .fold<int>(0, (max, value) => value > max ? value : max) +
        1;
    return Status(
      id: '$nextId',
      applicableRoles: const [],
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );
  }

  void updateDraftNewField(StatusField field) {
    draftNewField = field;
  }

  void clearDraftNewField() {
    draftNewField = null;
  }

  void updateDraftNewStatus(Status status) {
    draftNewStatus = status;
  }

  void clearDraftNewStatus() {
    draftNewStatus = null;
  }

  List<Status> statusesForRole(String? role) {
    if (role == null || role.isEmpty) {
      return statuses;
    }
    return statusesForRoles([role]);
  }

  List<Status> statusesForRoles(List<String> roles) {
    final normalizedRoles = roles
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (normalizedRoles.isEmpty) {
      return statuses;
    }

    return statuses.where((status) {
      if (status.isActive == false) {
        return false;
      }
      return status.applicableRoles.isEmpty ||
          normalizedRoles.every(status.applicableRoles.contains);
    }).toList();
  }

  List<Status> statusesForStatusType(String? statusType) {
    final role = switch (statusType) {
      'client_status' => 'client',
      'driver_status' => 'driver',
      'helper_status' => 'helper',
      _ => null,
    };
    return statusesForRole(role);
  }

  List<StatusField> get availableFieldsForSelection {
    final assignedIds =
        selectedForm?.fields
            .map((field) => field.id)
            .whereType<String>()
            .toSet() ??
        <String>{};
    return fieldLibrary
        .where((field) => !assignedIds.contains(field.id))
        .toList();
  }

  StatusField? fieldById(String? fieldId) {
    if (fieldId == null || fieldId.isEmpty) {
      return null;
    }
    final matches = fieldLibrary.where((field) => field.id == fieldId);
    return matches.isEmpty ? null : matches.first;
  }

  StatusFieldOverride? fieldOverrideFor(String? fieldId) {
    final form = selectedForm;
    if (form == null || fieldId == null || fieldId.isEmpty) {
      return null;
    }
    return form.fieldOverrides[fieldId];
  }

  bool effectiveRequiredForField(StatusField field) {
    return field.required ?? false;
  }

  void updateAssignedFieldRequired(String fieldId, bool required) {
    final form = selectedForm;
    if (form == null || fieldId.trim().isEmpty) {
      return;
    }
    final baseField = fieldById(fieldId);
    final baseRequired = baseField?.required;
    final currentOverride = form.fieldOverrides[fieldId];
    final nextOverrides = Map<String, StatusFieldOverride>.from(
      form.fieldOverrides,
    );

    final nextOverride = StatusFieldOverride(
      required: required == (baseRequired ?? false) ? null : required,
      placeholder: currentOverride?.placeholder,
    );

    if (nextOverride.required == null && nextOverride.placeholder == null) {
      nextOverrides.remove(fieldId);
    } else {
      nextOverrides[fieldId] = nextOverride;
    }

    selectedForm = form.copyWith(fieldOverrides: nextOverrides);
    fields = fields.map((field) {
      if (field.id != fieldId) {
        return field;
      }
      return field.copyWith(required: required);
    }).toList();
    notifyListeners();
  }

  void resetForm() {
    if (forms.isNotEmpty) {
      selectForm(forms.first);
      return;
    }
    createNewForm();
  }

  void clearSelection() {
    selectedForm = null;
    fields = [];
    errorMessage = null;
    successMessage = null;
    isPreviewVisible = true;
    notifyListeners();
  }

  void togglePreview() {
    isPreviewVisible = !isPreviewVisible;
    notifyListeners();
  }

  bool validateBeforeSave() {
    final form = selectedForm;
    if (form == null) {
      errorMessage = 'No form selected.';
      notifyListeners();
      return false;
    }

    if (form.resolvedRoles.isEmpty) {
      errorMessage = 'At least one role is required.';
      notifyListeners();
      return false;
    }

    if (_isBlank(form.currentStatusKey)) {
      errorMessage = 'Current Status Key is required.';
      notifyListeners();
      return false;
    }

    final hasNextStatus = !_isBlank(form.nextStatusKey);

    if (hasNextStatus && _isBlank(form.buttonText)) {
      errorMessage = 'Button Text is required.';
      notifyListeners();
      return false;
    }

    final knownStatusKeys = statuses
        .map((status) => status.key?.trim())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet();
    if (!knownStatusKeys.contains(form.currentStatusKey?.trim())) {
      errorMessage = 'Current Status Key must exist in Statuses.';
      notifyListeners();
      return false;
    }

    if (hasNextStatus &&
        !knownStatusKeys.contains(form.nextStatusKey?.trim())) {
      errorMessage = 'Next Status Key must exist in Statuses.';
      notifyListeners();
      return false;
    }

    final seenKeys = <String>{};
    for (final field in fields) {
      if (_isBlank(field.key) ||
          _isBlank(field.type) ||
          _isBlank(field.title)) {
        errorMessage = 'Each field must have key, type, and title.';
        notifyListeners();
        return false;
      }

      final normalizedKey = field.key!.trim();
      if (seenKeys.contains(normalizedKey)) {
        errorMessage = 'Field keys must be unique.';
        notifyListeners();
        return false;
      }
      seenKeys.add(normalizedKey);
    }

    for (final dependency in form.dependencies) {
      if (_isBlank(dependency.statusType)) {
        errorMessage =
            'At least one role must be selected for each dependency.';
        notifyListeners();
        return false;
      }
      if (_isBlank(dependency.statusKey)) {
        errorMessage = 'Dependency Required Status Key is required.';
        notifyListeners();
        return false;
      }
      if (!knownStatusKeys.contains(dependency.statusKey?.trim())) {
        errorMessage = 'Dependency Required Status Key must exist in Statuses.';
        notifyListeners();
        return false;
      }
    }

    if (form.dependencies.isNotEmpty && _isBlank(form.blockedMessage)) {
      errorMessage =
          'Blocked Message is required when dependencies are present.';
      notifyListeners();
      return false;
    }

    errorMessage = null;
    notifyListeners();
    return true;
  }

  Future<void> saveForm() async {
    final form = selectedForm;
    if (form == null || !validateBeforeSave()) {
      return;
    }

    busyMessage = 'Saving flow...';
    isLoading = true;
    notifyListeners();

    try {
      final now = DateTime.now();
      final normalizedForm = form.copyWith(
        blockedMessage: form.dependencies.isEmpty ? '' : form.blockedMessage,
        updatedAt: now,
        createdAt: form.createdAt ?? now,
      );
      final normalizedFields = fields.asMap().entries.map((entry) {
        return entry.value.copyWith(sortOrder: entry.key + 1);
      }).toList();

      await _repository.saveStatusForm(normalizedForm);
      await _repository.saveFields(normalizedForm.id ?? '', normalizedFields);
      _fieldsByFormId[normalizedForm.id ?? ''] = normalizedFields
          .map((field) => field.copyWith())
          .toList();
      selectedForm = normalizedForm;
      fields = normalizedFields;
      forms = await _repository.getStatusForms();
      _sortFormsLatestFirst();
      successMessage = 'Status form saved successfully.';
      errorMessage = null;
    } catch (error) {
      errorMessage = userFacingErrorMessage(
        error,
        fallback: 'We could not save the flow right now.',
      );
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteForm(StatusForm form) async {
    busyMessage = 'Deleting flow...';
    isLoading = true;
    notifyListeners();
    try {
      await _repository.deleteStatusForm(form.id ?? '');
      _fieldsByFormId.remove(form.id ?? '');
      forms = await _repository.getStatusForms();
      _sortFormsLatestFirst();
      if (forms.isEmpty) {
        createNewForm(notify: false);
      } else {
        await selectForm(forms.first, notify: false, notifyWhenLoaded: false);
      }
      successMessage = 'Status form deleted.';
      errorMessage = null;
    } catch (error) {
      errorMessage = userFacingErrorMessage(
        error,
        fallback: 'We could not delete the flow right now.',
      );
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deactivateForm(StatusForm form) async {
    busyMessage = 'Deactivating flow...';
    isLoading = true;
    notifyListeners();
    try {
      await _repository.deactivateStatusForm(form.id ?? '');
      forms = await _repository.getStatusForms();
      _sortFormsLatestFirst();
      if (selectedForm?.id == form.id) {
        final matches = forms.where((item) => item.id == form.id);
        final fresh = matches.isEmpty ? null : matches.first;
        if (fresh != null) {
          await selectForm(fresh, notify: false, notifyWhenLoaded: false);
        }
      }
      successMessage = 'Status form deactivated.';
      errorMessage = null;
    } catch (error) {
      errorMessage = userFacingErrorMessage(
        error,
        fallback: 'We could not deactivate the flow right now.',
      );
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  StatusFormEngine get engine => _engine;

  String _generateFieldKey(int number) => 'field_$number';

  void _sortFormsLatestFirst() {
    forms.sort(_compareFormsForDisplay);
  }

  int _compareFormsForDisplay(StatusForm a, StatusForm b) {
    final parsedAId = int.tryParse(a.id ?? '');
    final parsedBId = int.tryParse(b.id ?? '');
    if (parsedAId != null && parsedBId != null) {
      return parsedBId.compareTo(parsedAId);
    }

    return (b.id ?? '').compareTo(a.id ?? '');
  }

  void _sortFieldsLatestFirst() {
    fieldLibrary.sort(
      (a, b) =>
          _createdAtLatestFirstCompare(a.createdAt, b.createdAt, a.id, b.id),
    );
  }

  void _sortStatusesLatestFirst() {
    statuses.sort(
      (a, b) =>
          _createdAtLatestFirstCompare(a.createdAt, b.createdAt, a.id, b.id),
    );
  }

  int _createdAtLatestFirstCompare(
    DateTime? aCreated,
    DateTime? bCreated,
    String? aId,
    String? bId,
  ) {
    final createdComparison = _compareDateLatestFirst(aCreated, bCreated);
    if (createdComparison != 0) {
      return createdComparison;
    }

    final parsedAId = int.tryParse(aId ?? '');
    final parsedBId = int.tryParse(bId ?? '');
    if (parsedAId != null && parsedBId != null) {
      return parsedBId.compareTo(parsedAId);
    }
    return (bId ?? '').compareTo(aId ?? '');
  }

  int _compareDateLatestFirst(DateTime? a, DateTime? b) {
    if (a == null && b == null) {
      return 0;
    }
    if (a == null) {
      return 1;
    }
    if (b == null) {
      return -1;
    }
    return b.compareTo(a);
  }

  static bool _isBlank(String? value) => value == null || value.trim().isEmpty;
}
