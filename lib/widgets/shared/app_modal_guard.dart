import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as material;

class AppModalGuard {
  AppModalGuard._();

  static const double _defaultBottomSheetMaxHeightRatio = 9 / 16;
  static const Duration _debounceWindow = Duration(milliseconds: 350);
  static final Map<String, Future<Object?>> _activeModalFutures =
      <String, Future<Object?>>{};
  static final Map<String, DateTime> _lastAttemptAtByKey =
      <String, DateTime>{};
  static bool _presentationLocked = false;

  static Future<T?> showDialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
    Color? barrierColor,
    String? barrierLabel,
    bool useSafeArea = true,
    bool useRootNavigator = true,
    RouteSettings? routeSettings,
    Offset? anchorPoint,
    TraversalEdgeBehavior? traversalEdgeBehavior,
    bool fullscreenDialog = false,
    String? modalKey,
  }) async {
    final resolvedKey = _resolveModalKey(
      explicitKey: modalKey,
      routeSettings: routeSettings,
      fallbackPrefix: 'dialog',
    );
    final existing = _activeModalFutures[resolvedKey];
    if (existing != null) {
      return await existing.then((value) => value as T?);
    }

    final now = DateTime.now();
    final lastAttemptAt = _lastAttemptAtByKey[resolvedKey];
    final isInsideDebounceWindow =
        lastAttemptAt != null &&
        now.difference(lastAttemptAt) < _debounceWindow;
    if (_presentationLocked || isInsideDebounceWindow) {
      return null;
    }

    _presentationLocked = true;
    _lastAttemptAtByKey[resolvedKey] = now;
    scheduleMicrotask(() {
      _presentationLocked = false;
    });

    final future = material.showDialog<T>(
      context: context,
      builder: builder,
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor,
      barrierLabel: barrierLabel,
      useSafeArea: useSafeArea,
      useRootNavigator: useRootNavigator,
      routeSettings: routeSettings,
      anchorPoint: anchorPoint,
      traversalEdgeBehavior: traversalEdgeBehavior,
      fullscreenDialog: fullscreenDialog,
    );
    _activeModalFutures[resolvedKey] = future.then<Object?>((value) => value);
    try {
      return await future;
    } finally {
      _activeModalFutures.remove(resolvedKey);
      _lastAttemptAtByKey[resolvedKey] = DateTime.now();
    }
  }

  static Future<T?> showModalBottomSheet<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    Color? backgroundColor,
    String? barrierLabel,
    double? elevation,
    ShapeBorder? shape,
    Clip? clipBehavior,
    BoxConstraints? constraints,
    Color? barrierColor,
    bool isScrollControlled = false,
    double scrollControlDisabledMaxHeightRatio =
        _defaultBottomSheetMaxHeightRatio,
    bool useRootNavigator = false,
    bool isDismissible = true,
    bool enableDrag = true,
    bool? showDragHandle,
    bool useSafeArea = false,
    RouteSettings? routeSettings,
    AnimationController? transitionAnimationController,
    Offset? anchorPoint,
    AnimationStyle? sheetAnimationStyle,
    String? modalKey,
  }) async {
    final resolvedKey = _resolveModalKey(
      explicitKey: modalKey,
      routeSettings: routeSettings,
      fallbackPrefix: 'bottom-sheet',
    );
    final existing = _activeModalFutures[resolvedKey];
    if (existing != null) {
      return await existing.then((value) => value as T?);
    }

    final now = DateTime.now();
    final lastAttemptAt = _lastAttemptAtByKey[resolvedKey];
    final isInsideDebounceWindow =
        lastAttemptAt != null &&
        now.difference(lastAttemptAt) < _debounceWindow;
    if (_presentationLocked || isInsideDebounceWindow) {
      return null;
    }

    _presentationLocked = true;
    _lastAttemptAtByKey[resolvedKey] = now;
    scheduleMicrotask(() {
      _presentationLocked = false;
    });

    final future = material.showModalBottomSheet<T>(
      context: context,
      builder: builder,
      backgroundColor: backgroundColor,
      barrierLabel: barrierLabel,
      elevation: elevation,
      shape: shape,
      clipBehavior: clipBehavior,
      constraints: constraints,
      barrierColor: barrierColor,
      isScrollControlled: isScrollControlled,
      scrollControlDisabledMaxHeightRatio:
          scrollControlDisabledMaxHeightRatio,
      useRootNavigator: useRootNavigator,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      showDragHandle: showDragHandle,
      useSafeArea: useSafeArea,
      routeSettings: routeSettings,
      transitionAnimationController: transitionAnimationController,
      anchorPoint: anchorPoint,
      sheetAnimationStyle: sheetAnimationStyle,
    );
    _activeModalFutures[resolvedKey] = future.then<Object?>((value) => value);
    try {
      return await future;
    } finally {
      _activeModalFutures.remove(resolvedKey);
      _lastAttemptAtByKey[resolvedKey] = DateTime.now();
    }
  }

  static String _resolveModalKey({
    required String fallbackPrefix,
    String? explicitKey,
    RouteSettings? routeSettings,
  }) {
    final normalizedExplicitKey = explicitKey?.trim();
    if (normalizedExplicitKey != null && normalizedExplicitKey.isNotEmpty) {
      return normalizedExplicitKey;
    }
    final routeName = routeSettings?.name?.trim();
    if (routeName != null && routeName.isNotEmpty) {
      return '$fallbackPrefix:$routeName';
    }
    final stackLines = StackTrace.current.toString().split('\n');
    final callerLine = stackLines.firstWhere(
      (line) =>
          line.contains('package:webapp/') &&
          !line.contains('app_modal_guard.dart'),
      orElse: () => stackLines.length > 1 ? stackLines[1] : fallbackPrefix,
    );
    return '$fallbackPrefix:${callerLine.trim()}';
  }
}

Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useSafeArea = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
  TraversalEdgeBehavior? traversalEdgeBehavior,
  bool fullscreenDialog = false,
  String? modalKey,
}) {
  return AppModalGuard.showDialog<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    barrierLabel: barrierLabel,
    useSafeArea: useSafeArea,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    anchorPoint: anchorPoint,
    traversalEdgeBehavior: traversalEdgeBehavior,
    fullscreenDialog: fullscreenDialog,
    modalKey: modalKey,
  );
}

Future<T?> showAppModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  String? barrierLabel,
  double? elevation,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  Color? barrierColor,
  bool isScrollControlled = false,
  double scrollControlDisabledMaxHeightRatio =
      AppModalGuard._defaultBottomSheetMaxHeightRatio,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  bool useSafeArea = false,
  RouteSettings? routeSettings,
  AnimationController? transitionAnimationController,
  Offset? anchorPoint,
  AnimationStyle? sheetAnimationStyle,
  String? modalKey,
}) {
  return AppModalGuard.showModalBottomSheet<T>(
    context: context,
    builder: builder,
    backgroundColor: backgroundColor,
    barrierLabel: barrierLabel,
    elevation: elevation,
    shape: shape,
    clipBehavior: clipBehavior,
    constraints: constraints,
    barrierColor: barrierColor,
    isScrollControlled: isScrollControlled,
    scrollControlDisabledMaxHeightRatio:
        scrollControlDisabledMaxHeightRatio,
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: showDragHandle,
    useSafeArea: useSafeArea,
    routeSettings: routeSettings,
    transitionAnimationController: transitionAnimationController,
    anchorPoint: anchorPoint,
    sheetAnimationStyle: sheetAnimationStyle,
    modalKey: modalKey,
  );
}
