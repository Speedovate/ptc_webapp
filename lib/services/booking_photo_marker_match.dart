/// Recover only a unique marker for the same upload and original photo metadata.
String? matchingBookingPhotoStatus({
  required Map<String, dynamic> booking,
  required String uploadId,
  required String fieldKey,
  required String fileName,
  required int? size,
  required String? mimeType,
}) {
  final outputs = booking['status_outputs'];
  if (outputs is! Map) {
    return null;
  }
  final matches = <String>[];
  for (final section in outputs.entries) {
    final value = section.value;
    final fields = value is Map ? value['fields'] : null;
    final photo = fields is Map ? fields[fieldKey] : null;
    if (photo is Map && photo['pending_upload_id'] == uploadId) {
      // Even a duplicate with inconsistent metadata makes recovery ambiguous.
      if (photo['pending_upload'] != true ||
          photo['name'] != fileName ||
          photo['size'] != size ||
          photo['mime_type'] != mimeType) {
        return null;
      }
      matches.add('${section.key}');
    }
  }
  return matches.length == 1 ? matches.single : null;
}
