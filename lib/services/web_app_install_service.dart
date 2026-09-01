import 'web_app_install_service_stub.dart'
    if (dart.library.html) 'web_app_install_service_web.dart'
    as impl;

class WebAppInstallAttemptResult {
  const WebAppInstallAttemptResult({
    required this.didLaunchPrompt,
    this.message,
    this.isError = false,
    this.requiresManualInstall = false,
  });

  final bool didLaunchPrompt;
  final String? message;
  final bool isError;
  final bool requiresManualInstall;
}

abstract class WebAppInstallService {
  Future<WebAppInstallAttemptResult> install();
}

WebAppInstallService get webAppInstallService => impl.webAppInstallService;
