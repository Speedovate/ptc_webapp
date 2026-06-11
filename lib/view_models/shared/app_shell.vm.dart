import 'package:flutter/foundation.dart';
import 'package:stacked/stacked.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';

class AppShellViewModel extends BaseViewModel {
  AppShellViewModel({AuthRepository? repository})
    : _repository = repository ?? AuthRequest.instance;

  final AuthRepository _repository;

  bool isLoading = true;
  UserModel? currentUser;
  bool isQuickLoggedIn = false;

  Future<void> initialize() async {
    debugPrint('[APP_SHELL] initialize start');
    isLoading = true;
    notifyListeners();
    await _repository.initialize();
    currentUser = await _repository.getCurrentUser();
    isQuickLoggedIn = await _repository.hasQuickLoginSource();
    isLoading = false;
    debugPrint(
      '[APP_SHELL] initialize done currentUserId=${currentUser?.id} role=${currentUser?.role} quick=$isQuickLoggedIn',
    );
    notifyListeners();
  }

  Future<void> refreshCurrentUser() async {
    debugPrint('[APP_SHELL] refreshCurrentUser start');
    currentUser = await _repository.getCurrentUser();
    isQuickLoggedIn = await _repository.hasQuickLoginSource();
    debugPrint(
      '[APP_SHELL] refreshCurrentUser done currentUserId=${currentUser?.id} role=${currentUser?.role} quick=$isQuickLoggedIn',
    );
    notifyListeners();
  }

  Future<void> completeAuthentication(UserModel user) async {
    debugPrint(
      '[APP_SHELL] completeAuthentication incoming userId=${user.id} role=${user.role} photo=${user.photo}',
    );
    currentUser = user;
    notifyListeners();
    try {
      isQuickLoggedIn = await _repository.hasQuickLoginSource();
      notifyListeners();
      await refreshCurrentUser();
    } catch (_) {
      debugPrint('[APP_SHELL] completeAuthentication refresh fallback used');
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
    currentUser = await _repository.returnToQuickLoginSource();
    isQuickLoggedIn = await _repository.hasQuickLoginSource();
    notifyListeners();
  }
}
