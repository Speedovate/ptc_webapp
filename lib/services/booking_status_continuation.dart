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
