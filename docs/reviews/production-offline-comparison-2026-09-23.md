# Production comparison and online/offline transition review

Reviewed September 23, 2026. Verdict: the working tree adds useful functionality
and diagnostics, but is not an unconditional reliability improvement. Fix the
account-scope regression before release; address chassis reservation semantics
before describing multiple advance assignments as supported end to end.

## Follow-up: sync diagnostics fixes

The subsequent local fix retains the initiating account through foreground save
and offline fallback, and decouples foreground completion from optional cache
notifications. Regression tests reproduce both prior failures and now pass.
Foreground request/UI errors, uncaught frontend errors, startup failures and
network transitions now feed the independent diagnostic outbox. A periodic
watchdog captures queues without progress after 90 seconds online, and bounded
upload waits permit retries after stalled diagnostic writes. See
`docs/sync-error-logs.md` for report fields and limitations.

Validation after these changes: 469 Flutter tests and 8 Chrome persistence tests
passed; `flutter analyze` has no issues. Browser tests use fake Firestore with
real browser storage; live Firestore receipt has not been exercised. This is a
local change, not a production deployment. The chassis reservation finding below
was separate from that diagnostics fix. It has subsequently been addressed by
the shared reservation/activation rules described in `docs/chassis-reservations.md`;
the original reproduction below is retained as review history.

## Verified baseline

- GitHub HEAD and main: `0bac99eaf67eb2068b25290c9e9011d962272477`, Release 1.0.1+9.
- Public production: `https://paltranco.vercel.app/`; version.json reports 1.0.1, build 9.
- Live main.dart.js and `git show 0bac99e:build/web/main.dart.js` have identical SHA-256:
  `d8bff3b70e84c272dba3542e48914d5e5d82931a063fb8a570292acebfd16544`.
- Local source includes uncommitted tracked changes and new files. Production
  does not yet contain the new sync-error logging implementation.
- Production tests ran from an isolated Git archive, not by resetting the working tree.

## Findings, ordered by priority

### P1 — Online failure after an account switch queues work under the wrong account (new)

`lib/services/offline_mutation_queue_service.dart:753` awaits the foreground write
and then calls `queueCollectionDocumentUpsert`. It does not retain the originating
account across that await. The queue's existing serialization captures scope
only when the later queue operation begins.

Reproduced using a paused fake Firestore transaction:

1. Account A starts an online KPI save; payload contains `updated_by: account-A`.
2. Change the active session to B while the transaction is pending.
3. Network becomes offline and the transaction fails.
4. The save falls back to the durable queue.
5. A has zero queued actions; B has one action containing A's payload.

This breaks account isolation/ownership in queue display and replay. The same
helper serves KPI and operations settings; booking workflow has a similar
foreground-then-enqueue path. Capture and retain account scope before the first
await, including the fallback and cache writes. Handle session changes explicitly
before publishing results into the current UI.

### P1 — Multiple advance chassis bookings are not supported consistently (existing gap)

`lib/requests/booking.request.dart:1303` clears the previous booking's `chassis_id`
when a normal direct assignment moves the chassis to another booking. Conversely,
`lib/services/offline_mutation_queue_service.dart:1600` rejects a queued assignment
when `current_booking_id` belongs to another booking.

Reproduced with fake Firestore: direct assignment to booking 10 removed booking
9's chassis link; queued assignment to booking 11 was then blocked with a chassis
conflict. The assignment-history UI can list multiple linked bookings, but does
not change these write rules. Once the old link is deleted, its membership also
cannot be recovered by the current history projection.

This direct-versus-queued distinction already exists in the production revision.
The local workflow's new online-first path reuses the stricter queued transaction;
it does not establish a reservation model. Separate scheduled booking reservations
from the chassis's current physical assignment and retain historical links.

### P2 — A committed foreground save waits on optional cache notifications (new UI exposure)

`lib/services/offline_mutation_queue_service.dart:748` awaits cache-version writes
after the business transaction has committed. `_publishCollectionVersion` at line
1514 has a 30-second timeout. Bookings publish both bookings and chassis versions
sequentially, permitting roughly 60 seconds of additional waiting if both stall.

Reproduced: the KPI document existed on the fake server, but the save Future
remained incomplete until an intentionally held `manage_cache` write was released.
This leaves the UI saying it is saving after the authoritative write has already
succeeded. Keep cache notification retries independent of foreground completion.

### P2 — Firestore diagnostics do not cover all foreground failures (coverage gap)

The foreground helper catches errors at
`lib/services/offline_mutation_queue_service.dart:735`, returns false for
connectivity failures, or rethrows other failures. It does not call
`offlineErrorDiagnostics`/`SyncErrorLogService.capture` there. Thus a foreground
permission, identity, or validation conflict that is never queued can be absent
from `sync_error_logs`.

Global handlers in `lib/main.dart:29` present/report Flutter errors but do not
forward them into the Firestore logger. Queued replay failures have much better
coverage now, but "every frontend/backend error is logged" would be inaccurate.
Add separate foreground capture with original owner, operation, exception and
stack, while avoiding duplicate reporting when a durable replay reports it again.

## Improvements compared with production

- Normal online workflow writes can await the server directly without showing
  queue progress; offline/temporary references still use durable replay.
- Transaction callback errors retain their original exception and stack instead
  of only the opaque converted-Future error. Old boxed booking/catalog failures
  get one guarded recheck without clearing their original base version.
- Queue replay errors now have a separate persisted diagnostic outbox and copyable
  context. Logging upload failure does not delete the business queue item.
- Operations catalog conflict review checks current server versions and preserves
  matrix-version history. KPI/fuel first-write collisions have explicit guards.
- Missing related users/vehicles retain their IDs during booking hydration rather
  than silently losing the reference.
- Nested quick login retains the original return account, and failed restoration
  preserves the active session instead of silently treating it as a successful return.
- Chassis lifecycle location projection now records origin/destination/return
  location and Garage after confirmation.

## Transition assessment

| Transition | Assessment |
| --- | --- |
| Online submit → server acknowledgement | Covered by service tests; optional cache-signal wait is a regression above. |
| Offline submit → local durable queue | Covered by service tests and real Chrome storage tests on both revisions. |
| Queue reopen → online replay → acknowledged removal | Covered by Chrome tests with a fake server; identity/action times retained. |
| Online save stalls/fails → queued fallback | Present, but account-switch ownership regression reproduced. |
| Server version changes → blocked conflict | Covered by booking/resource/catalog tests; preserves pending edits. |
| Boxed transaction error → original error/recheck | New guarded recovery tests pass. |
| Pending writes → account switch | Existing scope tests pass, but the new online-first fallback needs the fix above. |
| assigned → ongoing → delivered/check → empty → return → confirm | Online/request and queued workflow tests pass; physical state ends ready with links cleared. |
| Chassis shared by advance bookings | Inconsistent direct/queued behavior; history UI alone is insufficient. |
| Diagnostic capture offline → later Firestore upload | Injected-writer tests pass; actual live Firestore receipt was not tested. |
| Cold start without cached application assets | Not established by queue tests; requires separate first-load/cache validation. |

Browser online state is based on navigator.onLine, not a successful Firebase
request. Tests distinguish injected failures from genuine internet reachability;
a connected Wi-Fi indicator alone cannot establish backend availability.

## Validation performed

| Check | Production source | Current source |
| --- | --- | --- |
| Default Flutter tests | 313 passed | 463 passed |
| Chrome offline persistence/reopen/replay tests | 8 passed | 8 passed |
| Static analysis | Not rerun | No issues found |
| Release JavaScript web build | Live bundle matched pushed artifact | Passed, output in a temporary directory |

Three additional temporary fault probes reproduced the account-scope issue,
post-commit notification wait, and direct/queued chassis assignment difference.
Their passing assertions confirm the undesirable observed behaviors; they are
not regression tests declaring those behaviors correct.

The release build reported a WebAssembly dry-run incompatibility for an existing
dart:html import. The normal JavaScript release build completed successfully.

## Limits and release recommendation

No deployment, production data changes, or production account sessions were
performed. Browser persistence tests use actual browser storage with a fake
Firestore server: they do not prove deployed Firebase rules, Storage permissions,
physical network loss, hard browser restart, or simultaneous real-device races.
The repository Firestore rules are permissive, but deployed rules were not checked.
The release script also does not supply APP_BUILD_COMMIT, so logging's optional
commit identity remains unavailable unless supplied by another build process.

Fix originating-account ownership first. Then make post-commit notifications
nonblocking and align chassis assignment semantics across entry points. Add the
reproduced transitions as regression tests, and validate real Firebase/Storage
failure and reconnect scenarios on staging before calling the flow fully verified
end to end. Application source was not changed by this review.
