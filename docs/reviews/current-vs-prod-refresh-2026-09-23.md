# Current versus pushed production — refreshed assessment

Date: September 23, 2026. Scope: read-only application review, regression tests,
Chrome storage/replay tests, and release compilation. No deployment or business
data mutation. This refresh supersedes the earlier reviews' *remaining* findings
where the subsequent fixes below now exist. It is not a claim that every path has
been exercised against real production Firebase.

## Decision

Current is the stronger candidate for PALTRANCO's expanded functionality and
specific data-correctness goals. Production is the smaller, simpler deployed
baseline. There is no measured basis to call current universally faster, immune
to freezing, or fully verified end to end. Keep the current correctness fixes;
measure and address the remaining performance and rollout risks before treating
it as an unconditional production upgrade.

## Baseline verification

- User identified production as the latest pushed commit.
- `git ls-remote origin refs/heads/main` returned
  `0bac99eaf67eb2068b25290c9e9011d962272477` (Release 1.0.1+9).
- Public `https://paltranco.vercel.app/version.json` reports 1.0.1, build 9.
- Live main.dart.js and that commit's build artifact have identical SHA-256:
  `d8bff3b70e84c272dba3542e48914d5e5d82931a063fb8a570292acebfd16544`.
- The isolated production test directory's 262 tracked source/test/pubspec files
  match HEAD byte-for-byte. The current tree contains uncommitted changes and new
  files; it is not the deployed bundle.

## Fresh validation

| Check | Production | Current |
| --- | --- | --- |
| Default Flutter suite | 313 passed | 483 passed |
| Full static analysis | Not rerun in this refresh | No issues |
| JavaScript release | Live artifact verified | Fresh temporary build passed |
| Chrome checks | 12 passed: persistence/cache/images | 24 passed: same 12 browser checks plus 12 diagnostic tests |

Tests use fake/injected Firestore and Storage behavior. Browser storage tests use
real browser storage, but do not reproduce actual Firebase permissions, hard
browser termination, physical network disconnection, or multiple real devices.
Test counts describe coverage, not a percentage improvement in reliability.
Release compilation reported the existing dart:html WebAssembly dry-run warning;
the normal JavaScript build succeeded.

## Functional comparison

| Area | Production | Current | Conclusion |
| --- | --- | --- | --- |
| Startup and existing list pages | Already has shared booking stream, cache, 15-row display paging, lazy widgets, resume safeguards | Retains those foundations, adds features/logging | No new universal speed win established |
| Online workflow writes | Existing pending-action queue path | Foreground server acknowledgement where eligible; queued fallback for offline/temporary references | Clearer outcome, tested transitions; network waits still possible |
| Account switch during failed online save | Does not contain the new foreground helper | Captures initiating account around save/fallback | Earlier current regression fixed and tested |
| Offline create/update and action times | Durable queues and resolver already present | Retains foundation; adds KPI/catalog/fuel coverage and diagnostics | More scope, not proof every role/operation is live-E2E verified |
| ID allocation | Existing resolver and collision protections | Core resolver unchanged; regression suite passes | Do not count it as a newly rewritten/faster resolver |
| Conflicting remote edits | Version checks block unsafe writes | Guarded boxed-error recovery, original transaction exception/stack, catalog conflict handling | Better diagnosis and targeted recovery; genuine conflicts remain valid |
| Chassis reservations and activation | Earlier direct/queued ownership discrepancy | Shared reservation rules; activation acquires physical ownership, reservations/history retained | Current better in tested direct and replay paths |
| Chassis location/status | Earlier lifecycle | Pickup/drop-off/return projection and ownership protection | Current better aligned with requested workflow |
| Booking photos | Earlier cleanup ordering can precede booking commit | Durable upload staging; committed cleanup intent; reference recheck and cleanup claim | Current safer under tested failed-save and replay scenarios |
| Impersonation/return | Earlier restoration behavior | Retains original return account, handles restoration failures | Current improves tested cases |
| Support chat/media | Existing queue, identity and persistence foundation | Broad foundation retained plus reporting | No evidence here of a universal chat-latency improvement |
| KPI, payroll, rates, fuel, incidents, export | New module absent | Added with scoped caches, permissions, financial tests and offline queue coverage | Current meets substantially more of the new goals |
| Error observability | Earlier local/console reporting | Persistent Firestore diagnostic outbox, original context, stall/network observations | Current materially better for investigation; logging itself is not bug recovery |

Relevant regression files include `online_transition_regression_test.dart`,
`booking_boxed_error_recovery_test.dart`, `chassis_reservations_test.dart`,
`booking_photo_commit_safety_test.dart`, `pm_kpi_queue_test.dart`, and
`sync_error_log_service_test.dart` in `test/`.

## Prior failure-path findings checked again

The following are no longer outstanding in the inspected current implementation:

1. Diagnostic persistence holding business failure handling: the shared diagnostic
   helper dispatches capture without awaiting it; local capture callers are bounded.
2. A malformed diagnostic row poisoning the entire outbox: invalid rows are now
   skipped/quarantined; healthy rows continue.
3. Photo cleanup before successful booking commit: cleanup intent is committed
   with the booking; deletion checks current references and records a claim.
4. Foreground photo upload holding save for network transfer: photo bytes are now
   staged durably and uploaded in the background after the booking marker commits.
5. Handled KPI export/edit failures missing reporting: relevant handlers now report
   original errors/stacks. This is not coverage of every swallowed SDK/browser error.
6. Account-switch fallback and post-commit cache-notification waits: dedicated
   regression tests now pass; optional notifications do not gate save completion.

## Remaining risks and performance work

### 1. KPI rebuild CPU work

`lib/views/admin/pm_kpi_dialog.dart:872` calculates the selected period inside
`_buildContent`; monthly mode calculates another four weekly results at line 1014.
Transactions are also sorted/grouped during the build. Day expand/collapse invokes
setState and repeats this work. Fifteen displayed rows limit rendered cells, not
all underlying calculations. Cache the derived report by data/period/settings
revision so presentation-only changes reuse it. Profile realistic large inputs.

### 2. Export runs CPU work on the browser main thread

`lib/services/kpi/kpi_template_workbook.dart:42` performs ZIP/XML decoding,
worksheet construction and ZIP encoding synchronously after loading the asset.
An async function does not move that work off the UI thread. Large fleet/range
exports can cause frame stalls; no measured freeze duration is claimed here.
Consider a web worker or chunked work and measure representative exports.

### 3. Diagnostic backlog cost is not bounded by receipt retention

`lib/services/sync_error_log_service.dart` has one 30-second maintenance timer,
one network subscription, and serialized outbox writes. Each capture processes
and rewrites the outbox; repeated errors still incur local work before upload
coalescing. Only acknowledged receipts are capped at 500; undelivered reports
are retained indefinitely. Long permission/network failures or error storms can
increase storage/CPU costs. Timed-out SDK writes cannot be cancelled and can
finish after a retry. Exercise a long backlog and improve incremental storage /
backpressure without silently dropping required error history.

### 4. Display paging does not page the Firestore collection

`BookingRequest._ensureBookingsRealtimeSync` still listens to the full bookings
collection in both revisions. `AdminModalRecordList.build` materializes values and
measures all supplied cells before building lazy row widgets. Fifteen-row windows
help rendering, but full data hydration/filtering/reconciliation still scales with
data size. Server paging needs a separate complete/partial cache design so global
search, export and ID reconciliation remain correct.

### 5. Mixed old/new clients need an explicit rollout check

Old deployed clients do not enforce new photo-cleanup claims or the new chassis
reservation semantics. Tests covering only updated writers cannot prove safety
when an old open tab writes concurrently. Verify mixed-version behavior and
refresh/update handling; retain reservations, photo references and action times.

### 6. Server-side permissions remain a separate safety issue

The repository's `firestore.rules` allows all reads and writes (`if true`) and is
unchanged from the baseline. New UI role restrictions are not server-side security.
Actual deployed rules were not read. If those permissive rules are deployed, both
versions have this exposure; current adds more operational/log data. Verify actual
rules before making a security-safety claim; do not blindly tighten them without
covering the existing custom authentication flows.

## Size and responsiveness evidence

| main.dart.js | Production | Current | Change |
| --- | ---: | ---: | ---: |
| Raw bytes | 5,470,063 | 5,803,748 | +6.10% |
| Locally gzip-compressed bytes | 1,537,501 | 1,642,017 | +6.80% |

These are artifact sizes, not measured CDN transfers or startup-time percentages.
Production has a smaller download/parse input. Runtime FPS, first-use latency,
memory growth and browser crash rates were not measured in authenticated release
sessions. Hot-restart debug shader errors are not an equivalent production
benchmark. The shared engine-view guard is unchanged, so current cannot claim a
new blanket fix for GPU/renderer failures or browser OOM termination.

## Release checks that would resolve the uncertainty

Compare release builds on the same device/browser/data: cold and warm startup,
first menu open, scroll p95/p99 frame time, repeated navigation/KPI expand-collapse,
background/resume, large exports, and memory after a sustained session. Separately
exercise real Firebase/Storage: offline submit/reopen/reconnect; online indicator
with Firebase blocked; interrupted image transfer; denied writes; stale conflicts;
account switch during save; simultaneous chassis activation; mixed old/new tabs.
Confirm original action times, stable IDs, no duplicate business effects, accurate
chassis ownership and actual Firestore diagnostic receipt.

No authenticated production sessions or data changes were performed by this audit.
