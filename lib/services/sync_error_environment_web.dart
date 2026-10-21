// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('navigator')
external JSObject get _navigator;

/// Reads only browser-exposed estimates; never infers cellular from `4g`.
Map<String, Object?> browserNetworkEvidence(JSObject navigator) {
  JSAny? raw(JSObject object, String name) {
    try {
      return object.getProperty<JSAny?>(name.toJS);
    } catch (_) {
      return null;
    }
  }

  Object? read(JSObject object, String name) => raw(object, name)?.dartify();

  final connection =
      (raw(navigator, 'connection') ??
              raw(navigator, 'mozConnection') ??
              raw(navigator, 'webkitConnection'))
          as JSObject?;
  final type = connection == null ? null : read(connection, 'type');
  final knownType = const {
    'wifi',
    'cellular',
    'ethernet',
    'bluetooth',
    'wimax',
    'mixed',
    'other',
    'none',
  }.contains(type);
  final effective = connection == null
      ? null
      : read(connection, 'effectiveType');
  num? number(String key) {
    final value = connection == null ? null : read(connection, key);
    return value is num && value.isFinite && value >= 0 ? value : null;
  }

  return {
    'observed_at': DateTime.now().toUtc().toIso8601String(),
    'source': 'browser_network_information',
    'browser_online': read(navigator, 'onLine'),
    'network_information_supported': connection != null,
    'connection_type': knownType ? type : 'unknown',
    'connection_type_available': knownType,
    if (!knownType)
      'connection_type_unavailable_reason': connection == null
          ? 'api_not_exposed'
          : 'type_not_exposed_or_unknown',
    'effective_type': const {'slow-2g', '2g', '3g', '4g'}.contains(effective)
        ? effective
        : null,
    'effective_type_is_radio_generation': false,
    'estimated_rtt_ms': number('rtt'),
    'estimated_downlink_mbps': number('downlink'),
    'save_data': connection == null ? null : read(connection, 'saveData'),
    'carrier': 'unknown',
    'carrier_unavailable_reason': 'not_exposed_by_browser',
    'server_reachability_verified': false,
  };
}

Map<String, Object?> syncNetworkEnvironment() =>
    browserNetworkEvidence(_navigator);

Map<String, Object?> syncErrorEnvironment() => {
  'browser': html.window.navigator.userAgent,
  'language': html.window.navigator.language,
  'viewport_width': html.window.innerWidth,
  'viewport_height': html.window.innerHeight,
  // Exclude query strings and fragments, which may carry credentials.
  'path': html.window.location.pathname,
  'network': syncNetworkEnvironment(),
};
