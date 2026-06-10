import 'package:stacked/stacked.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';

class AppShellViewModel extends BaseViewModel {
  AppShellViewModel({
    AuthRepository? repository,
  }) : _repository = repository ?? AuthRequest.instance;

  final AuthRepository _repository;

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
  }

  Future<void> refreshCurrentUser() async {
    currentUser = await _repository.getCurrentUser();
    isQuickLoggedIn = await _repository.hasQuickLoginSource();
    notifyListeners();
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
