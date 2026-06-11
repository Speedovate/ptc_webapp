import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/status_form.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/view_models/client/client_booking_home.vm.dart';
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
        titleColor: Colors.white,
        subtitleColor: Color(0xFFE4F6EA),
      );
    case 'cancelled':
      return const _ClientFormHeaderPalette(
        backgroundColor: Color(0xFFC93B3B),
        borderColor: Color(0xFFC93B3B),
        titleColor: Colors.white,
        subtitleColor: Color(0xFFFFE0E0),
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
    this.bookingClientUser,
    this.submittedByUserId,
    this.padding = const EdgeInsets.fromLTRB(24, 24, 24, 24),
    this.scrollable = true,
  });

  final UserModel user;
  final ValueChanged<Booking>? onBookingSubmitted;
  final UserModel? bookingClientUser;
  final String? submittedByUserId;
  final EdgeInsets padding;
  final bool scrollable;

  @override
  State<ClientBookingHomeView> createState() => _ClientBookingHomeViewState();
}

class _ClientBookingHomeViewState extends State<ClientBookingHomeView> {
  ClientBookingHomeViewModel? _viewModel;

  UserModel get _effectiveClientUser => widget.bookingClientUser ?? widget.user;

  String get _effectiveSubmittedByUserId =>
      widget.submittedByUserId ?? widget.user.id ?? '';

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
                ? 'Submitting booking...'
                : 'Loading booking form...',
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
                ? 'Submitting booking...'
                : 'Loading booking form...',
            child: _ClientBookingStateCard(
              scrollable: widget.scrollable,
              padding: widget.padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppRefreshStrip(isVisible: vm.isBusyLoading),
                  Text(
                    vm.isBusyLoading
                        ? 'Preparing booking form...'
                        : 'No client booking form available yet.',
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
                  key: ValueKey('${activeForm.id}:${_effectiveClientUser.id}'),
                  vm: vm,
                  form: activeForm,
                  clientUser: _effectiveClientUser,
                  submittedByUserId: _effectiveSubmittedByUserId,
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
              ? 'Submitting booking...'
              : 'Loading booking form...',
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
    required this.onUnfocusWithoutScroll,
    this.onBookingSubmitted,
  });

  final ClientBookingHomeViewModel vm;
  final StatusForm form;
  final UserModel clientUser;
  final String submittedByUserId;
  final VoidCallback onUnfocusWithoutScroll;
  final ValueChanged<Booking>? onBookingSubmitted;

  @override
  State<_ClientBookingFormSection> createState() =>
      _ClientBookingFormSectionState();
}

class _ClientBookingFormSectionState extends State<_ClientBookingFormSection> {
  Map<String, dynamic> _answers = {};
  Map<String, String> _errors = {};
  int _resetTick = 0;
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final form = widget.form;
    final fields = vm.fieldsForForm(form);
    final blockedMessage = vm.blockedMessageForForm(form, widget.clientUser);
    final terminalPalette = form.nextStatusKey == null
        ? _terminalClientHeaderPalette(form.currentStatusKey)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BookingFormHeaderCard(
          title: vm.resolvedTitleForForm(form),
          subtitle: vm.resolvedSubtitleForForm(form),
          backgroundColor: terminalPalette?.backgroundColor,
          borderColor: terminalPalette?.borderColor,
          titleColor: terminalPalette?.titleColor,
          subtitleColor: terminalPalette?.subtitleColor,
          showRequiredLegend: fields.any((field) => field.required == true),
          message: blockedMessage,
          messageBackgroundColor: const Color(0xFFFFF6F6),
          messageBorderColor: const Color(0xFFFFD2D2),
          messageIcon: Icons.block_rounded,
          messageIconColor: const Color(0xFFC93B3B),
          messageTextColor: AppColors.textPrimary,
        ),
        const SizedBox(height: 14),
        ...fields.map(
          (field) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: StatusFormRuntimeFieldCard(
              key: ValueKey('${form.id}:${field.key}:$_resetTick'),
              field: field,
              errorText: _errors[field.key],
              initialValue: _answers[field.key],
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
          ),
        ),
        const SizedBox(height: 2),
        _ClientBookingActions(
          isSubmitting: _isSubmitting,
          isBlocked: blockedMessage != null,
          submitLabel: _isSubmitting
              ? 'Submitting...'
              : vm.submitLabelForForm(form),
          onSubmit: () async {
            final validationErrors = vm.validateAnswersForForm(form, _answers);
            if (validationErrors.isNotEmpty || blockedMessage != null) {
              setState(() {
                _errors = validationErrors;
              });
              if (validationErrors.isNotEmpty) {
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
              }
              return;
            }
            setState(() {
              _answers = {};
              _errors = {};
              _resetTick += 1;
            });
            if (!mounted) {
              return;
            }
            if (!context.mounted) {
              return;
            }
            AppSnackbar.showSuccess(context, 'Booking has been created.');
            widget.onBookingSubmitted?.call(booking);
          },
          onClear: () {
            widget.onUnfocusWithoutScroll();
            setState(() {
              _answers = {};
              _errors = {};
              _resetTick += 1;
            });
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
    required this.submitLabel,
    required this.onSubmit,
    required this.onClear,
  });

  final bool isSubmitting;
  final bool isBlocked;
  final String submitLabel;
  final Future<void> Function() onSubmit;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final submitButton = FilledButton(
      onPressed: isSubmitting || isBlocked ? null : onSubmit,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(submitLabel),
    );

    final clearButton = TextButton(
      onPressed: isSubmitting ? null : onClear,
      child: const Text('Clear Form'),
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
