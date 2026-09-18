import 'dart:async';

import 'package:flutter/widgets.dart';

/// Keeps the mounted page (and its drafts) intact while reconnecting services.
class AppResumeRecovery extends StatefulWidget {
  const AppResumeRecovery({
    super.key,
    required this.child,
    required this.recover,
    this.settleDelay = const Duration(milliseconds: 300),
  });

  final Widget child;
  final Future<void> Function() recover;
  final Duration settleDelay;

  @override
  State<AppResumeRecovery> createState() => _AppResumeRecoveryState();
}

class _AppResumeRecoveryState extends State<AppResumeRecovery>
    with WidgetsBindingObserver {
  bool _wasBackgrounded = false;
  bool _recovering = false;
  Timer? _resumeTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _wasBackgrounded = true;
      _resumeTimer?.cancel();
    } else if (state == AppLifecycleState.resumed && _wasBackgrounded) {
      _resumeTimer?.cancel();
      // Let Flutter paint and accept input before starting recovery work.
      _resumeTimer = Timer(widget.settleDelay, _recover);
    }
  }

  Future<void> _recover() async {
    if (!mounted ||
        _recovering ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    _wasBackgrounded = false;
    _recovering = true;
    try {
      await widget.recover();
    } catch (_) {
      // Preserve the current page if the device still has no usable network.
    } finally {
      _recovering = false;
      if (mounted &&
          _wasBackgrounded &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _resumeTimer = Timer(widget.settleDelay, _recover);
      }
    }
  }

  @override
  void dispose() {
    _resumeTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
