import 'package:stacked/stacked.dart';
import 'package:flutter/material.dart';
import 'package:webapp/models/status_form.dart';
import 'package:webapp/utils/functions.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/views/admin/admin_users.dart';
import 'package:webapp/models/status.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';
import 'package:webapp/widgets/shared/app_snackbar.dart';
import 'package:webapp/widgets/shared/admin_action_confirmation.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/app_mouse_pressable.dart';
import 'package:webapp/widgets/shared/admin_modal_form_primitives.dart';
import 'package:webapp/widgets/shared/app_page_loading_overlay.dart';
import 'package:webapp/widgets/shared/app_refresh_strip.dart';
import 'package:webapp/view_models/admin/admin_flow.vm.dart';
import 'package:webapp/widgets/status_form/status_form_preview.dart';

String _formatFormsFilterDateValue(DateTime? value) {
  if (value == null) {
    return '';
  }
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[value.month - 1]} ${value.day}, ${value.year}';
}

class AdminFormsView extends StatelessWidget {
  const AdminFormsView({super.key});

  static const toolbarSectionGap = 12.0;
  static const tableSectionGap = 14.0;
  static const controlHeight = 52.0;
  static const surfaceRadius = 16.0;

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<AdminFlowViewModel>.reactive(
      viewModelBuilder: AdminFlowViewModel.new,
      onViewModelReady: (vm) => vm.loadFormsPage(),
      builder: (context, vm, _) {
        return AppPageLoadingOverlay(
          isVisible: vm.showBlockingLoading,
          message: vm.busyMessage,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppRefreshStrip(isVisible: vm.showBlockingLoading),
                _StatusFormsListSection(vm: vm),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatusFormsListSection extends StatefulWidget {
  const _StatusFormsListSection({required this.vm});

  final AdminFlowViewModel vm;

  @override
  State<_StatusFormsListSection> createState() =>
      _StatusFormsListSectionState();
}

class _StatusFormsListSectionState extends State<_StatusFormsListSection> {
  String _searchQuery = '';
  String _roleFilter = 'All';
  String _activeFilter = 'All';
  DateTime? _createdStartDate;
  DateTime? _createdEndDate;
  DateTime? _updatedStartDate;
  DateTime? _updatedEndDate;
  bool _isSubmittingFormDialog = false;

  String _formSaveMessage({required bool isEditing}) {
    return isEditing ? 'Form updated.' : 'Form added.';
  }

  String _formEditMessage() {
    return _formSaveMessage(isEditing: true);
  }

  String get _emptyMessage {
    final hasAnyData = widget.vm.forms.isNotEmpty;
    if (!hasAnyData) {
      return 'No forms yet.';
    }

    final hasSearch = _searchQuery.trim().isNotEmpty;
    final activeFilterCount = [
      _roleFilter != 'All',
      _activeFilter != 'All',
      _createdStartDate != null,
      _createdEndDate != null,
      _updatedStartDate != null,
      _updatedEndDate != null,
    ].where((isActive) => isActive).length;

    return AdminUsersView.buildEmptyStateMessage(
      noun: 'forms',
      hasSearch: hasSearch,
      activeFilterCount: activeFilterCount,
    );
  }

  List<StatusForm> get _displayForms {
    return [...widget.vm.forms];
  }

  List<StatusForm> get _filteredForms {
    return _displayForms.where((form) {
      final activeText = (form.isActive ?? false) ? 'Active' : 'Inactive';
      final searchHaystack = [
        form.resolvedRoles.join(' '),
        form.currentStatusKey ?? '',
        _resolvedFormStatusLabel(widget.vm, form),
        _resolvedFormStatusDescription(widget.vm, form),
        form.buttonText ?? '',
        form.nextStatusKey ?? '',
      ].join(' ').toLowerCase();

      final matchesSearch =
          _searchQuery.trim().isEmpty ||
          searchHaystack.contains(_searchQuery.trim().toLowerCase());
      final matchesRole =
          _roleFilter == 'All' ||
          form.resolvedRoles.any((role) => _titleCase(role) == _roleFilter);
      final matchesActive =
          _activeFilter == 'All' || activeText == _activeFilter;
      final matchesCreatedStart =
          _createdStartDate == null ||
          (form.createdAt != null &&
              !DateUtils.dateOnly(form.createdAt!).isBefore(
                DateUtils.dateOnly(_createdStartDate!),
              ));
      final matchesCreatedEnd =
          _createdEndDate == null ||
          (form.createdAt != null &&
              !DateUtils.dateOnly(form.createdAt!).isAfter(
                DateUtils.dateOnly(_createdEndDate!),
              ));
      final matchesUpdatedStart =
          _updatedStartDate == null ||
          (form.updatedAt != null &&
              !DateUtils.dateOnly(form.updatedAt!).isBefore(
                DateUtils.dateOnly(_updatedStartDate!),
              ));
      final matchesUpdatedEnd =
          _updatedEndDate == null ||
          (form.updatedAt != null &&
              !DateUtils.dateOnly(form.updatedAt!).isAfter(
                DateUtils.dateOnly(_updatedEndDate!),
              ));

      return matchesSearch &&
          matchesRole &&
          matchesActive &&
          matchesCreatedStart &&
          matchesCreatedEnd &&
          matchesUpdatedStart &&
          matchesUpdatedEnd;
    }).toList();
  }

  void _updateCreatedStartDate(DateTime? value) {
    setState(() {
      _createdStartDate = value;
      if (_createdStartDate != null &&
          _createdEndDate != null &&
          _createdEndDate!.isBefore(_createdStartDate!)) {
        _createdEndDate = _createdStartDate;
      }
    });
  }

  void _updateCreatedEndDate(DateTime? value) {
    setState(() {
      _createdEndDate = value;
      if (_createdStartDate != null &&
          _createdEndDate != null &&
          _createdStartDate!.isAfter(_createdEndDate!)) {
        _createdStartDate = _createdEndDate;
      }
    });
  }

  void _updateUpdatedStartDate(DateTime? value) {
    setState(() {
      _updatedStartDate = value;
      if (_updatedStartDate != null &&
          _updatedEndDate != null &&
          _updatedEndDate!.isBefore(_updatedStartDate!)) {
        _updatedEndDate = _updatedStartDate;
      }
    });
  }

  void _updateUpdatedEndDate(DateTime? value) {
    setState(() {
      _updatedEndDate = value;
      if (_updatedStartDate != null &&
          _updatedEndDate != null &&
          _updatedStartDate!.isAfter(_updatedEndDate!)) {
        _updatedStartDate = _updatedEndDate;
      }
    });
  }

  Future<void> _openNewFormDialog() async {
    if (!widget.vm.canCreateForms) {
      return;
    }
    widget.vm.ensureNewFormDraft();
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AnimatedBuilder(
          animation: widget.vm,
          builder: (context, _) {
            final form = widget.vm.selectedForm;
            if (form == null) {
              return const SizedBox.shrink();
            }

            return AdminModalShell(
              title: 'New Form',
              contentInset: const EdgeInsets.fromLTRB(0, 16, 0, 16),
              actionsInset: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: _isSubmittingFormDialog
                      ? null
                      : () async {
                          setState(() {
                            _isSubmittingFormDialog = true;
                          });
                          try {
                            await widget.vm.saveForm();
                            final errorMessage = widget.vm.errorMessage;
                            if (!dialogContext.mounted) {
                              return;
                            }
                            if (errorMessage == null) {
                              AppSnackbar.showSuccess(
                                dialogContext,
                                _formSaveMessage(isEditing: false),
                              );
                              widget.vm.clearSelection();
                              Navigator.of(dialogContext).pop();
                            } else {
                              AppSnackbar.showError(
                                dialogContext,
                                errorMessage,
                              );
                            }
                          } finally {
                            if (mounted) {
                              setState(() {
                                _isSubmittingFormDialog = false;
                              });
                            }
                          }
                        },
                  child: _isSubmittingFormDialog
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text('Save'),
                ),
              ],
              child: _InlineEditorContent(
                vm: widget.vm,
                form: form,
                onClose: () {
                  Navigator.of(dialogContext).pop();
                },
              ),
            );
          },
        );
      },
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _openEditFormDialog(StatusForm form) async {
    if (!widget.vm.canUpdateForms) {
      return;
    }
    widget.vm.selectForm(form, notify: false);
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AnimatedBuilder(
          animation: widget.vm,
          builder: (context, _) {
            final selected = widget.vm.selectedForm;
            if (selected == null) {
              return const SizedBox.shrink();
            }

            return AdminModalShell(
              title: 'Edit Form',
              contentInset: const EdgeInsets.fromLTRB(0, 16, 0, 16),
              actionsInset: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              actions: [
                TextButton(
                  onPressed: () {
                    widget.vm.clearSelection();
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: _isSubmittingFormDialog
                      ? null
                      : () async {
                          setState(() {
                            _isSubmittingFormDialog = true;
                          });
                          try {
                            await widget.vm.saveForm();
                            final errorMessage = widget.vm.errorMessage;
                            if (!dialogContext.mounted) {
                              return;
                            }
                            if (errorMessage == null) {
                              AppSnackbar.showSuccess(
                                dialogContext,
                                _formEditMessage(),
                              );
                              widget.vm.clearSelection();
                              Navigator.of(dialogContext).pop();
                            } else {
                              AppSnackbar.showError(
                                dialogContext,
                                errorMessage,
                              );
                            }
                          } finally {
                            if (mounted) {
                              setState(() {
                                _isSubmittingFormDialog = false;
                              });
                            }
                          }
                        },
                  child: _isSubmittingFormDialog
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text('Save'),
                ),
              ],
              child: Builder(
                builder: (context) {
                  return _InlineEditorContent(
                    vm: widget.vm,
                    form: selected,
                    onClose: () {
                      widget.vm.clearSelection();
                      Navigator.of(dialogContext).pop();
                    },
                  );
                },
              ),
            );
          },
        );
      },
    );

    if (mounted) {
      widget.vm.clearSelection();
      setState(() {});
    }
  }

  Future<void> _openPreviewFormDialog(StatusForm form) async {
    widget.vm.selectForm(form, notify: false);
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AnimatedBuilder(
          animation: widget.vm,
          builder: (context, _) {
            final selected = widget.vm.selectedForm;
            if (selected == null) {
              return const SizedBox.shrink();
            }

            return AdminModalShell(
              title: 'Form Preview',
              actions: [
                TextButton(
                  onPressed: () {
                    widget.vm.clearSelection();
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Close'),
                ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: StatusFormPreview(
                  form: selected,
                  fields: widget.vm.fields,
                  titleText: _resolvedFormStatusLabel(widget.vm, selected),
                  subtitleText: _resolvedFormStatusDescription(
                    widget.vm,
                    selected,
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (mounted) {
      widget.vm.clearSelection();
      setState(() {});
    }
  }

  Future<void> _confirmDeactivateForm(StatusForm form) async {
    final confirmed = await showAdminActionConfirmation(
      context,
      title: 'Deactivate Form ${form.id ?? '-'}',
      message: 'Are you sure you want to deactivate this form?',
      confirmLabel: 'Deactivate',
      onConfirmAsync: () async {
        try {
          await widget.vm.deactivateForm(form);
          if (!mounted) {
            return false;
          }
          AppSnackbar.showSuccess(context, 'Form deactivated.');
          return true;
        } catch (error) {
          if (!mounted) {
            return false;
          }
          AppSnackbar.showError(context, error.toString());
          return false;
        }
      },
    );
    if (!confirmed || !mounted) {
      return;
    }
  }

  Future<void> _confirmDeleteForm(StatusForm form) async {
    if (!widget.vm.canDeleteForms) {
      return;
    }
    final confirmed = await showAdminActionConfirmation(
      context,
      title: 'Delete Form ${form.id ?? '-'}',
      message: 'Are you sure you want to delete this form?',
      confirmLabel: 'Delete',
      isDanger: true,
      onConfirmAsync: () async {
        try {
          await widget.vm.deleteForm(form);
          if (!mounted) {
            return false;
          }
          AppSnackbar.showSuccess(context, 'Form deleted.');
          return true;
        } catch (error) {
          if (!mounted) {
            return false;
          }
          AppSnackbar.showError(context, error.toString());
          return false;
        }
      },
    );
    if (!confirmed || !mounted) {
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 940;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatusFormsToolbar(
              searchQuery: _searchQuery,
              roleFilter: _roleFilter,
              activeFilter: _activeFilter,
              createdStartDate: _createdStartDate,
              createdEndDate: _createdEndDate,
              updatedStartDate: _updatedStartDate,
              updatedEndDate: _updatedEndDate,
              onSearchChanged: (value) => setState(() => _searchQuery = value),
              onRoleChanged: (value) => setState(() => _roleFilter = value),
              onActiveChanged: (value) => setState(() => _activeFilter = value),
              onCreatedStartDateChanged: _updateCreatedStartDate,
              onCreatedEndDateChanged: _updateCreatedEndDate,
              onUpdatedStartDateChanged: _updateUpdatedStartDate,
              onUpdatedEndDateChanged: _updateUpdatedEndDate,
              onNewPressed: widget.vm.canCreateForms
                  ? _openNewFormDialog
                  : null,
            ),
            const SizedBox(height: AdminFormsView.toolbarSectionGap),
            ListenableBuilder(
              listenable: widget.vm,
              builder: (context, _) {
                if (isNarrow) {
                  if (_filteredForms.isEmpty) {
                    return _StatusFormsEmptyState(message: _emptyMessage);
                  }

                  return Column(
                    children: _filteredForms
                        .asMap()
                        .entries
                        .map(
                          (entry) => Padding(
                            padding: EdgeInsets.only(
                              bottom: entry.key == _filteredForms.length - 1
                                  ? 0
                                  : 12,
                            ),
                            child: RepaintBoundary(
                              child: _StatusFormResponsiveCard(
                                form: entry.value,
                                vm: widget.vm,
                                onViewPressed: () =>
                                    _openPreviewFormDialog(entry.value),
                                onEditPressed: widget.vm.canUpdateForms
                                    ? () => _openEditFormDialog(entry.value)
                                    : null,
                                onDeactivatePressed: widget.vm.canUpdateForms
                                    ? () => _confirmDeactivateForm(entry.value)
                                    : null,
                                onDeletePressed: widget.vm.canDeleteForms
                                    ? () => _confirmDeleteForm(entry.value)
                                    : null,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  );
                }

                return RepaintBoundary(
                  child: _StatusFormsTable(
                    forms: _filteredForms,
                    emptyMessage: _emptyMessage,
                    vm: widget.vm,
                    onViewPressed: _openPreviewFormDialog,
                    onEditPressed: widget.vm.canUpdateForms
                        ? _openEditFormDialog
                        : null,
                    onDeactivatePressed: widget.vm.canUpdateForms
                        ? _confirmDeactivateForm
                        : null,
                    onDeletePressed: widget.vm.canDeleteForms
                        ? _confirmDeleteForm
                        : null,
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _StatusFormsToolbar extends StatelessWidget {
  const _StatusFormsToolbar({
    required this.searchQuery,
    required this.roleFilter,
    required this.activeFilter,
    required this.createdStartDate,
    required this.createdEndDate,
    required this.updatedStartDate,
    required this.updatedEndDate,
    required this.onSearchChanged,
    required this.onRoleChanged,
    required this.onActiveChanged,
    required this.onCreatedStartDateChanged,
    required this.onCreatedEndDateChanged,
    required this.onUpdatedStartDateChanged,
    required this.onUpdatedEndDateChanged,
    required this.onNewPressed,
  });

  final String searchQuery;
  final String roleFilter;
  final String activeFilter;
  final DateTime? createdStartDate;
  final DateTime? createdEndDate;
  final DateTime? updatedStartDate;
  final DateTime? updatedEndDate;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onRoleChanged;
  final ValueChanged<String> onActiveChanged;
  final ValueChanged<DateTime?> onCreatedStartDateChanged;
  final ValueChanged<DateTime?> onCreatedEndDateChanged;
  final ValueChanged<DateTime?> onUpdatedStartDateChanged;
  final ValueChanged<DateTime?> onUpdatedEndDateChanged;
  final VoidCallback? onNewPressed;

  @override
  Widget build(BuildContext context) {
    return AdminListToolbar(
      controlHeight: AdminFormsView.controlHeight,
      surfaceRadius: AdminFormsView.surfaceRadius,
      search: _StatusFormsSearchField(
        initialValue: searchQuery,
        onChanged: onSearchChanged,
      ),
      filtersBuilder: (context, iconOnly) => _StatusFormsFiltersPanel(
        roleFilter: roleFilter,
        activeFilter: activeFilter,
        createdStartDate: createdStartDate,
        createdEndDate: createdEndDate,
        updatedStartDate: updatedStartDate,
        updatedEndDate: updatedEndDate,
        iconOnly: iconOnly,
        onRoleChanged: onRoleChanged,
        onActiveChanged: onActiveChanged,
        onCreatedStartDateChanged: onCreatedStartDateChanged,
        onCreatedEndDateChanged: onCreatedEndDateChanged,
        onUpdatedStartDateChanged: onUpdatedStartDateChanged,
        onUpdatedEndDateChanged: onUpdatedEndDateChanged,
      ),
      onNewPressed: onNewPressed,
    );
  }
}

class _StatusFormsSearchField extends StatefulWidget {
  const _StatusFormsSearchField({
    required this.initialValue,
    required this.onChanged,
  });

  final String initialValue;
  final ValueChanged<String> onChanged;

  @override
  State<_StatusFormsSearchField> createState() =>
      _StatusFormsSearchFieldState();
}

class _StatusFormsSearchFieldState extends State<_StatusFormsSearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void didUpdateWidget(covariant _StatusFormsSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.initialValue,
        selection: TextSelection.collapsed(offset: widget.initialValue.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdminListSearchField(
      controlHeight: AdminFormsView.controlHeight,
      surfaceRadius: AdminFormsView.surfaceRadius,
      initialValue: widget.initialValue,
      onChanged: widget.onChanged,
    );
  }
}

class _StatusFormsFiltersPanel extends StatefulWidget {
  const _StatusFormsFiltersPanel({
    required this.roleFilter,
    required this.activeFilter,
    required this.createdStartDate,
    required this.createdEndDate,
    required this.updatedStartDate,
    required this.updatedEndDate,
    required this.iconOnly,
    required this.onRoleChanged,
    required this.onActiveChanged,
    required this.onCreatedStartDateChanged,
    required this.onCreatedEndDateChanged,
    required this.onUpdatedStartDateChanged,
    required this.onUpdatedEndDateChanged,
  });

  final String roleFilter;
  final String activeFilter;
  final DateTime? createdStartDate;
  final DateTime? createdEndDate;
  final DateTime? updatedStartDate;
  final DateTime? updatedEndDate;
  final bool iconOnly;
  final ValueChanged<String> onRoleChanged;
  final ValueChanged<String> onActiveChanged;
  final ValueChanged<DateTime?> onCreatedStartDateChanged;
  final ValueChanged<DateTime?> onCreatedEndDateChanged;
  final ValueChanged<DateTime?> onUpdatedStartDateChanged;
  final ValueChanged<DateTime?> onUpdatedEndDateChanged;

  @override
  State<_StatusFormsFiltersPanel> createState() =>
      _StatusFormsFiltersPanelState();
}

class _StatusFormsFiltersPanelState extends State<_StatusFormsFiltersPanel> {
  final FocusNode _roleFocusNode = FocusNode();
  final FocusNode _activeFocusNode = FocusNode();

  void _unfocusFilterFields() {
    _roleFocusNode.unfocus();
    _activeFocusNode.unfocus();
    FocusScope.of(context).unfocus();
  }

  @override
  void dispose() {
    _roleFocusNode.dispose();
    _activeFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    const overlayRightPadding = 24.0;
    const filterItemWidth = 220.0;
    const overlayPadding = 14.0;
    const desiredOverlayWidth = filterItemWidth + (overlayPadding * 2);
    final overlayWidth = (screenWidth - 32 - overlayRightPadding).clamp(
      1.0,
      desiredOverlayWidth,
    );
    final contentWidth = (overlayWidth - (overlayPadding * 2)).clamp(
      1.0,
      desiredOverlayWidth,
    );
    final itemWidth = contentWidth;

    return AdminListFiltersButton(
      controlHeight: AdminFormsView.controlHeight,
      surfaceRadius: AdminFormsView.surfaceRadius,
      iconOnly: widget.iconOnly,
      menuChildren: [
        SizedBox(
          width: overlayWidth,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _unfocusFilterFields,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: itemWidth,
                    height: AdminFormsView.controlHeight,
                    child: _StatusFormsFilterDropdown(
                      label: 'Roles',
                      value: widget.roleFilter,
                      focusNode: _roleFocusNode,
                      items: const [
                        'All',
                        'Client',
                        'Driver',
                        'Admin',
                        'Helper',
                      ],
                      onChanged: widget.onRoleChanged,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: itemWidth,
                    height: AdminFormsView.controlHeight,
                    child: _StatusFormsFilterDropdown(
                      label: 'Is Active',
                      value: widget.activeFilter,
                      focusNode: _activeFocusNode,
                      items: const ['All', 'Active', 'Inactive'],
                      onChanged: widget.onActiveChanged,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: itemWidth,
                    child: _StatusFormsDateFilter(
                      label: 'Created Start',
                      value: widget.createdStartDate,
                      formatter: _formatFormsFilterDateValue,
                      onSelected: widget.onCreatedStartDateChanged,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: itemWidth,
                    child: _StatusFormsDateFilter(
                      label: 'Created End',
                      value: widget.createdEndDate,
                      formatter: _formatFormsFilterDateValue,
                      onSelected: widget.onCreatedEndDateChanged,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: itemWidth,
                    child: _StatusFormsDateFilter(
                      label: 'Updated Start',
                      value: widget.updatedStartDate,
                      formatter: _formatFormsFilterDateValue,
                      onSelected: widget.onUpdatedStartDateChanged,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: itemWidth,
                    child: _StatusFormsDateFilter(
                      label: 'Updated End',
                      value: widget.updatedEndDate,
                      formatter: _formatFormsFilterDateValue,
                      onSelected: widget.onUpdatedEndDateChanged,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: itemWidth,
                    height: AdminFormsView.controlHeight,
                    child: FilledButton(
                      onPressed: () {
                        _unfocusFilterFields();
                        widget.onRoleChanged('All');
                        widget.onActiveChanged('All');
                        widget.onCreatedStartDateChanged(null);
                        widget.onCreatedEndDateChanged(null);
                        widget.onUpdatedStartDateChanged(null);
                        widget.onUpdatedEndDateChanged(null);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AdminFormsView.surfaceRadius,
                          ),
                        ),
                      ),
                      child: const Text(
                        'Clear',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusFormsFilterDropdown extends StatelessWidget {
  const _StatusFormsFilterDropdown({
    required this.label,
    required this.value,
    required this.focusNode,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String value;
  final FocusNode focusNode;
  final List<String> items;
  final ValueChanged<String> onChanged;

  static const _subtlePrimaryTextStyle = adminDropdownDisplayTextStyle;

  @override
  Widget build(BuildContext context) {
    return AdminDropdownFormField<String>(
      initialValue: value == 'All' ? null : value,
      focusNode: focusNode,
      iconEnabledColor: AppColors.primaryColor,
      style: _subtlePrimaryTextStyle,
      decoration: adminFormInputDecoration(
        label,
        radius: AdminFormsView.surfaceRadius,
        minHeight: AdminFormsView.controlHeight,
      ),
      items: items
          .map(
            (item) => DropdownMenuItem<String>(
              value: item,
              child: Text(
                humanizeDropdownValue(item),
                overflow: TextOverflow.ellipsis,
                style: _subtlePrimaryTextStyle,
              ),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) {
          onChanged(value);
        }
        focusNode.unfocus();
      },
    );
  }
}

class _StatusFormsDateFilter extends StatefulWidget {
  const _StatusFormsDateFilter({
    required this.label,
    required this.value,
    required this.formatter,
    required this.onSelected,
  });

  final String label;
  final DateTime? value;
  final String Function(DateTime?) formatter;
  final ValueChanged<DateTime?> onSelected;

  @override
  State<_StatusFormsDateFilter> createState() => _StatusFormsDateFilterState();
}

class _StatusFormsDateFilterState extends State<_StatusFormsDateFilter> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _displayValue);
    _focusNode = FocusNode()..canRequestFocus = false;
  }

  @override
  void didUpdateWidget(covariant _StatusFormsDateFilter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != _displayValue) {
      _controller.value = _controller.value.copyWith(
        text: _displayValue,
        selection: TextSelection.collapsed(offset: _displayValue.length),
        composing: TextRange.empty,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String get _displayValue =>
      widget.value == null ? '' : widget.formatter(widget.value);

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.value ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (context.mounted) {
      widget.onSelected(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeFillColor = appFieldInteractiveFillColor(context);
    return SizedBox(
      height: AdminFormsView.controlHeight,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() {
          _isHovered = false;
          _isPressed = false;
        }),
        child: Listener(
          onPointerDown: (_) => setState(() => _isPressed = true),
          onPointerUp: (_) => setState(() => _isPressed = false),
          onPointerCancel: (_) => setState(() => _isPressed = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _pickDate,
            child: IgnorePointer(
              child: TextFormField(
                controller: _controller,
                focusNode: _focusNode,
                readOnly: true,
                showCursor: false,
                enableInteractiveSelection: false,
                style: adminDropdownDisplayTextStyle,
                decoration: adminFormInputDecoration(
                  widget.label,
                  radius: AdminFormsView.surfaceRadius,
                  minHeight: AdminFormsView.controlHeight,
                ).copyWith(
                  suffixIcon: IconButton(
                    onPressed: null,
                    icon: Icon(
                      Icons.calendar_today_outlined,
                      size: 18,
                      color: AppColors.primaryColor,
                    ),
                  ),
                  filled: true,
                  fillColor: _isPressed
                      ? activeFillColor.withValues(alpha: 0.92)
                      : (_isHovered ? activeFillColor : Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusFormsTable extends StatelessWidget {
  const _StatusFormsTable({
    required this.forms,
    required this.emptyMessage,
    required this.vm,
    required this.onViewPressed,
    this.onEditPressed,
    this.onDeactivatePressed,
    this.onDeletePressed,
  });

  final List<StatusForm> forms;
  final String emptyMessage;
  final AdminFlowViewModel vm;
  final Future<void> Function(StatusForm form) onViewPressed;
  final Future<void> Function(StatusForm form)? onEditPressed;
  final Future<void> Function(StatusForm form)? onDeactivatePressed;
  final Future<void> Function(StatusForm form)? onDeletePressed;

  static const _headerStyle = TextStyle(
    color: AppColors.textSecondary,
    fontWeight: FontWeight.w700,
  );

  static const _valueStyle = TextStyle(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w600,
  );

  static const _titleStyle = TextStyle(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w700,
  );

  static const _defaultTrailingPadding =
      AdminListMeasurements.defaultTrailingPadding;
  static const _extraWidthAllowance =
      AdminListMeasurements.defaultExtraWidthAllowance;
  static const _minFlexibleRolesWidth = 140.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScaler = MediaQuery.textScalerOf(context);
        final sampleId = forms
            .map((form) => form.id ?? '-')
            .fold<String>('-', _longerText);
        final sampleRole = forms
            .map(_resolvedFormRolesText)
            .fold<String>('-', _longerText);
        final sampleCurrent = forms
            .map((form) => form.currentStatusKey ?? '-')
            .fold<String>('-', _longerText);
        final sampleStatus = forms
            .map((form) {
              final label = _resolvedFormStatusLabel(vm, form);
              return label.isEmpty ? '-' : label;
            })
            .fold<String>('-', _longerText);
        final sampleButton = forms
            .map((form) => form.buttonText ?? '-')
            .fold<String>('-', _longerText);
        final sampleNext = forms
            .map((form) => form.nextStatusKey ?? '-')
            .fold<String>('-', _longerText);
        final idWidth = _maxTextWidth(
          context,
          textScaler,
          'ID',
          _headerStyle,
          sampleId,
          _valueStyle,
        );
        final roleWidth = _maxTextWidth(
          context,
          textScaler,
          'Roles',
          _headerStyle,
          sampleRole,
          _valueStyle,
        );
        final currentWidth = _maxTextWidth(
          context,
          textScaler,
          'Status',
          _headerStyle,
          sampleCurrent,
          _valueStyle,
        );
        final statusWidth = _maxTextWidth(
          context,
          textScaler,
          'Label',
          _headerStyle,
          sampleStatus,
          _titleStyle,
        );
        final buttonWidth = _maxTextWidth(
          context,
          textScaler,
          'Button',
          _headerStyle,
          sampleButton,
          _valueStyle,
        );
        final nextWidth = _maxTextWidth(
          context,
          textScaler,
          'Next',
          _headerStyle,
          sampleNext,
          _valueStyle,
        );
        final sampleCreated = forms
            .map((form) => AdminUsersView.formatCreatedAt(form.createdAt))
            .fold<String>('-', _longerText);
        final sampleUpdated = forms
            .map((form) => AdminUsersView.formatUpdatedAt(form.updatedAt))
            .fold<String>('-', _longerText);
        final createdWidth = _maxTextWidth(
          context,
          textScaler,
          'Created',
          _headerStyle,
          sampleCreated,
          _valueStyle,
        );
        final updatedWidth = _maxTextWidth(
          context,
          textScaler,
          'Updated',
          _headerStyle,
          sampleUpdated,
          _valueStyle,
        );
        final actionsWidth = _maxValue(
          208,
          _measureTextWidth(context, textScaler, 'Actions', _headerStyle),
        );

        final resolvedIdWidth = _resolvedColumnWidth(idWidth);
        final resolvedRoleWidth = _resolvedColumnWidth(roleWidth);
        final resolvedCurrentWidth = _resolvedColumnWidth(currentWidth);
        final resolvedStatusWidth = _resolvedColumnWidth(statusWidth);
        final resolvedButtonWidth = _resolvedColumnWidth(buttonWidth);
        final resolvedNextWidth = _resolvedColumnWidth(nextWidth);
        final resolvedCreatedWidth = _resolvedColumnWidth(createdWidth);
        final resolvedUpdatedWidth = _resolvedColumnWidth(updatedWidth);
        final resolvedActionsWidth = actionsWidth + _extraWidthAllowance;

        final totalMeasuredWidth =
            resolvedIdWidth +
            resolvedRoleWidth +
            resolvedCurrentWidth +
            resolvedStatusWidth +
            resolvedButtonWidth +
            resolvedNextWidth +
            resolvedCreatedWidth +
            resolvedUpdatedWidth +
            resolvedActionsWidth +
            40;

        final fixedWidthWithoutRoles = totalMeasuredWidth - resolvedRoleWidth;
        final shouldFlexRoles =
            fixedWidthWithoutRoles + _minFlexibleRolesWidth <=
            constraints.maxWidth;

        final shouldUseResponsiveCards =
            totalMeasuredWidth >= (constraints.maxWidth - 1) &&
            !shouldFlexRoles;

        if (shouldUseResponsiveCards) {
          if (forms.isEmpty) {
            return _StatusFormsEmptyState(message: emptyMessage);
          }

          return Column(
            children: forms
                .map(
                  (form) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _StatusFormResponsiveCard(
                      form: form,
                      vm: vm,
                      onViewPressed: () => onViewPressed(form),
                      onEditPressed: onEditPressed == null
                          ? null
                          : () => onEditPressed!(form),
                      onDeactivatePressed: onDeactivatePressed == null
                          ? null
                          : () => onDeactivatePressed!(form),
                      onDeletePressed: onDeletePressed == null
                          ? null
                          : () => onDeletePressed!(form),
                    ),
                  ),
                )
                .toList(),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminListHeaderBar(
              minHeight: AdminFormsView.controlHeight,
              borderRadius: AdminFormsView.surfaceRadius,
              child: Row(
                children: [
                  _FixedSlot(
                    width: resolvedIdWidth,
                    child: const _HeaderCell(label: 'ID'),
                  ),
                  if (shouldFlexRoles)
                    const Expanded(child: _HeaderCell(label: 'Roles'))
                  else
                    _FixedSlot(
                      width: resolvedRoleWidth,
                      child: const _HeaderCell(label: 'Roles'),
                    ),
                  _FixedSlot(
                    width: resolvedCurrentWidth,
                    child: const _HeaderCell(label: 'Status'),
                  ),
                  _FixedSlot(
                    width: resolvedStatusWidth,
                    child: const _HeaderCell(label: 'Label'),
                  ),
                  _FixedSlot(
                    width: resolvedButtonWidth,
                    child: const _HeaderCell(label: 'Button'),
                  ),
                  _FixedSlot(
                    width: resolvedNextWidth,
                    child: const _HeaderCell(label: 'Next'),
                  ),
                  _FixedSlot(
                    width: resolvedCreatedWidth,
                    child: const _HeaderCell(label: 'Created'),
                  ),
                  _FixedSlot(
                    width: resolvedUpdatedWidth,
                    child: const _HeaderCell(label: 'Updated'),
                  ),
                  AdminListTrailingActionsLane(
                    width: resolvedActionsWidth,
                    child: const _HeaderCell(
                      label: 'Actions',
                      trailingPadding: 0,
                      alignment: Alignment.centerRight,
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AdminFormsView.tableSectionGap),
            if (forms.isEmpty)
              _StatusFormsEmptyState(message: emptyMessage)
            else
              ...forms.asMap().entries.map(
                (entry) => Padding(
                  padding: EdgeInsets.only(
                    bottom: entry.key == forms.length - 1 ? 0 : 12,
                  ),
                  child: _StatusFormsTableRow(
                    form: entry.value,
                    vm: vm,
                    onViewPressed: () => onViewPressed(entry.value),
                    onEditPressed: onEditPressed == null
                        ? null
                        : () => onEditPressed!(entry.value),
                    onDeactivatePressed: onDeactivatePressed == null
                        ? null
                        : () => onDeactivatePressed!(entry.value),
                    onDeletePressed: onDeletePressed == null
                        ? null
                        : () => onDeletePressed!(entry.value),
                    shouldFlexRoles: shouldFlexRoles,
                    resolvedIdWidth: resolvedIdWidth,
                    resolvedRoleWidth: resolvedRoleWidth,
                    resolvedCurrentWidth: resolvedCurrentWidth,
                    resolvedStatusWidth: resolvedStatusWidth,
                    resolvedButtonWidth: resolvedButtonWidth,
                    resolvedNextWidth: resolvedNextWidth,
                    resolvedCreatedWidth: resolvedCreatedWidth,
                    resolvedUpdatedWidth: resolvedUpdatedWidth,
                    resolvedActionsWidth: resolvedActionsWidth,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  static double _resolvedColumnWidth(double measuredWidth) {
    return AdminListMeasurements.resolvedColumnWidth(
      measuredWidth,
      trailingPadding: _defaultTrailingPadding,
      extraWidthAllowance: _extraWidthAllowance,
    );
  }

  static double _maxTextWidth(
    BuildContext context,
    TextScaler textScaler,
    String headerText,
    TextStyle headerStyle,
    String valueText,
    TextStyle valueStyle,
  ) {
    return AdminListMeasurements.maxTextWidth(
      context,
      textScaler,
      headerText,
      headerStyle,
      valueText,
      valueStyle,
    );
  }

  static double _measureTextWidth(
    BuildContext context,
    TextScaler textScaler,
    String text,
    TextStyle style,
  ) {
    return AdminListMeasurements.measureTextWidth(
      context,
      textScaler,
      text,
      style,
    );
  }

  static double _maxValue(double a, double b) =>
      AdminListMeasurements.maxValue(a, b);

  static String _longerText(String current, String candidate) {
    return AdminListMeasurements.longerText(current, candidate);
  }
}

class _StatusFormsTableRow extends StatelessWidget {
  const _StatusFormsTableRow({
    required this.form,
    required this.vm,
    required this.onViewPressed,
    this.onEditPressed,
    this.onDeactivatePressed,
    this.onDeletePressed,
    required this.shouldFlexRoles,
    required this.resolvedIdWidth,
    required this.resolvedRoleWidth,
    required this.resolvedCurrentWidth,
    required this.resolvedStatusWidth,
    required this.resolvedButtonWidth,
    required this.resolvedNextWidth,
    required this.resolvedCreatedWidth,
    required this.resolvedUpdatedWidth,
    required this.resolvedActionsWidth,
  });

  final StatusForm form;
  final AdminFlowViewModel vm;
  final VoidCallback onViewPressed;
  final VoidCallback? onEditPressed;
  final VoidCallback? onDeactivatePressed;
  final VoidCallback? onDeletePressed;
  final bool shouldFlexRoles;
  final double resolvedIdWidth;
  final double resolvedRoleWidth;
  final double resolvedCurrentWidth;
  final double resolvedStatusWidth;
  final double resolvedButtonWidth;
  final double resolvedNextWidth;
  final double resolvedCreatedWidth;
  final double resolvedUpdatedWidth;
  final double resolvedActionsWidth;

  @override
  Widget build(BuildContext context) {
    return AdminListItemCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _FixedSlot(
            width: resolvedIdWidth,
            child: _BodyCell(
              child: Text(
                form.id ?? '-',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                softWrap: true,
              ),
            ),
          ),
          if (shouldFlexRoles)
            Expanded(
              child: _BodyCell(
                child: Text(
                  _resolvedFormRolesText(form),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  softWrap: true,
                ),
              ),
            )
          else
            _FixedSlot(
              width: resolvedRoleWidth,
              child: _BodyCell(
                child: Text(
                  _resolvedFormRolesText(form),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  softWrap: true,
                ),
              ),
            ),
          _FixedSlot(
            width: resolvedCurrentWidth,
            child: _BodyCell(
              child: Text(
                form.currentStatusKey ?? '-',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                softWrap: true,
              ),
            ),
          ),
          _FixedSlot(
            width: resolvedStatusWidth,
            child: _BodyCell(
              child: Text(
                _resolvedFormStatusLabel(vm, form).isEmpty
                    ? '-'
                    : _resolvedFormStatusLabel(vm, form),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
                softWrap: true,
              ),
            ),
          ),
          _FixedSlot(
            width: resolvedButtonWidth,
            child: _BodyCell(
              child: Text(
                form.buttonText ?? '-',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                softWrap: true,
              ),
            ),
          ),
          _FixedSlot(
            width: resolvedNextWidth,
            child: _BodyCell(
              child: Text(
                form.nextStatusKey ?? '-',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                softWrap: true,
              ),
            ),
          ),
          _FixedSlot(
            width: resolvedCreatedWidth,
            child: _BodyCell(
              child: Text(
                AdminUsersView.formatCreatedAt(form.createdAt),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                softWrap: true,
              ),
            ),
          ),
          _FixedSlot(
            width: resolvedUpdatedWidth,
            child: _BodyCell(
              child: Text(
                AdminUsersView.formatUpdatedAt(form.updatedAt),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                softWrap: true,
              ),
            ),
          ),
          AdminListTrailingActionsLane(
            width: resolvedActionsWidth,
            child: _BodyCell(
              trailingPadding: 0,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MiniActionButton(
                    icon: Icons.visibility_rounded,
                    backgroundColor: Colors.yellow.shade900,
                    onTap: onViewPressed,
                  ),
                  if (onEditPressed != null) ...[
                    const SizedBox(width: 8),
                    _MiniActionButton(
                      icon: Icons.edit_rounded,
                      onTap: onEditPressed!,
                    ),
                  ],
                  if (onDeactivatePressed != null) ...[
                    const SizedBox(width: 8),
                    _MiniActionButton(
                      icon: Icons.close_rounded,
                      backgroundColor: AppColors.dangerStrong,
                      onTap: onDeactivatePressed!,
                    ),
                  ],
                  if (onDeletePressed != null) ...[
                    const SizedBox(width: 8),
                    _MiniActionButton(
                      icon: Icons.delete_rounded,
                      onTap: onDeletePressed!,
                      isDanger: true,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusFormResponsiveCard extends StatelessWidget {
  const _StatusFormResponsiveCard({
    required this.form,
    required this.vm,
    required this.onViewPressed,
    this.onEditPressed,
    this.onDeactivatePressed,
    this.onDeletePressed,
  });

  final StatusForm form;
  final AdminFlowViewModel vm;
  final VoidCallback onViewPressed;
  final VoidCallback? onEditPressed;
  final VoidCallback? onDeactivatePressed;
  final VoidCallback? onDeletePressed;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const fieldGap = 16.0;
        final textScaler = MediaQuery.textScalerOf(context);
        final useSingleColumn = constraints.maxWidth < 520;
        const showTopActionsRow = true;
        final stackTopActions = constraints.maxWidth < 320;
        final resolvedFields = [
          ('ID', form.id ?? '-'),
          ('Roles', _resolvedFormRolesText(form)),
          ('Status', form.currentStatusKey ?? '-'),
          (
            'Label',
            _resolvedFormStatusLabel(vm, form).isEmpty
                ? '-'
                : _resolvedFormStatusLabel(vm, form),
          ),
          ('Button', form.buttonText ?? '-'),
          ('Next', form.nextStatusKey ?? '-'),
          ('Created', AdminUsersView.formatCreatedAt(form.createdAt)),
          ('Updated', AdminUsersView.formatUpdatedAt(form.updatedAt)),
        ];
        final contentWidths = resolvedFields
            .map(
              (field) => _resolvedResponsiveFieldWidth(
                context,
                textScaler,
                constraints.maxWidth,
                field.$1,
                field.$2,
              ),
            )
            .toList();

        return AdminListItemCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: useSingleColumn
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              if (!stackTopActions)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Spacer(),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _ActionButton(
                          icon: Icons.visibility_rounded,
                          backgroundColor: Colors.yellow.shade900,
                          onTap: onViewPressed,
                        ),
                        if (onEditPressed != null)
                          _ActionButton(
                            icon: Icons.edit_outlined,
                            onTap: onEditPressed!,
                          ),
                        if (onDeactivatePressed != null)
                          _ActionButton(
                            icon: Icons.close_rounded,
                            backgroundColor: AppColors.dangerStrong,
                            onTap: onDeactivatePressed!,
                          ),
                        if (onDeletePressed != null)
                          _ActionButton(
                            icon: Icons.delete_outline_rounded,
                            onTap: onDeletePressed!,
                            isDanger: true,
                          ),
                      ],
                    ),
                  ],
                ),
              const SizedBox(height: 18),
              Wrap(
                spacing: fieldGap,
                runSpacing: fieldGap,
                children: List.generate(
                  resolvedFields.length,
                  (index) => _ResponsiveField(
                    title: resolvedFields[index].$1,
                    value: resolvedFields[index].$2,
                    isTitle: resolvedFields[index].$1 == 'Label',
                    width: useSingleColumn
                        ? constraints.maxWidth
                        : contentWidths[index],
                    centered: useSingleColumn,
                  ),
                ).toList(),
              ),
              if (showTopActionsRow && stackTopActions) ...[
                const SizedBox(height: 18),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _ActionButton(
                      icon: Icons.visibility_rounded,
                      backgroundColor: Colors.yellow.shade900,
                      onTap: onViewPressed,
                    ),
                    if (onEditPressed != null)
                      _ActionButton(
                        icon: Icons.edit_outlined,
                        onTap: onEditPressed!,
                      ),
                    if (onDeactivatePressed != null)
                      _ActionButton(
                        icon: Icons.close_rounded,
                        backgroundColor: AppColors.dangerStrong,
                        onTap: onDeactivatePressed!,
                      ),
                    if (onDeletePressed != null)
                      _ActionButton(
                        icon: Icons.delete_outline_rounded,
                        onTap: onDeletePressed!,
                        isDanger: true,
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _StatusFormsEmptyState extends StatelessWidget {
  const _StatusFormsEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AdminListItemCard(
      padding: const EdgeInsets.all(18),
      child: Text(
        message,
        style: TextStyle(
          color: AppColors.primaryColor.withValues(alpha: 0.72),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _InlineEditorContent extends StatelessWidget {
  const _InlineEditorContent({
    required this.vm,
    required this.form,
    this.onClose,
  });

  final AdminFlowViewModel vm;
  final StatusForm form;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _BasicInfoSection(vm: vm, form: form),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _fullWidthRolesField(
            context: context,
            vm: vm,
            form: form,
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _FieldsSection(vm: vm),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _DependenciesSection(vm: vm, form: form),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: _mainFormToggleField(context, vm: vm, form: form),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _activeToggleField(context, vm: vm, form: form),
        ),
      ],
    );
  }
}

class _BasicInfoSection extends StatelessWidget {
  const _BasicInfoSection({required this.vm, required this.form});

  final AdminFlowViewModel vm;
  final StatusForm form;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 980;

        if (isNarrow) {
          final roleStatuses = _availableStatusesForForm(vm);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fullWidthStatusField(
                statuses: roleStatuses,
                value: form.currentStatusKey,
                label: 'Status',
                onChanged: (value) =>
                    vm.updateFormField('currentStatusKey', value),
              ),
              const SizedBox(height: 6),
              _fullWidthStatusField(
                statuses: roleStatuses,
                value: form.nextStatusKey,
                label: 'Next Status',
                onChanged: (value) =>
                    vm.updateFormField('nextStatusKey', value),
              ),
              const SizedBox(height: 6),
              _fullWidthTextField(
                initialValue: form.buttonText,
                label: 'Text On Button',
                onChanged: (value) => vm.updateFormField('buttonText', value),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Builder(
              builder: (context) {
                final roleStatuses = _availableStatusesForForm(vm);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _fullWidthStatusField(
                        statuses: roleStatuses,
                        value: form.currentStatusKey,
                        label: 'Status',
                        onChanged: (value) =>
                            vm.updateFormField('currentStatusKey', value),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 3,
                      child: _fullWidthStatusField(
                        statuses: roleStatuses,
                        value: form.nextStatusKey,
                        label: 'Next Status',
                        onChanged: (value) =>
                            vm.updateFormField('nextStatusKey', value),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _fullWidthTextField(
                    initialValue: form.buttonText,
                    label: 'Text On Button',
                    onChanged: (value) =>
                        vm.updateFormField('buttonText', value),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _DependenciesSection extends StatelessWidget {
  const _DependenciesSection({required this.vm, required this.form});

  final AdminFlowViewModel vm;
  final StatusForm form;

  @override
  Widget build(BuildContext context) {
    final dependencies = form.dependencies;
    final labelStyle = _modalRowLabelStyle(context);
    final dependencyRoles = AdminFlowViewModel.dependencyStatusTypes
        .map(_dependencyStatusTypeToRole)
        .whereType<String>()
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Dependencies', style: labelStyle)),
            _InlineAddButton(
              onTap: () {
                if (vm.statuses.isEmpty) {
                  AppSnackbar.showError(context, 'Create a status first.');
                  return;
                }
                vm.addDependency();
              },
            ),
          ],
        ),
        if (dependencies.isNotEmpty) const SizedBox(height: 8),
        if (dependencies.isNotEmpty)
          ...dependencies.asMap().entries.map(
            (entry) => Padding(
              padding: EdgeInsets.only(
                top: entry.key == 0 ? 4 : 0,
                bottom: entry.key == dependencies.length - 1 ? 0 : 12,
              ),
              child: _DependencyCard(
                index: entry.key,
                dependencyRoles: dependencyRoles,
                selectedRole: _dependencyStatusTypeToRole(
                  entry.value.statusType,
                ),
                selectedStatusKey: entry.value.statusKey,
                dependencyStatuses: vm.statusesForStatusType(
                  entry.value.statusType,
                ),
                blockedMessage: form.blockedMessage,
                showBlockedMessage: entry.key == dependencies.length - 1,
                onRoleSelected: (role) => vm.updateDependency(
                  entry.key,
                  statusType: _roleToDependencyStatusType(role),
                  statusKey: null,
                ),
                onStatusChanged: (value) => vm.updateDependency(
                  entry.key,
                  statusType: entry.value.statusType,
                  statusKey: value,
                ),
                onRemove: () => vm.removeDependency(entry.key),
                onBlockedMessageChanged: (value) =>
                    vm.updateFormField('blockedMessage', value),
              ),
            ),
          ),
      ],
    );
  }
}

class _DependencyCard extends StatelessWidget {
  const _DependencyCard({
    required this.index,
    required this.dependencyRoles,
    required this.selectedRole,
    required this.selectedStatusKey,
    required this.dependencyStatuses,
    required this.blockedMessage,
    required this.showBlockedMessage,
    required this.onRoleSelected,
    required this.onStatusChanged,
    required this.onRemove,
    required this.onBlockedMessageChanged,
  });

  final int index;
  final List<String> dependencyRoles;
  final String? selectedRole;
  final String? selectedStatusKey;
  final List<Status> dependencyStatuses;
  final String? blockedMessage;
  final bool showBlockedMessage;
  final ValueChanged<String> onRoleSelected;
  final ValueChanged<String?> onStatusChanged;
  final VoidCallback onRemove;
  final ValueChanged<String> onBlockedMessageChanged;

  @override
  Widget build(BuildContext context) {
    final resolvedRole = selectedRole?.trim().isNotEmpty == true
        ? humanizeDropdownValue(selectedRole!.trim())
        : 'Role';
    final resolvedStatus = dependencyStatuses
        .where((status) => status.key == selectedStatusKey)
        .map((status) => status.label?.trim())
        .whereType<String>()
        .where((label) => label.isNotEmpty)
        .cast<String?>()
        .firstWhere(
          (_) => true,
          orElse: () => selectedStatusKey?.trim().isNotEmpty == true
              ? selectedStatusKey!.trim()
              : 'Status',
        );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(18, 14, 18, showBlockedMessage ? 8 : 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primaryBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$resolvedRole $resolvedStatus',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _DependencyRemoveButton(onTap: onRemove),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: dependencyRoles.map((role) {
              final isSelected = role == selectedRole;
              return _DependencyRoleChip(
                label: humanizeDropdownValue(role),
                selected: isSelected,
                onTap: () => onRoleSelected(role),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          AdminModalDropdownField<String>(
            label: 'Required Status',
            bottomPadding: 0,
            initialValue:
                dependencyStatuses.any(
                  (status) => status.key == selectedStatusKey,
                )
                ? selectedStatusKey
                : null,
            iconEnabledColor: AppColors.primaryColor,
            disabledTapMessage: 'No statuses available for the selected role.',
            items: dependencyStatuses
                .map(
                  (status) => DropdownMenuItem<String>(
                    value: status.key,
                    child: Text(status.label ?? status.key ?? '-'),
                  ),
                )
                .toList(),
            onChanged: onStatusChanged,
          ),
          if (showBlockedMessage) ...[
            const SizedBox(height: 8),
            AdminModalValueTextField(
              label: 'Blocked Message',
              initialValue: blockedMessage,
              bottomPadding: 0,
              onChanged: onBlockedMessageChanged,
            ),
          ],
        ],
      ),
    );
  }
}

class _DependencyRoleChip extends StatelessWidget {
  const _DependencyRoleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? AppColors.primaryColor
        : AppColors.primaryBorder;
    final backgroundColor = selected ? AppColors.primarySurface : Colors.white;
    final textColor = selected ? AppColors.primaryColor : AppColors.textPrimary;

    return AppMousePressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(1000),
      child: Builder(
        builder: (context) => ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: appPressableActive(context)
                  ? AppColors.primarySurfaceAlt.withValues(alpha: 0.34)
                  : backgroundColor,
              borderRadius: BorderRadius.circular(1000),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: 18,
                  color: selected
                      ? AppColors.primaryColor
                      : AppColors.primaryColor.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  textHeightBehavior: const TextHeightBehavior(
                    applyHeightToFirstAscent: false,
                    applyHeightToLastDescent: false,
                  ),
                  style: TextStyle(
                    color: textColor,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DependencyRemoveButton extends StatelessWidget {
  const _DependencyRemoveButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.remove_circle_outline_rounded, size: 18),
      label: const Text('Remove'),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.danger,
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

String? _dependencyStatusTypeToRole(String? statusType) {
  return switch (statusType) {
    'client_status' => 'client',
    'driver_status' => 'driver',
    'helper_status' => 'helper',
    _ => null,
  };
}

String? _roleToDependencyStatusType(String? role) {
  return switch (role) {
    'client' => 'client_status',
    'driver' => 'driver_status',
    'helper' => 'helper_status',
    _ => null,
  };
}

class _FieldsSection extends StatefulWidget {
  const _FieldsSection({required this.vm});

  final AdminFlowViewModel vm;

  @override
  State<_FieldsSection> createState() => _FieldsSectionState();
}

class _FieldsSectionState extends State<_FieldsSection> {
  @override
  Widget build(BuildContext context) {
    final labelStyle = _modalRowLabelStyle(context);
    final availableFields = widget.vm.availableFieldsForSelection;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: Text('Fields', style: labelStyle)),
              _InlineAddFieldsButton(
                availableFields: availableFields,
                onSelected: (fieldId) => widget.vm.assignField(fieldId),
                onEmptyTap: () {
                  AppSnackbar.showError(context, 'Create a field first.');
                },
              ),
            ],
          ),
        ),
        if (widget.vm.fields.isNotEmpty) ...[
          const SizedBox(height: 16),
          ReorderableListView.builder(
            shrinkWrap: true,
            primary: false,
            buildDefaultDragHandles: false,
            physics: const NeverScrollableScrollPhysics(),
            proxyDecorator: (child, index, animation) {
              return AnimatedBuilder(
                animation: animation,
                builder: (context, _) {
                  final elevation = Tween<double>(
                    begin: 0,
                    end: 8,
                  ).evaluate(animation);
                  return Material(
                    color: Colors.transparent,
                    elevation: elevation,
                    shadowColor: Colors.black.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: child,
                    ),
                  );
                },
              );
            },
            itemCount: widget.vm.fields.length,
            onReorder: widget.vm.reorderAssignedField,
            itemBuilder: (context, index) {
              final field = widget.vm.fields[index];
              final key = field.id ?? '${field.key ?? 'field'}_$index';
              return Padding(
                key: ValueKey(key),
                padding: EdgeInsets.only(
                  bottom: index == widget.vm.fields.length - 1 ? 0 : 14,
                ),
                child: _AssignedFieldCard(
                  vm: widget.vm,
                  field: field,
                  index: index,
                  onRemove: () => widget.vm.removeAssignedField(index),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _InlineAddFieldsButton extends StatelessWidget {
  const _InlineAddFieldsButton({
    required this.availableFields,
    required this.onSelected,
    required this.onEmptyTap,
  });

  final List<StatusField> availableFields;
  final ValueChanged<String> onSelected;
  final VoidCallback onEmptyTap;

  @override
  Widget build(BuildContext context) {
    if (availableFields.isEmpty) {
      return _InlineAddButton(onTap: onEmptyTap);
    }

    return PopupMenuButton<String>(
      tooltip: 'Add field',
      color: Colors.white,
      surfaceTintColor: Colors.white,
      onSelected: onSelected,
      itemBuilder: (context) => availableFields
          .map(
            (field) => PopupMenuItem<String>(
              value: field.id,
              child: Text(
                field.title?.trim().isNotEmpty == true
                    ? field.title!
                    : field.key ?? 'Untitled Field',
                style: adminDropdownDisplayTextStyle,
              ),
            ),
          )
          .toList(),
      child: const _InlineAddButton(onTap: null),
    );
  }
}

class _AssignedFieldCard extends StatelessWidget {
  const _AssignedFieldCard({
    required this.vm,
    required this.field,
    required this.index,
    required this.onRemove,
  });

  final AdminFlowViewModel vm;
  final StatusField field;
  final int index;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final fieldId = field.id ?? '';
    final isRequired = vm.effectiveRequiredForField(field);
    final fieldTitle = field.title?.trim().isNotEmpty == true
        ? field.title!.trim()
        : field.key ?? 'Untitled Field';
    final fieldType = field.type?.trim().isNotEmpty == true
        ? field.type!.trim()
        : '-';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primaryBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: Container(
                          width: 40,
                          height: 40,
                          margin: const EdgeInsets.only(right: 14),
                          decoration: BoxDecoration(
                            color: AppColors.primarySurface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.primaryBorder),
                          ),
                          child: Icon(
                            Icons.drag_indicator_rounded,
                            color: AppColors.primaryColor.withValues(
                              alpha: 0.82,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fieldTitle,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w800,
                                height: 1.2,
                              ),
                            ),
                            Text(
                              fieldType,
                              style: TextStyle(
                                color: AppColors.primaryColor.withValues(
                                  alpha: 0.72,
                                ),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: onRemove,
                  icon: const Icon(
                    Icons.remove_circle_outline_rounded,
                    size: 18,
                  ),
                  label: const Text('Remove'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 18, right: 12),
            child: AdminModalToggleRow(
              title: 'Required',
              value: isRequired,
              leftInset: 0,
              rightInset: 0,
              onChanged: fieldId.isEmpty
                  ? (_) {}
                  : (value) => vm.updateAssignedFieldRequired(fieldId, value),
            ),
          ),
        ],
      ),
    );
  }
}

class _FixedSlot extends StatelessWidget {
  const _FixedSlot({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AdminListFixedSlot(width: width, child: child);
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.label,
    this.trailingPadding = AdminListMeasurements.defaultTrailingPadding,
    this.alignment = Alignment.centerLeft,
    this.textAlign = TextAlign.left,
  });

  final String label;
  final double trailingPadding;
  final Alignment alignment;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return AdminListHeaderCell(
      label: label,
      trailingPadding: trailingPadding,
      alignment: alignment,
      textAlign: textAlign,
    );
  }
}

class _BodyCell extends StatelessWidget {
  const _BodyCell({
    required this.child,
    this.trailingPadding = AdminListMeasurements.defaultTrailingPadding,
    this.alignment = Alignment.centerLeft,
  });

  final Widget child;
  final double trailingPadding;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return AdminListBodyCell(
      trailingPadding: trailingPadding,
      alignment: alignment,
      child: child,
    );
  }
}

class _ResponsiveField extends StatelessWidget {
  const _ResponsiveField({
    required this.title,
    required this.value,
    required this.width,
    required this.centered,
    this.isTitle = false,
  });

  final String title;
  final String value;
  final double width;
  final bool centered;
  final bool isTitle;

  @override
  Widget build(BuildContext context) {
    return AdminListResponsiveField(
      title: title,
      value: value,
      width: width,
      centered: centered,
      isTitle: isTitle,
    );
  }
}

double _resolvedResponsiveFieldWidth(
  BuildContext context,
  TextScaler textScaler,
  double maxWidth,
  String label,
  String value,
) {
  return AdminListMeasurements.resolvedResponsiveFieldWidth(
    context,
    textScaler,
    maxWidth,
    label,
    value,
  );
}

Widget _fullWidthRolesField({
  required BuildContext context,
  required AdminFlowViewModel vm,
  required StatusForm form,
}) {
  final selectedRoles = form.resolvedRoles.toSet();
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Roles',
        style: Theme.of(
          context,
        ).textTheme.bodyLarge?.copyWith(color: AppColors.textPrimary),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: AdminFlowViewModel.roleOptions.map((role) {
          final isSelected = selectedRoles.contains(role);
          return _FormApplicableRoleChip(
            label: humanizeDropdownValue(role),
            selected: isSelected,
            onTap: () {
              final nextRoles = {...selectedRoles};
              if (isSelected) {
                nextRoles.remove(role);
              } else {
                nextRoles.add(role);
              }
              vm.updateFormRoles(nextRoles.toList());
            },
          );
        }).toList(),
      ),
    ],
  );
}

Widget _fullWidthTextField({
  required String? initialValue,
  required String label,
  required ValueChanged<String> onChanged,
}) {
  return AdminModalValueTextField(
    initialValue: initialValue,
    label: label,
    bottomPadding: 0,
    onChanged: onChanged,
  );
}

Widget _fullWidthStatusField({
  required List<Status> statuses,
  required String? value,
  required String label,
  required ValueChanged<String?> onChanged,
}) {
  return AdminModalDropdownField<String>(
    label: label,
    bottomPadding: 0,
    initialValue: statuses.any((status) => status.key == value) ? value : null,
    iconEnabledColor: AppColors.primaryColor,
    items: statuses
        .map(
          (status) => DropdownMenuItem<String>(
            value: status.key,
            child: Text(status.label ?? status.key ?? '-'),
          ),
        )
        .toList(),
    onChanged: onChanged,
  );
}

Widget _activeToggleField(
  BuildContext context, {
  required AdminFlowViewModel vm,
  required StatusForm form,
}) {
  return AdminModalToggleRow(
    title: 'Active',
    value: form.isActive ?? true,
    onChanged: (value) => vm.updateFormField('isActive', value),
  );
}

Widget _mainFormToggleField(
  BuildContext context, {
  required AdminFlowViewModel vm,
  required StatusForm form,
}) {
  return AdminModalToggleRow(
    title: 'Main Form',
    value: form.resolvedIsMainForm,
    onChanged: (value) => vm.updateFormField('isMainForm', value),
  );
}

String _resolvedFormRolesText(StatusForm form) {
  final roles = form.resolvedRoles;
  if (roles.isEmpty) {
    return '-';
  }
  return roles.map(_titleCase).join(', ');
}

String _resolvedFormStatusLabel(AdminFlowViewModel vm, StatusForm form) {
  final currentStatusKey = form.currentStatusKey?.trim() ?? '';
  if (currentStatusKey.isEmpty) {
    return '';
  }

  for (final status in _availableStatusesForForm(vm)) {
    if ((status.key?.trim() ?? '') == currentStatusKey) {
      return status.label?.trim() ?? '';
    }
  }

  return '';
}

String _resolvedFormStatusDescription(AdminFlowViewModel vm, StatusForm form) {
  final currentStatusKey = form.currentStatusKey?.trim() ?? '';
  if (currentStatusKey.isEmpty) {
    return '';
  }

  for (final status in _availableStatusesForForm(vm)) {
    if ((status.key?.trim() ?? '') == currentStatusKey) {
      return status.description?.trim() ?? '';
    }
  }

  return '';
}

List<Status> _availableStatusesForForm(AdminFlowViewModel vm) {
  return vm.statuses.where((status) => status.isActive != false).toList();
}

class _FormApplicableRoleChip extends StatelessWidget {
  const _FormApplicableRoleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? AppColors.primaryColor
        : AppColors.primaryBorder;
    final backgroundColor = selected ? AppColors.primarySurface : Colors.white;
    final textColor = selected ? AppColors.primaryColor : AppColors.textPrimary;

    return AppMousePressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Builder(
        builder: (context) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: appPressableActive(context)
                ? AppColors.primarySurfaceAlt.withValues(alpha: 0.34)
                : backgroundColor,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 18,
                color: selected
                    ? AppColors.primaryColor
                    : AppColors.primaryColor.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

TextStyle? _modalRowLabelStyle(BuildContext context) {
  return Theme.of(
    context,
  ).textTheme.bodyLarge?.copyWith(color: AppColors.textPrimary);
}

ButtonStyle _primaryButtonStyle() {
  return FilledButton.styleFrom(
    backgroundColor: AppColors.primaryColor,
    foregroundColor: Colors.white,
    minimumSize: const Size(0, AdminFormsView.controlHeight),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AdminFormsView.surfaceRadius),
    ),
  );
}

class _InlineAddButton extends StatelessWidget {
  const _InlineAddButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 32,
      child: FilledButton(
        onPressed: onTap,
        style: _primaryButtonStyle().copyWith(
          minimumSize: WidgetStateProperty.all(const Size(52, 32)),
          padding: WidgetStateProperty.all(EdgeInsets.zero),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return AppColors.primaryColor;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return Colors.white;
          }),
          shape: WidgetStateProperty.all(
            const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(1000)),
            ),
          ),
        ),
        child: const Icon(Icons.add_rounded, size: 18),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.onTap,
    this.isDanger = false,
    this.backgroundColor,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool isDanger;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return AdminListActionButton(
      icon: icon,
      onTap: onTap,
      backgroundColor: backgroundColor,
      isDanger: isDanger,
      size: 40,
      iconSize: 18,
      borderRadius: 12,
    );
  }
}

class _MiniActionButton extends StatelessWidget {
  const _MiniActionButton({
    required this.icon,
    required this.onTap,
    this.isDanger = false,
    this.backgroundColor,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool isDanger;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return AdminListActionButton(
      icon: icon,
      onTap: onTap,
      backgroundColor: backgroundColor,
      isDanger: isDanger,
      size: 36,
      iconSize: 18,
      borderRadius: 12,
    );
  }
}

String _titleCase(String? value) {
  if (value == null || value.trim().isEmpty) {
    return '-';
  }

  return value
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
