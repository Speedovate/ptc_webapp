import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';
import 'package:webapp/view_models/admin/admin_vehicle_sizes.vm.dart';
import 'package:webapp/views/admin/admin_users.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';
import 'package:webapp/widgets/shared/admin_action_confirmation.dart';
import 'package:webapp/widgets/shared/app_snackbar.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/app_modal_guard.dart';
import 'package:webapp/widgets/shared/admin_modal_form_primitives.dart';
import 'package:webapp/widgets/shared/app_page_loading_overlay.dart';
import 'package:webapp/widgets/shared/app_refresh_strip.dart';

String _formatCatalogFilterDateValue(DateTime? value) {
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

class AdminVehicleSizesView extends StatefulWidget {
  const AdminVehicleSizesView({super.key});

  @override
  State<AdminVehicleSizesView> createState() => _AdminVehicleSizesViewState();
}

class _AdminVehicleSizesViewState extends State<AdminVehicleSizesView> {
  static const _toolbarControlHeight = 52.0;
  String _searchQuery = '';
  String _activeFilter = 'All';
  DateTime? _createdStartDate;
  DateTime? _createdEndDate;
  DateTime? _updatedStartDate;
  DateTime? _updatedEndDate;
  AdminVehicleSizesViewModel? _vm;

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
    return ViewModelBuilder<AdminVehicleSizesViewModel>.reactive(
      viewModelBuilder: AdminVehicleSizesViewModel.new,
      onViewModelReady: (vm) => vm.load(),
      builder: (context, vm, _) {
        _vm = vm;
        final filteredSizes = vm.sizes.where((item) {
          final haystack =
              '${item.id ?? ''} ${item.name ?? ''} ${item.slug ?? ''}'
                  .toLowerCase();
          final matchesSearch =
              _searchQuery.trim().isEmpty ||
              haystack.contains(_searchQuery.trim().toLowerCase());
          final matchesActive =
              _activeFilter == 'All' ||
              ((_activeFilter == 'Active') == (item.isActive ?? false));
          final matchesCreatedStart =
              _createdStartDate == null ||
              (item.createdAt != null &&
                  !DateUtils.dateOnly(
                    item.createdAt!,
                  ).isBefore(DateUtils.dateOnly(_createdStartDate!)));
          final matchesCreatedEnd =
              _createdEndDate == null ||
              (item.createdAt != null &&
                  !DateUtils.dateOnly(
                    item.createdAt!,
                  ).isAfter(DateUtils.dateOnly(_createdEndDate!)));
          final matchesUpdatedStart =
              _updatedStartDate == null ||
              (item.updatedAt != null &&
                  !DateUtils.dateOnly(
                    item.updatedAt!,
                  ).isBefore(DateUtils.dateOnly(_updatedStartDate!)));
          final matchesUpdatedEnd =
              _updatedEndDate == null ||
              (item.updatedAt != null &&
                  !DateUtils.dateOnly(
                    item.updatedAt!,
                  ).isAfter(DateUtils.dateOnly(_updatedEndDate!)));
          return matchesSearch &&
              matchesActive &&
              matchesCreatedStart &&
              matchesCreatedEnd &&
              matchesUpdatedStart &&
              matchesUpdatedEnd;
        }).toList();

        return LayoutBuilder(
          builder: (context, constraints) {
            final useWideTable = constraints.maxWidth >= 940;
            final textScaler = MediaQuery.textScalerOf(context);
            final sampleId = filteredSizes
                .map((item) => item.id ?? '-')
                .fold<String>('-', AdminListMeasurements.longerText);
            final sampleName = filteredSizes
                .map((item) => item.name ?? '-')
                .fold<String>('-', AdminListMeasurements.longerText);
            final sampleSlug = filteredSizes
                .map((item) => item.slug ?? '-')
                .fold<String>('-', AdminListMeasurements.longerText);
            final sampleActive = filteredSizes
                .map((item) => (item.isActive ?? false) ? 'Active' : 'Inactive')
                .fold<String>('Inactive', AdminListMeasurements.longerText);
            final sampleCreated = filteredSizes
                .map((item) => AdminUsersView.formatCreatedAt(item.createdAt))
                .fold<String>('-', AdminListMeasurements.longerText);
            final sampleUpdated = filteredSizes
                .map((item) => AdminUsersView.formatUpdatedAt(item.updatedAt))
                .fold<String>('-', AdminListMeasurements.longerText);
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
            final createdWidth = AdminListMeasurements.maxTextWidth(
              context,
              textScaler,
              'Created',
              _headerStyle,
              sampleCreated,
              _valueStyle,
            );
            final updatedWidth = AdminListMeasurements.maxTextWidth(
              context,
              textScaler,
              'Updated',
              _headerStyle,
              sampleUpdated,
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
            final resolvedCreatedWidth =
                AdminListMeasurements.resolvedColumnWidth(
                  createdWidth,
                  trailingPadding: _defaultTrailingPadding,
                  extraWidthAllowance: _extraWidthAllowance,
                );
            final resolvedUpdatedWidth =
                AdminListMeasurements.resolvedColumnWidth(
                  updatedWidth,
                  trailingPadding: _defaultTrailingPadding,
                  extraWidthAllowance: _extraWidthAllowance,
                );
            final resolvedActionsWidth = actionsWidth + _extraWidthAllowance;

            return AppPageLoadingOverlay(
              isVisible: vm.showBlockingLoading,
              message: vm.busyMessage,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppRefreshStrip(isVisible: vm.showBlockingLoading),
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
                            createdStartDate: _createdStartDate,
                            createdEndDate: _createdEndDate,
                            updatedStartDate: _updatedStartDate,
                            updatedEndDate: _updatedEndDate,
                            onActiveChanged: (value) {
                              setState(() {
                                _activeFilter = value;
                              });
                            },
                            onCreatedStartDateChanged: (value) {
                              setState(() {
                                _createdStartDate = value;
                                if (_createdStartDate != null &&
                                    _createdEndDate != null &&
                                    _createdEndDate!.isBefore(
                                      _createdStartDate!,
                                    )) {
                                  _createdEndDate = _createdStartDate;
                                }
                              });
                            },
                            onCreatedEndDateChanged: (value) {
                              setState(() {
                                _createdEndDate = value;
                                if (_createdStartDate != null &&
                                    _createdEndDate != null &&
                                    _createdStartDate!.isAfter(
                                      _createdEndDate!,
                                    )) {
                                  _createdStartDate = _createdEndDate;
                                }
                              });
                            },
                            onUpdatedStartDateChanged: (value) {
                              setState(() {
                                _updatedStartDate = value;
                                if (_updatedStartDate != null &&
                                    _updatedEndDate != null &&
                                    _updatedEndDate!.isBefore(
                                      _updatedStartDate!,
                                    )) {
                                  _updatedEndDate = _updatedStartDate;
                                }
                              });
                            },
                            onUpdatedEndDateChanged: (value) {
                              setState(() {
                                _updatedEndDate = value;
                                if (_updatedStartDate != null &&
                                    _updatedEndDate != null &&
                                    _updatedStartDate!.isAfter(
                                      _updatedEndDate!,
                                    )) {
                                  _updatedStartDate = _updatedEndDate;
                                }
                              });
                            },
                          ),
                      onNewPressed: vm.canCreateSizes
                          ? () {
                              _handleNew(vm);
                            }
                          : null,
                    ),
                    const SizedBox(height: 12),
                    if (vm.errorMessage != null)
                      AdminListStateText(message: vm.errorMessage!)
                    else if (vm.sizes.isEmpty)
                      const _VehicleSizeEmptyState(
                        message: 'No vehicle sizes yet.',
                      )
                    else if (filteredSizes.isEmpty)
                      const _VehicleSizeEmptyState(
                        message:
                            'No vehicle sizes matched your current search.',
                      )
                    else ...[
                      if (useWideTable)
                        _VehicleSizeHeaderRow(
                          idWidth: resolvedIdWidth,
                          nameWidth: resolvedNameWidth,
                          slugWidth: resolvedSlugWidth,
                          activeWidth: resolvedActiveWidth,
                          createdWidth: resolvedCreatedWidth,
                          updatedWidth: resolvedUpdatedWidth,
                          actionsWidth: resolvedActionsWidth,
                        ),
                      if (useWideTable) const SizedBox(height: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: filteredSizes
                            .asMap()
                            .entries
                            .map(
                              (entry) => Padding(
                                padding: EdgeInsets.only(
                                  bottom: entry.key == filteredSizes.length - 1
                                      ? 0
                                      : 12,
                                ),
                                child: useWideTable
                                    ? _VehicleSizeDesktopRow(
                                        item: entry.value,
                                        idWidth: resolvedIdWidth,
                                        nameWidth: resolvedNameWidth,
                                        slugWidth: resolvedSlugWidth,
                                        activeWidth: resolvedActiveWidth,
                                        createdWidth: resolvedCreatedWidth,
                                        updatedWidth: resolvedUpdatedWidth,
                                        actionsWidth: resolvedActionsWidth,
                                      )
                                    : _VehicleSizeResponsiveCard(
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

  Future<void> _handleNew(AdminVehicleSizesViewModel vm) async {
    final created = await _showCatalogItemDialog(
      context,
      title: 'New Size',
      onSaveAsync: (item) => vm.saveSize(item),
    );
    if (created == null || !mounted) {
      return;
    }
    AppSnackbar.showSuccess(context, 'Vehicle size added.');
  }

  Future<void> _handlePreview(VehicleCatalogItem item) async {
    await _showCatalogItemDialog(
      context,
      title: 'Size ${item.id ?? '-'}',
      initialItem: item,
      readOnly: true,
    );
  }

  Future<void> _handleEdit(
    AdminVehicleSizesViewModel vm,
    VehicleCatalogItem item,
  ) async {
    if (!vm.canUpdateSizes) {
      return;
    }
    final edited = await _showCatalogItemDialog(
      context,
      title: 'Edit Size',
      initialItem: item,
      onSaveAsync: (value) => vm.saveSize(value.copyWith(id: item.id)),
    );
    if (edited == null || !mounted) {
      return;
    }
    AppSnackbar.showSuccess(context, 'Vehicle size updated.');
  }

  Future<void> _handleToggleActive(
    AdminVehicleSizesViewModel vm,
    VehicleCatalogItem item,
  ) async {
    if (!vm.canUpdateSizes) {
      return;
    }
    final willBeActive = !(item.isActive ?? false);
    final confirmed = await showAdminActionConfirmation(
      context,
      title:
          '${willBeActive ? 'Activate' : 'Deactivate'} Size ${item.id ?? '-'}',
      message:
          'Are you sure you want to ${willBeActive ? 'activate' : 'deactivate'} ${item.name ?? 'this vehicle size'}?',
      confirmLabel: willBeActive ? 'Activate' : 'Deactivate',
      onConfirmAsync: () async {
        try {
          final saved = await vm.setSizeActive(item, willBeActive);
          if (!mounted) {
            return false;
          }
          AppSnackbar.showSuccess(
            context,
            (saved.isActive ?? false)
                ? 'Vehicle size activated.'
                : 'Vehicle size deactivated.',
          );
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
    if (confirmed != true || !mounted) {
      return;
    }
  }

  Future<void> _handleDelete(
    AdminVehicleSizesViewModel vm,
    VehicleCatalogItem item,
  ) async {
    if (!vm.canDeleteSizes) {
      return;
    }
    final confirmed = await showAdminActionConfirmation(
      context,
      title: 'Delete Size ${item.id ?? '-'}',
      message:
          'Are you sure you want to delete ${item.name ?? 'this vehicle size'}?',
      confirmLabel: 'Delete',
      isDanger: true,
      onConfirmAsync: () async {
        try {
          await vm.deleteSize(item);
          if (!mounted) {
            return false;
          }
          AppSnackbar.showSuccess(context, 'Vehicle size deleted.');
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
    if (confirmed != true || !mounted) {
      return;
    }
  }
}

class _VehicleSizeHeaderRow extends StatelessWidget {
  const _VehicleSizeHeaderRow({
    required this.idWidth,
    required this.nameWidth,
    required this.slugWidth,
    required this.activeWidth,
    required this.createdWidth,
    required this.updatedWidth,
    required this.actionsWidth,
  });

  final double idWidth;
  final double nameWidth;
  final double slugWidth;
  final double activeWidth;
  final double createdWidth;
  final double updatedWidth;
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
          AdminListFixedSlot(
            width: createdWidth,
            child: const AdminListHeaderCell(label: 'Created'),
          ),
          AdminListFixedSlot(
            width: updatedWidth,
            child: const AdminListHeaderCell(label: 'Updated'),
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

class _VehicleSizeDesktopRow extends StatelessWidget {
  const _VehicleSizeDesktopRow({
    required this.item,
    required this.idWidth,
    required this.nameWidth,
    required this.slugWidth,
    required this.activeWidth,
    required this.createdWidth,
    required this.updatedWidth,
    required this.actionsWidth,
  });

  final VehicleCatalogItem item;
  final double idWidth;
  final double nameWidth;
  final double slugWidth;
  final double activeWidth;
  final double createdWidth;
  final double updatedWidth;
  final double actionsWidth;

  @override
  Widget build(BuildContext context) {
    return AdminListItemCard(
      child: Row(
        children: [
          AdminListFixedSlot(
            width: idWidth,
            child: AdminListBodyCell(
              child: Text(item.id ?? '-', style: _VehicleSizeStyles.valueStyle),
            ),
          ),
          AdminListFixedSlot(
            width: nameWidth,
            child: AdminListBodyCell(
              child: Text(
                item.name ?? '-',
                style: _VehicleSizeStyles.titleStyle,
              ),
            ),
          ),
          AdminListFixedSlot(
            width: slugWidth,
            child: AdminListBodyCell(
              child: Text(
                item.slug ?? '-',
                style: _VehicleSizeStyles.valueStyle,
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
          AdminListFixedSlot(
            width: createdWidth,
            child: AdminListBodyCell(
              child: Text(
                AdminUsersView.formatCreatedAt(item.createdAt),
                style: _VehicleSizeStyles.valueStyle,
                softWrap: true,
              ),
            ),
          ),
          AdminListFixedSlot(
            width: updatedWidth,
            child: AdminListBodyCell(
              child: Text(
                AdminUsersView.formatUpdatedAt(item.updatedAt),
                style: _VehicleSizeStyles.valueStyle,
                softWrap: true,
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
                children: _vehicleSizeActions(context, item),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VehicleSizeResponsiveCard extends StatelessWidget {
  const _VehicleSizeResponsiveCard({required this.item});

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
            ('Created', AdminUsersView.formatCreatedAt(item.createdAt)),
            ('Updated', AdminUsersView.formatUpdatedAt(item.updatedAt)),
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
                      children: _vehicleSizeActions(context, item),
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
                        child: _VehicleSizeMetaColumn(
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
                  children: _vehicleSizeActions(context, item),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _VehicleSizeMetaColumn extends StatelessWidget {
  const _VehicleSizeMetaColumn({
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

class _VehicleSizeStyles {
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

List<Widget> _vehicleSizeActions(
  BuildContext context,
  VehicleCatalogItem item,
) => [
  AdminListActionButton(
    icon: Icons.visibility_rounded,
    backgroundColor: Colors.yellow.shade900,
    onTap: () {
      context
          .findAncestorStateOfType<_AdminVehicleSizesViewState>()
          ?._handlePreview(item);
    },
  ),
  if ((context
          .findAncestorStateOfType<_AdminVehicleSizesViewState>()
          ?._vm
          ?.canUpdateSizes ??
      false))
    AdminListActionButton(
      icon: Icons.edit_rounded,
      onTap: () {
        final state = context
            .findAncestorStateOfType<_AdminVehicleSizesViewState>();
        final vm = state?._vm;
        if (vm != null) {
          state?._handleEdit(vm, item);
        }
      },
    ),
  if ((context
          .findAncestorStateOfType<_AdminVehicleSizesViewState>()
          ?._vm
          ?.canUpdateSizes ??
      false))
    AdminListActionButton(
      icon: (item.isActive ?? false)
          ? Icons.close_rounded
          : Icons.check_rounded,
      backgroundColor: (item.isActive ?? false)
          ? AppColors.dangerStrong
          : const Color(0xFF2EAD62),
      onTap: () {
        final state = context
            .findAncestorStateOfType<_AdminVehicleSizesViewState>();
        final vm = state?._vm;
        if (vm != null) {
          state?._handleToggleActive(vm, item);
        }
      },
    ),
  if ((context
          .findAncestorStateOfType<_AdminVehicleSizesViewState>()
          ?._vm
          ?.canDeleteSizes ??
      false))
    AdminListActionButton(
      icon: Icons.delete_rounded,
      isDanger: true,
      onTap: () {
        final state = context
            .findAncestorStateOfType<_AdminVehicleSizesViewState>();
        final vm = state?._vm;
        if (vm != null) {
          state?._handleDelete(vm, item);
        }
      },
    ),
];

class _VehicleSizeEmptyState extends StatelessWidget {
  const _VehicleSizeEmptyState({required this.message});

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
    required this.createdStartDate,
    required this.createdEndDate,
    required this.updatedStartDate,
    required this.updatedEndDate,
    required this.onActiveChanged,
    required this.onCreatedStartDateChanged,
    required this.onCreatedEndDateChanged,
    required this.onUpdatedStartDateChanged,
    required this.onUpdatedEndDateChanged,
  });

  final bool iconOnly;
  final String activeFilter;
  final DateTime? createdStartDate;
  final DateTime? createdEndDate;
  final DateTime? updatedStartDate;
  final DateTime? updatedEndDate;
  final ValueChanged<String> onActiveChanged;
  final ValueChanged<DateTime?> onCreatedStartDateChanged;
  final ValueChanged<DateTime?> onCreatedEndDateChanged;
  final ValueChanged<DateTime?> onUpdatedStartDateChanged;
  final ValueChanged<DateTime?> onUpdatedEndDateChanged;

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
  Widget build(BuildContext context) => AdminListDynamicFiltersPanel(
    iconOnly: widget.iconOnly,
    filters: [
      AdminListDropdownFilterConfig(
        label: 'Is Active',
        value: widget.activeFilter,
        items: const ['All', 'Active', 'Inactive'],
        onChanged: widget.onActiveChanged,
      ),
      AdminListDateFilterConfig(
        label: 'Created Start',
        value: widget.createdStartDate,
        onSelected: widget.onCreatedStartDateChanged,
        formatter: _formatCatalogFilterDateValue,
      ),
      AdminListDateFilterConfig(
        label: 'Created End',
        value: widget.createdEndDate,
        onSelected: widget.onCreatedEndDateChanged,
        formatter: _formatCatalogFilterDateValue,
      ),
      AdminListDateFilterConfig(
        label: 'Updated Start',
        value: widget.updatedStartDate,
        onSelected: widget.onUpdatedStartDateChanged,
        formatter: _formatCatalogFilterDateValue,
      ),
      AdminListDateFilterConfig(
        label: 'Updated End',
        value: widget.updatedEndDate,
        onSelected: widget.onUpdatedEndDateChanged,
        formatter: _formatCatalogFilterDateValue,
      ),
    ],
    onClear: () {
      widget.onActiveChanged('All');
      widget.onCreatedStartDateChanged(null);
      widget.onCreatedEndDateChanged(null);
      widget.onUpdatedStartDateChanged(null);
      widget.onUpdatedEndDateChanged(null);
    },
  );

  // Retained during the catalog filter rollout for quick source comparison.
  // ignore: unused_element
  Widget _buildLegacy(BuildContext context) {
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
                    child: _CatalogDateFilter(
                      label: 'Created Start',
                      value: widget.createdStartDate,
                      formatter: _formatCatalogFilterDateValue,
                      onSelected: widget.onCreatedStartDateChanged,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: contentWidth,
                    child: _CatalogDateFilter(
                      label: 'Created End',
                      value: widget.createdEndDate,
                      formatter: _formatCatalogFilterDateValue,
                      onSelected: widget.onCreatedEndDateChanged,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: contentWidth,
                    child: _CatalogDateFilter(
                      label: 'Updated Start',
                      value: widget.updatedStartDate,
                      formatter: _formatCatalogFilterDateValue,
                      onSelected: widget.onUpdatedStartDateChanged,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: contentWidth,
                    child: _CatalogDateFilter(
                      label: 'Updated End',
                      value: widget.updatedEndDate,
                      formatter: _formatCatalogFilterDateValue,
                      onSelected: widget.onUpdatedEndDateChanged,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: contentWidth,
                    height: adminFilterClearButtonHeight,
                    child: FilledButton(
                      onPressed: () {
                        _unfocusFilterFields();
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

class _CatalogDateFilter extends StatefulWidget {
  const _CatalogDateFilter({
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
  State<_CatalogDateFilter> createState() => _CatalogDateFilterState();
}

class _CatalogDateFilterState extends State<_CatalogDateFilter> {
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
  void didUpdateWidget(covariant _CatalogDateFilter oldWidget) {
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
      height: adminFilterFieldMinHeight,
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
                      radius: 16,
                      minHeight: adminFilterFieldMinHeight,
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

Future<VehicleCatalogItem?> _showCatalogItemDialog(
  BuildContext context, {
  required String title,
  VehicleCatalogItem? initialItem,
  bool readOnly = false,
  Future<void> Function(VehicleCatalogItem item)? onSaveAsync,
}) async {
  final nameController = TextEditingController(text: initialItem?.name ?? '');
  final slugController = TextEditingController(text: initialItem?.slug ?? '');
  final nameFocusNode = FocusNode();
  final slugFocusNode = FocusNode();
  var isActive = initialItem?.isActive ?? true;
  final isEditing = initialItem != null;
  var isSubmitting = false;
  void Function(VoidCallback fn)? dialogSetState;
  var didScheduleDispose = false;

  void disposeLater() {
    if (didScheduleDispose) {
      return;
    }
    didScheduleDispose = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameController.dispose();
      slugController.dispose();
      nameFocusNode.dispose();
      slugFocusNode.dispose();
    });
  }

  Future<void> submit() async {
    final name = nameController.text.trim();
    final slug = slugController.text.trim();
    if (name.isEmpty || slug.isEmpty) {
      AppSnackbar.showError(context, 'Name and slug are required.');
      return;
    }
    final result = VehicleCatalogItem(
      id: initialItem?.id,
      name: name,
      slug: slug,
      isActive: isActive,
      createdAt: initialItem?.createdAt,
      updatedAt: DateTime.now(),
    );
    if (onSaveAsync == null) {
      Navigator.of(context).pop(result);
      return;
    }
    if (isSubmitting) {
      return;
    }
    dialogSetState?.call(() => isSubmitting = true);
    try {
      await onSaveAsync(result);
      if (!context.mounted) {
        return;
      }
      Navigator.of(context).pop(result);
    } catch (error) {
      if (context.mounted) {
        AppSnackbar.showError(context, error.toString());
      }
    } finally {
      if (context.mounted) {
        dialogSetState?.call(() => isSubmitting = false);
      }
    }
  }

  final result = await showAppDialog<VehicleCatalogItem>(
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
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSubmitting ? null : submit,
                  child: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : const Text('Save'),
                ),
              ],
        child: AdminModalFormBody(
          readOnly: readOnly,
          children: [
            Builder(
              builder: (context) {
                dialogSetState = setState;
                return const SizedBox.shrink();
              },
            ),
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
                  bottomPadding: 0,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) {
                    FocusScope.of(context).unfocus();
                    submit();
                  },
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
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
  disposeLater();
  return result;
}
