import 'dart:async';

import 'package:stacked/stacked.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/services/app_warmup_service.dart';
import 'package:webapp/services/role_access_service.dart';

class AppShellViewModel extends BaseViewModel {
  AppShellViewModel({AuthRepository? repository})
    : _repository = repository ?? AuthRequest.instance;

  final AuthRepository _repository;
  final RoleAccessService _roleAccessService = RoleAccessService.instance;
  final AppWarmupService _warmupService = AppWarmupService.instance;

  bool isLoading = true;
  UserModel? currentUser;
  bool isQuickLoggedIn = false;
  StreamSubscription<void>? _sessionInvalidationSubscription;
  static const Duration _startupStepTimeout = Duration(seconds: 8);
  int _sessionEpoch = 0;

  Future<void> initialize() async {
    _log('initialize start loggedIn=false');
    isLoading = true;
    notifyListeners();
    try {
      await _repository.initialize().timeout(
        _startupStepTimeout,
        onTimeout: () {},
      );

      currentUser = await _repository.getCurrentUser().timeout(
        _startupStepTimeout,
        onTimeout: () {
          return null;
        },
      );

      _roleAccessService.setCurrentUser(currentUser);
      unawaited(
        _roleAccessService
            .initialize()
            .then((_) {})
            .catchError((error, stackTrace) {}),
      );
      isQuickLoggedIn = await _repository.hasQuickLoginSource().timeout(
        _startupStepTimeout,
        onTimeout: () {
          return false;
        },
      );

      await _bindCurrentSessionWatch().timeout(
        _startupStepTimeout,
        onTimeout: () {},
      );
      _startWarmupForAuthenticatedMainUi(currentUser, source: 'initialize');
    } catch (error) {
      // Startup should still continue using cached/local state when background steps fail.
    }
    _log(
      'initialize done loggedIn=${currentUser != null} user=${currentUser?.id ?? "-"} role=${currentUser?.role ?? "-"} quick=$isQuickLoggedIn',
    );
    isLoading = false;
    notifyListeners();
  }

  Future<void> refreshCurrentUser() async {
    currentUser = await _repository.getCurrentUser();
    _roleAccessService.setCurrentUser(currentUser);
    isQuickLoggedIn = await _repository.hasQuickLoginSource();
    await _bindCurrentSessionWatch();
    _startWarmupForAuthenticatedMainUi(currentUser, source: 'refresh');
    _log(
      'refreshCurrentUser loggedIn=${currentUser != null} user=${currentUser?.id ?? "-"} role=${currentUser?.role ?? "-"} quick=$isQuickLoggedIn',
    );
    notifyListeners();
  }

  Future<void> completeAuthentication(UserModel user) async {
    final authEpoch = ++_sessionEpoch;
    _log(
      'completeAuthentication start loggedIn=true user=${user.id ?? "-"} role=${user.role ?? "-"}',
    );
    isLoading = true;
    currentUser = user;
    _roleAccessService.setCurrentUser(user);
    notifyListeners();
    try {
      isQuickLoggedIn = await _repository.hasQuickLoginSource();
      await _bindCurrentSessionWatch();
      _startWarmupForAuthenticatedMainUi(currentUser, source: 'complete');
      unawaited(_refreshCurrentUserInBackground(user, authEpoch));
    } catch (_) {
      if (authEpoch != _sessionEpoch) {
        return;
      }
      currentUser = user;
      _roleAccessService.setCurrentUser(currentUser);
      isQuickLoggedIn = await _repository.hasQuickLoginSource();
      await _bindCurrentSessionWatch();
      _startWarmupForAuthenticatedMainUi(
        currentUser,
        source: 'complete-fallback',
      );
    } finally {
      if (authEpoch == _sessionEpoch) {
        isLoading = false;
        _log(
          'completeAuthentication done loggedIn=${currentUser != null} user=${currentUser?.id ?? "-"} role=${currentUser?.role ?? "-"} quick=$isQuickLoggedIn',
        );
        notifyListeners();
      }
    }
  }

  Future<void> logout() async {
    _log(
      'logout start loggedIn=${currentUser != null} user=${currentUser?.id ?? "-"} role=${currentUser?.role ?? "-"}',
    );
    _sessionEpoch++;
    await _sessionInvalidationSubscription?.cancel();
    _sessionInvalidationSubscription = null;
    currentUser = null;
    _roleAccessService.setCurrentUser(null);
    isQuickLoggedIn = false;
    notifyListeners();
    try {
      await _repository.logout();
    } catch (_) {}
    _log('logout done loggedIn=false');
  }

  Future<void> goBackFromQuickLogin() async {
    _log(
      'goBackFromQuickLogin start loggedIn=${currentUser != null} user=${currentUser?.id ?? "-"} role=${currentUser?.role ?? "-"}',
    );
    // Ignore any background auth work that belongs to the impersonated session.
    _sessionEpoch++;
    final previousUser = currentUser;
    final previousQuickLoggedIn = isQuickLoggedIn;
    isLoading = true;
    notifyListeners();
    await _sessionInvalidationSubscription?.cancel();
    _sessionInvalidationSubscription = null;
    try {
      currentUser = await _repository.returnToQuickLoginSource();
      _roleAccessService.setCurrentUser(currentUser);
      isQuickLoggedIn = await _repository.hasQuickLoginSource();
      await _bindCurrentSessionWatch();
      _startWarmupForAuthenticatedMainUi(currentUser, source: 'go-back');
    } catch (_) {
      currentUser = previousUser;
      _roleAccessService.setCurrentUser(currentUser);
      isQuickLoggedIn = previousQuickLoggedIn;
      await _bindCurrentSessionWatch();
      _startWarmupForAuthenticatedMainUi(
        currentUser,
        source: 'go-back-fallback',
      );
      rethrow;
    } finally {
      isLoading = false;
      _log(
        'goBackFromQuickLogin done loggedIn=${currentUser != null} user=${currentUser?.id ?? "-"} role=${currentUser?.role ?? "-"} quick=$isQuickLoggedIn',
      );
      notifyListeners();
    }
  }

  Future<void> _bindCurrentSessionWatch() async {
    await _sessionInvalidationSubscription?.cancel();
    _sessionInvalidationSubscription = null;
    final authRequest = _repository is AuthRequest ? _repository : null;
    if (authRequest == null || currentUser == null) {
      return;
    }
    _sessionInvalidationSubscription = authRequest
        .watchCurrentSessionInvalidation()
        .listen((_) async {
          _log(
            'session invalidated loggedIn=${currentUser != null} user=${currentUser?.id ?? "-"} role=${currentUser?.role ?? "-"}',
          );
          currentUser = null;
          _roleAccessService.setCurrentUser(null);
          isQuickLoggedIn = false;
          notifyListeners();
        });
  }

  Future<void> _refreshCurrentUserInBackground(
    UserModel fallbackUser,
    int authEpoch,
  ) async {
    try {
      final refreshedUser = await _repository.getCurrentUser();
      if (authEpoch != _sessionEpoch) {
        return;
      }
      currentUser = _preserveProfilePhoto(
        refreshedUser ?? fallbackUser,
        fallbackUser,
      );
      _roleAccessService.setCurrentUser(currentUser);
      isQuickLoggedIn = await _repository.hasQuickLoginSource();
      if (authEpoch != _sessionEpoch) {
        return;
      }
      await _bindCurrentSessionWatch();
      if (authEpoch != _sessionEpoch) {
        return;
      }
      _startWarmupForAuthenticatedMainUi(
        currentUser,
        source: 'background-refresh',
      );
      notifyListeners();
    } catch (_) {
      if (authEpoch != _sessionEpoch) {
        return;
      }
      currentUser = fallbackUser;
      _roleAccessService.setCurrentUser(currentUser);
      _startWarmupForAuthenticatedMainUi(
        currentUser,
        source: 'background-fallback',
      );
      notifyListeners();
    }
  }

  UserModel _preserveProfilePhoto(
    UserModel refreshedUser,
    UserModel fallbackUser,
  ) {
    final isSameUser =
        refreshedUser.id?.trim().isNotEmpty == true &&
        refreshedUser.id == fallbackUser.id;
    final refreshedHasPhoto = refreshedUser.photo?.trim().isNotEmpty == true;
    final fallbackPhoto = fallbackUser.photo?.trim();
    if (!isSameUser ||
        refreshedHasPhoto ||
        fallbackPhoto == null ||
        fallbackPhoto.isEmpty) {
      return refreshedUser;
    }
    return refreshedUser.copyWith(photo: fallbackPhoto);
  }

  void _startWarmupForAuthenticatedMainUi(
    UserModel? resolvedUser, {
    required String source,
  }) {
    if (resolvedUser == null) {
      return;
    }
    _log(
      'warmup dispatch source=$source user=${resolvedUser.id ?? "-"} role=${resolvedUser.role ?? "-"}',
    );
    unawaited(_warmupService.warmUpForUser(resolvedUser).catchError((_, _) {}));
  }

  @override
  void dispose() {
    _sessionInvalidationSubscription?.cancel();
    super.dispose();
  }

  void _log(String message) {
    // Temporary debug logging removed.
  }
}
