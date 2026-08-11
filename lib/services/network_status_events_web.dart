// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

bool currentNetworkStatus() => html.window.navigator.onLine ?? true;

Stream<bool> networkStatusEvents() {
  return Stream<bool>.multi((controller) {
    controller.add(currentNetworkStatus());
    final onlineSubscription = html.window.onOnline.listen((_) {
      controller.add(true);
    });
    final offlineSubscription = html.window.onOffline.listen((_) {
      controller.add(false);
    });
    controller.onCancel = () async {
      await onlineSubscription.cancel();
      await offlineSubscription.cancel();
    };
  }).asBroadcastStream();
}
