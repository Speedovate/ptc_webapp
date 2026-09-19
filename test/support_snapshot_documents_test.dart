import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/utils/cached_snapshot_documents.dart';

void main() {
  final cached = <Map<String, dynamic>>[
    {'id': 'old', 'text': 'Saved chat'},
    {'id': 'same', 'text': 'Earlier message'},
  ];
  test('empty and partial SDK caches preserve persisted messages', () {
    expect(
      mergeCachedSnapshotDocuments(
        remote: [],
        cached: cached,
        isFromCache: true,
        hasPendingWrites: false,
      ),
      cached,
    );
    final merged = mergeCachedSnapshotDocuments(
      remote: [
        {'id': 'same', 'text': 'Edited message'},
      ],
      cached: cached,
      isFromCache: true,
      hasPendingWrites: false,
    );
    expect(merged.map((d) => d['id']), ['old', 'same']);
    expect(merged.last['text'], 'Edited message');
  });
  test(
    'pending snapshots preserve history but confirmed deletion removes it',
    () {
      expect(
        mergeCachedSnapshotDocuments(
          remote: [],
          cached: cached,
          isFromCache: false,
          hasPendingWrites: true,
        ),
        cached,
      );
      expect(
        mergeCachedSnapshotDocuments(
          remote: [],
          cached: cached,
          isFromCache: false,
          hasPendingWrites: false,
        ),
        isEmpty,
      );
    },
  );
}
