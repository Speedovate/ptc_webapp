// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'cache_mirror_codec_stub.dart' as fallback;

final _codec = _CodecWorker();
Future<String> encodeCacheMirror(String value) async {
  if (value.length < 32768) return fallback.encodeCacheMirror(value);
  try {
    return await _codec.run('encode', value);
  } catch (_) {
    return fallback.encodeCacheMirror(value);
  }
}

Future<String?> decodeCacheMirror(String? value) async {
  if (value == null || value.length < 256 || !value.startsWith('gzip:')) {
    return fallback.decodeCacheMirror(value);
  }
  try {
    return await _codec.run('decode', value);
  } catch (_) {
    return fallback.decodeCacheMirror(value);
  }
}

/// Compression/decompression happens outside Flutter's browser UI thread.
/// One reusable worker, disposed after idle; no ongoing polling.
class _CodecWorker {
  html.Worker? _worker;
  Timer? _idle;
  StreamSubscription<html.MessageEvent>? _messages;
  StreamSubscription<html.Event>? _errors;
  final _pending = <int, Completer<String>>{};
  int _sequence = 0;
  bool _unsupported = false;
  Future<String> run(String operation, String value) async {
    if (_unsupported) throw StateError('Native compression worker unavailable');
    _idle?.cancel();
    try {
      if (_worker == null) {
        final url = html.Url.createObjectUrlFromBlob(
          html.Blob([_script], 'text/javascript'),
        );
        try {
          _worker = html.Worker(url);
        } finally {
          html.Url.revokeObjectUrl(url);
        }
        _messages = _worker!.onMessage.listen((event) {
          final message = event.data as List;
          final pending = _pending.remove((message[0] as num).toInt());
          if (pending == null) return;
          if (message[1] == true) {
            pending.complete(message[2] as String);
          } else {
            pending.completeError(StateError('${message[2]}'));
          }
        });
        _errors = _worker!.onError.listen(
          (_) => _stop(StateError('Cache worker failed')),
        );
      }
      final id = ++_sequence;
      final result = Completer<String>();
      _pending[id] = result;
      _worker!.postMessage([id, operation, value]);
      try {
        return await result.future.timeout(const Duration(seconds: 30));
      } finally {
        _pending.remove(id);
      }
    } catch (error) {
      _unsupported =
          _worker == null ||
          '$error'.contains('CompressionStream') ||
          '$error'.contains('DecompressionStream') ||
          '$error'.contains('SecurityError');
      _stop(StateError('Cache worker unavailable'));
      rethrow;
    } finally {
      if (_pending.isEmpty) {
        _idle = Timer(const Duration(seconds: 30), _stop);
      }
    }
  }

  void _stop([Object? error]) {
    _worker?.terminate();
    _worker = null;
    _messages?.cancel();
    _errors?.cancel();
    for (final pending in _pending.values) {
      pending.completeError(error ?? StateError('Cache worker stopped'));
    }
    _pending.clear();
  }

  static const _script = r'''
self.onmessage = async (event) => {
  const [id, op, text] = event.data;
  try {
    if (op === 'encode') {
      const stream = new Blob([text]).stream().pipeThrough(new CompressionStream('gzip'));
      const bytes = new Uint8Array(await new Response(stream).arrayBuffer());
      const chunks = [];
      for (let i=0; i<bytes.length; i+=8192) chunks.push(String.fromCharCode(...bytes.subarray(i,i+8192)));
      self.postMessage([id, true, 'gzip:' + btoa(chunks.join(''))]);
    } else {
      const binary = atob(text.slice(5));
      const bytes = Uint8Array.from(binary, ch => ch.charCodeAt(0));
      const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('gzip'));
      self.postMessage([id, true, await new Response(stream).text()]);
    }
  } catch (error) { self.postMessage([id, false, String(error)]); }
};
''';
}
