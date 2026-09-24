import 'package:webapp/utils/location_display.dart';
import 'package:webapp/services/kpi/location_option_registry.dart';
import 'package:webapp/services/kpi/operations_catalog_store.dart';
import 'package:webapp/services/field_type_history_service.dart';
import 'package:webapp/widgets/shared/type_history_input.dart';
import 'package:webapp/models/chassis_action_history.dart';
import 'package:webapp/widgets/shared/chassis_action_history_dialog.dart';
import 'package:webapp/widgets/shared/lazy_data_scroll_view.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/chassis.dart';
import 'package:webapp/models/dispatcher_access_config.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/requests/booking.request.dart';
import 'package:webapp/requests/chassis.request.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:webapp/utils/functions.dart';
import 'package:webapp/views/admin/admin_users.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/admin_action_confirmation.dart';
import 'package:webapp/widgets/shared/app_modal_guard.dart';
import 'package:webapp/widgets/shared/admin_modal_form_primitives.dart';
import 'package:webapp/widgets/shared/booking_record_card.dart';
import 'package:webapp/views/admin/admin_bookings.dart';
import 'package:webapp/widgets/shared/chassis_status_presentation.dart';
import 'package:webapp/widgets/shared/app_page_loading_overlay.dart';
import 'package:webapp/widgets/shared/app_snackbar.dart';

String _chassisLocationLabel(Chassis item, {String? resolvedLocation}) {
  final location = (resolvedLocation ?? item.location)?.trim();
  if (location == null || location.isEmpty) {
    return '—';
  }
  return locationDisplayLabel(location);
}

class AdminChassisView extends StatefulWidget {
  const AdminChassisView({super.key});
  @override
  State<AdminChassisView> createState() => _AdminChassisViewState();
}

class _AdminChassisViewState extends State<AdminChassisView>
    with WidgetsBindingObserver {
  static const _headerStyle = TextStyle(
    color: AppColors.textSecondary,
    fontWeight: FontWeight.w700,
  );
  static const _defaultTrailingPadding =
      AdminListMeasurements.defaultTrailingPadding;
  static const _extraWidthAllowance =
      AdminListMeasurements.defaultExtraWidthAllowance;
  static const _noBookingOptionValue = '__chassis_no_booking__';
  static const _noDriverOptionValue = '__chassis_no_driver__';
  String _query = '';
  String _status = 'All';
  String _activeFilter = 'All';
  DateTime? _createdStartDate;
  DateTime? _createdEndDate;
  DateTime? _updatedStartDate;
  DateTime? _updatedEndDate;
  List<Chassis> _items = const <Chassis>[];
  List<Booking> _bookingOptions = const <Booking>[];
  Map<String, UserModel> _historyUsers = const {};
  List<UserModel> _driverOptions = const <UserModel>[];
  Future<void>? _editorOptionsFuture;
  StreamSubscription<List<Chassis>>? _chassisSubscription;
  final _histories = ValueNotifier<Map<int, ChassisActionHistory>>({});
  final _historyClock = ValueNotifier<DateTime>(DateTime.now());
  StreamSubscription<List<Booking>>? _bookingSubscription;
  Timer? _historyTimer;
  bool _pageVisible = true;
  bool _appVisible = true;

  void _refreshHistories() {
    final byChassis = <String, List<Booking>>{};
    final byId = <String?, Booking>{};
    for (final booking in _bookingOptions) {
      byId[booking.id] = booking;
      if (booking.chassisId != null) {
        byChassis.putIfAbsent(booking.chassisId!, () => []).add(booking);
      }
    }
    _histories.value = {
      for (final item in _items)
        item.id: ChassisActionHistory.fromBookings(item, {
          ...?byChassis['${item.id}'],
          if (item.bookingReferenceId != null &&
              byId[item.bookingReferenceId] != null)
            byId[item.bookingReferenceId]!,
        }),
    };
    _updateHistoryTimer();
  }

  void _updateHistoryTimer() {
    final needed =
        _pageVisible &&
        _appVisible &&
        _histories.value.values.any((history) => history.waiting);
    if (!needed) {
      _historyTimer?.cancel();
      _historyTimer = null;
    } else {
      _historyClock.value = DateTime.now();
      _historyTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        _historyClock.value = DateTime.now();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pageVisible = TickerMode.valuesOf(context).enabled;
    _updateHistoryTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appVisible = state == AppLifecycleState.resumed;
    _updateHistoryTimer();
  }

  bool _isLoadingChassis = true;
  String? _chassisLoadError;
  final RoleAccessService _roleAccessService = RoleAccessService.instance;

  bool get _canCreateChassis =>
      _roleAccessService.canAccess(DispatcherAccessCapability.chassisCreate);
  bool get _canUpdateChassis =>
      _roleAccessService.canAccess(DispatcherAccessCapability.chassisUpdate);
  bool get _canDeleteChassis =>
      _roleAccessService.canAccess(DispatcherAccessCapability.chassisDelete);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bookingSubscription = BookingRequest.instance.watchBookings().listen((
      bookings,
    ) {
      if (!mounted) return;
      setState(() {
        _bookingOptions = bookings;
        _refreshHistories();
      });
    }, onError: (_) {});
    _editorOptionsFuture = _loadEditorOptions();
    unawaited(_editorOptionsFuture!);
    _chassisSubscription = ChassisRequest.instance.watchChassis().listen((
      items,
    ) {
      if (!mounted || !ChassisRequest.instance.hasResolvedChassis) return;
      setState(() {
        _items = items;
        _refreshHistories();
        _isLoadingChassis = false;
        _chassisLoadError = null;
      });
    });
    unawaited(_loadChassis());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _historyTimer?.cancel();
    _bookingSubscription?.cancel();
    _histories.dispose();
    _historyClock.dispose();
    _chassisSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadChassis() async {
    if (mounted) {
      setState(() {
        _isLoadingChassis = true;
        _chassisLoadError = null;
      });
    }
    try {
      final items = await ChassisRequest.instance.getChassis();
      if (!mounted) return;
      setState(() {
        _items = items;
        _refreshHistories();
        _isLoadingChassis = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingChassis = false;
        _chassisLoadError = 'We could not load chassis from Firestore.';
      });
    }
  }

  Future<void> _loadEditorOptions() async {
    try {
      final results = await Future.wait<Object>([
        BookingRequest.instance.getBookings(),
        AuthRequest.instance.getUsers(),
      ]);
      if (!mounted) return;
      final bookings = results[0] as List<Booking>;
      final users = results[1] as List<UserModel>;
      setState(() {
        _bookingOptions = bookings;
        _refreshHistories();
        _historyUsers = {
          for (final user in users)
            if (user.id != null) user.id!: user,
        };
        _driverOptions = users
            .where((user) => user.role?.trim().toLowerCase() == 'driver')
            .toList();
      });
    } catch (_) {
      // The editor remains usable offline with any options already in memory.
    }
  }

  @override
  Widget build(BuildContext context) => Builder(
    builder: (context) {
      final items = List<Chassis>.from(_items);
      items.sort((a, b) => b.id.compareTo(a.id));
      final visible = items
          .where(
            (item) =>
                (_status == 'All' || item.currentStatus == _status) &&
                (_activeFilter == 'All' ||
                    (_activeFilter == 'Active' && item.isActive) ||
                    (_activeFilter == 'Inactive' && !item.isActive)) &&
                _isWithinRange(
                  item.createdAt,
                  _createdStartDate,
                  _createdEndDate,
                ) &&
                _isWithinRange(
                  item.updatedAt,
                  _updatedStartDate,
                  _updatedEndDate,
                ) &&
                '${item.id} ${item.name}'.toLowerCase().contains(
                  _query.toLowerCase(),
                ),
          )
          .toList();
      return LayoutBuilder(
        builder: (context, constraints) {
          const pagePadding = EdgeInsets.all(24);
          final contentWidth = constraints.maxWidth - pagePadding.horizontal;
          final textScaler = MediaQuery.textScalerOf(context);
          final sampleId = visible
              .map((item) => '${item.id}')
              .fold<String>('-', AdminListMeasurements.longerText);
          final sampleName = visible
              .map((item) => item.name)
              .fold<String>('-', AdminListMeasurements.longerText);
          final sampleClient = visible
              .map(
                (item) =>
                    _clientContactForBooking(item.bookingReferenceId).display,
              )
              .fold<String>('-', AdminListMeasurements.longerText);
          final sampleDriver = visible
              .map(
                (item) => _driverContactForId(item.driverReferenceId).display,
              )
              .fold<String>('-', AdminListMeasurements.longerText);
          final sampleBooking = visible
              .map((item) => item.bookingReferenceId?.toString() ?? '-')
              .fold<String>('-', AdminListMeasurements.longerText);
          final sampleLocation = visible
              .map(
                (item) => _chassisLocationLabel(
                  item,
                  resolvedLocation: _histories.value[item.id]?.currentLocation,
                ),
              )
              .fold<String>('-', AdminListMeasurements.longerText);
          final sampleStatus = visible
              .map((item) => chassisStatusLabel(item.currentStatus))
              .fold<String>('-', AdminListMeasurements.longerText);
          final sampleElapsed = visible
              .map(
                (item) =>
                    _histories.value[item.id]?.elapsedLabel(
                      _historyClock.value,
                    ) ??
                    '-',
              )
              .fold<String>('-', AdminListMeasurements.longerText);
          final idWidth = _resolvedChassisColumnWidth(
            context,
            textScaler,
            'ID',
            sampleId,
            _ChassisStyles.value,
          );
          final nameWidth = _resolvedChassisColumnWidth(
            context,
            textScaler,
            'Name',
            sampleName,
            _ChassisStyles.title,
          );
          var clientWidth = _resolvedChassisColumnWidth(
            context,
            textScaler,
            'Client',
            sampleClient,
            _ChassisStyles.link,
          );
          var driverWidth = _resolvedChassisColumnWidth(
            context,
            textScaler,
            'Driver',
            sampleDriver,
            _ChassisStyles.link,
          );
          final bookingWidth = _resolvedChassisColumnWidth(
            context,
            textScaler,
            'Booking',
            sampleBooking,
            _ChassisStyles.link,
          );
          var locationWidth = _resolvedChassisColumnWidth(
            context,
            textScaler,
            'Location',
            sampleLocation,
            _ChassisStyles.value,
          );

          final statusWidth = _resolvedChassisStatusColumnWidth(
            context,
            textScaler,
            sampleStatus,
          );
          final elapsedWidth =
              _resolvedChassisColumnWidth(
                context,
                textScaler,
                'Time',
                sampleElapsed,
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ) +
              16;

          final actionsWidth =
              AdminListMeasurements.maxValue(
                192,
                AdminListMeasurements.measureTextWidth(
                  context,
                  textScaler,
                  'Actions',
                  _headerStyle,
                ),
              ) +
              _extraWidthAllowance;
          var tableWidth =
              idWidth +
              nameWidth +
              clientWidth +
              driverWidth +
              bookingWidth +
              locationWidth +
              statusWidth +
              elapsedWidth +
              actionsWidth +
              34; // 16px card padding and 1px border on each side.
          // Keep identifiers, pills and actions at their measured widths.
          // Names/location may wrap before the whole row switches to cards.
          final flexibleWidths = [clientWidth, driverWidth, locationWidth];
          final minimumWidths = [
            for (var i = 0; i < flexibleWidths.length; i++)
              AdminListMeasurements.maxValue(
                _resolvedChassisColumnWidth(
                  context,
                  textScaler,
                  ['Client', 'Driver', 'Location'][i],
                  '',
                  _ChassisStyles.value,
                ),
                120,
              ).clamp(0.0, flexibleWidths[i]).toDouble(),
          ];
          final reducible = List.generate(
            3,
            (i) => flexibleWidths[i] - minimumWidths[i],
          );
          final totalReducible = reducible.fold<double>(0, (a, b) => a + b);
          final overflow = tableWidth - contentWidth;
          if (overflow > 0 && overflow <= totalReducible) {
            for (var i = 0; i < flexibleWidths.length; i++) {
              flexibleWidths[i] -= overflow * reducible[i] / totalReducible;
            }
            clientWidth = flexibleWidths[0];
            driverWidth = flexibleWidths[1];
            locationWidth = flexibleWidths[2];
            tableWidth = contentWidth;
          }
          // Desktop: use the wide table whenever the viewport is wide enough,
          // regardless of measured column totals. This matches the other admin
          // list pages (users/bookings): a fixed desktop breakpoint decides
          // "desktop table" instead of a measured-fit that can collapse the
          // whole page when a single column is a few pixels too wide.
          final useWideTable = constraints.maxWidth >= 760;
          // LazySliverList rows keep their flexible column widths (which have
          // already been reduced to fit contentWidth above), so a desktop
          // breakpoint alone is the trigger — matches users/bookings. There is
          // no extra horizontal-scroll wrapper because the flexible columns
          // already reduce to contentWidth, keeping the table scroll-free like
          // the other admin pages.

          return AppPageLoadingOverlay(
            isVisible: _isLoadingChassis && _items.isEmpty,
            message: 'Loading chassis ...',
            child: LazyDataScrollView(
              padding: pagePadding,
              child: SliverSection(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AdminListToolbar(
                    controlHeight: 52,
                    surfaceRadius: 16,
                    search: AdminListSearchField(
                      controlHeight: 52,
                      surfaceRadius: 16,
                      initialValue: _query,
                      onChanged: (value) => setState(() => _query = value),
                    ),
                    filtersBuilder: (_, iconOnly) => _ChassisFiltersPanel(
                      iconOnly: iconOnly,
                      status: _status,
                      active: _activeFilter,
                      createdStart: _createdStartDate,
                      createdEnd: _createdEndDate,
                      updatedStart: _updatedStartDate,
                      updatedEnd: _updatedEndDate,
                      onStatusChanged: (value) =>
                          setState(() => _status = value),
                      onActiveChanged: (value) =>
                          setState(() => _activeFilter = value),
                      onCreatedStartChanged: (value) =>
                          setState(() => _createdStartDate = value),
                      onCreatedEndChanged: (value) =>
                          setState(() => _createdEndDate = value),
                      onUpdatedStartChanged: (value) =>
                          setState(() => _updatedStartDate = value),
                      onUpdatedEndChanged: (value) =>
                          setState(() => _updatedEndDate = value),
                      onClear: () => setState(() {
                        _status = 'All';
                        _activeFilter = 'All';
                        _createdStartDate = null;
                        _createdEndDate = null;
                        _updatedStartDate = null;
                        _updatedEndDate = null;
                      }),
                    ),
                    onNewPressed: _canCreateChassis ? _openEditor : null,
                  ),
                  const SizedBox(height: 12),
                  if (_chassisLoadError != null && _items.isEmpty)
                    _ChassisLoadErrorState(
                      message: _chassisLoadError!,
                      onRetry: _loadChassis,
                    )
                  else if (_items.isEmpty)
                    const _ChassisEmptyState(message: 'No chassis yet.')
                  else if (visible.isEmpty)
                    const _ChassisEmptyState(
                      message: 'No chassis matched your current search.',
                    )
                  else ...[
                    if (useWideTable)
                      _ChassisHeaderRow(
                        idWidth: idWidth,
                        nameWidth: nameWidth,
                        clientWidth: clientWidth,
                        driverWidth: driverWidth,
                        bookingWidth: bookingWidth,
                        locationWidth: locationWidth,
                        statusWidth: statusWidth,
                        elapsedWidth: elapsedWidth,
                        actionsWidth: actionsWidth,
                      ),
                    if (useWideTable) const SizedBox(height: 14),
                    LazySliverList(
                      items: visible.asMap().entries,
                      itemBuilder: (context, entry) {
                        final client = _clientContactForBooking(
                          entry.value.bookingReferenceId,
                        );
                        final driver = _driverContactForId(
                          entry.value.driverReferenceId,
                        );
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: entry.key == visible.length - 1 ? 0 : 12,
                          ),
                          child: useWideTable
                              ? _ChassisDesktopRow(
                                  item: entry.value.copyWith(
                                    location:
                                        _histories
                                            .value[entry.value.id]
                                            ?.currentLocation ??
                                        _chassisLocationLabel(entry.value),
                                  ),
                                  elapsed: ChassisElapsedText(
                                    history:
                                        _histories.value[entry.value.id] ??
                                        ChassisActionHistory([]),
                                    clock: _historyClock,
                                    emptyLabel: '-',
                                  ),
                                  client: client,
                                  driver: driver,
                                  onOpenClient:
                                      _canOpenUsers &&
                                          client.user?.id?.isNotEmpty == true
                                      ? () => _openContactUser(client.user!)
                                      : null,
                                  onOpenDriver:
                                      _canOpenUsers &&
                                          driver.user?.id?.isNotEmpty == true
                                      ? () => _openContactUser(driver.user!)
                                      : null,
                                  idWidth: idWidth,
                                  nameWidth: nameWidth,
                                  clientWidth: clientWidth,
                                  driverWidth: driverWidth,
                                  bookingWidth: bookingWidth,
                                  locationWidth: locationWidth,
                                  statusWidth: statusWidth,
                                  elapsedWidth: elapsedWidth,
                                  actionsWidth: actionsWidth,
                                  actions: _chassisActions(entry.value),
                                  onOpenBooking: () => _openBooking(
                                    entry.value.bookingReferenceId,
                                  ),
                                )
                              : _ChassisResponsiveCard(
                                  item: entry.value.copyWith(
                                    location:
                                        _histories
                                            .value[entry.value.id]
                                            ?.currentLocation ??
                                        _chassisLocationLabel(entry.value),
                                  ),
                                  elapsed: ChassisElapsedText(
                                    history:
                                        _histories.value[entry.value.id] ??
                                        ChassisActionHistory([]),
                                    clock: _historyClock,
                                    emptyLabel: '-',
                                  ),
                                  client: client,
                                  driver: driver,
                                  onOpenClient:
                                      _canOpenUsers &&
                                          client.user?.id?.isNotEmpty == true
                                      ? () => _openContactUser(client.user!)
                                      : null,
                                  onOpenDriver:
                                      _canOpenUsers &&
                                          driver.user?.id?.isNotEmpty == true
                                      ? () => _openContactUser(driver.user!)
                                      : null,
                                  actions: _chassisActions(entry.value),
                                  onOpenBooking: () => _openBooking(
                                    entry.value.bookingReferenceId,
                                  ),
                                ),
                        );
                      },
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

  List<Widget> _chassisActions(Chassis item) => [
    AdminListActionButton(
      icon: Icons.visibility_rounded,
      backgroundColor: Colors.yellow.shade900,
      onTap: () => _openHistory(item),
    ),
    if (_canUpdateChassis)
      AdminListActionButton(
        icon: Icons.edit_rounded,
        onTap: () => _openEditor(item: item),
      ),
    if (_canUpdateChassis)
      AdminListActionButton(
        icon: item.isActive ? Icons.close_rounded : Icons.check_rounded,
        backgroundColor: item.isActive
            ? AppColors.dangerStrong
            : const Color(0xFF2EAD62),
        onTap: () => _toggleActive(item),
      ),
    if (_canDeleteChassis)
      AdminListActionButton(
        icon: Icons.delete_rounded,
        isDanger: true,
        onTap: () => _deleteChassis(item),
      ),
  ];

  Future<void> _openHistory(Chassis item) async {
    await (_editorOptionsFuture ??= _loadEditorOptions());
    if (!mounted) return;
    await showAppDialog<void>(
      context: context,
      wrapInSelectionArea: false,
      barrierDismissible: true,
      builder: (context) =>
          ValueListenableBuilder<Map<int, ChassisActionHistory>>(
            valueListenable: _histories,
            builder: (context, histories, child) => ChassisActionHistoryDialog(
              name: item.name,
              currentStatus:
                  _items
                      .where((chassis) => chassis.id == item.id)
                      .firstOrNull
                      ?.currentStatus ??
                  item.currentStatus,
              // Creation time is only evidence of the initial status when
              // the chassis has never subsequently been updated.
              currentStatusAt:
                  item.createdAt != null && item.createdAt == item.updatedAt
                  ? item.createdAt
                  : null,
              usersById: _historyUsers,
              history: histories[item.id] ?? ChassisActionHistory([]),
              clock: _historyClock,
            ),
          ),
    );
  }

  Future<void> _toggleActive(Chassis item) async {
    if (!_canUpdateChassis) return;
    final willBeActive = !item.isActive;
    await showAdminActionConfirmation(
      context,
      title: '${willBeActive ? 'Activate' : 'Deactivate'} Chassis ${item.id}',
      message:
          'Are you sure you want to ${willBeActive ? 'activate' : 'deactivate'} ${item.name}?',
      confirmLabel: willBeActive ? 'Activate' : 'Deactivate',
      onConfirmAsync: () async {
        try {
          await ChassisRequest.instance.saveChassis(
            item.copyWith(isActive: willBeActive),
            previousBookingId: item.bookingReferenceId,
          );
          if (!mounted) return false;
          AppSnackbar.showSuccess(
            context,
            willBeActive ? 'Chassis activated.' : 'Chassis deactivated.',
          );
          return true;
        } catch (_) {
          if (!mounted) return false;
          AppSnackbar.showError(context, 'We could not update the chassis.');
          return false;
        }
      },
    );
  }

  Future<void> _deleteChassis(Chassis item) async {
    if (!_canDeleteChassis) return;
    await showAdminActionConfirmation(
      context,
      title: 'Delete Chassis ${item.id}',
      message: 'Are you sure you want to delete ${item.name}?',
      confirmLabel: 'Delete',
      isDanger: true,
      onConfirmAsync: () async {
        try {
          await ChassisRequest.instance.deleteChassis(item);
          if (!mounted) return false;
          AppSnackbar.showSuccess(context, 'Chassis deleted.');
          return true;
        } catch (_) {
          if (!mounted) return false;
          AppSnackbar.showError(context, 'We could not delete the chassis.');
          return false;
        }
      },
    );
  }

  Future<void> _openEditor({Chassis? item, bool readOnly = false}) async {
    await (_editorOptionsFuture ??= _loadEditorOptions());
    if (!mounted) return;
    await OperationsCatalogStore.instance.restore();
    unawaited(
      OperationsCatalogStore.instance.load().then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {},
      ),
    );
    final historyAccount = await FieldTypeHistoryService.instance
        .currentAccount();
    if (!mounted) return;
    final name = TextEditingController(text: item?.name ?? '');
    final location = TextEditingController(text: item?.location ?? '');
    final isActive = ValueNotifier<bool>(item?.isActive ?? true);
    var selectedStatus = item?.currentStatus ?? Chassis.ready;
    var selectedBookingId = item?.bookingReferenceId?.toString();
    var selectedDriverId = item?.driverReferenceId?.toString();
    var isSaving = false;
    final saved = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AdminModalShell(
          title: readOnly
              ? 'Chassis ${item?.id ?? '-'}'
              : item == null
              ? 'New Chassis'
              : 'Edit Chassis',
          contentInset: const EdgeInsets.fromLTRB(0, 16, 0, 14),
          actions: readOnly
              ? [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Close'),
                  ),
                ]
              : [
                  TextButton(
                    onPressed: isSaving
                        ? null
                        : () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            final resolvedName = name.text.trim();
                            if (resolvedName.isEmpty) {
                              AppSnackbar.showError(
                                dialogContext,
                                'Name is required.',
                              );
                              return;
                            }
                            setDialogState(() => isSaving = true);
                            _traceOffline(
                              'modal save pressed editing=${item != null}',
                            );
                            final now = DateTime.now();
                            final next = Chassis(
                              id: item?.id ?? 0,
                              submissionKey: item?.submissionKey,
                              name: resolvedName,
                              isActive: isActive.value,
                              currentStatus: selectedStatus,
                              bookingReferenceId: selectedBookingId,
                              driverReferenceId: selectedBookingId == null
                                  ? null
                                  : selectedDriverId,
                              location: location.text.trim().isEmpty
                                  ? null
                                  : location.text.trim(),
                              createdAt: item?.createdAt ?? now,
                              updatedAt: now,
                            );
                            try {
                              await ChassisRequest.instance.saveChassis(
                                next,
                                previousBookingId: item?.bookingReferenceId,
                                baseUpdatedAt: item?.updatedAt,
                              );
                              unawaited(
                                FieldTypeHistoryService.instance
                                    .record(historyAccount, {
                                      'chassis:name': next.name,
                                      'chassis:location': next.location ?? '',
                                    }, now),
                              );
                              _traceOffline('modal save resolved; closing');
                              if (dialogContext.mounted) {
                                Navigator.of(dialogContext).pop(true);
                              }
                            } catch (error) {
                              _traceOffline('modal save failed error=$error');
                              if (!dialogContext.mounted) return;
                              setDialogState(() => isSaving = false);
                              AppSnackbar.showError(
                                dialogContext,
                                'We could not save the chassis right now.',
                              );
                            }
                          },
                    child: isSaving
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
          child: IgnorePointer(
            ignoring: readOnly,
            child: AdminModalFormBody(
              children: [
                AdminModalFieldsSection(
                  children: [
                    TypeHistoryInput(
                      controller: name,
                      historyKey: readOnly ? null : 'chassis:name',
                      inputFormatters: const [NameCaseTextInputFormatter()],
                      child: AdminModalTextField(
                        controller: name,
                        label: 'Name',
                        bottomPadding: 0,
                        minHeight: 0,
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                    const SizedBox(height: 12),
                    AdminDropdownFormField<String>(
                      initialValue: item == null ? null : selectedStatus,
                      iconEnabledColor: AppColors.primaryColor,
                      style: adminDropdownDisplayTextStyle,
                      decoration: adminFormInputDecoration(
                        'Status',
                        radius: 16,
                        minHeight: adminModalFieldMinHeight,
                      ),
                      items: Chassis.statuses
                          .map(
                            (status) => DropdownMenuItem<String>(
                              value: status,
                              child: Text(
                                chassisStatusLabel(status),
                                style: adminDropdownDisplayTextStyle,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) selectedStatus = value;
                      },
                    ),
                    const SizedBox(height: 6),
                    AdminDropdownFormField<String>(
                      initialValue: selectedBookingId,
                      iconEnabledColor: AppColors.primaryColor,
                      style: adminDropdownDisplayTextStyle,
                      decoration: adminFormInputDecoration(
                        'Booking',
                        radius: 16,
                        minHeight: adminModalFieldMinHeight,
                      ),
                      items: _bookingDropdownItems(),
                      onChanged: (value) => selectedBookingId =
                          value == _noBookingOptionValue ? null : value,
                    ),
                    const SizedBox(height: 6),
                    AdminDropdownFormField<String>(
                      initialValue: selectedDriverId,
                      iconEnabledColor: AppColors.primaryColor,
                      style: adminDropdownDisplayTextStyle,
                      decoration: adminFormInputDecoration(
                        'Driver',
                        radius: 16,
                        minHeight: adminModalFieldMinHeight,
                      ),
                      items: _driverDropdownItems(),
                      onChanged: (value) => selectedDriverId =
                          value == _noDriverOptionValue ? null : value,
                    ),
                    const SizedBox(height: 6),
                    ValueListenableBuilder<int>(
                      valueListenable: LocationOptionRegistry.revision,
                      builder: (context, revision, child) => TypeHistoryInput(
                        controller: location,
                        historyKey: readOnly ? null : 'chassis:location',
                        browseOptionsOnFocus: true,
                        options: {
                          'Garage',
                          ...LocationOptionRegistry.options(
                            'destination',
                            const [],
                          ),
                          ...LocationOptionRegistry.options(
                            'destination_barangay',
                            const [],
                          ),
                          ..._items
                              .map((chassis) => chassis.location?.trim() ?? '')
                              .where((value) => value.isNotEmpty),
                        }.toList(growable: false),
                        child: AdminModalTextField(
                          controller: location,
                          label: 'Location',
                          bottomPadding: 0,
                          minHeight: 0,
                          textInputAction: TextInputAction.done,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ValueListenableBuilder<bool>(
                      valueListenable: isActive,
                      builder: (context, value, _) => AdminModalToggleRow(
                        title: 'Active',
                        value: value,
                        onChanged: (nextValue) => isActive.value = nextValue,
                        leftInset: 0,
                        rightInset: 0,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // A dialog result can resolve while its exit animation is still rebuilding
    // its fields. Dispose external notifiers only after that route is gone.
    Future<void>.delayed(const Duration(milliseconds: 250), () {
      name.dispose();
      location.dispose();
      isActive.dispose();
    });
    if (saved != true) return;
  }

  bool get _canOpenUsers => RoleAccessService.instance.canAccess(
    DispatcherAccessCapability.usersRead,
  );

  bool _openingRelatedPage = false;

  Future<void> _openContactUser(UserModel user) async {
    if (_openingRelatedPage || !_canOpenUsers || user.id?.isNotEmpty != true) {
      return;
    }
    _openingRelatedPage = true;
    try {
      final currentUser = await AuthRequest.instance.getCurrentUser();
      if (!mounted || currentUser == null || !_canOpenUsers) {
        return;
      }
      await AdminUsersView.openDetailPage(
        context,
        currentUser: currentUser,
        viewedUser: _historyUsers[user.id] ?? user,
      );
    } finally {
      _openingRelatedPage = false;
    }
  }

  Future<void> _openBooking(String? bookingId) async {
    if (_openingRelatedPage || bookingId == null) {
      return;
    }
    final booking = _bookingOptions
        .where((item) => item.id == bookingId)
        .firstOrNull;
    if (booking == null) {
      return;
    }
    _openingRelatedPage = true;
    try {
      final currentUser = await AuthRequest.instance.getCurrentUser();
      if (!mounted || currentUser == null) {
        return;
      }
      await AdminBookingsView.openDetailPage(
        context,
        currentUser: currentUser,
        booking: booking,
      );
    } finally {
      _openingRelatedPage = false;
    }
  }

  void _traceOffline(String message) {}

  _ChassisContact _clientContactForBooking(String? bookingId) {
    final bookingIdText = bookingId?.toString();
    for (final booking in _bookingOptions) {
      if (booking.id != bookingIdText) continue;
      return _ChassisContact.fromValues(
        BookingRecordCard.outputFieldDisplayValue(
          booking.statusOutputs,
          'representative_name',
        ),
        BookingRecordCard.outputFieldDisplayValue(
          booking.statusOutputs,
          'representative_phone',
        ),
        user: _historyUsers[booking.client?.id] ?? booking.client,
      );
    }
    return const _ChassisContact.empty();
  }

  _ChassisContact _driverContactForId(String? driverId) {
    final driverIdText = driverId?.toString();
    for (final driver in _driverOptions) {
      if (driver.id == driverIdText) return _ChassisContact.fromUser(driver);
    }
    return const _ChassisContact.empty();
  }

  List<DropdownMenuItem<String>> _bookingDropdownItems() => [
    const DropdownMenuItem<String>(
      value: _noBookingOptionValue,
      child: Text('No Booking', style: adminDropdownDisplayTextStyle),
    ),
    ..._bookingOptions
        .where((booking) => booking.id?.trim().isNotEmpty == true)
        .map(
          (booking) => DropdownMenuItem<String>(
            value: booking.id,
            child: Text(
              _bookingOptionLabel(booking),
              overflow: TextOverflow.ellipsis,
              style: adminDropdownDisplayTextStyle,
            ),
          ),
        ),
  ];

  List<DropdownMenuItem<String>> _driverDropdownItems() => [
    const DropdownMenuItem<String>(
      value: _noDriverOptionValue,
      child: Text('No Driver', style: adminDropdownDisplayTextStyle),
    ),
    ..._driverOptions
        .where((driver) => driver.id?.trim().isNotEmpty == true)
        .map(
          (driver) => DropdownMenuItem<String>(
            value: driver.id,
            child: Text(
              _driverOptionLabel(driver),
              overflow: TextOverflow.ellipsis,
              style: adminDropdownDisplayTextStyle,
            ),
          ),
        ),
  ];

  String _bookingOptionLabel(Booking booking) {
    final id = booking.id ?? '-';
    final status = booking.clientStatus?.trim();
    return status == null || status.isEmpty
        ? 'Booking $id'
        : 'Booking $id | ${toTitleCase(status.replaceAll('_', ' '))}';
  }

  String _driverOptionLabel(UserModel driver) {
    final name = driver.name?.trim();
    return name == null || name.isEmpty
        ? 'Driver ${driver.id ?? '-'}'
        : '${driver.id ?? '-'} | $name';
  }

  bool _isWithinRange(DateTime? value, DateTime? start, DateTime? end) {
    if (value == null) return true;
    final day = DateTime(value.year, value.month, value.day);
    if (start != null) {
      final first = DateTime(start.year, start.month, start.day);
      if (day.isBefore(first)) return false;
    }
    if (end != null) {
      final last = DateTime(end.year, end.month, end.day);
      if (day.isAfter(last)) return false;
    }
    return true;
  }

  double _resolvedChassisColumnWidth(
    BuildContext context,
    TextScaler textScaler,
    String header,
    String sample,
    TextStyle valueStyle,
  ) {
    final measured = AdminListMeasurements.maxTextWidth(
      context,
      textScaler,
      header,
      _headerStyle,
      sample,
      valueStyle,
    );
    return AdminListMeasurements.resolvedColumnWidth(
      measured,
      trailingPadding: _defaultTrailingPadding,
      extraWidthAllowance: _extraWidthAllowance,
    );
  }

  double _resolvedChassisStatusColumnWidth(
    BuildContext context,
    TextScaler textScaler,
    String sample,
  ) {
    const pillTextStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w700);
    final headerWidth = AdminListMeasurements.measureTextWidth(
      context,
      textScaler,
      'Status',
      _headerStyle,
    );
    final pillWidth =
        AdminListMeasurements.measureTextWidth(
          context,
          textScaler,
          sample,
          pillTextStyle,
        ) +
        26; // Meta pill: 12px on each side plus its 1px borders.
    return AdminListMeasurements.resolvedColumnWidth(
      AdminListMeasurements.maxValue(headerWidth, pillWidth),
      trailingPadding: _defaultTrailingPadding,
      extraWidthAllowance: _extraWidthAllowance,
    );
  }
}

class _ChassisHeaderRow extends StatelessWidget {
  const _ChassisHeaderRow({
    required this.idWidth,
    required this.nameWidth,
    required this.clientWidth,
    required this.driverWidth,
    required this.bookingWidth,
    required this.locationWidth,
    required this.statusWidth,
    required this.elapsedWidth,

    required this.actionsWidth,
  });

  final double idWidth;
  final double nameWidth;
  final double clientWidth;
  final double driverWidth;
  final double bookingWidth;
  final double locationWidth;
  final double statusWidth;
  final double elapsedWidth;

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
            width: clientWidth,
            child: const AdminListHeaderCell(label: 'Client'),
          ),
          AdminListFixedSlot(
            width: driverWidth,
            child: const AdminListHeaderCell(label: 'Driver'),
          ),
          AdminListFixedSlot(
            width: bookingWidth,
            child: const AdminListHeaderCell(label: 'Booking'),
          ),
          AdminListFixedSlot(
            width: locationWidth,
            child: const AdminListHeaderCell(label: 'Location'),
          ),
          AdminListFixedSlot(
            width: statusWidth,
            child: const AdminListHeaderCell(label: 'Status'),
          ),
          AdminListFixedSlot(
            width: elapsedWidth,
            child: const AdminListHeaderCell(label: 'Time'),
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

class _ChassisDesktopRow extends StatelessWidget {
  const _ChassisDesktopRow({
    required this.item,
    required this.elapsed,
    required this.client,
    required this.driver,
    required this.idWidth,
    required this.nameWidth,
    required this.clientWidth,
    required this.driverWidth,
    required this.bookingWidth,
    required this.locationWidth,
    required this.statusWidth,
    required this.elapsedWidth,

    required this.actionsWidth,
    required this.actions,
    required this.onOpenBooking,
    this.onOpenClient,
    this.onOpenDriver,
  });

  final Chassis item;
  final Widget elapsed;
  final _ChassisContact client;
  final _ChassisContact driver;
  final double idWidth;
  final double nameWidth;
  final double clientWidth;
  final double driverWidth;
  final double bookingWidth;
  final double locationWidth;
  final double statusWidth;
  final double elapsedWidth;

  final double actionsWidth;
  final List<Widget> actions;
  final VoidCallback onOpenBooking;
  final VoidCallback? onOpenClient;
  final VoidCallback? onOpenDriver;

  @override
  Widget build(BuildContext context) {
    return AdminListItemCard(
      child: Row(
        children: [
          AdminListFixedSlot(
            width: idWidth,
            child: AdminListBodyCell(
              child: Text('${item.id}', style: _ChassisStyles.value),
            ),
          ),
          AdminListFixedSlot(
            width: nameWidth,
            child: AdminListBodyCell(
              child: Text(item.name, style: _ChassisStyles.title),
            ),
          ),
          AdminListFixedSlot(
            width: clientWidth,
            child: AdminListBodyCell(
              child: _ChassisContactText(
                contact: client,
                onOpen: onOpenClient,
                role: 'Client',
              ),
            ),
          ),
          AdminListFixedSlot(
            width: driverWidth,
            child: AdminListBodyCell(
              child: _ChassisContactText(
                contact: driver,
                onOpen: onOpenDriver,
                role: 'Driver',
              ),
            ),
          ),
          AdminListFixedSlot(
            width: bookingWidth,
            child: AdminListBodyCell(
              child: _ChassisBookingLink(
                bookingId: item.bookingReferenceId,
                onOpen: onOpenBooking,
              ),
            ),
          ),
          AdminListFixedSlot(
            width: locationWidth,
            child: AdminListBodyCell(
              child: Text(
                _chassisLocationLabel(item),
                style: _ChassisStyles.value,
              ),
            ),
          ),
          AdminListFixedSlot(
            width: statusWidth,
            child: AdminListBodyCell(
              child: ChassisStatusPill(status: item.currentStatus),
            ),
          ),
          AdminListFixedSlot(
            width: elapsedWidth,
            child: AdminListBodyCell(child: elapsed),
          ),
          AdminListTrailingActionsLane(
            width: actionsWidth,
            child: AdminListBodyCell(
              trailingPadding: 0,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: actions
                    .expand<Widget>(
                      (action) => [
                        action,
                        if (action != actions.last) const SizedBox(width: 8),
                      ],
                    )
                    .toList(growable: false),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChassisResponsiveCard extends StatelessWidget {
  const _ChassisResponsiveCard({
    required this.item,
    required this.elapsed,
    required this.client,
    required this.driver,
    required this.actions,
    required this.onOpenBooking,
    this.onOpenClient,
    this.onOpenDriver,
  });

  final Chassis item;
  final Widget elapsed;
  final _ChassisContact client;
  final _ChassisContact driver;
  final List<Widget> actions;
  final VoidCallback onOpenBooking;
  final VoidCallback? onOpenClient;
  final VoidCallback? onOpenDriver;

  @override
  Widget build(BuildContext context) {
    return AdminListItemCard(
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final singleColumn = constraints.maxWidth < 520;
          final fields = [
            ('ID', '${item.id}', false),
            ('Name', item.name, true),
            ('Client', client.display, false),
            ('Driver', driver.display, false),
            ('Location', _chassisLocationLabel(item), false),
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Spacer(),
                  Wrap(spacing: 8, children: actions),
                ],
              ),
              const SizedBox(height: 18),
              _ChassisBookingLink(
                bookingId: item.bookingReferenceId,
                onOpen: onOpenBooking,
                showLabel: true,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  ...fields.map(
                    (field) => field.$1 == 'Client' || field.$1 == 'Driver'
                        ? SizedBox(
                            width: singleColumn
                                ? constraints.maxWidth
                                : (constraints.maxWidth - 16) / 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AdminListHeaderCell(label: field.$1),
                                const SizedBox(height: 6),
                                _ChassisContactText(
                                  contact: field.$1 == 'Client'
                                      ? client
                                      : driver,
                                  onOpen: field.$1 == 'Client'
                                      ? onOpenClient
                                      : onOpenDriver,
                                  role: field.$1,
                                ),
                              ],
                            ),
                          )
                        : AdminListResponsiveField(
                            title: field.$1,
                            value: field.$2,
                            isTitle: field.$3,
                            centered: false,
                            width: singleColumn
                                ? constraints.maxWidth
                                : (constraints.maxWidth - 16) / 2,
                          ),
                  ),
                  SizedBox(
                    width: singleColumn
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 16) / 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Status',
                          style: TextStyle(
                            color: AppColors.primaryColor.withValues(
                              alpha: 0.72,
                            ),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ChassisStatusPill(status: item.currentStatus),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: singleColumn
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 16) / 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const AdminListHeaderCell(label: 'Time'),
                        const SizedBox(height: 6),
                        elapsed,
                      ],
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ChassisContact {
  const _ChassisContact({required this.name, required this.phone, this.user});

  const _ChassisContact.empty() : name = '-', phone = '-', user = null;

  final String name;
  final String phone;
  final UserModel? user;

  bool get isEmpty => name == '-' && phone == '-';

  String get display => name;

  factory _ChassisContact.fromUser(UserModel? user) {
    if (user == null) return const _ChassisContact.empty();
    return _ChassisContact.fromValues(user.name, user.phone, user: user);
  }

  factory _ChassisContact.fromValues(
    String? nameValue,
    String? phoneValue, {
    UserModel? user,
  }) {
    final name =
        (nameValue?.trim().isNotEmpty == true && nameValue != '-'
                ? nameValue
                : user?.name)
            ?.trim();
    final phone = phoneValue?.trim();
    if ((name == null || name.isEmpty) &&
        (phone == null || phone.isEmpty) &&
        user == null) {
      return const _ChassisContact.empty();
    }
    return _ChassisContact(
      user: user,
      name: name == null || name.isEmpty || name == '-' ? '-' : name,
      phone: phone == null || phone.isEmpty || phone == '-' ? '-' : phone,
    );
  }
}

class _ChassisContactText extends StatelessWidget {
  const _ChassisContactText({
    required this.contact,
    required this.role,
    this.onOpen,
  });
  final _ChassisContact contact;
  final String role;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final link = Text(
      contact.display,
      softWrap: true,
      style: onOpen != null ? _ChassisStyles.link : _ChassisStyles.value,
    );
    if (onOpen == null) return link;
    return Tooltip(
      message: 'Open $role account',
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: link,
        ),
      ),
    );
  }
}

class _ChassisBookingLink extends StatelessWidget {
  const _ChassisBookingLink({
    required this.bookingId,
    required this.onOpen,
    this.showLabel = false,
  });

  final String? bookingId;
  final VoidCallback onOpen;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final value = bookingId?.toString() ?? '-';
    final canOpen = bookingId != null;
    final link = Text(
      value,
      style: canOpen ? _ChassisStyles.link : _ChassisStyles.value,
    );
    final interactiveLink = canOpen
        ? InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: link,
            ),
          )
        : link;
    if (!showLabel) return interactiveLink;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Booking',
          style: TextStyle(
            color: AppColors.primaryColor.withValues(alpha: 0.72),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        interactiveLink,
      ],
    );
  }
}

class _ChassisStyles {
  static const link = TextStyle(
    color: AppColors.primaryColor,
    fontWeight: FontWeight.w700,
    decoration: TextDecoration.underline,
    decorationColor: AppColors.primaryColor,
    height: 1.2,
  );
  static const title = TextStyle(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );
  static const value = TextStyle(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );
}

class _ChassisLoadErrorState extends StatelessWidget {
  const _ChassisLoadErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AdminListItemCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: AppColors.primaryColor.withValues(alpha: 0.72),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _ChassisEmptyState extends StatelessWidget {
  const _ChassisEmptyState({required this.message});

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

class _ChassisFiltersPanel extends StatefulWidget {
  const _ChassisFiltersPanel({
    required this.iconOnly,
    required this.status,
    required this.active,
    required this.createdStart,
    required this.createdEnd,
    required this.updatedStart,
    required this.updatedEnd,
    required this.onStatusChanged,
    required this.onActiveChanged,
    required this.onCreatedStartChanged,
    required this.onCreatedEndChanged,
    required this.onUpdatedStartChanged,
    required this.onUpdatedEndChanged,
    required this.onClear,
  });

  final bool iconOnly;
  final String status;
  final String active;
  final DateTime? createdStart;
  final DateTime? createdEnd;
  final DateTime? updatedStart;
  final DateTime? updatedEnd;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onActiveChanged;
  final ValueChanged<DateTime?> onCreatedStartChanged;
  final ValueChanged<DateTime?> onCreatedEndChanged;
  final ValueChanged<DateTime?> onUpdatedStartChanged;
  final ValueChanged<DateTime?> onUpdatedEndChanged;
  final VoidCallback onClear;

  @override
  State<_ChassisFiltersPanel> createState() => _ChassisFiltersPanelState();
}

class _ChassisFiltersPanelState extends State<_ChassisFiltersPanel> {
  @override
  Widget build(BuildContext context) => AdminListDynamicFiltersPanel(
    iconOnly: widget.iconOnly,
    filters: [
      AdminListDropdownFilterConfig(
        label: 'Status',
        value: widget.status,
        items: ['All', ...Chassis.statuses],
        displayValue: (status) =>
            status == 'All' ? status : chassisStatusLabel(status),
        onChanged: widget.onStatusChanged,
        itemBuilder: (status) => status == 'All'
            ? Text('All', style: adminDropdownDisplayTextStyle)
            : ChassisStatusOptionLabel(
                label: chassisStatusLabel(status),
                status: status,
              ),
      ),
      AdminListDropdownFilterConfig(
        label: 'Is Active',
        value: widget.active,
        items: const ['All', 'Active', 'Inactive'],
        onChanged: widget.onActiveChanged,
      ),
      AdminListDateFilterConfig(
        label: 'Created Start',
        value: widget.createdStart,
        onSelected: widget.onCreatedStartChanged,
        formatter: _formatChassisFilterDateValue,
      ),
      AdminListDateFilterConfig(
        label: 'Created End',
        value: widget.createdEnd,
        onSelected: widget.onCreatedEndChanged,
        formatter: _formatChassisFilterDateValue,
      ),
      AdminListDateFilterConfig(
        label: 'Updated Start',
        value: widget.updatedStart,
        onSelected: widget.onUpdatedStartChanged,
        formatter: _formatChassisFilterDateValue,
      ),
      AdminListDateFilterConfig(
        label: 'Updated End',
        value: widget.updatedEnd,
        onSelected: widget.onUpdatedEndChanged,
        formatter: _formatChassisFilterDateValue,
      ),
    ],
    onClear: widget.onClear,
  );
}

String _formatChassisFilterDateValue(DateTime? value) {
  if (value == null) return '';
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
