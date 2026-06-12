import 'package:stacked/stacked.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/status.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/models/status_form.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/booking.request.dart';
import 'package:webapp/requests/status.request.dart';
import 'package:webapp/repositories/interfaces/booking_repository.dart';
import 'package:webapp/repositories/interfaces/status_form_repository.dart';
import 'package:webapp/services/status_field_option_resolver.dart';
import 'package:webapp/services/status_form_engine.dart';
import 'package:webapp/utils/functions.dart';

class ClientBookingHomeViewModel extends BaseViewModel {
  ClientBookingHomeViewModel({
    StatusFormRepository? statusRepository,
    BookingRepository? bookingRepository,
  }) : _statusRepository = statusRepository ?? StatusRequest.instance,
       _bookingRepository = bookingRepository ?? BookingRequest.instance,
       _engine = StatusFormEngine(statusRepository ?? StatusRequest.instance) {
    mainForms = List<StatusForm>.from(_cachedMainForms);
    form = _cachedForm;
    fields = List<StatusField>.from(_cachedFields);
    statuses = List<Status>.from(_cachedStatuses);
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
  final StatusFormEngine _engine;
  final StatusFieldOptionResolver _optionResolver = StatusFieldOptionResolver();
  static List<StatusForm> _cachedMainForms = const [];
  static Map<String, List<StatusField>> _cachedFieldsByFormId = const {};
  static StatusForm? _cachedForm;
  static List<StatusField> _cachedFields = const [];
  static List<Status> _cachedStatuses = const [];
  static String? _cachedLoadError;
  static String? _cachedBlockedMessage;
  static UserModel? _cachedActiveClientUser;

  static void clearCachedState() {
    _cachedMainForms = const [];
    _cachedFieldsByFormId = const {};
    _cachedForm = null;
    _cachedFields = const [];
    _cachedStatuses = const [];
    _cachedLoadError = null;
    _cachedBlockedMessage = null;
    _cachedActiveClientUser = null;
  }

  List<StatusForm> mainForms = [];
  final Map<String, List<StatusField>> _fieldsByFormId = {};
  StatusForm? form;
  List<StatusField> fields = [];
  List<Status> statuses = [];
  Map<String, dynamic> answers = {};
  Map<String, String> errors = {};
  String? loadError;
  String? blockedMessage;
  bool isBusyLoading = false;
  bool isSubmitting = false;
  int resetTick = 0;
  UserModel? _activeClientUser;

  Future<void> load(UserModel clientUser) async {
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
      final bookForms = await _statusRepository.getStatusFormsByRoleAndStatus(
        'client',
        'book',
      );
      final loadedMainForms = bookForms
          .where((item) => item.isActive != false && item.resolvedIsMainForm)
          .toList();
      mainForms = loadedMainForms;

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
      _activeClientUser = clientUser;
      blockedMessage = _resolveBlockedMessage(clientUser);
      _cachedMainForms = List<StatusForm>.from(mainForms);
      _cachedFieldsByFormId = _fieldsByFormId.map(
        (key, value) => MapEntry(key, List<StatusField>.from(value)),
      );
      _cachedForm = form;
      _cachedFields = List<StatusField>.from(fields);
      _cachedStatuses = List<Status>.from(statuses);
      _cachedLoadError = null;
      _cachedBlockedMessage = blockedMessage;
      _cachedActiveClientUser = _activeClientUser;
    } catch (error) {
      loadError = userFacingErrorMessage(
        error,
        fallback: 'We could not load the booking form right now.',
      );
      _cachedLoadError = loadError;
    } finally {
      isBusyLoading = false;
      notifyListeners();
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
    required UserModel clientUser,
    required String submittedByUserId,
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
      final baseBooking = Booking(
        client: clientUser,
        clientStatus: activeForm.currentStatusKey,
        createdAt: now,
        updatedAt: now,
      );
      final nextBooking = _engine.applyOutputToBooking(
        baseBooking,
        activeForm,
        fieldsForForm(activeForm),
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
    required UserModel clientUser,
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
    await Future<void>.delayed(const Duration(milliseconds: 16));

    try {
      final now = DateTime.now();
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
}
