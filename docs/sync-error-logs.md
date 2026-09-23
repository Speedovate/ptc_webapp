# Persistent sync diagnostics

`sync_error_logs/{device_id}_{fingerprint}` is written by the application, not a
Cloud Function. Ship the updated client to each affected device. The existing
Firestore rules must permit writes to this collection. No production rules or
data are deployed as part of this change.

Copy the document's `copy_report` field to investigate an error. It contains the
source file, queue operation and entry ID, target ID/path, original action time,
first/latest failure times, captured time, attempt count, raw exception, stack,
Firebase plugin/code where available, role/account scope, current session ID,
version/build, platform/browser, viewport and origin/path. Optional build
identity can be supplied with `--dart-define=APP_BUILD_COMMIT=<commit>`.

Coverage: foreground request failures, displayed UI errors, uncaught Flutter/platform/zone errors, startup failures, mutation replay, booking-photo uploads (including failures subsequently
removed as obsolete), support/profile/media replay, and cleanup replay. Queue
errors from older clients are scanned once on startup in known saved account
scopes. Original diagnostics are retained; absent historical stacks/times cannot
be reconstructed. These recovered reports are marked `persisted_queue_failure`.

`online_queue_activity` records a transition into syncing while the network
monitor reports online. This is an observation, not proof of an application bug:
reconnect replay is expected. It includes queue source flags and up to 100 queue
item summaries (IDs, action times, retry counts, blocked status). Same-minute,
same-scope, same-stack observations deduplicate. Business queue visibility and
online-first behavior are not changed by logging.

Failure capture first persists in a separate local outbox. Remote writes run
independently of business operations. Upload is single-flight with batches of 20,
triggered by connectivity/status events and a 30-second maintenance timer.
The watchdog reports `queue_stalled` after 90 seconds without observed progress
while online, including pending/failed counts, retry deadlines, blocked flags,
account scopes and recent network transitions. It resets the observation window
on reconnection and progress; repeated stall reports are limited to five-minute
intervals. Empty queues report recovery after a detected stall. These are
observations, not a definitive diagnosis: deliberately blocked conflicts and
saved-account queues can also remain pending.

Duplicate callbacks for the same fingerprint/attempt are ignored. Changed
failures get separate documents; repeats update their existing document at most
once every five minutes. Uploads have a 30-second deadline; failures retain the
outbox and retry after a one-minute cooldown, or immediately on reconnection.
Timed-out SDK writes cannot be cancelled and may still complete later; retries
use the same document ID. Diagnostic uploads never block a business save.
Closing a tab before delivery leaves the local outbox
for the next session. If browser storage itself is unavailable, logging reports
a console error and cannot promise durability.

Acknowledged diagnostic receipts are bounded locally to eight per shard (512 total); unacknowledged
reports are never evicted by that limit. Existing business queue entries and
original timestamps are not modified by backfill. Queue success/removal never
deletes Firestore diagnostics. There is no TTL or automatic remote deletion.
Reports describe observed failures, not current unresolved status.

Credentials in exception strings and nested diagnostic context are redacted. Queued payload values, chat
messages, attachment/image bytes, passwords and tokens are not included as
context. Error text is limited to 16,000 characters and stack text to 48,000;
`diagnostic_truncated` explicitly marks this case to stay below document limits.
`received_at` is a server timestamp; action/failure timestamps remain the original
client-observed times. Firestore permissions and actual production receipt still
need verification in the deployed environment.


Failure-path hardening (September 23 follow-up): business queues retain the
formatted error in their own durable entry and dispatch diagnostic capture
without awaiting the diagnostic outbox. Capture callers have a two-second local
persistence budget; the underlying write lock remains serialized until storage
settles, so a late write cannot overwrite newer reports. Temporary storage stalls
can delay durability until recovery, but do not hold business failure handling.
Queue snapshot enrichment also has a deadline. Malformed JSON/schema rows are
quarantined locally (bounded/redacted) and skipped so healthy/new reports can
persist and upload. No logger can guarantee durability if all browser storage
remains unavailable or the tab closes before a write succeeds.

Handled KPI load/edit/export, import, operations catalog and fuel-ledger failures
now report original errors/stacks before UI presentation. Booking request fallback
catch paths also report their errors. Export reports identify the operation as
`export KPI workbook`. This does not claim coverage for every possible browser
termination or every third-party library's internally swallowed error.

Performance follow-up: new reports are stored individually with 64 small sharded
indexes. Retrying/acknowledging one report does not rewrite other error payloads.
The v1 list migrates without changing report IDs or original action/failure times;
it is cleared only after successful local migration. See
`performance-followup-2026-09-23.md` for coverage and remaining limits.
