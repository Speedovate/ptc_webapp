/// Copies a document without Map.from's dynamic forEach dispatch. The web
/// replay failure occurred at that dispatch, before any reference was resolved.
/// Preserve every field and value; do not JSON-round-trip Firestore values or
/// treat a failed conversion as an empty document.
Map<String, dynamic> copyDocumentFields(Map source) => {
  for (final key in source.keys) key as String: source[key],
};
