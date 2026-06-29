import 'package:flutter/widgets.dart';

typedef OpenEmbeddedSupportCallback =
    void Function({
      String? initialTopicKey,
      String? initialBookingId,
      String? initialUserId,
    });

class SupportSectionNavigationScope extends InheritedWidget {
  const SupportSectionNavigationScope({
    super.key,
    required this.onOpenSupport,
    required super.child,
  });

  final OpenEmbeddedSupportCallback onOpenSupport;

  static SupportSectionNavigationScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<
      SupportSectionNavigationScope
    >();
  }

  @override
  bool updateShouldNotify(SupportSectionNavigationScope oldWidget) {
    return onOpenSupport != oldWidget.onOpenSupport;
  }
}
