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
  final AppWarmupService _warmupService = AppWarmupService.instance;
  final RoleAccessService _roleAccessService = RoleAccessService.instance;

  bool isLoading = true;
  UserModel? currentUser;
  bool isQuickLoggedIn = false;
  StreamSubscription<void>? _sessionInvalidationSubscription;
  static const Duration _startupStepTimeout = Duration(seconds: 8);
  int _sessionEpoch = 0;

  Future<void> initialize() async {
    isLoading = true;
    notifyListeners();
    try {
      await _repository
          .initialize()
          .timeout(_startupStepTimeout, onTimeout: () {
          });

      currentUser = await _repository
          .getCurrentUser()
          .timeout(_startupStepTimeout, onTimeout: () {
            return null;
          });

      _roleAccessService.setCurrentUser(currentUser);
      unawaited(
        _roleAccessService.initialize().then((_) {
        }).catchError((error, stackTrace) {
        }),
      );
      isQuickLoggedIn = await _repository
          .hasQuickLoginSource()
          .timeout(_startupStepTimeout, onTimeout: () {
            return false;
          });

      await _bindCurrentSessionWatch()
          .timeout(_startupStepTimeout, onTimeout: () {
          });
    } catch (error) {
      // Startup should still continue using cached/local state when background steps fail.
    }
    isLoading = false;
    notifyListeners();
    unawaited(_finishInitializationInBackground());
  }

  Future<void> refreshCurrentUser() async {
    currentUser = await _repository.getCurrentUser();
    _roleAccessService.setCurrentUser(currentUser);
    isQuickLoggedIn = await _repository.hasQuickLoginSource();
    await _bindCurrentSessionWatch();
    notifyListeners();
  }

  Future<void> completeAuthentication(UserModel user) async {
    final authEpoch = ++_sessionEpoch;
    isLoading = true;
    currentUser = user;
    _roleAccessService.setCurrentUser(user);
    notifyListeners();
    try {
      isQuickLoggedIn = await _repository.hasQuickLoginSource();
      await _bindCurrentSessionWatch();
      unawaited(_finishInitializationInBackground(userOverride: user));
      unawaited(_refreshCurrentUserInBackground(user, authEpoch));
    } catch (_) {
      if (authEpoch != _sessionEpoch) {
        return;
      }
      currentUser = user;
      _roleAccessService.setCurrentUser(currentUser);
      isQuickLoggedIn = await _repository.hasQuickLoginSource();
      await _bindCurrentSessionWatch();
    } finally {
      if (authEpoch == _sessionEpoch) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> logout() async {
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
  }

  Future<void> goBackFromQuickLogin() async {
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
      unawaited(_finishInitializationInBackground());
    } catch (_) {
      currentUser = previousUser;
      _roleAccessService.setCurrentUser(currentUser);
      isQuickLoggedIn = previousQuickLoggedIn;
      await _bindCurrentSessionWatch();
      rethrow;
    } finally {
      isLoading = false;
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
          currentUser = null;
          _roleAccessService.setCurrentUser(null);
          isQuickLoggedIn = false;
          notifyListeners();
        });
  }

  Future<void> _finishInitializationInBackground({
    UserModel? userOverride,
  }) async {
    try {
      await _warmupService.warmUpForUser(userOverride ?? currentUser);
    } catch (_) {}
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
      currentUser = refreshedUser ?? fallbackUser;
      _roleAccessService.setCurrentUser(currentUser);
      isQuickLoggedIn = await _repository.hasQuickLoginSource();
      if (authEpoch != _sessionEpoch) {
        return;
      }
      await _bindCurrentSessionWatch();
      if (authEpoch != _sessionEpoch) {
        return;
      }
      notifyListeners();
    } catch (_) {
      if (authEpoch != _sessionEpoch) {
        return;
      }
      currentUser = fallbackUser;
      _roleAccessService.setCurrentUser(currentUser);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sessionInvalidationSubscription?.cancel();
    super.dispose();
  }
}
