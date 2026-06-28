import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';
import 'package:webapp/view_models/admin/admin_vehicle_types.vm.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';
import 'package:webapp/widgets/shared/admin_action_confirmation.dart';
import 'package:webapp/widgets/shared/app_snackbar.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/admin_modal_form_primitives.dart';
import 'package:webapp/widgets/shared/app_page_loading_overlay.dart';
import 'package:webapp/widgets/shared/app_refresh_strip.dart';

class AdminVehicleTypesView extends StatefulWidget {
  const AdminVehicleTypesView({super.key});

  @override
  State<AdminVehicleTypesView> createState() => _AdminVehicleTypesViewState();
}

class _AdminVehicleTypesViewState extends State<AdminVehicleTypesView> {
  static const _toolbarControlHeight = 52.0;
  String _searchQuery = '';
  String _activeFilter = 'All';
  AdminVehicleTypesViewModel? _vm;

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
    return ViewModelBuilder<AdminVehicleTypesViewModel>.reactive(
      viewModelBuilder: AdminVehicleTypesViewModel.new,
      onViewModelReady: (vm) => vm.load(),
      builder: (context, vm, _) {
        _vm = vm;
        final filteredTypes = vm.types.where((item) {
          final haystack =
              '${item.id ?? ''} ${item.name ?? ''} ${item.slug ?? ''}'
                  .toLowerCase();
          final matchesSearch =
              _searchQuery.trim().isEmpty ||
              haystack.contains(_searchQuery.trim().toLowerCase());
          final matchesActive =
              _activeFilter == 'All' ||
              ((_activeFilter == 'Active') == (item.isActive ?? false));
          return matchesSearch && matchesActive;
        }).toList();

        return LayoutBuilder(
          builder: (context, constraints) {
            final useWideTable = constraints.maxWidth >= 940;
            final textScaler = MediaQuery.textScalerOf(context);
            final sampleId = filteredTypes
                .map((item) => item.id ?? '-')
                .fold<String>('-', AdminListMeasurements.longerText);
            final sampleName = filteredTypes
                .map((item) => item.name ?? '-')
                .fold<String>('-', AdminListMeasurements.longerText);
            final sampleSlug = filteredTypes
                .map((item) => item.slug ?? '-')
                .fold<String>('-', AdminListMeasurements.longerText);
            final sampleActive = filteredTypes
                .map((item) => (item.isActive ?? false) ? 'Active' : 'Inactive')
                .fold<String>('Inactive', AdminListMeasurements.longerText);
            final idWidth = AdminListMeasurements.maxTextWidth(
              context,
              textScaler,
              'ID',
              _headerStyle,
              sampleId,
              _valueStyle,
            );
            final nameWidth = AdminListMeasurements.maxTextWidth(
              context,
              textScaler,
              'Name',
              _headerStyle,
              sampleName,
              _titleStyle,
            );
            final slugWidth = AdminListMeasurements.maxTextWidth(
              context,
              textScaler,
              'Slug',
              _headerStyle,
              sampleSlug,
              _valueStyle,
            );
            final activeWidth = AdminListMeasurements.maxTextWidth(
              context,
              textScaler,
              'Active',
              _headerStyle,
              sampleActive,
              _valueStyle,
            );
            final actionsWidth = AdminListMeasurements.maxValue(
              176,
              AdminListMeasurements.measureTextWidth(
                context,
                textScaler,
                'Actions',
                _headerStyle,
              ),
            );
            final resolvedIdWidth = AdminListMeasurements.resolvedColumnWidth(
              idWidth,
              trailingPadding: _defaultTrailingPadding,
              extraWidthAllowance: _extraWidthAllowance,
            );
            final resolvedNameWidth = AdminListMeasurements.resolvedColumnWidth(
              nameWidth,
              trailingPadding: _defaultTrailingPadding,
              extraWidthAllowance: _extraWidthAllowance,
            );
            final resolvedSlugWidth = AdminListMeasurements.resolvedColumnWidth(
              slugWidth,
              trailingPadding: _defaultTrailingPadding,
              extraWidthAllowance: _extraWidthAllowance,
            );
            final resolvedActiveWidth =
                AdminListMeasurements.resolvedColumnWidth(
                  activeWidth,
                  trailingPadding: _defaultTrailingPadding,
                  extraWidthAllowance: _extraWidthAllowance,
                ) +
                12;
            final resolvedActionsWidth = actionsWidth + _extraWidthAllowance;

            return AppPageLoadingOverlay(
              isVisible: vm.isBusy,
              message: vm.busyMessage,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppRefreshStrip(isVisible: vm.isBusy),
                    AdminListToolbar(
                      controlHeight: _toolbarControlHeight,
                      surfaceRadius: 16,
                      search: AdminListSearchField(
                        controlHeight: _toolbarControlHeight,
                        surfaceRadius: 16,
                        initialValue: _searchQuery,
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value;
                          });
                        },
                      ),
                      filtersBuilder: (context, iconOnly) =>
                          _CatalogFiltersPanel(
                            iconOnly: iconOnly,
                            activeFilter: _activeFilter,
                            onActiveChanged: (value) {
                              setState(() {
                                _activeFilter = value;
                              });
                            },
                          ),
                      onNewPressed: () {
                        _handleNew(vm);
                      },
                    ),
                    const SizedBox(height: 12),
                    if (vm.errorMessage != null)
                      AdminListStateText(message: vm.errorMessage!)
                    else if (vm.types.isEmpty)
                      const _VehicleTypeEmptyState(
                        message: 'No vehicle types yet.',
                      )
                    else if (filteredTypes.isEmpty)
                      const _VehicleTypeEmptyState(
                        message:
                            'No vehicle types matched your current search.',
                      )
                    else ...[
                      if (useWideTable)
                        _VehicleTypeHeaderRow(
                          idWidth: resolvedIdWidth,
                          nameWidth: resolvedNameWidth,
                          slugWidth: resolvedSlugWidth,
                          activeWidth: resolvedActiveWidth,
                          actionsWidth: resolvedActionsWidth,
                        ),
                      if (useWideTable) const SizedBox(height: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: filteredTypes
                            .asMap()
                            .entries
                            .map(
                              (entry) => Padding(
                                padding: EdgeInsets.only(
                                  bottom: entry.key == filteredTypes.length - 1
                                      ? 0
                                      : 12,
                                ),
                                child: useWideTable
                                    ? _VehicleTypeDesktopRow(
                                        item: entry.value,
                                        idWidth: resolvedIdWidth,
                                        nameWidth: resolvedNameWidth,
                                        slugWidth: resolvedSlugWidth,
                                        activeWidth: resolvedActiveWidth,
                                        actionsWidth: resolvedActionsWidth,
                                      )
                                    : _VehicleTypeResponsiveCard(
                                        item: entry.value,
                                      ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _handleNew(AdminVehicleTypesViewModel vm) async {
    final created = await _showCatalogItemDialog(context, title: 'New Type');
    if (created == null || !mounted) {
      return;
    }
    await vm.saveType(created);
    if (!mounted) {
      return;
    }
    AppSnackbar.showSuccess(
      context,
      'Vehicle type added.',
    );
  }

  Future<void> _handlePreview(VehicleCatalogItem item) async {
    await _showCatalogItemDialog(
      context,
      title: 'Type ${item.id ?? '-'}',
      initialItem: item,
      readOnly: true,
    );
  }

  Future<void> _handleEdit(
    AdminVehicleTypesViewModel vm,
    VehicleCatalogItem item,
  ) async {
    final edited = await _showCatalogItemDialog(
      context,
      title: 'Edit Type',
      initialItem: item,
    );
    if (edited == null || !mounted) {
      return;
    }
    await vm.saveType(edited.copyWith(id: item.id));
    if (!mounted) {
      return;
    }
    AppSnackbar.showSuccess(
      context,
      'Vehicle type updated.',
    );
  }

  Future<void> _handleToggleActive(
    AdminVehicleTypesViewModel vm,
    VehicleCatalogItem item,
  ) async {
    final willBeActive = !(item.isActive ?? false);
    final confirmed = await showAdminActionConfirmation(
      context,
      title:
          '${willBeActive ? 'Activate' : 'Deactivate'} Type ${item.id ?? '-'}',
      message:
          'Are you sure you want to ${willBeActive ? 'activate' : 'deactivate'} ${item.name ?? 'this vehicle type'}?',
      confirmLabel: willBeActive ? 'Activate' : 'Deactivate',
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final saved = await vm.setTypeActive(item, !(item.isActive ?? false));
    if (!mounted) {
      return;
    }
    AppSnackbar.showSuccess(
      context,
      (saved.isActive ?? false)
          ? 'Vehicle type activated.'
          : 'Vehicle type deactivated.',
    );
  }

  Future<void> _handleDelete(
    AdminVehicleTypesViewModel vm,
    VehicleCatalogItem item,
  ) async {
    final confirmed = await showAdminActionConfirmation(
      context,
      title: 'Delete Type ${item.id ?? '-'}',
      message:
          'Are you sure you want to delete ${item.name ?? 'this vehicle type'}?',
      confirmLabel: 'Delete',
      isDanger: true,
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await vm.deleteType(item);
    if (!mounted) {
      return;
    }
    AppSnackbar.showSuccess(
      context,
      'Vehicle type deleted.',
    );
  }
}

class _VehicleTypeHeaderRow extends StatelessWidget {
  const _VehicleTypeHeaderRow({
    required this.idWidth,
    required this.nameWidth,
    required this.slugWidth,
    required this.activeWidth,
    required this.actionsWidth,
  });

  final double idWidth;
  final double nameWidth;
  final double slugWidth;
  final double activeWidth;
  final double actionsWidth;

  @override
  Widget build(BuildContext context) {
    return AdminListHeaderBar(
      minHeight: 52,
      borderRadius: 16,
      horizontalPadding: 16,
      child: Row(
        children: [
          AdminListFixedSlot(
            width: idWidth,
            child: const AdminListHeaderCell(label: 'ID'),
          ),
          AdminListFixedSlot(
            width: nameWidth,
            child: const AdminListHeaderCell(label: 'Name'),
          ),
          AdminListFixedSlot(
            width: slugWidth,
            child: const AdminListHeaderCell(label: 'Slug'),
          ),
          AdminListFixedSlot(
            width: activeWidth,
            child: const AdminListHeaderCell(label: 'Active'),
          ),
          AdminListTrailingActionsLane(
            width: actionsWidth,
            child: const AdminListHeaderCell(
              label: 'Actions',
              trailingPadding: 0,
              alignment: Alignment.centerRight,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _VehicleTypeDesktopRow extends StatelessWidget {
  const _VehicleTypeDesktopRow({
    required this.item,
    required this.idWidth,
    required this.nameWidth,
    required this.slugWidth,
    required this.activeWidth,
    required this.actionsWidth,
  });

  final VehicleCatalogItem item;
  final double idWidth;
  final double nameWidth;
  final double slugWidth;
  final double activeWidth;
  final double actionsWidth;

  @override
  Widget build(BuildContext context) {
    return AdminListItemCard(
      child: Row(
        children: [
          AdminListFixedSlot(
            width: idWidth,
            child: AdminListBodyCell(
              child: Text(item.id ?? '-', style: _VehicleTypeStyles.valueStyle),
            ),
          ),
          AdminListFixedSlot(
            width: nameWidth,
            child: AdminListBodyCell(
              child: Text(
                item.name ?? '-',
                style: _VehicleTypeStyles.titleStyle,
              ),
            ),
          ),
          AdminListFixedSlot(
            width: slugWidth,
            child: AdminListBodyCell(
              child: Text(
                item.slug ?? '-',
                style: _VehicleTypeStyles.valueStyle,
              ),
            ),
          ),
          AdminListFixedSlot(
            width: activeWidth,
            child: AdminListBodyCell(
              child: adminMetaPill(
                (item.isActive ?? false) ? 'Active' : 'Inactive',
                isFilled: item.isActive ?? false,
              ),
            ),
          ),
          AdminListTrailingActionsLane(
            width: actionsWidth,
            child: AdminListBodyCell(
              trailingPadding: 0,
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: _vehicleTypeActions(context, item),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VehicleTypeResponsiveCard extends StatelessWidget {
  const _VehicleTypeResponsiveCard({required this.item});

  final VehicleCatalogItem item;

  @override
  Widget build(BuildContext context) {
    return AdminListItemCard(
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useSingleColumn = constraints.maxWidth < 520;
          final stackTopActions = constraints.maxWidth < 320;
          final resolvedFields = [
            ('ID', item.id ?? '-'),
            ('Name', item.name ?? '-'),
            ('Slug', item.slug ?? '-'),
          ];

          return Column(
            crossAxisAlignment: useSingleColumn
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              if (stackTopActions)
                Column(
                  children: [
                    adminMetaPill(
                      (item.isActive ?? false) ? 'Active' : 'Inactive',
                      isFilled: item.isActive ?? false,
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    adminMetaPill(
                      (item.isActive ?? false) ? 'Active' : 'Inactive',
                      isFilled: item.isActive ?? false,
                    ),
                    const Spacer(),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 10,
                      runSpacing: 10,
                      children: _vehicleTypeActions(context, item),
                    ),
                  ],
                ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: resolvedFields
                    .map(
                      (field) => SizedBox(
                        width: useSingleColumn ? constraints.maxWidth : null,
                        child: _VehicleTypeMetaColumn(
                          label: field.$1,
                          value: field.$2,
                          isTitle: field.$1 == 'Name',
                          centered: useSingleColumn,
                        ),
                      ),
                    )
                    .toList(),
              ),
              if (stackTopActions) ...[
                const SizedBox(height: 18),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: _vehicleTypeActions(context, item),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _VehicleTypeMetaColumn extends StatelessWidget {
  const _VehicleTypeMetaColumn({
    required this.label,
    required this.value,
    this.isTitle = false,
    this.centered = false,
  });

  final String label;
  final String value;
  final bool isTitle;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.primaryColor.withValues(alpha: 0.72),
            fontWeight: FontWeight.w700,
            fontSize: 10,
            height: 1.15,
          ),
        ),
        Text(
          value,
          textAlign: centered ? TextAlign.center : TextAlign.left,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: isTitle ? FontWeight.w700 : FontWeight.w600,
            height: 1.2,
          ),
          softWrap: true,
        ),
      ],
    );
  }
}

class _VehicleTypeStyles {
  static const titleStyle = TextStyle(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );

  static const valueStyle = TextStyle(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );
}

List<Widget> _vehicleTypeActions(
  BuildContext context,
  VehicleCatalogItem item,
) => [
  AdminListActionButton(
    icon: Icons.visibility_rounded,
    backgroundColor: Colors.yellow.shade900,
    onTap: () {
      context
          .findAncestorStateOfType<_AdminVehicleTypesViewState>()
          ?._handlePreview(item);
    },
  ),
  AdminListActionButton(
    icon: Icons.edit_rounded,
    onTap: () {
      final state = context
          .findAncestorStateOfType<_AdminVehicleTypesViewState>();
      final vm = state?._vm;
      if (vm != null) {
        state?._handleEdit(vm, item);
      }
    },
  ),
  AdminListActionButton(
    icon: (item.isActive ?? false) ? Icons.close_rounded : Icons.check_rounded,
    backgroundColor: (item.isActive ?? false)
        ? AppColors.dangerStrong
        : const Color(0xFF2EAD62),
    onTap: () {
      final state = context
          .findAncestorStateOfType<_AdminVehicleTypesViewState>();
      final vm = state?._vm;
      if (vm != null) {
        state?._handleToggleActive(vm, item);
      }
    },
  ),
  AdminListActionButton(
    icon: Icons.delete_rounded,
    isDanger: true,
    onTap: () {
      final state = context
          .findAncestorStateOfType<_AdminVehicleTypesViewState>();
      final vm = state?._vm;
      if (vm != null) {
        state?._handleDelete(vm, item);
      }
    },
  ),
];

class _VehicleTypeEmptyState extends StatelessWidget {
  const _VehicleTypeEmptyState({required this.message});

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

class _CatalogFiltersPanel extends StatefulWidget {
  const _CatalogFiltersPanel({
    required this.iconOnly,
    required this.activeFilter,
    required this.onActiveChanged,
  });

  final bool iconOnly;
  final String activeFilter;
  final ValueChanged<String> onActiveChanged;

  @override
  State<_CatalogFiltersPanel> createState() => _CatalogFiltersPanelState();
}

class _CatalogFiltersPanelState extends State<_CatalogFiltersPanel> {
  final FocusNode _activeFocusNode = FocusNode();

  void _unfocusFilterFields() {
    _activeFocusNode.unfocus();
    FocusScope.of(context).unfocus();
  }

  @override
  void dispose() {
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

    return AdminListFiltersButton(
      controlHeight: adminFilterFieldMinHeight,
      surfaceRadius: 16,
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
                    width: contentWidth,
                    height: adminFilterFieldMinHeight,
                    child: _CatalogFilterDropdown(
                      label: 'Is Active',
                      value: widget.activeFilter,
                      focusNode: _activeFocusNode,
                      items: const ['All', 'Active', 'Inactive'],
                      onChanged: widget.onActiveChanged,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: contentWidth,
                    height: adminFilterFieldMinHeight,
                    child: FilledButton(
                      onPressed: () {
                        _unfocusFilterFields();
                        widget.onActiveChanged('All');
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
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

class _CatalogFilterDropdown extends StatelessWidget {
  const _CatalogFilterDropdown({
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

  @override
  Widget build(BuildContext context) {
    return AdminDropdownFormField<String>(
      initialValue: value == 'All' ? null : value,
      focusNode: focusNode,
      iconEnabledColor: AppColors.primaryColor,
      style: adminDropdownDisplayTextStyle,
      decoration: adminFormInputDecoration(
        label,
        radius: 16,
        minHeight: adminFilterFieldMinHeight,
      ),
      items: items
          .map(
            (item) => DropdownMenuItem<String>(
              value: item,
              child: Text(
                item,
                overflow: TextOverflow.ellipsis,
                style: adminDropdownDisplayTextStyle,
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

Future<VehicleCatalogItem?> _showCatalogItemDialog(
  BuildContext context, {
  required String title,
  VehicleCatalogItem? initialItem,
  bool readOnly = false,
}) async {
  final nameController = TextEditingController(text: initialItem?.name ?? '');
  final slugController = TextEditingController(text: initialItem?.slug ?? '');
  final nameFocusNode = FocusNode();
  final slugFocusNode = FocusNode();
  var isActive = initialItem?.isActive ?? true;
  final isEditing = initialItem != null;

  void submit() {
    final name = nameController.text.trim();
    final slug = slugController.text.trim();
    if (name.isEmpty || slug.isEmpty) {
      AppSnackbar.showError(context, 'Name and slug are required.');
      return;
    }
    Navigator.of(context).pop(
      VehicleCatalogItem(
        id: initialItem?.id,
        name: name,
        slug: slug,
        isActive: isActive,
        createdAt: initialItem?.createdAt,
        updatedAt: DateTime.now(),
      ),
    );
  }

  try {
    return await showDialog<VehicleCatalogItem>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AdminModalShell(
          title: title,
          contentInset: const EdgeInsets.fromLTRB(0, 16, 0, 14),
          actions: readOnly
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
                  FilledButton(onPressed: submit, child: const Text('Save')),
                ],
          child: AdminModalFormBody(
            readOnly: readOnly,
            children: [
              AdminModalFieldsSection(
                children: [
                  AdminModalTextField(
                    controller: nameController,
                    focusNode: nameFocusNode,
                    label: 'Name',
                    bottomPadding: 4,
                    textInputAction: isEditing
                        ? TextInputAction.done
                        : TextInputAction.next,
                    onSubmitted: (_) => isEditing
                        ? submit()
                        : FocusScope.of(context).requestFocus(slugFocusNode),
                  ),
                  AdminModalTextField(
                    controller: slugController,
                    focusNode: slugFocusNode,
                    label: 'Slug',
                    bottomPadding: 4,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      FocusScope.of(context).unfocus();
                      submit();
                    },
                  ),
                ],
              ),
              AdminModalToggleRow(
                title: 'Active',
                value: isActive,
                onChanged: (value) => setState(() => isActive = value),
              ),
            ],
          ),
        ),
      ),
    );
  } finally {
    nameController.dispose();
    slugController.dispose();
    nameFocusNode.dispose();
    slugFocusNode.dispose();
  }
}
