import 'dart:async';
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;

import 'web_app_install_service.dart';

class _WebAppInstallService implements WebAppInstallService {
  bool _initialized = false;
  Object? _deferredPrompt;

  void _ensureInitialized() {
    if (_initialized) {
      _deferredPrompt ??= _readDeferredPrompt();
      return;
    }
    _initialized = true;
    _deferredPrompt = _readDeferredPrompt();
    html.window.addEventListener('beforeinstallprompt', _handleBeforeInstall);
    html.window.addEventListener('appinstalled', _handleAppInstalled);
    html.window.addEventListener(
      'paltranco-install-available',
      _handleInstallAvailable,
    );
    html.window.addEventListener('paltranco-installed', _handleInstalledFlag);
  }

  Object? _readDeferredPrompt() {
    try {
      return (html.window as dynamic).__paltrancoInstallPrompt;
    } catch (_) {
      return null;
    }
  }

  void _clearDeferredPrompt() {
    _deferredPrompt = null;
    try {
      (html.window as dynamic).__paltrancoInstallPrompt = null;
    } catch (_) {}
  }

  void _markInstalled() {
    try {
      (html.window as dynamic).__paltrancoInstalled = true;
    } catch (_) {}
  }

  Future<bool> _requestBrowserInstallPrompt() async {
    try {
      final launched = await Future.sync(
        () => (html.window as dynamic).__paltrancoRequestInstall(),
      );
      return launched?.launched == true;
    } catch (_) {
      return false;
    }
  }

  bool _isInstalled() {
    try {
      final installedFlag =
          (html.window as dynamic).__paltrancoInstalled == true;
      if (installedFlag) {
        return true;
      }
    } catch (_) {}

    try {
      final standaloneMedia = html.window.matchMedia(
        '(display-mode: standalone)',
      );
      if (standaloneMedia.matches) {
        return true;
      }
    } catch (_) {}

    try {
      final navigator = html.window.navigator;
      if ((navigator as dynamic).standalone == true) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  bool _isIosDevice() {
    final agent = html.window.navigator.userAgent.toLowerCase();
    return agent.contains('iphone') ||
        agent.contains('ipad') ||
        agent.contains('ipod');
  }

  bool _isChromiumOrAndroid() {
    final agent = html.window.navigator.userAgent.toLowerCase();
    return agent.contains('android') ||
        agent.contains('chrome') ||
        agent.contains('crios') ||
        agent.contains('edg') ||
        agent.contains('samsungbrowser');
  }

  void _handleBeforeInstall(html.Event event) {
    event.preventDefault();
    _deferredPrompt = event;
    try {
      (html.window as dynamic).__paltrancoInstallPrompt = event;
    } catch (_) {}
  }

  void _handleAppInstalled(html.Event event) {
    _markInstalled();
    _clearDeferredPrompt();
  }

  void _handleInstallAvailable(html.Event event) {
    _deferredPrompt = _readDeferredPrompt();
  }

  void _handleInstalledFlag(html.Event event) {
    _markInstalled();
    _clearDeferredPrompt();
  }

  @override
  Future<WebAppInstallAttemptResult> install() async {
    _ensureInitialized();

    if (_isInstalled()) {
      return const WebAppInstallAttemptResult(
        didLaunchPrompt: false,
        message: 'App is already installed on this device.',
      );
    }

    final promptEvent = _deferredPrompt ?? _readDeferredPrompt();
    if (promptEvent != null) {
      final didLaunchPrompt = await _requestBrowserInstallPrompt();
      if (didLaunchPrompt) {
        _clearDeferredPrompt();
        return const WebAppInstallAttemptResult(
          didLaunchPrompt: true,
          message: 'Install prompt opened.',
        );
      }
      _clearDeferredPrompt();
    }

    if (_isIosDevice()) {
      return const WebAppInstallAttemptResult(
        didLaunchPrompt: false,
        message:
            'To install on iPhone or iPad, tap Share then Add to Home Screen.',
        requiresManualInstall: true,
      );
    }

    if (_isChromiumOrAndroid()) {
      return const WebAppInstallAttemptResult(
        didLaunchPrompt: false,
        message:
            'Chrome has not shown its install prompt yet. Tap the three-dot menu, then choose Install app or Add to Home screen.',
        requiresManualInstall: true,
      );
    }

    return const WebAppInstallAttemptResult(
      didLaunchPrompt: false,
      message: 'This browser does not support installing this app right now.',
      isError: true,
    );
  }

  @override
  void openInstallPage() {
    html.window.location.assign('/download');
  }
}

final WebAppInstallService webAppInstallService = _WebAppInstallService();
