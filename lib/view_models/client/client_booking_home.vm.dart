import 'package:stacked/stacked.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/status_definition.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/models/status_form.dart';
import 'package:webapp/repositories/local/local_booking_repository.dart';
import 'package:webapp/repositories/local/local_status_form_repository.dart';
import 'package:webapp/services/status_field_option_resolver.dart';
import 'package:webapp/services/status_form_engine.dart';

class ClientBookingHomeViewModel extends BaseViewModel {
  ClientBookingHomeViewModel()
      : _statusRepository = LocalStatusFormRepository.instance,
        _bookingRepository = LocalBookingRepository.instance,
        _engine = StatusFormEngine(LocalStatusFormRepository.instance);

  final LocalStatusFormRepository _statusRepository;
  final LocalBookingRepository _bookingRepository;
  final StatusFormEngine _engine;
  final StatusFieldOptionResolver _optionResolver = StatusFieldOptionResolver();

  List<StatusForm> mainForms = [];
  final Map<String, List<StatusField>> _fieldsByFormId = {};
  StatusForm? form;
  List<StatusField> fields = [];
  List<StatusDefinition> statuses = [];
  Map<String, dynamic> answers = {};
  Map<String, String> errors = {};
  String? loadError;
  String? blockedMessage;
  bool isBusyLoading = false;
  bool isSubmitting = false;
  int resetTick = 0;
  String? _activeClientId;

  Future<void> load(String clientId) async {
    if (isBusyLoading) {
      return;
    }

    isBusyLoading = true;
    loadError = null;
    blockedMessage = null;
    notifyListeners();

    try {
      await _bookingRepository.initialize();

      statuses = await _statusRepository.getStatuses();
      final seededBookForms = await _statusRepository.getStatusFormsByRoleAndStatus(
        'client',
        'book',
      );
      final loadedMainForms = seededBookForms
          .where((item) => item.isActive != false && item.resolvedIsMainForm)
          .toList();
      if (loadedMainForms.isNotEmpty) {
        mainForms = loadedMainForms;
      } else {
        final forms = await _statusRepository.getStatusForms();
        final fallbackForm = forms.cast<StatusForm?>().firstWhere(
          (item) => item?.role == 'client' && item?.isActive != false,
          orElse: () => null,
        );
        mainForms = fallbackForm == null ? const [] : [fallbackForm];
      }

      form = mainForms.firstOrNull;
      if (form == null) {
        mainForms = [];
        _fieldsByFormId.clear();
        fields = [];
        answers = {};
        errors = {};
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
      _activeClientId = clientId;
      blockedMessage = _resolveBlockedMessage(clientId);
    } catch (_) {
      loadError = 'Failed to load the booking form.';
    } finally {
      isBusyLoading = false;
      notifyListeners();
    }
  }

  void syncClient(String clientId) {
    if (_activeClientId == clientId) {
      return;
    }
    _activeClientId = clientId;
    answers = {};
    errors = {};
    resetTick += 1;
    blockedMessage = _resolveBlockedMessage(clientId);
    notifyListeners();
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

  List<StatusField> fieldsForForm(StatusForm activeForm) {
    return _fieldsByFormId[activeForm.id ?? ''] ?? const [];
  }

  Map<String, String> validateAnswersForForm(
    StatusForm activeForm,
    Map<String, dynamic> formAnswers,
  ) {
    return _engine.validateFields(fieldsForForm(activeForm), formAnswers);
  }

  Future<Booking?> submitForm({
    required StatusForm activeForm,
    required Map<String, dynamic> formAnswers,
    required String clientId,
    required String submittedByUserId,
  }) async {
    if (blockedMessageForForm(activeForm, clientId) != null) {
      notifyListeners();
      return null;
    }

    isSubmitting = true;
    notifyListeners();

    try {
      final now = DateTime.now();
      final baseBooking = Booking(
        clientId: clientId,
        clientStatus: activeForm.currentStatusKey,
        createdAt: now,
        updatedAt: now,
      );
      final nextBooking = _engine.applyOutputToBooking(
        baseBooking,
        activeForm,
        formAnswers,
        submittedByUserId,
      );
      return await _bookingRepository.saveBooking(nextBooking);
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  Future<Booking?> submit({
    required String clientId,
    required String submittedByUserId,
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

    try {
      final now = DateTime.now();
      final baseBooking = Booking(
        clientId: clientId,
        clientStatus: activeForm.currentStatusKey,
        createdAt: now,
        updatedAt: now,
      );
      final nextBooking = _engine.applyOutputToBooking(
        baseBooking,
        activeForm,
        answers,
        submittedByUserId,
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
    final status = statuses.cast<StatusDefinition?>().firstWhere(
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
    final status = statuses.cast<StatusDefinition?>().firstWhere(
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

  String? _resolveBlockedMessage(String clientId) {
    final activeForm = form;
    if (activeForm == null) {
      return null;
    }
    return blockedMessageForForm(activeForm, clientId);
  }

  String? blockedMessageForForm(StatusForm activeForm, String clientId) {
    final dependencyCheckBooking = Booking(
      clientId: clientId,
      clientStatus: activeForm.currentStatusKey,
    );
    return _engine.getBlockedMessage(dependencyCheckBooking, activeForm);
  }

}
