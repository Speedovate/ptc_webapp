# Offline writes and identity audit — 2026-09-18

Scope: request-layer create/update entry points and shared replay services used by
admin, client, driver, helper, and configurable dispatcher access. Role permission
checks remain in their existing request/view-model paths. This audit does not
certify production security rules, every browser/device, or every screen interaction.

| Area | Offline identity and replay behavior |
| --- | --- |
| Booking creation | Existing booking reservation/resolver allocates unused numeric IDs; original creation time survives sync. |
| Booking workflow and edits | Existing identity stays stable; Complete/Finish/Deliver/cancel enqueue durably; action event/time retained on unchanged failed retry. Temporary client/vehicle/chassis references wait for their creates. |
| Billing updates | Existing booking identity; original queued time; version check and patch in one transaction. Bulk queue replacement touches only requested bookings. |
| Users and client members | Shared resource create queue; edits coalesce into pending creates; numeric IDs are retained on updates. Parent client and vehicle-type references remap explicitly. |
| Vehicle makes/types/sizes | Shared resource create/update queue; temporary driver/type references resolve before replay. Editing a temporary record after reconnect queues instead of writing an offline ID to Firestore. |
| Forms, fields, statuses | Shared resource create/update queue; field_ids and field_overrides keys remap. Form answers, labels and machine/status keys remain intact. |
| Chassis | New offline chassis use negative temporary IDs; legacy numeric provisional creates stay queued until resolved. Creation publishes an alias for dependent booking writes; provisional edits retain their identity; linked timestamps use the action date. |
| Profile/license photos | User identity resolves in the originating queue scope; upload time is separate metadata. Existing value comparison protects newer photos. |
| Booking photos | Existing verified booking resolver; upload waits for matching pending marker and preserves booking action timestamps. |
| Support | Stable message IDs across direct send and offline fallback; queued action time retained. Sender/requester IDs resolve in their originating queue scope; older messages cannot rewind the remote thread preview. Thread/message keys retain their existing format. |
| Role access and read markers | Update existing semantic keys; do not allocate numeric IDs for role names or thread paths. |

Shared safeguards added in this audit:

- Each new offline resource has a distinct identity based on its provisional ID,
  rather than its editable name/email/form description.
- Generic resource and chassis creates refuse to overwrite occupied reservations.
  A committed create retry does not restore old data over subsequent edits.
- Resource updates check the base version inside their write transaction.
- Only schema-owned ID fields remap. Missing dependencies remain queued; ambiguous
  conflicts remain reviewable instead of being guessed or discarded.
- Queue read/modify/write sections and flush-result reconciliation serialize;
  network work runs outside this local lock.
- No additional periodic timers or Firestore subscriptions were introduced.

Existing boundaries:

- Self-registration explicitly requires internet. First-time authentication and
  uncached cloud files cannot be made available by an ID resolver.
- Offline actions still require the relevant forms, assignments and permissions
  to be cached. An unavailable dependency must produce a recoverable error or
  remain pending rather than bypass validation.
- Chassis booking/driver references now retain temporary string IDs through the
  model, editor, local cache and queue. Confirmed numeric references serialize
  back to the existing numeric Firestore representation. Existing integer
  constructors/accessors remain available. Creating a driver, booking and chassis
  offline and replaying their links after a simulated restart is regression-tested.
- Provisional chassis deletion waits for its own create alias and cannot delete
  an occupied numeric record without that mapping. Detaching a chassis only clears
  a booking still linked to that chassis. Other delete policies remain unchanged.
- Legacy conflicting reservations remain blocked for review. The booking-specific
  preserve-both repair policy is not blindly applied to users/catalog records.
- Timestamps preserve the device's captured action time; this does not correct an
  inaccurate device clock.

Validation: native regression suite, focused resource replay tests, static analysis,
release web build. Resource tests use a transaction helper because
fake_cloud_firestore 4.1.1 ignores SetOptions in transaction.set. The helper models
merge semantics and buffered writes, but does not simulate server transaction
contention, security rules or real browser reconnection. Authenticated per-role
browser offline/reconnect validation remains a deployment check.

Chassis follow-up validation: legacy numeric round trips, temporary references
through JSON reload and edits, request-layer local save, dependency replay with
preserved action times, stale assignment conflicts, provisional delete isolation,
and an account switch during a paused local queue write. Chassis and workflow
regressions also ran in Chrome with fake Firestore; this is not a live Firebase
multi-device or authenticated per-role acceptance test.

## Follow-up: linked dependencies and in-flight saves

The follow-up audit found and corrected three additional cases:

1. New booking and chassis creates could wait on each other's temporary IDs.
   An exact reciprocal pair now commits together, preserving both action dates
   and reservation identities. Occupied IDs leave both actions pending for review.
2. A chassis edit arriving during create acknowledgement could be mistaken for a
   conflicting create retry. Successful-create reconciliation now retains it as
   a version-checked update. Replaying an acknowledged original create preserves
   later remote edits instead of restoring its old contents.
3. A booking photo could enter another user's queue if accounts changed while
   image preparation was pending. The queue scope is now captured before that
   preparation starts.

Regression coverage includes both linked-create queue orders, lost acknowledgement
and restart, occupied reservations, edits during a paused transaction, and account
switching during actual image preparation. These are local/fake-Firestore checks;
real server security rules, transaction contention and authenticated multi-device
reconnection still need live acceptance validation.

### Follow-up: media queue commit races and failed uploads

Media flush-result merges now share the enqueue mutation lock. Network uploads
remain outside the lock. A photo enqueued while a completed batch is being
persisted cannot be erased by that batch's stale queue snapshot.

All failed media entries retain their bytes, original action date and last error.
Previously a non-retryable user-photo exception silently removed the queued copy.
Retry deadlines are persisted: transient failures back off from 20 seconds to
20 minutes; other failures wait 20 minutes between attempts. Existing scheduling
checks the deadline without additional timers/listeners. Scoped/current failed
counts include retained errors. Legacy entries without a deadline remain readable.
An unavailable upload can therefore remain pending; this is not a guarantee of
successful storage authorization or server acceptance.

Regression tests pause the local flush commit while enqueueing another photo,
and verify failed uploads survive with unchanged action time and that repeated
flush calls do not bypass their deadline. Live browser/multi-device validation
remains necessary; these are local storage and fake-service tests.

### Browser verification (2026-09-18)

No staging environment or role test accounts are available (confirmed by the
owner). Live authenticated per-role acceptance testing remains unverified.

Added `test/web/offline_browser_persistence_test.dart`: eight browser-only cases
cover admin/client booking creates and driver/helper complete, finish and delivered
payloads. These use the actual browser storage backend and a fake Firestore server.
They verify pending data survives opening another backend/queue instance, writes
wait while the injected connection flag is offline, action dates survive replay,
occupied booking IDs stay untouched, confirmed identity resolves using the exact
submission key, and a second flush does not duplicate the action. These queue-level
cases do not log in as those roles, reload the browser process, cut the real network,
or exercise production security rules. Workflow view-model cases are separate.

Browser test setup now seeds/reads session anchors through AuthStorageBackend and
clears media-test session keys explicitly. SharedPreferences mocks alone do not
reset the web localStorage backend; this caused five failures in a combined Chrome
run even though focused/native runs had passed.

Validation after test fixes:
- Full native suite: 148 passed.
- Chrome persistence + media + auth-session suites: 23 passed.
- Flutter analyzer: no issues.
- Broad Chrome run also exposed four existing DOCX template-build test timeouts
  (30 seconds each); export browser verification remains unresolved. The entire
  Chrome suite is therefore not reported as passing.

This verification changed tests/documentation only; no production deployment or
live data mutation was performed.

### Follow-up: deleting resources before their IDs finish resolving

Confirmed and fixed additional provisional-delete gaps:
- User deletes previously removed their pending resource create, losing the only
  source of the confirmed-ID alias. Keep that create until identity resolution,
  then delete its confirmed target; this also handles an already in-flight create.
- User, vehicle make/type/size and status/field/form delete requests now route
  temporary targets through the queue even when connectivity has returned. A
  successful delete of a nonexistent temporary server document must not count as
  deletion of the pending create.
- Generic replay rejects unresolved negative targets as well as `offline_` IDs.
  No guessed/raw temporary target is sent to the server delete operation.

Twelve regression cases cover seven resource create/delete replays, three vehicle
request paths after reconnect, unresolved negative targets, and a user delete
arriving during create commit. Existing occupied records remain unchanged. This
fix adds no listener, polling loop, or reservation guessing. Confirmed numeric
record deletion keeps its existing behavior. Previously lost pending payloads
cannot be reconstructed by this fix; live data reconciliation remains separate.

### Follow-up: offline file cleanup (2026-09-19)

The file/folder cleanup queue still had unprotected read/modify/write operations.
Concurrent enqueue calls could overwrite each other, and completion of a network
cleanup batch could erase newly queued deletions. Queue writes and batch merges
now share one local lock; Storage requests run outside it. A replacement request
for the same path gets its own queue identity and survives the older batch.

Enqueue pins the originating account and action timestamp before initialization
and lock waits. Failed cleanup requests retain their error and original action
time, with a persisted retry deadline (20-second exponential backoff capped at
20 minutes, or 20 minutes for non-retryable errors). Existing scheduling respects
that deadline; no listener/timer is added. Object-not-found still counts as a
successful cleanup. Concurrent flush callers await the same active operation.

Storage paths remain exact literal paths, not document IDs to renumber. Six
regression cases cover concurrent enqueue, in-flight additions/replacements,
account switching during a local write, failed-work persistence/backoff across a
queue reopening, and already-missing objects. Tests use fake Storage; live
permissions and real multi-device/browser restart acceptance remain unverified.

### Follow-up: support read markers using provisional users

Existing shared resolvers already cover offline users, vehicle catalogs, status
forms/fields/statuses, chassis and bookings. A remaining read-marker dependency
was fixed: its queue target is a local composite `user:thread` key, not a remote
record ID. Replay now validates/remaps the actual `payload.user_id` without trying
to resolve that composite key as a standalone temporary ID. Unresolved users stay
queued, and a successful replay writes only under the confirmed user ID.

The support request also queues read markers for temporary users even when the
network has returned. The original read-action time is captured before local
cache awaits; thread/message identities stay unchanged. Three regression cases
cover create-and-marker replay after queue reopening, unresolved users, and the
online request path with a temporary user. Existing occupied users receive no
marker writes from another provisional identity.

### Follow-up: repeated offline photos and delayed read actions

Profile/license upload entries retain an optional `previous_upload_id` when their
original preview exactly matches an earlier queued photo for the same user/field.
Legacy queue entries get these links persisted before replay removes predecessors.
Each successful photo patch atomically stores a small per-field receipt in
`users.offline_photo_uploads` (upload entry ID and resulting URL). A replacement
can follow only its exact predecessor receipt while the current photo still equals
that receipt's URL. Unrelated remote changes cannot authorize replacement. Failed
or unverifiable chains stay queued with the existing backoff; acknowledged retries
do not restore old photos. Preflight checks avoid uploading known-blocked/already
acknowledged work, and the transaction repeats the checks before the final patch.
Original action timestamps and existing user IDs remain unchanged. A legacy
already-committed predecessor without a verifiable receipt may remain pending;
the code does not infer ownership from a similar URL or timestamp.

Direct and replayed support read-marker writes share a transaction that preserves
newer server action timestamps. Equal timestamps preserve the existing marker;
missing/invalid incoming timestamps cannot replace a valid dated server marker.
Queue coalescing also preserves a newer pending read action against a delayed older
enqueue. This comparison uses captured device action time, not sync time; it does
not correct device clock skew.

New tests cover profile and license replacements, enqueue during upload, lost
acknowledgement with a persisted receipt, failed predecessors, unrelated server
photo changes, read-marker timestamp ordering and delayed offline replay. These
are fake-backend regressions, not live Storage/Firestore permission verification.
No new timers, listeners, or automatic retry loops were added.

### Three-photo replay after lost batch acknowledgement (resolved locally)

A focused fake-Firestore probe reproduced a remaining media edge case: queue
photos A -> B -> C all commit, but the browser restarts before the local batch
acknowledgement is persisted. The server keeps only C's per-field receipt. On
replay A and C are acknowledged/skipped, but B remains queued with a predecessor
error. The server correctly retains C; this is a stuck pending entry, not an ID
collision or an overwrite. Existing backoff limits retries but cannot prove B
already committed. This finding is now patched using the exact pending
predecessor chain and the latest committed receipt; see the final follow-up below. The temporary audit probe was kept outside the suite
at /tmp/offline_three_photo_audit_probe.dart; its assertion documented the observed
remaining B entry, not a successful fix.

### Cross-role request-path findings (resolved locally)

These findings are now patched locally and regression-tested as described below.
They have not been exercised with live role accounts:

- Admin/authorized account deletion: online deleteUser scheduled linked
  client_members and user-asset cleanup, while the queued userDelete replay only
  deleted users/{resolvedId} and published the users version. Offline deletion could
  therefore leave linked membership rows and uploaded assets behind.
- Admin/authorized billing updates: once the browser reports online, both single
  and bulk billing request paths required an immediate temporary-booking resolution.
  An unresolved pending create caused an exception instead of keeping the billing
  action queued behind that create. The offline branch already supports queueing.
- Shared support sending: sendMessageWithAttachments selected its direct path using
  connectivity alone. sendMessage then wrote sender/requester/booking references
  from cached thread/user models without the scoped temporary-reference mapper.
  Reconnecting before the referenced booking/user create resolved could persist a
  temporary reference through this direct path, bypassing media queue resolution.

These affect the shared request paths used by whichever roles have access, rather
than proving a separate defect for every role. The previously reproduced
three-photo acknowledgement finding is also fixed locally. Driver/helper workflow
regression coverage does not constitute a complete live multi-role acceptance test.


### Final targeted follow-up: acknowledged photos, deletes, billing and support

- Photo recovery walks only the persisted pending predecessor chain from the
  latest committed per-field receipt. Each traversed entry must match the user and
  photo field; missing links stop verification and a visited set bounds cycles.
  Already committed ancestors are acknowledged without uploading/restoring old
  photos. No growing server receipt history or extra listener is introduced.
- Queued user deletion rechecks membership ownership inside transactions of at
  most 100 candidate documents, deletes only that user's matching/legacy direct
  membership rows, then deletes the user. Asset cleanup is handed to the existing
  cleanup queue under the originating account scope and original delete time. A
  handoff failure retains the mutation for retry; Storage deletion remains pending
  until the cleanup queue completes it. Unrelated memberships are preserved.
- Single and bulk billing requests retain temporary booking IDs in the queue after
  connectivity returns, rather than requiring immediate resolution. Original
  action time is passed through replay and the local cache. Queueable online write
  failures also fall back to that queue. Confirmed ID behavior remains unchanged.
- Support sends check sender, requester/parent and booking references before
  uploads/direct writes. Temporary dependencies use the existing media queue;
  direct send also guards against unresolved references. Replay updates existing
  requester references only when they still match the exact original temporary
  identity; a changed recipient stays pending rather than being reassigned.

Ten added regression cases exercise these paths, including lost batch
acknowledgement, cross-user/field isolation, reconnect billing, membership
ownership, cleanup handoff failure/account switching, pending booking support,
and conflicting requester identities. All tests use fake cloud services; live
permissions, actual multi-device contention, and authenticated role acceptance
remain unverified. The unrelated Chrome DOCX template-test timeouts remain outside
this offline/ID-resolver fix scope.

Ordinary queued user updates and SDK user-document replacement also preserve the
existing offline_photo_uploads receipts inside their transactions. Web REST user
patches already update only their listed fields. This prevents an account edit
from erasing the proof required for later photo-batch acknowledgement recovery;
other full-replacement field semantics are unchanged.

### Queued action visibility

Authenticated shells show offline/pending status above the page content at all
widths, including when the navigation drawer is closed. View queued actions reads
only the current account's four persisted queues on demand. The selectable dialog
uses lazy rows, readable action/record labels and local saved times; temporary IDs
are described as pending sync. Refresh is explicit, with no new polling or remote
reads/writes. Queue inspection does not initialize sync, publish status events,
modify payloads, or change resolver/replay behavior. The list is a local snapshot,
not server acknowledgement. Existing conflict review controls remain available.
