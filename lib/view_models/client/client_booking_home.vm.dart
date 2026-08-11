import 'package:stacked/stacked.dart';
import 'package:flutter/foundation.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/status.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/utils/functions.dart';
import 'package:webapp/models/status_form.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/models/client_member.dart';
import 'package:webapp/requests/status.request.dart';
import 'package:webapp/requests/booking.request.dart';
import 'package:webapp/services/status_form_engine.dart';
import 'package:webapp/requests/client_member.request.dart';
import 'package:webapp/services/status_field_option_resolver.dart';
import 'package:webapp/repositories/interfaces/booking_repository.dart';
import 'package:webapp/repositories/interfaces/status_form_repository.dart';
import 'package:webapp/repositories/interfaces/client_member_repository.dart';

class ClientBookingHomeViewModel extends BaseViewModel {
  ClientBookingHomeViewModel({
    StatusFormRepository? statusRepository,
    BookingRepository? bookingRepository,
    ClientMemberRepository? clientMemberRepository,
  }) : _statusRepository = statusRepository ?? StatusRequest.instance,
       _bookingRepository = bookingRepository ?? BookingRequest.instance,
       _clientMemberRepository =
           clientMemberRepository ?? ClientMemberRequest.instance,
       _engine = StatusFormEngine(statusRepository ?? StatusRequest.instance) {
    mainForms = List<StatusForm>.from(_cachedMainForms);
    form = _cachedForm;
    fields = List<StatusField>.from(_cachedFields);
    statuses = List<Status>.from(_cachedStatuses);
    members = List<ClientMember>.from(_cachedMembers);
    _fieldsByFormId.addAll(
      _cachedFieldsByFormId.map(
        (key, value) => MapEntry(key, List<StatusField>.from(value)),
      ),
    );
    loadError = _cachedLoadError;
    blockedMessage = _cachedBlockedMessage;
    _activeClientUser = _cachedActiveClientUser;
  }

  final StatusFormRepository _statusRepository;
  final BookingRepository _bookingRepository;
  final ClientMemberRepository _clientMemberRepository;
  final StatusFormEngine _engine;
  final StatusFieldOptionResolver _optionResolver = StatusFieldOptionResolver();
  static List<StatusForm> _cachedMainForms = const [];
  static Map<String, List<StatusField>> _cachedFieldsByFormId = const {};
  static StatusForm? _cachedForm;
  static List<StatusField> _cachedFields = const [];
  static List<Status> _cachedStatuses = const [];
  static List<ClientMember> _cachedMembers = const [];
  static String? _cachedLoadError;
  static String? _cachedBlockedMessage;
  static UserModel? _cachedActiveClientUser;

  static void clearCachedState() {
    _cachedMainForms = const [];
    _cachedFieldsByFormId = const {};
    _cachedForm = null;
    _cachedFields = const [];
    _cachedStatuses = const [];
    _cachedMembers = const [];
    _cachedLoadError = null;
    _cachedBlockedMessage = null;
    _cachedActiveClientUser = null;
  }

  List<StatusForm> mainForms = [];
  final Map<String, List<StatusField>> _fieldsByFormId = {};
  StatusForm? form;
  List<StatusField> fields = [];
  List<Status> statuses = [];
  List<ClientMember> members = [];
  Map<String, dynamic> answers = {};
  Map<String, String> errors = {};
  String? loadError;
  String? blockedMessage;
  bool isBusyLoading = false;
  bool isSubmitting = false;
  int resetTick = 0;
  UserModel? _activeClientUser;
  UserModel? _pendingClientUser;
  static const representativeIdKey = 'representative_id';

  Future<void> load(UserModel clientUser) async {
    if (isBusyLoading) {
      _pendingClientUser = clientUser;
      return;
    }

    isBusyLoading = true;
    loadError = null;
    blockedMessage = null;
    notifyListeners();

    try {
      await _bookingRepository.initialize();
      await _clientMemberRepository.initialize();

      statuses = await _statusRepository.getStatuses();
      members = await _clientMemberRepository.getMembersForClient(
        clientUser.id ?? '',
      );
      final bookForms = await _statusRepository.getStatusFormsByRoleAndStatus(
        'client',
        'book',
      );
      final loadedMainForms = bookForms
          .where((item) => item.isActive != false && item.resolvedIsMainForm)
          .toList();
      mainForms = loadedMainForms;
      debugPrint(
        '[ClientBookingHomeViewModel] user=${clientUser.id} statuses=${statuses.length} members=${members.length} bookForms=${bookForms.length} mainForms=${mainForms.length}',
      );

      form = mainForms.firstOrNull;
      if (form == null) {
        mainForms = [];
        _fieldsByFormId.clear();
        fields = [];
        answers = {};
        errors = {};
        debugPrint('[ClientBookingHomeViewModel] no main form resolved');
        return;
      }

      _fieldsByFormId.clear();
      for (final loadedForm in mainForms) {
        final formId = loadedForm.id ?? '';
        if (formId.isEmpty) {
          _fieldsByFormId[formId] = const [];
          continue;
        }
        _fieldsByFormId[formId] = await _optionResolver.hydrateFields(
          await _statusRepository.getFields(formId),
        );
      }
      fields = fieldsForForm(form!);
      debugPrint(
        '[ClientBookingHomeViewModel] selectedForm=${form?.id} loadedFieldBuckets=${_fieldsByFormId.length} visibleFields=${fields.length}',
      );
      _activeClientUser = clientUser;
      blockedMessage = _resolveBlockedMessage(clientUser);
      _cachedMainForms = List<StatusForm>.from(mainForms);
      _cachedFieldsByFormId = _fieldsByFormId.map(
        (key, value) => MapEntry(key, List<StatusField>.from(value)),
      );
      _cachedForm = form;
      _cachedFields = List<StatusField>.from(fields);
      _cachedStatuses = List<Status>.from(statuses);
      _cachedMembers = List<ClientMember>.from(members);
      _cachedLoadError = null;
      _cachedBlockedMessage = blockedMessage;
      _cachedActiveClientUser = _activeClientUser;
    } catch (error) {
      debugPrint('[ClientBookingHomeViewModel] load error=$error');
      loadError = userFacingErrorMessage(
        error,
        fallback: 'We could not load the booking form right now.',
      );
      _cachedLoadError = loadError;
    } finally {
      isBusyLoading = false;
      notifyListeners();
      final pendingClientUser = _pendingClientUser;
      if (pendingClientUser != null &&
          pendingClientUser.id != _activeClientUser?.id) {
        _pendingClientUser = null;
        Future<void>.microtask(() => load(pendingClientUser));
      } else {
        _pendingClientUser = null;
      }
    }
  }

  void syncClient(UserModel clientUser) {
    if (_activeClientUser?.id == clientUser.id &&
        _activeClientUser?.updatedAt == clientUser.updatedAt) {
      return;
    }
    _activeClientUser = clientUser;
    answers = {};
    errors = {};
    resetTick += 1;
    blockedMessage = _resolveBlockedMessage(clientUser);
    notifyListeners();
  }

  List<ClientMember> get activeMembers =>
      members.where((member) => member.isActive ?? true).toList();

  bool formUsesMemberSelection(StatusForm activeForm) {
    return fieldsForForm(activeForm).any(_isMemberField);
  }

  Map<String, String> memberOptionLabelsForForm(StatusForm activeForm) {
    if (!formUsesMemberSelection(activeForm)) {
      return const {};
    }
    final labels = <String, String>{};
    for (final member in activeMembers) {
      final id = (member.id ?? '').trim();
      if (id.isEmpty) {
        continue;
      }
      final parts = <String>[
        member.displayName,
        if (member.normalizedPhone.isNotEmpty) member.normalizedPhone,
        if ((member.position?.trim() ?? '').isNotEmpty) member.position!.trim(),
      ];
      labels[id] = parts.join(' | ');
    }
    return labels;
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
    resetTick += 1;
    notifyListeners();
  }

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

    return StatusFormEngine.visibleFields(
      resolvedFields,
      answers ?? this.answers,
    );
  }

  Map<String, String> validateAnswersForForm(
    StatusForm activeForm,
    Map<String, dynamic> formAnswers,
  ) {
    return _engine.validateFields(
      fieldsForForm(activeForm, answers: formAnswers),
      formAnswers,
    );
  }

  Future<Booking?> submitForm({
    required StatusForm activeForm,
    required Map<String, dynamic> formAnswers,
    required UserModel clientUser,
    required String submittedByUserId,
    required String? submittedByUserRole,
  }) async {
    if (blockedMessageForForm(activeForm, clientUser) != null) {
      notifyListeners();
      return null;
    }

    isSubmitting = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 16));

    try {
      final now = DateTime.now();
      final normalizedAnswers = _answersWithMemberSnapshot(formAnswers);
      final baseBooking = Booking(
        client: clientUser,
        clientStatus: activeForm.currentStatusKey,
        createdAt: now,
        updatedAt: now,
      );
      final nextBooking = _engine.applyOutputToBooking(
        baseBooking,
        activeForm,
        fieldsForForm(activeForm, answers: normalizedAnswers),
        normalizedAnswers,
        submittedByUserId,
        submittedByUserRole,
      );
      return await _bookingRepository.saveBooking(nextBooking);
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  Future<Booking?> submit({
    required UserModel clientUser,
    required String submittedByUserId,
    required String? submittedByUserRole,
  }) async {
    final activeForm = form;
    if (activeForm == null) {
      loadError = 'No client booking form is available yet.';
      notifyListeners();
      return null;
    }
    if (!validateForSubmit()) {
      return null;
    }

    isSubmitting = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 16));

    try {
      final now = DateTime.now();
      final normalizedAnswers = _answersWithMemberSnapshot(answers);
      final baseBooking = Booking(
        client: clientUser,
        clientStatus: activeForm.currentStatusKey,
        createdAt: now,
        updatedAt: now,
      );
      final nextBooking = _engine.applyOutputToBooking(
        baseBooking,
        activeForm,
        fields,
        normalizedAnswers,
        submittedByUserId,
        submittedByUserRole,
      );
      final savedBooking = await _bookingRepository.saveBooking(nextBooking);
      answers = {};
      errors = {};
      resetTick += 1;
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

    final validationErrors = _engine.validateFields(fields, answers);
    errors = validationErrors;
    notifyListeners();
    return validationErrors.isEmpty;
  }

  String resolvedTitle() {
    final activeForm = form;
    if (activeForm == null) {
      return 'Client Booking';
    }
    return resolvedTitleForForm(activeForm);
  }

  String resolvedTitleForForm(StatusForm activeForm) {
    final customTitle = activeForm.statusText?.trim();
    if (customTitle?.isNotEmpty == true) {
      return customTitle!;
    }
    final key = activeForm.currentStatusKey;
    if (key == null || key.isEmpty) {
      return 'Client Booking';
    }
    final status = statuses.cast<Status?>().firstWhere(
      (item) => item?.key == key,
      orElse: () => null,
    );
    final label = status?.label?.trim();
    return label?.isNotEmpty == true ? label! : 'Client Booking';
  }

  String? resolvedSubtitle() {
    final activeForm = form;
    if (activeForm == null) {
      return null;
    }
    return resolvedSubtitleForForm(activeForm);
  }

  String? resolvedSubtitleForForm(StatusForm activeForm) {
    final customSubtitle = activeForm.statusSubtext?.trim();
    if (customSubtitle?.isNotEmpty == true) {
      return customSubtitle;
    }
    final key = activeForm.currentStatusKey;
    if (key == null || key.isEmpty) {
      return null;
    }
    final status = statuses.cast<Status?>().firstWhere(
      (item) => item?.key == key,
      orElse: () => null,
    );
    final description = status?.description?.trim();
    return description?.isNotEmpty == true ? description : null;
  }

  String submitLabel() {
    final text = form?.buttonText?.trim();
    return text?.isNotEmpty == true ? text! : 'Submit';
  }

  String submitLabelForForm(StatusForm activeForm) {
    final text = activeForm.buttonText?.trim();
    return text?.isNotEmpty == true ? text! : 'Submit';
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

  String? _resolveBlockedMessage(UserModel clientUser) {
    final activeForm = form;
    if (activeForm == null) {
      return null;
    }
    return blockedMessageForForm(activeForm, clientUser);
  }

  String? blockedMessageForForm(StatusForm activeForm, UserModel clientUser) {
    final dependencyCheckBooking = Booking(
      client: clientUser,
      clientStatus: activeForm.currentStatusKey,
    );
    return _engine.getBlockedMessage(dependencyCheckBooking, activeForm);
  }

  bool _isMemberField(StatusField field) {
    final key = (field.key ?? '').trim().toLowerCase();
    final sourceKey = StatusFieldOptionResolver.resolvedOptionSourceKey(field);
    return key == representativeIdKey ||
        sourceKey == statusFieldOptionSourceClientMembers;
  }

  Map<String, dynamic> _answersWithMemberSnapshot(
    Map<String, dynamic> answers,
  ) {
    final memberId = normalizeId(answers[representativeIdKey]?.toString());
    if (memberId == null) {
      return answers;
    }
    final matchedMember = activeMembers
        .where((member) => member.id == memberId)
        .firstOrNull;
    if (matchedMember == null) {
      return answers;
    }

    final nextAnswers = Map<String, dynamic>.from(answers);
    nextAnswers[representativeIdKey] = memberId;
    return nextAnswers;
  }
}
