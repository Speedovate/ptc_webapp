import 'package:flutter/foundation.dart';
import 'package:webapp/services/kpi/operations_catalog.dart';

/// Runtime overlay. Default constants remain available without network access.
class LocationOptionRegistry {
  static const keys = [
    'cities',
    'origin',
    'destination',
    'origin_barangay',
    'destination_barangay',
  ];
  static final revision = ValueNotifier<int>(0);
  static Map<String, dynamic> _options = {};
  static Map<String, dynamic> _retired = {};
  static Map<String, String> _labels = {};
  static final _defaultLabels = const OperationsCatalog(
    {},
  ).labelsFor(DateTime.utc(2026));
  static final _defaultOptions = const OperationsCatalog({}).options;
  static final _defaultRetired = const OperationsCatalog({}).retired;
  static bool supports(String? key) => keys.contains(key);
  static void apply(
    Map<String, dynamic> options,
    Map<String, dynamic> retired, {
    Map<String, String> labels = const {},
  }) {
    _options = options;
    _retired = retired;
    _labels = labels;
    revision.value++;
  }

  static String label(String? key, String value) =>
      supports(key) ? _labels[value] ?? _defaultLabels[value] ?? value : value;

  static List<String> options(String? key, List<String> fallback) {
    final raw = _options[key];
    if (raw is List) {
      return raw.whereType<String>().toList();
    }
    final defaults = _defaultOptions[key];
    return defaults is List ? defaults.whereType<String>().toList() : fallback;
  }

  static List<String> retired(String key) =>
      ((_retired[key] ?? _defaultRetired[key]) as List?)
          ?.whereType<String>()
          .toList() ??
      [];
  static bool accepts(String key, String value, List<String> fallback) => [
    ...options(key, fallback),
    ...retired(key),
  ].any((s) => s.toLowerCase() == value.trim().toLowerCase());
}
