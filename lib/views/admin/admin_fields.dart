import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/utils/functions.dart';
import 'package:webapp/view_models/admin/admin_status_form.vm.dart';
import 'package:webapp/views/admin/admin_users.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';
import 'package:webapp/widgets/shared/admin_action_confirmation.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/admin_modal_form_primitives.dart';
import 'package:webapp/widgets/shared/app_refresh_strip.dart';
import 'package:webapp/widgets/shared/app_snackbar.dart';
import 'package:webapp/widgets/status_form/status_field_editor_card.dart';

class AdminFieldsView extends StatelessWidget {
  const AdminFieldsView({super.key});

  static Future<void> confirmToggleFieldActive(
    BuildContext context,
    AdminStatusFormViewModel vm,
    StatusField field,
  ) async {
    final willBeActive = !(field.isActive ?? false);
    final confirmed = await showAdminActionConfirmation(
      context,
      title:
          '${willBeActive ? 'Activate' : 'Deactivate'} Field ${field.id ?? '-'}',
      message:
          'Are you sure you want to ${willBeActive ? 'activate' : 'deactivate'} ${field.title?.trim().isNotEmpty == true ? field.title!.trim() : 'this field'}?',
      confirmLabel: willBeActive ? 'Activate' : 'Deactivate',
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    await vm.setLibraryFieldActive(field, willBeActive);
    if (!context.mounted) {
      return;
    }
    AppSnackbar.showSuccess(
      context,
      willBeActive ? 'Field activated.' : 'Field deactivated.',
    );
  }

  static Future<void> confirmDeleteField(
    BuildContext context,
    AdminStatusFormViewModel vm,
    StatusField field,
  ) async {
    final confirmed = await showAdminActionConfirmation(
      context,
      title: 'Delete Field ${field.id ?? '-'}',
      message:
          'Are you sure you want to delete ${field.title?.trim().isNotEmpty == true ? field.title!.trim() : 'this field'}?',
      confirmLabel: 'Delete',
      isDanger: true,
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    await vm.deleteLibraryField(field);
    if (!context.mounted) {
      return;
    }
    AppSnackbar.showSuccess(context, 'Field deleted.');
  }

  static const sectionGap = 14.0;
  static const controlHeight = 52.0;
  static const surfaceRadius = 16.0;

  static String _fieldSaveMessage(
    StatusField field, {
    required bool isEditing,
    StatusField? originalField,
  }) {
    final subject = (field.title ?? field.key ?? '').trim();
    if (isEditing && originalField != null) {
      final changedFields = _changedFieldLabels(originalField, field);
      final detailedMessage = _buildDetailedUpdateMessage(
        subject: subject.isNotEmpty ? '$subject field' : 'Field',
        changes: changedFields,
      );
      if (detailedMessage != null) {
        return detailedMessage;
      }
    }

    if (subject.isNotEmpty) {
      return isEditing
          ? '$subject field has been updated.'
          : '$subject field has been created.';
    }

    return isEditing ? 'Field has been updated.' : 'Field has been created.';
  }

  static Map<String, String> _changedFieldLabels(
    StatusField before,
    StatusField after,
  ) {
    final changed = <String, String>{};

    if ((before.key ?? '').trim() != (after.key ?? '').trim()) {
      changed['key'] = after.key?.trim() ?? '-';
    }
    if ((before.type ?? '').trim() != (after.type ?? '').trim()) {
      changed['type'] = after.type?.trim() ?? '-';
    }
    if ((before.title ?? '').trim() != (after.title ?? '').trim()) {
      changed['title'] = after.title?.trim() ?? '-';
    }
    if ((before.subtitle ?? '').trim() != (after.subtitle ?? '').trim()) {
      changed['subtitle'] = after.subtitle?.trim() ?? '-';
    }
    if ((before.instructions ?? '').trim() !=
        (after.instructions ?? '').trim()) {
      changed['instructions'] = after.instructions?.trim() ?? '-';
    }
    if ((before.placeholder ?? '').trim() != (after.placeholder ?? '').trim()) {
      changed['placeholder'] = after.placeholder?.trim() ?? '-';
    }
    if ((before.required ?? false) != (after.required ?? false)) {
      changed['required'] = '${after.required ?? false}';
    }
    if (before.min != after.min) changed['min'] = '${after.min ?? 'Not set'}';
    if (before.max != after.max) changed['max'] = '${after.max ?? 'Not set'}';
    if (before.options.join('|') != after.options.join('|')) {
      changed['options'] = after.options.isEmpty
          ? '-'
          : after.options.join(', ');
    }
    if ((before.requiredError ?? '').trim() !=
        (after.requiredError ?? '').trim()) {
      changed['required error'] = after.requiredError?.trim() ?? '-';
    }
    if ((before.validationError ?? '').trim() !=
        (after.validationError ?? '').trim()) {
      changed['validation error'] = after.validationError?.trim() ?? '-';
    }
    if ((before.isActive ?? false) != (after.isActive ?? false)) {
      changed['active status'] = '${after.isActive ?? false}';
    }

    return changed;
  }

  static String? _buildDetailedUpdateMessage({
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

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<AdminStatusFormViewModel>.reactive(
      viewModelBuilder: AdminStatusFormViewModel.new,
      onViewModelReady: (vm) => vm.loadForms(),
      builder: (context, vm, child) {
        return Column(
          children: [
            AppRefreshStrip(
              isVisible: vm.isLoading,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            ),
            Expanded(child: _FieldsContent(vm: vm)),
          ],
        );
      },
    );
  }

  static Future<void> openFieldDialog(
    BuildContext context,
    AdminStatusFormViewModel vm, {
    StatusField? initialField,
    required String title,
    bool readOnly = false,
  }) async {
    final savedField = await showDialog<StatusField>(
      context: context,
      builder: (dialogContext) => _FieldEditorDialog(
        title: title,
        initialField: initialField ?? vm.draftNewField,
        generatedId: initialField == null ? vm.nextFieldId : null,
        readOnly: readOnly,
        onDraftChanged: initialField == null ? vm.updateDraftNewField : null,
      ),
    );

    if (!readOnly && savedField != null && context.mounted) {
      try {
        await vm.saveLibraryField(savedField);
        if (initialField == null) {
          vm.clearDraftNewField();
        }
        if (!context.mounted) {
          return;
        }
        AppSnackbar.showSuccess(
          context,
          _fieldSaveMessage(
            savedField,
            isEditing: initialField != null,
            originalField: initialField,
          ),
        );
      } catch (_) {
        if (!context.mounted) {
          return;
        }
        AppSnackbar.showError(context, 'Failed to save field.');
      }
    }
  }
}

class _FieldsContent extends StatefulWidget {
  const _FieldsContent({required this.vm});

  final AdminStatusFormViewModel vm;

  @override
  State<_FieldsContent> createState() => _FieldsContentState();
}

class _FieldsContentState extends State<_FieldsContent> {
  String _searchQuery = '';
  String _typeFilter = 'All';
  String _activeFilter = 'All';

  String get _emptyMessage {
    final hasAnyData = widget.vm.fields.isNotEmpty;
    if (!hasAnyData) {
      return 'No fields yet.';
    }

    final hasSearch = _searchQuery.trim().isNotEmpty;
    final activeFilterCount = [
      _typeFilter != 'All',
      _activeFilter != 'All',
    ].where((isActive) => isActive).length;

    return AdminUsersView.buildEmptyStateMessage(
      noun: 'fields',
      hasSearch: hasSearch,
      activeFilterCount: activeFilterCount,
    );
  }

  List<StatusField> get _filteredFields {
    return widget.vm.fieldLibrary.where((field) {
      final key = field.key ?? '';
      final title = field.title ?? '';
      final type = field.type ?? '-';
      final active = (field.isActive ?? false) ? 'Active' : 'Inactive';
      final haystack = '$key $title $type'.toLowerCase();

      final matchesSearch =
          _searchQuery.trim().isEmpty ||
          haystack.contains(_searchQuery.trim().toLowerCase());
      final matchesType = _typeFilter == 'All' || type == _typeFilter;
      final matchesActive = _activeFilter == 'All' || active == _activeFilter;

      return matchesSearch && matchesType && matchesActive;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 940;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FieldsToolbar(
                searchQuery: _searchQuery,
                typeFilter: _typeFilter,
                activeFilter: _activeFilter,
                onSearchChanged: (value) =>
                    setState(() => _searchQuery = value),
                onTypeChanged: (value) => setState(() => _typeFilter = value),
                onActiveChanged: (value) =>
                    setState(() => _activeFilter = value),
                onNewPressed: () => AdminFieldsView.openFieldDialog(
                  context,
                  widget.vm,
                  title: 'New Field',
                ),
              ),
              const SizedBox(height: AdminFieldsView.sectionGap),
              if (isNarrow)
                _filteredFields.isEmpty
                    ? _FieldsEmptyState(message: _emptyMessage)
                    : Column(
                        children: _filteredFields
                            .map(
                              (field) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _FieldResponsiveCard(
                                  field: field,
                                  vm: widget.vm,
                                ),
                              ),
                            )
                            .toList(),
                      )
              else
                _FieldsTable(
                  fields: _filteredFields,
                  emptyMessage: _emptyMessage,
                  vm: widget.vm,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _FieldsToolbar extends StatelessWidget {
  const _FieldsToolbar({
    required this.searchQuery,
    required this.typeFilter,
    required this.activeFilter,
    required this.onSearchChanged,
    required this.onTypeChanged,
    required this.onActiveChanged,
    required this.onNewPressed,
  });

  final String searchQuery;
  final String typeFilter;
  final String activeFilter;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<String> onActiveChanged;
  final VoidCallback onNewPressed;

  @override
  Widget build(BuildContext context) {
    return AdminListToolbar(
      controlHeight: AdminFieldsView.controlHeight,
      surfaceRadius: AdminFieldsView.surfaceRadius,
      search: _FieldsSearchField(
        initialValue: searchQuery,
        onChanged: onSearchChanged,
      ),
      filtersBuilder: (context, iconOnly) => _FieldsFiltersPanel(
        typeFilter: typeFilter,
        activeFilter: activeFilter,
        iconOnly: iconOnly,
        onTypeChanged: onTypeChanged,
        onActiveChanged: onActiveChanged,
      ),
      onNewPressed: onNewPressed,
    );
  }
}

class _FieldsSearchField extends StatefulWidget {
  const _FieldsSearchField({
    required this.initialValue,
    required this.onChanged,
  });

  final String initialValue;
  final ValueChanged<String> onChanged;

  @override
  State<_FieldsSearchField> createState() => _FieldsSearchFieldState();
}

class _FieldsSearchFieldState extends State<_FieldsSearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void didUpdateWidget(covariant _FieldsSearchField oldWidget) {
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
      controlHeight: AdminFieldsView.controlHeight,
      surfaceRadius: AdminFieldsView.surfaceRadius,
      initialValue: widget.initialValue,
      onChanged: widget.onChanged,
    );
  }
}

class _FieldsFiltersPanel extends StatefulWidget {
  const _FieldsFiltersPanel({
    required this.typeFilter,
    required this.activeFilter,
    required this.iconOnly,
    required this.onTypeChanged,
    required this.onActiveChanged,
  });

  final String typeFilter;
  final String activeFilter;
  final bool iconOnly;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<String> onActiveChanged;

  @override
  State<_FieldsFiltersPanel> createState() => _FieldsFiltersPanelState();
}

class _FieldsFiltersPanelState extends State<_FieldsFiltersPanel> {
  final FocusNode _typeFocusNode = FocusNode();
  final FocusNode _activeFocusNode = FocusNode();

  void _unfocusFilterFields() {
    _typeFocusNode.unfocus();
    _activeFocusNode.unfocus();
    FocusScope.of(context).unfocus();
  }

  @override
  void dispose() {
    _typeFocusNode.dispose();
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
      controlHeight: AdminFieldsView.controlHeight,
      surfaceRadius: AdminFieldsView.surfaceRadius,
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
                    height: AdminFieldsView.controlHeight,
                    child: _FieldsFilterDropdown(
                      label: 'Type',
                      value: widget.typeFilter,
                      focusNode: _typeFocusNode,
                      items: const [
                        'All',
                        ...AdminStatusFormViewModel.fieldTypeOptions,
                      ],
                      onChanged: widget.onTypeChanged,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: itemWidth,
                    height: AdminFieldsView.controlHeight,
                    child: _FieldsFilterDropdown(
                      label: 'Is Active',
                      value: widget.activeFilter,
                      focusNode: _activeFocusNode,
                      items: const ['All', 'Active', 'Inactive'],
                      onChanged: widget.onActiveChanged,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: itemWidth,
                    height: AdminFieldsView.controlHeight,
                    child: FilledButton(
                      onPressed: () {
                        _unfocusFilterFields();
                        widget.onTypeChanged('All');
                        widget.onActiveChanged('All');
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFD94B4B),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AdminFieldsView.surfaceRadius,
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

class _FieldsFilterDropdown extends StatelessWidget {
  const _FieldsFilterDropdown({
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
        radius: AdminFieldsView.surfaceRadius,
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

class _FieldsTable extends StatelessWidget {
  const _FieldsTable({
    required this.fields,
    required this.emptyMessage,
    required this.vm,
  });

  final List<StatusField> fields;
  final String emptyMessage;
  final AdminStatusFormViewModel vm;

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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScaler = MediaQuery.textScalerOf(context);
        final sampleId = fields
            .map((field) => field.id ?? '-')
            .fold<String>('-', _longerText);
        final sampleKey = fields
            .map((field) => field.key ?? '-')
            .fold<String>('-', _longerText);
        final sampleTitle = fields
            .map(
              (field) =>
                  field.title?.trim().isNotEmpty == true ? field.title! : '-',
            )
            .fold<String>('-', _longerText);
        final sampleType = fields
            .map((field) => field.type ?? '-')
            .fold<String>('-', _longerText);
        final sampleActive = fields
            .map((field) => (field.isActive ?? false) ? 'Active' : 'Inactive')
            .fold<String>('Inactive', _longerText);

        final idWidth = _maxTextWidth(
          context,
          textScaler,
          'ID',
          _headerStyle,
          sampleId,
          _valueStyle,
        );
        final keyWidth = _maxTextWidth(
          context,
          textScaler,
          'Key',
          _headerStyle,
          sampleKey,
          _valueStyle,
        );
        final titleWidth = _maxTextWidth(
          context,
          textScaler,
          'Title',
          _headerStyle,
          sampleTitle,
          _titleStyle,
        );
        final typeWidth = _maxTextWidth(
          context,
          textScaler,
          'Type',
          _headerStyle,
          sampleType,
          _valueStyle,
        );
        final activeWidth = _maxTextWidth(
          context,
          textScaler,
          'Active',
          _headerStyle,
          sampleActive,
          _valueStyle,
        );
        final actionsWidth = _maxValue(
          176,
          _measureTextWidth(context, textScaler, 'Actions', _headerStyle),
        );

        final resolvedIdWidth = _resolvedColumnWidth(idWidth);
        final resolvedKeyWidth = _resolvedColumnWidth(keyWidth);
        final resolvedTitleWidth = _resolvedColumnWidth(titleWidth);
        final resolvedTypeWidth = _resolvedColumnWidth(typeWidth);
        final resolvedActiveWidth = _resolvedColumnWidth(activeWidth) + 12;
        final resolvedActionsWidth = actionsWidth + _extraWidthAllowance;
        final fixedWidthTotal =
            resolvedIdWidth +
            resolvedTypeWidth +
            resolvedActiveWidth +
            resolvedActionsWidth +
            40;
        final desiredVariableWidthTotal = resolvedKeyWidth + resolvedTitleWidth;
        final availableVariableWidth = (constraints.maxWidth - fixedWidthTotal)
            .clamp(0.0, double.infinity);
        final shouldCompressVariableColumns =
            availableVariableWidth < desiredVariableWidthTotal;
        final variableWidthScale =
            shouldCompressVariableColumns && desiredVariableWidthTotal > 0
            ? availableVariableWidth / desiredVariableWidthTotal
            : 1.0;
        final effectiveKeyWidth = shouldCompressVariableColumns
            ? resolvedKeyWidth * variableWidthScale
            : resolvedKeyWidth;
        final effectiveTitleWidth = shouldCompressVariableColumns
            ? resolvedTitleWidth * variableWidthScale
            : resolvedTitleWidth;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminListHeaderBar(
              minHeight: AdminFieldsView.controlHeight,
              borderRadius: AdminFieldsView.surfaceRadius,
              child: Row(
                children: [
                  _FieldsFixedSlot(
                    width: resolvedIdWidth,
                    child: const _FieldsHeaderCell(label: 'ID'),
                  ),
                  _FieldsFixedSlot(
                    width: effectiveKeyWidth,
                    child: const _FieldsHeaderCell(label: 'Key'),
                  ),
                  _FieldsFixedSlot(
                    width: effectiveTitleWidth,
                    child: const _FieldsHeaderCell(label: 'Title'),
                  ),
                  _FieldsFixedSlot(
                    width: resolvedTypeWidth,
                    child: const _FieldsHeaderCell(label: 'Type'),
                  ),
                  _FieldsFixedSlot(
                    width: resolvedActiveWidth,
                    child: const _FieldsHeaderCell(label: 'Active'),
                  ),
                  AdminListTrailingActionsLane(
                    width: resolvedActionsWidth,
                    child: const _FieldsHeaderCell(
                      label: 'Actions',
                      alignment: Alignment.centerRight,
                      textAlign: TextAlign.right,
                      trailingPadding: 0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AdminFieldsView.sectionGap),
            if (fields.isEmpty)
              _FieldsEmptyState(message: emptyMessage)
            else
              ...fields.map(
                (field) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _FieldTableRow(
                    field: field,
                    vm: vm,
                    resolvedIdWidth: resolvedIdWidth,
                    resolvedKeyWidth: effectiveKeyWidth,
                    resolvedTitleWidth: effectiveTitleWidth,
                    resolvedTypeWidth: resolvedTypeWidth,
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

  static double _resolvedColumnWidth(double measuredWidth) =>
      AdminListMeasurements.resolvedColumnWidth(
        measuredWidth,
        trailingPadding: _defaultTrailingPadding,
        extraWidthAllowance: _extraWidthAllowance,
      );

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

  static String _longerText(String current, String candidate) =>
      AdminListMeasurements.longerText(current, candidate);
}

class _FieldTableRow extends StatelessWidget {
  const _FieldTableRow({
    required this.field,
    required this.vm,
    required this.resolvedIdWidth,
    required this.resolvedKeyWidth,
    required this.resolvedTitleWidth,
    required this.resolvedTypeWidth,
    required this.resolvedActiveWidth,
    required this.resolvedActionsWidth,
  });

  final StatusField field;
  final AdminStatusFormViewModel vm;
  final double resolvedIdWidth;
  final double resolvedKeyWidth;
  final double resolvedTitleWidth;
  final double resolvedTypeWidth;
  final double resolvedActiveWidth;
  final double resolvedActionsWidth;

  @override
  Widget build(BuildContext context) {
    return AdminListItemCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(
        children: [
          _FieldsFixedSlot(
            width: resolvedIdWidth,
            child: _FieldsBodyCell(
              child: Text(field.id ?? '-', style: _FieldsStyles.valueStyle),
            ),
          ),
          _FieldsFixedSlot(
            width: resolvedKeyWidth,
            child: _FieldsBodyCell(
              child: Text(
                field.key ?? '-',
                style: _FieldsStyles.valueStyle,
                softWrap: true,
              ),
            ),
          ),
          _FieldsFixedSlot(
            width: resolvedTitleWidth,
            child: _FieldsBodyCell(
              child: Text(
                field.title?.trim().isNotEmpty == true ? field.title! : '-',
                style: _FieldsStyles.titleStyle,
                softWrap: true,
              ),
            ),
          ),
          _FieldsFixedSlot(
            width: resolvedTypeWidth,
            child: _FieldsBodyCell(
              child: Text(field.type ?? '-', style: _FieldsStyles.valueStyle),
            ),
          ),
          _FieldsFixedSlot(
            width: resolvedActiveWidth,
            child: _FieldsBodyCell(
              child: _metaPill(
                (field.isActive ?? false) ? 'Active' : 'Inactive',
                isFilled: field.isActive ?? false,
              ),
            ),
          ),
          AdminListTrailingActionsLane(
            width: resolvedActionsWidth,
            child: _FieldsBodyCell(
              trailingPadding: 0,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MiniActionButton(
                    icon: Icons.visibility_rounded,
                    backgroundColor: Colors.yellow.shade900,
                    onTap: () => AdminFieldsView.openFieldDialog(
                      context,
                      vm,
                      initialField: field,
                      title: 'Field Preview',
                      readOnly: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _MiniActionButton(
                    icon: Icons.edit_rounded,
                    onTap: () => AdminFieldsView.openFieldDialog(
                      context,
                      vm,
                      initialField: field,
                      title: 'Edit Field',
                    ),
                  ),
                  const SizedBox(width: 8),
                  _MiniActionButton(
                    icon: (field.isActive ?? false)
                        ? Icons.close_rounded
                        : Icons.check_rounded,
                    backgroundColor: (field.isActive ?? false)
                        ? Colors.red.shade700
                        : const Color(0xFF2EAD62),
                    onTap: () => AdminFieldsView.confirmToggleFieldActive(
                      context,
                      vm,
                      field,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _MiniActionButton(
                    icon: Icons.delete_rounded,
                    backgroundColor: Colors.red.shade700,
                    onTap: () =>
                        AdminFieldsView.confirmDeleteField(context, vm, field),
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

class _FieldResponsiveCard extends StatelessWidget {
  const _FieldResponsiveCard({required this.field, required this.vm});

  final StatusField field;
  final AdminStatusFormViewModel vm;

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
          ('ID', field.id ?? '-'),
          ('Key', field.key ?? '-'),
          (
            'Title',
            field.title?.trim().isNotEmpty == true ? field.title! : '-',
          ),
          ('Type', field.type ?? '-'),
        ];
        final contentWidths = resolvedFields
            .map(
              (item) => _resolvedFieldWidth(
                context,
                textScaler,
                constraints.maxWidth,
                item.$1,
                item.$2,
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
                      (field.isActive ?? false) ? 'Active' : 'Inactive',
                      isFilled: field.isActive ?? false,
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    _metaPill(
                      (field.isActive ?? false) ? 'Active' : 'Inactive',
                      isFilled: field.isActive ?? false,
                    ),
                    const Spacer(),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 10,
                      runSpacing: 10,
                      children: _fieldActions(context),
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
                    width: useSingleColumn
                        ? constraints.maxWidth
                        : contentWidths[index],
                    centered: useSingleColumn,
                    isTitle: resolvedFields[index].$1 == 'Title',
                  ),
                ).toList(),
              ),
              if (showTopActionsRow && stackTopActions) ...[
                const SizedBox(height: 18),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: _fieldActions(context),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  List<Widget> _fieldActions(BuildContext context) => [
    _ActionButton(
      icon: Icons.visibility_rounded,
      backgroundColor: Colors.yellow.shade900,
      onTap: () => AdminFieldsView.openFieldDialog(
        context,
        vm,
        initialField: field,
        title: 'Field Preview',
        readOnly: true,
      ),
    ),
    _ActionButton(
      icon: Icons.edit_outlined,
      onTap: () => AdminFieldsView.openFieldDialog(
        context,
        vm,
        initialField: field,
        title: 'Edit Field',
      ),
    ),
    _ActionButton(
      icon: (field.isActive ?? false)
          ? Icons.close_rounded
          : Icons.check_rounded,
      backgroundColor: (field.isActive ?? false)
          ? Colors.red.shade700
          : const Color(0xFF2EAD62),
      onTap: () => AdminFieldsView.confirmToggleFieldActive(context, vm, field),
    ),
    _ActionButton(
      icon: Icons.delete_outline_rounded,
      backgroundColor: Colors.red.shade700,
      onTap: () => AdminFieldsView.confirmDeleteField(context, vm, field),
    ),
  ];

  static double _resolvedFieldWidth(
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
}

class _FieldsEmptyState extends StatelessWidget {
  const _FieldsEmptyState({required this.message});

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

class _FieldEditorDialog extends StatefulWidget {
  const _FieldEditorDialog({
    required this.title,
    this.initialField,
    this.generatedId,
    this.readOnly = false,
    this.onDraftChanged,
  });

  final String title;
  final StatusField? initialField;
  final String? generatedId;
  final bool readOnly;
  final ValueChanged<StatusField>? onDraftChanged;

  @override
  State<_FieldEditorDialog> createState() => _FieldEditorDialogState();
}

class _FieldEditorDialogState extends State<_FieldEditorDialog> {
  late StatusField _field;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _field =
        widget.initialField ??
        StatusField(
          id: widget.generatedId,
          key: null,
          required: false,
          min: null,
          max: null,
          options: const [],
          sortOrder: null,
          isActive: true,
          createdAt: now,
          updatedAt: now,
        );
    _handleDraftChanged();
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
      actions: widget.readOnly
          ? [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ]
          : [
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
        readOnly: widget.readOnly,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: StatusFieldEditorCard(
              field: _field,
              index: 0,
              fieldTypeOptions: AdminStatusFormViewModel.fieldTypeOptions,
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
                _handleDraftChanged();
              },
            ),
          ),
        ],
      ),
    );
  }

  void _handleDraftChanged() {
    widget.onDraftChanged?.call(_field);
  }
}

class _FieldsStyles {
  static const valueStyle = TextStyle(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w600,
  );

  static const titleStyle = TextStyle(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w700,
  );
}

class _FieldsHeaderCell extends StatelessWidget {
  const _FieldsHeaderCell({
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

class _FieldsFixedSlot extends StatelessWidget {
  const _FieldsFixedSlot({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AdminListFixedSlot(width: width, child: child);
  }
}

class _FieldsBodyCell extends StatelessWidget {
  const _FieldsBodyCell({
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

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.onTap,
    this.backgroundColor,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return AdminListActionButton(
      icon: icon,
      onTap: onTap,
      backgroundColor: backgroundColor,
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
    this.backgroundColor,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return AdminListActionButton(
      icon: icon,
      onTap: onTap,
      backgroundColor: backgroundColor,
      size: 36,
      iconSize: 18,
      borderRadius: 12,
    );
  }
}

Widget _metaPill(String label, {bool isFilled = false}) {
  return adminMetaPill(label, isFilled: isFilled);
}
