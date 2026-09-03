class FirestoreCachePersistence {
  const FirestoreCachePersistence();

  bool get isAvailable => false;

  Future<String?> read(String key) async => null;

  Future<void> write(String key, String value) async {}

  Future<void> remove(String key) async {}

  Future<void> removeWhere(bool Function(String key) predicate) async {}
}

FirestoreCachePersistence createFirestoreCachePersistence() =>
    const FirestoreCachePersistence();
