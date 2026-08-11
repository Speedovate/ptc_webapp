import 'dart:async';

import 'package:stacked/stacked.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/services/app_warmup_service.dart';

class AppShellViewModel extends BaseViewModel {
  AppShellViewModel({AuthRepository? repository})
    : _repository = repository ?? AuthRequest.instance;

  final AuthRepository _repository;
  final AppWarmupService _warmupService = AppWarmupService.instance;

  bool isLoading = true;
  UserModel? currentUser;
  bool isQuickLoggedIn = false;

  Future<void> initialize() async {
    isLoading = true;
    notifyListeners();
    await _repository.initialize();
    currentUser = await _repository.getCurrentUser();
    isQuickLoggedIn = await _repository.hasQuickLoginSource();
    isLoading = false;
    notifyListeners();
    unawaited(_finishInitializationInBackground());
  }

  Future<void> refreshCurrentUser() async {
    currentUser = await _repository.getCurrentUser();
    isQuickLoggedIn = await _repository.hasQuickLoginSource();
    notifyListeners();
  }

  Future<void> completeAuthentication(UserModel user) async {
    isLoading = true;
    currentUser = user;
    notifyListeners();
    try {
      isQuickLoggedIn = await _repository.hasQuickLoginSource();
      await refreshCurrentUser();
      unawaited(_finishInitializationInBackground(userOverride: user));
    } catch (_) {
      currentUser = await _repository.getCurrentUser();
      isQuickLoggedIn = await _repository.hasQuickLoginSource();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _repository.logout();
    currentUser = null;
    isQuickLoggedIn = false;
    notifyListeners();
  }

  Future<void> goBackFromQuickLogin() async {
    isLoading = true;
    notifyListeners();
    currentUser = await _repository.returnToQuickLoginSource();
    isQuickLoggedIn = await _repository.hasQuickLoginSource();
    isLoading = false;
    notifyListeners();
    unawaited(_finishInitializationInBackground());
  }

  Future<void> _finishInitializationInBackground({
    UserModel? userOverride,
  }) async {
    try {
      await AuthRequest.instance.migrateSubClientDataOnce();
    } catch (_) {}
    try {
      await _warmupService.warmUpForUser(userOverride ?? currentUser);
    } catch (_) {}
  }
}
