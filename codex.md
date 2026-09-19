# PALTRANCO Development Basis

This file is the working basis for succeeding development in PALTRANCO.

Use this as the project-wide source of truth for:

- architecture direction
- naming consistency
- MVVM expectations
- shared widget strategy
- UI consistency
- responsiveness rules
- data-library direction
- current important feature decisions

## Project Scope

PALTRANCO is a trucking and logistics MVP.

Current known roles:

- `client`
- `admin`
- `driver`
- `helper`

## Global Development Rules

### Architecture

Default architectural direction:

- `View` handles UI
- `ViewModel` handles state and UI actions
- `Repository` handles persistence and data access
- `Service` or `Engine` handles business logic when logic is reusable or domain-heavy

Do not put substantial business logic directly inside widgets unless it is purely presentational.

### Consistency

Before introducing a new UI pattern:

1. check if an existing shared widget or pattern already exists
2. reuse shared primitives first
3. extend shared primitives if the new case is close enough
4. only create a new one-off widget when the behavior is intentionally different

### Shared-First Rule

As much as possible:

- shared widgets
- shared layout shells
- shared action buttons
- shared modal shells
- shared measurement helpers
- shared responsiveness logic

If two screens are meant to feel the same, prefer one shared implementation over two similar local implementations.

### Naming

Keep naming aligned with existing code and domain language.

Prefer:

- `StatusForm`
- `StatusField`
- `StatusDefinition`
- `status_outputs`
- `client_status`
- `driver_status`
- `helper_status`

Avoid introducing alternate terms for the same concept without a strong reason.

### IDs

Use numeric string IDs only, starting from `1`, unless a different format is explicitly required by a real external backend.

Current rule applies to:

- users
- forms
- fields
- statuses

Examples:

- `id: "1"`
- `id: "2"`

Machine keys may still be non-numeric where appropriate, such as:

- `field_1`
- `pending`
- `documents_ready`

But `id` should stay numeric.

Offline bookings temporarily use `offline_booking_...` locally. On sync, the
booking transaction allocates the next unused numeric ID at or above the counter.
`BookingIdResolver` verifies the exact submission key against both `manage_id`
and the confirmed booking before resolving a temporary reference. Never infer
identity from waybill numbers, names, timestamps, or row order. Only known
historical generated key formats may be reconstructed for lookup.

Booking retries must not overwrite a committed booking or move the counter
backwards. The reservation keeps the original submitted document for exact retry
comparison; divergent legacy retries remain blocked for review. Resolve only
explicit booking reference fields, preserving notes and form values. Conflicting
legacy temporary/numeric rows must not overwrite each other. Preserve divergent
temporary records under a separately allocated numeric ID and submission key.
Offline chassis conflicts retain pending work rather than steal assignments.

## MVVM Rules

### Views

Views should:

- compose widgets
- wire callbacks
- show dialogs
- render responsive layout states

Views should avoid:

- persistence logic
- complex domain validation
- reusable business rules

### ViewModels

ViewModels should:

- expose state for the view
- mutate state in response to UI actions
- call repositories and services
- own loading, success, and error state

### Repositories

Repositories should:

- abstract data source details
- support mock-first development when backend is not ready

### Services / Engines

Use a service or engine when logic is:

- reusable
- domain-specific
- too complex to keep inside a ViewModel cleanly

## Shared UI Rules

### Initial Home Startup

- Use `StartupSplashHandoff` for non-admin home pages. Signal readiness after
  essential data resolves, including confirmed empty and error states.
- Driver assignments require bookings and chassis return assignments; helper
  assignments require bookings. Users and status labels refresh in the background.
- Start broad non-admin warmup after the initial home resolves. Preserve form
  and option loading requirements for the client booking form.
- Never treat an unresolved empty cache as a confirmed empty assignment list.

### Returning From Background

- Keep the mounted page and unsaved forms intact during foreground recovery.
- Use `AppResumeRecovery` to debounce recovery; never force a page reload or
  recreate Firestore merely because the browser was backgrounded.
- Automatic queue polling pauses while hidden; foreground recovery retries
  durable queues with their existing conflict checks and write ordering.
- Only full-state snapshots may be coalesced. Never drop queued user mutations.
- Cache storage operations must have a bounded timeout, abort stale transactions,
  and recover their connection without deleting pending user actions.

### Typography

Default text baseline across the app:

- `TextStyle.height` should be `1.2`
- if a text needs a different line height, that should be an intentional exception rather than the default

### Main UI Copy

For main UI screens:

- default to no helper subtext
- avoid descriptive subtitle paragraphs under section titles
- avoid extra explanatory copy inside primary content areas unless the user truly needs it

Subtext should be treated as optional and used sparingly.
This rule is stricter for main UI screens than for builder-style admin screens like `Forms` and `Fields`.

### List Screens

When multiple admin list screens are intended to feel the same, they should follow the same list-screen structure:

1. `Search / Filters / New` toolbar
2. titles row container
3. content rows below
4. responsive card fallback on narrow widths

### Shared Primitives

Current shared UI primitives that should be reused first:

- `lib/widgets/shared/admin_list_primitives.dart`
- `lib/widgets/admin_modal_shell.dart`
- `lib/widgets/shared/admin_icon_action_button.dart`

Current shared list primitives include:

- toolbar shell
- search field shell
- filters button shell
- new button shell
- title/header container bar
- fixed slots
- header cells
- body cells
- responsive field item
- action button primitive
- status/meta pill
- text measurement helpers

### Responsiveness

Primary baseline for admin list responsiveness:

- `Users`

Other matching screens should follow the same direction:

- measured column widths on wide layout
- only selected text-heavy columns become flexible when width gets tight
- narrow layout falls back to card view
- card field widths are content-based, not arbitrary fixed-breakpoint-only widths

### Positioning And Spacing

Prefer:

- consistent top toolbar spacing
- consistent titles-row spacing
- consistent card padding
- consistent button sizes
- consistent modal footer alignment

For scrollable admin-home sections:

- outer shell/body padding should not own the section content inset
- section content padding should live inside the section's own scroll/content area
- this keeps the vertical scrollbar at the outer edge while preserving the intended visible content spacing

If a spacing decision is intentionally changed, update this file.

### Input Focus Behavior

For all textfields and dropdowns across the app:

- tapping outside the focused field should unfocus it
- this should be treated as app-wide default behavior, not a one-off per screen unless a screen intentionally needs different focus handling

### Name Fields

For all editable `Name` fields across the app:

- while typing, first letters of each word should auto-capitalize
- on save, names should still be normalized to caps on first letters per word as a fallback
- this applies to current user/auth flows and should also be followed by future screens that introduce name inputs

### Branding Header Rule

For branded auth and similar hero headers:

- use the brand mark and name stack directly
- prefer:
  - `PALTRANCO`
  - `Digital Platform`
- `Digital Platform` should be slightly smaller than `PALTRANCO`, readable, and not bold
- do not place an extra `SizedBox` spacer between those two text lines
- do not add helper subtext below that two-line brand stack

Keep the header minimal, premium, and consistent with the current purple PALTRANCO branding.

## Shared Action Rules

### Action Set

Expected list action patterns where applicable:

- `eye` for preview/view
- `edit`
- `activate/deactivate`
- `delete`

### Action Colors

Use these meanings consistently:

- view: yellow
- edit: primary color
- activate: green
- deactivate: red
- delete: red

### Action Layout

On wide list rows:

- action buttons should not wrap if the row is still in wide mode

On narrow cards:

- wrapping is acceptable

## Modal Rules

All admin dialogs and modals should follow the shared modal shell unless intentionally different:

- white background
- same sizing logic
- same footer area behavior

Use:

- `lib/widgets/admin_modal_shell.dart`

### Modal Content Rules

- normal fields should use side padding inside modal content
- toggle rows may intentionally follow their own row layout rules

### Footer Rules

Prefer simple footer actions:

- `Cancel`
- `Save`

For read-only modals:

- `Close`

## Admin-Specific Basis

### Admin Sections

Current admin sections:

- `Dashboard`
- `Bookings`
- `Settings`
- `Users`

Current `Settings` sub-sections:

- `Forms`
- `Fields`
- `Statuses`

### Admin Shared Responsiveness Rule

`Users`, `Forms`, `Fields`, and `Statuses` should feel structurally the same in layout and responsiveness.

Shared responsiveness may stay the same while allowing a unique lead item in narrow cards:

- `Users`: photo + actions
- `Forms`: status pill + actions
- `Fields`: active pill + actions
- `Statuses`: active pill + actions

## Forms / Fields / Statuses Direction

### Statuses

`Statuses` is the reusable status library.

It answers:

- what statuses exist
- which roles can use or reference them

It should not contain:

- transition logic
- dependency logic
- hardcoded hierarchy such as client -> driver -> helper

Recommended status shape:

- `id`
- `key`
- `label`
- `description`
- `applicable_roles`
- `sort_order`
- `is_active`
- `created_at`
- `updated_at`

### Fields

`Fields` is the reusable field library.

It answers:

- what reusable form fields exist

Fields are assignable to forms.

### Forms

`Forms` defines:

- role
- current status
- next status
- assigned reusable fields
- dependencies
- blocked message

It answers:

- who can move from which status to which next status
- what fields are required for that transition
- what dependencies must be completed first

### Booking Status Structure

Booking uses only:

- `client_status`
- `driver_status`
- `helper_status`

There is no `admin_status`.

Dependencies should be handled in `Forms`, not in `Statuses`.

## Validation Direction

### Users

Required:

- role
- email
- name
- phone
- password

### Fields

Each field should have:

- key
- type
- title

### Forms

Required:

- role
- current status
- next status
- status text
- button text

If dependencies exist:

- blocked message is required

### Statuses

Should validate:

- key required
- label required
- key unique

## Current Important Files

### Shared UI

- `lib/widgets/shared/admin_list_primitives.dart`
- `lib/widgets/admin_modal_shell.dart`
- `lib/widgets/shared/admin_icon_action_button.dart`

### Admin Views

- `lib/views/admin/admin_home.dart`
- `lib/views/admin/admin_users.dart`
- `lib/views/admin/admin_forms.dart`
- `lib/views/admin/admin_fields.dart`
- `lib/views/admin/admin_statuses.dart`

### Admin ViewModels

- `lib/view_models/admin/admin_home.vm.dart`
- `lib/view_models/admin/admin_status_form.vm.dart`

### Models

- `lib/models/status_form.dart`
- `lib/models/status_field.dart`
- `lib/models/status_definition.dart`
- `lib/models/user.dart`

## Rule For Succeeding Work

Before adding or changing any feature:

1. check this file
2. reuse shared primitives first
3. follow MVVM
4. keep naming consistent
5. keep IDs numeric where current project rule expects it
6. keep responsiveness aligned with the established screen family when the feature belongs to that family
7. update this file when a real project rule changes

## When This File Should Be Updated

Update this file when:

- a shared UI rule changes
- a new shared primitive is introduced
- a naming rule is finalized
- an architecture decision is finalized
- action meanings or color rules change
- data model direction changes
- a project-wide convention is intentionally changed

### Booking identity resolver resource limits

The resolver is demand-driven and has no snapshot subscription or periodic retry
timer. A shared gate per Firestore instance coalesces identical in-flight lookups,
limits reads to four concurrent lookups and sixteen starts per minute, and retains
at most 256 backoff entries. Missing mappings/errors back off from 30 seconds to
15 minutes. Only queue activity requests another lookup; elapsed time alone does
not start one. A 30-second caller timeout keeps ownership of an unfinished SDK
read to prevent accumulating duplicate reads. Confirmed offline creates and
explicit conflict retries invalidate their ID's backoff without cancelling active
reads. Numeric IDs bypass the gate. Existing queue scheduling remains separate.

### Existing Firestore booking ID repair

`LegacyBookingRepairService` runs from existing server-confirmed booking snapshots
only when actual document IDs begin with `offline_`, and only for an online admin.
It adds no listener or periodic retry; it is not awaited by startup. It attempts
at most 256 IDs per service lifetime, sequentially, with at most three transaction
attempts per repair. Network failures are deferred until a later app session.

Exact submission identity is required. An existing numeric counterpart must match
all business fields (only ID, updated_at, and local queue metadata are ignored).
Timestamp-only differences are archived without replacing canonical data. An
orphan with a verified submission key can receive the next unused numeric ID.
Missing reserved targets, ambiguous identity, and inconsistent chassis assignments
remain untouched for review. Divergent contents with a verified occupied target
are preserved as a separate booking under a new unused, unreserved numeric ID. Never auto-select the newest
status or merge by waybill.

Repairs archive original documents under
`booking_id_repairs/{temporaryId}/snapshots/{source,canonical}` and atomically
write the numeric booking/reservation, update explicit chassis/support references,
and remove the temporary document. Storage paths and arbitrary form strings are
preserved. Completed/conflicting reports are not automatically reprocessed.
`needs_review` reports contain a reason and differing business fields when known;
operator reconciliation must review both source documents and references. This
path does not apply a human decision about conflicting statuses. Results are
printed as `[Booking ID repair] ...` in the app console. Old pending deletes for
temporary IDs must never be redirected into deleting a canonical booking.

### Admin conflict comparison and explicit reconciliation

Admin Bookings shows `Review offline booking conflicts` when temporary bookings
are present. Opening the modal performs one-time server reads, with manual refresh
and no new subscriptions. The view uses a dedicated review ViewModel and service.
It shows live differences, full records/history, and requires an explicit version
choice plus acknowledgement. No version is preselected.

`Keep numeric booking data` preserves the canonical document. `Use temporary copy
data under numeric ID` replaces business data only for supported assignment-stage
corrections (pending/assigned in the same stage or assigned-to-cancelled without a
chassis). Other transitions require workflow review. Original numeric creation time
and ID are retained. History is not silently combined: both pre-decision records
are archived under `booking_id_repairs/{id}/decision_snapshots`. The report records
resolution, acting admin, and time. Referenced chassis/support data is rechecked;
other bookings' chassis cannot be taken. Entire source/canonical documents, report,
reservation and known references must still match the preview transactionally.
Stale comparisons require reload. The apply transaction checks the admin user role.
No live reconciliation occurs until the admin applies their chosen version.

The shared `AdminModalShell.flexibleBody` option is enabled for conflict review so
wrapped titles and actions leave the remaining height for scrolling. Other dialogs
retain the existing layout by default.

### Copyable modal text

App-owned dialog and bottom-sheet routes wrap their contents in `SelectionArea`,
including direct nested search pickers, sync conflicts, and booking ID review.
The page selection region does not extend into navigator overlays. Prefer normal
`Text` inside these regions for continuous multi-field selection; text inputs keep
their native editing/clipboard behavior. Modal guard and dismissal semantics stay
unchanged.

### Booking creation identity and ordering

Bookings lists default to `created_at` descending, including local inserts and
realtime refreshes. Missing creation dates go last. IDs are only tie breakers;
updates and delayed sync must not move an old booking above a newer creation.
The driver/helper assignment work queue keeps its separate existing ordering.

A failed form submission retains the original booking, creation time and event
history only while the submitted inputs, client, actor and form remain the same.
Changed inputs or an explicit clear start a new submission identity. Normal
edits keep the existing booking ID. A direct online create cannot overwrite an
existing numeric document, even if an old reservation returns that ID.
Unused numeric IDs are allocated at or above the counter; gaps are acceptable.
Existing ambiguous legacy pairs still require review, not automatic duplication.

### Foreground recovery workload

Foreground recovery gives the existing booking listener a two-second grace period.
A recent confirmed snapshot or one received during that grace suppresses a fallback
collection read. Only one recovery owns an unfinished fallback; going offline or
hidden cancels the pending fallback. Resume no longer calls enableNetwork on an
already active Firestore connection. It flushes only initialized queues with known
pending work; normal enqueue, initialization and periodic queue discovery remain.

Retry snapshots privately copy each Uint8List photo once per new submission and
reuse its unmodifiable view in retained inputs and returned booking payloads.
Nested maps remain isolated; changed input bytes still create a new submission.
Numeric-only booking snapshots bypass temporary-copy reconciliation allocations.

### Occupied booking IDs: preserve both records

Legacy repair policy v2 revisits old content-difference reports once per session.
When a verified temporary booking conflicts with an occupied numeric target,
allocate another ID atomically using the shared counter, skipping existing booking
and reserved IDs. Preserve the occupied booking and its reservation unchanged.
Process temporary records by original creation time ascending; the list remains
creation time descending. Existing original creation/update times, status, form
history and photo paths remain intact on the newly numbered copy.

A distinct `booking_split_<temporaryId>` submission key and reservation belong to
the new document. The durable repair report maps the original temporary identity
to this new key/ID, and the resolver verifies that mapping before using it.
Archives are kept in `split_snapshots`; only references still pointing exactly to
the temporary ID are remapped. Chassis owned by another booking still block repair.
An old queued create for a split record stays blocked for explicit review instead
of replaying into the occupied numeric booking. Other review reasons are not
repeated automatically. This adds no listeners or periodic retry tasks.

### Booking van-number sizing

Measure rendered widths instead of character counts for the Van Number column.
Use the bounded TextWidthCache (256 entries) to reuse unchanged metrics across
rebuilds, keyed by text, effective style, text scale, direction and locale.
Dispose each temporary TextPainter after measurement. Van-number table cells
remain single-line; the existing table-to-card breakpoint uses the measured width.

### Offline workflow action time

Existing-booking workflow submissions save a durable local mutation before
returning success, including when connectivity appears online. Preserve one
captured action time for status history, delivered_at and updated_at. Retry an
unchanged failed submission with its original event and remote base version;
changed inputs create a fresh action. Local action/base markers are excluded from
Firestore documents. Confirmation failures release loading and display errors.

Photos queue separately and wait for the matching server-side pending marker.
Upload completion writes media_synced_at rather than changing the booking action
time. Support message retries reuse their queue ID as the message document ID;
older offline messages must not replace a newer thread preview. Resolve temporary
booking references only through the existing verified ID resolver during sync.

### Shared offline resource identity

See docs/offline-write-audit.md for the audited request paths and boundaries.
Non-booking offline creates use a provisional-ID-scoped reservation key, preserve
created/updated action times, and record committed payloads in their reservations.
Retries never overwrite occupied IDs or restore old snapshots over later edits.
Generic update version checks and writes run in one transaction.

OfflineReferenceMapper remaps only explicit schema references, including form
field IDs and override keys. Never recursively replace arbitrary strings in form
answers or notes. Unresolved dependencies remain queued. Aliases are persisted per
queue user scope and reused by media sync without adding listeners or timers.
Serialize queue mutations and flush-result merges while keeping network work
outside the local queue lock. Preserve the first remote base version when
coalescing updates and the original assignment when coalescing chassis edits.


### Offline chassis references and account switching

Chassis.bookingReferenceId and driverReferenceId preserve numeric or temporary
identities as strings. Keep the legacy integer constructors/accessors; toMap emits
numeric IDs as integers and temporary IDs as strings. Editors, labels, navigation
and role assignment checks use the reference getters. New offline chassis use
negative IDs, never a locally guessed next positive ID.

Chassis replay checks the original version and current booking ownership inside
the transaction. A conflicting remote assignment stays pending for review.
Queue writes pin their originating user scope across awaits, including mutation,
media and booking-photo queues, so account switches cannot redirect local writes.
Provisional chassis deletes wait for the committed create alias and detach only
booking links still owned by that chassis.

### Mutually linked offline creates and edits during sync

When a queued booking create and a queued provisional chassis create explicitly
reference each other, commit the pair in the booking transaction. Match only
exact queue identities and both reference fields; never infer a pair by name,
waybill, or date. Reserve the chassis ID using its existing submission identity,
verify ownership and vacancy inside the transaction, and preserve each record's
own action dates. Record the linked source payload in the reservation so a retry
after lost acknowledgement cannot overwrite subsequent edits.

An edit arriving during a successful chassis create becomes an update against
that committed create's original version, with the same resolved ID. Ordinary
remote conflicts still require review. Booking-photo enqueue captures its user
scope before image processing, not after the CPU/async preparation step. These
paths add no timers or listeners; they run only for existing pending work.

Media queue flush-result persistence must use the same local mutation lock as
media enqueue. Never discard upload bytes solely because an exception is classified
as non-retryable. Persist the error and retry deadline; repeated queue checks must
respect backoff without adding timers, and preserve the original action date.

### Deletes of pending offline resources

Route temporary user/catalog/status/form/field deletes through the mutation queue
regardless of current connectivity. Keep the pending user create until its exact
confirmed identity is known (it may already be in flight), then apply its delete
through the persisted alias. Never delete a raw unresolved `offline_` or negative
resource target. Preserve ordinary confirmed-ID behavior and booking-specific
canonical-delete protections.

File-cleanup queue enqueue and flush-result merges share one local mutation lock.
Capture account scope and action time before awaits. Preserve newly queued or
replacement cleanup identities during sync, retain errors with persisted retry
backoff, and let concurrent flush callers await the active operation. Treat Storage
paths literally; never apply numeric document-ID resolution to arbitrary paths.

Support read-marker queue targets are local composite keys, not numeric resource
IDs. Resolve their payload.user_id through the scoped aliases; do not classify the
entire user:thread target as an unresolved document ID. Queue temporary-user read
markers even online and capture action time before local cache awaits.

Repeated offline user-photo uploads link exact preceding preview/queue identities.
Persist optional previous_upload_id before removing predecessors; atomically record
per-field offline_photo_uploads receipts with the final photo patch. Only a receipt
matching both predecessor identity and current URL authorizes the next photo;
never bypass a remote change based on timestamps. Keep unverifiable work pending.
Use the shared support read-marker transaction for both direct writes and replay,
and never coalesce an older action over a newer pending read-marker timestamp.

To acknowledge older queued photos after a lost batch acknowledgement, walk the
exact persisted predecessor chain from the latest server receipt, checking the
same user and field and bounding cycles. Do not infer by timestamp or retain an
unbounded server history. User-delete replay must verify linked membership owners
and durably hand asset cleanup to the originating scoped cleanup queue before
acknowledging success. Billing and support requests must continue queueing temporary
references after reconnect; existing support requester links may only be remapped
when they still match the original temporary identity.


### Support notifications

Support incoming-message notifications cover all six current roles. Foreground
thread updates show a shared snackbar and play sounds/sound.mp3. Foreground FCM
also handles messages received after offline replay; a bounded, session-scoped
256-entry signature set deduplicates the thread and push paths. Initial thread
snapshots remain silent and sender echoes are excluded. The FCM subscription is
cancelled on stop and reused during the session; no polling timer is added.

The notifySupportMessage function triggers only on support/{threadId}/messages
creation. Recipients match inbox visibility: active admin/manager/dispatcher users
plus the active requester, excluding the sender. Parent clients and unrelated
client/driver/helper accounts are not recipients. Payload previews are bounded;
visible background notifications use generic text. Original action timestamps
remain unchanged. Background delivery requires deployment of the function and
notification permission; the service worker uses browser/OS notification audio,
not custom MP3 playback. Function deployment is separate from building the web app.

### Sync status feedback and retry overhead

Queue readScopedStatuses must remain observational after initialization: do not
call initialize again there, because its status refresh emits events that trigger
another aggregate scope read. This previously formed a self-sustaining feedback
loop through OfflineSyncStatusService. Keep queue events for changes in other
account scopes, coalesce aggregate reads with LatestValueWorker, and notify the
current UI only when the merged status changes.

Media and cleanup queues with no due entries must preserve their stored payloads
without rewriting or announcing active syncing. This also applies after reopening
while a persisted retry deadline is in the future. Keep deadline checks, scoped
ownership, original action times, and concurrent-enqueue merge safeguards.

### Web engine view teardown guard

The app starts with AppWidgetsBinding. Its sendFramesToEngine gate checks the
public platform dispatcher registry against the exact FlutterView objects used
by framework RenderViews. A removed view, including an old object whose ID was
reused, cannot submit graphics/semantics to the engine. Registered views resume
normally without a sticky flag. Preserve the superclass first-frame gate and
native behavior. Do not suppress engine assertions, auto-reload the page, clear
local storage, or patch the shared Flutter SDK to handle this condition.

The window.dart:99 disposed-view assertion was reproduced in isolated headless
Chrome during hot restart, before this guard. Repeated restarts after the guard
no longer emitted it, and the login UI still rendered. This establishes coverage
for that restart path, not every possible GPU/browser crash or authenticated flow.

### Admin Fields key widths

Measure every distinct field key with its inherited rendered text style using
the bounded TextWidthCache. Do not proportionally compress the measured Key
column to fit the viewport. Table headers and rows share the measured widths;
the list switches to responsive cards if those widths do not fit. Keys remain single-line and fully
accessible, including responsive cards via the opt-in singleLine field rendering.
Other responsive field values retain their existing wrapping behavior.

### Retained navigation rendering

AdminHome and RolePlatformHome use RetainedSectionStack. Keep the existing
bounded page-retention policy and child identity, but disable tickers on hidden
sections and isolate each section's repaint work. Derive wrapper ValueKeys from
child keys rather than reusing GlobalKeys. Do not dispose hidden pages or disable
their data subscriptions: drafts, scroll positions and live data must survive
navigation. This reduces hidden animation/paint work; IndexedStack still performs
layout and this is not a claim that all scrolling or hot-restart lag is resolved.

### Lazy admin bookings list

The bookings overview uses one CustomScrollView with a toolbar/state sliver and
AdminBookingsListSliver. Both responsive cards and wide table rows use lazy
SliverList builders. Do not nest a shrink-wrapped full list in an outer Column:
that eagerly lays out every booking again. Keep table-wide content measurements
outside scroll-time SliverLayoutBuilder callbacks so scrolling alone does not
rescan the dataset. Preserve the existing filters, order, row actions and separate
booking-detail scroll path. Tests cover 1,000 bookings at narrow and wide widths.


### Lazy data lists across roles

Use LazyDataScrollView with SliverSection and LazySliverList for long read-only
record lists. This now covers dashboard completed bookings, Users, Chassis,
vehicle catalogs, Flow catalogs, client history, assigned driver/helper bookings,
profile booking history, and grouped support conversations. Existing staff
support and message builders remain lazy. UserBookingsSection produces a sliver;
its profile and user-detail hosts must place it in a SliverSection.

SliverWidthBuilder caches width-dependent table construction while scrolling,
and invalidates for new widget data, viewport width and inherited text/theme
changes. Snapshot filtered lists before building lazy rows, so each row does not
repeat filtering. Wide tables fall back to responsive cards where measured
columns cannot fit. The export modal keeps its form controls mounted and gives
its booking candidate list a bounded, separately scrollable viewport.

Do not virtualize editable/reorderable forms or fixed navigation/control groups
just because they contain Columns. Preserve form values, validation and focus.
This rendering change does not change repository operations, offline queue or ID
resolution behavior, and does not add timers or database listeners. Widget tests
use 1,000-row fixtures; authenticated release profiling is still needed to
quantify production performance and investigate remaining non-rendering costs.


The Access role catalog and booking conflict review now also use lazy slivers.
AdminModalShell.bodyHandlesScrolling opts a dialog into a bounded child viewport;
its default preserves the existing form scroll behavior. Sync Review uses a
bounded ListView without shrinkWrap. Full conflict JSON records are constructed
when their expansion is opened. Keep review choices, acknowledgement and write
permissions in the existing view model; virtualization must not bypass them.

### Shared booking processing and display windows

BookingRequest.watchBookings uses SharedReplayStream so retained pages share
cache processing as well as the remote listener. The replay is released with the
last observer and each new session uses the existing cache trust rules. Keep
emitted lists immutable. Booking/dashboard filters cache their results until a
view-model notification invalidates them. Diagnostic strings must stay lazy.

PagedDataSliver bounds Bookings and Dashboard presentation to batches of 15, with pull-up loading instead of a button;
filter over all records first and never use the display subset for export or
reconciliation. Preserve its PageStorage window across detail navigation and
reset on changed filter criteria. This is not server pagination: never limit the
shared authoritative collection snapshot without separating partial-page cache
semantics from complete offline/reconciliation snapshots. See
`docs/booking-data-performance.md` for the remaining data-layer work.

### Booking chassis replay safety

Project chassis state from the final booking stage, not an exact prior-stage
pair: offline updates coalesce and retries can repeat a stage. Delivered/Check
clear the driver but retain the booking and loaded state. Confirm/Cancelled clear
both links only when the chassis still belongs to that booking. Historical chassis
references must never reclaim or release another booking's asset. Preserve queued
action timestamps and existing identity/version conflict checks. The scheduled
Delivered-to-Check write must transactionally recheck the live status and deadline
so a stale query cannot overwrite a subsequent stage.

### Failed support message recovery

Queued Actions automatically attempts failed-chat recovery once when opened online
for the active account. There is no manual retry button. Busy/offline opens skip
recovery; repeated opens for the same account have a 30-second cooldown with no
new timer or listener. Rebuilds and Refresh only read the queue. Empty/no-failure
queues are not rewritten. Recovery only advances failed support-message deadlines,
retaining message IDs, original
action dates, payloads and normal transaction checks. Automatic retry backoff stays
unchanged. Debug builds log the replay failure stack without logging message bodies.
Queue modal text uses individual SelectableText cells rather than a shared
SelectionArea over the changing lazy list. Status remains the wrapping column.
The captured other[$forEach] replay stack fails in OfflineReferenceMapper's
Map.from copy before sender-reference resolution. That path and the no-alias
return now copy via keys/indexed access, as do support replay thread copies.
The snapshot documentData conversion also avoids forEach. Preserve all values
(including native Firestore values); never use an empty-map fallback or JSON
round-trip. Regression fixtures explicitly fail forEach and exercise normal and
temporary references. This removes the observed dispatch dependency, but is not
a verified fix for the broader hot-restart runtime/shader failure. Never clear
local storage as a recovery step.

Queued Actions listens to the existing sync-status notifier only while mounted.
On idle status changes it re-reads all four account-scoped queues and closes its
current dialog route only when the read succeeds with no remaining actions.
Failed/pending actions keep it open. Stale reads cannot close the route; the
listener is removed on dispose. No polling timer or extra sync retry is added.

The sidebar sync status is tappable for every signed-in role, including offline
and non-failed pending work. It opens that account's Queued Actions; failed-action
conflict review still requires sync.read. Do not gate read-only queue inspection
on conflict-review permission or the presence of an error.

The later runtime log also fails at rawData.keys and cloud_firestore_web's
decodeMapData updateAll. The key-copy workaround is therefore not a complete
fix for the reported runtime failure; avoid claiming otherwise or successively
replacing SDK map operations without reproducing the underlying runtime issue.

### Optional field type history

Flow text/email/phone/number inputs and chassis name/location use the additive
TypeHistoryInput wrapper. Preserve the underlying controllers, validators, phone/
casing formatters, and save behavior. History is written only after a successful
business save; failures must remain isolated. No typing-time Firestore query or
write is introduced. See `docs/field-type-history.md` for bounds, exclusions, and
the pending security/scope decision that prevents private Firestore history from
being enabled under the current allow-all rules. Existing schema options work.

Search dropdown pickers keep SelectionArea inside the bounded Dialog child,
not around the entire route. Outside taps dismiss only the picker, preserve the
prior value, and never invoke onChanged. Keep the local navigator for nested
forms. Reproduced at 375/1200 widths before the fix; regression checks also cover
filtering and selecting after dismissal.

All current dialogs and bottom sheets support outside-tap dismissal. Shared
showAppDialog defaults to no route-wide SelectionArea; AdminModalShell selects
inside its own Dialog by default. Standalone image/camera/user dialogs use
AppSelectableDialog, while alert text is individually selectable. Keep selection
inside modal surfaces. Booking-conflict review allows dismissal while busy; its
view-model disposal guard protects late notifications. Dismissal does not cancel
a business operation already in flight. Tests cover forms, confirmations, custom
dialogs, sheets, nested search, selection, and late confirmation completion.

Chassis history status pills use the shared booking-to-chassis lifecycle
projection (Delivered/Check = Loaded), not raw booking stages. Unknown stages
show no inferred chassis state. Waiting/claim durations omit a zero-hour prefix
(e.g. 5m); durations of an hour or more retain hours and minutes.
