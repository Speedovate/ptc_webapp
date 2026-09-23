// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

Map<String, Object?> syncErrorEnvironment() => {
  'browser': html.window.navigator.userAgent,
  'language': html.window.navigator.language,
  'viewport_width': html.window.innerWidth,
  'viewport_height': html.window.innerHeight,
  // Exclude query strings and fragments, which may carry credentials.
  'path': html.window.location.pathname,
};
