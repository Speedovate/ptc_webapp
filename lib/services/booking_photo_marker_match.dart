import 'dart:convert';

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
      (photo['name'] == fileName ||
          photo['name'] ==
              fileName.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')) &&
      photo['size'] == size &&
      photo['mime_type'] == mimeType &&
      path is String &&
      path.startsWith(
        'bookings/$bookingId/status_outputs/$statusKey/$fieldKey/',
      ) &&
      Uri.tryParse('${photo['download_url']}')?.scheme == 'https';
}

/// A repeated submission can move the same uploaded photo to another event.
/// Accept one matching Storage object, never guess between different uploads.
bool bookingPhotoAlreadyUploadedInHistory({
  required Map<String, dynamic> booking,
  required String bookingId,
  required String fieldKey,
  required String fileName,
  required int? size,
  required String? mimeType,
}) {
  final outputs = booking['status_outputs'];
  if (outputs is! Map) return false;
  final paths = <String>{};
  for (final section in outputs.entries) {
    final event = section.value;
    final fields = event is Map ? event['fields'] : null;
    final photo = fields is Map ? fields[fieldKey] : null;
    if (bookingPhotoAlreadyUploaded(
      photo: photo,
      bookingId: bookingId,
      statusKey: '${section.key}',
      fieldKey: fieldKey,
      fileName: fileName,
      size: size,
      mimeType: mimeType,
    )) {
      paths.add((photo as Map)['storage_path'] as String);
    }
  }
  return paths.length == 1;
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

/// Restaging the same image can create a new queue id while the server still
/// owns the original marker. Metadata alone cannot prove it is the same image.
bool bookingPendingPhotoMatchesBytes({
  required Object? photo,
  required String fileName,
  required int? size,
  required String? mimeType,
  required String bytesBase64,
}) {
  if (photo is! Map ||
      photo['pending_upload'] != true ||
      photo['pending_upload_id'] is! String ||
      (photo['pending_upload_id'] as String).isEmpty ||
      photo['name'] != fileName ||
      size == null ||
      photo['size'] != size ||
      mimeType == null ||
      photo['mime_type'] != mimeType) {
    return false;
  }
  try {
    final data = Uri.parse('${photo['download_url']}').data;
    if (data == null || !data.isBase64 || data.mimeType != mimeType) {
      return false;
    }
    final serverBytes = data.contentAsBytes();
    final queuedBytes = base64Decode(bytesBase64);
    return serverBytes.length == size &&
        queuedBytes.length == size &&
        base64Encode(serverBytes) == base64Encode(queuedBytes);
  } on FormatException {
    return false;
  }
}
