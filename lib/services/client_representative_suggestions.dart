import 'package:webapp/models/user.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/utils/functions.dart';

/// Suggestions come from saved booking history, never another client's values.
List<String> clientRepresentativeSuggestions(
  Iterable<Booking> bookings,
  String? clientId,
) {
  final client = normalizeId(clientId);
  if (client == null) return const [];
  final names = <String, String>{};
  for (final booking in bookings) {
    if (normalizeId(booking.client?.id) != client) continue;
    for (final section in (booking.statusOutputs ?? const {}).values) {
      if (section is! Map || section['fields'] is! Map) continue;
      final value = (section['fields'] as Map)['representative_name'];
      if (value is! String) continue;
      final name = value.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (name.isEmpty || name == '-') continue;
      names.putIfAbsent(name.toLowerCase(), () => name);
    }
  }
  return names.values.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
}

/// Old dynamic client fields may contain a display name rather than an ID.
/// Resolve only a unique match; never combine accounts that share a name.
String? representativeClientSelectionId(
  String? selection,
  Iterable<UserModel> users,
) {
  final value = normalizeId(selection);
  if (value == null) return null;
  if (users.any((user) => normalizeId(user.id) == value)) return value;
  final matches = users
      .where(
        (user) =>
            normalizeRoleKey(user.role) == 'client' &&
            user.name?.trim().toLowerCase() == value.toLowerCase(),
      )
      .toList();
  return matches.length == 1 ? normalizeId(matches.single.id) : null;
}

/// Build a safe name/phone association from each booking's chronological deltas.
/// Prefer the latest dated saved number; ambiguous ties require manual entry.
Map<String, String> clientRepresentativePhones(
  Iterable<Booking> bookings,
  String? clientId,
) {
  final client = normalizeId(clientId);
  if (client == null) return const {};
  String? nameKey(Object? value) {
    if (value is! String) return null;
    final text = value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    return text.isEmpty || text == '-' ? null : text;
  }

  final phones = <String, Set<String>>{};
  final latestPhoneTimes = <String, DateTime>{};
  void addPhone(String name, String phone, DateTime? savedAt) {
    final previousTime = latestPhoneTimes[name];
    if (savedAt != null &&
        (previousTime == null || savedAt.isAfter(previousTime))) {
      latestPhoneTimes[name] = savedAt;
      phones[name] = {phone};
    } else if (savedAt == previousTime) {
      (phones[name] ??= {}).add(phone);
    }
  }

  for (final booking in bookings) {
    if (normalizeId(booking.client?.id) != client) continue;
    final dated = <Map>[];
    final legacy = <String, Set<String>>{};
    for (final section
        in (booking.statusOutputs ?? const {}).values.whereType<Map>()) {
      if (DateTime.tryParse('${section['submitted_at']}') != null) {
        dated.add(section);
      } else {
        final fields = section['fields'];
        if (fields is! Map) continue;
        final name = nameKey(fields['representative_name']);
        final phone = normalizePhilippinePhone(
          fields['representative_phone']?.toString(),
        );
        if (name != null && phone != null) (legacy[name] ??= {}).add(phone);
      }
    }
    dated.sort(
      (a, b) => DateTime.parse(
        '${a['submitted_at']}',
      ).compareTo(DateTime.parse('${b['submitted_at']}')),
    );
    // An undated legacy pair can seed later partial edits only if unambiguous.
    String? currentName = legacy.length == 1 && legacy.values.single.length == 1
        ? legacy.keys.single
        : null;
    String? currentPhone = currentName == null
        ? null
        : legacy[currentName]!.single;
    final latestByName = <String, String>{};
    final savedAtByName = <String, DateTime>{};
    final touched = <String>{};
    for (final section in dated) {
      final fields = section['fields'];
      if (fields is! Map) continue;
      final hasName = fields.containsKey('representative_name');
      final hasPhone = fields.containsKey('representative_phone');
      if (!hasName && !hasPhone) continue;
      if (hasName) {
        final next = nameKey(fields['representative_name']);
        if (next != currentName) currentPhone = null;
        currentName = next;
      }
      if (hasPhone) {
        currentPhone = normalizePhilippinePhone(
          fields['representative_phone']?.toString(),
        );
      }
      if (currentName == null) continue;
      touched.add(currentName);
      if (currentPhone != null) {
        latestByName[currentName] = currentPhone;
        savedAtByName[currentName] = DateTime.parse(
          '${section['submitted_at']}',
        );
      } else if (hasPhone) {
        latestByName.remove(currentName);
      }
    }
    for (final entry in legacy.entries) {
      if (!touched.contains(entry.key)) {
        for (final phone in entry.value) {
          addPhone(entry.key, phone, booking.updatedAt ?? booking.createdAt);
        }
      }
    }
    for (final entry in latestByName.entries) {
      addPhone(entry.key, entry.value, savedAtByName[entry.key]);
    }
  }
  return {
    for (final entry in phones.entries)
      if (entry.value.length == 1) entry.key: entry.value.single,
  };
}

/// Explicit selection replaces existing phones when a saved match is available.
/// Without a match, preserve manual input and clear a previous automatic value.
class RepresentativePhoneAutofill {
  bool _manuallyEdited = false;
  void markManualEdit() => _manuallyEdited = true;
  void reset() => _manuallyEdited = false;
  String? valueForSelection({
    required String? suggestedPhone,
    required String? currentPhone,
  }) {
    if (suggestedPhone == null &&
        _manuallyEdited &&
        (currentPhone?.trim().isNotEmpty ?? false)) {
      return null;
    }
    _manuallyEdited = false;
    return suggestedPhone ?? '';
  }
}
