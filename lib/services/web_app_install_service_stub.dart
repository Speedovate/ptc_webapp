import 'web_app_install_service.dart';

class _StubWebAppInstallService implements WebAppInstallService {
  @override
  Future<WebAppInstallAttemptResult> install() async {
    return const WebAppInstallAttemptResult(
      didLaunchPrompt: false,
      message: 'App install is not supported in this environment.',
      isError: true,
    );
  }
}

final WebAppInstallService webAppInstallService = _StubWebAppInstallService();
