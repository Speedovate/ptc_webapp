# Current versus production: reliability and responsiveness

Reviewed 2026-09-23 after the shared chassis fixes. This is a read-only application
review: no application fixes, deployments, or production data writes performed.

## Subsequent fixes

The five findings below are historical review findings. A subsequent local change
moves photo cleanup to committed intent with guarded background deletion, stages
foreground photos in the durable upload queue, decouples diagnostic persistence
from business error handling, quarantines corrupt diagnostic rows, and reports
handled KPI/import/catalog/fuel errors. See `docs/booking-photo-safety.md` and
`docs/sync-error-logs.md`. Deployment and real production receipt remain separate
verification steps.

## Verdict

Current is better for reservation correctness, retained booking references,
transaction error visibility, account-return handling and diagnostic coverage.
It is not established as universally faster or less prone to stuck work. Do not
label it an unconditional reliability upgrade until the failure-path issues
below are addressed. Production is lighter and acknowledges photo-bearing
workflow actions locally sooner, but retains the earlier chassis inconsistency
and weaker diagnostics. Neither revision is proven error-free end to end.

## Baseline and evidence

The public production main.dart.js was fetched again and matches pushed commit
`0bac99eaf67eb2068b25290c9e9011d962272477` exactly:
`d8bff3b70e84c272dba3542e48914d5e5d82931a063fb8a570292acebfd16544`.
Production source was tested in `/private/tmp/ptc-prod-review.pKOY3u`.

Fresh default suite runs: production 313 passed; current 476 passed. The latter
includes account-switch fallback, nonblocking foreground cache notification,
shared reservations, physical ownership protection and crew/history tests.
Eight Chrome persistence tests passed on each revision in the preceding reviews;
the current run was repeated after chassis changes. They use real browser storage
and fake Firestore, not live Firebase. Current analysis is clean and its normal
JavaScript release build succeeded. An existing dart:html WebAssembly dry-run
warning remains. Suite duration is not a UI latency benchmark.

Two fresh isolated diagnostic fault probes passed assertions of undesirable
behavior, not assertions that the issues were fixed. Source:
`/private/tmp/ptc_comparison_fault_probe_test.dart`; output:
`/private/tmp/ptc-comparison-fault-probes.log`.

## Remaining findings

### P1: photo cleanup precedes the authoritative booking commit

`lib/requests/booking.request.dart:573` awaits `_persistPhotoFields` before the
booking transaction. At line 1105 that helper deletes obsolete photo paths when
uploads are not forced into the queue. `lib/services/photo_storage_service.dart:132`
performs Storage deletion (or queues deletion on connectivity failure), without
waiting for the replacement booking document to commit.

Trigger: a photo edit actually removes/replaces a referenced path, then the
subsequent booking transaction fails or conflicts. The remote booking can retain
a reference to a photo already deleted or scheduled for deletion. Code-path
finding, not a live destructive reproduction. This ordering already existed for
normal direct saves in production; current broadens exposure to online pending
workflow actions by changing `queueUploads` from `pendingActionAt != null` to
`pendingActionAt != null && !currentNetworkStatus()`.

Move obsolete-file cleanup after acknowledged booking commit, including replay,
and verify that the old path is no longer referenced. Direct Storage deletion
also lacks a deadline here, adding another possible extended save wait.

### P2: diagnostic persistence can hold a business queue's failure path

Mutation replay awaits `offlineErrorDiagnostics` at line 2593; the shared helper
awaits `SyncErrorLogService.capture` at line 40. Photo/media/cleanup queues also
await it. Capture serializes outbox reads/writes and awaits `_save` at line 505.
Only remote upload and metadata lookup have deadlines, not local persistence.

Fault probe: hold the diagnostic backend write unresolved; capture remains
incomplete until released. The code has no timeout on this await. Thus remote
logging is independent, but local diagnostic persistence is not independent of
business-queue error handling. Browser mirror writes normally return promptly;
the adverse path is blocked/unavailable mirror storage plus delayed IndexedDB,
or a stalled shared database open/read/serialized operation. This is not proof
that ordinary users presently experience the injected storage failure.

Use a bounded, failure-isolated capture path and ensure a wedged diagnostic task
cannot indefinitely hold either business replay or all later diagnostic work.

### P2: one malformed outbox entry prevents later diagnostic persistence

`SyncErrorLogService._read` at line 103 decodes the entire list without per-row
recovery. Fault probe: seed one invalid JSON row, then report a new failure. The
new report was not persisted or uploaded; only console messages were produced.
Startup/maintenance retry does not repair the malformed row.

Quarantine malformed rows and continue processing healthy/new reports. Diagnostic
coverage is broader than production, but not guaranteed durable in this state.

### P2: online photo workflow trades quick acknowledgement for foreground waits

Current pending actions upload photos before saving when the browser reports
online. Production forced these actions' photos into durable replay. The field
loop is sequential (`booking.request.dart:1090`), with a one-minute upload timeout
per photo (`:53`, `:1157`). Multiple slow uploads can therefore add multiple
minutes before the save returns. This is an asynchronous wait, not proof of a
blocked rendering thread, but users can experience it as a stuck Saving state.
The optional post-commit cache-notification delay was fixed separately; that fix
does not remove pre-commit upload/cleanup waits.

### P2: handled error coverage still has explicit holes

For example, KPI export catches errors at `pm_kpi_dialog.dart:1615` and displays
a direct ScaffoldMessenger snackbar; it neither calls the logger nor rethrows.
Global uncaught handlers and AppSnackbar logging cannot observe that handled
error. "All online errors have a copy_report" remains too broad. Audit handled
error boundaries and report original exceptions/stacks there.

## Functional and transition comparison

| Area/transition | Production | Current | Assessment |
| --- | --- | --- | --- |
| Account switch while online save falls back offline | Earlier architecture; no new online-first helper | Originating scope retained through await; regression tested | Current identified regression addressed |
| Advance booking shares chassis | Direct displaces old link; queued may reject | Multiple reservations; activation alone acquires physical ownership | Current better |
| Reservation cancellation while another booking is active | Inconsistent ownership model | Active chassis/crew retained | Current better |
| Release and next activation | Lifecycle present | Preserved old booking links and per-booking crew | Current better |
| Normal online workflow acknowledgement | Queue-based pending actions | Server-first where supported | Current clearer server outcome; not always quicker |
| Offline action, reopen, replay | Existing durable queues and identity checks | Same foundation plus added reservation/diagnostic checks | Both pass storage tests |
| Reconnect to reachable Firebase | Existing replay | Replay plus transition/stall diagnostics | Current more observable |
| Browser says online, Firebase unreachable | Indicator is not backend reachability | Same indicator; foreground media waits add exposure | No universal current win |
| Optional cache signal stalls after foreground commit | Pending workflow path differs | Foreground helper no longer awaits signal | Identified current regression fixed |
| Conflicting remote update | Version checks/blocking | Version checks plus guarded recovery and clearer error | Current better diagnosis; conflicts still require resolution |
| Malformed/hung diagnostic storage | No new diagnostic outbox | New failure paths described above | Production lacks this additional coupling |
| Authentication return account | Earlier restoration behavior | Original return scope retained; restoration failure handled | Current better in tested cases |
| Cold offline launch without previously cached app | Not proven by queue tests | Not proven by queue tests | Neither established |
| Concurrent real devices / deployed Firebase permissions | Not exercised here | Not exercised here | No end-to-end production claim |

## Performance and freeze assessment

Measured JavaScript bundle sizes (same normal release artifact category):

| Artifact | Production | Current | Difference |
| --- | ---: | ---: | ---: |
| Raw main.dart.js | 5,470,063 bytes | 5,795,844 bytes | +5.96% |
| Locally gzip-compressed main.dart.js | 1,537,501 bytes | 1,640,094 bytes | +6.67% |

Local gzip measurements are not measured CDN transfer sizes. More bytes imply
additional download/parse work, not a measured startup-time percentage.

The main lazy lists, storage mirror, connectivity implementation and queue
coordinator already existed in production; their presence cannot be counted as a
new speed improvement. AdminModalRecordList uses lazy row widgets but eagerly
builds values and measures all cells before layout on both revisions. Current
also groups rows; large lists still need realistic frame-time profiling.

New KPI template export decodes ZIP/XML, builds worksheets and encodes ZIP
synchronously after loading the asset (`kpi_template_workbook.dart:42-155`). An
async method does not move this CPU work off the browser UI thread. Large fleet /
multiple-month exports are a plausible frame-stall hotspot, not a measured
production regression because production has no equivalent new KPI feature.

Diagnostics add metadata reads, outbox serialization, a 30-second maintenance
timer and writes. Each capture reads/rewrites the outbox; uploaded receipts are
bounded to 500 but undelivered reports are not capped. Extended delivery failures
can increase CPU/storage cost. No representative long-running backlog or mobile
FPS benchmark was performed, so no numerical lag improvement is claimed.

## Release assessment

Keep the current correctness fixes. Before describing the build as the safer
production replacement, isolate diagnostic persistence from business replay,
recover malformed outbox entries, and make photo cleanup commit-safe. Decide the
acceptable foreground media wait and validate it on a throttled connection.

Then exercise authenticated staging with real Firestore/Storage: interrupted
upload, denied permission, browser online with blocked Firebase, account switch
during save, tab close/reopen before acknowledgement, simultaneous activation
from two devices, and a large KPI export. Verify both business outcomes and
actual diagnostic receipt. No deployment or production mutation was performed
by this comparison.
