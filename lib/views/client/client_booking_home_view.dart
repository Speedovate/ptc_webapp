import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/client_member.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/models/status_form.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/services/status_field_option_resolver.dart';
import 'package:webapp/utils/functions.dart';
import 'package:webapp/view_models/client/client_booking_home.vm.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
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
  String? _selectedMemberId;

  UserModel get _effectiveClientUser {
    final bookingClientUser = widget.bookingClientUser;
    if (bookingClientUser != null) {
      return bookingClientUser;
    }
    final parentClientId = widget.user.parentClientId?.trim();
    if (isSubClientRole(widget.user.role) &&
        parentClientId != null &&
        parentClientId.isNotEmpty) {
      return widget.user.copyWith(
        id: parentClientId,
        role: 'client',
        parentClientId: null,
      );
    }
    return widget.user;
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
      setState(() {
        _selectedMemberId = null;
      });
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
            isVisible: vm.isBusyLoading || vm.isSubmitting,
            message: vm.isSubmitting
                ? 'Submitting booking ...'
                : 'Loading booking form ...',
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
            isVisible: vm.isBusyLoading || vm.isSubmitting,
            message: vm.isSubmitting
                ? 'Submitting booking ...'
                : 'Loading booking form ...',
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
              final selectedMember = isSubClientRole(widget.user.role)
                  ? ClientMember(
                      id: widget.user.id,
                      clientId: widget.user.parentClientId,
                      userId: widget.user.id,
                      email: widget.user.email,
                      name: widget.user.name,
                      phone: widget.user.phone,
                      position: widget.user.position,
                      isActive: widget.user.isActive,
                    )
                  : vm.activeMembers
                        .where((member) => member.id == _selectedMemberId)
                        .firstOrNull;
              return Padding(
                padding: EdgeInsets.only(
                  bottom: entry.key == vm.mainForms.length - 1 ? 0 : 18,
                ),
                child: _ClientBookingFormSection(
                  key: ValueKey('${activeForm.id}:${_effectiveClientUser.id}'),
                  vm: vm,
                  form: activeForm,
                  clientUser: _effectiveClientUser,
                  submittedByUserId: _effectiveSubmittedByUserId,
                  submittedByUserRole: _effectiveSubmittedByUserRole,
                  selectedMember: selectedMember,
                  showRepresentativePreset:
                      !isSubClientRole(widget.user.role) &&
                      vm.activeMembers.isNotEmpty &&
                      !vm.formUsesMemberSelection(activeForm),
                  onSelectedMemberChanged: (value) {
                    setState(() {
                      _selectedMemberId = value;
                    });
                  },
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
          isVisible: vm.isBusyLoading || vm.isSubmitting,
          message: vm.isSubmitting
              ? 'Submitting booking ...'
              : 'Loading booking form ...',
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
    required this.selectedMember,
    required this.showRepresentativePreset,
    required this.onSelectedMemberChanged,
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
  final ClientMember? selectedMember;
  final bool showRepresentativePreset;
  final ValueChanged<String?> onSelectedMemberChanged;
  final VoidCallback onUnfocusWithoutScroll;
  final String? Function()? submitBlockMessage;
  final ValueChanged<Booking>? onBookingSubmitted;
  final VoidCallback? onRepresentativeTapWithoutClient;

  @override
  State<_ClientBookingFormSection> createState() =>
      _ClientBookingFormSectionState();
}

class _ClientBookingFormSectionState extends State<_ClientBookingFormSection> {
  Map<String, dynamic> _answers = {};
  Map<String, String> _errors = {};
  int _resetTick = 0;
  bool _isSubmitting = false;
  final Map<String, FocusNode> _fieldFocusNodes = {};
  final FocusNode _submitFocusNode = FocusNode(
    debugLabel: 'booking_field(__cta__)',
  );

  String? _clientMemberFieldKey(List<StatusField> fields) {
    for (final field in fields) {
      final key = (field.key ?? '').trim().toLowerCase();
      final sourceKey = StatusFieldOptionResolver.resolvedOptionSourceKey(
        field,
      );
      if (sourceKey == statusFieldOptionSourceClientMembers ||
          key == 'representative_id') {
        return (field.key ?? '').trim();
      }
    }
    return null;
  }

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
    _applySelectedMemberAutofill(overwriteExisting: false);
  }

  @override
  void didUpdateWidget(covariant _ClientBookingFormSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldMember = oldWidget.selectedMember;
    final nextMember = widget.selectedMember;
    final memberChanged =
        oldMember?.id != nextMember?.id ||
        oldMember?.name != nextMember?.name ||
        oldMember?.phone != nextMember?.phone ||
        oldMember?.position != nextMember?.position;
    if (memberChanged && nextMember != null) {
      _applySelectedMemberAutofill(overwriteExisting: true);
    }
  }

  void _applySelectedMemberAutofill({required bool overwriteExisting}) {
    final selectedMember = widget.selectedMember;
    if (selectedMember == null) {
      return;
    }
    final fields = widget.vm.fieldsForForm(widget.form, answers: _answers);
    final fieldKeys = fields
        .map((field) => (field.key ?? '').trim())
        .where((key) => key.isNotEmpty)
        .toSet();
    final memberFieldKey = _clientMemberFieldKey(fields);
    final nextAnswers = Map<String, dynamic>.from(_answers);

    void applyValue(String key, String? value) {
      if (!fieldKeys.contains(key)) {
        return;
      }
      final trimmedValue = value?.trim() ?? '';
      if (trimmedValue.isEmpty) {
        return;
      }
      final currentValue = nextAnswers[key]?.toString().trim() ?? '';
      if (!overwriteExisting && currentValue.isNotEmpty) {
        return;
      }
      nextAnswers[key] = trimmedValue;
    }

    if (memberFieldKey != null && memberFieldKey.isNotEmpty) {
      applyValue(memberFieldKey, selectedMember.id);
    }

    if (mounted) {
      setState(() {
        _answers = nextAnswers;
        if (memberFieldKey != null && memberFieldKey.isNotEmpty) {
          _errors = Map<String, String>.from(_errors)..remove(memberFieldKey);
        } else {
          _errors = Map<String, String>.from(_errors);
        }
      });
    } else {
      _answers = nextAnswers;
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final form = widget.form;
    final fields = vm.fieldsForForm(form, answers: _answers);
    final memberFieldKey = _clientMemberFieldKey(fields);
    final memberOptionLabels = vm.memberOptionLabelsForForm(form);
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
        if (widget.showRepresentativePreset) ...[
          _ClientBookingRepresentativeSelector(
            members: vm.activeMembers,
            selectedMemberId: widget.selectedMember?.id,
            onChanged: widget.onSelectedMemberChanged,
          ),
          const SizedBox(height: 18),
        ],
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
                  nextFieldType == 'dropdown' ||
                  nextFieldType == 'search_dropdown' ||
                  nextFieldType == 'date' ||
                  nextFieldType == 'time' ||
                  nextFieldType == 'photo';
              final fieldKeyValue = (field.key ?? '').trim();
              final shouldRedirectRepresentativeTap =
                  memberFieldKey != null &&
                  fieldKeyValue == memberFieldKey &&
                  widget.onRepresentativeTapWithoutClient != null &&
                  (widget.clientUser.id?.trim().isNotEmpty != true);
              if (memberFieldKey != null && fieldKeyValue == memberFieldKey) {
                debugPrint(
                  '[REP_BOOKED_BY_DEBUG][FIELD_BUILD] '
                  'fieldKey=$fieldKeyValue '
                  'clientId=${widget.clientUser.id ?? '-'} '
                  'hasRedirect=$shouldRedirectRepresentativeTap '
                  'memberOptions=$memberOptionLabels.length',
                );
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: StatusFormRuntimeFieldCard(
                  key: ValueKey('${form.id}:${field.key}:$_resetTick'),
                  field: field,
                  focusNode: focusNode,
                  nextFocusNode: nextFocusNode,
                  activateNextFocus: activateNextFocus,
                  errorText: _errors[field.key],
                  initialValue: _answers[field.key],
                  formTitle: vm.resolvedTitleForForm(form),
                  formButtonText: form.buttonText,
                  formStatusKey: form.currentStatusKey,
                  optionLabels:
                      memberFieldKey != null &&
                          (field.key ?? '').trim() == memberFieldKey
                      ? memberOptionLabels
                      : const {},
                  onDisabledTap: shouldRedirectRepresentativeTap
                      ? () {
                          debugPrint(
                            '[REP_BOOKED_BY_DEBUG][FIELD_REDIRECT] '
                            'fieldKey=$fieldKeyValue '
                            'clientId=${widget.clientUser.id ?? '-'}',
                          );
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
            );
            if (!confirmed || !mounted) {
              return;
            }
            widget.onUnfocusWithoutScroll();
            setState(() {
              _isSubmitting = true;
            });
            final booking = await vm.submitForm(
              activeForm: form,
              formAnswers: Map<String, dynamic>.from(_answers),
              clientUser: widget.clientUser,
              submittedByUserId: widget.submittedByUserId,
              submittedByUserRole: widget.submittedByUserRole,
            );
            if (!mounted) {
              return;
            }
            setState(() {
              _isSubmitting = false;
            });
            if (booking == null) {
              final latestBlockedMessage = vm.blockedMessageForForm(
                form,
                widget.clientUser,
              );
              if (latestBlockedMessage != null) {
                if (!mounted) {
                  return;
                }
                if (!context.mounted) {
                  return;
                }
                AppSnackbar.showError(context, latestBlockedMessage);
              } else {
                final latestExternalBlockMessage =
                    widget.submitBlockMessage?.call();
                if (latestExternalBlockMessage != null) {
                  if (!mounted || !context.mounted) {
                    return;
                  }
                  AppSnackbar.showError(context, latestExternalBlockMessage);
                }
              }
              return;
            }
            setState(() {
              _answers = {};
              _errors = {};
              _resetTick += 1;
            });
            _applySelectedMemberAutofill(overwriteExisting: true);
            if (!mounted) {
              return;
            }
            if (!context.mounted) {
              return;
            }
            AppSnackbar.showSuccess(context, 'Booking created.');
            widget.onBookingSubmitted?.call(booking);
          },
          onClear: () {
            widget.onUnfocusWithoutScroll();
            setState(() {
              _answers = {};
              _errors = {};
              _resetTick += 1;
            });
            _applySelectedMemberAutofill(overwriteExisting: true);
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

class _ClientBookingRepresentativeSelector extends StatelessWidget {
  const _ClientBookingRepresentativeSelector({
    required this.members,
    required this.selectedMemberId,
    required this.onChanged,
  });

  final List<ClientMember> members;
  final String? selectedMemberId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.primaryBorder),
        ),
        child: const Text(
          'Create members from the Members menu to auto-fill representative name, phone, and position while booking.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primaryBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Representative Preset',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Select a saved member to auto-fill the representative details on this booking.',
            style: TextStyle(
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          AdminDropdownFormField<String>(
            initialValue: selectedMemberId,
            isExpanded: true,
            decoration: adminFormInputDecoration(
              'Saved Member',
              hintText: 'Manual entry',
            ),
            items: [
              const DropdownMenuItem<String>(
                value: null,
                child: Text('Manual entry'),
              ),
              ...members.map((member) {
                final phone = member.normalizedPhone;
                final position = member.position?.trim() ?? '';
                final labelParts = <String>[
                  member.displayName,
                  if (phone.isNotEmpty) phone,
                  if (position.isNotEmpty) position,
                ];
                return DropdownMenuItem<String>(
                  value: member.id,
                  child: Text(
                    labelParts.join(' | '),
                    overflow: TextOverflow.ellipsis,
                    style: adminDropdownDisplayTextStyle,
                  ),
                );
              }),
            ],
            onChanged: onChanged,
          ),
        ],
      ),
    );
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
