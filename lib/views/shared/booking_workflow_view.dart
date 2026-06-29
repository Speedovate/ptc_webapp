import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stacked/stacked.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/constants/palawan_locations.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/status_form.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/models/support_thread.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/services/status_field_option_resolver.dart';
import 'package:webapp/services/status_form_engine.dart';
import 'package:webapp/utils/functions.dart';
import 'package:webapp/view_models/shared/booking_workflow.vm.dart';
import 'package:webapp/views/admin/admin_users.dart';
import 'package:webapp/views/shared/support_center_view.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';
import 'package:webapp/widgets/shared/app_snackbar.dart';
import 'package:webapp/widgets/shared/admin_action_confirmation.dart';
import 'package:webapp/widgets/shared/admin_modal_form_primitives.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/app_cached_network_image.dart';
import 'package:webapp/widgets/shared/app_page_loading_overlay.dart';
import 'package:webapp/widgets/shared/app_mouse_pressable.dart';
import 'package:webapp/widgets/shared/app_refresh_strip.dart';
import 'package:webapp/widgets/shared/app_image_viewer.dart';
import 'package:webapp/widgets/shared/booking_form_primitives.dart';
import 'package:webapp/widgets/shared/booking_record_card.dart';
import 'package:webapp/widgets/status_form/status_field_editor_card.dart';

class BookingWorkflowView extends StatefulWidget {
  const BookingWorkflowView({
    super.key,
    required this.user,
    required this.booking,
    this.embedded = false,
    this.embeddedScrollController,
    this.onBookingUpdated,
    this.loadingOverlayVisibleHeight,
    this.loadingOverlayAlignmentY = 0,
  });

  final UserModel user;
  final Booking booking;
  final bool embedded;
  final ScrollController? embeddedScrollController;
  final ValueChanged<Booking>? onBookingUpdated;
  final double? loadingOverlayVisibleHeight;
  final double loadingOverlayAlignmentY;

  @override
  State<BookingWorkflowView> createState() => _BookingWorkflowViewState();
}

String? _supportTargetUserIdForBooking(UserModel currentUser, Booking booking) {
  if (normalizeRoleKey(currentUser.role) != 'admin') {
    return null;
  }
  return normalizeId(
    BookingRecordCard.outputFieldValue(
      booking.statusOutputs,
      'representative_id',
    )?.toString(),
  );
}

class _WorkflowHeaderPalette {
  const _WorkflowHeaderPalette({
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

const BookingFormPalette _workflowDeliveredPalette = BookingFormPalette(
  strip: Color(0xFF2EAD62),
  accent: Color(0xFF2EAD62),
  accentMuted: Color(0xFF4D7C5C),
  surface: Color(0xFFF4FBF6),
  surfaceAlt: Color(0xFFE7F5EB),
  border: Color(0xFFBFE1C8),
);

BookingFormPalette _workflowResolvedPalette({
  required String? title,
  String? buttonText,
  String? currentStatusKey,
}) {
  if (bookingFormUsesDangerTheme(title: title, buttonText: buttonText)) {
    return bookingFormDangerPalette;
  }
  if (currentStatusKey?.trim() == 'delivered') {
    return _workflowDeliveredPalette;
  }
  return bookingFormResolvedPalette(title: title, buttonText: buttonText);
}

Color _workflowResolvedActionColor({
  required String? title,
  String? buttonText,
  String? currentStatusKey,
}) {
  return _workflowResolvedPalette(
    title: title,
    buttonText: buttonText,
    currentStatusKey: currentStatusKey,
  ).accent;
}

_WorkflowHeaderPalette? _terminalHeaderPaletteForStatus(String? statusKey) {
  switch (statusKey?.trim()) {
    case 'delivered':
      return const _WorkflowHeaderPalette(
        backgroundColor: Color(0xFF2EAD62),
        borderColor: Color(0xFF2EAD62),
        titleColor: AppColors.textPrimary,
        subtitleColor: AppColors.textPrimary,
      );
    case 'cancelled':
      return const _WorkflowHeaderPalette(
        backgroundColor: AppColors.dangerStrong,
        borderColor: AppColors.dangerStrong,
        titleColor: AppColors.textPrimary,
        subtitleColor: AppColors.textPrimary,
      );
    default:
      return null;
  }
}

class _WorkflowScrollSnapshot {
  const _WorkflowScrollSnapshot({required this.position, required this.offset});

  final ScrollPosition? position;
  final double? offset;
}

class _BookingWorkflowViewState extends State<BookingWorkflowView> {
  late final ScrollController _pageScrollController;
  final FocusNode _primaryActionFocusNode = FocusNode(
    debugLabel: 'workflow_field(__cta__)',
  );
  ScrollPosition? _embeddedScrollPosition;
  double? _embeddedScrollOffset;
  bool _pendingExplicitAttachRetry = false;

  @override
  void initState() {
    super.initState();
    _pageScrollController = ScrollController();
  }

  @override
  void dispose() {
    _detachEmbeddedScrollPosition();
    _primaryActionFocusNode.dispose();
    _pageScrollController.dispose();
    super.dispose();
  }

  @override
  void reassemble() {
    super.reassemble();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreScrollOffset(_embeddedScrollPosition, _embeddedScrollOffset);
      if (_pageScrollController.hasClients) {
        _restoreScrollOffset(
          _pageScrollController.position,
          _pageScrollController.position.pixels,
        );
      }
    });
  }

  void _attachEmbeddedScrollPosition(BuildContext context) {
    final explicitController = widget.embeddedScrollController;
    if (explicitController != null && !explicitController.hasClients) {
      _scheduleExplicitEmbeddedAttachRetry();
      return;
    }
    final position =
        explicitController?.position ?? Scrollable.maybeOf(context)?.position;
    if (identical(position, _embeddedScrollPosition)) {
      return;
    }
    _detachEmbeddedScrollPosition();
    _embeddedScrollPosition = position;
    _embeddedScrollOffset = position?.hasPixels == true
        ? position!.pixels
        : _embeddedScrollOffset;
    position?.addListener(_handleEmbeddedScrollChanged);
  }

  void _detachEmbeddedScrollPosition() {
    _embeddedScrollPosition?.removeListener(_handleEmbeddedScrollChanged);
    _embeddedScrollPosition = null;
  }

  void _scheduleExplicitEmbeddedAttachRetry() {
    if (_pendingExplicitAttachRetry) {
      return;
    }
    _pendingExplicitAttachRetry = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingExplicitAttachRetry = false;
      if (!mounted || !widget.embedded) {
        return;
      }
      final explicitController = widget.embeddedScrollController;
      if (explicitController?.hasClients == true) {
        _attachEmbeddedScrollPosition(context);
        return;
      }
      _scheduleExplicitEmbeddedAttachRetry();
    });
  }

  void _handleEmbeddedScrollChanged() {
    final position = _embeddedScrollPosition;
    if (position == null || !position.hasPixels) {
      return;
    }
    _embeddedScrollOffset = position.pixels;
  }

  ScrollController? _preferredScrollController() {
    if (widget.embedded) {
      final explicitController = widget.embeddedScrollController;
      if (explicitController != null) {
        return explicitController;
      }
      return null;
    }
    return _pageScrollController;
  }

  ScrollPosition? _preferredScrollPosition(BuildContext context) {
    final preferredController = _preferredScrollController();
    if (preferredController?.hasClients == true) {
      return preferredController!.position;
    }
    if (widget.embedded && widget.embeddedScrollController != null) {
      return _embeddedScrollPosition;
    }
    if (widget.embedded && _embeddedScrollPosition != null) {
      return _embeddedScrollPosition;
    }
    return Scrollable.maybeOf(context)?.position;
  }

  _WorkflowScrollSnapshot _captureScrollSnapshot(BuildContext context) {
    final position = _preferredScrollPosition(context);
    return _WorkflowScrollSnapshot(
      position: position,
      offset: position?.hasPixels == true ? position!.pixels : null,
    );
  }

  void _restoreScrollSnapshot(_WorkflowScrollSnapshot snapshot) {
    _restoreScrollOffset(snapshot.position, snapshot.offset);
  }

  Future<void> _openManagedFieldEditor(
    BuildContext context,
    BookingWorkflowViewModel vm, {
    required StatusField initialField,
    bool addAfterSave = false,
  }) async {
    final savedField = await showDialog<StatusField>(
      context: context,
      builder: (dialogContext) => _BookingFieldEditorDialog(
        title: initialField.id == vm.nextFieldId ? 'New Field' : 'Edit Field',
        initialField: initialField,
      ),
    );

    if (savedField == null || !context.mounted) {
      return;
    }

    final persistedField = await vm.saveLibraryField(savedField);
    if (addAfterSave) {
      final persistedId = persistedField.id ?? '';
      if (persistedId.isNotEmpty) {
        await vm.addExistingField(persistedId);
      }
    }
    if (!context.mounted) {
      return;
    }
    AppSnackbar.showSuccess(
      context,
      addAfterSave ? 'Field added.' : 'Field updated.',
    );
  }

  void _restoreScrollOffset(ScrollPosition? position, double? offset) {
    if (position == null || offset == null) {
      return;
    }
    void restoreOnNextFrame([int remainingPasses = 5]) {
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

  Widget _nonFocusable(Widget child) {
    return ExcludeFocus(excluding: true, child: child);
  }

  void _unfocusWithoutScroll(BuildContext context) {
    final snapshot = _captureScrollSnapshot(context);
    FocusScope.of(context).unfocus();
    _restoreScrollSnapshot(snapshot);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      _attachEmbeddedScrollPosition(context);
    } else {
      _detachEmbeddedScrollPosition();
    }

    return ViewModelBuilder<BookingWorkflowViewModel>.reactive(
      viewModelBuilder: BookingWorkflowViewModel.new,
      onViewModelReady: (vm) =>
          vm.load(user: widget.user, booking: widget.booking),
      builder: (context, vm, _) {
        final currentBooking = vm.booking ?? widget.booking;
        final currentStatusLabel = vm.currentStatusLabel();
        final statusDescription = vm.currentStatusDescription();
        final guidanceMessage = vm.roleGuidanceMessage();
        final content = vm.loadError != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 240,
                        child: AppRefreshStrip(isVisible: vm.isBusyLoading),
                      ),
                      Text(
                        vm.loadError!,
                        style: TextStyle(
                          color: AppColors.primaryColor.withValues(alpha: 0.72),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : widget.embedded
            ? _buildContent(
                context,
                vm,
                currentBooking,
                currentStatusLabel,
                statusDescription,
                guidanceMessage,
              )
            : SingleChildScrollView(
                key: PageStorageKey(
                  'booking-workflow-page-${currentBooking.id ?? ''}',
                ),
                controller: _pageScrollController,
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: _buildContent(
                  context,
                  vm,
                  currentBooking,
                  currentStatusLabel,
                  statusDescription,
                  guidanceMessage,
                ),
              );
        final contentWithRefreshIndicator = Column(
          children: [
            AppRefreshStrip(
              isVisible: vm.isBusyLoading,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            ),
            Expanded(child: content),
          ],
        );
        final overlayVisible =
            vm.isBusyLoading || vm.isSubmitting || vm.isCancelSubmitting;
        final overlayMessage = vm.isCancelSubmitting
            ? 'Submitting cancellation ...'
            : vm.isSubmitting
            ? 'Submitting update ...'
            : 'Loading booking ...';

        if (widget.embedded) {
          return AppPageLoadingOverlay(
            isVisible: overlayVisible,
            message: overlayMessage,
            child: content,
          );
        }

        return AppPageLoadingOverlay(
          isVisible: overlayVisible,
          message: overlayMessage,
          visibleHeightWhenUnbounded: widget.loadingOverlayVisibleHeight,
          loadingAlignmentY: widget.loadingOverlayAlignmentY,
          child: Scaffold(
            backgroundColor: const Color(0xFFF7F7FB),
            appBar: AppBar(
              title: Text('Booking ${currentBooking.id ?? '-'}'),
              actions: [
                BookingSupportButton(
                  onPressed: () => openSupportDestination(
                    context,
                    user: widget.user,
                    initialTopicKey: supportTopicBooking,
                    initialBookingId: currentBooking.id,
                    initialUserId: _supportTargetUserIdForBooking(
                      widget.user,
                      currentBooking,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              backgroundColor: Colors.white,
              foregroundColor: AppColors.textPrimary,
              elevation: 0,
              surfaceTintColor: Colors.white,
            ),
            body: contentWithRefreshIndicator,
          ),
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    BookingWorkflowViewModel vm,
    Booking currentBooking,
    String currentStatusLabel,
    String? statusDescription,
    String? guidanceMessage,
  ) {
    final resolvedPrimaryFields = vm.form == null
        ? vm.fields
        : vm.fieldsForForm(vm.form!, answers: vm.answers);
    final hasGuidance = guidanceMessage?.trim().isNotEmpty == true;
    final hasMultipleMainForms = vm.mainForms.length > 1;
    final hasMultipleSecondaryForms = vm.secondaryForms.length > 1;
    final hasActionForm = vm.hasActionablePrimaryForm;
    final hasCancelForm = vm.cancelForm != null;
    final hasFormFields = resolvedPrimaryFields.isNotEmpty;
    final hasBlockedMessage = vm.blockedMessage?.trim().isNotEmpty == true;
    final showTaskCard = hasBlockedMessage || hasFormFields;
    final terminalPalette = _terminalHeaderPaletteForStatus(
      currentBooking.clientStatus,
    );
    final actionSectionTopSpacing = hasActionForm
        ? (showTaskCard ? 16.0 : 14.0)
        : 0.0;
    final actionButtonTopSpacing = showTaskCard ? 14.0 : 0.0;
    final primaryActionLabel = vm.form?.buttonText?.trim().isNotEmpty == true
        ? vm.form!.buttonText!.trim()
        : 'Save';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BookingFormHeaderCard(
          title: currentStatusLabel,
          subtitle: statusDescription,
          paletteOverride: currentBooking.clientStatus?.trim() == 'delivered'
              ? _workflowDeliveredPalette
              : null,
          backgroundColor: terminalPalette?.backgroundColor,
          borderColor: terminalPalette?.borderColor,
          titleColor: terminalPalette?.titleColor,
          subtitleColor: terminalPalette?.subtitleColor,
        ),
        if (hasGuidance) ...[
          const SizedBox(height: 14),
          _WorkflowGuidanceCard(
            message: guidanceMessage!.trim(),
            backgroundColor: terminalPalette?.backgroundColor.withValues(
              alpha: 0.12,
            ),
            borderColor: terminalPalette?.borderColor.withValues(alpha: 0.28),
            textColor:
                terminalPalette?.borderColor ??
                AppColors.primaryColor.withValues(alpha: 0.72),
          ),
        ],
        if (hasMultipleMainForms) ...[
          const SizedBox(height: 16),
          ...vm.mainForms.asMap().entries.map((entry) {
            final activeForm = entry.value;
            return Padding(
              padding: EdgeInsets.only(
                bottom: entry.key == vm.mainForms.length - 1 ? 0 : 18,
              ),
              child: _WorkflowInteractiveFormSection(
                vm: vm,
                form: activeForm,
                preferredScrollController: _preferredScrollController(),
                captureScrollSnapshot: () => _captureScrollSnapshot(context),
                restoreScrollSnapshot: _restoreScrollSnapshot,
                onBookingUpdated: widget.onBookingUpdated,
                onUnfocusWithoutScroll: () => _unfocusWithoutScroll(context),
              ),
            );
          }),
        ] else if (hasActionForm) ...[
          SizedBox(height: actionSectionTopSpacing),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showTaskCard) ...[
                _WorkflowTaskCard(
                  vm: vm,
                  title: vm.form?.buttonText?.trim().isNotEmpty == true
                      ? vm.form!.buttonText!.trim()
                      : 'Complete Booking Step',
                  buttonText: vm.form?.buttonText?.trim(),
                  currentStatusKey: currentBooking.clientStatus,
                  preferredScrollController: _preferredScrollController(),
                  blockedMessage: vm.blockedMessage,
                  fields: resolvedPrimaryFields,
                  errors: vm.errors,
                  answers: vm.answers,
                  resetTick: vm.resetTick,
                  submitFocusNode: _primaryActionFocusNode,
                  onChanged: (fieldKey, value) {
                    vm.updateAnswer(fieldKey, value);
                  },
                ),
                SizedBox(height: actionButtonTopSpacing),
              ],
              Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) => _unfocusWithoutScroll(context),
                    child: FilledButton(
                      focusNode: _primaryActionFocusNode,
                      onPressed: vm.isSubmitting || vm.blockedMessage != null
                          ? null
                          : () async {
                              final scrollSnapshot = _captureScrollSnapshot(
                                context,
                              );
                              final isValid = vm.validateForSubmit();
                              if (!isValid) {
                                if (vm.errors.isNotEmpty) {
                                  AppSnackbar.showError(
                                    context,
                                    'Please complete the required booking fields.',
                                  );
                                } else if (vm.blockedMessage != null) {
                                  AppSnackbar.showError(
                                    context,
                                    vm.blockedMessage!,
                                  );
                                }
                                _restoreScrollSnapshot(scrollSnapshot);
                                return;
                              }
                              final actionLabel = primaryActionLabel;
                              final confirmed = await showAdminActionConfirmation(
                                context,
                                title: 'Confirm Action',
                                message:
                                    'Are you sure you want to ${actionLabel.toLowerCase()}?',
                                confirmLabel: actionLabel,
                              );
                              if (!confirmed || !context.mounted) {
                                _restoreScrollSnapshot(scrollSnapshot);
                                return;
                              }
                              final savedBooking = await vm.submit();
                              if (!context.mounted) {
                                return;
                              }
                              if (savedBooking == null) {
                                if (vm.blockedMessage != null) {
                                  AppSnackbar.showError(
                                    context,
                                    vm.blockedMessage!,
                                  );
                                }
                                _restoreScrollSnapshot(scrollSnapshot);
                                return;
                              }
                              _unfocusWithoutScroll(context);
                              widget.onBookingUpdated?.call(savedBooking);
                              AppSnackbar.showSuccess(
                                context,
                                'Booking updated.',
                              );
                            },
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 52),
                        backgroundColor: _workflowResolvedActionColor(
                          title: vm.form?.statusText?.trim(),
                          buttonText: primaryActionLabel,
                          currentStatusKey: currentBooking.clientStatus,
                        ),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        vm.isSubmitting ? 'Saving ...' : primaryActionLabel,
                      ),
                    ),
                  ),
                  if (hasFormFields || vm.supportsAdditionalFields) ...[
                    const Spacer(),
                  ],
                  if (hasFormFields) ...[
                    if (vm.supportsAdditionalFields) const SizedBox(width: 12),
                    if (vm.supportsAdditionalFields)
                      _WorkflowAddFieldButton(
                        availableFields: vm.availableFieldsForSelection,
                        onSelected: vm.addExistingField,
                        onCreateNew: () => _openManagedFieldEditor(
                          context,
                          vm,
                          initialField: vm.buildNewFieldDraft(),
                          addAfterSave: true,
                        ),
                        textColor: _workflowResolvedActionColor(
                          title: vm.form?.statusText?.trim(),
                          buttonText: primaryActionLabel,
                          currentStatusKey: currentBooking.clientStatus,
                        ),
                      ),
                    if (vm.supportsAdditionalFields) const SizedBox(width: 12),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (_) => _unfocusWithoutScroll(context),
                      child: TextButton(
                        onPressed: vm.isSubmitting
                            ? null
                            : () {
                                _unfocusWithoutScroll(context);
                                vm.clearForm();
                              },
                        style: TextButton.styleFrom(
                          foregroundColor: _workflowResolvedActionColor(
                            title: vm.form?.statusText?.trim(),
                            buttonText: primaryActionLabel,
                            currentStatusKey: currentBooking.clientStatus,
                          ),
                        ),
                        child: const Text('Clear Form'),
                      ),
                    ),
                  ],
                  if (!hasFormFields && vm.supportsAdditionalFields)
                    _WorkflowAddFieldButton(
                      availableFields: vm.availableFieldsForSelection,
                      onSelected: vm.addExistingField,
                      onCreateNew: () => _openManagedFieldEditor(
                        context,
                        vm,
                        initialField: vm.buildNewFieldDraft(),
                        addAfterSave: true,
                      ),
                      textColor: _workflowResolvedActionColor(
                        title: vm.form?.statusText?.trim(),
                        buttonText: primaryActionLabel,
                        currentStatusKey: currentBooking.clientStatus,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
        const SizedBox(height: 18),
        const AdminSectionTitle(title: 'Details'),
        const SizedBox(height: 10),
        BookingRecordCard(
          booking: currentBooking,
          headlineStatusLabel: currentStatusLabel,
          statusLabelForKey: vm.statusLabelForKey,
          showStatusSubmissions: false,
          showAllDetails: widget.user.role == 'admin',
          originValue: BookingRecordCard.outputFieldDisplayValue(
            currentBooking.statusOutputs,
            'origin',
          ),
          destinationValue: BookingRecordCard.outputFieldDisplayValue(
            currentBooking.statusOutputs,
            'destination',
          ),
          clientId: currentBooking.client?.id,
          clientName: vm.userName(currentBooking.client?.id, 'Unknown client'),
          clientPhone: vm.userPhone(currentBooking.client?.id),
          driverId: currentBooking.driver?.id,
          driverName: vm.userName(currentBooking.driver?.id, '-'),
          driverPhone: vm.userPhone(currentBooking.driver?.id),
          helperId: currentBooking.helper?.id,
          helperName: vm.userName(currentBooking.helper?.id, '-'),
          helperPhone: vm.userPhone(currentBooking.helper?.id),
          onLinkedUserTap: (userId) {
            final linkedUser = vm.userById(userId);
            if (linkedUser == null) {
              return;
            }
            AdminUsersView.showUserDetailDialog(
              context,
              currentUser: widget.user,
              viewedUser: linkedUser,
            );
          },
        ),
        if (widget.user.role != 'admin') ...[
          Builder(
            builder: (context) {
              final waybillPhotoValue = BookingRecordCard.outputFieldValue(
                currentBooking.statusOutputs,
                'waybill_photo',
              );
              final waybillPhotoUrl = photoDownloadUrl(waybillPhotoValue);
              if (waybillPhotoUrl == null) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 16),
                child: _WorkflowWaybillPhotoCard(imageUrl: waybillPhotoUrl),
              );
            },
          ),
        ],
        if (widget.user.role == 'admin' &&
            (currentBooking.statusOutputs ?? const {}).isNotEmpty) ...[
          const SizedBox(height: 18),
          const AdminSectionTitle(title: 'Statuses'),
          const SizedBox(height: 10),
          BookingStatusSubmissionsSection(
            booking: currentBooking,
            statusLabelForKey: vm.statusLabelForKey,
            userNameForId: (userId) => vm.userName(userId, '-'),
            userRoleForId: (userId, fallbackRole) =>
                vm.userRole(userId, fallbackRole),
            linkedUserDisplayForField: (fieldKey, rawValue) {
              if (!fieldKey.trim().toLowerCase().endsWith('_id')) {
                return null;
              }
              final linkedUser = vm.userById(rawValue);
              final linkedName = linkedUser?.name?.trim();
              if (linkedUser == null ||
                  linkedName == null ||
                  linkedName.isEmpty) {
                return null;
              }
              return '${linkedUser.id} | $linkedName';
            },
            onLinkedUserTapForField: (fieldKey, rawValue) {
              if (!fieldKey.trim().toLowerCase().endsWith('_id')) {
                return null;
              }
              final linkedUser = vm.userById(rawValue);
              if (linkedUser == null) {
                return null;
              }
              return () {
                AdminUsersView.showUserDetailDialog(
                  context,
                  currentUser: widget.user,
                  viewedUser: linkedUser,
                );
              };
            },
          ),
        ],
        if (hasMultipleSecondaryForms) ...[
          const SizedBox(height: 14),
          ...vm.secondaryForms.asMap().entries.map((entry) {
            final secondaryForm = entry.value;
            return Padding(
              padding: EdgeInsets.only(
                bottom: entry.key == vm.secondaryForms.length - 1 ? 0 : 18,
              ),
              child: _WorkflowInteractiveFormSection(
                vm: vm,
                form: secondaryForm,
                preferredScrollController: _preferredScrollController(),
                captureScrollSnapshot: () => _captureScrollSnapshot(context),
                restoreScrollSnapshot: _restoreScrollSnapshot,
                onBookingUpdated: widget.onBookingUpdated,
                onUnfocusWithoutScroll: () => _unfocusWithoutScroll(context),
                isDanger: true,
              ),
            );
          }),
        ] else if (hasCancelForm) ...[
          const SizedBox(height: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _WorkflowAlertHeaderCard(
                title: vm.cancelForm?.statusText?.trim().isNotEmpty == true
                    ? vm.cancelForm!.statusText!.trim()
                    : (vm.cancelForm?.buttonText?.trim().isNotEmpty == true
                          ? vm.cancelForm!.buttonText!.trim()
                          : 'Cancellation'),
                subtitle:
                    vm.cancelForm?.statusSubtext?.trim().isNotEmpty == true
                    ? vm.cancelForm!.statusSubtext!.trim()
                    : 'This action will mark the booking as cancelled.',
              ),
              const SizedBox(height: 14),
              _WorkflowTaskCard(
                vm: vm,
                title: vm.cancelForm?.statusText?.trim().isNotEmpty == true
                    ? vm.cancelForm!.statusText!.trim()
                    : (vm.cancelForm?.buttonText?.trim().isNotEmpty == true
                          ? vm.cancelForm!.buttonText!.trim()
                          : 'Cancellation'),
                buttonText: vm.cancelForm?.buttonText?.trim(),
                preferredScrollController: _preferredScrollController(),
                blockedMessage: null,
                fields: vm.cancelFields,
                errors: vm.cancelErrors,
                answers: vm.cancelAnswers,
                resetTick: vm.cancelResetTick,
                allowAdditionalFields: false,
                onChanged: (fieldKey, value) {
                  vm.updateCancelAnswer(fieldKey, value);
                },
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final cancelButton = GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) => _unfocusWithoutScroll(context),
                    child: _nonFocusable(
                      FilledButton(
                        onPressed: vm.isCancelSubmitting
                            ? null
                            : () async {
                                final scrollSnapshot = _captureScrollSnapshot(
                                  context,
                                );
                                final isValid = vm.validateCancelForSubmit();
                                if (!isValid) {
                                  if (vm.cancelErrors.isNotEmpty) {
                                    AppSnackbar.showError(
                                      context,
                                      'Please complete the required cancellation fields.',
                                    );
                                  }
                                  _restoreScrollSnapshot(scrollSnapshot);
                                  return;
                                }
                                final actionLabel =
                                    vm.cancelForm?.buttonText
                                            ?.trim()
                                            .isNotEmpty ==
                                        true
                                    ? vm.cancelForm!.buttonText!.trim()
                                    : 'Cancel Booking';
                                final confirmed = await showAdminActionConfirmation(
                                  context,
                                  title: 'Confirm Cancellation',
                                  message:
                                      'Are you sure you want to ${actionLabel.toLowerCase()}?',
                                  confirmLabel: actionLabel,
                                  isDanger: true,
                                );
                                if (!confirmed || !context.mounted) {
                                  _restoreScrollSnapshot(scrollSnapshot);
                                  return;
                                }
                                final savedBooking = await vm.submitCancel();
                                if (!context.mounted) {
                                  return;
                                }
                                if (savedBooking == null) {
                                  _restoreScrollSnapshot(scrollSnapshot);
                                  return;
                                }
                                _unfocusWithoutScroll(context);
                                widget.onBookingUpdated?.call(savedBooking);
                                AppSnackbar.showSuccess(
                                  context,
                                  'Booking cancelled.',
                                );
                              },
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 52),
                          backgroundColor: AppColors.dangerStrong,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          vm.isCancelSubmitting
                              ? 'Saving ...'
                              : (vm.cancelForm?.buttonText?.trim().isNotEmpty ==
                                        true
                                    ? vm.cancelForm!.buttonText!.trim()
                                    : 'Cancel Booking'),
                        ),
                      ),
                    ),
                  );
                  final clearButton = GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) => _unfocusWithoutScroll(context),
                    child: TextButton(
                      onPressed: vm.isCancelSubmitting
                          ? null
                          : () {
                              _unfocusWithoutScroll(context);
                              vm.clearCancelForm();
                            },
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.dangerStrong,
                      ),
                      child: const Text('Clear Form'),
                    ),
                  );
                  final useStackedLayout =
                      vm.cancelFields.isNotEmpty && constraints.maxWidth < 260;

                  if (useStackedLayout) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        cancelButton,
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: clearButton,
                        ),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      cancelButton,
                      if (vm.cancelFields.isNotEmpty) ...[
                        const Spacer(),
                        clearButton,
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _WorkflowGuidanceCard extends StatelessWidget {
  const _WorkflowGuidanceCard({
    required this.message,
    this.backgroundColor,
    this.borderColor,
    this.textColor,
  });

  final String message;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: bookingFormContentHorizontalPadding,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.primarySurfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor ?? AppColors.primaryBorder),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: textColor ?? AppColors.primaryColor.withValues(alpha: 0.72),
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      ),
    );
  }
}

class BookingSupportButton extends StatelessWidget {
  const BookingSupportButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(1000),
        border: Border.all(
          color: AppColors.primaryColor.withValues(alpha: 0.18),
        ),
      ),
      child: TextButton.icon(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryColor,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        icon: const Icon(Icons.support_agent_rounded, size: 20),
        label: const Text('Support'),
      ),
    );
  }
}

class _WorkflowWaybillPhotoCard extends StatelessWidget {
  const _WorkflowWaybillPhotoCard({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return AppMousePressable(
      onTap: () {
        showAppImageViewer(context, title: 'Waybill Photo', imageUrl: imageUrl);
      },
      borderRadius: BorderRadius.circular(18),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: AppCachedNetworkImage(
          imageUrl: imageUrl,
          width: double.infinity,
          fit: BoxFit.fitWidth,
          errorBuilder: (context, error) {
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              color: AppColors.primarySurface,
              child: const Text(
                'Failed to load photo.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _WorkflowInteractiveFormSection extends StatefulWidget {
  const _WorkflowInteractiveFormSection({
    required this.vm,
    required this.form,
    required this.preferredScrollController,
    required this.captureScrollSnapshot,
    required this.restoreScrollSnapshot,
    required this.onUnfocusWithoutScroll,
    this.onBookingUpdated,
    this.isDanger = false,
  });

  final BookingWorkflowViewModel vm;
  final StatusForm form;
  final ScrollController? preferredScrollController;
  final _WorkflowScrollSnapshot Function() captureScrollSnapshot;
  final void Function(_WorkflowScrollSnapshot snapshot) restoreScrollSnapshot;
  final VoidCallback onUnfocusWithoutScroll;
  final ValueChanged<Booking>? onBookingUpdated;
  final bool isDanger;

  @override
  State<_WorkflowInteractiveFormSection> createState() =>
      _WorkflowInteractiveFormSectionState();
}

class _WorkflowInteractiveFormSectionState
    extends State<_WorkflowInteractiveFormSection> {
  Map<String, dynamic> _answers = {};
  Map<String, String> _errors = {};
  int _resetTick = 0;
  bool _isSubmitting = false;
  final FocusNode _submitFocusNode = FocusNode(
    debugLabel: 'workflow_field(__cta__)',
  );

  @override
  void initState() {
    super.initState();
    _syncFromViewModel(resetLocalTick: false);
  }

  @override
  void didUpdateWidget(covariant _WorkflowInteractiveFormSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.vm.answers, widget.vm.answers) ||
        oldWidget.vm.resetTick != widget.vm.resetTick ||
        oldWidget.form.id != widget.form.id ||
        oldWidget.vm.booking?.id != widget.vm.booking?.id) {
      _syncFromViewModel(resetLocalTick: true);
    }
  }

  void _syncFromViewModel({required bool resetLocalTick}) {
    _answers = Map<String, dynamic>.from(widget.vm.answers);
    _errors = Map<String, String>.from(widget.vm.errors);
    if (resetLocalTick) {
      _resetTick += 1;
    }
  }

  @override
  void dispose() {
    _submitFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final form = widget.form;
    final fields = vm.fieldsForForm(form, answers: _answers);
    final blockedMessage = widget.isDanger
        ? null
        : vm.blockedMessageForForm(form);
    final terminalPalette = form.nextStatusKey == null
        ? _terminalHeaderPaletteForStatus(form.currentStatusKey)
        : null;
    final resolvedTitle = form.statusText?.trim().isNotEmpty == true
        ? form.statusText!.trim()
        : vm.statusLabelForKey(form.currentStatusKey);
    final resolvedSubtitle = form.statusSubtext?.trim().isNotEmpty == true
        ? form.statusSubtext!.trim()
        : vm.currentStatusDescription();
    final palette = _workflowResolvedPalette(
      title: resolvedTitle,
      buttonText: form.buttonText,
      currentStatusKey: form.currentStatusKey,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.isDanger)
          _WorkflowAlertHeaderCard(
            title: resolvedTitle,
            subtitle: resolvedSubtitle,
            showRequiredLegend: fields.any((field) => field.required == true),
          )
        else
          BookingFormHeaderCard(
            title: resolvedTitle,
            subtitle: resolvedSubtitle,
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
        const SizedBox(height: 14),
        _WorkflowTaskCard(
          vm: vm,
          title: resolvedTitle,
          buttonText: form.buttonText?.trim(),
          currentStatusKey: form.currentStatusKey,
          preferredScrollController: widget.preferredScrollController,
          blockedMessage: blockedMessage,
          fields: fields,
          errors: _errors,
          answers: _answers,
          resetTick: _resetTick,
          submitFocusNode: _submitFocusNode,
          allowAdditionalFields: false,
          onChanged: (fieldKey, value) {
            setState(() {
              final nextAnswers = Map<String, dynamic>.from(_answers);
              if (_isEmptyValue(value)) {
                nextAnswers.remove(fieldKey);
              } else {
                nextAnswers[fieldKey] = value;
              }
              _answers = nextAnswers;
              _errors = Map<String, String>.from(_errors)..remove(fieldKey);
            });
          },
        ),
        SizedBox(height: widget.isDanger ? 8 : 2),
        LayoutBuilder(
          builder: (context, constraints) {
            final actionLabel = form.buttonText?.trim().isNotEmpty == true
                ? form.buttonText!.trim()
                : (widget.isDanger ? 'Cancel Booking' : 'Save');
            final submitButton = GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => widget.onUnfocusWithoutScroll(),
              child: FilledButton(
                focusNode: _submitFocusNode,
                onPressed: _isSubmitting
                    ? null
                    : () async {
                        final validationErrors = vm.validateAnswersForForm(
                          fields,
                          _answers,
                        );
                        final scrollSnapshot = widget.captureScrollSnapshot();
                        if (validationErrors.isNotEmpty ||
                            blockedMessage != null) {
                          setState(() {
                            _errors = validationErrors;
                          });
                          if (validationErrors.isNotEmpty) {
                            AppSnackbar.showError(
                              context,
                              widget.isDanger
                                  ? 'Please complete the required cancellation fields.'
                                  : 'Please complete the required booking fields.',
                            );
                          } else if (blockedMessage != null) {
                            AppSnackbar.showError(context, blockedMessage);
                          }
                          widget.restoreScrollSnapshot(scrollSnapshot);
                          return;
                        }
                        final confirmed = await showAdminActionConfirmation(
                          context,
                          title: widget.isDanger
                              ? 'Confirm Cancellation'
                              : 'Confirm Action',
                          message:
                              'Are you sure you want to ${actionLabel.toLowerCase()}?',
                          confirmLabel: actionLabel,
                          isDanger: widget.isDanger,
                        );
                        if (!confirmed || !mounted) {
                          widget.restoreScrollSnapshot(scrollSnapshot);
                          return;
                        }
                        setState(() {
                          _isSubmitting = true;
                        });
                        final savedBooking = await vm.submitSpecificForm(
                          form,
                          Map<String, dynamic>.from(_answers),
                        );
                        if (!mounted) {
                          return;
                        }
                        setState(() {
                          _isSubmitting = false;
                        });
                        if (savedBooking == null) {
                          widget.restoreScrollSnapshot(scrollSnapshot);
                          return;
                        }
                        widget.onUnfocusWithoutScroll();
                        setState(() {
                          _answers = {};
                          _errors = {};
                          _resetTick += 1;
                        });
                        widget.onBookingUpdated?.call(savedBooking);
                        if (!mounted) {
                          return;
                        }
                        if (!context.mounted) {
                          return;
                        }
                        AppSnackbar.showSuccess(
                          context,
                          widget.isDanger
                              ? 'Booking cancelled.'
                              : 'Booking updated.',
                        );
                      },
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  backgroundColor: widget.isDanger
                      ? AppColors.dangerStrong
                      : _workflowResolvedActionColor(
                          title: resolvedTitle,
                          buttonText: actionLabel,
                          currentStatusKey: form.currentStatusKey,
                        ),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(_isSubmitting ? 'Saving ...' : actionLabel),
              ),
            );
            final clearButton = GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => widget.onUnfocusWithoutScroll(),
              child: TextButton(
                onPressed: _isSubmitting
                    ? null
                    : () {
                        widget.onUnfocusWithoutScroll();
                        setState(() {
                          _answers = {};
                          _errors = {};
                          _resetTick += 1;
                        });
                      },
                style: TextButton.styleFrom(
                  foregroundColor: widget.isDanger
                      ? AppColors.dangerStrong
                      : _workflowResolvedActionColor(
                          title: resolvedTitle,
                          buttonText: actionLabel,
                          currentStatusKey: form.currentStatusKey,
                        ),
                ),
                child: const Text('Clear Form'),
              ),
            );
            final useStackedLayout =
                fields.isNotEmpty && constraints.maxWidth < 260;

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

            return Row(
              children: [
                submitButton,
                if (fields.isNotEmpty) ...[const Spacer(), clearButton],
              ],
            );
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

class _WorkflowTaskCard extends StatefulWidget {
  const _WorkflowTaskCard({
    required this.vm,
    required this.title,
    this.buttonText,
    this.currentStatusKey,
    required this.preferredScrollController,
    required this.blockedMessage,
    required this.fields,
    required this.errors,
    required this.answers,
    required this.resetTick,
    required this.onChanged,
    this.submitFocusNode,
    this.allowAdditionalFields = true,
  });

  final BookingWorkflowViewModel vm;
  final String title;
  final String? buttonText;
  final String? currentStatusKey;
  final ScrollController? preferredScrollController;
  final String? blockedMessage;
  final List<StatusField> fields;
  final Map<String, String> errors;
  final Map<String, dynamic> answers;
  final int resetTick;
  final void Function(String fieldKey, dynamic value) onChanged;
  final FocusNode? submitFocusNode;
  final bool allowAdditionalFields;

  @override
  State<_WorkflowTaskCard> createState() => _WorkflowTaskCardState();
}

class _WorkflowTaskCardState extends State<_WorkflowTaskCard> {
  final Map<String, FocusNode> _fieldFocusNodes = {};

  String _focusKeyForField(StatusField field, int index) {
    final key = (field.key ?? '').trim();
    if (key.isNotEmpty) {
      return key;
    }
    return '__index_$index:${field.type}:${field.title}';
  }

  List<StatusField> get _orderedFields {
    final ordered = <StatusField>[...widget.fields];
    if (widget.allowAdditionalFields) {
      ordered.addAll(
        widget.vm.additionalFields.where((field) {
          final key = field.key?.trim();
          return key != null && key.isNotEmpty;
        }),
      );
    }
    return StatusFormEngine.visibleFields(ordered, widget.answers);
  }

  void _syncFocusNodes(List<StatusField> fields) {
    final activeKeys = <String>{};
    for (var index = 0; index < fields.length; index++) {
      final focusKey = _focusKeyForField(fields[index], index);
      activeKeys.add(focusKey);
      _fieldFocusNodes.putIfAbsent(
        focusKey,
        () => FocusNode(debugLabel: 'workflow_field($focusKey)'),
      );
    }

    final removedKeys = _fieldFocusNodes.keys
        .where((key) => !activeKeys.contains(key))
        .toList();
    for (final key in removedKeys) {
      _fieldFocusNodes.remove(key)?.dispose();
    }
  }

  bool _shouldActivateNextField(StatusField? nextField, FocusNode? nextFocus) {
    if (nextFocus == null) {
      return false;
    }
    if (nextField == null) {
      return true;
    }
    final type = (nextField.type ?? '').trim().toLowerCase();
    return type == 'dropdown' ||
        type == 'search_dropdown' ||
        type == 'date' ||
        type == 'time' ||
        type == 'photo';
  }

  @override
  void dispose() {
    for (final node in _fieldFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = _workflowResolvedPalette(
      title: widget.title,
      buttonText: widget.buttonText,
      currentStatusKey: widget.currentStatusKey,
    );
    final orderedFields = _orderedFields;
    _syncFocusNodes(orderedFields);
    final canManageFields =
        widget.vm.supportsAdditionalFields && widget.allowAdditionalFields;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.blockedMessage?.trim().isNotEmpty == true) ...[
          Text(
            widget.blockedMessage!,
            style: const TextStyle(
              color: AppColors.dangerStrong,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (canManageFields)
          ReorderableListView(
            shrinkWrap: true,
            buildDefaultDragHandles: false,
            physics: const NeverScrollableScrollPhysics(),
            proxyDecorator: (child, index, animation) {
              final proxyChild = child is _WorkflowReorderableFieldListItem
                  ? child.proxyChild
                  : child;
              return AnimatedBuilder(
                animation: animation,
                builder: (context, _) {
                  return Material(
                    type: MaterialType.transparency,
                    borderRadius: BorderRadius.circular(18),
                    clipBehavior: Clip.antiAlias,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    surfaceTintColor: Colors.transparent,
                    child: proxyChild,
                  );
                },
              );
            },
            onReorder: (oldIndex, newIndex) {
              widget.vm.reorderManagedFields(
                orderedFields,
                oldIndex,
                newIndex,
                answers: widget.answers,
              );
            },
            children: orderedFields.asMap().entries.map((entry) {
              final field = entry.value;
              final isLastField = entry.key == orderedFields.length - 1;
              final orderedIndex = orderedFields.indexOf(field);
              final focusKey = _focusKeyForField(field, orderedIndex);
              final nextField = orderedIndex + 1 < orderedFields.length
                  ? orderedFields[orderedIndex + 1]
                  : null;
              final nextFocusNode = nextField == null
                  ? widget.submitFocusNode
                  : _fieldFocusNodes[_focusKeyForField(
                      nextField,
                      orderedIndex + 1,
                    )];
              final fieldKey = field.key ?? '';
              final fieldCard = _WorkflowRemovableFieldCard(
                vm: widget.vm,
                formTitle: widget.title,
                formButtonText: widget.buttonText,
                formStatusKey: widget.currentStatusKey,
                preferredScrollController: widget.preferredScrollController,
                field: field,
                focusNode: _fieldFocusNodes[focusKey],
                nextFocusNode: nextFocusNode,
                activateNextFocus: _shouldActivateNextField(
                  nextField,
                  nextFocusNode,
                ),
                errorText: widget.errors[fieldKey],
                initialValue: widget.answers[fieldKey],
                onChanged: (value) => widget.onChanged(fieldKey, value),
                onRemove: () => widget.vm.removeManagedField(field),
                onEdit: () =>
                    _openFieldEditor(context, widget.vm, initialField: field),
                dragHandle: widget.vm.isFormAssignedField(field)
                    ? ReorderableDragStartListener(
                        index: entry.key,
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: Icon(
                            Icons.drag_indicator_rounded,
                            size: 20,
                            color: palette.accent.withValues(alpha: 0.8),
                          ),
                        ),
                      )
                    : null,
              );
              return _WorkflowReorderableFieldListItem(
                key: ValueKey(
                  '${field.key}:${field.type}:${field.updatedAt?.millisecondsSinceEpoch ?? 0}:${widget.resetTick}',
                ),
                bottomSpacing: isLastField ? 0 : 14,
                child: fieldCard,
              );
            }).toList(),
          )
        else
          ...orderedFields.asMap().entries.map((entry) {
            final field = entry.value;
            final isLastField = entry.key == orderedFields.length - 1;
            final orderedIndex = orderedFields.indexOf(field);
            final focusKey = _focusKeyForField(field, orderedIndex);
            final nextField = orderedIndex + 1 < orderedFields.length
                ? orderedFields[orderedIndex + 1]
                : null;
            final nextFocusNode = nextField == null
                ? widget.submitFocusNode
                : _fieldFocusNodes[_focusKeyForField(
                    nextField,
                    orderedIndex + 1,
                  )];
            return Padding(
              padding: EdgeInsets.only(bottom: isLastField ? 0 : 14),
              child: _WorkflowFieldCard(
                key: ValueKey('${field.key}:${widget.resetTick}'),
                vm: widget.vm,
                formTitle: widget.title,
                formButtonText: widget.buttonText,
                formStatusKey: widget.currentStatusKey,
                palette: palette,
                preferredScrollController: widget.preferredScrollController,
                field: field,
                focusNode: _fieldFocusNodes[focusKey],
                nextFocusNode: nextFocusNode,
                activateNextFocus: _shouldActivateNextField(
                  nextField,
                  nextFocusNode,
                ),
                initialValue: widget.answers[field.key],
                errorText: widget.errors[field.key],
                onEdit: null,
                onChanged: (value) {
                  final key = field.key;
                  if (key == null || key.isEmpty) {
                    return;
                  }
                  widget.onChanged(key, value);
                },
              ),
            );
          }),
      ],
    );
  }

  Future<void> _openFieldEditor(
    BuildContext context,
    BookingWorkflowViewModel vm, {
    required StatusField initialField,
    bool addAfterSave = false,
  }) async {
    final savedField = await showDialog<StatusField>(
      context: context,
      builder: (dialogContext) => _BookingFieldEditorDialog(
        title: initialField.id == vm.nextFieldId ? 'New Field' : 'Edit Field',
        initialField: initialField,
      ),
    );

    if (savedField == null || !context.mounted) {
      return;
    }

    final persistedField = await vm.saveLibraryField(savedField);
    if (addAfterSave) {
      final persistedId = persistedField.id ?? '';
      if (persistedId.isNotEmpty) {
        await vm.addExistingField(persistedId);
      }
    }
    if (!context.mounted) {
      return;
    }
    AppSnackbar.showSuccess(
      context,
      addAfterSave ? 'Field added.' : 'Field updated.',
    );
  }
}

class _WorkflowAddFieldButton extends StatelessWidget {
  const _WorkflowAddFieldButton({
    required this.availableFields,
    required this.onSelected,
    required this.onCreateNew,
    required this.textColor,
  });

  final List<StatusField> availableFields;
  final Future<void> Function(String) onSelected;
  final VoidCallback onCreateNew;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (buttonContext) {
        return TextButton(
          onPressed: () async {
            final button = buttonContext.findRenderObject() as RenderBox?;
            final overlay = Overlay.of(buttonContext)
                .context
                .findRenderObject() as RenderBox?;
            if (button == null || overlay == null) {
              return;
            }
            final result = await showMenu<String>(
              context: buttonContext,
              color: Colors.white,
              surfaceTintColor: Colors.white,
              position: RelativeRect.fromRect(
                Rect.fromPoints(
                  button.localToGlobal(Offset.zero, ancestor: overlay),
                  button.localToGlobal(
                    button.size.bottomRight(Offset.zero),
                    ancestor: overlay,
                  ),
                ),
                Offset.zero & overlay.size,
              ),
              items: [
                ...availableFields.map(
                  (field) => PopupMenuItem<String>(
                    value: field.id,
                    child: Text(
                      field.title?.trim().isNotEmpty == true
                          ? field.title!
                          : field.key ?? 'Untitled Field',
                      style: adminDropdownDisplayTextStyle,
                    ),
                  ),
                ),
                if (availableFields.isNotEmpty)
                  const PopupMenuDivider(height: 1, thickness: 1),
                PopupMenuItem<String>(
                  value: '__create_new_field__',
                  child: Text(
                    'Create New Field',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            );
            if (result == null) {
              return;
            }
            if (result == '__create_new_field__') {
              onCreateNew();
              return;
            }
            await onSelected(result);
          },
          style: TextButton.styleFrom(foregroundColor: textColor),
          child: const Text('Add Field'),
        );
      },
    );
  }
}

class _WorkflowAlertHeaderCard extends StatelessWidget {
  const _WorkflowAlertHeaderCard({
    required this.title,
    this.subtitle,
    this.showRequiredLegend = false,
  });

  final String title;
  final String? subtitle;
  final bool showRequiredLegend;

  @override
  Widget build(BuildContext context) {
    return BookingFormTitleCardShell(
      stripColor: AppColors.dangerStrong,
      borderColor: AppColors.dangerBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          if (subtitle?.trim().isNotEmpty == true)
            Text(
              subtitle!.trim(),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          if (showRequiredLegend) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              height: 1,
              color: AppColors.dangerBorder,
            ),
            const SizedBox(height: 14),
            const Text(
              '* indicates required input',
              style: TextStyle(
                color: AppColors.dangerStrong,
                fontSize: 14,
                fontWeight: FontWeight.w400,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WorkflowRemovableFieldCard extends StatelessWidget {
  const _WorkflowRemovableFieldCard({
    required this.vm,
    required this.formTitle,
    required this.formButtonText,
    required this.formStatusKey,
    required this.preferredScrollController,
    required this.field,
    required this.initialValue,
    required this.onChanged,
    required this.onRemove,
    required this.onEdit,
    this.focusNode,
    this.nextFocusNode,
    this.activateNextFocus = false,
    this.errorText,
    this.dragHandle,
  });

  final BookingWorkflowViewModel vm;
  final String formTitle;
  final String? formButtonText;
  final String? formStatusKey;
  final ScrollController? preferredScrollController;
  final StatusField field;
  final dynamic initialValue;
  final ValueChanged<dynamic> onChanged;
  final VoidCallback onRemove;
  final VoidCallback onEdit;
  final FocusNode? focusNode;
  final FocusNode? nextFocusNode;
  final bool activateNextFocus;
  final String? errorText;
  final Widget? dragHandle;

  @override
  Widget build(BuildContext context) {
    final palette = _workflowResolvedPalette(
      title: formTitle,
      buttonText: formButtonText,
      currentStatusKey: formStatusKey,
    );
    final editColor = _workflowResolvedActionColor(
      title: formTitle,
      buttonText: formButtonText,
      currentStatusKey: formStatusKey,
    );
    return _WorkflowFieldCard(
      vm: vm,
      formTitle: formTitle,
      formButtonText: formButtonText,
      formStatusKey: formStatusKey,
      palette: palette,
      preferredScrollController: preferredScrollController,
      field: field,
      focusNode: focusNode,
      nextFocusNode: nextFocusNode,
      activateNextFocus: activateNextFocus,
      initialValue: initialValue,
      errorText: errorText,
      headerTrailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: IconButton(
              onPressed: onEdit,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit_rounded, size: 18),
              color: editColor,
              splashRadius: 18,
            ),
          ),
          SizedBox(
            width: 36,
            height: 36,
            child: IconButton(
              onPressed: onRemove,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_rounded, size: 18),
              color: AppColors.dangerStrong,
              splashRadius: 18,
            ),
          ),
          if (dragHandle != null) ...[
            const SizedBox(width: 2),
            SizedBox(width: 36, height: 36, child: Center(child: dragHandle!)),
          ],
        ],
      ),
      onChanged: onChanged,
    );
  }
}

class _WorkflowReorderableFieldListItem extends StatelessWidget {
  const _WorkflowReorderableFieldListItem({
    super.key,
    required this.child,
    required this.bottomSpacing,
  });

  final Widget child;
  final double bottomSpacing;

  Widget get proxyChild => child;

  @override
  Widget build(BuildContext context) {
    if (bottomSpacing <= 0) {
      return child;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        SizedBox(height: bottomSpacing),
      ],
    );
  }
}

class _WorkflowFieldCard extends StatelessWidget {
  const _WorkflowFieldCard({
    super.key,
    required this.vm,
    required this.formTitle,
    required this.formButtonText,
    required this.formStatusKey,
    required this.palette,
    required this.preferredScrollController,
    required this.field,
    required this.initialValue,
    required this.onChanged,
    this.focusNode,
    this.nextFocusNode,
    this.activateNextFocus = false,
    this.headerTrailing,
    this.onEdit,
    this.errorText,
  });

  final BookingWorkflowViewModel vm;
  final String formTitle;
  final String? formButtonText;
  final String? formStatusKey;
  final BookingFormPalette palette;
  final ScrollController? preferredScrollController;
  final StatusField field;
  final dynamic initialValue;
  final ValueChanged<dynamic> onChanged;
  final FocusNode? focusNode;
  final FocusNode? nextFocusNode;
  final bool activateNextFocus;
  final Widget? headerTrailing;
  final VoidCallback? onEdit;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final title = field.title?.trim();
    final subtitle = field.subtitle?.trim();
    final instructions = field.instructions?.trim();
    final placeholder = field.placeholder?.trim();
    final effectiveTitle = title?.isNotEmpty == true ? title! : 'Field';
    final type = (field.type ?? 'text').trim().toLowerCase();
    final fieldKey = (field.key ?? '').trim().toLowerCase();
    final optionSourceKey = StatusFieldOptionResolver.resolvedOptionSourceKey(
      field,
    );
    final usesRoleDropdown =
        fieldKey == 'driver_id' ||
        optionSourceKey == statusFieldOptionSourceDrivers ||
        fieldKey == 'helper_id' ||
        optionSourceKey == statusFieldOptionSourceHelpers;
    final isSearchDropdownCard =
        type == 'search_dropdown' || isPalawanLocationFieldKey(fieldKey);
    final isNormalDropdownCard = type == 'dropdown' || usesRoleDropdown;
    final usesCompactDropdownCard =
        isNormalDropdownCard || isSearchDropdownCard;
    final editColor = _workflowResolvedActionColor(
      title: formTitle,
      buttonText: formButtonText,
      currentStatusKey: formStatusKey,
    );

    return BookingFormFieldCard(
      title: effectiveTitle,
      buttonText: formButtonText,
      paletteOverride: palette,
      required: field.required ?? false,
      subtitle: subtitle,
      instructions: instructions,
      inputTopSpacing: usesCompactDropdownCard ? 10 : 14,
      containerPadding: isSearchDropdownCard
          ? const EdgeInsets.fromLTRB(18, 8, 18, 4)
          : (isNormalDropdownCard
                ? const EdgeInsets.fromLTRB(18, 8, 18, 8)
                : const EdgeInsets.fromLTRB(18, 8, 18, 18)),
      headerTrailing:
          headerTrailing ??
          (onEdit == null
              ? null
              : TextButton.icon(
                  onPressed: onEdit,
                  style: TextButton.styleFrom(
                    foregroundColor: editColor,
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('Edit'),
                )),
      input: _buildFieldInput(
        context,
        palette: palette,
        placeholder: placeholder,
        errorText: errorText,
      ),
    );
  }

  Widget _buildFieldInput(
    BuildContext context, {
    required BookingFormPalette palette,
    required String? placeholder,
    required String? errorText,
  }) {
    final type = (field.type ?? 'text').trim().toLowerCase();
    final fieldKey = (field.key ?? '').trim().toLowerCase();
    final fieldLabel = field.title?.trim().isNotEmpty == true
        ? field.title!.trim()
        : 'Field';
    final optionSourceKey = StatusFieldOptionResolver.resolvedOptionSourceKey(
      field,
    );

    if (fieldKey == 'driver_id' ||
        optionSourceKey == statusFieldOptionSourceDrivers) {
      return _roleUserDropdown(
        context,
        role: 'driver',
        placeholder: placeholder,
        errorText: errorText,
      );
    }
    if (fieldKey == 'helper_id' ||
        optionSourceKey == statusFieldOptionSourceHelpers) {
      return _roleUserDropdown(
        context,
        role: 'helper',
        placeholder: placeholder,
        errorText: errorText,
      );
    }
    if (isPalawanLocationFieldKey(fieldKey)) {
      return AdminSearchSelectFormField(
        initialValue: initialValue?.toString(),
        focusNode: focusNode,
        autoActivateOnFocus: activateNextFocus,
        decoration: _bookingDropdownDecoration(
          (field.required ?? false)
              ? adminSelectPlaceholder(fieldLabel, override: placeholder)
              : (placeholder?.trim().isNotEmpty == true ? placeholder! : 'Optional'),
          palette,
        ).copyWith(errorText: errorText),
        options: palawanLocationOptions,
        onChanged: (value) {
          onChanged(value);
          final resolvedNextFocusNode = nextFocusNode;
          if (resolvedNextFocusNode != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) {
                return;
              }
              FocusScope.of(context).requestFocus(resolvedNextFocusNode);
              if (activateNextFocus) {
                final primaryFocus = FocusManager.instance.primaryFocus;
                final targetContext =
                    primaryFocus?.context ?? resolvedNextFocusNode.context;
                if (targetContext != null) {
                  Actions.maybeInvoke(targetContext, const ActivateIntent());
                }
              }
            });
          } else {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) {
                return;
              }
              FocusScope.of(context).unfocus();
            });
          }
        },
      );
    }

    switch (type) {
      case 'search_dropdown':
        return AdminSearchSelectFormField(
          initialValue: initialValue?.toString(),
          focusNode: focusNode,
          autoActivateOnFocus: activateNextFocus,
          decoration: _bookingDropdownDecoration(
            (field.required ?? false)
                ? adminSelectPlaceholder(fieldLabel, override: placeholder)
                : (placeholder?.trim().isNotEmpty == true
                      ? placeholder!
                      : 'Optional'),
            palette,
          ).copyWith(errorText: errorText),
          options: field.options,
          onChanged: (value) {
            onChanged(value);
            final resolvedNextFocusNode = nextFocusNode;
            if (resolvedNextFocusNode != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!context.mounted) {
                  return;
                }
                FocusScope.of(context).requestFocus(resolvedNextFocusNode);
                if (activateNextFocus) {
                  final primaryFocus = FocusManager.instance.primaryFocus;
                  final targetContext =
                      primaryFocus?.context ?? resolvedNextFocusNode.context;
                  if (targetContext != null) {
                    Actions.maybeInvoke(targetContext, const ActivateIntent());
                  }
                }
              });
            } else {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!context.mounted) {
                  return;
                }
                FocusScope.of(context).unfocus();
              });
            }
          },
        );
      case 'number':
        return _UnderlineTextField(
          formTitle: formTitle,
          formButtonText: formButtonText,
          formStatusKey: formStatusKey,
          preferredScrollController: preferredScrollController,
          initialValue: initialValue?.toString(),
          focusNode: focusNode,
          nextFocusNode: nextFocusNode,
          activateNextFocus: activateNextFocus,
          keyboardType: TextInputType.number,
          hintText: (field.required ?? false)
              ? adminEnterPlaceholder(fieldLabel, override: placeholder)
              : (placeholder?.trim().isNotEmpty == true ? placeholder : 'Optional'),
          errorText: errorText,
          onChanged: (value) => onChanged(value.trim()),
        );
      case 'email':
        return _UnderlineTextField(
          formTitle: formTitle,
          formButtonText: formButtonText,
          formStatusKey: formStatusKey,
          preferredScrollController: preferredScrollController,
          initialValue: initialValue?.toString(),
          focusNode: focusNode,
          nextFocusNode: nextFocusNode,
          activateNextFocus: activateNextFocus,
          keyboardType: TextInputType.emailAddress,
          hintText: (field.required ?? false)
              ? adminEnterPlaceholder(fieldLabel, override: placeholder)
              : (placeholder?.trim().isNotEmpty == true ? placeholder : 'Optional'),
          errorText: errorText,
          onChanged: (value) => onChanged(value.trim()),
        );
      case 'phone':
        return _UnderlineTextField(
          formTitle: formTitle,
          formButtonText: formButtonText,
          formStatusKey: formStatusKey,
          preferredScrollController: preferredScrollController,
          initialValue: initialValue?.toString(),
          focusNode: focusNode,
          nextFocusNode: nextFocusNode,
          activateNextFocus: activateNextFocus,
          keyboardType: TextInputType.phone,
          inputFormatters: const [PhilippinesPhoneInputFormatter()],
          hintText: (field.required ?? false)
              ? adminEnterPlaceholder(fieldLabel, override: placeholder)
              : (placeholder?.trim().isNotEmpty == true ? placeholder : 'Optional'),
          errorText: errorText,
          onChanged: (value) => onChanged(value.trim()),
        );
      case 'text':
        return _UnderlineTextField(
          formTitle: formTitle,
          formButtonText: formButtonText,
          formStatusKey: formStatusKey,
          preferredScrollController: preferredScrollController,
          initialValue: initialValue?.toString(),
          focusNode: focusNode,
          nextFocusNode: nextFocusNode,
          activateNextFocus: activateNextFocus,
          hintText: (field.required ?? false)
              ? adminEnterPlaceholder(fieldLabel, override: placeholder)
              : (placeholder?.trim().isNotEmpty == true ? placeholder : 'Optional'),
          errorText: errorText,
          onChanged: (value) => onChanged(value.trim()),
        );
      case 'dropdown':
        final optionSourceKey =
            StatusFieldOptionResolver.resolvedOptionSourceKey(field);
        final memberOptionLabels =
            optionSourceKey == statusFieldOptionSourceClientMembers ||
                fieldKey == 'representative_id'
            ? vm.memberOptionLabelsForCurrentBooking()
            : const <String, String>{};
        final effectiveOptions = field.options.isNotEmpty
            ? field.options
            : memberOptionLabels.keys.toList();
        return AdminDropdownFormField<String>(
          initialValue: initialValue?.toString(),
          focusNode: focusNode,
          iconEnabledColor: palette.accent,
          decoration: _bookingDropdownDecoration(
            (field.required ?? false)
                ? adminSelectPlaceholder(fieldLabel, override: placeholder)
                : (placeholder?.trim().isNotEmpty == true ? placeholder! : 'Optional'),
            palette,
          ).copyWith(errorText: errorText),
          style: adminDropdownDisplayTextStyle,
          items: effectiveOptions.map((item) {
            final label =
                memberOptionLabels[item] ??
                (optionSourceKey == statusFieldOptionSourceVehicleSizes
                    ? VehicleRequest.instance.displayVehicleSizeLabel(item)
                    : item);
            return DropdownMenuItem<String>(
              value: item,
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: adminDropdownDisplayTextStyle,
              ),
            );
          }).toList(),
          onChanged: (value) {
            onChanged(value);
            final resolvedNextFocusNode = nextFocusNode;
            if (resolvedNextFocusNode != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!context.mounted) {
                  return;
                }
                FocusScope.of(context).requestFocus(resolvedNextFocusNode);
                if (activateNextFocus) {
                  final primaryFocus = FocusManager.instance.primaryFocus;
                  final targetContext =
                      primaryFocus?.context ?? resolvedNextFocusNode.context;
                  if (targetContext != null) {
                    Actions.maybeInvoke(targetContext, const ActivateIntent());
                  }
                }
              });
            } else {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!context.mounted) {
                  return;
                }
                FocusScope.of(context).unfocus();
              });
            }
          },
        );
      case 'checkbox':
        final selectedValues =
            (initialValue as List?)?.map((item) => '$item').toSet() ??
            <String>{};
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: field.options.map((option) {
            final isSelected = selectedValues.contains(option);
            return FilterChip(
              label: Text(option),
              selected: isSelected,
              onSelected: (selected) {
                final next = {...selectedValues};
                if (selected) {
                  next.add(option);
                } else {
                  next.remove(option);
                }
                onChanged(next.toList());
              },
            );
          }).toList(),
        );
      case 'date':
        return _SelectButton(
          formTitle: formTitle,
          formButtonText: formButtonText,
          formStatusKey: formStatusKey,
          focusNode: focusNode,
          label: initialValue?.toString() ??
              ((field.required ?? false)
                  ? adminSelectPlaceholder(fieldLabel, override: placeholder)
                  : (placeholder?.trim().isNotEmpty == true
                        ? placeholder!
                        : 'Optional')),
          isPlaceholder: initialValue == null,
          icon: Icons.calendar_today_rounded,
          onPressed: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: now,
              firstDate: DateTime(now.year - 5),
              lastDate: DateTime(now.year + 5),
            );
            if (picked != null) {
              onChanged(picked.toIso8601String().split('T').first);
            }
          },
        );
      case 'time':
        return _SelectButton(
          formTitle: formTitle,
          formButtonText: formButtonText,
          formStatusKey: formStatusKey,
          focusNode: focusNode,
          label: initialValue?.toString() ??
              ((field.required ?? false)
                  ? adminSelectPlaceholder(fieldLabel, override: placeholder)
                  : (placeholder?.trim().isNotEmpty == true
                        ? placeholder!
                        : 'Optional')),
          isPlaceholder: initialValue == null,
          icon: Icons.schedule_rounded,
          onPressed: () async {
            final localizations = MaterialLocalizations.of(context);
            final picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.now(),
            );
            if (picked != null) {
              onChanged(localizations.formatTimeOfDay(picked));
            }
          },
        );
      case 'photo':
        return _PhotoField(
          formTitle: formTitle,
          formButtonText: formButtonText,
          formStatusKey: formStatusKey,
          focusNode: focusNode,
          nextFocusNode: nextFocusNode,
          activateNextFocus: activateNextFocus,
          initialValue: initialValue,
          errorText: errorText,
          onChanged: onChanged,
          placeholder: (field.required ?? false)
              ? adminUploadPlaceholder(fieldLabel, override: placeholder)
              : (placeholder?.trim().isNotEmpty == true ? placeholder! : 'Optional'),
        );
      default:
        return _UnderlineTextField(
          formTitle: formTitle,
          formButtonText: formButtonText,
          formStatusKey: formStatusKey,
          preferredScrollController: preferredScrollController,
          initialValue: initialValue?.toString(),
          focusNode: focusNode,
          nextFocusNode: nextFocusNode,
          activateNextFocus: activateNextFocus,
          hintText: (field.required ?? false)
              ? adminEnterPlaceholder(fieldLabel, override: placeholder)
              : (placeholder?.trim().isNotEmpty == true ? placeholder : 'Optional'),
          errorText: errorText,
          onChanged: (value) => onChanged(value.trim()),
        );
    }
  }

  Widget _roleUserDropdown(
    BuildContext context, {
    required String role,
    required String? placeholder,
    required String? errorText,
  }) {
    final palette = bookingFormResolvedPalette(
      title: formTitle,
      buttonText: formButtonText,
    );
    final users = vm.roleUsers(role);
    final selectedUserId = initialValue?.toString().trim();
    final items = <DropdownMenuItem<String>>[];
    final seenValues = <String>{};

    void addUserItem(String value, String label) {
      final normalizedValue = value.trim();
      if (normalizedValue.isEmpty || !seenValues.add(normalizedValue)) {
        return;
      }
      items.add(
        DropdownMenuItem<String>(
          value: normalizedValue,
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: adminDropdownDisplayTextStyle,
          ),
        ),
      );
    }

    if (selectedUserId != null && selectedUserId.isNotEmpty) {
      addUserItem(
        selectedUserId,
        vm.roleUserLabel(selectedUserId, fallbackRole: role),
      );
    }

    for (final user in users) {
      final userId = user.id?.trim();
      if (userId == null || userId.isEmpty) {
        continue;
      }
      addUserItem(userId, vm.roleUserLabel(userId, fallbackRole: role));
    }

    return AdminDropdownFormField<String>(
      initialValue: initialValue?.toString(),
      focusNode: focusNode,
      iconEnabledColor: palette.accent,
      decoration: _bookingDropdownDecoration(
        placeholder?.trim().isNotEmpty == true
            ? placeholder!.trim()
            : 'Select ${role == 'driver' ? 'Driver' : 'Helper'}',
        palette,
      ).copyWith(errorText: errorText),
      style: adminDropdownDisplayTextStyle,
      items: items,
      disabledTapMessage: role == 'driver'
          ? 'No online drivers available.'
          : 'No online helpers available.',
      onChanged: (value) {
        onChanged(value);
        final resolvedNextFocusNode = nextFocusNode;
        if (resolvedNextFocusNode != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) {
              return;
            }
            FocusScope.of(context).requestFocus(resolvedNextFocusNode);
            if (activateNextFocus) {
              final primaryFocus = FocusManager.instance.primaryFocus;
              final targetContext =
                  primaryFocus?.context ?? resolvedNextFocusNode.context;
              if (targetContext != null) {
                Actions.maybeInvoke(targetContext, const ActivateIntent());
              }
            }
          });
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) {
              return;
            }
            FocusScope.of(context).unfocus();
          });
        }
      },
    );
  }

  InputDecoration _bookingDropdownDecoration(
    String hintText,
    BookingFormPalette palette,
  ) {
    return adminPlainDropdownDecoration(hintText, radius: 16).copyWith(
      fillColor: palette.surface,
      hintStyle: adminFieldHintTextStyle.copyWith(color: palette.accentMuted),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: palette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: palette.accent),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: palette.border),
      ),
      constraints: const BoxConstraints(minHeight: adminModalFieldMinHeight),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    );
  }
}

class _BookingFieldEditorDialog extends StatefulWidget {
  const _BookingFieldEditorDialog({
    required this.title,
    required this.initialField,
  });

  final String title;
  final StatusField initialField;

  @override
  State<_BookingFieldEditorDialog> createState() =>
      _BookingFieldEditorDialogState();
}

class _BookingFieldEditorDialogState extends State<_BookingFieldEditorDialog> {
  late StatusField _field;

  @override
  void initState() {
    super.initState();
    _field = widget.initialField;
  }

  String? _validationMessage() {
    if ((_field.key ?? '').trim().isEmpty) {
      return 'Field key is required.';
    }
    if ((_field.type ?? '').trim().isEmpty) {
      return 'Field type is required.';
    }
    if ((_field.title ?? '').trim().isEmpty) {
      return 'Field title is required.';
    }
    final fieldType = (_field.type ?? '').trim();
    final sourceKey =
        StatusField.normalizedOptionSourceKey(_field.optionSourceKey) ??
        statusFieldOptionSourceStatic;
    final options = _field.options
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    final usesDynamicSource = statusFieldDynamicOptionSources.contains(
      sourceKey,
    );
    if ((fieldType == 'dropdown' || fieldType == 'search_dropdown') &&
        !usesDynamicSource &&
        options.isEmpty) {
      return 'Add at least one static choice or pick a choices source.';
    }
    if (fieldType == 'checkbox' && options.isEmpty) {
      return 'Add at least one choice.';
    }
    final visibilityControllerKey = (_field.visibilityControllerKey ?? '').trim();
    final visibilityOptionValues = _field.visibilityOptionValues
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (visibilityControllerKey.isNotEmpty && visibilityOptionValues.isEmpty) {
      return 'Add at least one Show When option.';
    }
    if (visibilityControllerKey.isEmpty && visibilityOptionValues.isNotEmpty) {
      return 'Show When Field Key is required.';
    }
    return null;
  }

  void _submitForm() {
    final validationMessage = _validationMessage();
    if (validationMessage != null) {
      AppSnackbar.showError(context, validationMessage);
      return;
    }
    Navigator.of(context).pop(_normalizeFieldPlaceholder(_field));
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
    if (fieldType == 'dropdown' || fieldType == 'search_dropdown') {
      final isRequired = field.required ?? false;
      if (isRequired) {
        return field.copyWith(placeholder: null);
      }

      final currentPlaceholder = field.placeholder?.trim() ?? '';
      if (currentPlaceholder.isEmpty) {
        return field.copyWith(placeholder: 'Optional');
      }
    }

    if (fieldType != 'photo' &&
        fieldType != 'dropdown' &&
        fieldType != 'search_dropdown') {
      final isRequired = field.required ?? false;
      if (!isRequired) {
        final currentPlaceholder = field.placeholder?.trim() ?? '';
        if (currentPlaceholder.isEmpty) {
          return field.copyWith(placeholder: 'Optional');
        }
      }
    }

    return field;
  }

  @override
  Widget build(BuildContext context) {
    return AdminModalShell(
      title: widget.title,
      contentInset: const EdgeInsets.fromLTRB(0, 16, 0, 14),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submitForm, child: const Text('Save')),
      ],
      child: AdminModalFormBody(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: StatusFieldEditorCard(
              field: _field,
              index: 0,
              fieldTypeOptions: BookingWorkflowViewModel.fieldTypeOptions,
              showContainer: false,
              sectionGap: 10,
              headerBottomGap: 12,
              toggleTopGap: 0,
              toggleGap: 0,
              onSubmit: _submitForm,
              onUpdate: (property, value) {
                setState(() {
                  final updatedField = switch (property) {
                    'key' => _field.copyWith(key: value as String?),
                    'type' => _field.copyWith(type: value as String?),
                    'title' => _field.copyWith(title: value as String?),
                    'subtitle' => _field.copyWith(subtitle: value as String?),
                    'instructions' => _field.copyWith(
                      instructions: value as String?,
                    ),
                    'placeholder' => _field.copyWith(
                      placeholder: value as String?,
                    ),
                    'required' => _field.copyWith(required: value as bool?),
                    'min' => _field.copyWith(min: value as int?),
                    'max' => _field.copyWith(max: value as int?),
                    'options' => _field.copyWith(
                      options: value as List<String>,
                    ),
                    'optionSourceKey' => _field.copyWith(
                      optionSourceKey:
                          (value as String?) == statusFieldOptionSourceStatic
                          ? null
                          : value,
                    ),
                    'visibilityControllerKey' => _field.copyWith(
                      visibilityControllerKey: value as String?,
                    ),
                    'visibilityOptionValues' => _field.copyWith(
                      visibilityOptionValues: value as List<String>,
                    ),
                    'requiredError' => _field.copyWith(
                      requiredError: value as String?,
                    ),
                    'validationError' => _field.copyWith(
                      validationError: value as String?,
                    ),
                    'sortOrder' => _field.copyWith(sortOrder: value as int?),
                    'isActive' => _field.copyWith(isActive: value as bool?),
                    _ => _field,
                  };
                  _field = _normalizeFieldPlaceholder(updatedField);
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _UnderlineTextField extends StatefulWidget {
  const _UnderlineTextField({
    required this.onChanged,
    required this.formTitle,
    required this.formButtonText,
    required this.formStatusKey,
    this.preferredScrollController,
    this.initialValue,
    this.focusNode,
    this.nextFocusNode,
    this.activateNextFocus = false,
    this.keyboardType,
    this.hintText,
    this.errorText,
    this.inputFormatters,
  });

  final String? initialValue;
  final String formTitle;
  final String? formButtonText;
  final String? formStatusKey;
  final ScrollController? preferredScrollController;
  final FocusNode? focusNode;
  final FocusNode? nextFocusNode;
  final bool activateNextFocus;
  final TextInputType? keyboardType;
  final String? hintText;
  final String? errorText;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String> onChanged;

  @override
  State<_UnderlineTextField> createState() => _UnderlineTextFieldState();
}

class _UnderlineTextFieldState extends State<_UnderlineTextField> {
  late final TextEditingController _controller;

  void _focusAndMaybeActivateNext(FocusNode nextFocusNode) {
    FocusScope.of(context).requestFocus(nextFocusNode);
    if (!widget.activateNextFocus) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final primaryFocus = FocusManager.instance.primaryFocus;
      final targetContext = primaryFocus?.context ?? nextFocusNode.context;
      if (targetContext != null) {
        Actions.maybeInvoke(targetContext, const ActivateIntent());
      }
    });
  }

  void _unfocusWithoutScroll(PointerDownEvent event) {
    final preferredController = widget.preferredScrollController;
    final scrollPosition = preferredController?.hasClients == true
        ? preferredController!.position
        : Scrollable.maybeOf(context)?.position;
    final scrollOffset = scrollPosition?.hasPixels == true
        ? scrollPosition!.pixels
        : null;
    FocusManager.instance.primaryFocus?.unfocus();
    if (scrollPosition == null || scrollOffset == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scrollPosition.hasPixels) {
        return;
      }
      final clampedOffset = scrollOffset.clamp(
        scrollPosition.minScrollExtent,
        scrollPosition.maxScrollExtent,
      );
      if ((scrollPosition.pixels - clampedOffset).abs() >= 0.5) {
        scrollPosition.jumpTo(clampedOffset);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void didUpdateWidget(covariant _UnderlineTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextText = widget.initialValue ?? '';
    if (_controller.text == nextText) {
      return;
    }
    _controller.value = _controller.value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
      composing: TextRange.empty,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = _workflowResolvedPalette(
      title: widget.formTitle,
      buttonText: widget.formButtonText,
      currentStatusKey: widget.formStatusKey,
    );
    return TextField(
      controller: _controller,
      focusNode: widget.focusNode,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.inputFormatters,
      textInputAction: widget.nextFocusNode != null
          ? TextInputAction.next
          : TextInputAction.done,
      onSubmitted: (_) {
        final nextFocusNode = widget.nextFocusNode;
        if (nextFocusNode != null) {
          _focusAndMaybeActivateNext(nextFocusNode);
        } else {
          FocusScope.of(context).unfocus();
        }
      },
      scrollPadding: EdgeInsets.zero,
      onTapOutside: _unfocusWithoutScroll,
      onChanged: widget.onChanged,
      style: adminFieldValueTextStyle,
      decoration: InputDecoration(
        hintText: widget.hintText,
        isDense: true,
        hintStyle: adminFieldHintTextStyle.copyWith(color: palette.accentMuted),
        contentPadding: const EdgeInsets.only(top: 14, bottom: 10),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: palette.accent, width: 2),
        ),
        errorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.danger, width: 2),
        ),
        errorText: widget.errorText,
      ),
    );
  }
}

class _SelectButton extends StatelessWidget {
  const _SelectButton({
    required this.formTitle,
    required this.formButtonText,
    required this.formStatusKey,
    this.focusNode,
    required this.label,
    required this.isPlaceholder,
    required this.icon,
    required this.onPressed,
  });

  final String formTitle;
  final String? formButtonText;
  final String? formStatusKey;
  final FocusNode? focusNode;
  final String label;
  final bool isPlaceholder;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = _workflowResolvedPalette(
      title: formTitle,
      buttonText: formButtonText,
      currentStatusKey: formStatusKey,
    );
    return OutlinedButton.icon(
      focusNode: focusNode,
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: palette.accent),
      label: Text(
        label,
        style: TextStyle(
          color: isPlaceholder ? palette.accentMuted : AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
        alignment: Alignment.centerLeft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(color: palette.border),
      ),
    );
  }
}

class _PhotoField extends StatefulWidget {
  const _PhotoField({
    required this.formTitle,
    required this.formButtonText,
    required this.formStatusKey,
    required this.initialValue,
    required this.placeholder,
    required this.onChanged,
    this.focusNode,
    this.nextFocusNode,
    this.activateNextFocus = false,
    this.errorText,
  });

  final String formTitle;
  final String? formButtonText;
  final String? formStatusKey;
  final dynamic initialValue;
  final String placeholder;
  final ValueChanged<dynamic> onChanged;
  final FocusNode? focusNode;
  final FocusNode? nextFocusNode;
  final bool activateNextFocus;
  final String? errorText;

  @override
  State<_PhotoField> createState() => _PhotoFieldState();
}

class _PhotoFieldState extends State<_PhotoField> {
  void _focusAndMaybeActivateNext(FocusNode nextFocusNode) {
    FocusScope.of(context).requestFocus(nextFocusNode);
    if (!widget.activateNextFocus) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final primaryFocus = FocusManager.instance.primaryFocus;
      final targetContext = primaryFocus?.context ?? nextFocusNode.context;
      if (targetContext != null) {
        Actions.maybeInvoke(targetContext, const ActivateIntent());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BookingPhotoFieldInput(
      initialValue: widget.initialValue,
      focusNode: widget.focusNode,
      nextFocusNode: widget.nextFocusNode,
      activateNextFocus: widget.activateNextFocus,
      errorText: widget.errorText,
      palette: _workflowResolvedPalette(
        title: widget.formTitle,
        buttonText: widget.formButtonText,
        currentStatusKey: widget.formStatusKey,
      ),
      placeholder: widget.placeholder,
      onMoveToNextFocus: _focusAndMaybeActivateNext,
      onChanged: widget.onChanged,
    );
  }
}
