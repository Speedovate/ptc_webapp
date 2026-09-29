/// Preserve an older edit as history only; never replace current server data.
Map<String, dynamic>? archiveSupersededBookingEdit(
  Map<String, dynamic> server,
  Map<String, dynamic> pending,
) {
  bool equal(Object? a, Object? b) {
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every((key) => b.containsKey(key) && equal(a[key], b[key]));
    }
    if (a is List && b is List) {
      return a.length == b.length &&
          List.generate(a.length, (i) => i).every((i) => equal(a[i], b[i]));
    }
    return a == b;
  }

  final identity = server['submission_key'];
  if (identity is! String ||
      identity.isEmpty ||
      pending['submission_key'] != identity ||
      server['id'] != pending['id']) {
    return null;
  }
  final before = server['status_outputs'];
  final after = pending['status_outputs'];
  if (before is! Map || after is! Map) return null;
  for (final key in {...server.keys, ...pending.keys}) {
    if (const {
      'status_outputs',
      'updated_at',
      'media_synced_at',
      'photo_cleanup_paths',
      'photo_cleanup_claims',
      'local_sync_status',
    }.contains(key)) {
      continue;
    }
    if (!equal(server[key], pending[key])) return null;
  }
  // Require the same timestamp representation before comparing legacy wall times.
  DateTime? time(Object? value) => DateTime.tryParse('$value');
  final added = after.keys.where((key) => !before.containsKey(key)).toList();
  if (added.length > 1 || after.isEmpty) return null;
  final candidates = after.keys.toList()
    ..sort((a, b) {
      final left = after[a];
      final right = after[b];
      return '${right is Map ? right['submitted_at'] : ''}'.compareTo(
        '${left is Map ? left['submitted_at'] : ''}',
      );
    });
  final eventKey = added.isEmpty ? candidates.first : added.single;
  final event = after[eventKey];
  if (added.isEmpty && !equal(event, before[eventKey])) return null;
  if (event is! Map ||
      event['status_form'] != null ||
      '${event['submitted_by'] ?? ''}'.isEmpty) {
    return null;
  }
  final fields = event['fields'];
  final at = time(event['submitted_at']);
  final latest = time(server['updated_at']);
  if (fields is! Map ||
      fields.isEmpty ||
      at == null ||
      latest == null ||
      at.isUtc != latest.isUtc ||
      !latest.isAfter(at) ||
      fields.keys.any(
        (key) => !const {
          'amount',
          'waybill_photo',
          'delivery_form_photo',
          'waybill_number',
          'delivery_form_number',
        }.contains(key),
      )) {
    return null;
  }
  bool photoKey(Object? key) =>
      key == 'waybill_photo' || key == 'delivery_form_photo';
  Map nonPhotos(Map map) => {
    for (final e in map.entries)
      if (!photoKey(e.key)) e.key: e.value,
  };
  final newer = before.values.where((value) {
    if (value is! Map ||
        value['status_form'] != null ||
        value['fields'] is! Map) {
      return false;
    }
    final newerAt = time(value['submitted_at']);
    return newerAt != null &&
        newerAt.isUtc == at.isUtc &&
        newerAt.isAfter(at) &&
        !newerAt.isAfter(latest) &&
        equal(
          {...event}
            ..remove('fields')
            ..remove('submitted_at'),
          {...value}
            ..remove('fields')
            ..remove('submitted_at'),
        ) &&
        equal(nonPhotos(fields), nonPhotos(value['fields'] as Map));
  });
  if (newer.isEmpty) return null;
  for (final key in after.keys.where(before.containsKey)) {
    final local = after[key];
    final remote = before[key];
    if (equal(local, remote)) continue;
    if (local is! Map ||
        remote is! Map ||
        local['fields'] is! Map ||
        remote['fields'] is! Map) {
      return null;
    }
    if (!equal({...local}..remove('fields'), {...remote}..remove('fields'))) {
      return null;
    }
    final localFields = local['fields'] as Map;
    final remoteFields = remote['fields'] as Map;
    for (final field in {...localFields.keys, ...remoteFields.keys}) {
      if (equal(localFields[field], remoteFields[field])) continue;
      final oldPhoto = localFields[field];
      final archivedPhoto = fields[field];
      if (!photoKey(field) ||
          oldPhoto is! Map ||
          archivedPhoto is! Map ||
          remoteFields[field] is! Map) {
        return null;
      }
      Map content(Map value) => {...value}
        ..remove('pending_upload')
        ..remove('pending_upload_id');
      // The old inline photo survives unchanged in the archived edit. We do
      // not assert it is the same image as the uploaded server photo.
      if (!equal(content(oldPhoto), content(archivedPhoto)) ||
          !'${oldPhoto['download_url'] ?? ''}'.startsWith('data:image/')) {
        return null;
      }
    }
  }
  return {
    ...server,
    'status_outputs': {...before, eventKey: event},
  };
}
