# Performance follow-up: KPI, export, diagnostics and bookings

Implemented locally on September 23, 2026. No deployment or production data
migration was performed.

## KPI calculations

The modal retains calculations for its current data/period revision. Expanding a
day, loading more displayed rows, showing issues and opening controls reuse the
monthly and weekly results. Changed bookings, stored settings/rates/fuel/days,
PM crew/code mapping, or selected period invalidate the cache. Transient cache /
refresh warnings are reset independently so successful refreshes do not retain
old warnings. Fleet export also reuses each PM/month's weekly calculations.

## Excel export

The workbook generator now has a cooperative async production path. It yields
between PM blocks, fuel row batches, months, worksheet serialization and archive
members after its scheduling budget. Both the synchronous reference path and
async path use the same generator; content-equivalence tests compare every ZIP
member, including formulas, styles and worksheets. This is chunking, not a claim
that all workbook work runs in a web worker. An individual XML/ZIP operation can
still take time; large real-fleet frame-time measurements remain useful.

## Diagnostic outbox

New diagnostics use independent records and 64 sharded indexes of upload metadata.
Updating an existing report writes that report and its small index, not every
other error/stack in the backlog. Upload reads at most 20 eligible report bodies
per batch and yields between index shards. Pending reports are retained; remote
Firestore logs are never deleted automatically. Local acknowledged receipts are
bounded to eight per shard (512 overall).

The legacy v1 list is migrated under the existing serialization lock. Its document
IDs, occurrence counts and original times are preserved. The legacy container is
cleared only after all healthy reports are persisted in the new format. Corrupt
rows remain quarantined. Retaining every undelivered unique error still consumes
disk space; this change removes whole-payload rewrites, not finite device limits.

## Booking data

UI display paging remains 15 rows. Background Firestore reads use stable document
ID pages of 150, which include legacy documents without created_at and provisional
IDs. Live listeners use disjoint ID ranges capped at 151 (the extra row detects
range overflow). Overflow triggers a coalesced repartition; subscriptions/timers
are cancelled when the source is disposed. Unchanged range snapshots do not emit
another complete-cache update. Partial reads are never published as a complete
collection or allowed to erase unrelated cached records.

Hydration reuses unchanged Booking models using compact content fingerprints,
invalidates on related user/vehicle data changes, removes deleted entries and
yields every 75 documents. Cache serialization yields between 150-document
batches. Large web cache gzip compression/decompression uses one reusable native
browser worker, disposed after idle; the existing gzip mirror format remains
readable by older clients. Browsers without worker/native compression support use
the compatible existing codec. Async cache writes have revision guards, including
parallel document/version writes and clear operations.

This deliberately retains the complete logical dataset for global search, KPI,
export, offline operation and ID reconciliation. It is not demand-only per-screen
server pagination and does not cap total dataset memory at 15/150 records. A cold
complete load still reads all documents in bounded requests. Partition discovery
and range listeners can cost additional initial reads and use one listener per
range. Measure real Firestore cost and large-data memory/frame times before
claiming a universal improvement over the old single listener. Moving to a truly
bounded per-screen dataset requires separate server-backed search/count/export /
KPI paths; silently limiting the shared cache would break existing behavior.

## Validation

- Full regression suite: 491 passed.
- Chrome: 35 checks passed, including native-worker codec compatibility,
  offline persistence/replay, cache concurrency, bounded pages and diagnostics.
- Additional final page/cache and booking regressions pass after unchanged-page
  suppression and compact fingerprint review.
- Analyzer clean; normal JavaScript release build verified in a temporary folder.
- Existing WebAssembly dry-run warning is separate from the successful JS build.

No authenticated production network tests or production FPS/memory benchmarks
were performed. These checks establish tested behavior and scheduling boundaries,
not a guarantee of zero lag, freeze or browser termination.
