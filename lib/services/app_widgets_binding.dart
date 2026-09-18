import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Reject stale framework views during the web engine's restart teardown.
/// Compare identity as well as ID: the engine may reuse an ID for a new view.
bool areFlutterViewsRegistered(
  Iterable<ui.FlutterView> views,
  ui.FlutterView? Function(int id) lookup,
) => views.every((view) => identical(lookup(view.viewId), view));

class AppWidgetsBinding extends WidgetsFlutterBinding {
  @override
  bool get sendFramesToEngine {
    if (!super.sendFramesToEngine) {
      return false;
    }
    if (!kIsWeb) {
      return true;
    }
    // Keep framework build/layout running normally. Only engine submission is
    // gated while its registry no longer owns a framework RenderView. A fresh
    // registered view is automatically allowed; no sticky flag or timer.
    return areFlutterViewsRegistered(
      renderViews.map((view) => view.flutterView),
      (id) => platformDispatcher.view(id: id),
    );
  }
}
