import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/requests/firestore_cache_persistence.dart';
import 'package:webapp/requests/firestore_cache_store.dart';

class _PausedPersistence extends Fake implements FirestoreCachePersistence {
  final started = Completer<void>();
  final release = Completer<void>();
  final values = <String, String>{};
  @override
  bool get isAvailable => true;
  @override
  Future<String?> read(String key) async {
    final old = values[key];
    if (!started.isCompleted) {
      started.complete();
    }
    await release.future;
    return old;
  }

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  Future<void> removeWhere(bool Function(String) predicate) async {
    values.removeWhere((key, _) => predicate(key));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final version in [false, true]) {
    for (final operation in ['write', 'clear', 'clearAll']) {
      test(
        'late ${version ? 'version' : 'documents'} read cannot undo $operation',
        () async {
          final persistence = _PausedPersistence();
          final key = version
              ? 'firestore_cache_version_test'
              : 'firestore_cache_data_test';
          persistence.values[key] = version ? 'old' : '[{"id":"old"}]';
          final store = FirestoreCacheStore(persistence: persistence);
          final read = version
              ? store.readVersion('test')
              : store.readDocumentMaps('test');
          await persistence.started.future;
          if (operation == 'write') {
            if (version) {
              await store.writeVersion('test', 'new');
            } else {
              await store.writeDocumentMaps('test', [
                {'id': 'new'},
              ]);
            }
          } else if (operation == 'clear') {
            await store.clearResource('test');
          } else {
            await store.clearAll();
          }
          persistence.release.complete();
          final result = await read;
          if (operation == 'write') {
            expect(
              result,
              version
                  ? 'new'
                  : [
                      {'id': 'new'},
                    ],
            );
            expect(persistence.values[key], contains('new'));
          } else {
            expect(result, isNull);
            expect(persistence.values[key], isNull);
          }
        },
      );
    }
  }
}
