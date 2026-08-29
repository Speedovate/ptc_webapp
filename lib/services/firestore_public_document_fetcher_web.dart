// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'package:webapp/firebase_options.dart';

import 'firestore_public_document_fetcher.dart';

class _WebFirestorePublicDocumentFetcher
    implements FirestorePublicDocumentFetcher {
  @override
  Future<List<Map<String, dynamic>>> fetchCollectionDocuments(
    String collectionPath, {
    int pageSize = 100,
  }) async {
    final options = DefaultFirebaseOptions.currentPlatform;
    final projectId = options.projectId;
    final apiKey = options.apiKey;
    final encodedCollection = Uri.encodeComponent(collectionPath)
        .replaceAll('%2F', '/');
    final uri = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/$encodedCollection?pageSize=$pageSize&key=$apiKey',
    );
    final response = await html.HttpRequest.request(
      uri.toString(),
      method: 'GET',
      requestHeaders: const {
        'Accept': 'application/json',
      },
    ).timeout(const Duration(seconds: 4), onTimeout: () {
      throw TimeoutException(
        'public firestore fetch timeout for $collectionPath',
      );
    });
    if (response.status != 200) {
      return const <Map<String, dynamic>>[];
    }
    final raw = response.responseText;
    if (raw == null || raw.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return const <Map<String, dynamic>>[];
    }
    final documents = decoded['documents'];
    if (documents is! List) {
      return const <Map<String, dynamic>>[];
    }
    final mapped = documents
        .whereType<Map>()
        .map((document) => _fromFirestoreDocument(Map<String, dynamic>.from(document)))
        .where((document) => document.isNotEmpty)
        .toList(growable: false);
    return mapped;
  }

  @override
  Future<bool> deleteDocument(String documentPath) async {
    final options = DefaultFirebaseOptions.currentPlatform;
    final projectId = options.projectId;
    final apiKey = options.apiKey;
    final encodedDocument = Uri.encodeComponent(documentPath).replaceAll(
      '%2F',
      '/',
    );
    final uri = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/$encodedDocument?key=$apiKey',
    );
    final response = await html.HttpRequest.request(
      uri.toString(),
      method: 'DELETE',
      requestHeaders: const {
        'Accept': 'application/json',
      },
    ).timeout(const Duration(seconds: 8), onTimeout: () {
      throw TimeoutException('public firestore delete timeout for $documentPath');
    });
    if (response.status == 200 || response.status == 204) {
      return true;
    }
    throw Exception(
      'public firestore delete failed for $documentPath (${response.status}): ${response.responseText ?? ""}',
    );
  }

  @override
  Future<bool> patchDocument(
    String documentPath, {
    required Map<String, dynamic> fields,
    List<String>? updateMaskFieldPaths,
  }) async {
    final options = DefaultFirebaseOptions.currentPlatform;
    final projectId = options.projectId;
    final apiKey = options.apiKey;
    final encodedDocument = Uri.encodeComponent(documentPath).replaceAll(
      '%2F',
      '/',
    );
    final query = <String>['key=$apiKey'];
    for (final fieldPath in updateMaskFieldPaths ?? const <String>[]) {
      query.add('updateMask.fieldPaths=${Uri.encodeQueryComponent(fieldPath)}');
    }
    final uri = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/$encodedDocument?${query.join('&')}',
    );
    final response = await html.HttpRequest.request(
      uri.toString(),
      method: 'PATCH',
      requestHeaders: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      sendData: jsonEncode({
        'fields': _encodeFirestoreFields(fields),
      }),
    ).timeout(const Duration(seconds: 8), onTimeout: () {
      throw TimeoutException('public firestore patch timeout for $documentPath');
    });
    if (response.status == 200) {
      return true;
    }
    throw Exception(
      'public firestore patch failed for $documentPath (${response.status}): ${response.responseText ?? ""}',
    );
  }

  Map<String, dynamic> _fromFirestoreDocument(Map<String, dynamic> document) {
    final name = document['name']?.toString() ?? '';
    final fields = document['fields'];
    if (fields is! Map) {
      return const <String, dynamic>{};
    }
    final result = <String, dynamic>{
      'id': name.isEmpty ? null : name.split('/').last,
    };
    for (final entry in fields.entries) {
      result[entry.key.toString()] = _decodeFirestoreValue(entry.value);
    }
    return result;
  }

  dynamic _decodeFirestoreValue(dynamic value) {
    if (value is! Map) {
      return value;
    }
    if (value.containsKey('stringValue')) {
      return value['stringValue']?.toString();
    }
    if (value.containsKey('booleanValue')) {
      return value['booleanValue'] == true;
    }
    if (value.containsKey('integerValue')) {
      return int.tryParse(value['integerValue']?.toString() ?? '');
    }
    if (value.containsKey('doubleValue')) {
      final raw = value['doubleValue'];
      if (raw is num) {
        return raw.toDouble();
      }
      return double.tryParse(raw?.toString() ?? '');
    }
    if (value.containsKey('nullValue')) {
      return null;
    }
    if (value.containsKey('timestampValue')) {
      return value['timestampValue']?.toString();
    }
    if (value.containsKey('mapValue')) {
      final fields = value['mapValue']?['fields'];
      if (fields is! Map) {
        return <String, dynamic>{};
      }
      final result = <String, dynamic>{};
      for (final entry in fields.entries) {
        result[entry.key.toString()] = _decodeFirestoreValue(entry.value);
      }
      return result;
    }
    if (value.containsKey('arrayValue')) {
      final values = value['arrayValue']?['values'];
      if (values is! List) {
        return const <dynamic>[];
      }
      return values.map(_decodeFirestoreValue).toList(growable: false);
    }
    return value;
  }

  Map<String, dynamic> _encodeFirestoreFields(Map<String, dynamic> fields) {
    final encoded = <String, dynamic>{};
    fields.forEach((key, value) {
      encoded[key] = _encodeFirestoreValue(value);
    });
    return encoded;
  }

  Map<String, dynamic> _encodeFirestoreValue(dynamic value) {
    if (value == null) {
      return const {'nullValue': null};
    }
    if (value is String) {
      return {'stringValue': value};
    }
    if (value is bool) {
      return {'booleanValue': value};
    }
    if (value is int) {
      return {'integerValue': value.toString()};
    }
    if (value is double) {
      return {'doubleValue': value};
    }
    if (value is num) {
      return {'doubleValue': value.toDouble()};
    }
    if (value is DateTime) {
      return {'timestampValue': value.toUtc().toIso8601String()};
    }
    if (value is Map) {
      final nestedFields = <String, dynamic>{};
      value.forEach((key, nestedValue) {
        nestedFields[key.toString()] = _encodeFirestoreValue(nestedValue);
      });
      return {
        'mapValue': {'fields': nestedFields},
      };
    }
    if (value is List) {
      return {
        'arrayValue': {
          'values': value.map(_encodeFirestoreValue).toList(growable: false),
        },
      };
    }
    return {'stringValue': value.toString()};
  }
}

FirestorePublicDocumentFetcher createFirestorePublicDocumentFetcher() =>
    _WebFirestorePublicDocumentFetcher();
