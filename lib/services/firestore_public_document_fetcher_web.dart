// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'package:webapp/firebase_options.dart';

import 'firestore_public_document_fetcher.dart';

class _WebFirestorePublicDocumentFetcher
    implements FirestorePublicDocumentFetcher {
  static const Duration _publicReadTimeout = Duration(seconds: 30);
  static const Duration _publicMutationTimeout = Duration(seconds: 30);

  @override
  Future<List<Map<String, dynamic>>> fetchCollectionDocuments(
    String collectionPath, {
    int pageSize = 100,
  }) async {
    final options = DefaultFirebaseOptions.currentPlatform;
    final projectId = options.projectId;
    final apiKey = options.apiKey;
    final encodedCollectionPath = Uri.encodeComponent(
      collectionPath,
    ).replaceAll('%2F', '/');
    final uri = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/$encodedCollectionPath?pageSize=$pageSize&key=$apiKey',
    );
    _log('fetch start collection=$collectionPath mode=listDocuments url=$uri');
    try {
      final response = await _performLoggedRequest(
        label: 'collection:$collectionPath',
        url: uri.toString(),
        method: 'GET',
        requestHeaders: const {
          'Accept': 'application/json',
        },
        timeout: _publicReadTimeout,
      );
    _log(
      'fetch response collection=$collectionPath status=${response.status} readyState=${response.readyState} bodyLength=${response.responseText?.length ?? 0}',
    );
    if (response.status != 200) {
      _log('fetch non-200 collection=$collectionPath status=${response.status}');
      _log(
        'fetch non-200 body collection=$collectionPath body=${response.responseText ?? "-"}',
      );
      return const <Map<String, dynamic>>[];
    }
      final raw = response.responseText;
      if (raw == null || raw.isEmpty) {
        _log('fetch empty body collection=$collectionPath');
        return const <Map<String, dynamic>>[];
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _log(
          'fetch decoded non-map collection=$collectionPath type=${decoded.runtimeType}',
        );
        return const <Map<String, dynamic>>[];
      }
      final documentList = (decoded['documents'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((document) => Map<String, dynamic>.from(document))
          .toList(growable: false);
      final mapped = documentList
          .map(_fromFirestoreDocument)
          .where((document) => document.isNotEmpty)
          .toList(growable: false);
      _log('fetch mapped collection=$collectionPath docs=${mapped.length}');
      if (collectionPath == 'bookings') {
        _log('firestore bookings present=${mapped.isNotEmpty} count=${mapped.length}');
      }
      return mapped;
    } catch (error) {
      throw Exception(
        'public firestore fetch failed for $collectionPath url=$uri error=$error',
      );
    }
  }

  @override
  Future<Map<String, dynamic>?> fetchDocument(String documentPath) async {
    final options = DefaultFirebaseOptions.currentPlatform;
    final projectId = options.projectId;
    final apiKey = options.apiKey;
    final encodedDocumentPath = Uri.encodeComponent(
      documentPath,
    ).replaceAll('%2F', '/');
    final uri = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/$encodedDocumentPath?key=$apiKey',
    );
    _log('fetch document start path=$documentPath mode=getDocument url=$uri');
    try {
      final response = await _performLoggedRequest(
        label: 'document:$documentPath',
        url: uri.toString(),
        method: 'GET',
        requestHeaders: const {
          'Accept': 'application/json',
        },
        timeout: _publicReadTimeout,
      );
    _log(
      'fetch document response path=$documentPath status=${response.status} readyState=${response.readyState} bodyLength=${response.responseText?.length ?? 0}',
    );
    if (response.status == 404) {
      _log('fetch document missing path=$documentPath');
      return null;
    }
    if (response.status != 200) {
      _log(
        'fetch document non-200 body path=$documentPath body=${response.responseText ?? "-"}',
      );
      throw Exception(
        'public firestore document fetch non-200 for $documentPath (${response.status})',
      );
    }
      final raw = response.responseText;
      if (raw == null || raw.isEmpty) {
        _log('fetch document empty body path=$documentPath');
        return null;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _log(
          'fetch document decoded non-map path=$documentPath type=${decoded.runtimeType}',
        );
        return null;
      }
      final mapped = _fromFirestoreDocument(Map<String, dynamic>.from(decoded));
      _log(
        'fetch document mapped path=$documentPath exists=${mapped.isNotEmpty} keys=${mapped.keys.length}',
      );
      return mapped.isEmpty ? null : mapped;
    } catch (error) {
      throw Exception(
        'public firestore document fetch failed for $documentPath url=$uri error=$error',
      );
    }
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
    ).timeout(_publicMutationTimeout, onTimeout: () {
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
    ).timeout(_publicMutationTimeout, onTimeout: () {
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

  Future<html.HttpRequest> _performLoggedRequest({
    required String label,
    required String url,
    required String method,
    required Duration timeout,
    Map<String, String>? requestHeaders,
    dynamic sendData,
  }) async {
    final request = html.HttpRequest();
    final completer = Completer<html.HttpRequest>();
    var completed = false;

    void finishSuccess() {
      if (completed) {
        return;
      }
      completed = true;
      completer.complete(request);
    }

    void finishError(Object error) {
      if (completed) {
        return;
      }
      completed = true;
      completer.completeError(error);
    }

    void logEvent(String event, [html.ProgressEvent? progress]) {
      final loaded = progress?.loaded;
      final total = progress?.total;
      final lengthComputable = progress?.lengthComputable;
      _log(
        'xhr event label=$label event=$event readyState=${request.readyState} status=${request.status} loaded=${loaded ?? "-"} total=${total ?? "-"} lengthComputable=${lengthComputable ?? "-"} responseUrl=${request.responseUrl ?? "-"} bodyLength=${request.responseText?.length ?? 0}',
      );
    }

    request
      ..open(method, url, async: true)
      ..responseType = 'text';
    request.timeout = timeout.inMilliseconds;
    requestHeaders?.forEach(request.setRequestHeader);

    request.onLoadStart.listen((event) => logEvent('loadstart', event));
    request.onProgress.listen((event) => logEvent('progress', event));
    request.onAbort.listen((event) {
      logEvent('abort', event);
      finishError(
        Exception(
          'xhr abort label=$label readyState=${request.readyState} status=${request.status}',
        ),
      );
    });
    request.onError.listen((event) {
      logEvent('error', event);
      finishError(
        Exception(
          'xhr error label=$label readyState=${request.readyState} status=${request.status} responseUrl=${request.responseUrl ?? "-"}',
        ),
      );
    });
    request.onTimeout.listen((event) {
      logEvent('timeout', event);
      finishError(
        TimeoutException(
          'xhr timeout label=$label readyState=${request.readyState} status=${request.status}',
        ),
      );
    });
    request.onLoad.listen((event) {
      logEvent('load', event);
      finishSuccess();
    });
    request.onLoadEnd.listen((event) => logEvent('loadend', event));

    try {
      request.send(sendData);
    } catch (error) {
      finishError(error);
    }

    return completer.future.timeout(timeout + const Duration(seconds: 1));
  }
}

FirestorePublicDocumentFetcher createFirestorePublicDocumentFetcher() =>
    _WebFirestorePublicDocumentFetcher();

void _log(String message) {
  // Temporary diagnostics removed.
}
