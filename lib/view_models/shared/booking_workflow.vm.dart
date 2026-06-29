import 'dart:async';

import 'package:stacked/stacked.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/status.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/models/status_form.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/requests/booking.request.dart';
import 'package:webapp/requests/status.request.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/repositories/interfaces/booking_repository.dart';
import 'package:webapp/repositories/interfaces/status_form_repository.dart';
import 'package:webapp/services/status_field_option_resolver.dart';
import 'package:webapp/services/status_form_engine.dart';
import 'package:webapp/utils/functions.dart';

class _BookingWorkflowCacheSnapshot {
  const _BookingWorkflowCacheSnapshot({
    required this.user,
    required this.booking,
    required this.mainForms,
    required this.secondaryForms,
    required this.fieldsByFormId,
    required this.form,
    required this.cancelForm,
    required this.fields,
    required this.cancelFields,
    required this.fieldLibrary,
    required this.additionalFields,
    required this.answers,
    required this.cancelAnswers,
    required this.errors,
    required this.cancelErrors,
    required this.loadError,
    required this.blockedMessage,
    required this.resetTick,
    required this.cancelResetTick,
    required this.usersById,
    required this.statusesByKey,
  });

  final UserModel? user;
  final Booking? booking;
  final List<StatusForm> mainForms;
  final List<StatusForm> secondaryForms;
  final Map<String, List<StatusField>> fieldsByFormId;
  final StatusForm? form;
  final StatusForm? cancelForm;
  final List<StatusField> fields;
  final List<StatusField> cancelFields;
  final List<StatusField> fieldLibrary;
  final List<StatusField> additionalFields;
  final Map<String, dynamic> answers;
  final Map<String, dynamic> cancelAnswers;
  final Map<String, String> errors;
  final Map<String, String> cancelErrors;
  final String? loadError;
  final String? blockedMessage;
  final int resetTick;
  final int cancelResetTick;
  final Map<String, UserModel> usersById;
  final Map<String, Status> statusesByKey;
}

class BookingWorkflowViewModel extends BaseViewModel {
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

  BookingWorkflowViewModel({
    AuthRepository? authRepository,
    BookingRepository? bookingRepository,
    StatusFormRepository? statusRepository,
  }) : _authRepository = authRepository ?? AuthRequest.instance,
       _bookingRepository = bookingRepository ?? BookingRequest.instance,
       _statusRepository = statusRepository ?? StatusRequest.instance,
       _engine = StatusFormEngine(statusRepository ?? StatusRequest.instance) {
    _restoreCachedState();
  }

  final AuthRepository _authRepository;
  final BookingRepository _bookingRepository;
  final StatusFormRepository _statusRepository;
  final StatusFormEngine _engine;
  final StatusFieldOptionResolver _optionResolver = StatusFieldOptionResolver();
  static final Map<String, _BookingWorkflowCacheSnapshot> _cacheByBookingId =
      {};

  static void clearCachedState() {
    _cacheByBookingId.clear();
  }

  final Map<String, UserModel> _usersById = {};
  final Map<String, Status> _statusesByKey = {};
  List<StatusForm> mainForms = [];
  List<StatusForm> secondaryForms = [];
  final Map<String, List<StatusField>> _fieldsByFormId = {};

  UserModel? user;
  Booking? booking;
  StatusForm? form;
  StatusForm? cancelForm;
  List<StatusField> fields = [];
  List<StatusField> cancelFields = [];
  List<StatusField> fieldLibrary = [];
  List<StatusField> additionalFields = [];
  Map<String, dynamic> answers = {};
  Map<String, dynamic> cancelAnswers = {};
  Map<String, String> errors = {};
  Map<String, String> cancelErrors = {};
  String? loadError;
  String? blockedMessage;
  bool isBusyLoading = false;
  bool isSubmitting = false;
  bool isCancelSubmitting = false;
  int resetTick = 0;
  int cancelResetTick = 0;

  void _restoreCachedState() {
    final snapshot = _cacheByBookingId[booking?.id ?? ''];
    if (snapshot == null) {
      return;
    }
    user = snapshot.user;
    booking = snapshot.booking;
    mainForms = List<StatusForm>.from(snapshot.mainForms);
    secondaryForms = List<StatusForm>.from(snapshot.secondaryForms);
    _fieldsByFormId
      ..clear()
      ..addAll(
        snapshot.fieldsByFormId.map(
          (key, value) => MapEntry(key, List<StatusField>.from(value)),
        ),
      );
    form = snapshot.form;
    cancelForm = snapshot.cancelForm;
    fields = List<StatusField>.from(snapshot.fields);
    cancelFields = List<StatusField>.from(snapshot.cancelFields);
    fieldLibrary = List<StatusField>.from(snapshot.fieldLibrary);
    additionalFields = List<StatusField>.from(snapshot.additionalFields);
    answers = Map<String, dynamic>.from(snapshot.answers);
    cancelAnswers = Map<String, dynamic>.from(snapshot.cancelAnswers);
    errors = Map<String, String>.from(snapshot.errors);
    cancelErrors = Map<String, String>.from(snapshot.cancelErrors);
    loadError = snapshot.loadError;
    blockedMessage = snapshot.blockedMessage;
    resetTick = snapshot.resetTick;
    cancelResetTick = snapshot.cancelResetTick;
    _usersById
      ..clear()
      ..addAll(snapshot.usersById);
    _statusesByKey
      ..clear()
      ..addAll(snapshot.statusesByKey);
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

  Future<void> load({required UserModel user, required Booking booking}) async {
    if (isBusyLoading) {
      return;
    }
    final cachedSnapshot = _cacheByBookingId[booking.id ?? ''];
    if (cachedSnapshot != null) {
      this.user = cachedSnapshot.user ?? user;
      this.booking = cachedSnapshot.booking ?? booking;
      _restoreCachedState();
    }
    this.user = user;
    this.booking = booking;
    isBusyLoading = true;
    loadError = null;
    blockedMessage = null;
    notifyListeners();

    try {
      await _bookingRepository.initialize();
      final users = await _authRepository.getUsers();
      final statuses = await _statusRepository.getStatuses();
      fieldLibrary = await _optionResolver.hydrateFields(
        await _statusRepository.getAllFields(),
      );
      _usersById
        ..clear()
        ..addEntries(
          users
              .where((item) => (item.id ?? '').isNotEmpty)
              .map((item) => MapEntry(item.id!, item)),
        );
      _statusesByKey
        ..clear()
        ..addEntries(
          statuses
              .where((item) => (item.key ?? '').isNotEmpty)
              .map((item) => MapEntry(item.key!, item)),
        );

      final currentKey = currentStatusKey;
      if (currentKey == null || currentKey.isEmpty) {
        form = null;
        cancelForm = null;
        mainForms = const [];
        secondaryForms = const [];
        _fieldsByFormId.clear();
        fields = const [];
        cancelFields = const [];
        additionalFields = const [];
        answers = {};
        cancelAnswers = {};
        errors = {};
        cancelErrors = {};
        return;
      }

      final matchingForms = await _statusRepository
          .getStatusFormsByRoleAndStatus(user.role ?? '', currentKey);
      final loadedForm = matchingForms
          .where((item) => item.resolvedIsMainForm)
          .firstOrNull;
      final loadedCancelForm = matchingForms
          .where((item) => !item.resolvedIsMainForm)
          .firstOrNull;
      if (loadedForm == null && loadedCancelForm == null) {
        form = null;
        cancelForm = null;
        mainForms = const [];
        secondaryForms = const [];
        _fieldsByFormId.clear();
        fields = const [];
        cancelFields = const [];
        additionalFields = const [];
        answers = {};
        cancelAnswers = {};
        errors = {};
        cancelErrors = {};
        return;
      }

      mainForms = matchingForms
          .where((item) => item.resolvedIsMainForm)
          .toList();
      secondaryForms = matchingForms
          .where((item) => !item.resolvedIsMainForm)
          .toList();
      form = loadedForm;
      cancelForm = loadedCancelForm;
      _fieldsByFormId.clear();
      for (final activeForm in matchingForms) {
        final formId = activeForm.id ?? '';
        _fieldsByFormId[formId] = formId.isEmpty
            ? const []
            : await _optionResolver.hydrateFields(
                await _statusRepository.getFields(formId),
              );
      }
      answers = loadedForm == null
          ? {}
          : _initialAnswersForBooking(
              booking,
              fieldLibrary: fieldLibrary,
            );
      fields = loadedForm == null
          ? const []
          : fieldsForForm(loadedForm, answers: answers);
      cancelAnswers = {};
      cancelFields = loadedCancelForm == null
          ? const []
          : fieldsForForm(loadedCancelForm, answers: cancelAnswers);
      blockedMessage = loadedForm == null
          ? null
          : _engine.getBlockedMessage(booking, loadedForm);
      additionalFields = const [];
      errors = {};
      cancelErrors = {};
      _cacheCurrentState();
    } catch (error) {
      loadError = userFacingErrorMessage(
        error,
        fallback: 'We could not load the booking workflow right now.',
      );
    } finally {
      isBusyLoading = false;
      notifyListeners();
    }
  }

  void _cacheCurrentState() {
    final bookingId = booking?.id ?? '';
    if (bookingId.isEmpty) {
      return;
    }
    _cacheByBookingId[bookingId] = _BookingWorkflowCacheSnapshot(
      user: user,
      booking: booking,
      mainForms: List<StatusForm>.from(mainForms),
      secondaryForms: List<StatusForm>.from(secondaryForms),
      fieldsByFormId: _fieldsByFormId.map(
        (key, value) => MapEntry(key, List<StatusField>.from(value)),
      ),
      form: form,
      cancelForm: cancelForm,
      fields: List<StatusField>.from(fields),
      cancelFields: List<StatusField>.from(cancelFields),
      fieldLibrary: List<StatusField>.from(fieldLibrary),
      additionalFields: List<StatusField>.from(additionalFields),
      answers: Map<String, dynamic>.from(answers),
      cancelAnswers: Map<String, dynamic>.from(cancelAnswers),
      errors: Map<String, String>.from(errors),
      cancelErrors: Map<String, String>.from(cancelErrors),
      loadError: loadError,
      blockedMessage: blockedMessage,
      resetTick: resetTick,
      cancelResetTick: cancelResetTick,
      usersById: Map<String, UserModel>.from(_usersById),
      statusesByKey: Map<String, Status>.from(_statusesByKey),
    );
  }

  String? get currentStatusKey {
    final currentBooking = booking;
    if (currentBooking == null) {
      return null;
    }
    return currentBooking.clientStatus;
  }

  String currentStatusLabel() {
    return statusLabelForKey(currentStatusKey);
  }

  String statusLabelForKey(String? statusKey) {
    final key = statusKey?.trim();
    if (key == null || key.isEmpty) {
      return '-';
    }
    final label = _statusesByKey[key]?.label?.trim();
    if (label != null && label.isNotEmpty) {
      return label;
    }
    return _humanize(key);
  }

  String? currentStatusDescription() {
    final key = currentStatusKey?.trim();
    if (key == null || key.isEmpty) {
      return null;
    }
    final description = _statusesByKey[key]?.description?.trim();
    return description?.isNotEmpty == true ? description : null;
  }

  String? roleGuidanceMessage() {
    final key = currentStatusKey?.trim();
    final role = user?.role?.trim();
    if (key == null || key.isEmpty || role == null || role.isEmpty) {
      return null;
    }
    final status = _statusesByKey[key];
    if (status == null || status.isActive == false) {
      return null;
    }
    if (status.applicableRoles.isNotEmpty &&
        !status.applicableRoles.contains(role)) {
      return null;
    }
    final message = status.roleMessages[role]?.trim();
    return message?.isNotEmpty == true ? message : null;
  }

  void updateAnswer(String key, dynamic value) {
    final nextAnswers = Map<String, dynamic>.from(answers);
    if (_isEmptyValue(value)) {
      nextAnswers.remove(key);
    } else {
      nextAnswers[key] = value;
    }
    answers = nextAnswers;
    errors = Map<String, String>.from(errors)..remove(key);
    notifyListeners();
  }

  void clearForm() {
    answers = {};
    errors = {};
    additionalFields = const [];
    resetTick += 1;
    notifyListeners();
  }

  void updateCancelAnswer(String key, dynamic value) {
    final shouldNotify = cancelErrors.containsKey(key);
    final nextAnswers = Map<String, dynamic>.from(cancelAnswers);
    if (_isEmptyValue(value)) {
      nextAnswers.remove(key);
    } else {
      nextAnswers[key] = value;
    }
    cancelAnswers = nextAnswers;
    cancelErrors = Map<String, String>.from(cancelErrors)..remove(key);
    if (shouldNotify) {
      notifyListeners();
    }
  }

  void clearCancelForm() {
    cancelAnswers = {};
    cancelErrors = {};
    cancelResetTick += 1;
    notifyListeners();
  }

  bool get hasActionablePrimaryForm {
    final activeForm = form;
    if (activeForm == null) {
      return false;
    }
    final hasNextStatus =
        (activeForm.nextStatusKey?.trim().isNotEmpty ?? false);
    return hasNextStatus || fields.isNotEmpty;
  }

  bool get supportsAdditionalFields =>
      (user?.role ?? '') == 'admin' && hasActionablePrimaryForm;

  List<StatusField> fieldsForForm(
    StatusForm activeForm, {
    Map<String, dynamic>? answers,
  }) {
    final baseFields = _fieldsByFormId[activeForm.id ?? ''] ?? const [];
    final resolvedFields = baseFields.map((field) {
      final override = activeForm.fieldOverrides[field.id];
      if (override == null) {
        return field;
      }
      return field.copyWith(
        required: override.required ?? field.required,
        placeholder: override.placeholder ?? field.placeholder,
      );
    }).toList();
    return StatusFormEngine.visibleFields(resolvedFields, answers ?? this.answers);
  }

  String? blockedMessageForForm(StatusForm activeForm) {
    final currentBooking = booking;
    if (currentBooking == null) {
      return null;
    }
    return _engine.getBlockedMessage(currentBooking, activeForm);
  }

  Map<String, String> validateAnswersForForm(
    List<StatusField> activeFields,
    Map<String, dynamic> formAnswers, {
    List<StatusField> additionalFields = const [],
  }) {
    final validationErrors = _engine.validateFields(activeFields, formAnswers);
    if (additionalFields.isNotEmpty) {
      validationErrors.addAll(
        _engine.validateFields(additionalFields, formAnswers),
      );
    }
    return validationErrors;
  }

  List<StatusField> get availableFieldsForSelection {
    final assignedKeys = {
      ...fields.map((field) => field.key ?? ''),
      ...additionalFields.map((field) => field.key ?? ''),
    };
    return fieldLibrary
        .where((field) => !assignedKeys.contains(field.key ?? ''))
        .toList()
      ..sort((a, b) {
        final left = (a.title?.trim().isNotEmpty == true)
            ? a.title!
            : a.key ?? '';
        final right = (b.title?.trim().isNotEmpty == true)
            ? b.title!
            : b.key ?? '';
        return left.compareTo(right);
      });
  }

  StatusField buildNewFieldDraft() {
    final now = DateTime.now();
    return StatusField(
      id: nextFieldId,
      required: false,
      options: const [],
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> addExistingField(String fieldId) async {
    if (!supportsAdditionalFields) {
      return;
    }
    final activeForm = form;
    if (activeForm == null) {
      return;
    }
    final matches = fieldLibrary.where((item) => item.id == fieldId);
    if (matches.isEmpty) {
      return;
    }
    final field = matches.first;
    final fieldKey = field.key ?? '';
    if (fieldKey.isEmpty) {
      return;
    }
    if (fields.any((item) => item.key == fieldKey) ||
        additionalFields.any((item) => item.key == fieldKey)) {
      return;
    }
    final assignedField = field.copyWith(
      sortOrder: fields.length + 1,
      updatedAt: DateTime.now(),
    );
    final updatedForm = activeForm.copyWith(
      fields: [
        ...activeForm.fields.map((item) => item.copyWith()),
        assignedField,
      ],
      updatedAt: DateTime.now(),
    );
    form = updatedForm;
    fields = [...fields, assignedField];
    final formId = updatedForm.id ?? '';
    if (formId.isNotEmpty) {
      _fieldsByFormId[formId] = fields.map((item) => item.copyWith()).toList();
    }
    _replaceFormInCollections(updatedForm);
    _cacheCurrentState();
    notifyListeners();
    unawaited(_statusRepository.saveStatusForm(updatedForm));
  }

  Future<StatusField> saveLibraryField(StatusField field) async {
    final now = DateTime.now();
    final savedField = field.copyWith(
      updatedAt: now,
      createdAt: field.createdAt ?? now,
    );
    await _statusRepository.saveField(savedField);
    fieldLibrary = await _optionResolver.hydrateFields(
      await _statusRepository.getAllFields(),
    );
    _replaceFieldInCollections(savedField);
    notifyListeners();
    return savedField;
  }

  bool isAdditionalField(StatusField field) {
    final fieldId = field.id ?? '';
    final fieldKey = field.key ?? '';
    return additionalFields.any((item) => _sameField(item, fieldId, fieldKey));
  }

  bool isFormAssignedField(StatusField field) {
    final activeForm = form;
    if (activeForm == null) {
      return false;
    }
    final fieldId = field.id ?? '';
    final fieldKey = field.key ?? '';
    final baseFields = _fieldsByFormId[activeForm.id ?? ''] ?? const [];
    return baseFields.any((item) => _sameField(item, fieldId, fieldKey));
  }

  void removeManagedField(StatusField field) {
    final fieldKey = (field.key ?? '').trim();
    if (fieldKey.isEmpty) {
      return;
    }

    if (!isFormAssignedField(field)) {
      removeAdditionalField(fieldKey);
      return;
    }

    final activeForm = form;
    if (activeForm == null) {
      return;
    }

    final formId = activeForm.id ?? '';
    final fieldId = field.id ?? '';
    final baseFields = _fieldsByFormId[formId] ?? const [];
    final nextBaseFields = baseFields
        .where((item) => !_sameField(item, fieldId, fieldKey))
        .toList()
        .asMap()
        .entries
        .map((entry) => entry.value.copyWith(sortOrder: entry.key + 1))
        .toList();
    final nextFieldOverrides = Map<String, StatusFieldOverride>.from(
      activeForm.fieldOverrides,
    );
    if (fieldId.isNotEmpty) {
      nextFieldOverrides.remove(fieldId);
    }

    final updatedForm = activeForm.copyWith(
      fields: nextBaseFields.map((item) => item.copyWith()).toList(),
      fieldOverrides: nextFieldOverrides,
      updatedAt: DateTime.now(),
    );

    form = updatedForm;
    _fieldsByFormId[formId] = nextBaseFields.map((item) => item.copyWith()).toList();
    fields = fieldsForForm(updatedForm, answers: answers);
    additionalFields = additionalFields
        .where((item) => !_sameField(item, fieldId, fieldKey))
        .toList();
    answers = Map<String, dynamic>.from(answers)..remove(fieldKey);
    errors = Map<String, String>.from(errors)..remove(fieldKey);
    _replaceFormInCollections(updatedForm);
    _cacheCurrentState();
    notifyListeners();
    unawaited(_statusRepository.saveStatusForm(updatedForm));
  }

  void reorderManagedFields(
    List<StatusField> visibleOrderedFields,
    int oldIndex,
    int newIndex, {
    Map<String, dynamic>? answers,
  }) {
    final activeForm = form;
    if (activeForm == null ||
        oldIndex < 0 ||
        oldIndex >= visibleOrderedFields.length) {
      return;
    }

    var targetIndex = newIndex;
    if (targetIndex > oldIndex) {
      targetIndex -= 1;
    }
    if (targetIndex < 0 || targetIndex >= visibleOrderedFields.length) {
      return;
    }

    final movedField = visibleOrderedFields[oldIndex];
    if (!isFormAssignedField(movedField)) {
      return;
    }

    final reorderedVisibleFields = [...visibleOrderedFields];
    final movedVisibleField = reorderedVisibleFields.removeAt(oldIndex);
    reorderedVisibleFields.insert(targetIndex, movedVisibleField);

    final formId = activeForm.id ?? '';
    final baseFields = _fieldsByFormId[formId] ?? const [];
    final visibleAssignedFields = reorderedVisibleFields
        .where(isFormAssignedField)
        .toList();
    final visibleAssignedIds = {
      for (final field in visibleAssignedFields)
        if ((field.id ?? '').trim().isNotEmpty) field.id!.trim(),
    };
    final visibleAssignedKeys = {
      for (final field in visibleAssignedFields)
        if ((field.key ?? '').trim().isNotEmpty) field.key!.trim(),
    };

    final remainingBaseFields = baseFields.where((field) {
      final fieldId = (field.id ?? '').trim();
      final fieldKey = (field.key ?? '').trim();
      return !visibleAssignedIds.contains(fieldId) &&
          !visibleAssignedKeys.contains(fieldKey);
    }).toList();

    final orderedBaseFields = [
      for (final visibleField in visibleAssignedFields)
        ...baseFields.where(
          (field) => _sameField(
            field,
            visibleField.id ?? '',
            visibleField.key ?? '',
          ),
        ),
      ...remainingBaseFields,
    ].asMap().entries.map((entry) {
      return entry.value.copyWith(sortOrder: entry.key + 1);
    }).toList();

    final updatedForm = activeForm.copyWith(
      fields: orderedBaseFields.map((field) => field.copyWith()).toList(),
      updatedAt: DateTime.now(),
    );

    form = updatedForm;
    _fieldsByFormId[formId] = orderedBaseFields
        .map((field) => field.copyWith())
        .toList();
    fields = fieldsForForm(updatedForm, answers: answers ?? this.answers);
    _replaceFormInCollections(updatedForm);
    _cacheCurrentState();
    notifyListeners();
    unawaited(_statusRepository.saveFields(formId, orderedBaseFields));
  }

  void removeAdditionalField(String fieldKey) {
    if (fieldKey.trim().isEmpty) {
      return;
    }
    additionalFields = additionalFields
        .where((field) => (field.key ?? '') != fieldKey)
        .toList();
    answers = Map<String, dynamic>.from(answers)..remove(fieldKey);
    notifyListeners();
  }

  void _replaceFieldInCollections(StatusField savedField) {
    final savedId = savedField.id ?? '';
    final savedKey = savedField.key ?? '';
    fields = fields
        .map(
          (field) => _sameField(field, savedId, savedKey)
              ? savedField.copyWith()
              : field,
        )
        .toList();
    additionalFields = additionalFields
        .map(
          (field) => _sameField(field, savedId, savedKey)
              ? savedField.copyWith()
              : field,
        )
        .toList();
  }

  bool _sameField(StatusField field, String savedId, String savedKey) {
    return (savedId.isNotEmpty && field.id == savedId) ||
        (savedKey.isNotEmpty && field.key == savedKey);
  }

  void _replaceFormInCollections(StatusForm updatedForm) {
    mainForms = mainForms
        .map((item) => (item.id == updatedForm.id) ? updatedForm : item)
        .toList();
    secondaryForms = secondaryForms
        .map((item) => (item.id == updatedForm.id) ? updatedForm : item)
        .toList();
  }

  Future<Booking?> submit() async {
    final currentUser = user;
    final currentBooking = booking;
    final activeForm = form;
    if (currentUser == null || currentBooking == null || activeForm == null) {
      return null;
    }
    if (!validateForSubmit()) {
      return null;
    }

    isSubmitting = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 16));

    try {
      final nextBooking = _bookingWithResolvedUsers(
        _engine.applyOutputToBooking(
          currentBooking,
          activeForm,
          [
            ...StatusFormEngine.visibleFields(fields, answers),
            ...StatusFormEngine.visibleFields(additionalFields, answers),
          ],
          answers,
          currentUser.id ?? '',
          currentUser.role,
        ),
        currentBooking: currentBooking,
        formAnswers: answers,
      );
      final savedBooking = await _bookingRepository.saveBooking(nextBooking);
      answers = {};
      errors = {};
      additionalFields = const [];
      resetTick += 1;
      await load(user: currentUser, booking: savedBooking);
      return savedBooking;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  Future<Booking?> submitSpecificForm(
    StatusForm activeForm,
    Map<String, dynamic> formAnswers,
  ) async {
    final currentUser = user;
    final currentBooking = booking;
    if (currentUser == null || currentBooking == null) {
      return null;
    }

    isSubmitting = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 16));

    try {
      final nextBooking = _bookingWithResolvedUsers(
        _engine.applyOutputToBooking(
          currentBooking,
          activeForm,
          [
            ...fieldsForForm(activeForm, answers: formAnswers),
            ...StatusFormEngine.visibleFields(additionalFields, formAnswers),
          ],
          formAnswers,
          currentUser.id ?? '',
          currentUser.role,
        ),
        currentBooking: currentBooking,
        formAnswers: formAnswers,
      );
      final savedBooking = await _bookingRepository.saveBooking(nextBooking);
      await load(user: currentUser, booking: savedBooking);
      return savedBooking;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  bool validateForSubmit() {
    if (blockedMessage != null) {
      notifyListeners();
      return false;
    }

    final activeForm = form;
    final activeFields = activeForm == null
        ? fields
        : fieldsForForm(activeForm, answers: answers);
    final validationErrors = _engine.validateFields(activeFields, answers);
    validationErrors.addAll(_engine.validateFields(additionalFields, answers));
    errors = validationErrors;
    notifyListeners();
    return validationErrors.isEmpty;
  }

  Future<Booking?> submitCancel() async {
    final currentUser = user;
    final currentBooking = booking;
    final activeForm = cancelForm;
    if (currentUser == null || currentBooking == null || activeForm == null) {
      return null;
    }

    if (!validateCancelForSubmit()) {
      return null;
    }

    isCancelSubmitting = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 16));

    try {
      final nextBooking = _bookingWithResolvedUsers(
        _engine.applyOutputToBooking(
          currentBooking,
          activeForm,
          cancelFields,
          cancelAnswers,
          currentUser.id ?? '',
          currentUser.role,
        ),
        currentBooking: currentBooking,
        formAnswers: cancelAnswers,
      );
      final savedBooking = await _bookingRepository.saveBooking(nextBooking);
      cancelAnswers = {};
      cancelErrors = {};
      cancelResetTick += 1;
      await load(user: currentUser, booking: savedBooking);
      return savedBooking;
    } finally {
      isCancelSubmitting = false;
      notifyListeners();
    }
  }

  bool validateCancelForSubmit() {
    final validationErrors = _engine.validateFields(
      cancelFields,
      cancelAnswers,
    );
    cancelErrors = validationErrors;
    notifyListeners();
    return validationErrors.isEmpty;
  }

  String userName(String? userId, String fallback) {
    final name = _usersById[userId]?.name?.trim();
    return name?.isNotEmpty == true ? name! : fallback;
  }

  String userPhone(String? userId) {
    final phone = _usersById[userId]?.phone?.trim();
    return phone?.isNotEmpty == true ? phone! : '-';
  }

  String userRole(String? userId, String fallback) {
    final role = _usersById[userId]?.role?.trim();
    return role?.isNotEmpty == true ? role! : fallback;
  }

  UserModel? userById(String? userId) {
    final normalizedId = normalizeId(userId);
    if (normalizedId == null) {
      return null;
    }
    return _usersById[normalizedId];
  }

  List<UserModel> roleUsers(String role) {
    final normalizedRole = role.trim().toLowerCase();
    return _usersById.values
        .where(
          (item) =>
              (item.role ?? '').trim().toLowerCase() == normalizedRole &&
              (item.isActive ?? false) &&
              (item.isOnline ?? false),
        )
        .toList()
      ..sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
  }

  Map<String, String> memberOptionLabelsForCurrentBooking() {
    final clientId = normalizeId(booking?.client?.id);
    if (clientId == null) {
      return const {};
    }

    final members = _usersById.values.where((item) {
      return isSubClientRole(item.role) &&
          (item.isActive ?? true) &&
          normalizeId(item.parentClientId) == clientId;
    }).toList()
      ..sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));

    final labels = <String, String>{};
    for (final member in members) {
      final id = normalizeId(member.id);
      if (id == null) {
        continue;
      }
      final parts = <String>[
        if ((member.name?.trim() ?? '').isNotEmpty) member.name!.trim() else 'Unnamed Member',
        if ((member.phone?.trim() ?? '').isNotEmpty)
          normalizePhilippinePhone(member.phone) ?? member.phone!.trim(),
        if ((member.position?.trim() ?? '').isNotEmpty) member.position!.trim(),
      ];
      labels[id] = parts.join(' | ');
    }

    return labels;
  }

  String roleUserLabel(String userId, {required String fallbackRole}) {
    final user = _usersById[userId];
    if (user == null) {
      return _humanize(fallbackRole);
    }
    final name = user.name?.trim();
    final phone = user.phone?.trim();
    if (name?.isNotEmpty == true && phone?.isNotEmpty == true) {
      return '$name • $phone';
    }
    if (name?.isNotEmpty == true) {
      return name!;
    }
    return phone?.isNotEmpty == true ? phone! : _humanize(fallbackRole);
  }

  static String _humanize(String value) {
    return value
        .split('_')
        .where((part) => part.isNotEmpty)
        .map(
          (part) => part.length == 1
              ? part.toUpperCase()
              : '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  static bool _isEmptyValue(dynamic value) {
    if (value == null) {
      return true;
    }
    if (value is String) {
      return value.trim().isEmpty;
    }
    if (value is List) {
      return value.isEmpty;
    }
    if (value is Map) {
      return value.isEmpty;
    }
    return false;
  }

  Map<String, dynamic> _initialAnswersForBooking(
    Booking booking, {
    required List<StatusField> fieldLibrary,
  }) {
    final answers = <String, dynamic>{};
    if ((booking.vehicleMake?.id ?? '').trim().isNotEmpty) {
      answers['vehicle_make_id'] = booking.vehicleMake!.id!.trim();
    }
    if ((booking.driver?.id ?? '').trim().isNotEmpty) {
      answers['driver_id'] = booking.driver!.id!.trim();
    }
    if ((booking.helper?.id ?? '').trim().isNotEmpty) {
      answers['helper_id'] = booking.helper!.id!.trim();
    }
    final candidateKeys = <String>{
      'vehicle_make_id',
      'driver_id',
      'helper_id',
      for (final field in fieldLibrary)
        if ((field.key ?? '').trim().isNotEmpty) field.key!.trim(),
    };
    for (final key in candidateKeys) {
      final value = _firstNonEmptyOutputField(booking, key);
      if (_isEmptyValue(value)) {
        continue;
      }
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isEmpty) {
          continue;
        }
        answers[key] = key == 'van_size'
            ? (VehicleRequest.instance.normalizeVehicleSizeId(trimmed) ??
                  trimmed)
            : trimmed;
        continue;
      }
      answers[key] = value;
    }
    return answers;
  }

  static Map<String, dynamic> _outputFieldsForStatus(
    Booking booking,
    String statusKey,
  ) {
    final section = booking.statusOutputs?[statusKey];
    if (section is! Map || section['fields'] is! Map) {
      return const {};
    }
    return Map<String, dynamic>.from(section['fields'] as Map);
  }

  static dynamic _firstNonEmptyOutputField(Booking booking, String key) {
    final pendingFields = _outputFieldsForStatus(booking, 'pending');
    final pendingValue = pendingFields[key];
    if (!_isEmptyValue(pendingValue)) {
      return pendingValue;
    }

    final outputs = booking.statusOutputs;
    if (outputs == null || outputs.isEmpty) {
      return null;
    }

    for (final entry in outputs.entries) {
      if (entry.key == 'pending') {
        continue;
      }
      if (entry.value is! Map) {
        continue;
      }
      final raw = Map<String, dynamic>.from(entry.value as Map);
      if (raw['fields'] is! Map) {
        continue;
      }
      final fields = Map<String, dynamic>.from(raw['fields'] as Map);
      final value = fields[key];
      if (!_isEmptyValue(value)) {
        return value;
      }
    }

    return null;
  }

  Booking _bookingWithResolvedUsers(
    Booking booking, {
    required Booking currentBooking,
    required Map<String, dynamic> formAnswers,
  }) {
    final driverId = _normalizedAnswer(formAnswers['driver_id']);
    final helperId = _normalizedAnswer(formAnswers['helper_id']);
    return booking.copyWith(
      client: currentBooking.client?.id == null
          ? currentBooking.client
          : _usersById[currentBooking.client!.id!] ?? currentBooking.client,
      driver: driverId == null
          ? currentBooking.driver
          : _usersById[driverId] ?? currentBooking.driver,
      helper: helperId == null
          ? currentBooking.helper
          : _usersById[helperId] ?? currentBooking.helper,
    );
  }

  String? _normalizedAnswer(dynamic value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
