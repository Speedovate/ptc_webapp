import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/dispatcher_access_config.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/requests/role_access.request.dart';
import 'package:webapp/services/app_warmup_service.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:webapp/utils/functions.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/admin_modal_form_primitives.dart';
import 'package:webapp/widgets/shared/app_modal_guard.dart';
import 'package:webapp/widgets/shared/app_page_loading_overlay.dart';
import 'package:webapp/widgets/shared/app_snackbar.dart';

class AdminAccessView extends StatefulWidget {
  const AdminAccessView({super.key});

  @override
  State<AdminAccessView> createState() => _AdminAccessViewState();
}

class _AdminAccessViewState extends State<AdminAccessView> {
  static const double _defaultTrailingPadding = 12;
  static const double _extraWidthAllowance = 20;
  static const double _actionsWidth = 176;
  static const double _tableSectionGap = 12;
  static const double _toolbarControlHeight = 52;
  static const double _toolbarSurfaceRadius = 16;
  static const Set<String> _hiddenRoleEditorCapabilities = {
    DispatcherAccessCapability.supportRead,
    DispatcherAccessCapability.supportCreate,
    DispatcherAccessCapability.supportUpdate,
    DispatcherAccessCapability.profileRead,
    DispatcherAccessCapability.profileUpdate,
    DispatcherAccessCapability.syncUpdate,
  };
  final RoleAccessService _service = RoleAccessService.instance;
  final AuthRequest _authRequest = AuthRequest.instance;
  final AppWarmupService _warmupService = AppWarmupService.instance;
  StreamSubscription<void>? _roleAccessCacheUpdatesSubscription;
  StreamSubscription<void>? _usersCacheUpdatesSubscription;
  static List<_AccessRoleEntry> _cachedRoles = const [];
  static String? _cachedErrorMessage;
  static bool _cachedHasCompletedInitialLoad = false;

  bool _isLoading = true;
  bool _hasCompletedInitialLoad = false;
  String? _errorMessage;
  String _searchQuery = '';
  List<_AccessRoleEntry> _roles = List<_AccessRoleEntry>.from(_cachedRoles);
  bool _isRealtimeReloading = false;

  bool get _canReadRoles => _service.canAccess(
    DispatcherAccessCapability.roleAccessRead,
  );

  bool get _canUpdateRoles => _service.canAccess(
    DispatcherAccessCapability.roleAccessUpdate,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hasCompletedInitialLoad == _cachedHasCompletedInitialLoad &&
        _errorMessage == null &&
        _cachedErrorMessage != null) {
      _errorMessage = _cachedErrorMessage;
    }
    _hasCompletedInitialLoad = _cachedHasCompletedInitialLoad;
  }

  @override
  void initState() {
    super.initState();
    _ensureRealtimeSubscriptions();
    _load();
  }

  void _ensureRealtimeSubscriptions() {
    _roleAccessCacheUpdatesSubscription ??= RoleAccessRequest.instance
        .watchRoleAccessCacheUpdates()
        .listen((_) {
          unawaited(_reloadFromRealtime());
        });
    _usersCacheUpdatesSubscription ??= AuthRequest.instance
        .watchUsersCacheUpdates()
        .listen((_) {
          unawaited(_reloadFromRealtime());
        });
  }

  Future<void> _reloadFromRealtime() async {
    if (_isRealtimeReloading || !mounted) {
      return;
    }
    _isRealtimeReloading = true;
    try {
      await _load();
    } finally {
      _isRealtimeReloading = false;
    }
  }

  @override
  void dispose() {
    _roleAccessCacheUpdatesSubscription?.cancel();
    _usersCacheUpdatesSubscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_canReadRoles) {
      setState(() {
        _isLoading = false;
        _hasCompletedInitialLoad = true;
        _errorMessage = 'You do not have access to view roles.';
        _roles = const [];
      });
      return;
    }
    final hasSharedRoleAccess = _service.roleAccessConfigs.isNotEmpty;
    final hasSharedUsers = AuthRequest.hasResolvedUsers;
    if (_roles.isEmpty && hasSharedRoleAccess && hasSharedUsers) {
      final sharedRoleKeys = <String>{
        ..._service.roleAccessConfigs.map((config) => config.role),
        ...AuthRequest.hydratedUsersSnapshot.map((user) => user.role ?? ''),
      }
          .map(_normalizeRoleKey)
          .whereType<String>()
          .toSet()
          .toList(growable: false);
      _roles = _buildRoleEntries(sharedRoleKeys);
    }
    final seededRoleKeys = <String>{
      ...builtInRoleKeys,
      ..._service.knownRoleKeys,
      ..._roles.map((role) => role.roleKey),
    }.where((role) => role.trim().isNotEmpty).toList(growable: false);
    final shouldShowBlockingLoading =
        !_hasCompletedInitialLoad &&
        _roles.isEmpty &&
        _cachedRoles.isEmpty &&
        !(hasSharedRoleAccess && hasSharedUsers);
    _log(
      'load start visible=${!shouldShowBlockingLoading} local=${_roles.length} cached=${_cachedRoles.length} sharedRoles=$hasSharedRoleAccess sharedUsers=$hasSharedUsers',
    );
    setState(() {
      _isLoading = shouldShowBlockingLoading;
      _errorMessage = null;
      _roles = _buildRoleEntries(seededRoleKeys);
    });
    try {
      await _warmupService.warmRoleAccess().timeout(
        const Duration(seconds: 6),
        onTimeout: () {
        },
      );
      await _warmupService.warmUsers().timeout(
        const Duration(seconds: 6),
        onTimeout: () {
        },
      );
      final users = AuthRequest.hasResolvedUsers
          ? AuthRequest.hydratedUsersSnapshot
          : await _authRequest.getUsers().timeout(
              const Duration(seconds: 6),
              onTimeout: () {
                return const [];
              },
            );
      final roleKeys = <String>{
        ..._service.roleAccessConfigs.map((config) => config.role),
        ...users.map((user) => (user.role ?? '').trim()),
      }
          .map(_normalizeRoleKey)
          .whereType<String>()
          .toSet()
          .toList();

      _roles = _buildRoleEntries(roleKeys);
      _log('load resolved roles=${_roles.length} users=${users.length}');
      _cachedRoles = List<_AccessRoleEntry>.from(_roles);
      _cachedErrorMessage = null;
      _cachedHasCompletedInitialLoad = true;
    } catch (error) {
      _log('load error error=$error');
      _errorMessage = error.toString();
      _cachedErrorMessage = _errorMessage;
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasCompletedInitialLoad = true;
        });
      }
      _cachedHasCompletedInitialLoad = true;
      _log(
        'load finish loading=$_isLoading completed=$_hasCompletedInitialLoad roles=${_roles.length} error=${_errorMessage ?? "-"}',
      );
    }
  }

  void _log(String message) {
    // Temporary debug logging removed.
  }

  List<_AccessRoleEntry> _buildRoleEntries(Iterable<String> roleKeys) {
    final uniqueRoleKeys = roleKeys
        .map(_normalizeRoleKey)
        .whereType<String>()
        .where((role) => role.trim().isNotEmpty)
        .toSet()
        .toList(growable: false);
    final sortableEntries = uniqueRoleKeys.map((roleKey) {
      final config = _service.accessConfigForRole(roleKey);
      final resolvedCapabilities = Map<String, bool>.from(
        defaultAccessCapabilitiesForRole(roleKey),
      )..addAll(config?.capabilities ?? const <String, bool>{});
      final permissionCount = resolvedCapabilities.entries
          .where(
            (entry) =>
                !_hiddenRoleEditorCapabilities.contains(entry.key) &&
                entry.value,
          )
          .length;
      final createdAt = _tryParseIsoDateTime(config?.createdAtIso);
      final updatedAt = _tryParseIsoDateTime(config?.updatedAtIso);
      return _SortableAccessRoleEntry(
        roleKey: roleKey,
        label: humanizeDropdownValue(roleKey),
        permissionCount: permissionCount,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
    }).toList(growable: true);

    final oldestFirst = List<_SortableAccessRoleEntry>.from(sortableEntries)
      ..sort(_compareRolesOldestFirst);
    final displayIdByRole = <String, String>{
      for (final entry in oldestFirst.asMap().entries)
        entry.value.roleKey: '${entry.key + 1}',
    };

    sortableEntries.sort(_compareRolesLatestFirst);
    return sortableEntries.map((entry) {
      return _AccessRoleEntry(
        id: displayIdByRole[entry.roleKey] ?? '',
        roleKey: entry.roleKey,
        label: entry.label,
        permissionCount: entry.permissionCount,
      );
    }).toList(growable: false);
  }

  static DateTime? _tryParseIsoDateTime(String? value) {
    final raw = value?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw)?.toUtc();
  }

  int _compareRolesLatestFirst(
    _SortableAccessRoleEntry left,
    _SortableAccessRoleEntry right,
  ) {
    final updatedComparison = _compareDateLatestFirst(
      left.updatedAt,
      right.updatedAt,
    );
    if (updatedComparison != 0) {
      return updatedComparison;
    }
    final createdComparison = _compareDateLatestFirst(
      left.createdAt,
      right.createdAt,
    );
    if (createdComparison != 0) {
      return createdComparison;
    }
    return left.label.toLowerCase().compareTo(right.label.toLowerCase());
  }

  int _compareRolesOldestFirst(
    _SortableAccessRoleEntry left,
    _SortableAccessRoleEntry right,
  ) {
    final updatedComparison = _compareDateOldestFirst(
      left.updatedAt,
      right.updatedAt,
    );
    if (updatedComparison != 0) {
      return updatedComparison;
    }
    final createdComparison = _compareDateOldestFirst(
      left.createdAt,
      right.createdAt,
    );
    if (createdComparison != 0) {
      return createdComparison;
    }
    return left.label.toLowerCase().compareTo(right.label.toLowerCase());
  }

  int _compareDateLatestFirst(DateTime? left, DateTime? right) {
    if (left == null && right == null) {
      return 0;
    }
    if (left == null) {
      return 1;
    }
    if (right == null) {
      return -1;
    }
    return right.compareTo(left);
  }

  int _compareDateOldestFirst(DateTime? left, DateTime? right) {
    if (left == null && right == null) {
      return 0;
    }
    if (left == null) {
      return 1;
    }
    if (right == null) {
      return -1;
    }
    return left.compareTo(right);
  }

  Future<void> _openRoleEditor(_AccessRoleEntry role) async {
    if (!_canUpdateRoles) {
      AppSnackbar.showError(context, 'You do not have access to update roles.');
      return;
    }
    final existingConfig = _service.accessConfigForRole(role.roleKey);
    final initialDraft = role.roleKey == 'admin'
        ? _fullAccessCapabilities()
        : Map<String, bool>.from(
            existingConfig?.capabilities ??
                DispatcherAccessConfig.defaults(roleKey: role.roleKey)
                    .capabilities,
          );
    final savedDraft = await showAppDialog<Map<String, bool>>(
      context: context,
      builder: (dialogContext) => _RoleAccessDialog(
        role: role,
        initialDraft: initialDraft,
        onSave: role.roleKey == 'admin'
            ? null
            : (draft) async {
                final base =
                    existingConfig ??
                    DispatcherAccessConfig.defaults(roleKey: role.roleKey);
                await _service.saveRoleAccess(
                  base.copyWith(
                    id: role.roleKey,
                    role: role.roleKey,
                    capabilities: Map<String, bool>.from(draft),
                  ),
                );
              },
      ),
    );
    if (!mounted || savedDraft == null || role.roleKey == 'admin') {
      return;
    }
    await _load();
  }

  Future<void> _openNewRoleDialog() async {
    if (!_canUpdateRoles) {
      AppSnackbar.showError(context, 'You do not have access to update roles.');
      return;
    }
    final createdRoleKey = await showAppDialog<String>(
      context: context,
      builder: (dialogContext) => const _NewRoleDialog(),
    );
    final normalizedRoleKey = _normalizeRoleKey(createdRoleKey);
    if (!mounted || normalizedRoleKey == null) {
      return;
    }
    if (_roles.any((role) => role.roleKey == normalizedRoleKey)) {
      final existingRole = _roles.firstWhere(
        (role) => role.roleKey == normalizedRoleKey,
      );
      await _openRoleEditor(existingRole);
      return;
    }
    await _service.saveRoleAccess(
      DispatcherAccessConfig.defaults(roleKey: normalizedRoleKey),
    );
    await _load();
    if (!mounted) {
      return;
    }
    final createdRole = _roles.where((role) => role.roleKey == normalizedRoleKey).firstOrNull;
    if (createdRole != null) {
      await _openRoleEditor(createdRole);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredRoles = _roles.where((role) {
      final query = _searchQuery.trim().toLowerCase();
      if (query.isEmpty) {
        return true;
      }
      return role.id.toLowerCase().contains(query) ||
          role.roleKey.toLowerCase().contains(query) ||
          role.label.toLowerCase().contains(query) ||
          '${role.permissionCount}'.contains(query);
    }).toList(growable: false);
    final showInitialLoading =
        _isLoading && !_hasCompletedInitialLoad && _errorMessage == null;

    return AbsorbPointer(
      absorbing: showInitialLoading,
      child: AppPageLoadingOverlay(
        isVisible: showInitialLoading,
        message: 'Loading roles ...',
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RolesToolbar(
                searchQuery: _searchQuery,
                onSearchChanged: (value) => setState(() => _searchQuery = value),
                onNewPressed: _canUpdateRoles ? _openNewRoleDialog : null,
              ),
              const SizedBox(height: _tableSectionGap),
              _AccessListSection(
                roles: filteredRoles,
                errorMessage: _errorMessage,
                isLoading: _isLoading,
                hasCompletedInitialLoad: _hasCompletedInitialLoad,
                onEditPressed: _canUpdateRoles ? _openRoleEditor : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static double _resolvedColumnWidth(double measuredWidth) {
    return AdminListMeasurements.resolvedColumnWidth(
      measuredWidth,
      trailingPadding: _defaultTrailingPadding,
      extraWidthAllowance: _extraWidthAllowance,
    );
  }

  static double _measureTextWidth(
    BuildContext context,
    String label,
    TextStyle labelStyle,
    String value,
    TextStyle valueStyle,
  ) {
    return AdminListMeasurements.maxTextWidth(
      context,
      MediaQuery.textScalerOf(context),
      label,
      labelStyle,
      value,
      valueStyle,
    );
  }
}

class _RolesToolbar extends StatelessWidget {
  const _RolesToolbar({
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onNewPressed,
  });

  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback? onNewPressed;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 520;
        return Row(
          children: [
            Expanded(
              child: AdminListSearchField(
                controlHeight: _AdminAccessViewState._toolbarControlHeight,
                surfaceRadius: _AdminAccessViewState._toolbarSurfaceRadius,
                initialValue: searchQuery,
                onChanged: onSearchChanged,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: isCompact ? 52 : 116,
              child: AdminListNewButton(
                controlHeight: _AdminAccessViewState._toolbarControlHeight,
                surfaceRadius: _AdminAccessViewState._toolbarSurfaceRadius,
                iconOnly: isCompact,
                onTap: onNewPressed,
                label: 'New',
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AccessRoleEntry {
  const _AccessRoleEntry({
    required this.id,
    required this.roleKey,
    required this.label,
    required this.permissionCount,
  });

  final String id;
  final String roleKey;
  final String label;
  final int permissionCount;
}

class _SortableAccessRoleEntry {
  const _SortableAccessRoleEntry({
    required this.roleKey,
    required this.label,
    required this.permissionCount,
    required this.createdAt,
    required this.updatedAt,
  });

  final String roleKey;
  final String label;
  final int permissionCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

class _AccessListSection extends StatelessWidget {
  const _AccessListSection({
    required this.roles,
    required this.errorMessage,
    required this.isLoading,
    required this.hasCompletedInitialLoad,
    required this.onEditPressed,
  });

  final List<_AccessRoleEntry> roles;
  final String? errorMessage;
  final bool isLoading;
  final bool hasCompletedInitialLoad;
  final ValueChanged<_AccessRoleEntry>? onEditPressed;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 920;
        if (errorMessage != null) {
          return AdminListItemCard(
            padding: const EdgeInsets.all(20),
            child: Text(
              errorMessage!,
              style: const TextStyle(
                color: AppColors.dangerStrong,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        }
        if (isLoading && !hasCompletedInitialLoad) {
          return const SizedBox.shrink();
        }
        if (roles.isEmpty) {
          return const AdminListItemCard(
            padding: EdgeInsets.all(20),
            child: AdminListStateText(message: 'No roles found.'),
          );
        }
        if (isNarrow) {
          return Column(
            children: roles.asMap().entries.map((entry) {
              return Padding(
                padding: EdgeInsets.only(
                  bottom: entry.key == roles.length - 1 ? 0 : 12,
                ),
                child: _AccessResponsiveCard(
                  role: entry.value,
                  onEdit: onEditPressed == null
                      ? null
                      : () => onEditPressed!(entry.value),
                ),
              );
            }).toList(),
          );
        }

        final idWidth = _AdminAccessViewState._resolvedColumnWidth(
          _AdminAccessViewState._measureTextWidth(
            context,
            'ID',
            _headerMeasureStyle,
            '${roles.length}',
            _valueStyle,
          ),
        );
        final roleWidth = _AdminAccessViewState._resolvedColumnWidth(
          _AdminAccessViewState._measureTextWidth(
            context,
            'Role',
            _headerMeasureStyle,
            roles.map((role) => role.label).fold<String>(
              'Role',
              (longest, value) => value.length > longest.length ? value : longest,
            ),
            _valueStyle,
          ),
        );
        final permissionsWidth = _AdminAccessViewState._resolvedColumnWidth(
          _AdminAccessViewState._measureTextWidth(
            context,
            'Permissions',
            _headerMeasureStyle,
            '${DispatcherAccessCapability.values.length}',
            _valueStyle,
          ),
        );

        return Column(
          children: [
            _AccessHeaderRow(
              idWidth: idWidth,
              roleWidth: roleWidth,
              permissionsWidth: permissionsWidth,
              actionsWidth:
                  _AdminAccessViewState._actionsWidth +
                  _AdminAccessViewState._extraWidthAllowance,
            ),
            const SizedBox(height: _AdminAccessViewState._tableSectionGap),
            ...roles.asMap().entries.map((entry) {
              return Padding(
                padding: EdgeInsets.only(
                  bottom: entry.key == roles.length - 1 ? 0 : 12,
                ),
                child: _AccessDesktopRow(
                  role: entry.value,
                  idWidth: idWidth,
                  roleWidth: roleWidth,
                  permissionsWidth: permissionsWidth,
                  onEdit: onEditPressed == null
                      ? null
                      : () => onEditPressed!(entry.value),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class _AccessHeaderRow extends StatelessWidget {
  const _AccessHeaderRow({
    required this.idWidth,
    required this.roleWidth,
    required this.permissionsWidth,
    required this.actionsWidth,
  });

  final double idWidth;
  final double roleWidth;
  final double permissionsWidth;
  final double actionsWidth;

  @override
  Widget build(BuildContext context) {
    return AdminListHeaderBar(
      minHeight: 52,
      borderRadius: 16,
      child: Row(
        children: [
          AdminListFixedSlot(
            width: idWidth,
            child: const AdminListHeaderCell(label: 'ID'),
          ),
          AdminListFixedSlot(
            width: roleWidth,
            child: const AdminListHeaderCell(label: 'Role'),
          ),
          AdminListFixedSlot(
            width: permissionsWidth,
            child: const AdminListHeaderCell(label: 'Permissions'),
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

class _AccessDesktopRow extends StatelessWidget {
  const _AccessDesktopRow({
    required this.role,
    required this.idWidth,
    required this.roleWidth,
    required this.permissionsWidth,
    required this.onEdit,
  });

  final _AccessRoleEntry role;
  final double idWidth;
  final double roleWidth;
  final double permissionsWidth;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return AdminListItemCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(
        children: [
          AdminListFixedSlot(
            width: idWidth,
            child: AdminListBodyCell(
              child: Text(role.id, style: _valueStyle),
            ),
          ),
          AdminListFixedSlot(
            width: roleWidth,
            child: AdminListBodyCell(
              child: Text(role.label, style: _nameStyle),
            ),
          ),
          AdminListFixedSlot(
            width: permissionsWidth,
            child: AdminListBodyCell(
              child: Text('${role.permissionCount}', style: _valueStyle),
            ),
          ),
          AdminListTrailingActionsLane(
            width:
                _AdminAccessViewState._actionsWidth +
                _AdminAccessViewState._extraWidthAllowance,
            child: AdminListBodyCell(
              alignment: Alignment.centerRight,
              trailingPadding: 0,
              child: AdminListActionButton(
                icon: Icons.edit_rounded,
                onTap: onEdit,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccessResponsiveCard extends StatelessWidget {
  const _AccessResponsiveCard({required this.role, required this.onEdit});

  final _AccessRoleEntry role;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return AdminListItemCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(role.label, style: _nameStyle),
                    const SizedBox(height: 4),
                    Text('${role.permissionCount}', style: _metaStyle),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AdminListActionButton(
                icon: Icons.edit_rounded,
                onTap: onEdit,
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final useSingleColumn = constraints.maxWidth < 520;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  AdminListResponsiveField(
                    title: 'ID',
                    value: role.id,
                    width: useSingleColumn ? constraints.maxWidth : 180,
                    centered: false,
                  ),
                  AdminListResponsiveField(
                    title: 'Role',
                    value: role.label,
                    width: useSingleColumn ? constraints.maxWidth : 220,
                    centered: false,
                    isTitle: true,
                  ),
                  AdminListResponsiveField(
                    title: 'Permissions',
                    value: '${role.permissionCount}',
                    width: useSingleColumn ? constraints.maxWidth : 220,
                    centered: false,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _NewRoleDialog extends StatefulWidget {
  const _NewRoleDialog();

  @override
  State<_NewRoleDialog> createState() => _NewRoleDialogState();
}

class _NewRoleDialogState extends State<_NewRoleDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final normalizedRoleKey = _normalizeRoleKey(_controller.text);
    if (normalizedRoleKey == null) {
      setState(() {
        _errorText = 'Role name is required.';
      });
      return;
    }
    Navigator.of(context).pop(normalizedRoleKey);
  }

  @override
  Widget build(BuildContext context) {
    return AdminModalShell(
      title: 'New Role',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
      child: AdminModalFormBody(
        children: [
          AdminModalFieldsSection(
            children: [
              TextFormField(
                controller: _controller,
                autofocus: true,
                style: _valueStyle,
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Role',
                  errorText: _errorText,
                  hintText: 'Enter role name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.primaryBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.primaryColor),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoleAccessDialog extends StatefulWidget {
  const _RoleAccessDialog({
    required this.role,
    required this.initialDraft,
    this.onSave,
  });

  final _AccessRoleEntry role;
  final Map<String, bool> initialDraft;
  final Future<void> Function(Map<String, bool> draft)? onSave;

  @override
  State<_RoleAccessDialog> createState() => _RoleAccessDialogState();
}

class _RoleAccessDialogState extends State<_RoleAccessDialog> {
  late Map<String, bool> _draft;
  bool _isSaving = false;

  bool get _isEditable => widget.onSave != null;

  @override
  void initState() {
    super.initState();
    _draft = Map<String, bool>.from(widget.initialDraft);
  }

  Future<void> _save() async {
    final onSave = widget.onSave;
    if (onSave == null || _isSaving) {
      return;
    }
    setState(() {
      _isSaving = true;
    });
    try {
      await onSave(_draft);
      if (!mounted) {
        return;
      }
      AppSnackbar.showSuccess(context, '${widget.role.label} access saved.');
      Navigator.of(context).pop(Map<String, bool>.from(_draft));
    } catch (_) {
      if (!mounted) {
        return;
      }
      AppSnackbar.showError(
        context,
        'We could not save ${widget.role.label.toLowerCase()} access right now.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminModalShell(
      title: '${widget.role.label} Permissions',
      maxWidth: 720,
      contentInset: const EdgeInsets.fromLTRB(0, 16, 0, 14),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        if (_isEditable)
          FilledButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text('Save'),
          ),
      ],
      child: AdminModalFormBody(
        readOnly: !_isEditable,
        children: [
          AdminModalFieldsSection(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 520 ? 2 : 1;
                  const spacing = 12.0;
                  final itemWidth =
                      ((constraints.maxWidth - ((columns - 1) * spacing)) /
                              columns)
                          .clamp(0.0, constraints.maxWidth);
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: _allAccessOptions.map((option) {
                      final value = _draft[option.key] ?? false;
                      return SizedBox(
                        width: itemWidth,
                        child: _RoleCapabilityTile(
                          label: _formatPermissionLabel(option.key),
                          value: value,
                          enabled: _isEditable,
                          onChanged: (nextValue) {
                            setState(() {
                              _draft[option.key] = nextValue;
                            });
                          },
                        ),
                      );
                    }).toList(growable: false),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoleCapabilityTile extends StatelessWidget {
  const _RoleCapabilityTile({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? () => onChanged(!value) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Transform.scale(
              scale: 0.95,
              child: Checkbox(
                value: value,
                activeColor: AppColors.primaryColor,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: enabled
                    ? (nextValue) => onChanged(nextValue == true)
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(label, style: _checkboxLabelStyle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Map<String, bool> _fullAccessCapabilities() {
  return {
    for (final capability in DispatcherAccessCapability.values) capability: true,
  };
}

String _formatPermissionLabel(String permissionKey) {
  return _permissionDisplayLabels[permissionKey] ??
      permissionKey.replaceAll('_', '-').replaceAll('.', '-');
}

String? _normalizeRoleKey(String? value) {
  final normalized = (value ?? '')
      .trim()
      .toLowerCase()
      .replaceAll('_', '-')
      .replaceAll(RegExp(r'[^a-z0-9 -]'), '')
      .replaceAll(' ', '-')
      .replaceAll(RegExp(r'-+'), '-');
  if (normalized.isEmpty) {
    return null;
  }
  if (normalized == 'sub-client' || normalized == 'member') {
    return 'client';
  }
  return normalized;
}

const TextStyle _nameStyle = TextStyle(
  color: AppColors.textPrimary,
  fontWeight: FontWeight.w700,
  fontSize: 15,
  height: 1.2,
);

const TextStyle _headerMeasureStyle = TextStyle(
  color: AppColors.textSecondary,
  fontWeight: FontWeight.w700,
);

const TextStyle _valueStyle = TextStyle(
  color: AppColors.textPrimary,
  fontWeight: FontWeight.w700,
  fontSize: 15,
  height: 1.2,
);

const TextStyle _metaStyle = TextStyle(
  color: AppColors.textSecondary,
  fontWeight: FontWeight.w700,
  fontSize: 15,
  height: 1.2,
);

const TextStyle _checkboxLabelStyle = TextStyle(
  fontWeight: FontWeight.w700,
  color: AppColors.textPrimary,
  height: 1.3,
);

const Map<String, String> _permissionDisplayLabels = {
  DispatcherAccessCapability.dashboardRead: 'view-dashboard',
  DispatcherAccessCapability.dashboardUpdateBilling: 'manage-billing',
  DispatcherAccessCapability.dashboardExport: 'view-summary-report',
  DispatcherAccessCapability.bookingsCreate: 'manage-bookings',
  DispatcherAccessCapability.bookingsRead: 'view-bookings',
  DispatcherAccessCapability.bookingsUpdate: 'update-bookings',
  DispatcherAccessCapability.usersCreate: 'manage-users',
  DispatcherAccessCapability.usersRead: 'view-users',
  DispatcherAccessCapability.usersUpdate: 'update-users',
  DispatcherAccessCapability.usersDelete: 'delete-users',
  DispatcherAccessCapability.usersImpersonate: 'manage-user-login',
  DispatcherAccessCapability.vehicleMakesCreate: 'manage-vehicle-makes',
  DispatcherAccessCapability.vehicleMakesRead: 'view-vehicle-makes',
  DispatcherAccessCapability.vehicleMakesUpdate: 'update-vehicle-makes',
  DispatcherAccessCapability.vehicleMakesDelete: 'delete-vehicle-makes',
  DispatcherAccessCapability.vehicleTypesCreate: 'manage-vehicle-types',
  DispatcherAccessCapability.vehicleTypesRead: 'view-vehicle-types',
  DispatcherAccessCapability.vehicleTypesUpdate: 'update-vehicle-types',
  DispatcherAccessCapability.vehicleTypesDelete: 'delete-vehicle-types',
  DispatcherAccessCapability.vehicleSizesCreate: 'manage-vehicle-sizes',
  DispatcherAccessCapability.vehicleSizesRead: 'view-vehicle-sizes',
  DispatcherAccessCapability.vehicleSizesUpdate: 'update-vehicle-sizes',
  DispatcherAccessCapability.vehicleSizesDelete: 'delete-vehicle-sizes',
  DispatcherAccessCapability.statusesCreate: 'manage-statuses',
  DispatcherAccessCapability.statusesRead: 'view-statuses',
  DispatcherAccessCapability.statusesUpdate: 'update-statuses',
  DispatcherAccessCapability.statusesDelete: 'delete-statuses',
  DispatcherAccessCapability.formsCreate: 'manage-flows',
  DispatcherAccessCapability.formsRead: 'view-flows',
  DispatcherAccessCapability.formsUpdate: 'update-flows',
  DispatcherAccessCapability.formsDelete: 'delete-flows',
  DispatcherAccessCapability.fieldsCreate: 'manage-fields',
  DispatcherAccessCapability.fieldsRead: 'view-fields',
  DispatcherAccessCapability.fieldsUpdate: 'update-fields',
  DispatcherAccessCapability.fieldsDelete: 'delete-fields',
  DispatcherAccessCapability.roleAccessRead: 'view-roles',
  DispatcherAccessCapability.roleAccessUpdate: 'update-roles',
  DispatcherAccessCapability.syncRead: 'view-sync-queue',
};

class _AccessOption {
  const _AccessOption(this.key, this.label);

  final String key;
  final String label;
}

int _permissionGroupRank(String label) {
  if (label.startsWith('view-')) {
    return 0;
  }
  if (label.startsWith('update-')) {
    return 1;
  }
  if (label.startsWith('manage-')) {
    return 2;
  }
  if (label.startsWith('delete-')) {
    return 3;
  }
  return 4;
}

int _compareAccessOptions(_AccessOption left, _AccessOption right) {
  final groupComparison = _permissionGroupRank(
    left.label,
  ).compareTo(_permissionGroupRank(right.label));
  if (groupComparison != 0) {
    return groupComparison;
  }
  return left.label.compareTo(right.label);
}

final List<_AccessOption> _allAccessOptions =
    [
      const _AccessOption(
        DispatcherAccessCapability.dashboardRead,
        'view-dashboard',
      ),
      const _AccessOption(
        DispatcherAccessCapability.dashboardUpdateBilling,
        'manage-billing',
      ),
      const _AccessOption(
        DispatcherAccessCapability.dashboardExport,
        'view-summary-report',
      ),
      const _AccessOption(
        DispatcherAccessCapability.bookingsCreate,
        'manage-bookings',
      ),
      const _AccessOption(
        DispatcherAccessCapability.bookingsRead,
        'view-bookings',
      ),
      const _AccessOption(
        DispatcherAccessCapability.bookingsUpdate,
        'update-bookings',
      ),
      const _AccessOption(DispatcherAccessCapability.usersCreate, 'manage-users'),
      const _AccessOption(DispatcherAccessCapability.usersRead, 'view-users'),
      const _AccessOption(DispatcherAccessCapability.usersUpdate, 'update-users'),
      const _AccessOption(DispatcherAccessCapability.usersDelete, 'delete-users'),
      const _AccessOption(
        DispatcherAccessCapability.usersImpersonate,
        'manage-user-login',
      ),
      const _AccessOption(
        DispatcherAccessCapability.vehicleMakesCreate,
        'manage-vehicle-makes',
      ),
      const _AccessOption(
        DispatcherAccessCapability.vehicleMakesRead,
        'view-vehicle-makes',
      ),
      const _AccessOption(
        DispatcherAccessCapability.vehicleMakesUpdate,
        'update-vehicle-makes',
      ),
      const _AccessOption(
        DispatcherAccessCapability.vehicleMakesDelete,
        'delete-vehicle-makes',
      ),
      const _AccessOption(
        DispatcherAccessCapability.vehicleTypesCreate,
        'manage-vehicle-types',
      ),
      const _AccessOption(
        DispatcherAccessCapability.vehicleTypesRead,
        'view-vehicle-types',
      ),
      const _AccessOption(
        DispatcherAccessCapability.vehicleTypesUpdate,
        'update-vehicle-types',
      ),
      const _AccessOption(
        DispatcherAccessCapability.vehicleTypesDelete,
        'delete-vehicle-types',
      ),
      const _AccessOption(
        DispatcherAccessCapability.vehicleSizesCreate,
        'manage-vehicle-sizes',
      ),
      const _AccessOption(
        DispatcherAccessCapability.vehicleSizesRead,
        'view-vehicle-sizes',
      ),
      const _AccessOption(
        DispatcherAccessCapability.vehicleSizesUpdate,
        'update-vehicle-sizes',
      ),
      const _AccessOption(
        DispatcherAccessCapability.vehicleSizesDelete,
        'delete-vehicle-sizes',
      ),
      const _AccessOption(
        DispatcherAccessCapability.statusesCreate,
        'manage-statuses',
      ),
      const _AccessOption(
        DispatcherAccessCapability.statusesRead,
        'view-statuses',
      ),
      const _AccessOption(
        DispatcherAccessCapability.statusesUpdate,
        'update-statuses',
      ),
      const _AccessOption(
        DispatcherAccessCapability.statusesDelete,
        'delete-statuses',
      ),
      const _AccessOption(DispatcherAccessCapability.formsCreate, 'manage-flows'),
      const _AccessOption(DispatcherAccessCapability.formsRead, 'view-flows'),
      const _AccessOption(DispatcherAccessCapability.formsUpdate, 'update-flows'),
      const _AccessOption(DispatcherAccessCapability.formsDelete, 'delete-flows'),
      const _AccessOption(DispatcherAccessCapability.fieldsCreate, 'manage-fields'),
      const _AccessOption(DispatcherAccessCapability.fieldsRead, 'view-fields'),
      const _AccessOption(DispatcherAccessCapability.fieldsUpdate, 'update-fields'),
      const _AccessOption(DispatcherAccessCapability.fieldsDelete, 'delete-fields'),
      const _AccessOption(DispatcherAccessCapability.roleAccessRead, 'view-roles'),
      const _AccessOption(
        DispatcherAccessCapability.roleAccessUpdate,
        'update-roles',
      ),
      const _AccessOption(DispatcherAccessCapability.syncRead, 'view-sync-queue'),
    ]..sort(_compareAccessOptions);
