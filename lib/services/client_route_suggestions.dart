import 'package:webapp/models/booking.dart';
import 'package:webapp/utils/functions.dart';

const bookingRouteKeys = {
  'origin',
  'destination',
  'origin_barangay',
  'destination_barangay',
};

bool isBookingRouteFieldKey(String? key) =>
    bookingRouteKeys.contains(key?.trim().toLowerCase());

bool isPuertoPrincesaLocation(Object? value) => const {
  'ppc',
  'puerto princesa',
  'puerto princesa city',
}.contains(value?.toString().trim().toLowerCase());

/// Keep each route associated with its own client and representative. Dated
/// workflow deltas may extend a route; undated entries must be self-contained.
List<Map<String, String>> clientRepresentativeRoutes(
  Iterable<Booking> bookings,
  String? clientId,
  String? representativeName,
) {
  String normalized(Object? value) =>
      value?.toString().trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase() ??
      '';
  final client = normalizeId(clientId);
  final representative = normalized(representativeName);
  if (client == null || representative.isEmpty) return const [];
  final result = <({DateTime at, Map<String, String> route})>[];
  for (final booking in bookings) {
    if (normalizeId(booking.client?.id) != client) continue;
    final sections = (booking.statusOutputs ?? const {}).values
        .whereType<Map>()
        .toList();
    sections.sort(
      (a, b) => (DateTime.tryParse('${a['submitted_at']}') ?? DateTime(0))
          .compareTo(DateTime.tryParse('${b['submitted_at']}') ?? DateTime(0)),
    );
    var currentName = '';
    var route = <String, String>{};
    for (final section in sections) {
      final fields = section['fields'];
      if (fields is! Map) continue;
      final submittedAt = DateTime.tryParse('${section['submitted_at']}');
      if (submittedAt == null) {
        currentName = '';
        route = {};
      }
      if (fields.containsKey('representative_name')) {
        final nextName = normalized(fields['representative_name']);
        if (nextName != currentName) route = {};
        currentName = nextName;
      }
      final hasRoute = bookingRouteKeys.any(fields.containsKey);
      for (final key in bookingRouteKeys) {
        if (!fields.containsKey(key)) continue;
        final value = fields[key]?.toString().trim() ?? '';
        if (value.isEmpty || value == '-') {
          route.remove(key);
        } else {
          if ((key == 'origin' || key == 'destination') &&
              normalized(route[key]) != normalized(value)) {
            route.remove('${key}_barangay');
          }
          route[key] = value;
        }
      }
      if (hasRoute && currentName == representative && route.isNotEmpty) {
        result.add((
          at:
              submittedAt ??
              booking.updatedAt ??
              booking.createdAt ??
              DateTime(0),
          route: Map.of(route),
        ));
      }
    }
  }
  result.sort((a, b) => b.at.compareTo(a.at));
  return result.map((entry) => entry.route).toList();
}

List<String> routeFieldSuggestions(
  Iterable<Map<String, String>> routes,
  String key,
  Map<String, dynamic> answers,
) {
  final seen = <String>{};
  final values = <String>[];
  final parentKey = key.endsWith('_barangay')
      ? key.replaceFirst('_barangay', '')
      : null;
  for (final route in routes) {
    if (parentKey != null &&
        (!isPuertoPrincesaLocation(answers[parentKey]) ||
            !isPuertoPrincesaLocation(route[parentKey]))) {
      continue;
    }
    final value = route[key];
    if (value != null && seen.add(value.toLowerCase())) values.add(value);
  }
  return values;
}
