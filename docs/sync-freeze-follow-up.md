# Sync-status freeze investigation

Production comparison: the fetched public main.dart.js matched pushed commit
6936f861145a43437cda8a90f9df02ae0dd5ba2b byte-for-byte (SHA-256
5faa47e2f4158f025e66f9dd28b68dc5a0eae9db0158d52d29746ccf6d05f589).
This confirms the code baseline, not runtime performance equivalence.

## Reproduced unnecessary work

1. readScopedStatuses called initialize even after startup. That refreshed and
   emitted queue status. OfflineSyncStatusService responded by reading all scoped
   statuses again, feeding the same event chain. The path also exists in the
   pushed source; it is not proven to be a newly introduced regression.
2. Media retry checks reread and rewrote unchanged photo payloads while all entries
   were waiting for future retry deadlines. Cleanup had the same write pattern.

Before fixing: three media status reads produced three status events; three
backoff checks caused three more queue writes without another upload. These
regression assertions failed against the pre-fix source.

## Applied changes

- All four queues skip repeated initialization during scoped status inspection.
- Aggregate status reads run serially, retaining only the latest waiting refresh.
- Unchanged merged current-user status no longer rebuilds listeners.
- Retain ordinary queue events so aggregate status still discovers other accounts'
  changes, including when current-user counts are unchanged.
- Media/cleanup passes with no due work do not rewrite queues or pretend to sync.
- No polling interval, Firestore schema, ID allocation rule, or queued action time
  was changed. Persisted queues and concurrency merge protections are retained.

## Validation

198 native tests and 30 focused Chrome tests pass. All four queues now emit zero
new events from three repeated scoped-status reads after initialization. Media
and cleanup backoff checks cause zero extra queue writes; pending payloads remain
stored. Analyzer passes. Existing tests cover retry recovery, overlapping enqueue,
account switching, identity resolution and original action timestamps.

These tests establish the corrected feedback/write behavior, not a measured FPS,
heap reduction or proof that every Aw, Snap crash is resolved. No authenticated
production browser performance trace or multi-role live test was available.
