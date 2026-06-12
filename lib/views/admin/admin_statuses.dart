import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/status.dart';
import 'package:webapp/utils/functions.dart';
import 'package:webapp/view_models/admin/admin_flow.vm.dart';
import 'package:webapp/views/admin/admin_users.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';
import 'package:webapp/widgets/shared/admin_action_confirmation.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/app_mouse_pressable.dart';
import 'package:webapp/widgets/shared/admin_modal_form_primitives.dart';
import 'package:webapp/widgets/shared/app_page_loading_overlay.dart';
import 'package:webapp/widgets/shared/app_refresh_strip.dart';
import 'package:webapp/widgets/shared/app_snackbar.dart';

class AdminStatusesView extends StatelessWidget {
  const AdminStatusesView({super.key});

  static Future<void> confirmToggleStatusActive(
    BuildContext context,
    AdminFlowViewModel vm,
    Status status,
  ) async {
    final willBeActive = !(status.isActive ?? false);
    final label = status.label?.trim().isNotEmpty == true
        ? status.label!.trim()
        : 'this status';
    final confirmed = await showAdminActionConfirmation(
      context,
      title:
          '${willBeActive ? 'Activate' : 'Deactivate'} Status ${status.id ?? '-'}',
      message:
          'Are you sure you want to ${willBeActive ? 'activate' : 'deactivate'} $label?',
      confirmLabel: willBeActive ? 'Activate' : 'Deactivate',
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    await vm.setStatusActive(status, willBeActive);
    if (!context.mounted) {
      return;
    }
    AppSnackbar.showSuccess(
      context,
      willBeActive ? 'Status activated.' : 'Status deactivated.',
    );
  }

  static Future<void> confirmDeleteStatus(
    BuildContext context,
    AdminFlowViewModel vm,
    Status status,
  ) async {
    final label = status.label?.trim().isNotEmpty == true
        ? status.label!.trim()
        : 'this status';
    final confirmed = await showAdminActionConfirmation(
      context,
      title: 'Delete Status ${status.id ?? '-'}',
      message: 'Are you sure you want to delete $label?',
      confirmLabel: 'Delete',
      isDanger: true,
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    await vm.deleteStatus(status);
    if (!context.mounted) {
      return;
    }
    AppSnackbar.showSuccess(context, 'Status deleted.');
  }

  static const toolbarSectionGap = 12.0;
  static const tableSectionGap = 14.0;
  static const controlHeight = 52.0;
  static const surfaceRadius = 16.0;

  static String formatApplicableRoles(List<String> roles) {
    if (roles.isEmpty) {
      return '-';
    }
    return roles.map(humanizeDropdownValue).join(', ');
  }

  static String _statusSaveMessage(
    Status status, {
    required bool isEditing,
    Status? originalStatus,
  }) {
    final subject = (status.label ?? status.key ?? '').trim();
    if (isEditing && originalStatus != null) {
      final changedFields = _changedStatusLabels(originalStatus, status);
      final detailedMessage = _buildDetailedUpdateMessage(
        subject: subject.isNotEmpty ? '$subject status' : 'Status',
        changes: changedFields,
      );
      if (detailedMessage != null) {
        return detailedMessage;
      }
    }

    if (subject.isNotEmpty) {
      return isEditing
          ? '$subject status has been updated.'
          : '$subject status has been created.';
    }

    return isEditing ? 'Status has been updated.' : 'Status has been created.';
  }

  static Map<String, String> _changedStatusLabels(Status before, Status after) {
    final changed = <String, String>{};

    if ((before.key ?? '').trim() != (after.key ?? '').trim()) {
      changed['key'] = after.key?.trim() ?? '-';
    }
    if ((before.label ?? '').trim() != (after.label ?? '').trim()) {
      changed['label'] = after.label?.trim() ?? '-';
    }
    if ((before.description ?? '').trim() != (after.description ?? '').trim()) {
      changed['description'] = after.description?.trim() ?? '-';
    }
    if (before.applicableRoles.join('|') != after.applicableRoles.join('|')) {
      changed['applicable roles'] = formatApplicableRoles(
        after.applicableRoles,
      );
    }
    for (final role in AdminFlowViewModel.roleOptions) {
      final beforeMessage = (before.roleMessages[role] ?? '').trim();
      final afterMessage = (after.roleMessages[role] ?? '').trim();
      if (beforeMessage != afterMessage) {
        changed['${humanizeDropdownValue(role).toLowerCase()} message'] =
            afterMessage.isEmpty ? '-' : afterMessage;
      }
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
    return ViewModelBuilder<AdminFlowViewModel>.reactive(
      viewModelBuilder: AdminFlowViewModel.new,
      onViewModelReady: (vm) => vm.loadForms(),
      builder: (context, vm, child) {
        return AppPageLoadingOverlay(
          isVisible: vm.isLoading,
          message: vm.busyMessage,
          child: Column(
            children: [
              AppRefreshStrip(
                isVisible: vm.isLoading,
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              ),
              Expanded(child: _StatusesContent(vm: vm)),
            ],
          ),
        );
      },
    );
  }

  static Future<void> openStatusDialog(
    BuildContext context,
    AdminFlowViewModel vm, {
    Status? initialStatus,
    required String title,
    bool readOnly = false,
  }) async {
    final savedStatus = await showDialog<Status>(
      context: context,
      builder: (dialogContext) => _StatusEditorDialog(
        title: title,
        initialStatus: initialStatus ?? vm.draftNewStatus,
        roleOptions: AdminFlowViewModel.roleOptions,
        readOnly: readOnly,
        onDraftChanged: initialStatus == null ? vm.updateDraftNewStatus : null,
      ),
    );

    if (!readOnly && savedStatus != null && context.mounted) {
      try {
        await vm.saveStatus(savedStatus);
        if (initialStatus == null) {
          vm.clearDraftNewStatus();
        }
        if (!context.mounted) {
          return;
        }
        AppSnackbar.showSuccess(
          context,
          _statusSaveMessage(
            savedStatus,
            isEditing: initialStatus != null,
            originalStatus: initialStatus,
          ),
        );
      } catch (error) {
        if (!context.mounted) {
          return;
        }
        AppSnackbar.showError(
          context,
          userFacingErrorMessage(
            error,
            fallback: 'We could not save the status right now.',
          ),
        );
      }
    }
  }
}

class _StatusesContent extends StatefulWidget {
  const _StatusesContent({required this.vm});

  final AdminFlowViewModel vm;

  @override
  State<_StatusesContent> createState() => _StatusesContentState();
}

class _StatusesContentState extends State<_StatusesContent> {
  String _searchQuery = '';
  String _roleFilter = 'All';
  String _activeFilter = 'All';

  String get _emptyMessage {
    final hasAnyData = widget.vm.statuses.isNotEmpty;
    if (!hasAnyData) {
      return 'No statuses yet.';
    }

    final hasSearch = _searchQuery.trim().isNotEmpty;
    final activeFilterCount = [
      _roleFilter != 'All',
      _activeFilter != 'All',
    ].where((isActive) => isActive).length;

    return AdminUsersView.buildEmptyStateMessage(
      noun: 'statuses',
      hasSearch: hasSearch,
      activeFilterCount: activeFilterCount,
    );
  }

  List<Status> get _filteredStatuses {
    return widget.vm.statuses.where((status) {
      final key = status.key ?? '';
      final label = status.label ?? '';
      final roles = status.applicableRoles.join(' ');
      final active = (status.isActive ?? false) ? 'Active' : 'Inactive';
      final haystack = '$key $label $roles'.toLowerCase();

      final matchesSearch =
          _searchQuery.trim().isEmpty ||
          haystack.contains(_searchQuery.trim().toLowerCase());
      final matchesRole =
          _roleFilter == 'All' ||
          status.applicableRoles.contains(_roleFilter.toLowerCase());
      final matchesActive = _activeFilter == 'All' || active == _activeFilter;

      return matchesSearch && matchesRole && matchesActive;
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
              _StatusesToolbar(
                searchQuery: _searchQuery,
                roleFilter: _roleFilter,
                activeFilter: _activeFilter,
                onSearchChanged: (value) =>
                    setState(() => _searchQuery = value),
                onRoleChanged: (value) => setState(() => _roleFilter = value),
                onActiveChanged: (value) =>
                    setState(() => _activeFilter = value),
                onNewPressed: () => AdminStatusesView.openStatusDialog(
                  context,
                  widget.vm,
                  initialStatus: widget.vm.createDraftStatus(),
                  title: 'New Status',
                ),
              ),
              const SizedBox(height: AdminStatusesView.toolbarSectionGap),
              if (isNarrow)
                _filteredStatuses.isEmpty
                    ? _StatusesEmptyState(message: _emptyMessage)
                    : Column(
                        children: _filteredStatuses
                            .asMap()
                            .entries
                            .map(
                            (entry) => Padding(
                              padding: EdgeInsets.only(
                                bottom:
                                    entry.key == _filteredStatuses.length - 1
                                        ? 0
                                        : 12,
                              ),
                                child: _StatusResponsiveCard(
                                  status: entry.value,
                                  vm: widget.vm,
                                ),
                              ),
                            )
                            .toList(),
                      )
              else
                _StatusesTable(
                  statuses: _filteredStatuses,
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

class _StatusesToolbar extends StatelessWidget {
  const _StatusesToolbar({
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
      controlHeight: AdminStatusesView.controlHeight,
      surfaceRadius: AdminStatusesView.surfaceRadius,
      search: _StatusesSearchField(
        initialValue: searchQuery,
        onChanged: onSearchChanged,
      ),
      filtersBuilder: (context, iconOnly) => _StatusesFiltersPanel(
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

class _StatusesSearchField extends StatefulWidget {
  const _StatusesSearchField({
    required this.initialValue,
    required this.onChanged,
  });

  final String initialValue;
  final ValueChanged<String> onChanged;

  @override
  State<_StatusesSearchField> createState() => _StatusesSearchFieldState();
}

class _StatusesSearchFieldState extends State<_StatusesSearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void didUpdateWidget(covariant _StatusesSearchField oldWidget) {
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
      controlHeight: AdminStatusesView.controlHeight,
      surfaceRadius: AdminStatusesView.surfaceRadius,
      initialValue: widget.initialValue,
      onChanged: widget.onChanged,
    );
  }
}

class _StatusesFiltersPanel extends StatefulWidget {
  const _StatusesFiltersPanel({
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
  State<_StatusesFiltersPanel> createState() => _StatusesFiltersPanelState();
}

class _StatusesFiltersPanelState extends State<_StatusesFiltersPanel> {
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
      controlHeight: AdminStatusesView.controlHeight,
      surfaceRadius: AdminStatusesView.surfaceRadius,
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
                    height: AdminStatusesView.controlHeight,
                    child: _StatusesFilterDropdown(
                      label: 'Role',
                      value: widget.roleFilter,
                      focusNode: _roleFocusNode,
                      items: const ['All', 'Client', 'Driver', 'Helper'],
                      onChanged: widget.onRoleChanged,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: itemWidth,
                    height: AdminStatusesView.controlHeight,
                    child: _StatusesFilterDropdown(
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
                    height: AdminStatusesView.controlHeight,
                    child: FilledButton(
                      onPressed: () {
                        _unfocusFilterFields();
                        widget.onRoleChanged('All');
                        widget.onActiveChanged('All');
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AdminStatusesView.surfaceRadius,
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

class _StatusesFilterDropdown extends StatelessWidget {
  const _StatusesFilterDropdown({
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
        radius: AdminStatusesView.surfaceRadius,
        minHeight: AdminStatusesView.controlHeight,
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

class _StatusesTable extends StatelessWidget {
  const _StatusesTable({
    required this.statuses,
    required this.emptyMessage,
    required this.vm,
  });

  final List<Status> statuses;
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

  static const _defaultTrailingPadding = 20.0;
  static const _extraWidthAllowance = 16.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScaler = MediaQuery.textScalerOf(context);
        final sampleId = statuses
            .map((status) => status.id ?? '-')
            .fold<String>('-', _longerText);
        final sampleKey = statuses
            .map((status) => status.key ?? '-')
            .fold<String>('-', _longerText);
        final sampleLabel = statuses
            .map(
              (status) =>
                  status.label?.trim().isNotEmpty == true ? status.label! : '-',
            )
            .fold<String>('-', _longerText);
        final sampleDescription = statuses
            .map(
              (status) => status.description?.trim().isNotEmpty == true
                  ? status.description!
                  : '-',
            )
            .fold<String>('-', _longerText);
        final sampleRoles = statuses
            .map(
              (status) => AdminStatusesView.formatApplicableRoles(
                status.applicableRoles,
              ),
            )
            .fold<String>('-', _longerText);
        final sampleActive = statuses
            .map((status) => (status.isActive ?? false) ? 'Active' : 'Inactive')
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
        final labelWidth = _maxTextWidth(
          context,
          textScaler,
          'Label',
          _headerStyle,
          sampleLabel,
          _titleStyle,
        );
        final rolesWidth = _maxTextWidth(
          context,
          textScaler,
          'Roles',
          _headerStyle,
          sampleRoles,
          _valueStyle,
        );
        final descriptionWidth = _maxTextWidth(
          context,
          textScaler,
          'Description',
          _headerStyle,
          sampleDescription,
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
        final resolvedLabelWidth = _resolvedColumnWidth(labelWidth);
        final resolvedDescriptionWidth = _resolvedColumnWidth(descriptionWidth);
        final resolvedRolesWidth = _resolvedColumnWidth(rolesWidth);
        final resolvedActiveWidth = _resolvedColumnWidth(activeWidth) + 12;
        final resolvedActionsWidth = actionsWidth + _extraWidthAllowance;

        final fixedWidthTotal =
            resolvedIdWidth +
            resolvedKeyWidth +
            resolvedActiveWidth +
            resolvedActionsWidth +
            40;
        final desiredVariableWidthTotal =
            resolvedLabelWidth + resolvedDescriptionWidth + resolvedRolesWidth;
        final availableVariableWidth = (constraints.maxWidth - fixedWidthTotal)
            .clamp(0.0, double.infinity);
        final shouldCompressVariableColumns =
            availableVariableWidth < desiredVariableWidthTotal;
        final variableWidthScale =
            shouldCompressVariableColumns && desiredVariableWidthTotal > 0
            ? availableVariableWidth / desiredVariableWidthTotal
            : 1.0;
        final effectiveLabelWidth = shouldCompressVariableColumns
            ? resolvedLabelWidth * variableWidthScale
            : resolvedLabelWidth;
        final effectiveDescriptionWidth = shouldCompressVariableColumns
            ? resolvedDescriptionWidth * variableWidthScale
            : resolvedDescriptionWidth;
        final effectiveRolesWidth = shouldCompressVariableColumns
            ? resolvedRolesWidth * variableWidthScale
            : resolvedRolesWidth;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminListHeaderBar(
              minHeight: AdminStatusesView.controlHeight,
              borderRadius: AdminStatusesView.surfaceRadius,
              child: Row(
                children: [
                  _StatusesFixedSlot(
                    width: resolvedIdWidth,
                    child: const _StatusesHeaderCell(label: 'ID'),
                  ),
                  _StatusesFixedSlot(
                    width: resolvedKeyWidth,
                    child: const _StatusesHeaderCell(label: 'Key'),
                  ),
                  _StatusesFixedSlot(
                    width: effectiveLabelWidth,
                    child: const _StatusesHeaderCell(label: 'Label'),
                  ),
                  _StatusesFixedSlot(
                    width: effectiveDescriptionWidth,
                    child: const _StatusesHeaderCell(label: 'Description'),
                  ),
                  _StatusesFixedSlot(
                    width: effectiveRolesWidth,
                    child: const _StatusesHeaderCell(label: 'Roles'),
                  ),
                  _StatusesFixedSlot(
                    width: resolvedActiveWidth,
                    child: const _StatusesHeaderCell(label: 'Active'),
                  ),
                  AdminListTrailingActionsLane(
                    width: resolvedActionsWidth,
                    child: const _StatusesHeaderCell(
                      label: 'Actions',
                      alignment: Alignment.centerRight,
                      textAlign: TextAlign.right,
                      trailingPadding: 0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AdminStatusesView.tableSectionGap),
            if (statuses.isEmpty)
              _StatusesEmptyState(message: emptyMessage)
            else
              ...statuses.asMap().entries.map(
                (entry) => Padding(
                  padding: EdgeInsets.only(
                    bottom: entry.key == statuses.length - 1 ? 0 : 12,
                  ),
                  child: _StatusTableRow(
                    status: entry.value,
                    vm: vm,
                    resolvedIdWidth: resolvedIdWidth,
                    resolvedKeyWidth: resolvedKeyWidth,
                    resolvedLabelWidth: effectiveLabelWidth,
                    resolvedDescriptionWidth: effectiveDescriptionWidth,
                    resolvedRolesWidth: effectiveRolesWidth,
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

class _StatusTableRow extends StatelessWidget {
  const _StatusTableRow({
    required this.status,
    required this.vm,
    required this.resolvedIdWidth,
    required this.resolvedKeyWidth,
    required this.resolvedLabelWidth,
    required this.resolvedDescriptionWidth,
    required this.resolvedRolesWidth,
    required this.resolvedActiveWidth,
    required this.resolvedActionsWidth,
  });

  final Status status;
  final AdminFlowViewModel vm;
  final double resolvedIdWidth;
  final double resolvedKeyWidth;
  final double resolvedLabelWidth;
  final double resolvedDescriptionWidth;
  final double resolvedRolesWidth;
  final double resolvedActiveWidth;
  final double resolvedActionsWidth;

  @override
  Widget build(BuildContext context) {
    return AdminListItemCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(
        children: [
          _StatusesFixedSlot(
            width: resolvedIdWidth,
            child: _StatusesBodyCell(
              child: Text(status.id ?? '-', style: _StatusesStyles.valueStyle),
            ),
          ),
          _StatusesFixedSlot(
            width: resolvedKeyWidth,
            child: _StatusesBodyCell(
              child: Text(status.key ?? '-', style: _StatusesStyles.valueStyle),
            ),
          ),
          _StatusesFixedSlot(
            width: resolvedLabelWidth,
            child: _StatusesBodyCell(
              child: Text(
                status.label?.trim().isNotEmpty == true ? status.label! : '-',
                style: _StatusesStyles.titleStyle,
                softWrap: true,
              ),
            ),
          ),
          _StatusesFixedSlot(
            width: resolvedDescriptionWidth,
            child: _StatusesBodyCell(
              child: Text(
                status.description?.trim().isNotEmpty == true
                    ? status.description!
                    : '-',
                style: _StatusesStyles.valueStyle,
                softWrap: true,
              ),
            ),
          ),
          _StatusesFixedSlot(
            width: resolvedRolesWidth,
            child: _StatusesBodyCell(
              child: Text(
                AdminStatusesView.formatApplicableRoles(status.applicableRoles),
                style: _StatusesStyles.valueStyle,
                softWrap: true,
              ),
            ),
          ),
          _StatusesFixedSlot(
            width: resolvedActiveWidth,
            child: _StatusesBodyCell(
              child: _metaPill(
                (status.isActive ?? false) ? 'Active' : 'Inactive',
                isFilled: status.isActive ?? false,
              ),
            ),
          ),
          AdminListTrailingActionsLane(
            width: resolvedActionsWidth,
            child: _StatusesBodyCell(
              trailingPadding: 0,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MiniActionButton(
                    icon: Icons.visibility_rounded,
                    backgroundColor: Colors.yellow.shade900,
                    onTap: () => AdminStatusesView.openStatusDialog(
                      context,
                      vm,
                      initialStatus: status,
                      title: 'Status Preview',
                      readOnly: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _MiniActionButton(
                    icon: Icons.edit_rounded,
                    onTap: () => AdminStatusesView.openStatusDialog(
                      context,
                      vm,
                      initialStatus: status,
                      title: 'Edit Status',
                    ),
                  ),
                  const SizedBox(width: 8),
                  _MiniActionButton(
                    icon: (status.isActive ?? false)
                        ? Icons.close_rounded
                        : Icons.check_rounded,
                    backgroundColor: (status.isActive ?? false)
                        ? AppColors.dangerStrong
                        : const Color(0xFF2EAD62),
                    onTap: () => AdminStatusesView.confirmToggleStatusActive(
                      context,
                      vm,
                      status,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _MiniActionButton(
                    icon: Icons.delete_rounded,
                    backgroundColor: AppColors.dangerStrong,
                    onTap: () => AdminStatusesView.confirmDeleteStatus(
                      context,
                      vm,
                      status,
                    ),
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

class _StatusResponsiveCard extends StatelessWidget {
  const _StatusResponsiveCard({required this.status, required this.vm});

  final Status status;
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
          ('ID', status.id ?? '-'),
          ('Key', status.key ?? '-'),
          (
            'Label',
            status.label?.trim().isNotEmpty == true ? status.label! : '-',
          ),
          (
            'Description',
            status.description?.trim().isNotEmpty == true
                ? status.description!
                : '-',
          ),
          (
            'Roles',
            AdminStatusesView.formatApplicableRoles(status.applicableRoles),
          ),
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
                      (status.isActive ?? false) ? 'Active' : 'Inactive',
                      isFilled: status.isActive ?? false,
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    _metaPill(
                      (status.isActive ?? false) ? 'Active' : 'Inactive',
                      isFilled: status.isActive ?? false,
                    ),
                    const Spacer(),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 10,
                      runSpacing: 10,
                      children: _statusActions(context),
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
                  children: _statusActions(context),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  List<Widget> _statusActions(BuildContext context) => [
    _ActionButton(
      icon: Icons.visibility_rounded,
      backgroundColor: Colors.yellow.shade900,
      onTap: () => AdminStatusesView.openStatusDialog(
        context,
        vm,
        initialStatus: status,
        title: 'Status Preview',
        readOnly: true,
      ),
    ),
    _ActionButton(
      icon: Icons.edit_outlined,
      onTap: () => AdminStatusesView.openStatusDialog(
        context,
        vm,
        initialStatus: status,
        title: 'Edit Status',
      ),
    ),
    _ActionButton(
      icon: (status.isActive ?? false)
          ? Icons.close_rounded
          : Icons.check_rounded,
      backgroundColor: (status.isActive ?? false)
          ? AppColors.dangerStrong
          : const Color(0xFF2EAD62),
      onTap: () =>
          AdminStatusesView.confirmToggleStatusActive(context, vm, status),
    ),
    _ActionButton(
      icon: Icons.delete_outline_rounded,
      backgroundColor: AppColors.dangerStrong,
      onTap: () => AdminStatusesView.confirmDeleteStatus(context, vm, status),
    ),
  ];
}

class _StatusesEmptyState extends StatelessWidget {
  const _StatusesEmptyState({required this.message});

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

class _StatusEditorDialog extends StatefulWidget {
  const _StatusEditorDialog({
    required this.title,
    required this.roleOptions,
    this.initialStatus,
    this.readOnly = false,
    this.onDraftChanged,
  });

  final String title;
  final List<String> roleOptions;
  final Status? initialStatus;
  final bool readOnly;
  final ValueChanged<Status>? onDraftChanged;

  @override
  State<_StatusEditorDialog> createState() => _StatusEditorDialogState();
}

class _StatusEditorDialogState extends State<_StatusEditorDialog> {
  late final TextEditingController _keyController;
  late final TextEditingController _labelController;
  late final TextEditingController _descriptionController;
  late final Map<String, TextEditingController> _roleMessageControllers;
  late bool _isActive;
  late Set<String> _selectedRoles;

  @override
  void initState() {
    super.initState();
    final status = widget.initialStatus;
    _keyController = TextEditingController(text: status?.key ?? '');
    _labelController = TextEditingController(text: status?.label ?? '');
    _descriptionController = TextEditingController(
      text: status?.description ?? '',
    );
    _roleMessageControllers = {
      for (final role in widget.roleOptions)
        role: TextEditingController(text: status?.roleMessages[role] ?? ''),
    };
    _isActive = status?.isActive ?? true;
    _selectedRoles = {...?status?.applicableRoles};
    _keyController.addListener(_handleDraftChanged);
    _labelController.addListener(_handleDraftChanged);
    _descriptionController.addListener(_handleDraftChanged);
    for (final controller in _roleMessageControllers.values) {
      controller.addListener(_handleDraftChanged);
    }
    _handleDraftChanged();
  }

  @override
  void dispose() {
    _keyController.removeListener(_handleDraftChanged);
    _labelController.removeListener(_handleDraftChanged);
    _descriptionController.removeListener(_handleDraftChanged);
    for (final controller in _roleMessageControllers.values) {
      controller.removeListener(_handleDraftChanged);
      controller.dispose();
    }
    _keyController.dispose();
    _labelController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  String? _validationMessage() {
    if (_keyController.text.trim().isEmpty) {
      return 'Status key is required.';
    }
    if (_labelController.text.trim().isEmpty) {
      return 'Status label is required.';
    }
    if (_selectedRoles.isEmpty) {
      return 'Select at least one applicable role.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AdminModalShell(
      title: widget.title,
      contentInset: const EdgeInsets.fromLTRB(0, 16, 0, 16),
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
                  final base =
                      widget.initialStatus ?? const Status(applicableRoles: []);
                  Navigator.of(context).pop(_buildStatus(base));
                },
                child: const Text('Save'),
              ),
            ],
      child: AdminModalFormBody(
        readOnly: widget.readOnly,
        children: [
          AdminModalFieldsSection(
            children: [
              AdminModalTextField(
                controller: _keyController,
                label: 'Key',
                bottomPadding: 4,
              ),
              AdminModalTextField(
                controller: _labelController,
                label: 'Label',
                bottomPadding: 4,
              ),
              AdminModalTextField(
                controller: _descriptionController,
                label: 'Description',
                bottomPadding: 4,
              ),
              AdminModalFieldSlot(
                bottomPadding: 0,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Roles',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
              AdminModalFieldSlot(
                bottomPadding: 8,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: widget.roleOptions.map((role) {
                      final isSelected = _selectedRoles.contains(role);
                      return _ApplicableRoleChip(
                        label: humanizeDropdownValue(role),
                        selected: isSelected,
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selectedRoles.remove(role);
                            } else {
                              _selectedRoles.add(role);
                            }
                          });
                          _handleDraftChanged();
                        },
                      );
                    }).toList(),
                  ),
                ),
              ),
              ..._selectedRoles.toList().asMap().entries.map((entry) {
                final role = entry.value;
                return AdminModalTextField(
                  controller: _roleMessageControllers[role]!,
                  label: '${humanizeDropdownValue(role)} Message',
                  minLines: 1,
                  maxLines: 3,
                  bottomPadding: 4,
                );
              }),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: AdminModalToggleRow(
              title: 'Active',
              value: _isActive,
              onChanged: (value) => setState(() {
                _isActive = value;
                _handleDraftChanged();
              }),
            ),
          ),
        ],
      ),
    );
  }

  Status _buildStatus(Status base) {
    return base.copyWith(
      key: _keyController.text.trim(),
      label: _labelController.text.trim(),
      description: _descriptionController.text.trim(),
      applicableRoles: _selectedRoles.toList(),
      roleMessages: {
        for (final entry in _roleMessageControllers.entries)
          if (_selectedRoles.contains(entry.key) &&
              entry.value.text.trim().isNotEmpty)
            entry.key: entry.value.text.trim(),
      },
      isActive: _isActive,
    );
  }

  void _handleDraftChanged() {
    final base = widget.initialStatus ?? const Status(applicableRoles: []);
    widget.onDraftChanged?.call(_buildStatus(base));
  }
}

class _ApplicableRoleChip extends StatelessWidget {
  const _ApplicableRoleChip({
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

class _StatusesStyles {
  static const valueStyle = TextStyle(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w600,
  );

  static const titleStyle = TextStyle(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w700,
  );
}

class _StatusesHeaderCell extends StatelessWidget {
  const _StatusesHeaderCell({
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

class _StatusesBodyCell extends StatelessWidget {
  const _StatusesBodyCell({
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

class _StatusesFixedSlot extends StatelessWidget {
  const _StatusesFixedSlot({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AdminListFixedSlot(width: width, child: child);
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
