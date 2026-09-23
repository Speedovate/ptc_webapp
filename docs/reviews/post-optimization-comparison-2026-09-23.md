# Post-optimization comparison with pushed production

September 23, 2026. Application source was not changed during this review. No
production business data, accounts, rules or deployments were changed. This
assessment supersedes an unconditional reading of the preceding successful-test
summary: new fault probes exposed failure paths not covered by that suite.

> Follow-up: the three reproduced defects were subsequently fixed locally.
> See [three-issue-fixes-2026-09-23.md](three-issue-fixes-2026-09-23.md) for scope and validation.
> The findings below describe the pre-fix review state.

## Verdict

Current is more complete for the requested PALTRANCO goals and has better tested
booking/chassis/photo correctness and error observability. It is **not yet an
unconditional safety or responsiveness upgrade**. Three current failure paths
were reproduced with injected dependencies. Fix these before recommending the
whole current bundle as the safer production replacement. Production retains a
smaller bundle and simpler single-listener booking architecture, but lacks the
new features and correctness protections.

## Baseline and evidence

- Latest pushed main was checked again: `0bac99eaf67eb2068b25290c9e9011d962272477`.
- Public production main.dart.js still matches that commit exactly, SHA-256
  `d8bff3b70e84c272dba3542e48914d5e5d82931a063fb8a570292acebfd16544`.
- Recent baseline suite: 313 tests and 12 Chrome checks passed.
- Latest full current suite: 491 tests and 35 Chrome checks passed. Final focused
  page/cache and booking tests also passed after the final source refinements.
- Current analyzer clean; JavaScript release build successful. These existing
  validation runs were not repeated wholesale solely for this review.
- Fresh current fault probes: three reproduced undesirable outcomes. Their tests
  pass because their assertions confirm the defects, **not because they are fixed**.
- Fresh production cache probe: the equivalent ordered storage-failure scenario
  retained the newer cache value.

Probe source is retained in `probes/post-optimization-current-probe.dart.txt` and
`probes/post-optimization-prod-cache-probe.dart.txt`. Copy the relevant file to a
`.dart` temporary file and run `flutter test --no-pub <path>` from the respective
source checkout. These use fake Firestore/storage, not live failures on a user's
device. The cache fake preserves serialized write ordering like the web backend.

## Findings

### P1 — A late cache fallback can remove a newer successful mirror

Location: `lib/requests/firestore_cache_store.dart:227`.

Reproduced sequence:

1. An older cache write cannot save its localStorage mirror and waits for its
   IndexedDB fallback.
2. A newer write successfully saves its mirror. Its asynchronous IndexedDB backup
   subsequently fails (injected storage/quota failure).
3. The older fallback completes, then unconditionally removes the mirror key.
4. A newly constructed cache store reads the older data from IndexedDB.

The revision check runs before the awaited fallback, not before the destructive
mirror removal after that await. Production does not remove the newer mirror in
this scenario; the equivalent probe reads the newer value there. This is a
persisted-cache regression, not evidence that Firestore business documents were
overwritten. It matters particularly when the user reopens offline.

Required correction: coordinate the entire per-resource persistence operation,
recheck ownership/revision after awaited work, and only remove a mirror that is
still the stale value owned by that operation. Include fallback failures and
cross-store/tab writes in regression coverage.

### P2 — Failed initial page discovery leaves live updates uninstalled

Location: `lib/services/paged_booking_source.dart:109` and `:153`.

The source installs range listeners only after all initial page reads succeed.
The catch reports an error but does not re-arm discovery. Rebuild is requested on
a network-status event or range overflow; neither necessarily happens when the
browser remains online while Firebase temporarily fails.

Reproduced: initial get throws `unavailable`; then a direct read succeeds and the
fake server accepts a booking update, but the original watch still has zero live
subscriptions and emits no booking updates. A successful direct refresh does not
repair that watch. Production attaches its single collection listener directly,
without this new successful-page-discovery prerequisite. This is not a claim
that every production listener error is automatically recoverable.

Required correction: bounded recovery for transient discovery/listener failures,
including successful foreground refresh/resume while navigator.onLine remains
true. Recovery must retain the previous complete dataset, suppress duplicates,
and stop on disposal/account invalidation rather than polling indefinitely.

### P2 — Concurrent diagnostic writers can orphan a persisted report

Location: `lib/services/sync_diagnostic_outbox.dart:65`.

Each writer reads a shard index, modifies it, then writes it back separately from
the report body. The owning service's lock covers one Dart instance, not another
browser tab sharing the same origin storage.

Reproduced with two independent writers and colliding index shards: both report
bodies are stored, but one index overwrites the other. `ready()` finds only one
report, so the other is not uploaded. This concerns diagnostic completeness,
not loss of the business queue operation. Production lacks the new outbox, so it
also lacks its reporting benefits; it is not a diagnostic reliability winner.

Required correction: cross-tab atomic index/record updates (for example, a real
IndexedDB transaction), or discoverable per-record storage without a vulnerable
read/modify/write index. Retain legacy migration and orphan-recovery coverage.

## End-to-end and transition comparison

| Transition / area | Production | Current assessment |
| --- | --- | --- |
| Normal online save → acknowledgement | Existing workflow/queue behavior | Eligible foreground writes await server; optional cache notification does not hold completion |
| Online save fails → offline fallback | Existing architecture | Initiating account retained; regression tested |
| Offline booking → close/reopen queue → reconnect | Existing durable queue/resolver | Same core plus broader coverage; browser tests preserve identity/action times |
| Driver/helper finish/complete/delivered offline → replay | Existing paths | Request/service tests pass, including original action time and lifecycle effects |
| Offline cached reads under overlapping storage failures | Older cache behavior | Newly reproduced stale-cache regression above |
| Browser online but Firebase unavailable → backend recovers | Single listener installed independently | Failed-discovery recovery gap above |
| Remote edit → conflicting local replay | Version checks block unsafe writes | Clearer original errors and guarded recovery; true conflicts still require resolution |
| Temporary ID → permanent ID | Resolver already exists | Core retained and tested; no blanket claim of a new faster resolver |
| Multiple chassis reservations → activation → release | Earlier ownership inconsistency | Shared reservation/ownership rules tested on direct and replay paths |
| Replace photo → booking commit fails | Earlier cleanup ordering risk | Committed cleanup intent, reference checks and staged upload improve safety |
| Admin impersonation → return/logout | Earlier restoration behavior | Tested original-account retention and failure handling improvements |
| Diagnostics offline → online → recovery | No persistent new outbox | Better reporting/retention, but cross-tab index race remains |
| Old and new clients writing together | Deployed older rules | New cleanup claims/reservation conventions need mixed-version verification |

These are code/service/widget/browser-storage results. They do not establish all
real-role UI journeys against actual Firestore/Storage. No staging/test accounts
were provided, and no authenticated production session was used.

## Responsiveness comparison

The four optimizations do useful work:

- KPI period results are reused across presentation-only rebuilds.
- Workbook export yields between batches; its output-equivalence tests pass.
- Diagnostic writes no longer serialize every report body in the backlog.
- Booking requests/live ranges are bounded, unchanged models are reused, and
  large supported-browser cache compression uses a worker.

But their limits matter:

- The full logical booking dataset is still retained. A single changed range can
  still lead to combined-cache serialization and a traversal of all booking
  fingerprints. This is not O(changed-documents)-only processing.
- Cold range discovery plus range subscriptions can add reads/listeners compared
  with production's single subscription. More pages do not by themselves prove
  lower latency or lower memory. Multiple queries also do not constitute one
  atomic collection snapshot; cross-range transitions need dedicated checks.
- The export's scheduling budget is checked between operations, not a hard
  deadline within a single XML/ZIP operation.
- Unsupported worker/native-compression environments use the compatible main-
  thread fallback codec. Pending diagnostic storage can still grow indefinitely
  by design, even though individual writes are cheaper.
- Existing lazy lists, shared streams and engine-view guards already exist in
  production. They cannot be counted as new current-only speed improvements.

| Release main.dart.js | Production | Current |
| --- | ---: | ---: |
| Raw bytes | 5,470,063 | 5,824,997 |
| Locally gzip-compressed bytes | 1,537,501 | 1,649,034 |

Current is +6.49% raw / +7.25% gzip. These are artifact sizes, not measured CDN
transfer sizes or startup-time percentages. There is no authenticated release
FPS, p95/p99 frame-time, sustained-memory or crash-rate result proving a winner
for lag/freeze/Aw, Snap. Debug hot restart is not an equivalent prod benchmark.

## Safety beyond functional correctness

Repository Firestore rules still allow all reads/writes and are unchanged from
production source. Actual deployed rules were not read. UI role permissions do
not establish server authorization. Native browser crashes, storage eviction,
physical network interruptions and mixed-device concurrency remain outside the
passing unit/browser-storage coverage.

## Recommendation

Keep the current features and targeted correctness improvements. Fix the three
reproduced findings before deploying this as the safer replacement. Then compare
release builds on the same device/data: cold/warm startup, first page open,
scrolling, repeated KPI interactions, background/resume, large export and a long
queued backlog. Exercise actual Firebase/Storage reconnect/failure cases and
mixed old/new clients separately. Production is preferable in the reproduced
cache-fallback scenario; current is preferable in the tested chassis/photo/
account-scope flows. Neither is established as universally error-free end to end.
