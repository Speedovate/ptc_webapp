import 'dart:async';

import 'package:stacked/stacked.dart';
import 'package:webapp/models/dispatcher_access_config.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/models/status.dart';
import 'package:webapp/models/status_form.dart';
import 'package:webapp/requests/status.request.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/repositories/interfaces/status_form_repository.dart';
import 'package:webapp/services/app_warmup_service.dart';
import 'package:webapp/services/role_access_service.dart';
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
    _hasLoadedOnce = _cachedHasLoadedOnce;
    _fieldsByFormId.addAll(
      _cachedFieldsByFormId.map(
        (key, value) => MapEntry(key, List<StatusField>.from(value)),
      ),
    );
    _log('view-model created');
  }

  final StatusFormRepository _repository;
  final StatusFormEngine _engine;
  final RoleAccessService _roleAccessService = RoleAccessService.instance;
  final StatusFieldOptionResolver _optionResolver = StatusFieldOptionResolver();
  final AppWarmupService _warmupService = AppWarmupService.instance;
  StreamSubscription<void>? _statusCacheUpdatesSubscription;
  static List<StatusForm> _cachedForms = const [];
  static StatusForm? _cachedSelectedForm;
  static List<StatusField> _cachedFields = const [];
  static List<StatusField> _cachedFieldLibrary = const [];
  static List<Status> _cachedStatuses = const [];
  static Map<String, List<StatusField>> _cachedFieldsByFormId = const {};
  static String? _cachedErrorMessage;
  static String? _cachedSuccessMessage;
  static bool _cachedIsPreviewVisible = true;
  static bool _cachedHasLoadedOnce = false;

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
    _cachedHasLoadedOnce = false;
  }

  static List<String> get roleOptions =>
      RoleAccessService.instance.workflowRoleKeys;
  static const dependencyStatusTypes = ['client_status'];
  static const formStatusOrder = [
    'book',
    'pending',
    'assigned',
    'ongoing',
    'delivered',
    'check',
    'empty',
    'return',
    'confirm',
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
    'search_dropdown',
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
    statusFieldOptionSourceChassis,
    statusFieldOptionSourceStatuses,
    statusFieldOptionSourceForms,
    statusFieldOptionSourceFields,
    statusFieldOptionSourceBookings,
    statusFieldOptionSourcePuertoPrincesaBarangays,
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
  bool _hasLoadedOnce = false;
  String? errorMessage;
  String? successMessage;
  bool isPreviewVisible = true;
  String busyMessage = 'Loading, please wait ...';
  bool _isRealtimeRefreshing = false;
  bool get showBlockingLoading =>
      isLoading &&
      !_hasLoadedOnce &&
      forms.isEmpty &&
      _cachedForms.isEmpty &&
      fieldLibrary.isEmpty &&
      _cachedFieldLibrary.isEmpty &&
      statuses.isEmpty &&
      _cachedStatuses.isEmpty;
  bool get canReadForms =>
      _roleAccessService.canAccess(DispatcherAccessCapability.formsRead);
  bool get canCreateForms =>
      _roleAccessService.canAccess(DispatcherAccessCapability.formsCreate);
  bool get canUpdateForms =>
      _roleAccessService.canAccess(DispatcherAccessCapability.formsUpdate);
  bool get canDeleteForms =>
      _roleAccessService.canAccess(DispatcherAccessCapability.formsDelete);
  bool get canReadFields =>
      _roleAccessService.canAccess(DispatcherAccessCapability.fieldsRead);
  bool get canCreateFields =>
      _roleAccessService.canAccess(DispatcherAccessCapability.fieldsCreate);
  bool get canUpdateFields =>
      _roleAccessService.canAccess(DispatcherAccessCapability.fieldsUpdate);
  bool get canDeleteFields =>
      _roleAccessService.canAccess(DispatcherAccessCapability.fieldsDelete);
  bool get canReadStatuses =>
      _roleAccessService.canAccess(DispatcherAccessCapability.statusesRead);
  bool get canCreateStatuses =>
      _roleAccessService.canAccess(DispatcherAccessCapability.statusesCreate);
  bool get canUpdateStatuses =>
      _roleAccessService.canAccess(DispatcherAccessCapability.statusesUpdate);
  bool get canDeleteStatuses =>
      _roleAccessService.canAccess(DispatcherAccessCapability.statusesDelete);
  bool get canReadAnyFlowAdminData =>
      canReadForms || canReadFields || canReadStatuses;

  Future<void> loadFormsPage() async {
    _ensureStatusRealtimeSubscription();
    if (!canReadForms) {
      errorMessage = 'You do not have access to view forms.';
      _log('load forms-page denied');
      notifyListeners();
      return;
    }
    busyMessage = 'Loading forms ...';
    final hasSharedPrimaryData = StatusRequest.hasResolvedForms;
    final hasVisiblePrimaryData =
        forms.isNotEmpty || _cachedForms.isNotEmpty || hasSharedPrimaryData;
    final shouldShowLoadingState = !_hasLoadedOnce && !hasVisiblePrimaryData;
    if (shouldShowLoadingState) {
      isLoading = true;
      _log('overlay show section=forms');
      notifyListeners();
    }
    _log(
      'load start section=forms visible=${!shouldShowLoadingState} localForms=${forms.length} cachedForms=${_cachedForms.length} sharedForms=$hasSharedPrimaryData',
    );
    try {
      if (hasSharedPrimaryData && forms.isEmpty) {
        forms = List<StatusForm>.from(StatusRequest.hydratedFormsSnapshot);
        _sortFormsLatestFirst();
        if (forms.isEmpty) {
          selectedForm = null;
          fields = [];
        } else {
          selectedForm ??= forms.first;
        }
        _log('prime shared section=forms count=${forms.length}');
        notifyListeners();
      }
      await _warmupService.warmStatusForms();
      forms = await _repository.getStatusForms();
      _sortFormsLatestFirst();
      if (forms.isEmpty) {
        selectedForm = null;
        fields = [];
      } else {
        selectedForm ??= forms.first;
      }
      errorMessage = null;
      _cachedForms = List<StatusForm>.from(forms);
      _hasLoadedOnce = true;
      _cachedHasLoadedOnce = true;
      _log('load resolved section=forms count=${forms.length}');
      if (shouldShowLoadingState) {
        isLoading = false;
        _log('overlay hide section=forms reason=primary-data-ready');
      }
      notifyListeners();
      unawaited(_hydrateFormsSupportingDataInBackground());
    } catch (error) {
      _log('load error section=forms error=$error');
      errorMessage = userFacingErrorMessage(
        error,
        fallback: 'We could not load the forms right now.',
      );
      _cachedErrorMessage = errorMessage;
      _hasLoadedOnce = true;
      _cachedHasLoadedOnce = true;
      if (shouldShowLoadingState) {
        isLoading = false;
        _log('overlay hide section=forms reason=error');
      }
      notifyListeners();
    } finally {
      _log(
        'load finish section=forms loading=$isLoading forms=${forms.length} selected=${selectedForm?.id ?? "-"} error=${errorMessage ?? "-"}',
      );
    }
  }

  Future<void> loadFieldsPage() async {
    _ensureStatusRealtimeSubscription();
    if (!canReadFields) {
      errorMessage = 'You do not have access to view fields.';
      _log('load fields-page denied');
      notifyListeners();
      return;
    }
    busyMessage = 'Loading fields ...';
    final hasVisiblePrimaryData =
        fieldLibrary.isNotEmpty ||
        _cachedFieldLibrary.isNotEmpty ||
        StatusRequest.hasResolvedFields;
    final shouldShowLoadingState = !_hasLoadedOnce && !hasVisiblePrimaryData;
    if (shouldShowLoadingState) {
      isLoading = true;
      _log('overlay show section=fields');
      notifyListeners();
    }
    _log(
      'load start section=fields visible=${!shouldShowLoadingState} localFields=${fieldLibrary.length} cachedFields=${_cachedFieldLibrary.length} sharedFields=${StatusRequest.hasResolvedFields}',
    );
    try {
      if (StatusRequest.hasResolvedFields && fieldLibrary.isEmpty) {
        fieldLibrary = List<StatusField>.from(
          StatusRequest.hydratedFieldsSnapshot,
        );
        _sortFieldsLatestFirst();
        _log('prime shared section=fields count=${fieldLibrary.length}');
        notifyListeners();
      }
      await _warmupService.warmStatusFields();
      fieldLibrary = (await _repository.getAllFields())
          .map((field) => field.copyWith())
          .toList();
      _sortFieldsLatestFirst();
      errorMessage = null;
      _cachedFieldLibrary = List<StatusField>.from(fieldLibrary);
      _hasLoadedOnce = true;
      _cachedHasLoadedOnce = true;
      _log('load resolved section=fields count=${fieldLibrary.length}');
    } catch (error) {
      _log('load error section=fields error=$error');
      errorMessage = userFacingErrorMessage(
        error,
        fallback: 'We could not load the fields right now.',
      );
      _cachedErrorMessage = errorMessage;
      _hasLoadedOnce = true;
      _cachedHasLoadedOnce = true;
    } finally {
      if (shouldShowLoadingState) {
        isLoading = false;
        _log(
          'overlay hide section=fields reason=${errorMessage == null ? "primary-data-ready" : "error"}',
        );
      }
      _log(
        'load finish section=fields loading=$isLoading fields=${fieldLibrary.length} error=${errorMessage ?? "-"}',
      );
      notifyListeners();
    }
  }

  Future<void> loadStatusesPage() async {
    _ensureStatusRealtimeSubscription();
    if (!canReadStatuses) {
      errorMessage = 'You do not have access to view statuses.';
      _log('load statuses-page denied');
      notifyListeners();
      return;
    }
    busyMessage = 'Loading statuses ...';
    final hasVisiblePrimaryData =
        statuses.isNotEmpty ||
        _cachedStatuses.isNotEmpty ||
        StatusRequest.hasResolvedStatuses;
    final shouldShowLoadingState = !_hasLoadedOnce && !hasVisiblePrimaryData;
    if (shouldShowLoadingState) {
      isLoading = true;
      _log('overlay show section=statuses');
      notifyListeners();
    }
    _log(
      'load start section=statuses visible=${!shouldShowLoadingState} localStatuses=${statuses.length} cachedStatuses=${_cachedStatuses.length} sharedStatuses=${StatusRequest.hasResolvedStatuses}',
    );
    try {
      if (StatusRequest.hasResolvedStatuses && statuses.isEmpty) {
        statuses = List<Status>.from(StatusRequest.hydratedStatusesSnapshot);
        _sortStatusesLatestFirst();
        _log('prime shared section=statuses count=${statuses.length}');
        notifyListeners();
      }
      await _warmupService.warmStatuses();
      statuses = (await _repository.getStatuses())
          .map((status) => status.copyWith())
          .toList();
      _sortStatusesLatestFirst();
      errorMessage = null;
      _cachedStatuses = List<Status>.from(statuses);
      _hasLoadedOnce = true;
      _cachedHasLoadedOnce = true;
      _log('load resolved section=statuses count=${statuses.length}');
    } catch (error) {
      _log('load error section=statuses error=$error');
      errorMessage = userFacingErrorMessage(
        error,
        fallback: 'We could not load the statuses right now.',
      );
      _cachedErrorMessage = errorMessage;
      _hasLoadedOnce = true;
      _cachedHasLoadedOnce = true;
    } finally {
      if (shouldShowLoadingState) {
        isLoading = false;
        _log(
          'overlay hide section=statuses reason=${errorMessage == null ? "primary-data-ready" : "error"}',
        );
      }
      _log(
        'load finish section=statuses loading=$isLoading statuses=${statuses.length} error=${errorMessage ?? "-"}',
      );
      notifyListeners();
    }
  }

  Future<void> loadForms() async {
    _ensureStatusRealtimeSubscription();
    if (!canReadAnyFlowAdminData) {
      errorMessage = 'You do not have access to view flows.';
      _log('load flows denied');
      notifyListeners();
      return;
    }
    busyMessage = 'Loading flows ...';
    final hasVisiblePrimaryData =
        forms.isNotEmpty ||
        _cachedForms.isNotEmpty ||
        fields.isNotEmpty ||
        _cachedFields.isNotEmpty ||
        fieldLibrary.isNotEmpty ||
        _cachedFieldLibrary.isNotEmpty ||
        statuses.isNotEmpty ||
        _cachedStatuses.isNotEmpty ||
        StatusRequest.hasResolvedForms ||
        StatusRequest.hasResolvedFields ||
        StatusRequest.hasResolvedStatuses;
    final shouldShowLoadingState = !_hasLoadedOnce && !hasVisiblePrimaryData;
    if (shouldShowLoadingState) {
      isLoading = true;
      _log('overlay show section=flows');
    }
    _log(
      'load start section=flows visible=${!shouldShowLoadingState} forms=${forms.length}/${_cachedForms.length} fieldLibrary=${fieldLibrary.length}/${_cachedFieldLibrary.length} statuses=${statuses.length}/${_cachedStatuses.length} sharedForms=${StatusRequest.hasResolvedForms} sharedFields=${StatusRequest.hasResolvedFields} sharedStatuses=${StatusRequest.hasResolvedStatuses}',
    );
    notifyListeners();

    try {
      if (forms.isEmpty && StatusRequest.hasResolvedForms) {
        forms = List<StatusForm>.from(StatusRequest.hydratedFormsSnapshot);
        _sortFormsLatestFirst();
      }
      if (fieldLibrary.isEmpty && StatusRequest.hasResolvedFields) {
        fieldLibrary = List<StatusField>.from(
          StatusRequest.hydratedFieldsSnapshot,
        );
        _sortFieldsLatestFirst();
      }
      if (statuses.isEmpty && StatusRequest.hasResolvedStatuses) {
        statuses = List<Status>.from(StatusRequest.hydratedStatusesSnapshot);
        _sortStatusesLatestFirst();
      }
      if (forms.isNotEmpty && selectedForm == null) {
        selectedForm = forms.first;
      }
      if (!shouldShowLoadingState) {
        _log(
          'prime shared section=flows forms=${forms.length} fields=${fieldLibrary.length} statuses=${statuses.length}',
        );
        notifyListeners();
      }
      await Future.wait([
        _warmupService.warmStatusForms(),
        _warmupService.warmStatusFields(),
        _warmupService.warmStatuses(),
      ]);
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
      _hasLoadedOnce = true;
      _cachedHasLoadedOnce = true;
      _log(
        'load resolved section=flows forms=${forms.length} fieldLibrary=${fieldLibrary.length} statuses=${statuses.length} selected=${selectedForm?.id ?? "-"}',
      );
    } catch (error) {
      _log('load error section=flows error=$error');
      errorMessage = userFacingErrorMessage(
        error,
        fallback: 'We could not load the flows right now.',
      );
      _cachedErrorMessage = errorMessage;
      _hasLoadedOnce = true;
      _cachedHasLoadedOnce = true;
    } finally {
      if (shouldShowLoadingState) {
        isLoading = false;
        _log(
          'overlay hide section=flows reason=${errorMessage == null ? "primary-data-ready" : "error"}',
        );
      }
      _log(
        'load finish section=flows loading=$isLoading forms=${forms.length} fieldLibrary=${fieldLibrary.length} statuses=${statuses.length} error=${errorMessage ?? "-"}',
      );
      notifyListeners();
    }
  }

  void _ensureStatusRealtimeSubscription() {
    _statusCacheUpdatesSubscription ??= StatusRequest.instance
        .watchStatusCacheUpdates()
        .listen((_) {
          unawaited(_reloadFromRealtime());
        });
  }

  Future<void> _reloadFromRealtime() async {
    if (_isRealtimeRefreshing) {
      return;
    }
    _isRealtimeRefreshing = true;
    try {
      if (forms.isNotEmpty ||
          fieldLibrary.isNotEmpty ||
          statuses.isNotEmpty ||
          _hasLoadedOnce) {
        await loadForms();
      }
    } catch (_) {
      // Keep the current visible state if a live refresh fails.
    } finally {
      _isRealtimeRefreshing = false;
    }
  }

  Future<void> _hydrateFormsSupportingDataInBackground() async {
    _log('supporting reload start section=forms');
    try {
      fieldLibrary = await _optionResolver.hydrateFields(
        (await _repository.getAllFields())
            .map((field) => field.copyWith())
            .toList(),
      );
      statuses = (await _repository.getStatuses())
          .map((status) => status.copyWith())
          .toList();
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
      if (forms.isNotEmpty) {
        selectedForm ??= forms.first;
      }
      if (forms.isNotEmpty && selectedForm != null) {
        final selectedId = selectedForm?.id ?? '';
        final selectedFields = _fieldsByFormId[selectedId];
        if (selectedFields != null) {
          fields = selectedFields.map((field) => field.copyWith()).toList();
        }
      }
      _cacheSnapshot();
      _log(
        'supporting reload done section=forms fieldLibrary=${fieldLibrary.length} statuses=${statuses.length} selectedFields=${fields.length}',
      );
      notifyListeners();
    } catch (error) {
      _log('supporting reload error section=forms error=$error');
      // Keep the currently visible cached form/field data if refresh fails.
    }
  }

  void _log(String message) {
    // Temporary flow diagnostics intentionally removed.
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
    _log(
      'select form id=${selectedId.isEmpty ? "-" : selectedId} fields=${fields.length}',
    );
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
    if (!canCreateForms) {
      throw const AuthFailure('You do not have access to create flows.');
    }
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
      'visibilityControllerKey' => field.copyWith(
        visibilityControllerKey: value as String?,
      ),
      'visibilityOptionValues' => field.copyWith(
        visibilityOptionValues: value as List<String>,
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
    final isRequired = field.required ?? false;
    final currentPlaceholder = field.placeholder?.trim() ?? '';
    if (isRequired && currentPlaceholder.toLowerCase() == 'optional') {
      return field.copyWith(placeholder: null);
    }
    if (fieldType == 'photo') {
      if (currentPlaceholder.isEmpty) {
        return field.copyWith(placeholder: 'Photo');
      }
      return field;
    }
    if (fieldType == 'dropdown' || fieldType == 'search_dropdown') {
      if (isRequired) {
        return field.copyWith(placeholder: null);
      }

      if (currentPlaceholder.isEmpty) {
        return field.copyWith(placeholder: 'Optional');
      }
    }

    if (fieldType != 'photo' &&
        fieldType != 'dropdown' &&
        fieldType != 'search_dropdown') {
      if (!isRequired) {
        if (currentPlaceholder.isEmpty) {
          return field.copyWith(placeholder: 'Optional');
        }
      }
    }

    return field;
  }

  Future<void> saveLibraryField(StatusField field) async {
    final isExisting = _loadedLibraryFieldById(field.id) != null;
    if (isExisting ? !canUpdateFields : !canCreateFields) {
      throw const AuthFailure('You do not have access to save fields.');
    }
    final existingField = _loadedLibraryFieldById(field.id);
    final now = DateTime.now();
    final normalizedField = field.copyWith(
      updatedAt: now,
      createdAt: field.createdAt ?? now,
    );
    if (existingField != null &&
        _sameLibraryFieldContent(existingField, normalizedField)) {
      successMessage = 'Nothing changed.';
      errorMessage = null;
      notifyListeners();
      return;
    }

    busyMessage = 'Saving field ...';
    isLoading = true;
    notifyListeners();
    try {
      await _repository.saveField(normalizedField);
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
    if (!canDeleteFields) {
      throw const AuthFailure('You do not have access to delete fields.');
    }
    final fieldId = field.id ?? '';
    if (fieldId.isEmpty) {
      return;
    }
    busyMessage = 'Deleting field ...';
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
    if (!canUpdateFields) {
      throw const AuthFailure('You do not have access to update fields.');
    }
    final fieldId = field.id ?? '';
    if (fieldId.isEmpty) {
      return;
    }
    busyMessage = isActive ? 'Activating field ...' : 'Deactivating field ...';
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
    final isExisting = _loadedStatusById(status.id) != null;
    if (isExisting ? !canUpdateStatuses : !canCreateStatuses) {
      throw const AuthFailure('You do not have access to save statuses.');
    }
    final existingStatus = _loadedStatusById(status.id);
    final now = DateTime.now();
    final normalizedStatus = status.copyWith(
      updatedAt: now,
      createdAt: status.createdAt ?? now,
    );
    if (existingStatus != null &&
        _sameStatusContent(existingStatus, normalizedStatus)) {
      successMessage = 'Nothing changed.';
      errorMessage = null;
      notifyListeners();
      return;
    }

    busyMessage = 'Saving status ...';
    isLoading = true;
    notifyListeners();
    try {
      await _repository.saveStatus(normalizedStatus);
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
    if (!canDeleteStatuses) {
      throw const AuthFailure('You do not have access to delete statuses.');
    }
    final statusId = status.id ?? '';
    if (statusId.isEmpty) {
      return;
    }
    busyMessage = 'Deleting status ...';
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
    if (!canUpdateStatuses) {
      throw const AuthFailure('You do not have access to update statuses.');
    }
    final statusId = status.id ?? '';
    if (statusId.isEmpty) {
      return;
    }
    busyMessage = isActive
        ? 'Activating status ...'
        : 'Deactivating status ...';
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
    if (!canCreateStatuses) {
      throw const AuthFailure('You do not have access to create statuses.');
    }
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
    final override = fieldOverrideFor(field.id);
    return override?.required ?? field.required ?? false;
  }

  void updateAssignedFieldRequired(String fieldId, bool required) {
    final form = selectedForm;
    if (form == null || fieldId.trim().isEmpty) {
      return;
    }
    final assignedField = fields
        .where((field) => field.id == fieldId)
        .firstOrNull;
    final baseRequired =
        assignedField?.required ?? fieldById(fieldId)?.required;
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
    final isExisting = _loadedFormById(form.id) != null;
    if (isExisting ? !canUpdateForms : !canCreateForms) {
      throw const AuthFailure('You do not have access to save flows.');
    }

    busyMessage = 'Saving flow ...';
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
      final existingForm = _loadedFormById(normalizedForm.id);
      final existingFields = normalizedForm.id == null
          ? const <StatusField>[]
          : (_fieldsByFormId[normalizedForm.id!] ?? const <StatusField>[]);

      if (existingForm != null &&
          _sameFormContent(existingForm, normalizedForm) &&
          _sameAssignedFields(existingFields, normalizedFields)) {
        successMessage = 'Nothing changed.';
        errorMessage = null;
        return;
      }

      await _repository.saveStatusForm(normalizedForm);
      await _repository.saveFields(normalizedForm.id ?? '', normalizedFields);
      _fieldsByFormId[normalizedForm.id ?? ''] = normalizedFields
          .map((field) => field.copyWith())
          .toList();
      selectedForm = normalizedForm;
      fields = normalizedFields;
      forms = await _repository.getStatusForms();
      _sortFormsLatestFirst();
      successMessage = 'Form saved.';
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
    if (!canDeleteForms) {
      throw const AuthFailure('You do not have access to delete flows.');
    }
    busyMessage = 'Deleting flow ...';
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
      successMessage = 'Form deleted.';
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
    if (!canUpdateForms) {
      throw const AuthFailure('You do not have access to update flows.');
    }
    busyMessage = 'Deactivating flow ...';
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
      successMessage = 'Form deactivated.';
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

  StatusField? _loadedLibraryFieldById(String? fieldId) {
    if (fieldId == null || fieldId.isEmpty) {
      return null;
    }
    for (final field in fieldLibrary) {
      if (field.id == fieldId) {
        return field;
      }
    }
    return null;
  }

  Status? _loadedStatusById(String? statusId) {
    if (statusId == null || statusId.isEmpty) {
      return null;
    }
    for (final status in statuses) {
      if (status.id == statusId) {
        return status;
      }
    }
    return null;
  }

  StatusForm? _loadedFormById(String? formId) {
    if (formId == null || formId.isEmpty) {
      return null;
    }
    for (final form in forms) {
      if (form.id == formId) {
        return form;
      }
    }
    return null;
  }

  bool _sameLibraryFieldContent(StatusField left, StatusField right) {
    return left.copyWith(updatedAt: null, createdAt: null) ==
        right.copyWith(updatedAt: null, createdAt: null);
  }

  bool _sameStatusContent(Status left, Status right) {
    return left.copyWith(updatedAt: null, createdAt: null) ==
        right.copyWith(updatedAt: null, createdAt: null);
  }

  bool _sameFormContent(StatusForm left, StatusForm right) {
    return left.copyWith(updatedAt: null, createdAt: null, fields: const []) ==
        right.copyWith(updatedAt: null, createdAt: null, fields: const []);
  }

  bool _sameAssignedFields(List<StatusField> left, List<StatusField> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (left[index].copyWith(updatedAt: null, createdAt: null) !=
          right[index].copyWith(updatedAt: null, createdAt: null)) {
        return false;
      }
    }
    return true;
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

  @override
  void dispose() {
    _statusCacheUpdatesSubscription?.cancel();
    super.dispose();
  }
}
