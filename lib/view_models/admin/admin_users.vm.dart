import 'package:stacked/stacked.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';

class AdminUsersViewModel extends BaseViewModel {
  AdminUsersViewModel({AuthRepository? repository})
    : _repository = repository ?? AuthRequest.instance {
    _users.addAll(_cachedUsers);
    _currentUser = _cachedCurrentUser;
    _viewedUser = _cachedViewedUser;
  }

  final AuthRepository _repository;
  static List<UserModel> _cachedUsers = const [];
  static UserModel? _cachedCurrentUser;
  static UserModel? _cachedViewedUser;

  static void clearCachedState() {
    _cachedUsers = const [];
    _cachedCurrentUser = null;
    _cachedViewedUser = null;
  }

  final List<UserModel> _users = [];
  UserModel? _currentUser;
  UserModel? _viewedUser;
  UserModel? _draftNewUser;
  String _searchQuery = '';
  String _roleFilter = 'All';
  String _activeFilter = 'All';
  String _onlineFilter = 'All';
  DateTime? _startDate;
  DateTime? _endDate;
  String _busyMessage = 'Loading, please wait ...';
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
  String get busyMessage => _busyMessage;

  Future<void> loadUsers({UserModel? fallbackCurrentUser}) async {
    _busyMessage = 'Loading users ...';
    setBusy(true);
    try {
      final users = await _repository.getUsers();
      final currentUser = await _repository.getCurrentUser();
      _users
        ..clear()
        ..addAll(users);
      _sortUsers();
      _currentUser = currentUser ?? fallbackCurrentUser;
      _cachedUsers = List<UserModel>.from(_users);
      _cachedCurrentUser = _currentUser;
      _cachedViewedUser = _viewedUser;
    } finally {
      setBusy(false);
      notifyListeners();
    }
  }

  Future<UserModel> updateUser(UserModel user) async {
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
      _searchQuery = '';
      notifyListeners();
      return saved;
    } finally {
      setBusy(false);
    }
  }

  Future<UserModel> addUser(UserModel user) async {
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
    notifyListeners();
  }

  void updateDraftNewUser(UserModel user) {
    _draftNewUser = user;
  }

  void clearDraftNewUser() {
    _draftNewUser = null;
  }

  Future<void> deleteUser(UserModel user) async {
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
      notifyListeners();
    } finally {
      setBusy(false);
    }
  }

  Future<void> loginAsUser(UserModel user) async {
    final userId = user.id ?? '';
    if (userId.isEmpty) {
      throw const AuthFailure('User ID is required.');
    }
    _busyMessage = 'Signing in as user ...';
    setBusy(true);
    try {
      await _repository.loginAsUser(userId);
    } finally {
      setBusy(false);
    }
  }

  void openUserView(UserModel user) {
    _viewedUser = user;
    _cachedViewedUser = _viewedUser;
    notifyListeners();
  }

  void closeUserView() {
    _viewedUser = null;
    _cachedViewedUser = null;
    notifyListeners();
  }

  Future<void> setUserActive(UserModel user, bool isActive) async {
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
        ((_onlineFilter == 'Online') == (user.isOnline ?? false));

    final matchesStartDate =
        _startDate == null ||
        (createdAt != null &&
            !_dateOnly(createdAt).isBefore(_dateOnly(_startDate!)));

    final matchesEndDate =
        _endDate == null ||
        (createdAt != null &&
            !_dateOnly(createdAt).isAfter(_dateOnly(_endDate!)));

    return matchesQuery &&
        matchesRole &&
        matchesActive &&
        matchesOnline &&
        matchesStartDate &&
        matchesEndDate;
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

  void clearFilters() {
    _roleFilter = 'All';
    _activeFilter = 'All';
    _onlineFilter = 'All';
    _startDate = null;
    _endDate = null;
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

    return role
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
}
