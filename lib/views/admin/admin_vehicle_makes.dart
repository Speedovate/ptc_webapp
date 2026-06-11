import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/view_models/admin/admin_vehicle_makes.vm.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';
import 'package:webapp/widgets/shared/admin_action_confirmation.dart';
import 'package:webapp/widgets/shared/app_snackbar.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/admin_modal_form_primitives.dart';
import 'package:webapp/widgets/shared/app_page_loading_overlay.dart';
import 'package:webapp/widgets/shared/app_refresh_strip.dart';

class AdminVehicleMakesView extends StatefulWidget {
  const AdminVehicleMakesView({super.key});

  @override
  State<AdminVehicleMakesView> createState() => _AdminVehicleMakesViewState();
}

class _AdminVehicleMakesViewState extends State<AdminVehicleMakesView> {
  static const _toolbarControlHeight = 52.0;
  String _searchQuery = '';
  String _activeFilter = 'All';
  AdminVehicleMakesViewModel? _vm;

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
    return ViewModelBuilder<AdminVehicleMakesViewModel>.reactive(
      viewModelBuilder: AdminVehicleMakesViewModel.new,
      onViewModelReady: (vm) => vm.load(),
      builder: (context, vm, _) {
        _vm = vm;
        final filteredMakes = vm.makes.where((item) {
          final haystack =
              '${item.id ?? ''} '
                      '${item.code ?? ''} '
                      '${item.type?.name ?? ''} '
                      '${item.type?.slug ?? ''} '
                      '${item.driver?.name ?? ''} '
                      '${item.driver?.email ?? ''} '
                      '${item.driver?.phone ?? ''}'
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
            final useWideTable = constraints.maxWidth >= 1080;
            final textScaler = MediaQuery.textScalerOf(context);
            final sampleId = filteredMakes
                .map((item) => item.id ?? '-')
                .fold<String>('-', AdminListMeasurements.longerText);
            final sampleCode = filteredMakes
                .map(
                  (item) => item.code?.trim().isNotEmpty == true
                      ? item.code!.trim()
                      : '-',
                )
                .fold<String>('-', AdminListMeasurements.longerText);
            final sampleType = filteredMakes
                .map(
                  (item) => item.type?.name?.trim().isNotEmpty == true
                      ? item.type!.name!.trim()
                      : '-',
                )
                .fold<String>('-', AdminListMeasurements.longerText);
            final sampleDriver = filteredMakes
                .map(
                  (item) => item.driver?.name?.trim().isNotEmpty == true
                      ? item.driver!.name!.trim()
                      : '-',
                )
                .fold<String>('-', AdminListMeasurements.longerText);
            final sampleActive = filteredMakes
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
            final codeWidth = AdminListMeasurements.maxTextWidth(
              context,
              textScaler,
              'Code',
              _headerStyle,
              sampleCode,
              _valueStyle,
            );
            final typeWidth = AdminListMeasurements.maxTextWidth(
              context,
              textScaler,
              'Type',
              _headerStyle,
              sampleType,
              _titleStyle,
            );
            final driverWidth = AdminListMeasurements.maxTextWidth(
              context,
              textScaler,
              'Driver',
              _headerStyle,
              sampleDriver,
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
            final resolvedCodeWidth = AdminListMeasurements.resolvedColumnWidth(
              codeWidth,
              trailingPadding: _defaultTrailingPadding,
              extraWidthAllowance: _extraWidthAllowance,
            );
            final resolvedTypeWidth = AdminListMeasurements.resolvedColumnWidth(
              typeWidth,
              trailingPadding: _defaultTrailingPadding,
              extraWidthAllowance: _extraWidthAllowance,
            );
            final resolvedDriverWidth =
                AdminListMeasurements.resolvedColumnWidth(
                  driverWidth,
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
                    const SizedBox(height: 14),
                    if (vm.errorMessage != null)
                      AdminListStateText(message: vm.errorMessage!)
                    else if (vm.makes.isEmpty)
                      const _VehicleCatalogEmptyState(
                        message: 'No vehicle makes yet.',
                      )
                    else if (filteredMakes.isEmpty)
                      const _VehicleCatalogEmptyState(
                        message:
                            'No vehicle makes matched your current search.',
                      )
                    else ...[
                      if (useWideTable)
                        _VehicleMakeHeaderRow(
                          idWidth: resolvedIdWidth,
                          codeWidth: resolvedCodeWidth,
                          typeWidth: resolvedTypeWidth,
                          driverWidth: resolvedDriverWidth,
                          activeWidth: resolvedActiveWidth,
                          actionsWidth: resolvedActionsWidth,
                        ),
                      if (useWideTable) const SizedBox(height: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: filteredMakes
                            .map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: useWideTable
                                    ? _VehicleMakeDesktopRow(
                                        item: item,
                                        idWidth: resolvedIdWidth,
                                        codeWidth: resolvedCodeWidth,
                                        typeWidth: resolvedTypeWidth,
                                        driverWidth: resolvedDriverWidth,
                                        activeWidth: resolvedActiveWidth,
                                        actionsWidth: resolvedActionsWidth,
                                      )
                                    : _VehicleMakeResponsiveCard(item: item),
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

  Future<void> _handleNew(AdminVehicleMakesViewModel vm) async {
    final created = await _showMakeDialog(
      context,
      title: 'New Make',
      types: vm.types,
      drivers: vm.drivers,
    );
    if (created == null || !mounted) {
      return;
    }
    final saved = await vm.saveMake(created);
    if (!mounted) {
      return;
    }
    AppSnackbar.showSuccess(
      context,
      'Vehicle make ${saved.id ?? '-'} has been created.',
    );
  }

  Future<void> _handlePreview(VehicleMake item) async {
    await _showMakeDialog(
      context,
      title: 'Make ${item.id ?? '-'}',
      initialItem: item,
      types: _vm?.types ?? const [],
      drivers: _vm?.drivers ?? const [],
      readOnly: true,
    );
  }

  Future<void> _handleEdit(
    AdminVehicleMakesViewModel vm,
    VehicleMake item,
  ) async {
    final edited = await _showMakeDialog(
      context,
      title: 'Edit Make',
      initialItem: item,
      types: vm.types,
      drivers: vm.drivers,
    );
    if (edited == null || !mounted) {
      return;
    }
    final saved = await vm.saveMake(edited.copyWith(id: item.id));
    if (!mounted) {
      return;
    }
    AppSnackbar.showSuccess(
      context,
      'Vehicle make ${saved.id ?? '-'} has been updated.',
    );
  }

  Future<void> _handleToggleActive(
    AdminVehicleMakesViewModel vm,
    VehicleMake item,
  ) async {
    final willBeActive = !(item.isActive ?? false);
    final confirmed = await showAdminActionConfirmation(
      context,
      title:
          '${willBeActive ? 'Activate' : 'Deactivate'} Make ${item.id ?? '-'}',
      message:
          'Are you sure you want to ${willBeActive ? 'activate' : 'deactivate'} vehicle make ${item.id ?? '-'}?',
      confirmLabel: willBeActive ? 'Activate' : 'Deactivate',
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final saved = await vm.setMakeActive(item, !(item.isActive ?? false));
    if (!mounted) {
      return;
    }
    AppSnackbar.showSuccess(
      context,
      'Vehicle make ${saved.id ?? '-'} is now ${(saved.isActive ?? false) ? 'active' : 'inactive'}.',
    );
  }

  Future<void> _handleDelete(
    AdminVehicleMakesViewModel vm,
    VehicleMake item,
  ) async {
    final confirmed = await showAdminActionConfirmation(
      context,
      title: 'Delete Make ${item.id ?? '-'}',
      message:
          'Are you sure you want to delete vehicle make ${item.id ?? '-'}?',
      confirmLabel: 'Delete',
      isDanger: true,
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await vm.deleteMake(item);
    if (!mounted) {
      return;
    }
    AppSnackbar.showSuccess(
      context,
      'Vehicle make ${item.id ?? '-'} has been deleted.',
    );
  }
}

class _VehicleMakeHeaderRow extends StatelessWidget {
  const _VehicleMakeHeaderRow({
    required this.idWidth,
    required this.codeWidth,
    required this.typeWidth,
    required this.driverWidth,
    required this.activeWidth,
    required this.actionsWidth,
  });

  final double idWidth;
  final double codeWidth;
  final double typeWidth;
  final double driverWidth;
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
            width: codeWidth,
            child: const AdminListHeaderCell(label: 'Code'),
          ),
          AdminListFixedSlot(
            width: typeWidth,
            child: const AdminListHeaderCell(label: 'Type'),
          ),
          AdminListFixedSlot(
            width: driverWidth,
            child: const AdminListHeaderCell(label: 'Driver'),
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

class _VehicleMakeDesktopRow extends StatelessWidget {
  const _VehicleMakeDesktopRow({
    required this.item,
    required this.idWidth,
    required this.codeWidth,
    required this.typeWidth,
    required this.driverWidth,
    required this.activeWidth,
    required this.actionsWidth,
  });

  final VehicleMake item;
  final double idWidth;
  final double codeWidth;
  final double typeWidth;
  final double driverWidth;
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
              child: Text(item.id ?? '-', style: _VehicleMakeStyles.valueStyle),
            ),
          ),
          AdminListFixedSlot(
            width: codeWidth,
            child: AdminListBodyCell(
              child: Text(
                item.code?.trim().isNotEmpty == true ? item.code!.trim() : '-',
                style: _VehicleMakeStyles.valueStyle,
              ),
            ),
          ),
          AdminListFixedSlot(
            width: typeWidth,
            child: AdminListBodyCell(
              child: Text(
                item.type?.name?.trim().isNotEmpty == true
                    ? item.type!.name!.trim()
                    : '-',
                style: _VehicleMakeStyles.titleStyle,
              ),
            ),
          ),
          AdminListFixedSlot(
            width: driverWidth,
            child: AdminListBodyCell(
              child: Text(
                item.driver?.name?.trim().isNotEmpty == true
                    ? item.driver!.name!.trim()
                    : '-',
                style: _VehicleMakeStyles.valueStyle,
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
                children: _vehicleMakeActions(context, item),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VehicleMakeResponsiveCard extends StatelessWidget {
  const _VehicleMakeResponsiveCard({required this.item});

  final VehicleMake item;

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
            (
              'Code',
              item.code?.trim().isNotEmpty == true ? item.code!.trim() : '-',
            ),
            (
              'Type',
              item.type?.name?.trim().isNotEmpty == true
                  ? item.type!.name!.trim()
                  : '-',
            ),
            (
              'Driver',
              item.driver?.name?.trim().isNotEmpty == true
                  ? item.driver!.name!.trim()
                  : '-',
            ),
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
                      children: _vehicleMakeActions(context, item),
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
                        child: _VehicleMakeMetaColumn(
                          label: field.$1,
                          value: field.$2,
                          isTitle: field.$1 == 'Type',
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
                  children: _vehicleMakeActions(context, item),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _VehicleMakeMetaColumn extends StatelessWidget {
  const _VehicleMakeMetaColumn({
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

class _VehicleMakeStyles {
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

List<Widget> _vehicleMakeActions(BuildContext context, VehicleMake item) => [
  AdminListActionButton(
    icon: Icons.visibility_rounded,
    backgroundColor: Colors.yellow.shade900,
    onTap: () {
      context
          .findAncestorStateOfType<_AdminVehicleMakesViewState>()
          ?._handlePreview(item);
    },
  ),
  AdminListActionButton(
    icon: Icons.edit_rounded,
    onTap: () {
      final state = context
          .findAncestorStateOfType<_AdminVehicleMakesViewState>();
      final vm = state?._vm;
      if (vm != null) {
        state?._handleEdit(vm, item);
      }
    },
  ),
  AdminListActionButton(
    icon: (item.isActive ?? false) ? Icons.close_rounded : Icons.check_rounded,
    backgroundColor: (item.isActive ?? false)
        ? Colors.red.shade700
        : const Color(0xFF2EAD62),
    onTap: () {
      final state = context
          .findAncestorStateOfType<_AdminVehicleMakesViewState>();
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
          .findAncestorStateOfType<_AdminVehicleMakesViewState>();
      final vm = state?._vm;
      if (vm != null) {
        state?._handleDelete(vm, item);
      }
    },
  ),
];

class _VehicleCatalogEmptyState extends StatelessWidget {
  const _VehicleCatalogEmptyState({required this.message});

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
                        backgroundColor: const Color(0xFFD94B4B),
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
          .where((item) => item != 'All')
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

Future<VehicleMake?> _showMakeDialog(
  BuildContext context, {
  required String title,
  VehicleMake? initialItem,
  required List<VehicleCatalogItem> types,
  required List<UserModel> drivers,
  bool readOnly = false,
}) async {
  final codeController = TextEditingController(text: initialItem?.code ?? '');
  String? typeId = initialItem?.type?.id;
  String? driverId = initialItem?.driver?.id;
  var isActive = initialItem?.isActive ?? true;

  List<DropdownMenuItem<String>> buildTypeItems() {
    final items = <DropdownMenuItem<String>>[];
    final seen = <String>{};

    void addItem(String? value, String label) {
      final normalized = value?.trim();
      if (normalized == null || normalized.isEmpty || !seen.add(normalized)) {
        return;
      }
      items.add(
        DropdownMenuItem<String>(
          value: normalized,
          child: Text(label, style: adminDropdownDisplayTextStyle),
        ),
      );
    }

    addItem(initialItem?.type?.id, (initialItem?.type?.name ?? '').trim());
    for (final item in types) {
      addItem(
        item.id,
        (item.name ?? '').trim().isNotEmpty ? item.name!.trim() : '-',
      );
    }
    return items;
  }

  List<DropdownMenuItem<String>> buildDriverItems() {
    final items = <DropdownMenuItem<String>>[];
    final seen = <String>{};

    void addItem(UserModel? user) {
      final normalized = user?.id?.trim();
      if (normalized == null || normalized.isEmpty || !seen.add(normalized)) {
        return;
      }
      final name = (user?.name ?? '').trim();
      final phone = (user?.phone ?? '').trim();
      final label = name.isNotEmpty
          ? (phone.isNotEmpty ? '$name | $phone' : name)
          : (phone.isNotEmpty ? phone : 'Driver');
      items.add(
        DropdownMenuItem<String>(
          value: normalized,
          child: Text(label, style: adminDropdownDisplayTextStyle),
        ),
      );
    }

    addItem(initialItem?.driver);
    for (final item in drivers) {
      addItem(item);
    }
    return items;
  }

  return showDialog<VehicleMake>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AdminModalShell(
        title: title,
        contentInset: const EdgeInsets.fromLTRB(0, 16, 0, 16),
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
                FilledButton(
                  onPressed: () {
                    final selectedType = types
                        .where((item) => item.id == typeId)
                        .cast<VehicleCatalogItem?>()
                        .firstWhere(
                          (_) => true,
                          orElse: () => initialItem?.type,
                        );
                    final selectedDriver = drivers
                        .where((item) => item.id == driverId)
                        .cast<UserModel?>()
                        .firstWhere(
                          (_) => true,
                          orElse: () => initialItem?.driver,
                        );
                    if (selectedType == null || selectedDriver == null) {
                      AppSnackbar.showError(
                        context,
                        'Code, assigned type, and driver are required.',
                      );
                      return;
                    }
                    final code = codeController.text.trim();
                    if (code.isEmpty) {
                      AppSnackbar.showError(
                        context,
                        'Code, assigned type, and driver are required.',
                      );
                      return;
                    }
                    Navigator.of(context).pop(
                      VehicleMake(
                        id: initialItem?.id,
                        code: code,
                        type: selectedType,
                        driver: selectedDriver,
                        isActive: isActive,
                        createdAt: initialItem?.createdAt,
                        updatedAt: DateTime.now(),
                      ),
                    );
                  },
                  child: const Text('Save'),
                ),
              ],
        child: AdminModalFormBody(
          readOnly: readOnly,
          children: [
            AdminModalFieldsSection(
              children: [
                AdminModalTextField(
                  controller: codeController,
                  label: 'Code',
                  bottomPadding: 4,
                ),
                AdminModalDropdownField<String>(
                  label: 'Type',
                  initialValue: typeId,
                  bottomPadding: 6,
                  iconEnabledColor: AppColors.primaryColor,
                  disabledTapMessage: 'No active vehicle types available.',
                  items: buildTypeItems(),
                  onChanged: (value) => setState(() => typeId = value),
                ),
                AdminModalDropdownField<String>(
                  label: 'Driver',
                  initialValue: driverId,
                  bottomPadding: 0,
                  iconEnabledColor: AppColors.primaryColor,
                  disabledTapMessage: 'No online drivers available.',
                  items: buildDriverItems(),
                  onChanged: (value) => setState(() => driverId = value),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: AdminModalToggleRow(
                title: 'Active',
                value: isActive,
                onChanged: (value) => setState(() => isActive = value),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
