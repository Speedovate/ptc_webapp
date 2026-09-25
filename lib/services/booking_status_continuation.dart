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

const _bookingActionStages = {
  'pending',
  'assigned',
  'ongoing',
  'delivered',
  'check',
  'empty',
  'return',
  'cancelled',
  'confirm',
};

const _physicalBookingStages = {
  'ongoing',
  'delivered',
  'check',
  'empty',
  'return',
};

/// Chassis states that mean the asset is physically committed to a booking.
/// `ready` is a reservation, so it can be displaced by a reservation.
const _activeChassisStatuses = {'loaded', 'empty', 'return'};

const _bookingStageRanks = {
  'pending': 0,
  'assigned': 10,
  'ongoing': 20,
  'delivered': 30,
  'check': 40,
  'empty': 50,
  'return': 60,
  'cancelled': 70,
  'confirm': 80,
};

const _bookingWorkflowFields = {
  'id',
  'submission_key',
  'updated_at',
  'client_status',
  'driver_status',
  'helper_status',
  'delivered_at',
  'chassis_id',
  'status_outputs',
  'photo_cleanup_paths',
  'photo_cleanup_claims',
  'media_synced_at',
  'local_sync_status',
};

/// Returns true only when a newer server action proves that the queued action
/// is already represented in history. A timestamp alone is not enough: the
/// booking identity, event identity, workflow form, and all unrelated fields
/// must still agree.
bool isProvenSupersededBookingAction(
  Map<String, dynamic> server,
  Map<String, dynamic> pending, {
  required String? baseUpdatedAt,
}) {
  if (!_sameBookingIdentity(server, pending)) return false;
  final base = _bookingInstant(baseUpdatedAt);
  final remote = _bookingInstant(server['updated_at']);
  if (base == null || remote == null || !remote.isAfter(base)) return false;
  if (!_onlyBookingWorkflowFieldsDiffer(server, pending)) return false;

  final serverEvents = _bookingEvents(server);
  final pendingEvents = _bookingEvents(pending);
  if (serverEvents.isEmpty || pendingEvents.isEmpty) return false;
  if (!_serverStageCanSupersede(server['client_status'])) return false;

  for (final entry in pendingEvents.entries) {
    final serverEvent = serverEvents[entry.key];
    if (serverEvent != null && !_equal(serverEvent, entry.value)) {
      return false;
    }
  }

  final pendingOnly = pendingEvents.entries
      .where((entry) => !serverEvents.containsKey(entry.key))
      .toList(growable: false);
  if (pendingOnly.isEmpty) {
    // The local history is byte-for-byte present on the server. Cleanup
    // metadata may legitimately differ because it is server-managed.
    return true;
  }

  final pendingTimes = <DateTime>[];
  for (final entry in pendingOnly) {
    final event = entry.value;
    if (!_isForwardWorkflowEvent(event)) return false;
    final time = _bookingInstant(event['submitted_at']);
    if (time == null) return false;
    pendingTimes.add(time);
  }
  final latestPending = pendingTimes.reduce(
    (latest, value) => value.isAfter(latest) ? value : latest,
  );
  final hasLaterServerEvent = serverEvents.values.any((event) {
    if (!_isForwardWorkflowEvent(event)) return false;
    final time = _bookingInstant(event['submitted_at']);
    return time != null && time.isAfter(latestPending);
  });
  return hasLaterServerEvent;
}

/// Proves that an old booking action cannot reclaim a chassis that is already
/// owned by a later physical booking. This never authorizes a write; callers
/// use it only to retire the stale action and preserve the active owner.
bool isProvenSupersededChassisAction({
  required Map<String, dynamic> pending,
  required Map<String, dynamic> serverBooking,
  required Map<String, dynamic> chassis,
  required Map<String, dynamic> ownerBooking,
  required String? baseUpdatedAt,
}) {
  if (!_sameBookingIdentity(serverBooking, pending)) return false;
  final pendingStage = _physicalStage(pending['client_status']);
  final ownerStage = _physicalStage(ownerBooking['client_status']);
  final chassisStatus = _normalizedText(chassis['current_status']);
  final ownerChassis = _normalizedText(ownerBooking['chassis_id']);
  final chassisId = _normalizedText(chassis['id']);
  final pendingChassis = _normalizedText(pending['chassis_id']);
  final serverChassis = _normalizedText(serverBooking['chassis_id']);
  final ownerId = _normalizedText(chassis['current_booking_id']);
  final bookingId = _normalizedText(serverBooking['id']);
  if (pendingStage == null ||
      ownerStage == null ||
      !_activeChassisStatuses.contains(chassisStatus) ||
      ownerId == null ||
      ownerId == bookingId ||
      ownerChassis == null ||
      chassisId == null ||
      ownerChassis != chassisId ||
      pendingChassis != chassisId ||
      (serverChassis != null && serverChassis != pendingChassis) ||
      !_onlyBookingWorkflowFieldsDiffer(serverBooking, pending)) {
    return false;
  }

  final pendingEvents = _bookingEvents(pending);
  final ownerEvents = _bookingEvents(ownerBooking);
  final pendingEventTimes = pendingEvents.values
      .map(_bookingEventTime)
      .whereType<DateTime>()
      .toList(growable: false);
  final ownerEventTimes = ownerEvents.values
      .map(_bookingEventTime)
      .whereType<DateTime>()
      .toList(growable: false);
  if (pendingEventTimes.isEmpty || ownerEventTimes.isEmpty) return false;
  final pendingTime = _latestInstant([
    _bookingInstant(pending['updated_at']),
    ...pendingEventTimes,
  ]);
  final ownerTime = _latestInstant([
    _bookingInstant(ownerBooking['updated_at']),
    ...ownerEventTimes,
  ]);
  final base = _bookingInstant(baseUpdatedAt);
  if (pendingTime == null ||
      ownerTime == null ||
      base == null ||
      !ownerTime.isAfter(base)) {
    return false;
  }

  // Physical progression is required: the owner must be further along in the
  // physical workflow, or it must have progressed after the stale action.
  final pendingRank = _bookingStageRanks[pendingStage]!;
  final ownerRank = _bookingStageRanks[ownerStage]!;
  return ownerRank > pendingRank || ownerTime.isAfter(pendingTime);
}

bool _sameBookingIdentity(
  Map<String, dynamic> server,
  Map<String, dynamic> pending,
) {
  final identity = _normalizedText(server['submission_key']);
  final bookingId = _normalizedText(server['id']);
  return identity != null &&
      bookingId != null &&
      identity == _normalizedText(pending['submission_key']) &&
      bookingId == _normalizedText(pending['id']);
}

bool _onlyBookingWorkflowFieldsDiffer(
  Map<String, dynamic> server,
  Map<String, dynamic> pending,
) {
  for (final key in {...server.keys, ...pending.keys}) {
    if (_bookingWorkflowFields.contains(key)) continue;
    if (!_sameNullableValue(server[key], pending[key])) return false;
  }
  return true;
}

Map<String, Map<String, dynamic>> _bookingEvents(
  Map<String, dynamic> document,
) {
  final outputs = document['status_outputs'];
  if (outputs is! Map) return const {};
  final events = <String, Map<String, dynamic>>{};
  for (final entry in outputs.entries) {
    final key = _normalizedText(entry.key);
    final value = entry.value;
    if (key == null || value is! Map) continue;
    events[key] = Map<String, dynamic>.from(value);
  }
  return events;
}

bool _isForwardWorkflowEvent(Map<String, dynamic> event) {
  final form = event['status_form'];
  final fields = event['fields'];
  final status = _normalizedText(event['status_key']);
  final from = _normalizedText(form is Map ? form['current_status_key'] : null);
  final to = _normalizedText(form is Map ? form['next_status_key'] : null);
  final fromRank = from == null ? null : _bookingStageRanks[from];
  final toRank = to == null ? null : _bookingStageRanks[to];
  return status != null &&
      _bookingActionStages.contains(status) &&
      form is Map &&
      fields is Map &&
      form['is_main_form'] == true &&
      _normalizedText(event['submitted_by']) != null &&
      fromRank != null &&
      toRank != null &&
      toRank > fromRank &&
      _bookingInstant(event['submitted_at']) != null;
}

bool _serverStageCanSupersede(Object? value) {
  final stage = _normalizedText(value);
  return stage != null &&
      _bookingActionStages.contains(stage) &&
      stage != 'pending' &&
      stage != 'assigned';
}

String? _physicalStage(Object? value) {
  final stage = _normalizedText(value)?.toLowerCase();
  return stage != null && _physicalBookingStages.contains(stage) ? stage : null;
}

DateTime? _bookingEventTime(Map<String, dynamic> event) =>
    _isForwardWorkflowEvent(event)
    ? _bookingInstant(event['submitted_at'])
    : null;

DateTime? _latestInstant(Iterable<DateTime?> values) {
  DateTime? latest;
  for (final value in values) {
    if (value != null && (latest == null || value.isAfter(latest))) {
      latest = value;
    }
  }
  return latest;
}

DateTime? parseBookingSyncTimestamp(Object? value) => _bookingInstant(value);

DateTime? _bookingInstant(Object? value) {
  final text = _normalizedText(value);
  if (text == null) return null;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  final hasOffset =
      text.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(text);
  if (hasOffset) return parsed.toUtc();
  // Legacy Firestore action timestamps are Philippine wall-clock values.
  return DateTime.utc(
    parsed.year,
    parsed.month,
    parsed.day,
    parsed.hour,
    parsed.minute,
    parsed.second,
    parsed.millisecond,
    parsed.microsecond,
  ).subtract(const Duration(hours: 8));
}

String? _normalizedText(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

bool _sameNullableValue(Object? first, Object? second) {
  if (first == null || second == null) return first == null && second == null;
  return _equal(first, second);
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
  final archived = _reconcileSupersededAssignment(
    server,
    pending,
    normalized,
    baseUpdatedAt!,
    verifiedMake,
  );
  if (archived != null) return archived;
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

/// Retain a missed assignment as history only when the same actor subsequently
/// assigned the same crew/chassis, changing at most pickup/drop-off schedule.
Map<String, dynamic>? _reconcileSupersededAssignment(
  Map<String, dynamic> server,
  Map<String, dynamic> pending,
  Map<String, dynamic> normalized,
  String baseUpdatedAt,
  Map<String, dynamic>? verifiedMake,
) {
  final history = server['status_outputs'] as Map;
  final added = normalized.keys
      .where((key) => !history.containsKey(key))
      .toList();
  if (added.isEmpty) {
    final assignments = normalized.entries
        .where(
          (entry) =>
              entry.value is Map &&
              (entry.value as Map)['status_form'] is Map &&
              ((entry.value as Map)['status_form']
                      as Map)['current_status_key'] ==
                  'pending' &&
              ((entry.value as Map)['status_form'] as Map)['next_status_key'] ==
                  'assigned',
        )
        .toList();
    if (assignments.length != 1) return null;
    final withoutArchived = {
      ...server,
      'status_outputs': Map<String, dynamic>.from(history)
        ..remove(assignments.single.key),
    };
    final replay = reconcileBookingHistory(
      withoutArchived,
      pending,
      baseUpdatedAt: baseUpdatedAt,
      verifiedMake: verifiedMake,
    );
    return _equal(replay, server) ? Map<String, dynamic>.from(server) : null;
  }
  if (added.length != 1) return null;
  final local = normalized[added.single];
  final remoteAssignments = history.entries
      .where(
        (entry) =>
            !normalized.containsKey(entry.key) &&
            entry.value is Map &&
            (entry.value as Map)['status_form'] != null,
      )
      .toList();
  if (local is! Map || remoteAssignments.length != 1) return null;
  final remote = remoteAssignments.single.value as Map;
  final form = local['status_form'];
  final localFields = local['fields'];
  final remoteFields = remote['fields'];
  if (form is! Map ||
      localFields is! Map ||
      remoteFields is! Map ||
      form['current_status_key'] != 'pending' ||
      form['next_status_key'] != 'assigned' ||
      form['is_main_form'] != true ||
      !_equal(form, remote['status_form']) ||
      local['status_key'] != 'pending' ||
      remote['status_key'] != 'pending' ||
      '${local['submitted_by'] ?? ''}'.isEmpty ||
      local['submitted_by'] != remote['submitted_by'] ||
      local['submitted_role'] != remote['submitted_role']) {
    return null;
  }
  final localTime = DateTime.tryParse('${local['submitted_at']}');
  final remoteTime = DateTime.tryParse('${remote['submitted_at']}');
  final serverTime = DateTime.tryParse('${server['updated_at']}');
  if (localTime == null ||
      remoteTime == null ||
      serverTime == null ||
      !remoteTime.isAfter(localTime) ||
      remoteTime.isAfter(serverTime)) {
    return null;
  }
  const schedule = {
    'pick_up_date',
    'pick_up_time',
    'drop_off_date',
    'drop_off_time',
  };
  const crew = {'driver_id', 'helper_id', 'chassis_id'};
  for (final key in {...localFields.keys, ...remoteFields.keys}) {
    if (!schedule.contains(key) && !crew.contains(key)) return null;
    if (!schedule.contains(key) &&
        !_equal(localFields[key], remoteFields[key])) {
      return null;
    }
  }
  for (final key in crew) {
    if (pending[key] == null ||
        pending[key] != server[key] ||
        localFields[key] != pending[key] ||
        remoteFields[key] != server[key]) {
      return null;
    }
  }
  for (final key in ['client_status', 'driver_status', 'helper_status']) {
    if (pending[key] != 'assigned' || server[key] != 'assigned') return null;
  }
  final baseline = <String, dynamic>{
    ...server,
    'status_outputs': Map<String, dynamic>.from(history)
      ..remove(remoteAssignments.single.key),
    'updated_at': baseUpdatedAt,
    for (final key in crew) key: null,
    'vehicle_make_id': null,
    for (final key in ['client_status', 'driver_status', 'helper_status'])
      key: 'pending',
  };
  // Reuse the strict original-action and common-history/photo validation.
  final validated = reconcileBookingHistory(
    baseline,
    pending,
    baseUpdatedAt: baseUpdatedAt,
    verifiedMake: verifiedMake,
  );
  if (validated == null) return null;
  for (final key in {...validated.keys, ...server.keys}) {
    if (key == 'status_outputs' || key == 'updated_at') continue;
    if (!_equal(validated[key], server[key])) return null;
  }
  return {
    ...server,
    'status_outputs': {...history, added.single: local},
  };
}
