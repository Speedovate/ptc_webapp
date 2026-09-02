import 'dart:async';

import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/chassis.dart';
import 'package:webapp/models/support_thread.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/requests/booking.request.dart';
import 'package:webapp/requests/chassis.request.dart';
import 'package:webapp/requests/support.request.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/view_models/admin/admin_home.vm.dart';
import 'package:webapp/view_models/admin/admin_flow.vm.dart';
import 'package:webapp/view_models/admin/admin_users.vm.dart';
import 'package:webapp/views/admin/admin_bookings.dart';
import 'package:webapp/views/admin/admin_chassis.dart';
import 'package:webapp/views/admin/admin_access.dart';
import 'package:webapp/views/admin/admin_analytics.dart';
import 'package:webapp/views/admin/admin_dashboard.dart';
import 'package:webapp/views/admin/admin_fields.dart';
import 'package:webapp/views/admin/admin_forms.dart';
import 'package:webapp/views/admin/admin_statuses.dart';
import 'package:webapp/views/admin/admin_users.dart';
import 'package:webapp/views/admin/admin_vehicle_makes.dart';
import 'package:webapp/views/admin/admin_vehicle_sizes.dart';
import 'package:webapp/views/admin/admin_vehicle_types.dart';
import 'package:webapp/views/shared/profile_view.dart';
import 'package:webapp/views/shared/support_center_view.dart';
import 'package:webapp/widgets/shared/app_page_loading_overlay.dart';
import 'package:webapp/widgets/shared/admin_shell_layout_scope.dart';
import 'package:webapp/widgets/shared/booking_section_navigation_scope.dart';
import 'package:webapp/widgets/shared/platform_shell.dart';
import 'package:webapp/widgets/shared/support_section_navigation_scope.dart';
import 'package:webapp/widgets/shared/user_bookings_section.dart';
import 'package:webapp/widgets/sidebar_menu_item.dart';
import 'package:webapp/models/dispatcher_access_config.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:webapp/utils/performance_trace.dart';

class AdminHome extends StatefulWidget {
  const AdminHome({
    super.key,
    required this.user,
    required this.onLogout,
    required this.onUserUpdated,
    this.isQuickLoggedIn = false,
  });

  final UserModel user;
  final VoidCallback onLogout;
  final Future<void> Function() onUserUpdated;
  final bool isQuickLoggedIn;

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  final AdminHomeViewModel _viewModel = AdminHomeViewModel();
  final AdminFlowViewModel _flowViewModel = AdminFlowViewModel();
  late final AdminUsersViewModel _profileUsersViewModel;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AuthRepository _authRepository = AuthRequest.instance;
  final RoleAccessService _roleAccessService = RoleAccessService.instance;
  final SupportRequest _supportRequest = SupportRequest.instance;
  late UserModel _shellUser;
  StreamSubscription<List<Booking>>? _bookingsBadgeSubscription;
  StreamSubscription<List<Chassis>>? _chassisBadgeSubscription;
  StreamSubscription<List<SupportThread>>? _supportBadgeSubscription;
  StreamSubscription<void>? _supportReadBadgeSubscription;
  List<Booking> _sidebarBookings = const <Booking>[];
  List<Chassis> _sidebarChassis = const <Chassis>[];
  List<SupportThread> _sidebarThreads = const <SupportThread>[];
  Map<String, String> _sidebarThreadReadMarkers = const <String, String>{};
  bool _hasResolvedSidebarThreadReadMarkers = false;
  bool _isUploadingProfilePhoto = false;
  String? _supportInitialTopicKey;
  String? _supportInitialBookingId;
  String? _supportInitialUserId;
  int _supportViewTick = 0;
  Booking? _bookingInitialSelection;

  void _log(String message) {
    // Temporary debug logging removed.
  }

  @override
  void initState() {
    super.initState();
    PerformanceTrace.event(
      'admin-home',
      'init user=${widget.user.id ?? '-'} role=${widget.user.role ?? '-'}',
    );
    _shellUser = widget.user;
    _profileUsersViewModel = AdminUsersViewModel(
      fallbackCurrentUser: _shellUser,
    );
    unawaited(
      _profileUsersViewModel.loadUsers(fallbackCurrentUser: _shellUser),
    );
    _startSidebarBadgeSync();
  }

  @override
  void didUpdateWidget(covariant AdminHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.id != widget.user.id ||
        oldWidget.user.updatedAt != widget.user.updatedAt) {
      _shellUser = widget.user;
      if (oldWidget.user.id != widget.user.id) {
        _startSidebarBadgeSync();
      }
    }
  }

  @override
  void dispose() {
    PerformanceTrace.event('admin-home', 'dispose');
    _bookingsBadgeSubscription?.cancel();
    _chassisBadgeSubscription?.cancel();
    _supportBadgeSubscription?.cancel();
    _supportReadBadgeSubscription?.cancel();
    _flowViewModel.dispose();
    _profileUsersViewModel.dispose();
    super.dispose();
  }

  void _startSidebarBadgeSync() {
    _bookingsBadgeSubscription?.cancel();
    _chassisBadgeSubscription?.cancel();
    _supportBadgeSubscription?.cancel();
    _supportReadBadgeSubscription?.cancel();

    final userId = _shellUser.id?.trim();
    _sidebarBookings = BookingRequest.hydratedBookingsSnapshot;
    _sidebarChassis = ChassisRequest.instance.hydratedChassisSnapshot;
    _sidebarThreads = SupportRequest.hydratedAllThreadsSnapshot;
    _sidebarThreadReadMarkers = const <String, String>{};
    _hasResolvedSidebarThreadReadMarkers = false;

    unawaited(BookingRequest.instance.initialize());
    _bookingsBadgeSubscription = BookingRequest.instance.watchBookings().listen(
      (bookings) {
        if (!mounted) {
          return;
        }
        setState(() {
          _sidebarBookings = List<Booking>.from(bookings);
        });
        PerformanceTrace.event(
          'admin-home',
          'sidebar bookings update count=${bookings.length}',
        );
      },
    );
    _chassisBadgeSubscription = ChassisRequest.instance.watchChassis().listen((
      chassis,
    ) {
      if (!mounted) {
        return;
      }
      setState(() {
        _sidebarChassis = List<Chassis>.from(chassis);
      });
    });
    _supportBadgeSubscription = _supportRequest.watchAllThreads().listen((
      threads,
    ) {
      if (!mounted) {
        return;
      }
      setState(() {
        _sidebarThreads = List<SupportThread>.from(threads);
      });
      PerformanceTrace.event(
        'admin-home',
        'sidebar support update count=${threads.length}',
      );
    });
    if (userId == null || userId.isEmpty) {
      return;
    }
    _supportReadBadgeSubscription = _supportRequest
        .watchThreadReadMarkerUpdates(userId)
        .listen((_) => unawaited(_loadSidebarThreadReadMarkers(userId)));
    unawaited(_loadSidebarThreadReadMarkers(userId));
  }

  Future<void> _loadSidebarThreadReadMarkers(String userId) async {
    final markers = await _supportRequest.readThreadReadMarkers(userId);
    if (!mounted || _shellUser.id?.trim() != userId) {
      return;
    }
    setState(() {
      _sidebarThreadReadMarkers = markers;
      _hasResolvedSidebarThreadReadMarkers = true;
    });
    PerformanceTrace.event(
      'admin-home',
      'sidebar read markers resolved count=${markers.length}',
    );
  }

  int get _pendingBookingsBadgeCount => _sidebarBookings.where((booking) {
    return (booking.clientStatus ?? '').trim().toLowerCase() == 'pending';
  }).length;

  int get _unbilledBookingsBadgeCount => _sidebarBookings.where((booking) {
    return (booking.billingStatus ?? '').trim().toLowerCase() == 'unbilled';
  }).length;

  int get _emptyChassisBadgeCount => _sidebarChassis.where((chassis) {
    return chassis.isActive && chassis.currentStatus == Chassis.empty;
  }).length;

  Widget _vehiclesTrailing(AdminHomeViewModel vm) {
    final badge = vm.isVehiclesExpanded
        ? null
        : _sidebarBadge(_emptyChassisBadgeCount);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (badge != null) ...[badge, const SizedBox(width: 6)],
        Icon(
          vm.isVehiclesExpanded
              ? Icons.keyboard_arrow_down_rounded
              : Icons.chevron_right_rounded,
          color: Colors.white,
          size: 18,
        ),
      ],
    );
  }

  int get _unreadSupportBadgeCount {
    // Threads can arrive from cache/realtime before the current user's read
    // markers. Do not briefly label every thread as unread during that race.
    if (!_hasResolvedSidebarThreadReadMarkers) {
      return 0;
    }
    final currentUserId = _shellUser.id?.trim();
    if (currentUserId == null || currentUserId.isEmpty) {
      return 0;
    }
    return _sidebarThreads.where((thread) {
      final threadId = thread.id?.trim();
      final senderId = thread.lastSenderUserId?.trim();
      if (threadId == null ||
          threadId.isEmpty ||
          senderId == null ||
          senderId.isEmpty ||
          senderId == currentUserId ||
          !thread.hasConversation) {
        return false;
      }
      return _sidebarThreadReadMarkers[threadId] !=
          _supportRequest.threadReadMarkerForThread(thread);
    }).length;
  }

  Widget? _sidebarBadge(int count) {
    if (count <= 0) {
      return null;
    }
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 24),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFE31E24),
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }

  Future<void> _saveProfileChanges(ProfilePendingProfileChanges changes) async {
    if (_isUploadingProfilePhoto || !changes.hasChanges) {
      return;
    }
    final userId = _shellUser.id?.trim();
    if (userId == null || userId.isEmpty) {
      throw const AuthFailure('User ID is required.');
    }

    setState(() {
      _isUploadingProfilePhoto = true;
    });
    try {
      var updatedUser = _shellUser;
      final photoUpload = changes.photoUpload;
      if (photoUpload != null) {
        updatedUser = await _authRepository.saveUserPhoto(
          userId: userId,
          bytes: photoUpload.bytes,
          fileName: photoUpload.fileName,
          mimeType: photoUpload.mimeType,
          size: photoUpload.size,
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _shellUser = updatedUser;
      });
      await widget.onUserUpdated();
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingProfilePhoto = false;
        });
      }
    }
  }

  Future<void> _openProfileEditDialog() async {
    await AdminUsersView.showEditUserDialog(
      context,
      _profileUsersViewModel,
      _shellUser,
      () async {
        await widget.onUserUpdated();
        final refreshedUser = await _authRepository.getCurrentUser();
        if (!mounted || refreshedUser == null) {
          return;
        }
        setState(() {
          _shellUser = refreshedUser;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    PerformanceTrace.build('admin-home');
    return AnimatedBuilder(
      animation: _roleAccessService,
      builder: (context, _) {
        return ViewModelBuilder<AdminHomeViewModel>.reactive(
          viewModelBuilder: () => _viewModel,
          builder: (context, vm, _) {
            final width = MediaQuery.of(context).size.width;
            final isCompact = width < 1100;
            final showRail = !isCompact && vm.showDrawer;
            final overlayVisible = _isUploadingProfilePhoto;
            final resolvedSection = _resolvedSection(vm.selectedSection);
            _log(
              'build user=${_shellUser.id ?? "-"} role=${_shellUser.role ?? "-"} selected=${vm.selectedSection.name} resolved=${resolvedSection.name} compact=$isCompact showRail=$showRail overlay=$overlayVisible',
            );

            return PlatformShell(
              scaffoldKey: _scaffoldKey,
              user: _shellUser,
              title: _selectedSectionTitle(vm),
              isCompact: isCompact,
              showRail: showRail,
              onToggleNavigation: vm.toggleDrawer,
              onProfile: () => vm.selectSection(AdminSection.profile),
              onLogout: widget.onLogout,
              logoutLabel: widget.isQuickLoggedIn ? 'Go Back' : 'Logout',
              sidebar: _buildSidebar(vm, isCompact: isCompact),
              body: SupportSectionNavigationScope(
                onOpenSupport:
                    ({
                      String? initialTopicKey,
                      String? initialBookingId,
                      String? initialUserId,
                    }) {
                      setState(() {
                        _supportInitialTopicKey = initialTopicKey;
                        _supportInitialBookingId = initialBookingId;
                        _supportInitialUserId = initialUserId;
                        _supportViewTick++;
                      });
                      vm.selectSection(AdminSection.support);
                    },
                child: BookingSectionNavigationScope(
                  onOpenBooking: (booking) {
                    setState(() => _bookingInitialSelection = booking);
                    vm.selectSection(AdminSection.bookings);
                  },
                  child: AppPageLoadingOverlay(
                    isVisible: overlayVisible,
                    message: 'Uploading profile photo ...',
                    child: KeyedSubtree(
                      key: ValueKey(
                        '${vm.selectedSection}:${vm.selectedSettingsSection}',
                      ),
                      child: AdminShellLayoutScope(
                        filtersRightGap: showRail ? 44 : 24,
                        // With no rail, align every filter panel with the
                        // toolbar action's outer right edge.
                        alignFiltersToToolbarAction: !showRail,
                        child: _buildSelectedSection(vm.selectedSection),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  bool get _canReadDashboard => _roleAccessService.canAccess(
    DispatcherAccessCapability.dashboardRead,
    role: _shellUser.role,
  );

  // Analytics is a read-only view of the dashboard booking data.
  bool get _canReadAnalytics => _canReadDashboard;

  bool get _canReadBookings => _roleAccessService.canAccess(
    DispatcherAccessCapability.bookingsRead,
    role: _shellUser.role,
  );

  bool get _canReadUsers => _roleAccessService.canAccess(
    DispatcherAccessCapability.usersRead,
    role: _shellUser.role,
  );

  bool get _canReadSupport => _roleAccessService.canAccess(
    DispatcherAccessCapability.supportRead,
    role: _shellUser.role,
  );

  bool get _canReadProfile => _roleAccessService.canAccess(
    DispatcherAccessCapability.profileRead,
    role: _shellUser.role,
  );

  bool get _canUpdateProfile => _roleAccessService.canAccess(
    DispatcherAccessCapability.profileUpdate,
    role: _shellUser.role,
  );

  bool get _canReadRoles => _roleAccessService.canAccess(
    DispatcherAccessCapability.roleAccessRead,
    role: _shellUser.role,
  );

  bool get _canAccessVehicles => _roleAccessService.hasAnyAccess(const [
    DispatcherAccessCapability.vehicleMakesRead,
    DispatcherAccessCapability.vehicleTypesRead,
    DispatcherAccessCapability.vehicleSizesRead,
    DispatcherAccessCapability.chassisRead,
  ], role: _shellUser.role);

  bool get _canReadVehicleMakes => _roleAccessService.canAccess(
    DispatcherAccessCapability.vehicleMakesRead,
    role: _shellUser.role,
  );

  bool get _canReadVehicleTypes => _roleAccessService.canAccess(
    DispatcherAccessCapability.vehicleTypesRead,
    role: _shellUser.role,
  );

  bool get _canReadVehicleSizes => _roleAccessService.canAccess(
    DispatcherAccessCapability.vehicleSizesRead,
    role: _shellUser.role,
  );

  bool get _canReadChassis => _roleAccessService.canAccess(
    DispatcherAccessCapability.chassisRead,
    role: _shellUser.role,
  );

  bool get _canAccessFlows => _roleAccessService.hasAnyAccess(const [
    DispatcherAccessCapability.statusesRead,
    DispatcherAccessCapability.formsRead,
    DispatcherAccessCapability.fieldsRead,
  ], role: _shellUser.role);

  bool get _canReadStatuses => _roleAccessService.canAccess(
    DispatcherAccessCapability.statusesRead,
    role: _shellUser.role,
  );

  bool get _canReadForms => _roleAccessService.canAccess(
    DispatcherAccessCapability.formsRead,
    role: _shellUser.role,
  );

  bool get _canReadFields => _roleAccessService.canAccess(
    DispatcherAccessCapability.fieldsRead,
    role: _shellUser.role,
  );

  AdminSection _resolvedSection(AdminSection section) {
    if (section == AdminSection.dashboard && !_canReadDashboard) {
      return _fallbackSection();
    }
    if (section == AdminSection.analytics && !_canReadAnalytics) {
      return _fallbackSection();
    }
    if (section == AdminSection.bookings && !_canReadBookings) {
      return _fallbackSection();
    }
    if (section == AdminSection.vehicles && !_canAccessVehicles) {
      return _fallbackSection();
    }
    if (section == AdminSection.settings && !_canAccessFlows) {
      return _fallbackSection();
    }
    if (section == AdminSection.users && !_canReadUsers) {
      return _fallbackSection();
    }
    if (section == AdminSection.support && !_canReadSupport) {
      return _fallbackSection();
    }
    if (section == AdminSection.profile && !_canReadProfile) {
      return _fallbackSection();
    }
    if (section == AdminSection.access && !_canReadRoles) {
      return _fallbackSection();
    }
    return section;
  }

  AdminSection _fallbackSection() {
    if (_canReadDashboard) {
      return AdminSection.dashboard;
    }
    if (_canReadBookings) {
      return AdminSection.bookings;
    }
    if (_canReadSupport) {
      return AdminSection.support;
    }
    if (_canReadUsers) {
      return AdminSection.users;
    }
    return AdminSection.profile;
  }

  Widget _buildSidebar(AdminHomeViewModel vm, {required bool isCompact}) {
    return PlatformSidebarContainer(
      currentUser: _shellUser,
      onBrandTap: () {
        vm.selectSection(AdminSection.dashboard);
        if (isCompact && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
      children: [
        if (_canReadDashboard)
          SidebarMenuItem(
            label: AdminSection.dashboard.title,
            icon: _menuIcon(AdminSection.dashboard),
            isSelected: vm.selectedSection == AdminSection.dashboard,
            trailing: _sidebarBadge(_unbilledBookingsBadgeCount),
            onTap: () {
              vm.selectSection(AdminSection.dashboard);
              if (isCompact) {
                Navigator.of(context).pop();
              }
            },
          ),
        if (_canReadBookings)
          SidebarMenuItem(
            label: AdminSection.bookings.title,
            icon: _menuIcon(AdminSection.bookings),
            isSelected: vm.selectedSection == AdminSection.bookings,
            trailing: _sidebarBadge(_pendingBookingsBadgeCount),
            onTap: () {
              vm.selectSection(AdminSection.bookings);
              if (isCompact) {
                Navigator.of(context).pop();
              }
            },
          ),
        if (_canAccessVehicles)
          SidebarMenuItem(
            label: AdminSection.vehicles.title,
            icon: _menuIcon(AdminSection.vehicles),
            isSelected: false,
            trailing: _vehiclesTrailing(vm),
            onTap: vm.toggleVehiclesExpanded,
            children: vm.isVehiclesExpanded
                ? [
                    if (_canReadChassis)
                      SidebarMenuItem(
                        label: AdminVehiclesSection.chassis.title,
                        icon: Icons.rv_hookup_outlined,
                        isChild: true,
                        isSelected:
                            vm.selectedSection == AdminSection.vehicles &&
                            vm.selectedVehiclesSection ==
                                AdminVehiclesSection.chassis,
                        trailing: _sidebarBadge(_emptyChassisBadgeCount),
                        onTap: () {
                          vm.selectVehiclesSection(
                            AdminVehiclesSection.chassis,
                          );
                          if (isCompact) Navigator.of(context).pop();
                        },
                      ),
                    if (_canReadVehicleMakes)
                      SidebarMenuItem(
                        label: AdminVehiclesSection.makes.title,
                        icon: Icons.directions_car_filled,
                        isChild: true,
                        isSelected:
                            vm.selectedSection == AdminSection.vehicles &&
                            vm.selectedVehiclesSection ==
                                AdminVehiclesSection.makes,
                        onTap: () {
                          vm.selectVehiclesSection(AdminVehiclesSection.makes);
                          if (isCompact) {
                            Navigator.of(context).pop();
                          }
                        },
                      ),
                    if (_canReadVehicleTypes)
                      SidebarMenuItem(
                        label: AdminVehiclesSection.types.title,
                        icon: Icons.category_rounded,
                        isChild: true,
                        isSelected:
                            vm.selectedSection == AdminSection.vehicles &&
                            vm.selectedVehiclesSection ==
                                AdminVehiclesSection.types,
                        onTap: () {
                          vm.selectVehiclesSection(AdminVehiclesSection.types);
                          if (isCompact) {
                            Navigator.of(context).pop();
                          }
                        },
                      ),
                    if (_canReadVehicleSizes)
                      SidebarMenuItem(
                        label: AdminVehiclesSection.sizes.title,
                        icon: Icons.crop_16_9_rounded,
                        isChild: true,
                        isSelected:
                            vm.selectedSection == AdminSection.vehicles &&
                            vm.selectedVehiclesSection ==
                                AdminVehiclesSection.sizes,
                        onTap: () {
                          vm.selectVehiclesSection(AdminVehiclesSection.sizes);
                          if (isCompact) {
                            Navigator.of(context).pop();
                          }
                        },
                      ),
                  ]
                : const [],
          ),
        if (_canReadSupport)
          SidebarMenuItem(
            label: AdminSection.support.title,
            icon: _menuIcon(AdminSection.support),
            isSelected: vm.selectedSection == AdminSection.support,
            trailing: _sidebarBadge(_unreadSupportBadgeCount),
            onTap: () {
              vm.selectSection(AdminSection.support);
              if (isCompact) {
                Navigator.of(context).pop();
              }
            },
          ),
        if (_canReadRoles)
          SidebarMenuItem(
            label: AdminSection.access.title,
            icon: _menuIcon(AdminSection.access),
            isSelected: vm.selectedSection == AdminSection.access,
            onTap: () {
              vm.selectSection(AdminSection.access);
              if (isCompact) {
                Navigator.of(context).pop();
              }
            },
          ),
        if (_canAccessFlows)
          SidebarMenuItem(
            label: AdminSection.settings.title,
            icon: _menuIcon(AdminSection.settings),
            isSelected: false,
            trailing: Icon(
              vm.isSettingsExpanded
                  ? Icons.keyboard_arrow_down_rounded
                  : Icons.chevron_right_rounded,
              color: Colors.white,
              size: 18,
            ),
            onTap: vm.toggleSettingsExpanded,
            children: vm.isSettingsExpanded
                ? [
                    if (_canReadStatuses)
                      SidebarMenuItem(
                        label: AdminSettingsSection.statuses.title,
                        icon: Icons.flag_rounded,
                        isChild: true,
                        isSelected:
                            vm.selectedSection == AdminSection.settings &&
                            vm.selectedSettingsSection ==
                                AdminSettingsSection.statuses,
                        onTap: () {
                          vm.selectSettingsSection(
                            AdminSettingsSection.statuses,
                          );
                          if (isCompact) {
                            Navigator.of(context).pop();
                          }
                        },
                      ),
                    if (_canReadForms)
                      SidebarMenuItem(
                        label: AdminSettingsSection.forms.title,
                        icon: Icons.description_rounded,
                        isChild: true,
                        isSelected:
                            vm.selectedSection == AdminSection.settings &&
                            vm.selectedSettingsSection ==
                                AdminSettingsSection.forms,
                        onTap: () {
                          vm.selectSettingsSection(AdminSettingsSection.forms);
                          if (isCompact) {
                            Navigator.of(context).pop();
                          }
                        },
                      ),
                    if (_canReadFields)
                      SidebarMenuItem(
                        label: AdminSettingsSection.fields.title,
                        icon: Icons.list_alt_rounded,
                        isChild: true,
                        isSelected:
                            vm.selectedSection == AdminSection.settings &&
                            vm.selectedSettingsSection ==
                                AdminSettingsSection.fields,
                        onTap: () {
                          vm.selectSettingsSection(AdminSettingsSection.fields);
                          if (isCompact) {
                            Navigator.of(context).pop();
                          }
                        },
                      ),
                  ]
                : const [],
          ),
        if (_canReadUsers)
          SidebarMenuItem(
            label: AdminSection.users.title,
            icon: _menuIcon(AdminSection.users),
            isSelected: vm.selectedSection == AdminSection.users,
            onTap: () {
              vm.selectSection(AdminSection.users);
              if (isCompact) {
                Navigator.of(context).pop();
              }
            },
          ),
        if (_canReadProfile)
          SidebarMenuItem(
            label: AdminSection.profile.title,
            icon: _menuIcon(AdminSection.profile),
            isSelected: vm.selectedSection == AdminSection.profile,
            onTap: () {
              vm.selectSection(AdminSection.profile);
              if (isCompact) {
                Navigator.of(context).pop();
              }
            },
          ),
        if (_canReadAnalytics)
          SidebarMenuItem(
            label: AdminSection.analytics.title,
            icon: _menuIcon(AdminSection.analytics),
            isSelected: vm.selectedSection == AdminSection.analytics,
            onTap: () {
              vm.selectSection(AdminSection.analytics);
              if (isCompact) {
                Navigator.of(context).pop();
              }
            },
          ),
      ],
    );
  }

  Widget _buildSelectedSection(AdminSection section) {
    final resolvedSection = _resolvedSection(section);
    _log(
      'build section selected=${section.name} resolved=${resolvedSection.name}',
    );
    return switch (resolvedSection) {
      AdminSection.dashboard => AdminDashboardView(user: _shellUser),
      AdminSection.bookings => AdminBookingsView(
        user: widget.user,
        initialBooking: _bookingInitialSelection,
        onInitialBookingHandled: () {
          if (mounted) setState(() => _bookingInitialSelection = null);
        },
      ),
      AdminSection.vehicles => switch (_resolvedVehiclesSection()) {
        AdminVehiclesSection.makes => const AdminVehicleMakesView(),
        AdminVehiclesSection.sizes => const AdminVehicleSizesView(),
        AdminVehiclesSection.types => const AdminVehicleTypesView(),
        AdminVehiclesSection.chassis => const AdminChassisView(),
      },
      AdminSection.settings => switch (_resolvedSettingsSection()) {
        AdminSettingsSection.forms => AdminFormsView(viewModel: _flowViewModel),
        AdminSettingsSection.fields => AdminFieldsView(
          viewModel: _flowViewModel,
        ),
        AdminSettingsSection.statuses => AdminStatusesView(
          viewModel: _flowViewModel,
        ),
      },
      AdminSection.users => AdminUsersView(
        user: _shellUser,
        onCurrentUserUpdated: widget.onUserUpdated,
        onLogout: widget.onLogout,
        isQuickLoggedIn: widget.isQuickLoggedIn,
        initialEditUserId: _viewModel.pendingEditUserId,
        onInitialEditHandled: _viewModel.clearPendingEditUser,
      ),
      AdminSection.access => const AdminAccessView(),
      AdminSection.support => SupportCenterView(
        key: ValueKey(
          'support:$_supportViewTick:${_supportInitialTopicKey ?? '-'}:${_supportInitialBookingId ?? '-'}:${_supportInitialUserId ?? '-'}',
        ),
        user: _shellUser,
        embedded: true,
        initialTopicKey: _supportInitialTopicKey,
        initialBookingId: _supportInitialBookingId,
        initialUserId: _supportInitialUserId,
      ),
      AdminSection.profile => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProfileView(
              key: profileViewRefreshKey(_shellUser),
              user: _shellUser,
              scrollable: false,
              padding: EdgeInsets.zero,
              isCurrentUserView: true,
              onLogout: widget.onLogout,
              logoutLabel: widget.isQuickLoggedIn ? 'Go Back' : 'Logout',
              onSaveProfileChanges: _canUpdateProfile
                  ? _saveProfileChanges
                  : null,
              onEditPressed: () => unawaited(_openProfileEditDialog()),
            ),
            const SizedBox(height: 12),
            UserBookingsSection(user: _shellUser),
          ],
        ),
      ),
      AdminSection.analytics => const AdminAnalyticsView(),
    };
  }

  AdminVehiclesSection _resolvedVehiclesSection() {
    final selected = _viewModel.selectedVehiclesSection;
    if (selected == AdminVehiclesSection.makes && _canReadVehicleMakes) {
      return selected;
    }
    if (selected == AdminVehiclesSection.types && _canReadVehicleTypes) {
      return selected;
    }
    if (selected == AdminVehiclesSection.sizes && _canReadVehicleSizes) {
      return selected;
    }
    if (selected == AdminVehiclesSection.chassis && _canReadChassis) {
      return selected;
    }
    if (_canReadVehicleMakes) {
      return AdminVehiclesSection.makes;
    }
    if (_canReadVehicleTypes) {
      return AdminVehiclesSection.types;
    }
    return AdminVehiclesSection.sizes;
  }

  AdminSettingsSection _resolvedSettingsSection() {
    final selected = _viewModel.selectedSettingsSection;
    if (selected == AdminSettingsSection.statuses && _canReadStatuses) {
      return selected;
    }
    if (selected == AdminSettingsSection.forms && _canReadForms) {
      return selected;
    }
    if (selected == AdminSettingsSection.fields && _canReadFields) {
      return selected;
    }
    if (_canReadStatuses) {
      return AdminSettingsSection.statuses;
    }
    if (_canReadForms) {
      return AdminSettingsSection.forms;
    }
    return AdminSettingsSection.fields;
  }

  String _selectedSectionTitle(AdminHomeViewModel vm) {
    final resolvedSection = _resolvedSection(vm.selectedSection);
    if (resolvedSection == AdminSection.settings) {
      return vm.selectedSettingsSection.title;
    }
    if (resolvedSection == AdminSection.vehicles) {
      return vm.selectedVehiclesSection.title;
    }
    return resolvedSection.title;
  }

  IconData _menuIcon(AdminSection section) {
    return switch (section) {
      AdminSection.dashboard => Icons.dashboard_rounded,
      AdminSection.bookings => Icons.calendar_month_rounded,
      AdminSection.vehicles => Icons.local_shipping,
      AdminSection.settings => Icons.alt_route_rounded,
      AdminSection.users => Icons.people_alt_rounded,
      AdminSection.access => Icons.manage_accounts_rounded,
      AdminSection.support => Icons.support_agent_rounded,
      AdminSection.profile => Icons.account_circle_rounded,
      AdminSection.analytics => Icons.insights_rounded,
    };
  }
}
