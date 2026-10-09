/// Inline previews stay in the local booking/photo queue. Firestore receives
/// only the small upload marker until Storage supplies an HTTPS URL.
Map<String, dynamic> bookingRemoteDocument(Map<String, dynamic> document) {
  Object? clean(Object? value) {
    if (value is List) return value.map(clean).toList();
    if (value is! Map) return value;
    return <String, dynamic>{
      for (final entry in value.entries)
        if (!(entry.key == 'download_url' &&
            entry.value is String &&
            (entry.value as String).startsWith('data:') &&
            value['pending_upload'] == true &&
            '${value['pending_upload_id'] ?? ''}'.isNotEmpty))
          '${entry.key}': clean(entry.value),
    };
  }

  return clean(document) as Map<String, dynamic>;
}
