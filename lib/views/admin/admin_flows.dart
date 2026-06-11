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

class AdminFlowsView extends StatelessWidget {
  const AdminFlowsView({super.key});

  static const sectionGap = 14.0;
  static const controlHeight = 52.0;
  static const surfaceRadius = 16.0;

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<AdminFlowViewModel>.reactive(
      viewModelBuilder: AdminFlowViewModel.new,
      onViewModelReady: (vm) => vm.loadForms(),
      builder: (context, vm, _) {
        return AppPageLoadingOverlay(
          isVisible: vm.isLoading,
          message: vm.busyMessage,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppRefreshStrip(isVisible: vm.isLoading),
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

  String _formSaveMessage(StatusForm form, {required bool isEditing}) {
    final roleLabel = _resolvedFormRolesText(form);
    final statusLabel = _resolvedFormStatusLabel(widget.vm, form);
    final subject = [
      if (roleLabel.isNotEmpty && roleLabel != '-') roleLabel,
      if (statusLabel.isNotEmpty) statusLabel,
    ].join(' ');

    if (subject.isNotEmpty) {
      return isEditing
          ? '$subject form has been updated.'
          : '$subject form has been created.';
    }

    return isEditing ? 'Form has been updated.' : 'Form has been created.';
  }

  String _formEditMessage(StatusForm before, StatusForm after) {
    final roleLabel = _resolvedFormRolesText(after);
    final statusLabel = _resolvedFormStatusLabel(widget.vm, after);
    final subject = [
      if (roleLabel.isNotEmpty && roleLabel != '-') roleLabel,
      if (statusLabel.isNotEmpty) statusLabel,
    ].join(' ');
    final changedFields = _changedFormFields(before, after);
    final detailedMessage = _buildDetailedUpdateMessage(
      subject: subject.isNotEmpty ? '$subject form' : 'Form',
      changes: changedFields,
    );
    if (detailedMessage != null) {
      return detailedMessage;
    }
    return _formSaveMessage(after, isEditing: true);
  }

  Map<String, String> _changedFormFields(StatusForm before, StatusForm after) {
    final changed = <String, String>{};

    if (before.resolvedRoles.join('|') != after.resolvedRoles.join('|')) {
      changed['roles'] = _resolvedFormRolesText(after);
    }
    if (before.currentStatusKey != after.currentStatusKey) {
      changed['current status'] = after.currentStatusKey ?? '-';
    }
    if (before.nextStatusKey != after.nextStatusKey) {
      changed['next status'] = after.nextStatusKey ?? '-';
    }
    if (_resolvedFormStatusLabel(widget.vm, before) !=
        _resolvedFormStatusLabel(widget.vm, after)) {
      final label = _resolvedFormStatusLabel(widget.vm, after);
      changed['status label'] = label.isEmpty ? '-' : label;
    }
    if (_resolvedFormStatusDescription(widget.vm, before) !=
        _resolvedFormStatusDescription(widget.vm, after)) {
      final description = _resolvedFormStatusDescription(widget.vm, after);
      changed['status description'] = description.isEmpty ? '-' : description;
    }
    if ((before.buttonText ?? '').trim() != (after.buttonText ?? '').trim()) {
      changed['button text'] = after.buttonText?.trim() ?? '-';
    }
    if (before.resolvedIsMainForm != after.resolvedIsMainForm) {
      changed['main form'] = after.resolvedIsMainForm ? 'Main' : 'Not Main';
    }
    final beforeFieldIds = before.fields
        .map((field) => field.id ?? '')
        .join('|');
    final afterFieldIds = after.fields.map((field) => field.id ?? '').join('|');
    if (beforeFieldIds != afterFieldIds) {
      changed['fields'] = after.fields.isEmpty
          ? '-'
          : after.fields.map((field) => field.id ?? '-').join(', ');
    }
    if (_fieldOverrideSignature(before) != _fieldOverrideSignature(after)) {
      changed['field rules'] = after.fieldOverrides.isEmpty
          ? '-'
          : after.fieldOverrides.entries
                .map(
                  (entry) =>
                      '${entry.key}: required=${entry.value.required ?? 'default'}, placeholder=${entry.value.placeholder ?? 'default'}',
                )
                .join(', ');
    }
    if (_dependencySignature(before) != _dependencySignature(after)) {
      changed['dependencies'] = after.dependencies.isEmpty
          ? '-'
          : after.dependencies
                .map(
                  (item) =>
                      '${item.statusType ?? '-'}:${item.statusKey ?? '-'}',
                )
                .join(', ');
    }
    if ((before.blockedMessage ?? '').trim() !=
        (after.blockedMessage ?? '').trim()) {
      changed['blocked message'] = after.blockedMessage?.trim() ?? '-';
    }
    if ((before.isActive ?? false) != (after.isActive ?? false)) {
      changed['active status'] = '${after.isActive ?? false}';
    }

    return changed;
  }

  String _dependencySignature(StatusForm form) {
    return form.dependencies
        .map((item) => '${item.statusType ?? ''}:${item.statusKey ?? ''}')
        .join('|');
  }

  String _fieldOverrideSignature(StatusForm form) {
    return form.fieldOverrides.entries
        .map(
          (entry) =>
              '${entry.key}:${entry.value.required?.toString() ?? ''}:${entry.value.placeholder ?? ''}',
        )
        .join('|');
  }

  String? _buildDetailedUpdateMessage({
    required String subject,
    required Map<String, String> changes,
  }) {
    if (changes.isEmpty) {
      return null;
    }
    if (changes.length == 1) {
      final entry = changes.entries.first;
      return "$subject's ${entry.key} has been updated to ${entry.value}.";
    }
    final summary = changes.entries
        .map((entry) => '${entry.key} = ${entry.value}')
        .join('; ');
    return '$subject has been updated: $summary.';
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

      return matchesSearch && matchesRole && matchesActive;
    }).toList();
  }

  Future<void> _openNewFormDialog() async {
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
                  onPressed: () async {
                    final savingForm = form;
                    await widget.vm.saveForm();
                    final errorMessage = widget.vm.errorMessage;
                    if (!dialogContext.mounted) {
                      return;
                    }
                    if (errorMessage == null) {
                      AppSnackbar.showSuccess(
                        dialogContext,
                        _formSaveMessage(savingForm, isEditing: false),
                      );
                      widget.vm.clearSelection();
                      Navigator.of(dialogContext).pop();
                    } else {
                      AppSnackbar.showError(dialogContext, errorMessage);
                    }
                  },
                  child: const Text('Save'),
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
                  onPressed: () async {
                    final savingForm = selected;
                    await widget.vm.saveForm();
                    final errorMessage = widget.vm.errorMessage;
                    if (!dialogContext.mounted) {
                      return;
                    }
                    if (errorMessage == null) {
                      AppSnackbar.showSuccess(
                        dialogContext,
                        _formEditMessage(form, savingForm),
                      );
                      widget.vm.clearSelection();
                      Navigator.of(dialogContext).pop();
                    } else {
                      AppSnackbar.showError(dialogContext, errorMessage);
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
              child: _InlineEditorContent(
                vm: widget.vm,
                form: selected,
                onClose: () {
                  widget.vm.clearSelection();
                  Navigator.of(dialogContext).pop();
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
    );
    if (!confirmed || !mounted) {
      return;
    }
    await widget.vm.deactivateForm(form);
    if (!mounted) {
      return;
    }
    AppSnackbar.showSuccess(context, 'Form deactivated.');
  }

  Future<void> _confirmDeleteForm(StatusForm form) async {
    final confirmed = await showAdminActionConfirmation(
      context,
      title: 'Delete Form ${form.id ?? '-'}',
      message: 'Are you sure you want to delete this form?',
      confirmLabel: 'Delete',
      isDanger: true,
    );
    if (!confirmed || !mounted) {
      return;
    }
    await widget.vm.deleteForm(form);
    if (!mounted) {
      return;
    }
    AppSnackbar.showSuccess(context, 'Form deleted.');
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
              onSearchChanged: (value) => setState(() => _searchQuery = value),
              onRoleChanged: (value) => setState(() => _roleFilter = value),
              onActiveChanged: (value) => setState(() => _activeFilter = value),
              onNewPressed: _openNewFormDialog,
            ),
            const SizedBox(height: AdminFlowsView.sectionGap),
            ListenableBuilder(
              listenable: widget.vm,
              builder: (context, _) {
                if (isNarrow) {
                  if (_filteredForms.isEmpty) {
                    return _StatusFormsEmptyState(message: _emptyMessage);
                  }

                  return Column(
                    children: _filteredForms
                        .map(
                          (form) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: RepaintBoundary(
                              child: _StatusFormResponsiveCard(
                                form: form,
                                vm: widget.vm,
                                onViewPressed: () =>
                                    _openPreviewFormDialog(form),
                                onEditPressed: () => _openEditFormDialog(form),
                                onDeactivatePressed: () =>
                                    _confirmDeactivateForm(form),
                                onDeletePressed: () => _confirmDeleteForm(form),
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
                    onEditPressed: _openEditFormDialog,
                    onDeactivatePressed: _confirmDeactivateForm,
                    onDeletePressed: _confirmDeleteForm,
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
    required this.onSearchChanged,
    required this.onRoleChanged,
    required this.onActiveChanged,
    required this.onNewPressed,
  });

  final String searchQuery;
  final String roleFilter;
  final String activeFilter;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onRoleChanged;
  final ValueChanged<String> onActiveChanged;
  final VoidCallback onNewPressed;

  @override
  Widget build(BuildContext context) {
    return AdminListToolbar(
      controlHeight: AdminFlowsView.controlHeight,
      surfaceRadius: AdminFlowsView.surfaceRadius,
      search: _StatusFormsSearchField(
        initialValue: searchQuery,
        onChanged: onSearchChanged,
      ),
      filtersBuilder: (context, iconOnly) => _StatusFormsFiltersPanel(
        roleFilter: roleFilter,
        activeFilter: activeFilter,
        iconOnly: iconOnly,
        onRoleChanged: onRoleChanged,
        onActiveChanged: onActiveChanged,
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
      controlHeight: AdminFlowsView.controlHeight,
      surfaceRadius: AdminFlowsView.surfaceRadius,
      initialValue: widget.initialValue,
      onChanged: widget.onChanged,
    );
  }
}

class _StatusFormsFiltersPanel extends StatefulWidget {
  const _StatusFormsFiltersPanel({
    required this.roleFilter,
    required this.activeFilter,
    required this.iconOnly,
    required this.onRoleChanged,
    required this.onActiveChanged,
  });

  final String roleFilter;
  final String activeFilter;
  final bool iconOnly;
  final ValueChanged<String> onRoleChanged;
  final ValueChanged<String> onActiveChanged;

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
    const filterItemWidth = 180.0;
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
      controlHeight: AdminFlowsView.controlHeight,
      surfaceRadius: AdminFlowsView.surfaceRadius,
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
                    height: AdminFlowsView.controlHeight,
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
                    height: AdminFlowsView.controlHeight,
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
                    height: AdminFlowsView.controlHeight,
                    child: FilledButton(
                      onPressed: () {
                        _unfocusFilterFields();
                        widget.onRoleChanged('All');
                        widget.onActiveChanged('All');
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFD94B4B),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AdminFlowsView.surfaceRadius,
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
        radius: AdminFlowsView.surfaceRadius,
        minHeight: AdminFlowsView.controlHeight,
      ),
      items: items
          .where((item) => item != 'All')
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

class _StatusFormsTable extends StatelessWidget {
  const _StatusFormsTable({
    required this.forms,
    required this.emptyMessage,
    required this.vm,
    required this.onViewPressed,
    required this.onEditPressed,
    required this.onDeactivatePressed,
    required this.onDeletePressed,
  });

  final List<StatusForm> forms;
  final String emptyMessage;
  final AdminFlowViewModel vm;
  final Future<void> Function(StatusForm form) onViewPressed;
  final Future<void> Function(StatusForm form) onEditPressed;
  final Future<void> Function(StatusForm form) onDeactivatePressed;
  final Future<void> Function(StatusForm form) onDeletePressed;

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

  static const _defaultTrailingPadding = 20.0;
  static const _extraWidthAllowance = 16.0;
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
        final sampleActive = forms
            .map((form) => (form.isActive ?? false) ? 'Active' : 'Inactive')
            .fold<String>('Inactive', _longerText);
        final activeWidth = _maxTextWidth(
          context,
          textScaler,
          'Active',
          _headerStyle,
          sampleActive,
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
        final resolvedActiveWidth = _resolvedColumnWidth(activeWidth) + 12;
        final resolvedActionsWidth = actionsWidth + _extraWidthAllowance;

        final totalMeasuredWidth =
            resolvedIdWidth +
            resolvedRoleWidth +
            resolvedCurrentWidth +
            resolvedStatusWidth +
            resolvedButtonWidth +
            resolvedNextWidth +
            resolvedActiveWidth +
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
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _StatusFormResponsiveCard(
                      form: form,
                      vm: vm,
                      onViewPressed: () => onViewPressed(form),
                      onEditPressed: () => onEditPressed(form),
                      onDeactivatePressed: () => onDeactivatePressed(form),
                      onDeletePressed: () => onDeletePressed(form),
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
              minHeight: AdminFlowsView.controlHeight,
              borderRadius: AdminFlowsView.surfaceRadius,
              child: Row(
                children: [
                  _FixedSlot(
                    width: resolvedIdWidth,
                    child: const _HeaderCell(label: 'ID', trailingPadding: 20),
                  ),
                  if (shouldFlexRoles)
                    const Expanded(
                      child: _HeaderCell(label: 'Roles', trailingPadding: 20),
                    )
                  else
                    _FixedSlot(
                      width: resolvedRoleWidth,
                      child: const _HeaderCell(
                        label: 'Roles',
                        trailingPadding: 20,
                      ),
                    ),
                  _FixedSlot(
                    width: resolvedCurrentWidth,
                    child: const _HeaderCell(
                      label: 'Status',
                      trailingPadding: 20,
                    ),
                  ),
                  _FixedSlot(
                    width: resolvedStatusWidth,
                    child: const _HeaderCell(
                      label: 'Label',
                      trailingPadding: 20,
                    ),
                  ),
                  _FixedSlot(
                    width: resolvedButtonWidth,
                    child: const _HeaderCell(
                      label: 'Button',
                      trailingPadding: 20,
                    ),
                  ),
                  _FixedSlot(
                    width: resolvedNextWidth,
                    child: const _HeaderCell(
                      label: 'Next',
                      trailingPadding: 20,
                    ),
                  ),
                  _FixedSlot(
                    width: resolvedActiveWidth,
                    child: const _HeaderCell(
                      label: 'Active',
                      trailingPadding: 20,
                    ),
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
            const SizedBox(height: AdminFlowsView.sectionGap),
            if (forms.isEmpty)
              _StatusFormsEmptyState(message: emptyMessage)
            else
              ...forms.map(
                (form) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _StatusFormsTableRow(
                    form: form,
                    vm: vm,
                    onViewPressed: () => onViewPressed(form),
                    onEditPressed: () => onEditPressed(form),
                    onDeactivatePressed: () => onDeactivatePressed(form),
                    onDeletePressed: () => onDeletePressed(form),
                    shouldFlexRoles: shouldFlexRoles,
                    resolvedIdWidth: resolvedIdWidth,
                    resolvedRoleWidth: resolvedRoleWidth,
                    resolvedCurrentWidth: resolvedCurrentWidth,
                    resolvedStatusWidth: resolvedStatusWidth,
                    resolvedButtonWidth: resolvedButtonWidth,
                    resolvedNextWidth: resolvedNextWidth,
                    resolvedActiveWidth: resolvedActiveWidth,
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
    required this.onEditPressed,
    required this.onDeactivatePressed,
    required this.onDeletePressed,
    required this.shouldFlexRoles,
    required this.resolvedIdWidth,
    required this.resolvedRoleWidth,
    required this.resolvedCurrentWidth,
    required this.resolvedStatusWidth,
    required this.resolvedButtonWidth,
    required this.resolvedNextWidth,
    required this.resolvedActiveWidth,
    required this.resolvedActionsWidth,
  });

  final StatusForm form;
  final AdminFlowViewModel vm;
  final VoidCallback onViewPressed;
  final VoidCallback onEditPressed;
  final VoidCallback onDeactivatePressed;
  final VoidCallback onDeletePressed;
  final bool shouldFlexRoles;
  final double resolvedIdWidth;
  final double resolvedRoleWidth;
  final double resolvedCurrentWidth;
  final double resolvedStatusWidth;
  final double resolvedButtonWidth;
  final double resolvedNextWidth;
  final double resolvedActiveWidth;
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
            width: resolvedActiveWidth,
            child: _BodyCell(
              child: _metaPill(
                (form.isActive ?? false) ? 'Active' : 'Inactive',
                isFilled: form.isActive ?? false,
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
                  const SizedBox(width: 8),
                  _MiniActionButton(
                    icon: Icons.edit_rounded,
                    onTap: onEditPressed,
                  ),
                  const SizedBox(width: 8),
                  _MiniActionButton(
                    icon: Icons.close_rounded,
                    backgroundColor: Colors.red.shade700,
                    onTap: onDeactivatePressed,
                  ),
                  const SizedBox(width: 8),
                  _MiniActionButton(
                    icon: Icons.delete_rounded,
                    onTap: onDeletePressed,
                    isDanger: true,
                  ),
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
    required this.onEditPressed,
    required this.onDeactivatePressed,
    required this.onDeletePressed,
  });

  final StatusForm form;
  final AdminFlowViewModel vm;
  final VoidCallback onViewPressed;
  final VoidCallback onEditPressed;
  final VoidCallback onDeactivatePressed;
  final VoidCallback onDeletePressed;

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
              if (showTopActionsRow && stackTopActions)
                Column(
                  children: [
                    _metaPill(
                      (form.isActive ?? false) ? 'Active' : 'Inactive',
                      isFilled: form.isActive ?? false,
                    ),
                  ],
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (showTopActionsRow) ...[
                      _metaPill(
                        (form.isActive ?? false) ? 'Active' : 'Inactive',
                        isFilled: form.isActive ?? false,
                      ),
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
                          _ActionButton(
                            icon: Icons.edit_outlined,
                            onTap: onEditPressed,
                          ),
                          _ActionButton(
                            icon: Icons.close_rounded,
                            backgroundColor: Colors.red.shade700,
                            onTap: onDeactivatePressed,
                          ),
                          _ActionButton(
                            icon: Icons.delete_outline_rounded,
                            onTap: onDeletePressed,
                            isDanger: true,
                          ),
                        ],
                      ),
                    ],
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
                    _ActionButton(
                      icon: Icons.edit_outlined,
                      onTap: onEditPressed,
                    ),
                    _ActionButton(
                      icon: Icons.close_rounded,
                      backgroundColor: Colors.red.shade700,
                      onTap: onDeactivatePressed,
                    ),
                    _ActionButton(
                      icon: Icons.delete_outline_rounded,
                      onTap: onDeletePressed,
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
          child: _fullWidthRolesField(context: context, vm: vm, form: form),
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
            const SizedBox(height: 14),
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
              color: appPressablePressed(context)
                  ? AppColors.primarySurfaceAlt.withValues(alpha: 0.34)
                  : appPressableHovered(context)
                  ? AppColors.primarySurfaceAlt.withValues(alpha: 0.2)
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
        foregroundColor: const Color(0xFFD94B4B),
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
                    foregroundColor: const Color(0xFFD94B4B),
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
    this.trailingPadding = 20,
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
    this.trailingPadding = 20,
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
            color: appPressablePressed(context)
                ? AppColors.primarySurfaceAlt.withValues(alpha: 0.34)
                : appPressableHovered(context)
                ? AppColors.primarySurfaceAlt.withValues(alpha: 0.2)
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
    minimumSize: const Size(0, AdminFlowsView.controlHeight),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AdminFlowsView.surfaceRadius),
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

Widget _metaPill(String label, {bool isFilled = false}) {
  return adminMetaPill(label, isFilled: isFilled);
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
