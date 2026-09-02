import 'dart:async';

import 'package:stacked/stacked.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/status.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/utils/functions.dart';
import 'package:webapp/utils/performance_trace.dart';
import 'package:webapp/models/status_form.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/requests/status.request.dart';
import 'package:webapp/requests/booking.request.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/services/network_status_events.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:webapp/services/status_field_option_resolver.dart';
import 'package:webapp/services/status_form_engine.dart';
import 'package:webapp/services/app_warmup_service.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/repositories/interfaces/booking_repository.dart';
import 'package:webapp/repositories/interfaces/status_form_repository.dart';
import 'package:webapp/repositories/interfaces/vehicle_catalog_repository.dart';

class ClientBookingHomeViewModel extends BaseViewModel {
  ClientBookingHomeViewModel({
    StatusFormRepository? statusRepository,
    BookingRepository? bookingRepository,
    AuthRepository? authRepository,
    VehicleCatalogRepository? vehicleCatalogRepository,
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
    _hasLoadedOnce = _cachedHasLoadedOnce;
  }

  final StatusFormRepository _statusRepository;
  final BookingRepository _bookingRepository;
  final StatusFormEngine _engine;
  final StatusFieldOptionResolver _optionResolver = StatusFieldOptionResolver();
  final AppWarmupService _warmupService = AppWarmupService.instance;
  StreamSubscription<void>? _statusCacheUpdatesSubscription;
  StreamSubscription<void>? _usersCacheUpdatesSubscription;
  StreamSubscription<void>? _catalogCacheUpdatesSubscription;
  Timer? _realtimeReloadDebounce;
  static List<StatusForm> _cachedMainForms = const [];
  static Map<String, List<StatusField>> _cachedFieldsByFormId = const {};
  static StatusForm? _cachedForm;
  static List<StatusField> _cachedFields = const [];
  static List<Status> _cachedStatuses = const [];
  static String? _cachedLoadError;
  static String? _cachedBlockedMessage;
  static UserModel? _cachedActiveClientUser;
  static bool _cachedHasLoadedOnce = false;

  static void clearCachedState() {
    _cachedMainForms = const [];
    _cachedFieldsByFormId = const {};
    _cachedForm = null;
    _cachedFields = const [];
    _cachedStatuses = const [];
    _cachedLoadError = null;
    _cachedBlockedMessage = null;
    _cachedActiveClientUser = null;
    _cachedHasLoadedOnce = false;
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
  String? _pendingSubmissionKey;
  int resetTick = 0;
  UserModel? _activeClientUser;
  UserModel? _pendingClientUser;
  bool _isRealtimeRefreshing = false;
  bool _hasLoadedOnce = false;
  static const representativeNameKey = 'representative_name';
  static const representativePhoneKey = 'representative_phone';

  Future<void> load(UserModel clientUser) async {
    _log(
      'load start user=${clientUser.id ?? "-"} role=${clientUser.role ?? "-"} visiblePrimary=${mainForms.isNotEmpty || form != null || fields.isNotEmpty || _cachedMainForms.isNotEmpty || _cachedForm != null || _cachedFields.isNotEmpty} cachedForms=${_cachedMainForms.length} cachedFields=${_cachedFields.length}',
    );
    _ensureRealtimeSubscriptions();
    if (isBusyLoading) {
      _pendingClientUser = clientUser;
      _log('load queued pendingClient=${clientUser.id ?? "-"}');
      return;
    }

    final canReuseLoadedForm =
        _hasLoadedOnce &&
        _activeClientUser?.id == clientUser.id &&
        _activeClientUser?.updatedAt == clientUser.updatedAt &&
        mainForms.isNotEmpty &&
        form != null &&
        fields.isNotEmpty;
    if (canReuseLoadedForm) {
      _log('load skip reused shared form client=${clientUser.id ?? "-"}');
      return;
    }

    final hasVisiblePrimaryData =
        mainForms.isNotEmpty ||
        form != null ||
        fields.isNotEmpty ||
        _cachedMainForms.isNotEmpty ||
        _cachedForm != null ||
        _cachedFields.isNotEmpty;
    isBusyLoading = !_hasLoadedOnce && !hasVisiblePrimaryData;
    _log(
      'load mode busy=$isBusyLoading hasLoadedOnce=$_hasLoadedOnce activeClient=${_activeClientUser?.id ?? "-"}',
    );
    loadError = null;
    blockedMessage = null;
    if (!currentNetworkStatus()) {
      // A new modal has no in-memory flow graph after a reload. Restore the
      // previously loaded Firestore form library before resolving the booking
      // form, so offline creation remains available.
      await StatusRequest.instance.primeResolvedSnapshotsFromLocalCache();
    }
    _primeSharedBookFormData(clientUser);
    notifyListeners();

    try {
      _log('initialize repositories start');
      await Future.wait([_bookingRepository.initialize()]);
      _log('initialize repositories done');

      _log('primary queries start');
      final results = await Future.wait([
        _statusRepository.getStatuses(),
        _statusRepository.getStatusFormsByRoleAndStatus('client', 'book'),
      ]);
      _log('primary queries done');
      statuses = results[0] as List<Status>;
      final bookForms = results[1] as List<StatusForm>;
      final loadedMainForms = bookForms
          .where((item) => item.isActive != false && item.resolvedIsMainForm)
          .toList();
      mainForms = loadedMainForms;
      form = mainForms.firstOrNull;
      _log(
        'primary resolved forms=${mainForms.length} activeForm=${form?.id ?? "-"} statuses=${statuses.length}',
      );
      if (form == null) {
        mainForms = [];
        _fieldsByFormId.clear();
        fields = [];
        answers = {};
        errors = {};
        _log('load ended no-form');
        return;
      }

      _fieldsByFormId.clear();
      _log('field hydration start forms=${mainForms.length}');
      final fieldEntries = await Future.wait(
        mainForms.map((loadedForm) async {
          final formId = loadedForm.id ?? '';
          if (formId.isEmpty) {
            return MapEntry(formId, const <StatusField>[]);
          }
          final resolvedFields = await _optionResolver.hydrateFields(
            await _statusRepository.getFields(formId),
          );
          return MapEntry(formId, resolvedFields);
        }),
      );
      _log('field hydration done entries=${fieldEntries.length}');
      for (final entry in fieldEntries) {
        _fieldsByFormId[entry.key] = entry.value;
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
      _hasLoadedOnce = true;
      _cachedHasLoadedOnce = true;
      _log(
        'load success user=${clientUser.id ?? "-"} role=${clientUser.role ?? "-"} forms=${mainForms.length} activeForm=${form?.id ?? "-"} visibleFields=${fields.length} statuses=${statuses.length} blocked=${blockedMessage != null}',
      );
      unawaited(_warmupService.warmUpForUser(clientUser));
    } catch (error) {
      _log(
        'load error user=${clientUser.id ?? "-"} role=${clientUser.role ?? "-"} error=$error',
      );
      loadError = userFacingErrorMessage(
        error,
        fallback: 'We could not load the booking form right now.',
      );
      _cachedLoadError = loadError;
      _hasLoadedOnce = true;
      _cachedHasLoadedOnce = true;
    } finally {
      isBusyLoading = false;
      _log(
        'load finish user=${clientUser.id ?? "-"} role=${clientUser.role ?? "-"} busy=$isBusyLoading error=${loadError ?? "-"} pendingClient=${_pendingClientUser?.id ?? "-"}',
      );
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

  void _primeSharedBookFormData(UserModel clientUser) {
    final hasSharedStatuses = StatusRequest.hasResolvedStatuses;
    final hasSharedForms = StatusRequest.hasResolvedForms;
    if ((!hasSharedStatuses && !hasSharedForms) || mainForms.isNotEmpty) {
      return;
    }
    if (hasSharedStatuses && statuses.isEmpty) {
      statuses = List<Status>.from(StatusRequest.hydratedStatusesSnapshot);
    }
    if (hasSharedForms && mainForms.isEmpty) {
      final sharedBookForms = _sharedBookForms();
      if (sharedBookForms.isNotEmpty) {
        mainForms = sharedBookForms;
        form = mainForms.firstOrNull;
        final hydratedSharedLibrary = _optionResolver
            .hydrateFieldsFromResolvedSnapshots(
              List<StatusField>.from(StatusRequest.hydratedFieldsSnapshot),
            );
        _fieldsByFormId.clear();
        for (final sharedForm in mainForms) {
          final formId = sharedForm.id ?? '';
          if (formId.isEmpty) {
            continue;
          }
          final resolvedFields = sharedForm.fields
              .map((field) {
                final normalizedId = normalizeId(field.id);
                final normalizedKey = normalizeId(field.key);
                final hydratedField = hydratedSharedLibrary.firstWhere(
                  (candidate) =>
                      (normalizedId != null &&
                          normalizeId(candidate.id) == normalizedId) ||
                      (normalizedKey != null &&
                          normalizeId(candidate.key) == normalizedKey),
                  orElse: () => field,
                );
                return hydratedField.copyWith(
                  statusForm: sharedForm.toReferenceForm(),
                );
              })
              .toList(growable: false);
          _fieldsByFormId[formId] = resolvedFields;
        }
        if (form != null) {
          fields = fieldsForForm(form!);
        }
      }
    }
    _activeClientUser = clientUser;
    blockedMessage = _resolveBlockedMessage(clientUser);
  }

  List<StatusForm> _sharedBookForms() {
    final statuses = StatusRequest.hydratedStatusesSnapshot;
    bool isKnownActiveStatus(String? statusKey) {
      final normalizedStatusKey = statusKey?.trim().toLowerCase() ?? '';
      if (normalizedStatusKey.isEmpty) {
        return false;
      }
      for (final status in statuses) {
        if ((status.key?.trim().toLowerCase() ?? '') == normalizedStatusKey) {
          return status.isActive != false;
        }
      }
      return false;
    }

    bool isKnownActiveStatusOrTerminal(String? statusKey) {
      final normalizedStatusKey = statusKey?.trim() ?? '';
      if (normalizedStatusKey.isEmpty) {
        return true;
      }
      return isKnownActiveStatus(normalizedStatusKey);
    }

    final resolvedRoles = RoleAccessService.instance.workflowResolutionRoles(
      'client',
    );
    final matchingForms = StatusRequest.hydratedFormsSnapshot
        .where((form) {
          return resolvedRoles.any(form.resolvedRoles.contains) &&
              (form.currentStatusKey?.trim().toLowerCase() ?? '') == 'book' &&
              form.isActive != false &&
              form.resolvedIsMainForm &&
              isKnownActiveStatus(form.currentStatusKey) &&
              isKnownActiveStatusOrTerminal(form.nextStatusKey);
        })
        .map((form) => form.copyWith())
        .toList(growable: false);
    matchingForms.sort((left, right) {
      final leftUpdated = left.updatedAt ?? left.createdAt ?? DateTime(0);
      final rightUpdated = right.updatedAt ?? right.createdAt ?? DateTime(0);
      return leftUpdated.compareTo(rightUpdated);
    });
    return matchingForms;
  }

  void _ensureRealtimeSubscriptions() {
    _statusCacheUpdatesSubscription ??= StatusRequest.instance
        .watchStatusCacheUpdates()
        .listen((_) {
          _scheduleRealtimeReload();
        });
    _usersCacheUpdatesSubscription ??= AuthRequest.instance
        .watchUsersCacheUpdates()
        .listen((_) {
          _scheduleRealtimeReload();
        });
    _catalogCacheUpdatesSubscription ??= VehicleRequest.instance
        .watchCatalogCacheUpdates()
        .listen((_) {
          _scheduleRealtimeReload();
        });
  }

  void _scheduleRealtimeReload() {
    // The form is already backed by shared snapshots. Replaying every catalog
    // cache event after it is visible only starves UI work and submission.
    if (_hasLoadedOnce && mainForms.isNotEmpty && fields.isNotEmpty) {
      return;
    }
    if (_realtimeReloadDebounce?.isActive ?? false) {
      return;
    }
    _realtimeReloadDebounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_reloadFromRealtime());
    });
  }

  Future<void> _reloadFromRealtime() async {
    if (_isRealtimeRefreshing || _activeClientUser == null) {
      return;
    }
    _isRealtimeRefreshing = true;
    _log(
      'realtime reload start user=${_activeClientUser?.id ?? "-"} role=${_activeClientUser?.role ?? "-"}',
    );
    try {
      // These subscriptions are notified after their repositories update the
      // shared cache. Reading those repositories again here emits another
      // cache update and creates a reload loop.
      final refreshedClient =
          AuthRequest.hydratedUsersSnapshot
              .where((item) => item.id == _activeClientUser?.id)
              .firstOrNull ??
          _activeClientUser;
      await load(refreshedClient!);
    } catch (_) {
      // Keep current visible state if live support data refresh fails.
    } finally {
      _isRealtimeRefreshing = false;
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

    final visibleFields = StatusFormEngine.visibleFields(
      resolvedFields,
      answers ?? this.answers,
    );
    return visibleFields;
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
    if (isSubmitting) {
      return null;
    }
    final blocked = blockedMessageForForm(activeForm, clientUser);
    if (blocked != null) {
      notifyListeners();
      return null;
    }

    isSubmitting = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 16));

    try {
      final now = DateTime.now();
      final submissionKey = _pendingSubmissionKey ??= _createSubmissionKey(
        submittedByUserId: submittedByUserId,
        clientUserId: clientUser.id,
        formId: activeForm.id,
      );
      final normalizedAnswers = _normalizeRepresentativeAnswers(formAnswers);
      final baseBooking = Booking(
        client: clientUser,
        clientStatus: activeForm.currentStatusKey,
        createdAt: now,
        updatedAt: now,
        submissionKey: submissionKey,
      );
      final nextBooking = _engine.applyOutputToBooking(
        baseBooking,
        activeForm,
        fieldsForForm(activeForm, answers: normalizedAnswers),
        normalizedAnswers,
        submittedByUserId,
        submittedByUserRole,
      );
      final saved = await _bookingRepository.saveBooking(nextBooking);
      _pendingSubmissionKey = null;
      return saved;
    } catch (error) {
      rethrow;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _realtimeReloadDebounce?.cancel();
    _statusCacheUpdatesSubscription?.cancel();
    _usersCacheUpdatesSubscription?.cancel();
    _catalogCacheUpdatesSubscription?.cancel();
    super.dispose();
  }

  Future<Booking?> submit({
    required UserModel clientUser,
    required String submittedByUserId,
    required String? submittedByUserRole,
  }) async {
    if (isSubmitting) {
      return null;
    }
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
      final submissionKey = _pendingSubmissionKey ??= _createSubmissionKey(
        submittedByUserId: submittedByUserId,
        clientUserId: clientUser.id,
        formId: activeForm.id,
      );
      final normalizedAnswers = _normalizeRepresentativeAnswers(answers);
      final baseBooking = Booking(
        client: clientUser,
        clientStatus: activeForm.currentStatusKey,
        createdAt: now,
        updatedAt: now,
        submissionKey: submissionKey,
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
      _pendingSubmissionKey = null;
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

  String _createSubmissionKey({
    required String submittedByUserId,
    required String? clientUserId,
    required String? formId,
  }) {
    final submitter = submittedByUserId.trim().isEmpty
        ? 'anonymous'
        : submittedByUserId.trim();
    final client = clientUserId?.trim().isNotEmpty == true
        ? clientUserId!.trim()
        : 'unknown-client';
    final form = formId?.trim().isNotEmpty == true ? formId!.trim() : 'form';
    return 'booking_${submitter}_${client}_${form}_${DateTime.now().microsecondsSinceEpoch}';
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

  Map<String, dynamic> _normalizeRepresentativeAnswers(
    Map<String, dynamic> answers,
  ) {
    final nextAnswers = Map<String, dynamic>.from(answers);
    final representativeName =
        nextAnswers[representativeNameKey]?.toString().trim() ?? '';
    if (representativeName.isNotEmpty) {
      nextAnswers[representativeNameKey] = representativeName;
    }
    final representativePhone =
        normalizePhilippinePhone(
          nextAnswers[representativePhoneKey]?.toString(),
        ) ??
        nextAnswers[representativePhoneKey]?.toString().trim() ??
        '';
    if (representativePhone.isNotEmpty) {
      nextAnswers[representativePhoneKey] = representativePhone;
    }
    return nextAnswers;
  }

  void _log(String message) {
    PerformanceTrace.event('client-booking-form-vm', message);
  }
}
