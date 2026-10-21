/// SDK cache/pending-write snapshots are not complete server inventories.
/// Preserve durable records missing from those snapshots; a confirmed server
/// snapshot remains authoritative so deletions are still respected.
List<Map<String, dynamic>> mergeCachedSnapshotDocuments({
  required List<Map<String, dynamic>> remote,
  required List<Map<String, dynamic>> cached,
  required bool isFromCache,
  required bool hasPendingWrites,
}) {
  if (!isFromCache && !hasPendingWrites) {
    return remote;
  }
  return <String, Map<String, dynamic>>{
    for (final document in cached)
      if ((document['id']?.toString() ?? '').isNotEmpty)
        document['id'].toString(): document,
    for (final document in remote)
      if ((document['id']?.toString() ?? '').isNotEmpty)
        document['id'].toString(): document,
  }.values.toList(growable: false);
}

/// A server booking snapshot cannot contain a still-local temporary ID. Keep
/// its cached create payload until a matching submission key is confirmed on
/// the server; it may be the only remaining source for a dependent photo.
List<Map<String, dynamic>> mergeBookingSnapshotDocuments({
  required List<Map<String, dynamic>> remote,
  required List<Map<String, dynamic>> cached,
  required bool isFromCache,
  required bool hasPendingWrites,
}) {
  final merged = <Map<String, dynamic>>[
    ...mergeCachedSnapshotDocuments(
      remote: remote,
      cached: cached,
      isFromCache: isFromCache,
      hasPendingWrites: hasPendingWrites,
    ),
  ];
  if (isFromCache || hasPendingWrites) return merged;
  final committedKeys = remote
      .map((row) => row['submission_key']?.toString())
      .whereType<String>()
      .toSet();
  final seenIds = merged.map((row) => row['id']?.toString()).toSet();
  for (final row in cached) {
    final id = row['id']?.toString() ?? '';
    final key = row['submission_key']?.toString() ?? '';
    if (!id.startsWith('offline_booking_') ||
        row['local_sync_status'] != 'queued' ||
        key.isEmpty ||
        id != 'offline_$key' ||
        committedKeys.contains(key) ||
        seenIds.contains(id)) {
      continue;
    }
    merged.add(Map<String, dynamic>.from(row));
    seenIds.add(id);
  }
  return merged;
}
