import 'dart:convert';
import 'package:archive/archive.dart';

Future<String> encodeCacheMirror(String value) async =>
    'gzip:${base64Encode(GZipEncoder().encode(utf8.encode(value)))}';
Future<String?> decodeCacheMirror(String? value) async {
  if (value == null || !value.startsWith('gzip:')) return value;
  try {
    return utf8.decode(
      GZipDecoder().decodeBytes(base64Decode(value.substring(5))),
    );
  } catch (_) {
    return null;
  }
}
