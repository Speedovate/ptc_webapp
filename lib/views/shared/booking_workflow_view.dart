import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stacked/stacked.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/status_form.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/services/status_field_option_resolver.dart';
import 'package:webapp/utils/functions.dart';
import 'package:webapp/view_models/shared/booking_workflow.vm.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';
import 'package:webapp/widgets/shared/app_snackbar.dart';
import 'package:webapp/widgets/shared/admin_action_confirmation.dart';
import 'package:webapp/widgets/shared/admin_modal_form_primitives.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/app_refresh_strip.dart';
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
  });

  final UserModel user;
  final Booking booking;
  final bool embedded;
  final ScrollController? embeddedScrollController;
  final ValueChanged<Booking>? onBookingUpdated;

  @override
  State<BookingWorkflowView> createState() => _BookingWorkflowViewState();
}

const String _bookingSupportPhoneDisplay = '+63 917 812 3776';
const String _bookingSupportPhoneDial = '+639178123776';

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

_WorkflowHeaderPalette? _terminalHeaderPaletteForStatus(String? statusKey) {
  switch (statusKey?.trim()) {
    case 'delivered':
      return const _WorkflowHeaderPalette(
        backgroundColor: Color(0xFF2EAD62),
        borderColor: Color(0xFF2EAD62),
        titleColor: Colors.white,
        subtitleColor: Color(0xFFE4F6EA),
      );
    case 'cancelled':
      return const _WorkflowHeaderPalette(
        backgroundColor: Color(0xFFC93B3B),
        borderColor: Color(0xFFC93B3B),
        titleColor: Colors.white,
        subtitleColor: Color(0xFFFFE0E0),
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

        if (widget.embedded) {
          return content;
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF7F7FB),
          appBar: AppBar(
            title: Text('Booking ${currentBooking.id ?? '-'}'),
            actions: [
              BookingSupportButton(
                onPressed: () => launchBookingSupport(context),
              ),
              const SizedBox(width: 8),
            ],
            backgroundColor: Colors.white,
            foregroundColor: AppColors.textPrimary,
            elevation: 0,
            surfaceTintColor: Colors.white,
          ),
          body: contentWithRefreshIndicator,
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
    final hasGuidance = guidanceMessage?.trim().isNotEmpty == true;
    final hasMultipleMainForms = vm.mainForms.length > 1;
    final hasMultipleSecondaryForms = vm.secondaryForms.length > 1;
    final hasActionForm = vm.hasActionablePrimaryForm;
    final hasCancelForm = vm.cancelForm != null;
    final hasFormFields = vm.fields.isNotEmpty;
    final hasBlockedMessage = vm.blockedMessage?.trim().isNotEmpty == true;
    final showTaskCard =
        hasBlockedMessage || hasFormFields || vm.supportsAdditionalFields;
    final terminalPalette = _terminalHeaderPaletteForStatus(
      currentBooking.clientStatus,
    );
    final actionSectionTopSpacing = hasActionForm
        ? (showTaskCard ? 16.0 : 14.0)
        : 0.0;
    final actionButtonTopSpacing = showTaskCard ? 16.0 : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BookingFormHeaderCard(
          title: currentStatusLabel,
          subtitle: statusDescription,
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
          if (showTaskCard) ...[
            _WorkflowTaskCard(
              vm: vm,
              title: vm.form?.buttonText?.trim().isNotEmpty == true
                  ? vm.form!.buttonText!.trim()
                  : 'Complete Booking Step',
              preferredScrollController: _preferredScrollController(),
              blockedMessage: vm.blockedMessage,
              fields: vm.fields,
              errors: vm.errors,
              answers: vm.answers,
              resetTick: vm.resetTick,
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
                child: _nonFocusable(
                  FilledButton(
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
                            final actionLabel =
                                vm.form?.buttonText?.trim().isNotEmpty == true
                                ? vm.form!.buttonText!.trim()
                                : 'Save';
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
                              'Booking has been updated.',
                            );
                          },
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      backgroundColor: AppColors.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      vm.isSubmitting
                          ? 'Saving...'
                          : (vm.form?.buttonText?.trim().isNotEmpty == true
                                ? vm.form!.buttonText!.trim()
                                : 'Save'),
                    ),
                  ),
                ),
              ),
              if (hasFormFields) ...[
                const Spacer(),
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
                    child: const Text('Clear Form'),
                  ),
                ),
              ],
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
          startValue: BookingRecordCard.outputFieldDisplayValue(
            currentBooking.statusOutputs,
            'start',
          ),
          endValue: BookingRecordCard.outputFieldDisplayValue(
            currentBooking.statusOutputs,
            'end',
          ),
          clientName: vm.userName(currentBooking.client?.id, 'Unknown client'),
          clientPhone: vm.userPhone(currentBooking.client?.id),
          driverName: vm.userName(currentBooking.driver?.id, '-'),
          driverPhone: vm.userPhone(currentBooking.driver?.id),
          helperName: vm.userName(currentBooking.helper?.id, '-'),
          helperPhone: vm.userPhone(currentBooking.helper?.id),
        ),
        if (widget.user.role != 'admin') ...[
          Builder(
            builder: (context) {
              final waybillPhotoValue = BookingRecordCard.outputFieldValue(
                currentBooking.statusOutputs,
                'waybill_photo',
              );
              final waybillPhotoBytes = decodeBase64PhotoBytes(
                waybillPhotoValue,
              );
              if (waybillPhotoBytes == null) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 16),
                child: _WorkflowWaybillPhotoCard(imageBytes: waybillPhotoBytes),
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
          _WorkflowAlertHeaderCard(
            title: vm.cancelForm?.statusText?.trim().isNotEmpty == true
                ? vm.cancelForm!.statusText!.trim()
                : (vm.cancelForm?.buttonText?.trim().isNotEmpty == true
                      ? vm.cancelForm!.buttonText!.trim()
                      : 'Cancellation'),
            subtitle: vm.cancelForm?.statusSubtext?.trim().isNotEmpty == true
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
                                vm.cancelForm?.buttonText?.trim().isNotEmpty ==
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
                              'Booking has been cancelled.',
                            );
                          },
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      backgroundColor: const Color(0xFFC93B3B),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      vm.isCancelSubmitting
                          ? 'Saving...'
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
                    Align(alignment: Alignment.centerRight, child: clearButton),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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

Future<void> launchBookingSupport(BuildContext context) async {
  final supportUri = Uri(scheme: 'tel', path: _bookingSupportPhoneDial);
  if (await launchUrl(supportUri)) {
    return;
  }
  if (!context.mounted) {
    return;
  }
  AppSnackbar.showError(
    context,
    'Could not open customer support for $_bookingSupportPhoneDisplay.',
  );
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
  const _WorkflowWaybillPhotoCard({required this.imageBytes});

  final Uint8List imageBytes;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Image.memory(
        imageBytes,
        width: double.infinity,
        fit: BoxFit.fitWidth,
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

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final form = widget.form;
    final fields = vm.fieldsForForm(form);
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.isDanger)
          _WorkflowAlertHeaderCard(
            title: resolvedTitle,
            subtitle: resolvedSubtitle,
          )
        else
          BookingFormHeaderCard(
            title: resolvedTitle,
            subtitle: resolvedSubtitle,
            backgroundColor: terminalPalette?.backgroundColor,
            borderColor: terminalPalette?.borderColor,
            titleColor: terminalPalette?.titleColor,
            subtitleColor: terminalPalette?.subtitleColor,
            message: blockedMessage,
            messageBackgroundColor: const Color(0xFFFFF6F6),
            messageBorderColor: const Color(0xFFFFD2D2),
            messageIcon: Icons.block_rounded,
            messageIconColor: const Color(0xFFC93B3B),
            messageTextColor: AppColors.textPrimary,
          ),
        const SizedBox(height: 14),
        _WorkflowTaskCard(
          vm: vm,
          title: resolvedTitle,
          preferredScrollController: widget.preferredScrollController,
          blockedMessage: blockedMessage,
          fields: fields,
          errors: _errors,
          answers: _answers,
          resetTick: _resetTick,
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
              child: ExcludeFocus(
                excluding: true,
                child: FilledButton(
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
                                ? 'Booking has been cancelled.'
                                : 'Booking has been updated.',
                          );
                        },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 52),
                    backgroundColor: widget.isDanger
                        ? const Color(0xFFC93B3B)
                        : AppColors.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(_isSubmitting ? 'Saving...' : actionLabel),
                ),
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

class _WorkflowTaskCard extends StatelessWidget {
  const _WorkflowTaskCard({
    required this.vm,
    required this.title,
    required this.preferredScrollController,
    required this.blockedMessage,
    required this.fields,
    required this.errors,
    required this.answers,
    required this.resetTick,
    required this.onChanged,
    this.allowAdditionalFields = true,
  });

  final BookingWorkflowViewModel vm;
  final String title;
  final ScrollController? preferredScrollController;
  final String? blockedMessage;
  final List<StatusField> fields;
  final Map<String, String> errors;
  final Map<String, dynamic> answers;
  final int resetTick;
  final void Function(String fieldKey, dynamic value) onChanged;
  final bool allowAdditionalFields;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (blockedMessage?.trim().isNotEmpty == true) ...[
          Text(
            blockedMessage!,
            style: const TextStyle(
              color: Color(0xFFC93B3B),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
        ],
        ...fields.asMap().entries.map((entry) {
          final field = entry.value;
          final isLastField = entry.key == fields.length - 1;
          return Padding(
            padding: EdgeInsets.only(bottom: isLastField ? 0 : 14),
            child: _WorkflowFieldCard(
              key: ValueKey('${field.key}:$resetTick'),
              vm: vm,
              preferredScrollController: preferredScrollController,
              field: field,
              initialValue: answers[field.key],
              errorText: errors[field.key],
              onEdit: vm.supportsAdditionalFields
                  ? () => _openFieldEditor(context, vm, initialField: field)
                  : null,
              onChanged: (value) {
                final key = field.key;
                if (key == null || key.isEmpty) {
                  return;
                }
                onChanged(key, value);
              },
            ),
          );
        }),
        if (vm.supportsAdditionalFields && allowAdditionalFields) ...[
          SizedBox(height: vm.fields.isEmpty ? 0 : 16),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Fields',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _WorkflowAddFieldButton(
                availableFields: vm.availableFieldsForSelection,
                onSelected: vm.addExistingField,
                onCreateNew: () => _openFieldEditor(
                  context,
                  vm,
                  initialField: vm.buildNewFieldDraft(),
                  addAfterSave: true,
                ),
              ),
            ],
          ),
          if (vm.additionalFields.isNotEmpty) const SizedBox(height: 16),
          ...vm.additionalFields.asMap().entries.map((entry) {
            final field = entry.value;
            final fieldKey = field.key ?? '';
            final isLast = entry.key == vm.additionalFields.length - 1;
            if (fieldKey.isEmpty) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: _WorkflowRemovableFieldCard(
                preferredScrollController: preferredScrollController,
                field: field,
                errorText: errors[fieldKey],
                initialValue: answers[fieldKey],
                onChanged: (value) => onChanged(fieldKey, value),
                onRemove: () => vm.removeAdditionalField(fieldKey),
                vm: vm,
                onEdit: () =>
                    _openFieldEditor(context, vm, initialField: field),
              ),
            );
          }),
        ],
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
        vm.addExistingField(persistedId);
      }
    }
    if (!context.mounted) {
      return;
    }
    AppSnackbar.showSuccess(
      context,
      '${persistedField.title?.trim().isNotEmpty == true ? persistedField.title!.trim() : persistedField.key ?? 'Field'} field has been updated.',
    );
  }
}

class _WorkflowAlertHeaderCard extends StatelessWidget {
  const _WorkflowAlertHeaderCard({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFC93B3B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFC93B3B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          if (subtitle?.trim().isNotEmpty == true)
            Text(
              subtitle!.trim(),
              style: const TextStyle(
                color: Color(0xFFFFDADA),
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
        ],
      ),
    );
  }
}

class _WorkflowAddFieldButton extends StatelessWidget {
  const _WorkflowAddFieldButton({
    required this.availableFields,
    required this.onSelected,
    required this.onCreateNew,
  });

  final List<StatusField> availableFields;
  final ValueChanged<String> onSelected;
  final VoidCallback onCreateNew;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Add field',
      color: Colors.white,
      surfaceTintColor: Colors.white,
      onSelected: (value) {
        if (value == '__create_new_field__') {
          onCreateNew();
          return;
        }
        onSelected(value);
      },
      itemBuilder: (context) => [
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
        const PopupMenuItem<String>(
          value: '__create_new_field__',
          child: Text(
            'Create New Field',
            style: TextStyle(
              color: AppColors.primaryColor,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ),
      ],
      child: const _WorkflowInlineAddButton(),
    );
  }
}

class _WorkflowInlineAddButton extends StatelessWidget {
  const _WorkflowInlineAddButton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 32,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.primaryColor,
          borderRadius: const BorderRadius.all(Radius.circular(1000)),
        ),
        child: const Center(
          child: Icon(Icons.add_rounded, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}

class _WorkflowRemovableFieldCard extends StatelessWidget {
  const _WorkflowRemovableFieldCard({
    required this.vm,
    required this.preferredScrollController,
    required this.field,
    required this.initialValue,
    required this.onChanged,
    required this.onRemove,
    required this.onEdit,
    this.errorText,
  });

  final BookingWorkflowViewModel vm;
  final ScrollController? preferredScrollController;
  final StatusField field;
  final dynamic initialValue;
  final ValueChanged<dynamic> onChanged;
  final VoidCallback onRemove;
  final VoidCallback onEdit;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return _WorkflowFieldCard(
      vm: vm,
      preferredScrollController: preferredScrollController,
      field: field,
      initialValue: initialValue,
      errorText: errorText,
      headerTrailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_rounded, size: 18),
            color: AppColors.primaryColor,
            splashRadius: 20,
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded, size: 18),
            color: const Color(0xFFC93B3B),
            splashRadius: 20,
          ),
        ],
      ),
      onChanged: onChanged,
    );
  }
}

class _WorkflowFieldCard extends StatelessWidget {
  const _WorkflowFieldCard({
    super.key,
    required this.vm,
    required this.preferredScrollController,
    required this.field,
    required this.initialValue,
    required this.onChanged,
    this.headerTrailing,
    this.onEdit,
    this.errorText,
  });

  final BookingWorkflowViewModel vm;
  final ScrollController? preferredScrollController;
  final StatusField field;
  final dynamic initialValue;
  final ValueChanged<dynamic> onChanged;
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
    final usesDropdownCard = type == 'dropdown' || usesRoleDropdown;

    return BookingFormFieldCard(
      title: effectiveTitle,
      required: field.required ?? false,
      subtitle: subtitle,
      instructions: instructions,
      containerPadding: usesDropdownCard
          ? const EdgeInsets.fromLTRB(18, 18, 18, 4)
          : const EdgeInsets.all(18),
      headerTrailing:
          headerTrailing ??
          (onEdit == null
              ? null
              : TextButton.icon(
                  onPressed: onEdit,
                  style: TextButton.styleFrom(
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
        placeholder: placeholder,
        errorText: errorText,
      ),
    );
  }

  Widget _buildFieldInput(
    BuildContext context, {
    required String? placeholder,
    required String? errorText,
  }) {
    final type = (field.type ?? 'text').trim().toLowerCase();
    final fieldKey = (field.key ?? '').trim().toLowerCase();
    final optionSourceKey = StatusFieldOptionResolver.resolvedOptionSourceKey(
      field,
    );

    if (fieldKey == 'driver_id' ||
        optionSourceKey == statusFieldOptionSourceDrivers) {
      return _roleUserDropdown(
        role: 'driver',
        placeholder: placeholder,
        errorText: errorText,
      );
    }
    if (fieldKey == 'helper_id' ||
        optionSourceKey == statusFieldOptionSourceHelpers) {
      return _roleUserDropdown(
        role: 'helper',
        placeholder: placeholder,
        errorText: errorText,
      );
    }

    switch (type) {
      case 'number':
        return _UnderlineTextField(
          preferredScrollController: preferredScrollController,
          initialValue: initialValue?.toString(),
          keyboardType: TextInputType.number,
          hintText: placeholder,
          errorText: errorText,
          onChanged: (value) => onChanged(value.trim()),
        );
      case 'email':
        return _UnderlineTextField(
          preferredScrollController: preferredScrollController,
          initialValue: initialValue?.toString(),
          keyboardType: TextInputType.emailAddress,
          hintText: placeholder,
          errorText: errorText,
          onChanged: (value) => onChanged(value.trim()),
        );
      case 'phone':
        return _UnderlineTextField(
          preferredScrollController: preferredScrollController,
          initialValue: initialValue?.toString(),
          keyboardType: TextInputType.phone,
          inputFormatters: const [PhilippinesPhoneInputFormatter()],
          hintText: placeholder,
          errorText: errorText,
          onChanged: (value) => onChanged(value.trim()),
        );
      case 'text':
        return _UnderlineTextField(
          preferredScrollController: preferredScrollController,
          initialValue: initialValue?.toString(),
          hintText: placeholder,
          errorText: errorText,
          onChanged: (value) => onChanged(value.trim()),
        );
      case 'dropdown':
        return AdminDropdownFormField<String>(
          initialValue: initialValue?.toString(),
          iconEnabledColor: AppColors.primaryColor,
          decoration: _bookingDropdownDecoration(
            placeholder?.trim().isNotEmpty == true
                ? placeholder!
                : (field.required ?? false)
                ? 'Choose an option'
                : 'Optional',
          ).copyWith(errorText: errorText),
          style: adminDropdownDisplayTextStyle,
          items: field.options
              .map(
                (item) => DropdownMenuItem<String>(
                  value: item,
                  child: Text(item, style: adminDropdownDisplayTextStyle),
                ),
              )
              .toList(),
          onChanged: (value) => onChanged(value),
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
          label: initialValue?.toString() ?? (placeholder ?? 'Select Date'),
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
          label: initialValue?.toString() ?? (placeholder ?? 'Select Time'),
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
          initialValue: initialValue,
          errorText: errorText,
          onChanged: onChanged,
        );
      default:
        return _UnderlineTextField(
          preferredScrollController: preferredScrollController,
          initialValue: initialValue?.toString(),
          hintText: placeholder,
          errorText: errorText,
          onChanged: (value) => onChanged(value.trim()),
        );
    }
  }

  Widget _roleUserDropdown({
    required String role,
    required String? placeholder,
    required String? errorText,
  }) {
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
      iconEnabledColor: AppColors.primaryColor,
      decoration: _bookingDropdownDecoration(
        placeholder?.trim().isNotEmpty == true
            ? placeholder!.trim()
            : 'Select ${role == 'driver' ? 'Driver' : 'Helper'}',
      ).copyWith(errorText: errorText),
      style: adminDropdownDisplayTextStyle,
      items: items,
      onChanged: (value) => onChanged(value),
    );
  }

  InputDecoration _bookingDropdownDecoration(String hintText) {
    return adminPlainDropdownDecoration(hintText, radius: 16).copyWith(
      constraints: const BoxConstraints(minHeight: 60),
      contentPadding: const EdgeInsets.fromLTRB(14, 18, 14, 12),
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
    if (fieldType == 'dropdown' && !usesDynamicSource && options.isEmpty) {
      return 'Add at least one static choice or pick a choices source.';
    }
    if (fieldType == 'checkbox' && options.isEmpty) {
      return 'Add at least one choice.';
    }
    return null;
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
        FilledButton(
          onPressed: () {
            final validationMessage = _validationMessage();
            if (validationMessage != null) {
              AppSnackbar.showError(context, validationMessage);
              return;
            }
            Navigator.of(context).pop(_normalizeFieldPlaceholder(_field));
          },
          child: const Text('Save'),
        ),
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
    this.preferredScrollController,
    this.initialValue,
    this.keyboardType,
    this.hintText,
    this.errorText,
    this.inputFormatters,
  });

  final String? initialValue;
  final ScrollController? preferredScrollController;
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
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.inputFormatters,
      scrollPadding: EdgeInsets.zero,
      onTapOutside: _unfocusWithoutScroll,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        hintText: widget.hintText,
        isDense: true,
        hintStyle: TextStyle(
          color: AppColors.primaryColor.withValues(alpha: 0.72),
          fontWeight: FontWeight.w500,
        ),
        contentPadding: const EdgeInsets.only(top: 14, bottom: 10),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.primaryBorder),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.primaryColor, width: 2),
        ),
        errorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.red),
        ),
        focusedErrorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.red, width: 2),
        ),
        errorText: widget.errorText,
      ),
    );
  }
}

class _SelectButton extends StatelessWidget {
  const _SelectButton({
    required this.label,
    required this.isPlaceholder,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final bool isPlaceholder;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: TextStyle(
          color: isPlaceholder
              ? AppColors.primaryColor.withValues(alpha: 0.72)
              : AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
        alignment: Alignment.centerLeft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: const BorderSide(color: AppColors.primaryBorder),
      ),
    );
  }
}

class _PhotoField extends StatefulWidget {
  const _PhotoField({
    required this.initialValue,
    required this.onChanged,
    this.errorText,
  });

  final dynamic initialValue;
  final ValueChanged<dynamic> onChanged;
  final String? errorText;

  @override
  State<_PhotoField> createState() => _PhotoFieldState();
}

class _PhotoFieldState extends State<_PhotoField> {
  @override
  Widget build(BuildContext context) {
    return BookingPhotoFieldInput(
      initialValue: widget.initialValue,
      previewBytesBuilder: (value) => decodePhotoBytes(value, key: 'bytes'),
      valueBuilder: (file, encodedBytes) => {
        'name': file.name,
        'bytes': encodedBytes,
        'mime_type': file.extension == null ? null : 'image/${file.extension}',
      },
      errorText: widget.errorText,
      onChanged: widget.onChanged,
    );
  }
}
