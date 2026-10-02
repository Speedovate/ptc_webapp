import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

/// fake_cloud_firestore 4.1.1's transaction.set ignores SetOptions. Preserve
/// merge semantics and await buffered writes for these replay regression tests.
/// This fake does not model server concurrency or security rules.
class MergeAwareFirestore extends FakeFirebaseFirestore {
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    final transaction = _BufferedTransaction();
    final result = await transactionHandler(transaction);
    for (final write in transaction.writes) {
      await write();
    }
    return result;
  }
}

class _BufferedTransaction implements Transaction {
  final writes = <Future<void> Function()>[];
  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(DocumentReference<T> ref) {
    if (writes.isNotEmpty) throw StateError('Reads must precede writes');
    return ref.get();
  }

  @override
  Transaction set<T>(DocumentReference<T> ref, T data, [SetOptions? options]) {
    // Firestore serialization restores string-keyed maps. The fake retains
    // Map<dynamic, dynamic> from merges and then fails its own nested-update
    // cast when a later photo transaction patches a dotted field path.
    writes.add(() => ref.set(_stringKeyedMaps(data) as T, options));
    return this;
  }

  @override
  Transaction update(DocumentReference ref, Map<Object, Object?> data) {
    writes.add(
      () => ref.update(_stringKeyedMaps(data) as Map<Object, Object?>),
    );
    return this;
  }

  @override
  Transaction delete(DocumentReference ref) {
    writes.add(ref.delete);
    return this;
  }
}

Object? _stringKeyedMaps(Object? value) {
  if (value is Map && value.keys.every((key) => key is String)) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key as String: _stringKeyedMaps(entry.value),
    };
  }
  if (value is List) {
    return value.map(_stringKeyedMaps).toList();
  }
  return value;
}
