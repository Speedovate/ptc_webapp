// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webapp/constants/app_colors.dart';

class InAppBrowserGuard extends StatefulWidget {
  const InAppBrowserGuard({super.key, required this.child});

  final Widget child;

  @override
  State<InAppBrowserGuard> createState() => _InAppBrowserGuardState();
}

class _InAppBrowserGuardState extends State<InAppBrowserGuard> {
  static const _dismissedSessionKey =
      'paltranco_in_app_browser_prompt_dismissed';

  late final _InAppBrowserInfo _info = _InAppBrowserInfo.fromWindow();
  bool _dismissed = false;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _dismissed = html.window.sessionStorage[_dismissedSessionKey] == 'true';
  }

  @override
  Widget build(BuildContext context) {
    if (!_info.shouldPrompt || _dismissed) {
      return widget.child;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned.fill(
          child: ColoredBox(
            color: const Color(0xCC2B146A),
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppColors.primaryBorder),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x140E0A1F),
                            blurRadius: 30,
                            offset: Offset(0, 18),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 54,
                              height: 54,
                              decoration: const BoxDecoration(
                                color: AppColors.primaryColor,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.open_in_browser_rounded,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'Open In Chrome Instead',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primaryColor,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _info.message,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textPrimary,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _info.instructions,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primaryColor.withValues(
                                  alpha: 0.82,
                                ),
                                height: 1.4,
                              ),
                            ),
                            if (_copied) ...[
                              const SizedBox(height: 10),
                              const Text(
                                'Link copied. You can now paste it into Chrome.',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primaryColor,
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: FilledButton(
                                onPressed: _openPreferredBrowser,
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.primaryColor,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                child: Text(
                                  _info.primaryActionLabel,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: OutlinedButton(
                                onPressed: _copyCurrentLink,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.primaryColor,
                                  side: const BorderSide(
                                    color: AppColors.primaryBorder,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: const Text(
                                  'Copy Link',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _continueHere,
                                child: const Text('Continue Here'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _copyCurrentLink() async {
    await Clipboard.setData(ClipboardData(text: _info.currentUrl));
    if (!mounted) {
      return;
    }
    setState(() {
      _copied = true;
    });
  }

  void _continueHere() {
    html.window.sessionStorage[_dismissedSessionKey] = 'true';
    setState(() {
      _dismissed = true;
    });
  }

  void _openPreferredBrowser() {
    if (_info.chromeIntentUrl != null) {
      html.window.location.href = _info.chromeIntentUrl!;
      return;
    }
    if (_info.iOSChromeUrl != null) {
      html.window.location.href = _info.iOSChromeUrl!;
      unawaited(_fallbackCopyAfterDelay());
      return;
    }
    html.window.open(_info.currentUrl, '_blank');
    unawaited(_fallbackCopyAfterDelay());
  }

  Future<void> _fallbackCopyAfterDelay() async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) {
      return;
    }
    await _copyCurrentLink();
  }
}

class _InAppBrowserInfo {
  const _InAppBrowserInfo({
    required this.currentUrl,
    required this.sourceLabel,
    required this.isInAppBrowser,
    required this.isAndroid,
    required this.isIOS,
    required this.isDesktopLike,
    required this.shouldPrompt,
    required this.isPreferredBrowser,
    required this.chromeIntentUrl,
    required this.iOSChromeUrl,
  });

  final String currentUrl;
  final String sourceLabel;
  final bool isInAppBrowser;
  final bool isAndroid;
  final bool isIOS;
  final bool isDesktopLike;
  final bool shouldPrompt;
  final bool isPreferredBrowser;
  final String? chromeIntentUrl;
  final String? iOSChromeUrl;

  static _InAppBrowserInfo fromWindow() {
    final userAgent = html.window.navigator.userAgent.toLowerCase();
    final currentUrl = html.window.location.href;
    final isAndroid = userAgent.contains('android');
    final isIOS = userAgent.contains('iphone') || userAgent.contains('ipad');
    final isDesktopLike = !isAndroid && !isIOS;

    String sourceLabel = 'in-app browser';
    var isInApp = false;
    var isPreferredBrowser = false;

    if (userAgent.contains('messenger') ||
        userAgent.contains('fban') ||
        userAgent.contains('fbav') ||
        userAgent.contains('fb_iab')) {
      sourceLabel = 'Messenger';
      isInApp = true;
    } else if (userAgent.contains('telegram')) {
      sourceLabel = 'Telegram';
      isInApp = true;
    } else if (userAgent.contains('viber')) {
      sourceLabel = 'Viber';
      isInApp = true;
    } else if (userAgent.contains('line/')) {
      sourceLabel = 'LINE';
      isInApp = true;
    } else if (userAgent.contains('instagram')) {
      sourceLabel = 'Instagram';
      isInApp = true;
    } else if (userAgent.contains('crios/')) {
      sourceLabel = 'Chrome';
      isPreferredBrowser = true;
    } else if (userAgent.contains('edgios/')) {
      sourceLabel = 'Edge';
    } else if (userAgent.contains('fxios/')) {
      sourceLabel = 'Firefox';
    } else if (userAgent.contains('opt/')) {
      sourceLabel = 'Opera';
    } else if (userAgent.contains('samsungbrowser/')) {
      sourceLabel = 'Samsung Internet';
    } else if (userAgent.contains('edga/') || userAgent.contains('edg/')) {
      sourceLabel = 'Edge';
    } else if (userAgent.contains('opr/') || userAgent.contains('opera')) {
      sourceLabel = 'Opera';
    } else if (userAgent.contains('firefox/')) {
      sourceLabel = 'Firefox';
    } else if (userAgent.contains('safari/') &&
        !userAgent.contains('chrome/') &&
        !userAgent.contains('crios/')) {
      sourceLabel = 'Safari';
    } else if (userAgent.contains('chrome/') &&
        !userAgent.contains('edg/') &&
        !userAgent.contains('edga/') &&
        !userAgent.contains('opr/') &&
        !userAgent.contains('opera') &&
        !userAgent.contains('samsungbrowser/')) {
      sourceLabel = 'Chrome';
      isPreferredBrowser = true;
    } else {
      sourceLabel = 'browser';
    }

    final uri = Uri.tryParse(currentUrl);
    String? chromeIntentUrl;
    String? iOSChromeUrl;

    if (uri != null) {
      final authority = uri.authority;
      final path = uri.path;
      final query = uri.hasQuery ? '?${uri.query}' : '';
      final fragment = uri.hasFragment ? '#${uri.fragment}' : '';

      if (isAndroid && authority.isNotEmpty) {
        chromeIntentUrl =
            'intent://$authority$path$query$fragment#Intent;scheme=${uri.scheme};package=com.android.chrome;end';
      }

      if (isIOS && authority.isNotEmpty) {
        final chromeScheme = uri.scheme == 'https'
            ? 'googlechromes'
            : 'googlechrome';
        iOSChromeUrl = '$chromeScheme://$authority$path$query$fragment';
      }
    }

    return _InAppBrowserInfo(
      currentUrl: currentUrl,
      sourceLabel: sourceLabel,
      isInAppBrowser: isInApp,
      isAndroid: isAndroid,
      isIOS: isIOS,
      isDesktopLike: isDesktopLike,
      shouldPrompt: isInApp || !isPreferredBrowser,
      isPreferredBrowser: isPreferredBrowser,
      chromeIntentUrl: chromeIntentUrl,
      iOSChromeUrl: iOSChromeUrl,
    );
  }

  String get primaryActionLabel {
    if (isAndroid) {
      return 'Open In Chrome';
    }
    if (isIOS) {
      return 'Try Opening In Chrome';
    }
    return 'Open In Chrome';
  }

  String get message => isInAppBrowser
      ? 'This page is currently inside $sourceLabel. Some layouts, height behavior, sign in flow, and file actions may not work correctly there. For the best experience, open Paltranco Digital Platform in Chrome instead.'
      : 'This page is currently open in $sourceLabel. Paltranco Digital Platform works best in Chrome, so we recommend switching there whenever possible.';

  String get instructions {
    if (isAndroid) {
      return isInAppBrowser
          ? 'If Chrome does not open automatically, tap the menu in $sourceLabel and choose Open in browser.'
          : 'If Chrome does not open automatically, copy the link and open it manually in Chrome.';
    }
    if (isIOS) {
      return isInAppBrowser
          ? 'If Chrome does not open automatically, tap the menu in $sourceLabel and choose Open in browser, then switch to Chrome if needed.'
          : 'If Chrome does not open automatically, copy the link and paste it into Chrome on iPhone or iPad.';
    }
    if (isDesktopLike) {
      return 'Desktop browsers cannot be forced to switch apps from the web. Copy the link and open it directly in Chrome if you want the preferred experience.';
    }
    return 'If Chrome does not open automatically, copy the link and open it manually in Chrome.';
  }
}
