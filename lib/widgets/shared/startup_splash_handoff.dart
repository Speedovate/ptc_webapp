import 'package:flutter/material.dart';
import 'package:webapp/services/startup_splash.dart';

/// Reveals the first home frame only after its essential data has resolved.
class StartupSplashHandoff extends StatefulWidget {
  const StartupSplashHandoff({
    super.key,
    required this.ready,
    required this.child,
    this.onReady,
  });

  final bool ready;
  final Widget child;
  final VoidCallback? onReady;

  @override
  State<StartupSplashHandoff> createState() => _StartupSplashHandoffState();
}

class _StartupSplashHandoffState extends State<StartupSplashHandoff> {
  bool _dismissed = false;
  bool _scheduled = false;

  @override
  Widget build(BuildContext context) {
    if (widget.ready && !_dismissed && !_scheduled) {
      _scheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduled = false;
        if (!mounted || !widget.ready || _dismissed) return;
        _dismissed = true;
        (widget.onReady ?? dismissStartupSplash)();
      });
    }
    return widget.child;
  }
}
