import 'dart:async';

import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/models/status_form.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/view_models/client/client_booking_home.vm.dart';
import 'package:webapp/services/local_form_draft_service.dart';
import 'package:webapp/widgets/shared/admin_action_confirmation.dart';
import 'package:webapp/widgets/shared/app_page_loading_overlay.dart';
import 'package:webapp/widgets/shared/app_refresh_strip.dart';
import 'package:webapp/widgets/shared/app_snackbar.dart';
import 'package:webapp/widgets/shared/booking_form_primitives.dart';
import 'package:webapp/widgets/status_form/status_form_runtime_fields.dart';

class _ClientFormHeaderPalette {
  const _ClientFormHeaderPalette({
    required this.backgroundColor,
    required this.borderColor,
    required this.titleColor,
    required this.subtitleColor,
  });

  final Color backgroundColor;
  final Color borderColor;
  final Color titleColor;
  final Color subtitleColor;
}

_ClientFormHeaderPalette? _terminalClientHeaderPalette(String? statusKey) {
  switch (statusKey?.trim()) {
    case 'delivered':
      return const _ClientFormHeaderPalette(
        backgroundColor: Color(0xFF2EAD62),
        borderColor: Color(0xFF2EAD62),
        titleColor: AppColors.textPrimary,
        subtitleColor: AppColors.textPrimary,
      );
    case 'cancelled':
      return const _ClientFormHeaderPalette(
        backgroundColor: AppColors.dangerStrong,
        borderColor: AppColors.dangerStrong,
        titleColor: AppColors.textPrimary,
        subtitleColor: AppColors.textPrimary,
      );
    default:
      return null;
  }
}

class ClientBookingHomeView extends StatefulWidget {
  const ClientBookingHomeView({
    super.key,
    required this.user,
    this.onBookingSubmitted,
    this.submitBlockMessage,
    this.bookingClientUser,
    this.submittedByUserId,
    this.padding = const EdgeInsets.fromLTRB(24, 24, 24, 24),
    this.scrollable = true,
    this.loadingPlaceholderMinHeight,
    this.loadingOverlayVisibleHeight,
    this.loadingOverlayAlignmentY = 0,
    this.onRepresentativeTapWithoutClient,
  });

  final UserModel user;
  final ValueChanged<Booking>? onBookingSubmitted;
  final String? Function()? submitBlockMessage;
  final UserModel? bookingClientUser;
  final String? submittedByUserId;
  final EdgeInsets padding;
  final bool scrollable;
  final double? loadingPlaceholderMinHeight;
  final double? loadingOverlayVisibleHeight;
  final double loadingOverlayAlignmentY;
  final VoidCallback? onRepresentativeTapWithoutClient;

  @override
  State<ClientBookingHomeView> createState() => _ClientBookingHomeViewState();
}

class _ClientBookingHomeViewState extends State<ClientBookingHomeView> {
  ClientBookingHomeViewModel? _viewModel;

  UserModel get _effectiveClientUser {
    return widget.bookingClientUser ?? widget.user;
  }

  String get _effectiveSubmittedByUserId =>
      widget.submittedByUserId ?? widget.user.id ?? '';

  String? get _effectiveSubmittedByUserRole => widget.user.role;

  double get _loadingPlaceholderMinHeight =>
      widget.loadingPlaceholderMinHeight ?? 220;

  void _restoreScrollOffset(ScrollPosition? position, double? offset) {
    if (position == null || offset == null) {
      return;
    }
    void restoreOnNextFrame([int remainingPasses = 2]) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !position.hasPixels) {
          return;
        }
        final clampedOffset = offset.clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        if ((position.pixels - clampedOffset).abs() >= 0.5) {
          position.jumpTo(clampedOffset);
        }
        if (remainingPasses > 1) {
          restoreOnNextFrame(remainingPasses - 1);
        }
      });
    }

    restoreOnNextFrame();
  }

  void _unfocusWithoutScroll(BuildContext context) {
    final scrollPosition = Scrollable.maybeOf(context)?.position;
    final scrollOffset = scrollPosition?.hasPixels == true
        ? scrollPosition!.pixels
        : null;
    FocusScope.of(context).unfocus();
    _restoreScrollOffset(scrollPosition, scrollOffset);
  }

  @override
  void didUpdateWidget(covariant ClientBookingHomeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldClientUser = oldWidget.bookingClientUser ?? oldWidget.user;
    if (oldClientUser.id != _effectiveClientUser.id ||
        oldClientUser.updatedAt != _effectiveClientUser.updatedAt) {
      _viewModel?.syncClient(_effectiveClientUser);
      _viewModel?.load(_effectiveClientUser);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<ClientBookingHomeViewModel>.reactive(
      viewModelBuilder: ClientBookingHomeViewModel.new,
      onViewModelReady: (vm) {
        _viewModel = vm;
        vm.load(_effectiveClientUser);
      },
      builder: (context, vm, _) {
        _viewModel = vm;
        final loadError = vm.loadError;
        if (loadError != null) {
          return AppPageLoadingOverlay(
            isVisible: vm.isBusyLoading,
            message: 'Loading booking form ...',
            visibleHeightWhenUnbounded: widget.loadingOverlayVisibleHeight,
            loadingAlignmentY: widget.loadingOverlayAlignmentY,
            child: _ClientBookingStateCard(
              scrollable: widget.scrollable,
              padding: widget.padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppRefreshStrip(isVisible: vm.isBusyLoading),
                  Text(
                    loadError,
                    style: TextStyle(
                      color: AppColors.primaryColor.withValues(alpha: 0.72),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final form = vm.form;
        if (form == null || vm.mainForms.isEmpty) {
          return AppPageLoadingOverlay(
            isVisible: vm.isBusyLoading,
            message: 'Loading booking form ...',
            visibleHeightWhenUnbounded: widget.loadingOverlayVisibleHeight,
            loadingAlignmentY: widget.loadingOverlayAlignmentY,
            child: _ClientBookingStateCard(
              scrollable: widget.scrollable,
              padding: widget.padding,
              child: SizedBox(
                width: double.infinity,
                height: _loadingPlaceholderMinHeight,
                child: vm.isBusyLoading
                    ? const SizedBox.shrink()
                    : Center(
                        child: Text(
                          'No client booking form available yet.',
                          style: TextStyle(
                            color: AppColors.primaryColor.withValues(
                              alpha: 0.72,
                            ),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
              ),
            ),
          );
        }

        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...vm.mainForms.asMap().entries.map((entry) {
              final activeForm = entry.value;
              return Padding(
                padding: EdgeInsets.only(
                  bottom: entry.key == vm.mainForms.length - 1 ? 0 : 18,
                ),
                child: _ClientBookingFormSection(
                  key: ValueKey(activeForm.id),
                  vm: vm,
                  form: activeForm,
                  clientUser: _effectiveClientUser,
                  submittedByUserId: _effectiveSubmittedByUserId,
                  submittedByUserRole: _effectiveSubmittedByUserRole,
                  submitBlockMessage: widget.submitBlockMessage,
                  onRepresentativeTapWithoutClient:
                      widget.onRepresentativeTapWithoutClient,
                  onBookingSubmitted: widget.onBookingSubmitted,
                  onUnfocusWithoutScroll: () => _unfocusWithoutScroll(context),
                ),
              );
            }),
          ],
        );

        final scaffold = widget.scrollable
            ? SingleChildScrollView(padding: widget.padding, child: content)
            : Padding(padding: widget.padding, child: content);
        return AppPageLoadingOverlay(
          isVisible: vm.isBusyLoading,
          message: 'Loading booking form ...',
          visibleHeightWhenUnbounded: widget.loadingOverlayVisibleHeight,
          loadingAlignmentY: widget.loadingOverlayAlignmentY,
          child: scaffold,
        );
      },
    );
  }
}

class _ClientBookingFormSection extends StatefulWidget {
  const _ClientBookingFormSection({
    super.key,
    required this.vm,
    required this.form,
    required this.clientUser,
    required this.submittedByUserId,
    required this.submittedByUserRole,
    required this.onUnfocusWithoutScroll,
    this.submitBlockMessage,
    this.onBookingSubmitted,
    this.onRepresentativeTapWithoutClient,
  });

  final ClientBookingHomeViewModel vm;
  final StatusForm form;
  final UserModel clientUser;
  final String submittedByUserId;
  final String? submittedByUserRole;
  final VoidCallback onUnfocusWithoutScroll;
  final String? Function()? submitBlockMessage;
  final ValueChanged<Booking>? onBookingSubmitted;
  final VoidCallback? onRepresentativeTapWithoutClient;

  @override
  State<_ClientBookingFormSection> createState() =>
      _ClientBookingFormSectionState();
}

class _ClientBookingFormSectionState extends State<_ClientBookingFormSection> {
  final LocalFormDraftService _draftService = LocalFormDraftService.instance;
  Map<String, dynamic> _answers = {};
  Map<String, String> _errors = {};
  int _resetTick = 0;
  bool _isSubmitting = false;
  bool _isHydratingDraft = false;
  final Map<String, FocusNode> _fieldFocusNodes = {};
  final FocusNode _submitFocusNode = FocusNode(
    debugLabel: 'booking_field(__cta__)',
  );

  String _focusKeyForField(StatusField field, int index) {
    final key = (field.key ?? '').trim();
    if (key.isNotEmpty) {
      return key;
    }
    final title = (field.title ?? '').trim();
    final type = (field.type ?? '').trim();
    return '__index_$index:${title.isEmpty ? '-' : title}|${type.isEmpty ? '-' : type}';
  }

  void _syncFocusNodes(List<StatusField> fields) {
    final activeKeys = <String>{};
    for (var index = 0; index < fields.length; index++) {
      final field = fields[index];
      final focusKey = _focusKeyForField(field, index);
      activeKeys.add(focusKey);
      _fieldFocusNodes.putIfAbsent(
        focusKey,
        () => FocusNode(debugLabel: 'booking_field($focusKey)'),
      );
    }

    final removedKeys = _fieldFocusNodes.keys
        .where((key) => !activeKeys.contains(key))
        .toList();
    for (final key in removedKeys) {
      _fieldFocusNodes.remove(key)?.dispose();
    }
  }

  void _moveToNextVisibleFieldAfterSelection(
    StatusField currentField,
    dynamic nextValue,
  ) {
    final currentFieldKey = currentField.key?.trim();
    if (currentFieldKey == null || currentFieldKey.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        FocusScope.of(context).unfocus();
      });
      return;
    }

    final nextAnswers = Map<String, dynamic>.from(_answers);
    if (_isEmptyValue(nextValue)) {
      nextAnswers.remove(currentFieldKey);
    } else {
      nextAnswers[currentFieldKey] = nextValue;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      FocusScope.of(context).unfocus();
    });
  }

  @override
  void dispose() {
    for (final node in _fieldFocusNodes.values) {
      node.dispose();
    }
    _submitFocusNode.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    unawaited(_restoreDraft());
  }

  @override
  void didUpdateWidget(covariant _ClientBookingFormSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldDraftKey = _draftKeyFor(
      formId: oldWidget.form.id,
      clientId: oldWidget.clientUser.id,
      submittedByUserId: oldWidget.submittedByUserId,
    );
    final nextDraftKey = _draftKey;
    if (oldDraftKey == nextDraftKey) {
      return;
    }
    unawaited(_handleDraftIdentityChange(oldDraftKey: oldDraftKey));
  }

  String _draftKeyFor({
    required String? formId,
    required String? clientId,
    required String submittedByUserId,
  }) {
    final normalizedFormId = formId?.trim() ?? '';
    final normalizedClientId = clientId?.trim() ?? '';
    final submittedBy = submittedByUserId.trim();
    if (normalizedFormId.isEmpty || submittedBy.isEmpty) {
      return '';
    }
    return 'booking_form_draft_v1:$submittedBy:$normalizedClientId:$normalizedFormId';
  }

  String get _draftKey {
    return _draftKeyFor(
      formId: widget.form.id,
      clientId: widget.clientUser.id,
      submittedByUserId: widget.submittedByUserId,
    );
  }

  Future<void> _handleDraftIdentityChange({
    required String oldDraftKey,
  }) async {
    final nextDraftKey = _draftKey;
    if (nextDraftKey.isEmpty) {
      return;
    }
    if (_answers.isNotEmpty) {
      if (oldDraftKey.isNotEmpty && oldDraftKey != nextDraftKey) {
        await _draftService.remove(oldDraftKey);
      }
      await _persistDraft();
      return;
    }
    await _restoreDraft();
  }

  Future<void> _restoreDraft() async {
    final draftKey = _draftKey;
    if (draftKey.isEmpty) {
      return;
    }
    final draft = await _draftService.readMap(draftKey);
    if (!mounted || draft == null) {
      return;
    }
    final answers = draft['answers'];
    if (answers is! Map) {
      return;
    }
    _isHydratingDraft = true;
    try {
      setState(() {
        _answers = Map<String, dynamic>.from(answers);
        _errors = {};
      });
    } finally {
      _isHydratingDraft = false;
    }
  }

  Future<void> _persistDraft() async {
    final draftKey = _draftKey;
    if (draftKey.isEmpty || _isHydratingDraft) {
      return;
    }
    if (_answers.isEmpty) {
      await _draftService.remove(draftKey);
      return;
    }
    await _draftService.writeMap(draftKey, <String, dynamic>{
      'answers': _answers,
    });
  }

  Future<void> _clearDraft() async {
    final draftKey = _draftKey;
    if (draftKey.isEmpty) {
      return;
    }
    await _draftService.remove(draftKey);
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final form = widget.form;
    final fields = vm.fieldsForForm(form, answers: _answers);
    final vanSizeField = fields.where((field) {
      final key = (field.key ?? '').trim().toLowerCase();
      return key == 'van_size' || key == 'van_size_id' || key == 'vehicle_size';
    }).firstOrNull;
    if (vanSizeField != null) {
    }
    _syncFocusNodes(fields);
    final blockedMessage = vm.blockedMessageForForm(form, widget.clientUser);
    final terminalPalette = form.nextStatusKey == null
        ? _terminalClientHeaderPalette(form.currentStatusKey)
        : null;
    final palette = bookingFormResolvedStatusPalette(
      title: vm.resolvedTitleForForm(form),
      buttonText: form.buttonText,
      currentStatusKey: form.currentStatusKey,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BookingFormHeaderCard(
          title: vm.resolvedTitleForForm(form),
          subtitle: vm.resolvedSubtitleForForm(form),
          buttonText: form.buttonText,
          paletteOverride: palette,
          backgroundColor: terminalPalette?.backgroundColor,
          borderColor: terminalPalette?.borderColor,
          titleColor: terminalPalette?.titleColor,
          subtitleColor: terminalPalette?.subtitleColor,
          showRequiredLegend: fields.any((field) => field.required == true),
          message: blockedMessage,
          messageBackgroundColor: AppColors.dangerSurface,
          messageBorderColor: AppColors.dangerBorder,
          messageIcon: Icons.block_rounded,
          messageIconColor: AppColors.dangerStrong,
          messageTextColor: AppColors.textPrimary,
        ),
        const SizedBox(height: 8),
        FocusTraversalGroup(
          policy: WidgetOrderTraversalPolicy(),
          child: Column(
            children: fields.asMap().entries.map((entry) {
              final index = entry.key;
              final field = entry.value;
              final focusKey = _focusKeyForField(field, index);
              final isLastField = index == fields.length - 1;
              final nextField = isLastField ? null : fields[index + 1];
              final nextFocusKey = nextField == null
                  ? null
                  : _focusKeyForField(nextField, index + 1);
              final focusNode = _fieldFocusNodes[focusKey];
              final nextFocusNode = isLastField
                  ? _submitFocusNode
                  : (nextFocusKey == null
                        ? null
                        : _fieldFocusNodes[nextFocusKey]);
              final nextFieldType = (nextField?.type ?? '').trim().toLowerCase();
              final activateNextFocus =
                  isLastField ||
                  nextFieldType == 'date' ||
                  nextFieldType == 'time' ||
                  nextFieldType == 'photo';
              final fieldKeyValue = (field.key ?? '').trim();
              final normalizedFieldKey = fieldKeyValue.toLowerCase();
              if (normalizedFieldKey == 'van_size' ||
                  normalizedFieldKey == 'van_size_id' ||
                  normalizedFieldKey == 'vehicle_size') {
              }
              final shouldRedirectRepresentativeTap =
                  fieldKeyValue == ClientBookingHomeViewModel.representativeNameKey &&
                  widget.onRepresentativeTapWithoutClient != null &&
                  (widget.clientUser.id?.trim().isNotEmpty != true);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: StatusFormRuntimeFieldCard(
                  key: ValueKey('${form.id}:${field.key}:$_resetTick'),
                  field: field,
                  focusNode: focusNode,
                  nextFocusNode: nextFocusNode,
                  activateNextFocus: activateNextFocus,
                  onAdvanceAfterSelection: (value) =>
                      _moveToNextVisibleFieldAfterSelection(field, value),
                  errorText: _errors[field.key],
                  initialValue: _answers[field.key],
                  formTitle: vm.resolvedTitleForForm(form),
                  formButtonText: form.buttonText,
                  formStatusKey: form.currentStatusKey,
                  optionLabels: const {},
                  onDisabledTap: shouldRedirectRepresentativeTap
                      ? () {
                          widget.onRepresentativeTapWithoutClient?.call();
                        }
                      : null,
                  onChanged: (value) {
                    final key = field.key;
                    if (key == null || key.isEmpty) {
                      return;
                    }
                    setState(() {
                      final nextAnswers = Map<String, dynamic>.from(_answers);
                      if (_isEmptyValue(value)) {
                        nextAnswers.remove(key);
                      } else {
                        nextAnswers[key] = value;
                      }
                      _answers = nextAnswers;
                      _errors = Map<String, String>.from(_errors)..remove(key);
                    });
                    unawaited(_persistDraft());
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 2),
        _ClientBookingActions(
          isSubmitting: _isSubmitting,
          isBlocked: blockedMessage != null,
          title: vm.resolvedTitleForForm(form),
          focusNode: _submitFocusNode,
          submitLabel: _isSubmitting
              ? 'Submitting ...'
              : vm.submitLabelForForm(form),
          onSubmit: () async {
            final externalBlockMessage = widget.submitBlockMessage?.call();
            final validationErrors = vm.validateAnswersForForm(form, _answers);
            if (validationErrors.isNotEmpty ||
                blockedMessage != null ||
                externalBlockMessage != null) {
              setState(() {
                _errors = validationErrors;
              });
              if (externalBlockMessage != null) {
                AppSnackbar.showError(context, externalBlockMessage);
              } else if (validationErrors.isNotEmpty) {
                AppSnackbar.showError(
                  context,
                  'Please complete the required booking fields.',
                );
              } else if (blockedMessage != null) {
                AppSnackbar.showError(context, blockedMessage);
              }
              return;
            }
            final actionLabel = vm.submitLabelForForm(form);
            final confirmed = await showAdminActionConfirmation(
              context,
              title: 'Confirm Action',
              message: 'Are you sure you want to ${actionLabel.toLowerCase()}?',
              confirmLabel: actionLabel,
              onConfirmAsync: () async {
                widget.onUnfocusWithoutScroll();
                setState(() {
                  _isSubmitting = true;
                });
                try {
                  final booking = await vm.submitForm(
                    activeForm: form,
                    formAnswers: Map<String, dynamic>.from(_answers),
                    clientUser: widget.clientUser,
                    submittedByUserId: widget.submittedByUserId,
                    submittedByUserRole: widget.submittedByUserRole,
                  );
                  if (!mounted) {
                    return false;
                  }
                  if (booking == null) {
                    final latestBlockedMessage = vm.blockedMessageForForm(
                      form,
                      widget.clientUser,
                    );
                    if (latestBlockedMessage != null) {
                      if (!context.mounted) {
                        return false;
                      }
                      AppSnackbar.showError(context, latestBlockedMessage);
                    } else {
                      final latestExternalBlockMessage =
                          widget.submitBlockMessage?.call();
                      if (latestExternalBlockMessage != null &&
                          context.mounted) {
                        AppSnackbar.showError(
                          context,
                          latestExternalBlockMessage,
                        );
                      }
                    }
                    return false;
                  }
                  await _clearDraft();
                  if (!mounted) {
                    return false;
                  }
                  setState(() {
                    _answers = {};
                    _errors = {};
                    _resetTick += 1;
                  });
                  if (!context.mounted) {
                    return false;
                  }
                  AppSnackbar.showSuccess(
                    context,
                    (booking.localSyncStatus ?? '').trim().toLowerCase() ==
                            'queued'
                        ? 'Booking queued. It will sync once your internet is back.'
                        : 'Booking created.',
                  );
                  widget.onBookingSubmitted?.call(booking);
                  return true;
                } catch (error) {
                  if (context.mounted) {
                    AppSnackbar.showError(context, error.toString());
                  }
                  return false;
                } finally {
                  if (mounted) {
                    setState(() {
                      _isSubmitting = false;
                    });
                  }
                }
              },
            );
            if (!confirmed || !mounted) {
              return;
            }
          },
          onClear: () {
            widget.onUnfocusWithoutScroll();
            setState(() {
              _answers = {};
              _errors = {};
              _resetTick += 1;
            });
            unawaited(_clearDraft());
          },
        ),
      ],
    );
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
}

class _ClientBookingActions extends StatelessWidget {
  const _ClientBookingActions({
    required this.isSubmitting,
    required this.isBlocked,
    required this.title,
    required this.focusNode,
    required this.submitLabel,
    required this.onSubmit,
    required this.onClear,
  });

  final bool isSubmitting;
  final bool isBlocked;
  final String title;
  final FocusNode focusNode;
  final String submitLabel;
  final Future<void> Function() onSubmit;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final submitButton = FilledButton(
      focusNode: focusNode,
      onPressed: isSubmitting || isBlocked ? null : onSubmit,
      style: FilledButton.styleFrom(
        backgroundColor: bookingFormResolvedActionColor(
          title: title,
          buttonText: submitLabel,
        ),
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(submitLabel),
    );

    final clearColor = bookingFormResolvedActionColor(
      title: title,
      buttonText: submitLabel,
    );
    final clearButton = ExcludeFocus(
      child: TextButton(
        onPressed: isSubmitting ? null : onClear,
        style: TextButton.styleFrom(foregroundColor: clearColor),
        child: const Text('Clear Form'),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final useStackedLayout = constraints.maxWidth < 260;
        if (useStackedLayout) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              submitButton,
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: clearButton),
            ],
          );
        }

        return Row(children: [submitButton, const Spacer(), clearButton]);
      },
    );
  }
}

class _ClientBookingStateCard extends StatelessWidget {
  const _ClientBookingStateCard({
    required this.child,
    this.scrollable = true,
    this.padding = const EdgeInsets.fromLTRB(24, 24, 24, 24),
  });

  final Widget child;
  final bool scrollable;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primaryBorder),
      ),
      child: child,
    );

    return scrollable
        ? SingleChildScrollView(padding: padding, child: content)
        : Padding(padding: padding, child: content);
  }
}
