// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:typed_data';

import 'persistent_image_fetcher.dart';

Future<PersistentFetchedImage?> fetchPersistentImage(String url) async {
  final request = await html.HttpRequest.request(
    url,
    method: 'GET',
    responseType: 'arraybuffer',
  );
  final response = request.response;
  if (response is! ByteBuffer) {
    return null;
  }
  final mimeType = request.getResponseHeader('content-type') ?? 'image/jpeg';
  return PersistentFetchedImage(
    bytes: Uint8List.view(response),
    mimeType: mimeType,
  );
}
