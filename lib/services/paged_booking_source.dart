import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:webapp/services/network_status_events.dart';

class BookingDataMetadata {
  const BookingDataMetadata(this.isFromCache, this.hasPendingWrites);
  final bool isFromCache, hasPendingWrites;
}

/// Always a complete set. Partial page results never replace the durable cache.
class BookingDataSnapshot {
  BookingDataSnapshot(this.docs, this.metadata);
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final BookingDataMetadata metadata;
}

/// Stable document-ID ranges preserve legacy documents without created_at.
/// Each server read/listener is bounded. All ranges are retained because global
/// search, export and offline reconciliation require a complete collection.
class PagedBookingSource {
  PagedBookingSource(
    this.collection, {
    this.pageSize = 150,
    bool Function()? online,
  }) : online = online ?? currentNetworkStatus;
  final CollectionReference<Map<String, dynamic>> collection;
  final int pageSize;
  final bool Function() online;
  final _readRecovery = <void Function()>{};

  Query<Map<String, dynamic>> _query(String? after) {
    final query = collection.orderBy(FieldPath.documentId);
    return after == null
        ? query
        : query.where(FieldPath.documentId, isGreaterThan: after);
  }

  Future<List<_Page>> _pages(
    GetOptions options, {
    bool Function()? cancelled,
  }) async {
    final pages = <_Page>[];
    String? after;
    while (true) {
      if (cancelled?.call() ?? false) return [];
      final snapshot = await _query(
        after,
      ).limit(pageSize).get(options).timeout(const Duration(seconds: 30));
      final end = snapshot.docs.length < pageSize
          ? null
          : snapshot.docs.last.id;
      pages.add(_Page(after, end, snapshot));
      if (end == null) break;
      after = end;
      await Future<void>.delayed(Duration.zero);
    }
    return pages;
  }

  BookingDataSnapshot _combine(List<_Page> pages) => BookingDataSnapshot(
    [for (final page in pages) ...page.snapshot.docs],
    BookingDataMetadata(
      pages.any((p) => p.snapshot.metadata.isFromCache),
      pages.any((p) => p.snapshot.metadata.hasPendingWrites),
    ),
  );

  Future<BookingDataSnapshot> read(GetOptions options) async {
    final result = _combine(await _pages(options));
    for (final recover in _readRecovery.toList()) {
      recover();
    }
    return result;
  }

  Stream<BookingDataSnapshot> watch() {
    late StreamController<BookingDataSnapshot> controller;
    var disposed = false;
    var generation = 0;
    var running = false;
    var restart = false;
    Timer? emitTimer;
    Timer? rebuildTimer;
    Timer? recoveryTimer;
    var failures = 0;
    var needsRecovery = false;
    List<_Page> pages = [];
    final subscriptions =
        <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
    StreamSubscription<bool>? network;

    void emit() {
      emitTimer ??= Timer(const Duration(milliseconds: 8), () {
        emitTimer = null;
        if (!disposed && !running && pages.isNotEmpty) {
          controller.add(_combine(pages));
        }
      });
    }

    late Future<void> Function() rebuild;
    void requestRebuild() {
      if (disposed) return;
      if (running) {
        restart = true;
        return;
      }
      rebuildTimer ??= Timer(const Duration(milliseconds: 50), () {
        rebuildTimer = null;
        unawaited(rebuild());
      });
    }

    void onReadRecovery() {
      if (needsRecovery) requestRebuild();
    }

    void recover(Object error) {
      needsRecovery = true;
      // Permission/configuration errors need a real state change, not polling.
      if (error is FirebaseException &&
          !const {
            'unavailable',
            'deadline-exceeded',
            'aborted',
            'internal',
            'resource-exhausted',
          }.contains(error.code)) {
        return;
      }
      if (disposed || !online() || recoveryTimer != null) return;
      // One backoff timer per watch, capped at one attempt per minute.
      final seconds = 1 << failures.clamp(0, 6);
      failures++;
      recoveryTimer = Timer(Duration(seconds: seconds > 60 ? 60 : seconds), () {
        recoveryTimer = null;
        if (online()) requestRebuild();
      });
    }

    rebuild = () async {
      if (disposed || running) return;
      running = true;
      try {
        final next = await _pages(
          GetOptions(source: online() ? Source.server : Source.cache),
          cancelled: () => disposed,
        );
        if (disposed) return;
        final epoch = ++generation;
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
        subscriptions.clear();
        if (disposed || epoch != generation) return;
        pages = next;
        needsRecovery = false;
        recoveryTimer?.cancel();
        recoveryTimer = null;
        for (final page in pages) {
          var query = _query(page.after);
          if (page.end != null) {
            query = query.where(
              FieldPath.documentId,
              isLessThanOrEqualTo: page.end,
            );
          }
          subscriptions.add(
            query
                .limit(pageSize + 1)
                .snapshots(includeMetadataChanges: true)
                .listen(
                  (snapshot) {
                    if (disposed || epoch != generation) return;
                    if (online() &&
                        (snapshot.metadata.isFromCache ||
                            snapshot.metadata.hasPendingWrites)) {
                      return;
                    }
                    if (snapshot.docs.length > pageSize) {
                      requestRebuild();
                      return;
                    }
                    // Reset backoff only once a listener actually delivers.
                    failures = 0;
                    if (page.update(snapshot)) emit();
                  },
                  onError: (Object error, StackTrace stack) {
                    if (!disposed && epoch == generation) {
                      controller.addError(error, stack);
                      recover(error);
                    }
                  },
                ),
          );
        }
      } catch (error, stack) {
        if (!disposed) {
          controller.addError(error, stack);
          recover(error);
        }
      } finally {
        running = false;
        if (!disposed) {
          emit();
          if (restart) {
            restart = false;
            requestRebuild();
          }
        }
      }
    };
    controller = StreamController<BookingDataSnapshot>(
      onListen: () {
        _readRecovery.add(onReadRecovery);
        network = networkStatusEvents().listen((connected) {
          if (connected) requestRebuild();
        });
        unawaited(rebuild());
      },
      onCancel: () async {
        disposed = true;
        generation++;
        emitTimer?.cancel();
        rebuildTimer?.cancel();
        recoveryTimer?.cancel();
        _readRecovery.remove(onReadRecovery);
        await network?.cancel();
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );
    return controller.stream;
  }
}

class _Page {
  _Page(this.after, this.end, this.snapshot);
  final String? after, end;
  QuerySnapshot<Map<String, dynamic>> snapshot;

  bool update(QuerySnapshot<Map<String, dynamic>> next) {
    final before = snapshot.docs;
    final after = next.docs;
    final changed =
        snapshot.metadata.isFromCache != next.metadata.isFromCache ||
        snapshot.metadata.hasPendingWrites != next.metadata.hasPendingWrites ||
        before.length != after.length ||
        List.generate(before.length, (i) => i).any(
          (i) =>
              before[i].id != after[i].id ||
              !_equal(before[i].data(), after[i].data()),
        );
    snapshot = next;
    return changed;
  }

  static bool _equal(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every((key) => b.containsKey(key) && _equal(a[key], b[key]));
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_equal(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }
}
