/// Recover only a unique marker for the same upload and original photo metadata.
bool bookingPhotoAlreadyUploaded({
  required Object? photo,
  required String bookingId,
  required String statusKey,
  required String fieldKey,
  required String fileName,
  required int? size,
  required String? mimeType,
}) {
  if (photo is! Map || size == null || mimeType == null) return false;
  final path = photo['storage_path'];
  return photo['pending_upload'] != true &&
      photo['pending_upload_id'] == null &&
      photo['name'] == fileName &&
      photo['size'] == size &&
      photo['mime_type'] == mimeType &&
      path is String &&
      path.startsWith(
        'bookings/$bookingId/status_outputs/$statusKey/$fieldKey/',
      ) &&
      Uri.tryParse('${photo['download_url']}')?.scheme == 'https';
}

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
