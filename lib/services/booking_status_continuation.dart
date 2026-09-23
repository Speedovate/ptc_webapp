/// Recognizes only a single, fully evidenced forward action. Never merges or
/// chooses between edits to existing history or unrelated booking fields.
bool isSafeBookingStatusContinuation(
  Map<String, dynamic> server,
  Map<String, dynamic> pending, {
  Map<String, dynamic>? verifiedMake,
}) {
  final identity = server['submission_key'];
  if (identity is! String ||
      identity.isEmpty ||
      pending['submission_key'] != identity ||
      server['id'] != pending['id']) {
    return false;
  }
  final before = server['status_outputs'];
  final after = pending['status_outputs'];
  if (before is! Map || before.isEmpty || after is! Map) return false;
  if (before.keys.any(
    (key) => !after.containsKey(key) || !_equal(before[key], after[key]),
  )) {
    return false;
  }
  final added = after.keys.where((key) => !before.containsKey(key)).toList();
  if (added.length != 1) return false;
  final action = after[added.single];
  if (action is! Map ||
      action['fields'] is! Map ||
      action['status_form'] is! Map) {
    return false;
  }
  final form = action['status_form'] as Map;
  final fields = action['fields'] as Map;
  final from = server['client_status'];
  final to = pending['client_status'];
  if (!((from == 'pending' && to == 'assigned') ||
      (from == 'assigned' && to == 'ongoing'))) {
    return false;
  }
  if (action['status_key'] != from ||
      form['current_status_key'] != from ||
      form['next_status_key'] != to ||
      form['is_main_form'] != true) {
    return false;
  }
  final time = DateTime.tryParse('${action['submitted_at']}');
  final remoteTime = DateTime.tryParse('${server['updated_at']}');
  final pendingTime = DateTime.tryParse('${pending['updated_at']}');
  if (time == null ||
      remoteTime == null ||
      pendingTime == null ||
      !time.isAfter(remoteTime) ||
      time != pendingTime) {
    return false;
  }
  if ('${action['submitted_by'] ?? ''}'.isEmpty) return false;
  for (final key in ['client_status', 'driver_status', 'helper_status']) {
    if (server[key] != from || pending[key] != to) return false;
  }
  final allowed = {
    'status_outputs',
    'updated_at',
    'client_status',
    'driver_status',
    'helper_status',
  };
  if (from == 'pending') {
    for (final key in ['driver_id', 'helper_id', 'chassis_id']) {
      if (!_equal(server[key], pending[key])) {
        if (server[key] != null ||
            !fields.containsKey(key) ||
            !_equal(fields[key], pending[key])) {
          return false;
        }
        allowed.add(key);
      }
    }
    if (!_equal(server['vehicle_make_id'], pending['vehicle_make_id'])) {
      if (server['vehicle_make_id'] != null ||
          verifiedMake == null ||
          pending['vehicle_make_id'] == null ||
          verifiedMake['driver_id'] == null ||
          verifiedMake['helper_id'] == null ||
          verifiedMake['driver_id'] != pending['driver_id'] ||
          verifiedMake['helper_id'] != pending['helper_id']) {
        return false;
      }
      allowed.add('vehicle_make_id');
    }
  }
  for (final key in {...server.keys, ...pending.keys}) {
    if (!allowed.contains(key) &&
        (server.containsKey(key) != pending.containsKey(key) ||
            !_equal(server[key], pending[key]))) {
      return false;
    }
  }
  return true;
}

bool _equal(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((key) => b.containsKey(key) && _equal(a[key], b[key]));
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        List.generate(a.length, (i) => i).every((i) => _equal(a[i], b[i]));
  }
  return a == b;
}

/// Merge an independently recorded forward action with later amount/photo edits.
/// Existing event contents and unrelated booking fields are never overwritten.
Map<String, dynamic>? reconcileBookingHistory(
  Map<String, dynamic> server,
  Map<String, dynamic> pending, {
  required String? baseUpdatedAt,
  Map<String, dynamic>? verifiedMake,
}) {
  final base = DateTime.tryParse(baseUpdatedAt ?? '');
  final identity = server['submission_key'];
  if (base == null ||
      identity is! String ||
      identity.isEmpty ||
      pending['submission_key'] != identity ||
      server['id'] != pending['id']) {
    return null;
  }
  final before = server['status_outputs'];
  final after = pending['status_outputs'];
  if (before is! Map || after is! Map || before.isEmpty || after.isEmpty) {
    return null;
  }
  final normalized = <String, dynamic>{};
  for (final key in after.keys) {
    final local = after[key];
    if (!before.containsKey(key)) {
      normalized['$key'] = local;
      continue;
    }
    final remote = before[key];
    if (_equal(local, remote)) {
      normalized['$key'] = remote;
      continue;
    }
    if (local is! Map || remote is! Map) return null;
    final localFields = local['fields'];
    final remoteFields = remote['fields'];
    if (localFields is! Map || remoteFields is! Map) return null;
    final fields = Map<String, dynamic>.from(localFields);
    for (final field in localFields.keys) {
      final photo = localFields[field];
      final uploaded = remoteFields[field];
      if (_equal(photo, uploaded)) continue;
      // Only transport state of the same original event can be substituted.
      // The separate photo-upload queue remains responsible for its own action.
      if (photo is! Map ||
          uploaded is! Map ||
          photo['pending_upload'] != true ||
          '${photo['pending_upload_id'] ?? ''}'.isEmpty ||
          uploaded['pending_upload'] == true ||
          !'${uploaded['storage_path'] ?? ''}'.startsWith(
            'bookings/${server['id']}/status_outputs/$key/$field/',
          ) ||
          !'${uploaded['download_url'] ?? ''}'.startsWith('https://') ||
          [
            'name',
            'size',
            'mime_type',
          ].any((k) => photo[k] == null || photo[k] != uploaded[k])) {
        return null;
      }
      fields['$field'] = uploaded;
    }
    if (!_equal({...local, 'fields': fields}, remote)) return null;
    normalized['$key'] = remote;
  }
  // Remote-only events must be non-workflow amount/photo edits, never reassignment.
  for (final key in before.keys.where((key) => !after.containsKey(key))) {
    final event = before[key];
    if (event is! Map ||
        event['status_form'] != null ||
        event['fields'] is! Map) {
      return null;
    }
    final fields = event['fields'] as Map;
    if (fields.isEmpty ||
        fields.keys.any(
          (key) => !const {
            'amount',
            'waybill_photo',
            'delivery_form_photo',
          }.contains(key),
        )) {
      return null;
    }
    final time = DateTime.tryParse('${event['submitted_at']}');
    if (time == null || time.isBefore(base)) return null;
  }
  final candidate = Map<String, dynamic>.from(pending);
  // These server-managed fields cannot be restored from an old offline snapshot.
  for (final key in [
    'media_synced_at',
    'photo_cleanup_paths',
    'photo_cleanup_claims',
  ]) {
    if (pending.containsKey(key) && !_equal(pending[key], server[key])) {
      return null;
    }
    if (server.containsKey(key)) candidate[key] = server[key];
  }
  if (pending['vehicle_make_id'] == null && server['vehicle_make_id'] != null) {
    if (verifiedMake == null ||
        verifiedMake['driver_id'] != pending['driver_id'] ||
        verifiedMake['helper_id'] != pending['helper_id'] ||
        pending['driver_id'] == null ||
        pending['helper_id'] == null) {
      return null;
    }
    candidate['vehicle_make_id'] = server['vehicle_make_id'];
  }
  final added = normalized.keys
      .where((key) => !before.containsKey(key))
      .toList();
  final combined = {...before, ...normalized};
  if (added.isEmpty) {
    // Assignment already committed: acknowledge only a proven identical action.
    for (final key in {...candidate.keys, ...server.keys}) {
      if (key == 'updated_at' || key == 'status_outputs') continue;
      if (!_equal(candidate[key], server[key])) return null;
    }
    return Map<String, dynamic>.from(server);
  }
  if (added.length != 1) return null;
  // Validate against the action's original base, preserving all remote edits.
  final baseline = {...server, 'updated_at': baseUpdatedAt};
  candidate['status_outputs'] = combined;
  if (!isSafeBookingStatusContinuation(
    baseline,
    candidate,
    verifiedMake: verifiedMake,
  )) {
    return null;
  }
  final remoteTime = DateTime.tryParse('${server['updated_at']}');
  final actionTime = DateTime.tryParse('${candidate['updated_at']}');
  if (remoteTime != null &&
      actionTime != null &&
      remoteTime.isAfter(actionTime)) {
    candidate['updated_at'] = server['updated_at'];
  }
  return candidate;
}
