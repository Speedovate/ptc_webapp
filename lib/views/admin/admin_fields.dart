import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/utils/functions.dart';
import 'package:webapp/view_models/admin/admin_flow.vm.dart';
import 'package:webapp/views/admin/admin_users.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';
import 'package:webapp/widgets/shared/admin_action_confirmation.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/app_modal_guard.dart';
import 'package:webapp/widgets/shared/admin_modal_form_primitives.dart';
import 'package:webapp/widgets/shared/app_page_loading_overlay.dart';
import 'package:webapp/widgets/shared/app_refresh_strip.dart';
import 'package:webapp/widgets/shared/app_snackbar.dart';
import 'package:webapp/widgets/status_form/status_field_editor_card.dart';

String _formatFieldsFilterDateValue(DateTime? value) {
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

class AdminFieldsView extends StatelessWidget {
  const AdminFieldsView({super.key});

  static Future<void> confirmToggleFieldActive(
    BuildContext context,
    AdminFlowViewModel vm,
    StatusField field,
  ) async {
    if (!vm.canUpdateFields) {
      return;
    }
    final willBeActive = !(field.isActive ?? false);
    final confirmed = await showAdminActionConfirmation(
      context,
      title:
          '${willBeActive ? 'Activate' : 'Deactivate'} Field ${field.id ?? '-'}',
      message:
          'Are you sure you want to ${willBeActive ? 'activate' : 'deactivate'} ${field.title?.trim().isNotEmpty == true ? field.title!.trim() : 'this field'}?',
      confirmLabel: willBeActive ? 'Activate' : 'Deactivate',
      onConfirmAsync: () async {
        try {
          await vm.setLibraryFieldActive(field, willBeActive);
          if (!context.mounted) {
            return false;
          }
          AppSnackbar.showSuccess(
            context,
            willBeActive ? 'Field activated.' : 'Field deactivated.',
          );
          return true;
        } catch (error) {
          if (!context.mounted) {
            return false;
          }
          AppSnackbar.showError(context, error.toString());
          return false;
        }
      },
    );
    if (!confirmed || !context.mounted) {
      return;
    }
  }

  static Future<void> confirmDeleteField(
    BuildContext context,
    AdminFlowViewModel vm,
    StatusField field,
  ) async {
    if (!vm.canDeleteFields) {
      return;
    }
    final confirmed = await showAdminActionConfirmation(
      context,
      title: 'Delete Field ${field.id ?? '-'}',
      message:
          'Are you sure you want to delete ${field.title?.trim().isNotEmpty == true ? field.title!.trim() : 'this field'}?',
      confirmLabel: 'Delete',
      isDanger: true,
      onConfirmAsync: () async {
        try {
          await vm.deleteLibraryField(field);
          if (!context.mounted) {
            return false;
          }
          AppSnackbar.showSuccess(context, 'Field deleted.');
          return true;
        } catch (error) {
          if (!context.mounted) {
            return false;
          }
          AppSnackbar.showError(context, error.toString());
          return false;
        }
      },
    );
    if (!confirmed || !context.mounted) {
      return;
    }
  }

  static const toolbarSectionGap = 12.0;
  static const tableSectionGap = 14.0;
  static const controlHeight = 52.0;
  static const surfaceRadius = 16.0;

  static String _fieldSaveMessage({required bool isEditing}) {
    return isEditing ? 'Field updated.' : 'Field added.';
  }

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<AdminFlowViewModel>.reactive(
      viewModelBuilder: AdminFlowViewModel.new,
      onViewModelReady: (vm) => vm.loadFieldsPage(),
      builder: (context, vm, child) {
        return AppPageLoadingOverlay(
          isVisible: vm.showBlockingLoading,
          message: vm.busyMessage,
          child: Column(
            children: [
              AppRefreshStrip(
                isVisible: vm.showBlockingLoading,
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              ),
              Expanded(child: _FieldsContent(vm: vm)),
            ],
          ),
        );
      },
    );
  }

  static Future<void> openFieldDialog(
    BuildContext context,
    AdminFlowViewModel vm, {
    StatusField? initialField,
    required String title,
    bool readOnly = false,
  }) async {
    if (!readOnly &&
        !(initialField == null ? vm.canCreateFields : vm.canUpdateFields)) {
      return;
    }
    final savedField = await showAppDialog<StatusField>(
      context: context,
      builder: (dialogContext) => _FieldEditorDialog(
        title: title,
        initialField: initialField ?? vm.draftNewField,
        generatedId: initialField == null ? vm.nextFieldId : null,
        readOnly: readOnly,
        onDraftChanged: initialField == null ? vm.updateDraftNewField : null,
        onSaveAsync: readOnly ? null : (field) => vm.saveLibraryField(field),
      ),
    );

    if (!readOnly && savedField != null && context.mounted) {
      if (initialField == null) {
        vm.clearDraftNewField();
      }
      AppSnackbar.showSuccess(
        context,
        _fieldSaveMessage(isEditing: initialField != null),
      );
    }
  }
}

class _FieldsContent extends StatefulWidget {
  const _FieldsContent({required this.vm});

  final AdminFlowViewModel vm;

  @override
  State<_FieldsContent> createState() => _FieldsContentState();
}

class _FieldsContentState extends State<_FieldsContent> {
  String _searchQuery = '';
  String _typeFilter = 'All';
  String _activeFilter = 'All';
  DateTime? _createdStartDate;
  DateTime? _createdEndDate;
  DateTime? _updatedStartDate;
  DateTime? _updatedEndDate;

  String get _emptyMessage {
    final hasAnyData = widget.vm.fieldLibrary.isNotEmpty;
    if (!hasAnyData) {
      return 'No fields yet.';
    }

    final hasSearch = _searchQuery.trim().isNotEmpty;
    final activeFilterCount = [
      _typeFilter != 'All',
      _activeFilter != 'All',
      _createdStartDate != null,
      _createdEndDate != null,
      _updatedStartDate != null,
      _updatedEndDate != null,
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
      final matchesCreatedStart =
          _createdStartDate == null ||
          (field.createdAt != null &&
              !DateUtils.dateOnly(
                field.createdAt!,
              ).isBefore(DateUtils.dateOnly(_createdStartDate!)));
      final matchesCreatedEnd =
          _createdEndDate == null ||
          (field.createdAt != null &&
              !DateUtils.dateOnly(
                field.createdAt!,
              ).isAfter(DateUtils.dateOnly(_createdEndDate!)));
      final matchesUpdatedStart =
          _updatedStartDate == null ||
          (field.updatedAt != null &&
              !DateUtils.dateOnly(
                field.updatedAt!,
              ).isBefore(DateUtils.dateOnly(_updatedStartDate!)));
      final matchesUpdatedEnd =
          _updatedEndDate == null ||
          (field.updatedAt != null &&
              !DateUtils.dateOnly(
                field.updatedAt!,
              ).isAfter(DateUtils.dateOnly(_updatedEndDate!)));

      return matchesSearch &&
          matchesType &&
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
                createdStartDate: _createdStartDate,
                createdEndDate: _createdEndDate,
                updatedStartDate: _updatedStartDate,
                updatedEndDate: _updatedEndDate,
                onSearchChanged: (value) =>
                    setState(() => _searchQuery = value),
                onTypeChanged: (value) => setState(() => _typeFilter = value),
                onActiveChanged: (value) =>
                    setState(() => _activeFilter = value),
                onCreatedStartDateChanged: _updateCreatedStartDate,
                onCreatedEndDateChanged: _updateCreatedEndDate,
                onUpdatedStartDateChanged: _updateUpdatedStartDate,
                onUpdatedEndDateChanged: _updateUpdatedEndDate,
                onNewPressed: widget.vm.canCreateFields
                    ? () => AdminFieldsView.openFieldDialog(
                        context,
                        widget.vm,
                        title: 'New Field',
                      )
                    : null,
              ),
              const SizedBox(height: AdminFieldsView.toolbarSectionGap),
              if (isNarrow)
                _filteredFields.isEmpty
                    ? _FieldsEmptyState(message: _emptyMessage)
                    : Column(
                        children: _filteredFields
                            .asMap()
                            .entries
                            .map(
                              (entry) => Padding(
                                padding: EdgeInsets.only(
                                  bottom:
                                      entry.key == _filteredFields.length - 1
                                      ? 0
                                      : 12,
                                ),
                                child: _FieldResponsiveCard(
                                  field: entry.value,
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
    required this.createdStartDate,
    required this.createdEndDate,
    required this.updatedStartDate,
    required this.updatedEndDate,
    required this.onSearchChanged,
    required this.onTypeChanged,
    required this.onActiveChanged,
    required this.onCreatedStartDateChanged,
    required this.onCreatedEndDateChanged,
    required this.onUpdatedStartDateChanged,
    required this.onUpdatedEndDateChanged,
    required this.onNewPressed,
  });

  final String searchQuery;
  final String typeFilter;
  final String activeFilter;
  final DateTime? createdStartDate;
  final DateTime? createdEndDate;
  final DateTime? updatedStartDate;
  final DateTime? updatedEndDate;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<String> onActiveChanged;
  final ValueChanged<DateTime?> onCreatedStartDateChanged;
  final ValueChanged<DateTime?> onCreatedEndDateChanged;
  final ValueChanged<DateTime?> onUpdatedStartDateChanged;
  final ValueChanged<DateTime?> onUpdatedEndDateChanged;
  final VoidCallback? onNewPressed;

  @override
  Widget build(BuildContext context) {
    return AdminListToolbar(
      controlHeight: AdminFieldsView.controlHeight,
      surfaceRadius: AdminFieldsView.surfaceRadius,
      search: _FieldsSearchField(
        initialValue: searchQuery,
        onChanged: onSearchChanged,
      ),
      filtersBuilder: (context, iconOnly) => AdminListDynamicFiltersPanel(
        iconOnly: iconOnly,
        filters: [
          AdminListDropdownFilterConfig(
            label: 'Type',
            value: typeFilter,
            items: const ['All', ...AdminFlowViewModel.fieldTypeOptions],
            onChanged: onTypeChanged,
            displayValue: humanizeDropdownValue,
          ),
          AdminListDropdownFilterConfig(
            label: 'Is Active',
            value: activeFilter,
            items: const ['All', 'Active', 'Inactive'],
            onChanged: onActiveChanged,
          ),
          AdminListDateFilterConfig(
            label: 'Created Start',
            value: createdStartDate,
            onSelected: onCreatedStartDateChanged,
          ),
          AdminListDateFilterConfig(
            label: 'Created End',
            value: createdEndDate,
            onSelected: onCreatedEndDateChanged,
          ),
          AdminListDateFilterConfig(
            label: 'Updated Start',
            value: updatedStartDate,
            onSelected: onUpdatedStartDateChanged,
          ),
          AdminListDateFilterConfig(
            label: 'Updated End',
            value: updatedEndDate,
            onSelected: onUpdatedEndDateChanged,
          ),
        ],
        onClear: () {
          onTypeChanged('All');
          onActiveChanged('All');
          onCreatedStartDateChanged(null);
          onCreatedEndDateChanged(null);
          onUpdatedStartDateChanged(null);
          onUpdatedEndDateChanged(null);
        },
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
    required this.createdStartDate,
    required this.createdEndDate,
    required this.updatedStartDate,
    required this.updatedEndDate,
    required this.iconOnly,
    required this.onTypeChanged,
    required this.onActiveChanged,
    required this.onCreatedStartDateChanged,
    required this.onCreatedEndDateChanged,
    required this.onUpdatedStartDateChanged,
    required this.onUpdatedEndDateChanged,
  });

  final String typeFilter;
  final String activeFilter;
  final DateTime? createdStartDate;
  final DateTime? createdEndDate;
  final DateTime? updatedStartDate;
  final DateTime? updatedEndDate;
  final bool iconOnly;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<String> onActiveChanged;
  final ValueChanged<DateTime?> onCreatedStartDateChanged;
  final ValueChanged<DateTime?> onCreatedEndDateChanged;
  final ValueChanged<DateTime?> onUpdatedStartDateChanged;
  final ValueChanged<DateTime?> onUpdatedEndDateChanged;

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
                        ...AdminFlowViewModel.fieldTypeOptions,
                      ],
                      onChanged: widget.onTypeChanged,
                    ),
                  ),
                  const SizedBox(height: 8),
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
                  const SizedBox(height: 8),
                  SizedBox(
                    width: itemWidth,
                    child: _FieldsDateFilter(
                      label: 'Created Start',
                      value: widget.createdStartDate,
                      formatter: _formatFieldsFilterDateValue,
                      onSelected: widget.onCreatedStartDateChanged,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: itemWidth,
                    child: _FieldsDateFilter(
                      label: 'Created End',
                      value: widget.createdEndDate,
                      formatter: _formatFieldsFilterDateValue,
                      onSelected: widget.onCreatedEndDateChanged,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: itemWidth,
                    child: _FieldsDateFilter(
                      label: 'Updated Start',
                      value: widget.updatedStartDate,
                      formatter: _formatFieldsFilterDateValue,
                      onSelected: widget.onUpdatedStartDateChanged,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: itemWidth,
                    child: _FieldsDateFilter(
                      label: 'Updated End',
                      value: widget.updatedEndDate,
                      formatter: _formatFieldsFilterDateValue,
                      onSelected: widget.onUpdatedEndDateChanged,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: itemWidth,
                    height: adminFilterClearButtonHeight,
                    child: FilledButton(
                      onPressed: () {
                        _unfocusFilterFields();
                        widget.onTypeChanged('All');
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
        minHeight: AdminFieldsView.controlHeight,
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

class _FieldsDateFilter extends StatefulWidget {
  const _FieldsDateFilter({
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
  State<_FieldsDateFilter> createState() => _FieldsDateFilterState();
}

class _FieldsDateFilterState extends State<_FieldsDateFilter> {
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
  void didUpdateWidget(covariant _FieldsDateFilter oldWidget) {
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
      height: AdminFieldsView.controlHeight,
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
                decoration:
                    adminFormInputDecoration(
                      widget.label,
                      radius: AdminFieldsView.surfaceRadius,
                      minHeight: AdminFieldsView.controlHeight,
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

class _FieldsTable extends StatelessWidget {
  const _FieldsTable({
    required this.fields,
    required this.emptyMessage,
    required this.vm,
  });

  final List<StatusField> fields;
  final String emptyMessage;
  final AdminFlowViewModel vm;

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
        final sampleCreated = fields
            .map((field) => AdminUsersView.formatCreatedAt(field.createdAt))
            .fold<String>('-', _longerText);
        final sampleUpdated = fields
            .map((field) => AdminUsersView.formatUpdatedAt(field.updatedAt))
            .fold<String>('-', _longerText);

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
          176,
          _measureTextWidth(context, textScaler, 'Actions', _headerStyle),
        );

        final resolvedIdWidth = _resolvedColumnWidth(idWidth);
        final resolvedKeyWidth = _resolvedColumnWidth(keyWidth);
        final resolvedTitleWidth = _resolvedColumnWidth(titleWidth);
        final resolvedTypeWidth = _resolvedColumnWidth(typeWidth);
        final resolvedCreatedWidth = _resolvedColumnWidth(createdWidth);
        final resolvedUpdatedWidth = _resolvedColumnWidth(updatedWidth);
        final resolvedActionsWidth = actionsWidth + _extraWidthAllowance;
        final fixedWidthTotal =
            resolvedIdWidth +
            resolvedTypeWidth +
            resolvedCreatedWidth +
            resolvedUpdatedWidth +
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
                    width: resolvedCreatedWidth,
                    child: const _FieldsHeaderCell(label: 'Created'),
                  ),
                  _FieldsFixedSlot(
                    width: resolvedUpdatedWidth,
                    child: const _FieldsHeaderCell(label: 'Updated'),
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
            const SizedBox(height: AdminFieldsView.tableSectionGap),
            if (fields.isEmpty)
              _FieldsEmptyState(message: emptyMessage)
            else
              ...fields.asMap().entries.map(
                (entry) => Padding(
                  padding: EdgeInsets.only(
                    bottom: entry.key == fields.length - 1 ? 0 : 12,
                  ),
                  child: _FieldTableRow(
                    field: entry.value,
                    vm: vm,
                    resolvedIdWidth: resolvedIdWidth,
                    resolvedKeyWidth: effectiveKeyWidth,
                    resolvedTitleWidth: effectiveTitleWidth,
                    resolvedTypeWidth: resolvedTypeWidth,
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
    required this.resolvedCreatedWidth,
    required this.resolvedUpdatedWidth,
    required this.resolvedActionsWidth,
  });

  final StatusField field;
  final AdminFlowViewModel vm;
  final double resolvedIdWidth;
  final double resolvedKeyWidth;
  final double resolvedTitleWidth;
  final double resolvedTypeWidth;
  final double resolvedCreatedWidth;
  final double resolvedUpdatedWidth;
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
            width: resolvedCreatedWidth,
            child: _FieldsBodyCell(
              child: Text(
                AdminUsersView.formatCreatedAt(field.createdAt),
                style: _FieldsStyles.valueStyle,
                softWrap: true,
              ),
            ),
          ),
          _FieldsFixedSlot(
            width: resolvedUpdatedWidth,
            child: _FieldsBodyCell(
              child: Text(
                AdminUsersView.formatUpdatedAt(field.updatedAt),
                style: _FieldsStyles.valueStyle,
                softWrap: true,
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
                  if (vm.canUpdateFields) ...[
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
                          ? AppColors.dangerStrong
                          : const Color(0xFF2EAD62),
                      onTap: () => AdminFieldsView.confirmToggleFieldActive(
                        context,
                        vm,
                        field,
                      ),
                    ),
                  ],
                  if (vm.canDeleteFields) ...[
                    const SizedBox(width: 8),
                    _MiniActionButton(
                      icon: Icons.delete_rounded,
                      backgroundColor: AppColors.dangerStrong,
                      onTap: () => AdminFieldsView.confirmDeleteField(
                        context,
                        vm,
                        field,
                      ),
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

class _FieldResponsiveCard extends StatelessWidget {
  const _FieldResponsiveCard({required this.field, required this.vm});

  final StatusField field;
  final AdminFlowViewModel vm;

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
          ('Created', AdminUsersView.formatCreatedAt(field.createdAt)),
          ('Updated', AdminUsersView.formatUpdatedAt(field.updatedAt)),
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
              if (!stackTopActions)
                Row(
                  children: [
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
    if (vm.canUpdateFields)
      _ActionButton(
        icon: Icons.edit_outlined,
        onTap: () => AdminFieldsView.openFieldDialog(
          context,
          vm,
          initialField: field,
          title: 'Edit Field',
        ),
      ),
    if (vm.canUpdateFields)
      _ActionButton(
        icon: (field.isActive ?? false)
            ? Icons.close_rounded
            : Icons.check_rounded,
        backgroundColor: (field.isActive ?? false)
            ? AppColors.dangerStrong
            : const Color(0xFF2EAD62),
        onTap: () =>
            AdminFieldsView.confirmToggleFieldActive(context, vm, field),
      ),
    if (vm.canDeleteFields)
      _ActionButton(
        icon: Icons.delete_outline_rounded,
        backgroundColor: AppColors.dangerStrong,
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
    this.onSaveAsync,
  });

  final String title;
  final StatusField? initialField;
  final String? generatedId;
  final bool readOnly;
  final ValueChanged<StatusField>? onDraftChanged;
  final Future<void> Function(StatusField field)? onSaveAsync;

  @override
  State<_FieldEditorDialog> createState() => _FieldEditorDialogState();
}

class _FieldEditorDialogState extends State<_FieldEditorDialog> {
  late StatusField _field;
  bool _isSubmitting = false;

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
    if ((fieldType == 'dropdown' || fieldType == 'search_dropdown') &&
        !usesDynamicSource &&
        options.isEmpty) {
      return 'Add at least one static choice or pick a choices source.';
    }
    if (fieldType == 'checkbox' && options.isEmpty) {
      return 'Add at least one choice.';
    }
    final visibilityControllerKey = (_field.visibilityControllerKey ?? '')
        .trim();
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

  bool get _isEditing => widget.initialField != null;

  Future<void> _submitForm() async {
    final validationMessage = _validationMessage();
    if (validationMessage != null) {
      AppSnackbar.showError(context, validationMessage);
      return;
    }
    final result = _normalizeFieldPlaceholder(_field);
    if (widget.onSaveAsync == null) {
      Navigator.of(context).pop(result);
      return;
    }
    if (_isSubmitting) {
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await widget.onSaveAsync!(result);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppSnackbar.showError(
        context,
        userFacingErrorMessage(
          error,
          fallback: 'We could not save the field right now.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  StatusField _normalizeFieldPlaceholder(StatusField field) {
    final fieldType = (field.type ?? '').trim();
    final isRequired = field.required ?? false;
    final currentPlaceholder = field.placeholder?.trim() ?? '';
    if (isRequired && currentPlaceholder.toLowerCase() == 'optional') {
      return field.copyWith(placeholder: null);
    }
    if (fieldType == 'photo') {
      if (currentPlaceholder.isEmpty) {
        return field.copyWith(placeholder: 'Photo');
      }
      return field;
    }
    if (fieldType == 'dropdown' || fieldType == 'search_dropdown') {
      if (isRequired) {
        return field.copyWith(placeholder: null);
      }

      if (currentPlaceholder.isEmpty) {
        return field.copyWith(placeholder: 'Optional');
      }
    }

    if (fieldType != 'photo' &&
        fieldType != 'dropdown' &&
        fieldType != 'search_dropdown') {
      if (!isRequired) {
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
      actions: widget.readOnly
          ? [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ]
          : [
              TextButton(
                onPressed: _isSubmitting
                    ? null
                    : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: _isSubmitting ? null : _submitForm,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : const Text('Save'),
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
              fieldTypeOptions: AdminFlowViewModel.fieldTypeOptions,
              showContainer: false,
              sectionGap: 10,
              headerBottomGap: 12,
              toggleTopGap: 0,
              toggleGap: 0,
              onSubmit: _isEditing ? _submitForm : null,
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
