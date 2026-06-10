import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';

import 'auth_storage_backend.dart';

class LocalAuthRepository implements AuthRepository {
  LocalAuthRepository._();

  static final LocalAuthRepository instance = LocalAuthRepository._();

  static const _usersKey = 'paltranco_users';
  static const _currentUserIdKey = 'paltranco_current_user_id';
  static const _quickLoginSourceUserIdKey =
      'paltranco_quick_login_source_user_id';
  static const VehicleCatalogItem _primeMoverType = VehicleCatalogItem(
    id: '1',
    name: 'Prime Mover',
    slug: 'PM',
    isActive: true,
  );
  static final List<UserModel> _devSeedUsers = [
    UserModel(
      id: '1',
      role: 'admin',
      email: 'palawantransportcorp@gmail.com',
      name: 'Palawan Transport Corporation',
      phone: '+639926715321',
      isActive: true,
      isOnline: false,
      password: 'password',
    ),
    UserModel(
      id: '2',
      role: 'client',
      email: 'speedovate@gmail.com',
      name: 'Speedovate IT Services',
      phone: '+639081512851',
      isActive: true,
      isOnline: false,
      password: 'password',
    ),
    DriverModel(
      id: '3',
      role: 'driver',
      email: 'itronald@gmail.com',
      name: 'Ronald Iniego',
      phone: '+639939470079',
      vehicleType: _primeMoverType,
      isActive: true,
      isOnline: false,
      password: 'password',
    ),
    UserModel(
      id: '4',
      role: 'helper',
      email: 'ejdomingo82@gmail.com',
      name: 'Ephraim Jacob Domingo',
      phone: '+639064493206',
      isActive: true,
      isOnline: false,
      password: 'password',
    ),
  ];

  final AuthStorageBackend _storage = createAuthStorageBackend();

  @override
  Future<void> initialize() async {
    await _storage.initialize();
    await _ensureDevUsers();
  }

  @override
  Future<List<UserModel>> getUsers() async {
    await initialize();
    final raw = await _storage.readStringList(_usersKey);
    return raw.map(UserModel.fromJson).toList();
  }

  @override
  Future<UserModel?> getCurrentUser() async {
    await initialize();
    final currentId = await _storage.readString(_currentUserIdKey);
    if (currentId == null || currentId.isEmpty) {
      return null;
    }

    final users = await getUsers();
    final matches = users.where((user) => user.id == currentId);
    return matches.isEmpty ? null : matches.first;
  }

  @override
  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final users = await getUsers();
    final matches = users.where(
      (user) => (user.email ?? '').trim().toLowerCase() == normalizedEmail,
    );
    if (matches.isEmpty) {
      throw const AuthFailure('No account found for that email.');
    }

    final user = matches.first;
    if ((user.password ?? '') != password) {
      throw const AuthFailure('Incorrect password.');
    }

    if (user.isActive == false) {
      throw const AuthFailure('This account is inactive.');
    }

    final loggedInUser = user.copyWith(
      isOnline: _supportsOnline(user.role) ? true : false,
      updatedAt: DateTime.now(),
    );
    await _persistUpdatedUser(loggedInUser);
    await _storage.writeString(_currentUserIdKey, loggedInUser.id ?? '');
    return loggedInUser;
  }

  @override
  Future<UserModel> register(UserModel user) async {
    final users = await getUsers();
    final normalizedEmail = (user.email ?? '').trim().toLowerCase();
    final normalizedName = _toTitleCase(user.name);
    final emailTaken = users.any(
      (item) => (item.email ?? '').trim().toLowerCase() == normalizedEmail,
    );
    if (emailTaken) {
      throw const AuthFailure('That email is already registered.');
    }

    final nextId =
        users
            .map((item) => int.tryParse(item.id ?? ''))
            .whereType<int>()
            .fold<int>(0, (max, value) => value > max ? value : max) +
        1;
    final now = DateTime.now();
    final savedUser = user.copyWith(
      id: '$nextId',
      email: normalizedEmail,
      name: normalizedName,
      isActive: user.isActive ?? true,
      isOnline: false,
      createdAt: user.createdAt ?? now,
      updatedAt: now,
    );

    final nextUsers = [...users, savedUser];
    await _storage.writeStringList(
      _usersKey,
      nextUsers.map((item) => item.toJson()).toList(),
    );
    if (savedUser.isActive ?? false) {
      await _storage.writeString(_currentUserIdKey, savedUser.id ?? '');
    } else {
      await _storage.remove(_currentUserIdKey);
    }
    return savedUser;
  }

  @override
  Future<UserModel> saveUser(UserModel user) async {
    final users = await getUsers();
    final normalizedEmail = (user.email ?? '').trim().toLowerCase();
    final normalizedName = _toTitleCase(user.name);
    final emailTakenByOther = users.any(
      (item) =>
          item.id != user.id &&
          (item.email ?? '').trim().toLowerCase() == normalizedEmail,
    );
    if (emailTakenByOther) {
      throw const AuthFailure('That email is already registered.');
    }

    final normalizedUser = user.copyWith(
      name: normalizedName,
      isOnline: (user.isActive ?? false) && _supportsOnline(user.role)
          ? (user.isOnline ?? false)
          : false,
    );
    final index = users.indexWhere((item) => item.id == normalizedUser.id);
    UserModel savedUser;
    if (index == -1) {
      final updatedAt = _nextUpdatedAt(user.updatedAt);
      final nextId =
          users
              .map((item) => int.tryParse(item.id ?? ''))
              .whereType<int>()
              .fold<int>(0, (max, value) => value > max ? value : max) +
          1;
      savedUser = normalizedUser.copyWith(
        id: '$nextId',
        email: normalizedEmail,
        createdAt: normalizedUser.createdAt ?? updatedAt,
        updatedAt: updatedAt,
      );
      users.add(savedUser);
    } else {
      final existing = users[index];
      final updatedAt = _nextUpdatedAt(existing.updatedAt);
      savedUser = normalizedUser.copyWith(
        id: existing.id,
        email: normalizedEmail,
        createdAt: existing.createdAt ?? normalizedUser.createdAt ?? updatedAt,
        updatedAt: updatedAt,
      );
      users[index] = savedUser;
    }

    await _storage.writeStringList(
      _usersKey,
      users.map((item) => item.toJson()).toList(),
    );

    final currentUserId = await _storage.readString(_currentUserIdKey);
    if (currentUserId == savedUser.id) {
      await _storage.writeString(_currentUserIdKey, savedUser.id ?? '');
    }

    return savedUser;
  }

  @override
  Future<void> deleteUser(String userId) async {
    final users = await getUsers();
    users.removeWhere((item) => item.id == userId);
    await _storage.writeStringList(
      _usersKey,
      users.map((item) => item.toJson()).toList(),
    );

    final currentUserId = await _storage.readString(_currentUserIdKey);
    if (currentUserId == userId) {
      await _storage.remove(_currentUserIdKey);
    }
    final quickLoginSourceUserId = await _storage.readString(
      _quickLoginSourceUserIdKey,
    );
    if (quickLoginSourceUserId == userId) {
      await _storage.remove(_quickLoginSourceUserIdKey);
    }
  }

  @override
  Future<void> loginAsUser(String userId) async {
    await initialize();
    final users = await getUsers();
    final matches = users.where((user) => user.id == userId);
    if (matches.isEmpty) {
      throw const AuthFailure('No account found for that user.');
    }

    final user = matches.first;
    if (user.isActive == false) {
      throw const AuthFailure('This account is inactive.');
    }

    final currentUserId = await _storage.readString(_currentUserIdKey);
    if (currentUserId != null &&
        currentUserId.isNotEmpty &&
        currentUserId != userId &&
        (await _storage.readString(_quickLoginSourceUserIdKey))?.isNotEmpty !=
            true) {
      await _storage.writeString(_quickLoginSourceUserIdKey, currentUserId);
    }

    final nextUser = user.copyWith(
      isOnline: _supportsOnline(user.role) ? true : false,
      updatedAt: DateTime.now(),
    );
    await _persistUpdatedUser(nextUser);
    await _storage.writeString(_currentUserIdKey, userId);
  }

  @override
  Future<bool> hasQuickLoginSource() async {
    await initialize();
    final sourceUserId = await _storage.readString(_quickLoginSourceUserIdKey);
    return sourceUserId != null && sourceUserId.isNotEmpty;
  }

  @override
  Future<UserModel?> returnToQuickLoginSource() async {
    await initialize();
    final sourceUserId = await _storage.readString(_quickLoginSourceUserIdKey);
    if (sourceUserId == null || sourceUserId.isEmpty) {
      return null;
    }

    final users = await getUsers();
    final matches = users.where((user) => user.id == sourceUserId);
    if (matches.isEmpty) {
      await _storage.remove(_quickLoginSourceUserIdKey);
      await _storage.remove(_currentUserIdKey);
      return null;
    }

    final sourceUser = matches.first;
    final restoredUser = sourceUser.copyWith(
      isOnline: _supportsOnline(sourceUser.role) ? true : false,
      updatedAt: DateTime.now(),
    );
    await _persistUpdatedUser(restoredUser);
    await _storage.writeString(_currentUserIdKey, restoredUser.id ?? '');
    await _storage.remove(_quickLoginSourceUserIdKey);
    return restoredUser;
  }

  @override
  Future<void> logout() async {
    await initialize();
    await _storage.remove(_quickLoginSourceUserIdKey);
    final currentUser = await getCurrentUser();
    if (currentUser != null) {
      await _persistUpdatedUser(
        currentUser.copyWith(isOnline: false, updatedAt: DateTime.now()),
      );
    }
    await _storage.remove(_currentUserIdKey);
  }

  Future<void> _persistUpdatedUser(UserModel user) async {
    final users = await getUsers();
    final nextUsers = users.map((item) {
      if (item.id == user.id) {
        return user;
      }
      return item;
    }).toList();

    await _storage.writeStringList(
      _usersKey,
      nextUsers.map((item) => item.toJson()).toList(),
    );
  }

  Future<void> _ensureDevUsers() async {
    final raw = await _storage.readStringList(_usersKey);
    final existingUsers = raw.map(UserModel.fromJson).toList();
    final now = DateTime.now();
    var hasChanges = existingUsers.isEmpty;

    final nextUsers = [...existingUsers];
    for (final seedUser in _devSeedUsers) {
      final normalizedEmail = (seedUser.email ?? '').trim().toLowerCase();
      final index = nextUsers.indexWhere(
        (user) =>
            user.id == seedUser.id ||
            (user.email ?? '').trim().toLowerCase() == normalizedEmail,
      );

      final seededUser = seedUser.copyWith(
        email: normalizedEmail,
        name: _toTitleCase(seedUser.name),
        createdAt: index == -1 ? now : (nextUsers[index].createdAt ?? now),
        updatedAt: now,
      );

      if (index == -1) {
        nextUsers.add(seededUser);
        hasChanges = true;
      } else {
        final existing = nextUsers[index];
        final mergedUser = _mergeSeededUser(
          existing: existing,
          seeded: seededUser,
          now: now,
        );
        if (existing.toJson() != mergedUser.toJson()) {
          nextUsers[index] = mergedUser;
          hasChanges = true;
        }
      }
    }

    if (!hasChanges) {
      return;
    }

    await _storage.writeStringList(
      _usersKey,
      nextUsers.map((item) => item.toJson()).toList(),
    );
  }

  UserModel _mergeSeededUser({
    required UserModel existing,
    required UserModel seeded,
    required DateTime now,
  }) {
    final preservedUpdatedAt = existing.updatedAt ?? seeded.updatedAt ?? now;
    final existingDriver = existing.asDriver;
    final seededDriver = seeded.asDriver;
    return existing.copyWith(
      id: existing.id ?? seeded.id,
      role: _preferExistingString(existing.role, seeded.role),
      email: _preferExistingString(existing.email, seeded.email),
      name: _preferExistingString(existing.name, seeded.name),
      phone: _preferExistingString(existing.phone, seeded.phone),
      vehicleType: existingDriver?.vehicleType ?? seededDriver?.vehicleType,
      isActive: existing.isActive ?? seeded.isActive,
      isOnline: existing.isOnline ?? seeded.isOnline,
      password: _preferExistingString(existing.password, seeded.password),
      createdAt: existing.createdAt ?? seeded.createdAt ?? now,
      updatedAt: preservedUpdatedAt,
    );
  }

  DateTime _nextUpdatedAt(DateTime? previous) {
    final now = DateTime.now();
    if (previous == null) {
      return now;
    }

    final previousSecond = DateTime(
      previous.year,
      previous.month,
      previous.day,
      previous.hour,
      previous.minute,
      previous.second,
    );
    final nowSecond = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
      now.second,
    );

    if (!nowSecond.isAfter(previousSecond)) {
      return previousSecond.add(const Duration(seconds: 1));
    }
    return now;
  }

  static bool _supportsOnline(String? role) {
    return role == 'driver' || role == 'helper';
  }

  static String? _toTitleCase(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }

    String capitalizeSegment(String segment) {
      if (segment.isEmpty) {
        return segment;
      }
      return '${segment[0].toUpperCase()}${segment.substring(1).toLowerCase()}';
    }

    String capitalizeDelimited(String word, String delimiter) {
      return word.split(delimiter).map(capitalizeSegment).join(delimiter);
    }

    return trimmed
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .map((word) => capitalizeDelimited(capitalizeDelimited(word, '-'), "'"))
        .join(' ');
  }

  static String? _preferExistingString(String? existing, String? fallback) {
    final trimmedExisting = existing?.trim();
    if (trimmedExisting != null && trimmedExisting.isNotEmpty) {
      return trimmedExisting;
    }
    final trimmedFallback = fallback?.trim();
    if (trimmedFallback != null && trimmedFallback.isNotEmpty) {
      return trimmedFallback;
    }
    return fallback;
  }
}
