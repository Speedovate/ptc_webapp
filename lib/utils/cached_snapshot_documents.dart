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
