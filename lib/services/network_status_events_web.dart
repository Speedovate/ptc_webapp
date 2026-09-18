// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

bool isAppVisible() => html.document.visibilityState != 'hidden';

bool currentNetworkStatus() => html.window.navigator.onLine ?? true;

Stream<bool> networkStatusEvents() {
  return Stream<bool>.multi((controller) {
    // `navigator.onLine` is the initial state, not a reconnection. Consumers
    // read it directly during initialization; this stream is only for actual
    // offline <-> online transitions.
    var lastKnownStatus = currentNetworkStatus();

    void emitTransition(bool nextStatus) {
      if (nextStatus == lastKnownStatus) {
        return;
      }
      lastKnownStatus = nextStatus;
      controller.add(nextStatus);
    }

    final onlineSubscription = html.window.onOnline.listen((_) {
      emitTransition(true);
    });
    final offlineSubscription = html.window.onOffline.listen((_) {
      emitTransition(false);
    });
    controller.onCancel = () async {
      await onlineSubscription.cancel();
      await offlineSubscription.cancel();
    };
  }).asBroadcastStream();
}
