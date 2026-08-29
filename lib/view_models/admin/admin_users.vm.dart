import 'dart:async';

import 'package:stacked/stacked.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/models/dispatcher_access_config.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:webapp/utils/functions.dart';

class AdminUsersViewModel extends BaseViewModel {
  AdminUsersViewModel({AuthRepository? repository})
    : _repository = repository ?? AuthRequest.instance {
    _users.addAll(_cachedUsers);
    _currentUser = _cachedCurrentUser;
    _viewedUser = _cachedViewedUser;
    _viewedUserStack.addAll(_cachedViewedUserStack);
  }

  final AuthRepository _repository;
  final RoleAccessService _roleAccessService = RoleAccessService.instance;
  StreamSubscription<void>? _usersCacheUpdatesSubscription;
  static List<UserModel> _cachedUsers = const [];
  static UserModel? _cachedCurrentUser;
  static UserModel? _cachedViewedUser;
  static List<UserModel> _cachedViewedUserStack = const [];

  static void clearCachedState() {
    _cachedUsers = const [];
    _cachedCurrentUser = null;
    _cachedViewedUser = null;
    _cachedViewedUserStack = const [];
  }

  final List<UserModel> _users = [];
  UserModel? _currentUser;
  UserModel? _viewedUser;
  final List<UserModel> _viewedUserStack = [];
  UserModel? _draftNewUser;
  String _searchQuery = '';
  String _roleFilter = 'All';
  String _activeFilter = 'All';
  String _onlineFilter = 'All';
  DateTime? _startDate;
  DateTime? _endDate;
  DateTime? _updatedStartDate;
  DateTime? _updatedEndDate;
  String _busyMessage = 'Loading, please wait ...';
  bool _isRealtimeRefreshing = false;
  String get searchQuery => _searchQuery;
  List<UserModel> get users => List.unmodifiable(_users);
  UserModel? get currentUser => _currentUser;
  UserModel? get viewedUser => _viewedUser;
  UserModel? get draftNewUser => _draftNewUser;
  String get roleFilter => _roleFilter;
  String get activeFilter => _activeFilter;
  String get onlineFilter => _onlineFilter;
  DateTime? get startDate => _startDate;
  DateTime? get endDate => _endDate;
  DateTime? get updatedStartDate => _updatedStartDate;
  DateTime? get updatedEndDate => _updatedEndDate;
  String get busyMessage => _busyMessage;
  bool get showBlockingLoading =>
      isBusy &&
      _users.isEmpty &&
      _cachedUsers.isEmpty &&
      _currentUser == null &&
      _cachedCurrentUser == null;
  bool get canCreateUsers => _roleAccessService.canAccess(
    DispatcherAccessCapability.usersCreate,
    role: _currentUser?.role,
  );
  bool get canReadUsers => _roleAccessService.canAccess(
    DispatcherAccessCapability.usersRead,
    role: _currentUser?.role,
  );
  bool get canUpdateUsers => _roleAccessService.canAccess(
    DispatcherAccessCapability.usersUpdate,
    role: _currentUser?.role,
  );
  bool get canDeleteUsers => _roleAccessService.canAccess(
    DispatcherAccessCapability.usersDelete,
    role: _currentUser?.role,
  );
  bool get canSignInAsOtherUsers => _roleAccessService.canAccess(
    DispatcherAccessCapability.usersImpersonate,
    role: _currentUser?.role,
  );
  String? get effectiveCurrentRole =>
      _roleAccessService.effectiveRoleKey(_currentUser?.role);
  bool get canCreateAdminUsers {
    final liveRole = normalizeRoleKey(effectiveCurrentRole);
    if (liveRole.isNotEmpty) {
      return liveRole == 'admin';
    }
    return normalizeRoleKey(_currentUser?.role) == 'admin';
  }

  Future<void> loadUsers({UserModel? fallbackCurrentUser}) async {
    _ensureUsersRealtimeSubscription();
    _busyMessage = 'Loading users ...';
    final hasVisiblePrimaryData =
        _users.isNotEmpty ||
        _cachedUsers.isNotEmpty ||
        _currentUser != null ||
        _cachedCurrentUser != null;
    final shouldShowLoadingState = !hasVisiblePrimaryData;
    if (shouldShowLoadingState) {
      setBusy(true);
    }
    try {
      final results = await Future.wait([
        _repository.getUsers(),
        _repository.getCurrentUser(),
      ]);
      final users = results[0] as List<UserModel>;
      final currentUser = results[1] as UserModel?;
      _users
        ..clear()
        ..addAll(users);
      _sortUsers();
      _currentUser = currentUser ?? fallbackCurrentUser;
      _cachedUsers = List<UserModel>.from(_users);
      _cachedCurrentUser = _currentUser;
      _cachedViewedUser = _viewedUser;
      _cachedViewedUserStack = List<UserModel>.from(_viewedUserStack);
    } finally {
      if (shouldShowLoadingState) {
        setBusy(false);
      }
      notifyListeners();
    }
  }

  void _ensureUsersRealtimeSubscription() {
    _usersCacheUpdatesSubscription ??= AuthRequest.instance
        .watchUsersCacheUpdates()
        .listen((_) {
          unawaited(_reloadUsersFromRealtime());
        });
  }

  Future<void> _reloadUsersFromRealtime() async {
    if (_isRealtimeRefreshing) {
      return;
    }
    _isRealtimeRefreshing = true;
    try {
      final results = await Future.wait([
        _repository.getUsers(),
        _repository.getCurrentUser(),
      ]);
      final users = results[0] as List<UserModel>;
      final currentUser = results[1] as UserModel?;
      _users
        ..clear()
        ..addAll(users);
      _sortUsers();
      _currentUser = currentUser ?? _currentUser;
      if (_viewedUser != null) {
        _viewedUser = _findUserById(_viewedUser?.id);
      }
      if (_viewedUserStack.isNotEmpty) {
        final refreshedStack = _viewedUserStack
            .map(
              (item) => _findUserById(item.id),
            )
            .whereType<UserModel>()
            .toList(growable: false);
        _viewedUserStack
          ..clear()
          ..addAll(refreshedStack);
      }
      _cachedUsers = List<UserModel>.from(_users);
      _cachedCurrentUser = _currentUser;
      _cachedViewedUser = _viewedUser;
      _cachedViewedUserStack = List<UserModel>.from(_viewedUserStack);
      notifyListeners();
    } catch (_) {
      // Keep the current visible state if a live refresh fails.
    } finally {
      _isRealtimeRefreshing = false;
    }
  }

  Future<UserModel> updateUser(UserModel user) async {
    if (!canUpdateUsers) {
      throw const AuthFailure('You do not have access to edit users.');
    }
    _busyMessage = 'Saving user ...';
    setBusy(true);
    try {
      final saved = await _repository.saveUser(user);
      final existingIndex = _users.indexWhere((item) => item.id == saved.id);
      if (existingIndex >= 0) {
        _users[existingIndex] = saved;
      } else {
        _users.add(saved);
      }
      _sortUsers();
      _currentUser = await _resolveCurrentUser(fallback: saved);
      if (_viewedUser?.id == saved.id) {
        _viewedUser = saved;
      }
      _cachedUsers = List<UserModel>.from(_users);
      _cachedCurrentUser = _currentUser;
      _cachedViewedUser = _viewedUser;
      _cachedViewedUserStack = List<UserModel>.from(_viewedUserStack);
      _searchQuery = '';
      notifyListeners();
      return saved;
    } finally {
      setBusy(false);
    }
  }

  Future<UserModel> addUser(UserModel user) async {
    if (!canCreateUsers) {
      throw const AuthFailure('You do not have access to create users.');
    }
    if (!canCreateAdminUsers && normalizeRoleKey(user.role) == 'admin') {
      throw const AuthFailure('Only admin users can create other admin users.');
    }
    _busyMessage = 'Creating user ...';
    setBusy(true);
    try {
      final saved = await _repository.saveUser(
        user.copyWith(isOnline: user.isOnline ?? false),
      );
      _users.add(saved);
      _sortUsers();
      _currentUser = await _resolveCurrentUser();
      _searchQuery = '';
      _roleFilter = 'All';
      _activeFilter = 'All';
      _onlineFilter = 'All';
      _draftNewUser = null;
      _cachedUsers = List<UserModel>.from(_users);
      _cachedCurrentUser = _currentUser;
      _cachedViewedUserStack = List<UserModel>.from(_viewedUserStack);
      notifyListeners();
      return saved;
    } finally {
      setBusy(false);
    }
  }

  void syncUser(UserModel user) {
    final existingIndex = _users.indexWhere((item) => item.id == user.id);
    if (existingIndex >= 0) {
      _users[existingIndex] = user;
    } else {
      _users.add(user);
    }
    _sortUsers();
    if (_currentUser?.id == user.id) {
      _currentUser = user;
    }
    if (_viewedUser?.id == user.id) {
      _viewedUser = user;
    }
    _cachedUsers = List<UserModel>.from(_users);
    _cachedCurrentUser = _currentUser;
    _cachedViewedUser = _viewedUser;
    _cachedViewedUserStack = List<UserModel>.from(_viewedUserStack);
    notifyListeners();
  }

  void updateDraftNewUser(UserModel user) {
    _draftNewUser = user;
  }

  void clearDraftNewUser() {
    _draftNewUser = null;
  }

  void ensureCurrentUserContext(UserModel user) {
    if (_currentUser?.id == user.id && _currentUser?.role == user.role) {
      return;
    }
    _currentUser = user;
    _cachedCurrentUser = user;
  }

  Future<void> deleteUser(UserModel user) async {
    if (!canDeleteUsers) {
      throw const AuthFailure('You do not have access to delete users.');
    }
    _busyMessage = 'Deleting user ...';
    setBusy(true);
    try {
      await _repository.deleteUser(user.id ?? '');
      _users.removeWhere((item) => item.id == user.id);
      _sortUsers();
      _currentUser = await _resolveCurrentUser();
      if (_viewedUser?.id == user.id) {
        _viewedUser = null;
      }
      _cachedUsers = List<UserModel>.from(_users);
      _cachedCurrentUser = _currentUser;
      _cachedViewedUser = _viewedUser;
      _cachedViewedUserStack = List<UserModel>.from(_viewedUserStack);
      notifyListeners();
    } finally {
      setBusy(false);
    }
  }

  Future<void> loginAsUser(UserModel user) async {
    if (!canSignInAsOtherUsers) {
      throw const AuthFailure('You do not have access to sign in as other users.');
    }
    final userId = user.id ?? '';
    if (userId.isEmpty) {
      throw const AuthFailure('User ID is required.');
    }
    final roleLabel = humanizeDropdownValue(user.role).trim();
    _busyMessage = 'Signing in as ${roleLabel.isEmpty ? 'user' : roleLabel} ...';
    setBusy(true);
    try {
      await _repository.loginAsUser(userId);
    } finally {
      setBusy(false);
    }
  }

  void openUserView(UserModel user, {bool preserveCurrent = false}) {
    if (!preserveCurrent) {
      _viewedUserStack.clear();
    } else if (_viewedUser != null && _viewedUser!.id != user.id) {
      _viewedUserStack.add(_viewedUser!);
    }
    _viewedUser = user;
    _cachedViewedUser = _viewedUser;
    _cachedViewedUserStack = List<UserModel>.from(_viewedUserStack);
    notifyListeners();
  }

  void closeUserView() {
    if (_viewedUserStack.isNotEmpty) {
      _viewedUser = _viewedUserStack.removeLast();
      _cachedViewedUser = _viewedUser;
    } else {
      _viewedUser = null;
      _cachedViewedUser = null;
    }
    _cachedViewedUserStack = List<UserModel>.from(_viewedUserStack);
    notifyListeners();
  }

  UserModel? parentBusinessFor(UserModel user) {
    final parentId = user.parentClientId?.trim();
    if (parentId == null || parentId.isEmpty) {
      return null;
    }
    return _users.where((item) => item.id == parentId).firstOrNull;
  }

  Future<void> setUserActive(UserModel user, bool isActive) async {
    if (!canUpdateUsers) {
      throw const AuthFailure('You do not have access to update users.');
    }
    _busyMessage = isActive ? 'Activating user ...' : 'Deactivating user ...';
    await updateUser(
      user.copyWith(
        isActive: isActive,
        isOnline: isActive ? (user.isOnline ?? false) : false,
        updatedAt: DateTime.now(),
      ),
    );
  }

  String get nextUserId {
    var highest = 0;
    for (final user in _users) {
      final parsed = int.tryParse(user.id ?? '');
      if (parsed != null && parsed > highest) {
        highest = parsed;
      }
    }
    return (highest + 1).toString();
  }

  List<String> roleOptions() {
    final roles =
        _users
            .map((user) => _formatRole(user.role))
            .where((role) => role != '-')
            .toSet()
            .toList()
          ..sort();
    return ['All', ...roles];
  }

  bool matches(UserModel user) {
    final query = _searchQuery.trim().toLowerCase();
    final createdAt = user.createdAt;
    final isOnlineEligible = _roleAccessService.isOnlineEligibleRole(user.role);

    final matchesQuery =
        query.isEmpty ||
        [user.id, user.name, user.phone, user.email, _formatRole(user.role)]
            .whereType<String>()
            .any((value) => value.toLowerCase().contains(query));

    final matchesRole =
        _roleFilter == 'All' || _formatRole(user.role) == _roleFilter;

    final matchesActive =
        _activeFilter == 'All' ||
        ((_activeFilter == 'Active') == (user.isActive ?? false));

    final matchesOnline =
        _onlineFilter == 'All' ||
        ((_onlineFilter == 'Online') ==
            (isOnlineEligible && (user.isOnline ?? false)));

    final matchesStartDate =
        _startDate == null ||
        (createdAt != null &&
            !_dateOnly(createdAt).isBefore(_dateOnly(_startDate!)));

    final matchesEndDate =
        _endDate == null ||
        (createdAt != null &&
            !_dateOnly(createdAt).isAfter(_dateOnly(_endDate!)));
    final updatedAt = user.updatedAt;
    final matchesUpdatedStartDate =
        _updatedStartDate == null ||
        (updatedAt != null &&
            !_dateOnly(updatedAt).isBefore(_dateOnly(_updatedStartDate!)));
    final matchesUpdatedEndDate =
        _updatedEndDate == null ||
        (updatedAt != null &&
            !_dateOnly(updatedAt).isAfter(_dateOnly(_updatedEndDate!)));

    return matchesQuery &&
        matchesRole &&
        matchesActive &&
        matchesOnline &&
        matchesStartDate &&
        matchesEndDate &&
        matchesUpdatedStartDate &&
        matchesUpdatedEndDate;
  }

  void updateSearchQuery(String value) {
    _searchQuery = value;
    notifyListeners();
  }

  void updateRoleFilter(String? value) {
    _roleFilter = value ?? 'All';
    notifyListeners();
  }

  void updateActiveFilter(String? value) {
    _activeFilter = value ?? 'All';
    notifyListeners();
  }

  void updateOnlineFilter(String? value) {
    _onlineFilter = value ?? 'All';
    notifyListeners();
  }

  void updateStartDate(DateTime? value) {
    _startDate = value;
    if (_startDate != null &&
        _endDate != null &&
        _endDate!.isBefore(_startDate!)) {
      _endDate = _startDate;
    }
    notifyListeners();
  }

  void updateEndDate(DateTime? value) {
    _endDate = value;
    if (_startDate != null &&
        _endDate != null &&
        _startDate!.isAfter(_endDate!)) {
      _startDate = _endDate;
    }
    notifyListeners();
  }

  void updateUpdatedStartDate(DateTime? value) {
    _updatedStartDate = value;
    if (_updatedStartDate != null &&
        _updatedEndDate != null &&
        _updatedEndDate!.isBefore(_updatedStartDate!)) {
      _updatedEndDate = _updatedStartDate;
    }
    notifyListeners();
  }

  void updateUpdatedEndDate(DateTime? value) {
    _updatedEndDate = value;
    if (_updatedStartDate != null &&
        _updatedEndDate != null &&
        _updatedStartDate!.isAfter(_updatedEndDate!)) {
      _updatedStartDate = _updatedEndDate;
    }
    notifyListeners();
  }

  void clearFilters() {
    _roleFilter = 'All';
    _activeFilter = 'All';
    _onlineFilter = 'All';
    _startDate = null;
    _endDate = null;
    _updatedStartDate = null;
    _updatedEndDate = null;
    notifyListeners();
  }

  String formatDate(DateTime? value) {
    if (value == null) {
      return 'All';
    }

    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$month/$day/${value.year}';
  }

  static DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  Future<UserModel?> _resolveCurrentUser({UserModel? fallback}) async {
    return await _repository.getCurrentUser() ?? fallback ?? _currentUser;
  }

  List<UserModel> clientUsers() {
    return _users
        .where(
          (user) =>
              normalizeRoleKey(user.role) == 'client' &&
              (user.isActive ?? false),
        )
        .toList()
      ..sort(
        (a, b) => (a.name ?? '').toLowerCase().compareTo(
          (b.name ?? '').toLowerCase(),
        ),
      );
  }

  void _sortUsers() {
    _users.sort((a, b) {
      final createdComparison = _compareLatestFirst(a.createdAt, b.createdAt);
      if (createdComparison != 0) {
        return createdComparison;
      }

      final aId = int.tryParse(a.id ?? '');
      final bId = int.tryParse(b.id ?? '');
      if (aId != null && bId != null) {
        return bId.compareTo(aId);
      }
      return (b.id ?? '').compareTo(a.id ?? '');
    });
  }

  int _compareLatestFirst(DateTime? a, DateTime? b) {
    if (a == null && b == null) {
      return 0;
    }
    if (a == null) {
      return 1;
    }
    if (b == null) {
      return -1;
    }
    return b.compareTo(a);
  }

  static String _formatRole(String? role) {
    if (role == null || role.isEmpty) {
      return '-';
    }
    return humanizeDropdownValue(role);
  }

  UserModel? _findUserById(String? userId) {
    if (userId == null || userId.isEmpty) {
      return null;
    }
    for (final user in _users) {
      if (user.id == userId) {
        return user;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _usersCacheUpdatesSubscription?.cancel();
    super.dispose();
  }
}
