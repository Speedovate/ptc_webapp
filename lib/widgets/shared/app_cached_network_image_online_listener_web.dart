// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

Stream<void> onlineEvents() =>
    html.window.onOnline.map((_) {}).asBroadcastStream();
