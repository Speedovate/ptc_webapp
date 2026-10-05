# PALTRANCO engagement reconstruction

Research report · October 4, 2026 · Asia/Manila

This is an evidence reconstruction, not a presentation, recommendation ranking, or production endorsement. Repository baseline: `69ceff2`, October 3, 2026, Release `1.0.0+45`; `pubspec.yaml` agrees with that version.

## Scope and evidence conventions

Sources examined include the current repository, its available Git history, `codex.md`, all project Markdown documentation and review reports, implementation and test inventories, selected implementation paths, project-specific local conversation records and their referenced attachments, and surviving verification logs. A source inventory and commit chronology are in [paltranco-source-inventory.md](paltranco-source-inventory.md). Dated conversation references `Cxxxx` resolve to [paltranco-conversation-evidence.md](paltranco-conversation-evidence.md).

254 local session files matched this workspace's exact working directory, including archived and forked histories. Direct-user messages were indexed; approval-review transcript copies were excluded from the selected evidence register. This number is not the number of meetings, separate engagements, or completed tasks. Earlier discovery meetings, other repositories, external chats, and unavailable historical materials cannot be reconstructed merely because later messages refer to them. No live production account, database, deployed rule set, or current public deployment was inspected during this research. No application code was changed and no tests were newly run for this documentation task.

Statuses used throughout:

- **Implemented / MVP:** executable implementation exists in the available source. It does not establish deployment or operational acceptance.
- **Designed / specified:** requirements or rules are documented; implementation evidence is separately stated.
- **Discussed / proposed:** conversation or design direction exists without confirmed completion.
- **Tested / validated:** a named test, recorded result, or bounded reproduction exists; its environment and limits matter.
- **Discarded / replaced:** explicit abandonment or replacement is supported by evidence.
- **Future / not yet implemented:** an explicitly recorded next step or unresolved direction, not a new suggestion from this report.
- **Unknown:** evidence is absent or insufficient.
- **User-reported history:** the engagement account supplied in the October 4 request; retain it without presenting it as independently verified contemporaneous evidence.

## A. PROJECT TIMELINE

| Date / sequence | Reconstructed event | Status and evidence |
| --- | --- | --- |
| Engagement beginning; date unknown | Discovery meeting to understand requirements; initial request concerned backloading during a fuel price hike, allowing different clients/people to send or combine shipments through available trips. | User-reported history, October 4 request [S1]. Initiator, attendees, questions, minutes, commercial terms, and exact start date are unavailable. |
| Before revised operational MVP; dates unknown | Initial backloading MVP was created; deeper discovery found that backloading was outside Paltranco's actual current operation; that MVP was discarded. | User-reported built/discarded history [S1]. Its source, screens, roles, tests, and release records were not identified. |
| Revised discovery; date unknown | Actual business described as primarily B2B: a client such as Moreta requests transport of a container van between locations. Communication, dispatch, trip tracking, KPI/sales tracking, and billing-document preparation were difficulties. | User-reported discovery [S1]; later Moreta records and operational code corroborate parts of the model, but do not date the meeting. |
| May 25–30, 2026 | Earliest accessible project conversation starts with admin-home work. Shared sidebar/menu components, MVVM pages, user models, responsive lists/modals, authentication screens, profiles, and configurable booking flows were requested and refined. | Conversation C0000, C0030, C0033, C0227, C0348–C0352; existing project was already present when this record begins. |
| May 28–30 | Temporary users/statuses/fields supported development; booking fields, driver/helper assignment, waybill and Delivery Form photos/numbers, cancellation, schedules, ongoing→delivered, and completed-booking dashboard were specified and debugged. | C0758, C0952, C0983, C1085, C1191–C1347. Historical requests plus subsequent source; not every intermediate mock configuration remains current. |
| June 10 | First available Git commit `490b7bd`; already contains booking and role screens, local/mock repositories, models, and flow engine. Same-day commit `3bcf7ff` refactors Firestore CRUD; registration/phone fixes follow. | Git tree and history. June 10 is the first commit date, not the engagement start or initial-MVP date. |
| June 11–13 | Photo uploads, field/form responses and styling, export development, image zoom/cache, and password changes. | `f15ee2d`, `edc3880`, `52dd0ce`, `014f2ed`, `b7f5746`. |
| June 28–29 | Further fixes; unbilled-export work; repeated offline iterations. | `d511312`, `3e78491`, `0707bf8`, `2e6b689` through `626a4dc`. “Before…” and “wip” messages establish sequencing, not detailed feature acceptance. |
| July 3 | A project-local conversation record exists. | Source manifest; the record alone does not establish an additional milestone. |
| August 11–12 | Offline function and persistent logout/session work; offline functionality commit. | `b6b7273`, `6291162`, `ef3c28b`. |
| August 28–29 | Full-system-test/release work; production login, stale web-cache rollout, auth-error visibility, Firestore web configuration, and cold-start data fixes. User reports past-unbilled mismatch on Moreta records. | `972bf34` through `9fecae4`; C3002; later production-comparison reports. |
| September 1–2 | Support caching, form toggles, online ID reservations, camera switching, booking confirmation, mobile scrolling/safe areas, PWA install/download flow, booking/support badges, analytics filters, and chassis foundation. | Named commits in source inventory; `7175155`, `f925a24`. |
| September 3–5 | Chassis lifecycle/migration safeguards and alerts; offline chat; iPhone Safari startup; persistent caches and application-shell assets; transient-empty-booking fixes; Storage CORS; driver/helper schedules. | `0874f8d` through `07f80a9`; documentation [S4–S8]. |
| September 13–19 | Schedule detail work; offline delivery ordering; image-memory/renderer pressure; form/alert polish; performance/sync investigation; disposed-view hot-restart protection; local field-entry history; Release `1.0.1+9`. | Named Git commits, `0bac99e`; `docs/disposed-view-crash.md`, `docs/sync-freeze-follow-up.md`, `docs/field-type-history.md`. |
| September 19 | PM clarified as Prime Mover. Revenue, manager-entered fuel, matrix-based daily/trip salary, depreciation ₱50,000/month, maintenance ₱58,000/month, and gross-income/variance formulas explained. | C4273–C4274. Specification predates first committed PM-KPI module. |
| September 20 | Revenue target clarified to ₱350,000 **per PM per month**. Questions about 12 delivered bookings appearing as four daily rows exposed presentation/data-diagnostic confusion. | C4371–C4372 and surrounding September 20 conversation; [S3]. Four day groups must not be equated with four trips. |
| September 22 | Allowance-based ratings replaced by editable gross-margin, complaints, and accidents rules. User confirms “40% na rin … sabi ni boss.” Workbook layout work replaces automatic-import/format-menu direction. | C4525–C4526; `docs/pm-kpi.md`. |
| September 23 | PM KPI committed; extensive offline/current-vs-production audits, photo commit safety, diagnostics, account-scope fixes, chassis reservations, bounded Firestore pages, cooperative workbook/cache work, browser and emulator verification. Releases `1.0.1+10` to `+13`. | `2d18c93` and successors; dated review documents [S6–S8]. Many review passages explicitly describe local changes at the time. |
| September 24–25 | KPI Tracking workspace enters history; crew fuel/booking-count/shares/salary work, support read-marker ordering, image resizing, notification index, chassis presentation/assignment fixes. | `8129b81`, `c166711`, `8de39f6`, `f221fd3` and release commits. |
| September 27–29 | Investor scope/commission/statement implementation appears in Git; related investor tests and permission controls. September 29 user asks investor Support contacts to show main support and own crew, and permission-enabled Dashboard, Analytics, and KPI Tracking. | First investor-scope addition `9d2f989`; C4799, C4801; investor services and tests [S9]. |
| October 1–2 | Daily/weekly/monthly trip utilization requested and implemented; overview/total drill-down, matching periods, total-day denominator, summary-column simplification; last activity updates; continued dispatcher/helper sync-conflict and photo recovery work. | C4815, C4824–C4831, C4892–C4943; `36fd67a` onwards; fixture/test inventory [S10]. |
| October 3 | UI text selection/highlight fixes, including purple backgrounds, filters, popup labels, modal and retained-page text; latest release `1.0.0+45`. | C4965–C4967; `69ceff2`; preserved verification logs [S12]. |
| October 4 | Engagement reconstruction requested. | [S1]. No presentation created. |

## B. WHAT WE DID

### Discovery, requirements, and analysis

The initial discovery/backloading/pivot sequence is supplied by the current request. Accessible development conversations independently show prolonged requirements clarification and refinement of actual booking, crew, document, billing, and financial workflows. They include field requirements by role, cancellation eligibility, assignment availability, workflow dependencies, record ordering, delivery-photo requirements, PM attribution, financial formulas, rate matrices, target corrections, incident ownership, investor access, and utilization definitions. [S1, S2, S3, S9, S10; conversation register]

Non-development work includes architecture/UI conventions in `codex.md`; offline write-path audits; booking data/performance analysis; photo-safety policy; chassis reservation modeling; field-history privacy analysis; crash reproduction; current-versus-production bundle comparisons; fault-injection probes; predeployment verification; workbook-layout analysis/sanitization; and recorded limits on what testing establishes. These artifacts are deliverables even where they report unresolved issues. No original meeting minutes, full sales-process map, engagement contract, management slide deck, or formal pilot-signoff document was identified. [S2–S8]

### Development inventory

Work evidenced in source/history covers:

1. Flutter web frontend and MVVM structure with Stacked, repository interfaces, request/data-access layers, and reusable domain services.
2. Shared responsive navigation, tables/cards, modals, inputs, actions, date/search selectors, selection/copy behavior, loading states, safe areas, and retained-page rendering.
3. Registration/login, persisted application sessions, profile/photo/license editing, password changes, admin quick-login/return, active/online state, and last-opening activity updates.
4. Users, role/capability configuration, legacy client-member handling, investor-account grant controls, and crew relationships.
5. Client booking creation/history; office booking-on-behalf-of-client; editing, searching, filtering, scheduling, assignment, cancellation, and role-specific status progression/history.
6. Dynamic Forms, Fields, and Statuses libraries, field data sources, validation, dependencies, previews, and workflow engine.
7. Vehicle Makes/Types/Sizes catalogs, PM crew assignment, optional helpers, and registration-linked truck creation.
8. Chassis CRUD, reservations, active physical ownership, delivery/check/empty/return/confirm lifecycle, location/history/elapsed-time display, and waiting badges.
9. Dashboard completed/delivered booking presentation, billed/unbilled state, past-unbilled inclusion, billing statement/transmittal DOCX exports.
10. Support threads/messages, booking-linked support entry, attachment handling, read markers, contact scope, pending/error/retry states, foreground sounds/badges and FCM code.
11. PM financial KPIs, fuel ledgers, salary/trip-share calculation/confirmation, locations/rate versions, fixed-cost buffers/approved overrides, incident counts, rules, diagnostics, and period calculations.
12. Fleet KPI Tracking overview, total drill-down, utilization, crew KPI projections, fleet workbook and investor statement export.
13. Investor ownership/silo resolution, crew onboarding rules, reporting scopes, commission settings/calculation, approved-expense bridge, statement selection and export.
14. Durable account-scoped offline mutation, media/upload, cleanup, and diagnostic queues; caches; session/network transitions; local optimistic records; ordered replay and retained conflicts.
15. Numeric-ID reservation, temporary-reference resolution, legacy-booking repairs, conflict comparison, explicit operator reconciliation, archives, and photo cleanup claims.
16. PWA manifest/install/download routes, custom application service worker, startup splash/assets, Safari/in-app-browser handling, version/update support, Vercel static deployment configuration.
17. Firebase/Firestore/Storage client integration; scheduled/document-triggered Node functions; indexes, CORS/rule configuration, release scripts, and real-SDK emulator harness.
18. Calculation/unit/widget/browser/integration regressions; operational fixture replay; bug investigations; shared-stream/filter/model/calculation caching; lazy rendering and cooperative export/cache processing.

The module and validation detail below prevents this inventory from implying that every feature is deployed or every described business process was observed on site. [S2–S12]

## C. WHAT WE DISCOVERED

### Business and operational model

The user reports that Paltranco's current operation is primarily B2B transport, rather than shipment aggregation/backloading. Later records explicitly name **MORETA SHIPPING LINES**, include route pairs and container/waybill/delivery references, and demonstrate the importance of billed/unbilled tracking. This corroborates an actual customer/document workflow; it does not establish that Moreta is the only customer, quantify commercial volume, or prove every pasted record's correctness. [S1; C3002; dashboard/export code]

The supported system workflow is:

**Client or office-created booking → pending request → assignment of PM/driver/helper and, where relevant, chassis/schedule → role-specific workflow actions → delivery record/photo and delivery timestamp → post-delivery chassis handling where applicable → billed/unbilled review and billing documents → operational/financial reporting.**

Sales/coordination is part of the reported business context, but no separate lead→quotation→contract sales pipeline was identified. Collections/payment cannot be inserted into this sequence as an implemented step. Chassis completion and delivery completion are different events; a delivered trip may still have a chassis in Check, Empty, or Return. [S1–S5; `Booking.deliveredWorkflowStatuses`; dashboard VM]

### Process-by-process evidence

| Process | Observed/confirmed, discussed, proposed, implemented, or unknown | Supported detail / limit |
| --- | --- | --- |
| Client/customer | User-reported operating model; specified and implemented | Client accounts, booked-by association, client history, representative fields. Moreta appears in later user-supplied records. [S1; C1201; C3002] |
| Sales | Reported difficulty; implemented booking-amount reporting | Revenue/amount/billing summaries exist. No independently confirmed sales funnel, quotations, contract/pricing-negotiation workflow. [S1, S3] |
| Booking/request | Specified, implemented, regression-tested | Client and office creation; original creation time/submission identity; offline pending creates. [S2, S4] |
| Coordination/dispatch | Reported bottleneck; specified and implemented | Pending work, schedule/crew/PM assignments, alerts and role-gated office views. No separate observed telephone/email SOP. [S1, S2, S5] |
| Truck assignment | Specified, implemented, tested | Vehicle Make/PM references; current crew and historical trip attribution; unresolved legacy matches flagged. [S3; `booking_pm_assignment.dart`] |
| Driver assignment | Specified, implemented, tested | Availability, crew/vehicle links, assigned queue, investor-silo checks. [C1334; S9] |
| Helper assignment | Specified, implemented, tested | Assignment plus optional unassigned helper; saved trip crew retained. [S3, S9] |
| Trip creation | Implemented through Booking | No distinct universal `Trip` persistence entity was identified; KPI trips project Booking data. [S11] |
| Trip execution/status | Specified, implemented, tested | Configurable forms/dependencies; client/driver/helper statuses and history. [S2, S4] |
| Delivery/completion | Specified, implemented, tested | Delivery Form photo/number, Delivered action/time; offline replay preserves action time. [C1191, C1314; S4] |
| Proof/documentation | Specified, implemented, tested in bounded environments | Waybill/Delivery Form photos, references, history, image viewing/uploads. Not a verified legal-document acceptance process. [S4, S7] |
| Chassis return/reuse | Modeled, implemented, regression-tested | Reservation separated from physical ownership; Check/Empty/Return/Confirm; no theft of another active booking's chassis. [S5] |
| Billing | Reported difficulty; implemented, export-tested | Billed/unbilled flag and BS/BT regular/hustling DOCX. [S1; S11] |
| Collections/payment | Unknown as a dedicated process/module | Billing flag and bank details do not prove receipt, settlement, aging, payment reconciliation, or receivables subledger. |
| Expenses | Specified, implemented | Fuel, crew pay, depreciation/maintenance allocations/overrides; investor-approved expense projection. Not a complete general ledger. [S3, S9] |
| Fuel | Specified, implemented, tested | Manager/operator enters date, amount, PO/reference, supplier, optional liters/price/odometer; edits/voids/history/confirmation. [S3] |
| Maintenance | Fixed-cost rule confirmed by user; calculation/override code implemented | ₱58,000 monthly buffer. Expense bridge recognizes repair/parts/tires kinds. No maintenance scheduling, workshop job orders, service intervals, or inventory module established. [C4273; S9] |
| Driver/helper management | Specified and implemented | Accounts, activity/availability, license/profile, assignments, personal KPI projection, complaints/accidents. [S2, S3, S10] |
| Truck management | Specified and implemented | Makes/Types/Sizes, active state, PM labels/crew, KPI detail. No GPS/telematics evidence. [S3, S11] |
| Communication | Reported bottleneck; implemented Support/alerts | Threads/messages/media, scopes/read markers, FCM and sounds. No confirmed integration with external messaging providers. [S4, S9, S11] |
| Reporting/KPI | Initially difficult; specified, implemented, tested | Operational analytics, PM/fleet/crew reporting, utilization and exports. Financial completeness/attribution remain data-dependent. [S3, S10] |
| Investor operation | Designed in code, implemented calculations/scopes/UI paths | Supplies own trucks/crew; Paltranco books/dispatches/bills; actual investor onboarding/use/agreements not confirmed. [S9] |
| Multi-branch operation | Unknown | No branch model/workflow or confirmed branch expansion plan identified. |

### Bottlenecks and discoveries from development

The initial reported bottlenecks concern communication, dispatch visibility, ongoing versus finished trips, KPIs, sales, and billing documents. Later firsthand development feedback adds stalled login/dashboard/forms, stale/cold-start data, lost or blocked offline uploads, duplicate/temporary booking identities, conflicting assignments, incorrect/unexplained counts, memory/renderer failures, and expensive rebuilds. These are different evidence classes: an operational difficulty reported in discovery, a user-observed app symptom, a reproduced defect, and a test-confirmed correction should not be collapsed into one claim. [S1, S4, S6–S8; C3002, C3182]

Financial analysis established that booking Created dates and Delivered dates serve different purposes; daily rows do not equal trip counts; missing fuel/salary confirmation does not equal zero; crew changes must not rewrite historical earned pay/incidents; a rate-matrix change must not reprice confirmed history; and ambiguous PM/booking identity cannot be resolved by guessing. [S2, S3; C4273–C4274]

Existing tools supported by evidence are the **KPI-2026-new.xlsx** workbook and related DOCX billing layouts used as references/templates. The September 19 conversation supplies a fuel/salary/maintenance/revenue table. No complete pre-project inventory of spreadsheets, messaging apps, accounting software, or paper procedures was found. [S3; C4274; bundled assets]

## D. WHAT CHANGED

### Engagement direction

**Original direction:** backloading during the fuel price hike; different customers/people combining shipments on available trips. **Discovery:** user reports this did not represent Paltranco's current operation. **Revised direction:** B2B transport and automation of booking/dispatch, crew/truck assignment, trip documentation/status, billing and reporting. [S1]

The original MVP therefore contributed a requirement-fit lesson: validate the real operating model before treating the requested concept as the operating workflow. Its reuse, technical lessons, customer tests, and exact features cannot be reconstructed from the available source. “Discarded” must not become “wasted,” nor imply that the current repository is its preserved source.

### Recorded changes inside the operational MVP

| Earlier direction | Subsequent direction | Evidence |
| --- | --- | --- |
| Mock/local users and workflow data | Working login/registration and real data requested; temporary development seeds later reintroduced; Firestore CRUD committed | C0351–C0352, C0758; June 10 history. This is an iteration, not a single permanent mock-removal event. |
| Per-role/redundant seeded forms and statuses | Shared reusable forms, fields, statuses and role-based dependencies | May 29 conversation; `codex.md`; runtime engine. |
| Simple direct chassis assignment | Advance reservations separate from physical ownership, common direct/queued rules | September 23 review and `docs/chassis-reservations.md`. |
| ₱70,000 weekly PM revenue target / ₱280,000 month | ₱350,000 per PM/month; current weekly equivalent ₱87,500 | C4371–C4372; `PmKpi.revenueTarget`. |
| 45% financial benchmark and ₱10,000 allowance-based rating | Editable 40% benchmark, default margin thresholds 40% and 51%, separate complaints/accidents ratings | C4525–C4526; current `KpiRatingRules`. |
| Separate Driver/Helper Income and Payroll Summary UI | Grouped, expandable daily Transaction History and integrated KPI workspace | `docs/pm-kpi.md`; current dialog. |
| Excel import/print/PDF option in KPI toolbar | Fleet Excel export using sanitized reference layouts; import removed from current toolbar | `docs/pm-kpi.md`; current export path. Import/PDF-related source remains. |
| Repeated processing per subscriber and whole collection/list rendering | Shared processing, cached filters/calculations, lazy rows, bounded read/listener ranges, cooperative export/cache processing | Performance documents and lazy-list audit. Complete logical dataset still retained. |
| Cleanup before booking commit | Cleanup intent committed with booking; acknowledged worker claims/deletes | `docs/booking-photo-safety.md`. |
| Office-only investor statement comments | Investor role/scopes plus permission-enabled admin-style reporting requested September 29 | C4801; current reporting scopes. Some comments/UI copy still conflict. |
| Historical missing-PM notices surfaced as sync diagnostics | Current policy treats them separately; user requested their removal from KPI/sync-error display | C4932; `kpi_diagnostic_policy.dart`. Hiding a notice does not fill missing assignment data. |

## E. WHAT WE BUILT

### Module inventory

Each row identifies purpose/problem, user/workflow, status, data/reporting, and dependencies. Role capability grants can change visibility; “admin” does not mean manager/dispatcher automatically has every financial capability.

| Module | Purpose / problem | User and workflow | Implementation / data / reports / dependencies |
| --- | --- | --- | --- |
| Application shell, navigation, shared UI | Consistent responsive operation and stable unsaved state | All roles; role-capability shell, sidebar, retained pages, modal/detail routes | Implemented. Shared layout/actions/selection/loading; depends on session/capabilities. `app_shell.dart`, `admin_home.dart`, shared widgets, `codex.md`. |
| Login/registration/session | Account access and session continuity | Register/login using email/phone; cached session; quick-login/return; logout | Implemented **custom application auth**. `users`, local auth storage; bridge stub; not Firebase Auth token validation. `auth.request.dart`, session tests. |
| Users/profile/activity | Manage account/crew/contact details and availability | Role-gated CRUD/activation, profile photo/license/password; opening updates activity | Implemented. User/Driver models, `parent_client_id`, active/online/updated times; last opening is not continuous attendance. `admin_users`, `profile_view`, `user_activity_test`. |
| Roles / Access | Configure usable screens/actions | Admin configures built-in/custom capabilities; open screens react | Implemented application checks and offline cached configs in `role_access`; not server enforcement. `dispatcher_access_config.dart`, access service/request. |
| Bookings / client history | Capture transport request and track its progress | Client or authorized office creates, searches/filters/views/edits, books on behalf of client | Implemented. Booking references/status outputs/timestamps/submission key; trips and revenue feed reports; tests cover creation/history/identity. |
| Flows: Forms/Fields/Statuses | Adapt workflow/required information without separate hardcoded screens | Configure field library, roles, status/next status, main/secondary forms, dependencies, blocked messages | Implemented engine/builders/previews and validation. `status_forms`, `status_fields`, `statuses`; feeds booking actions. No `admin_status` on Booking. |
| Dispatch / assignment / schedules | Move pending requests to actionable crew work | Authorized office picks PM, driver, helper, chassis and schedule; crew sees assignment queue | Implemented inside Booking workflows and catalogs, not a separate dispatch backend. Depends on user availability, catalog, access, reservation/silo guards. |
| Execution / cancellation / delivery | Capture role actions and proof | Configured action forms, reasoned cancellation, Delivery Form photo/number, delivery time | Implemented with original action timestamps, history, continuation/retry. Depends on configured forms and durable media queue. [S2, S4] |
| Vehicles: Makes/Types/Sizes | Catalog and crew/PM references | Authorized CRUD, active state, PM code, driver/helper selection; driver signup truck link | Implemented `vehicle_makes/types/sizes`; optional helper, `needsCrew`; PM detail/KPI/report ownership depend on canonical data. |
| Chassis and history | Track reservations, physical state and post-delivery reuse | Reserve for bookings; activate trip; Check/Empty/Return/Confirm; inspect history/wait | Implemented transactions, replay safety, location/history/badges. `chassis`, Booking links; multiple reservations with one physical owner. [S5] |
| Dashboard / billing state | Review delivered work and prepare billing | Filter completed/delivered records; mark billed/unbilled; include past-unbilled; choose export records | Implemented `billing_status`; amount/reference summaries. Depends on delivery and fields; no payment-settlement ledger established. |
| Billing DOCX export | Reduce repetitive document preparation | Authorized export with client/period/statement/signatory/bank inputs | Implemented BS/BT regular/hustling templates and totals. Rows: DR No., Date, Waybill No., Van No., Van Size, Client, Amount. Template/export tests. [S11] |
| Support / contacts / media | Coordinate requests and errors | Main/booking support entry, threads/messages, attachments, read markers, failed-message retry, scoped contacts | Implemented `support/.../messages`, support management markers/local pending data; investor contact restrictions. Depends on users/session, Storage, queues. |
| Alerts / push | Notify staff/crew of pending/assigned work, support, chassis check | In-app sounds/badges; FCM token and service worker; server triggers | Implemented client and function source. `manage_notifications`, FCM; actual latest function deployment/delivery not confirmed. [S11] |
| PM KPI detail | Show PM income/cost/performance by period | Permission-enabled read/refresh; confirm fuel/salary; drill into history/rates/rules | Implemented `pm_kpi_records`, projected bookings; weekly/monthly/custom/all-time support in related services. Financial data/completeness/cache warnings matter. [S3] |
| Fuel Ledger | Trace recorded consumption/cost | Add dated amount/reference/supplier/optional liters-price-odometer; edit, void, history, confirm total | Implemented `pm_fuel_entries`, original date protected; legacy aggregate conversion; stable-ID offline replay and conflict checks. [S3] |
| Salary / trip shares / crew KPIs | Attribute daily pay and matrix earnings to actual crew | Office confirms daily routes/pay; crew sees own authorized summary; expand daily trips | Implemented saved day/rate/crew snapshots and read-only crew projection. Depends on delivered trips/time, rate matrix and role access; not bank/payroll disbursement. |
| Locations & Trip Shares / Rates | Maintain route options and compensation | Configure canonical locations/aliases/kinds/active state, paired crew rates and effective dates | Implemented `operations_catalog` and immutable matrix versions; historical options remain valid; salary confirmation snapshots preserved. |
| Rating Rules / incidents / cost overrides | Compare performance and record context | Authorized edits of financial thresholds; dated user incidents; approved period costs | Implemented settings/revision/offline support. Legacy PM incident counts remain unassigned; approved actual depreciation/maintenance can replace estimated buffer. |
| KPI Tracking overview / fleet Total | Compare PMs and drill into aggregate | Authorized office/investor opens overview, filters period, selects PM/Total | Implemented fleet projections, aggregate financial totals/ratings, total modal; scoped investor store. [S10] |
| Utilization | Count trips by date/week/month and active days | Choose shared period; view PM/Total trip cells and detail actions | Implemented delivery-date-based unique trips, unresolved count, PM mapping, active-day sets. It is not payload/capacity utilization, GPS uptime, or on-time delivery. [S10] |
| Analytics | Summarize operational activity/status/amounts | Permission-enabled filters and charts | Implemented `admin_analytics.dart` and role/report scope. No externally validated business-performance improvement claimed. |
| Fleet Excel export | Reproduce existing KPI workbook structure from app data | Confirm date range; on-demand authorized fleet reads; download Excel | Implemented template generator/export, selected ledger/month/week tabs, extra PM/fuel rows, async yielding. Admin cost manually entered in Excel. [S3, S8] |
| Investor statement / commission | Explain Paltranco share and investor net due | Office selects investor owning a truck and period; generates/export statement; authorized share edit | Implemented calculation/VM/dialog/workbook; default global 10% rate; crew-cost reconciliation and approved expenses. Not proof of actual payouts/contracts. [S9] |
| Offline Sync / Queued Actions | Retain accepted work across disconnect/reopen | Local saves → scoped queue → ordered/server-checked replay → acknowledged removal or conflict review | Implemented mutation, upload/media, cleanup queues, cache/reference mapper, status banners/retry. Server confirmation differs from local acceptance. [S4] |
| Legacy repair / conflict review | Preserve work when temporary/numeric records diverge | Bounded online-admin repair; explicit compare/choose/acknowledge for supported corrections | Implemented exact-key identity, transactional version/reference checks, `booking_id_repairs` archives/decision snapshots. No heuristic merges by name/waybill/newest time. [S2] |
| Error Logs / diagnostics | Make sync/runtime failures inspectable | Independent outbox, metadata/error/context, counts, copy/review/support linkage | Implemented `sync_error_logs`, sharded persistence, bounded upload batches, Web Locks; diagnostic failure must not delete business actions. Not universal backend observability. [S6–S8] |
| Photos / documents / cache | Keep evidence safe without blocking on every upload | Camera/file selection; image preparation/cache/viewing; durable staging; commit-intent cleanup | Implemented Storage/image/media paths and retry/claim protection. Actual cloud permissions/upload races require live validation. [S4, S7] |
| Field Type History / drafts | Reduce repeated input and preserve in-progress work | Eligible account/field suggestions, local draft storage; record history after accepted save | Implemented local bounded history; no keystroke remote reads. Passwords/unique IDs excluded; automatic private Firestore history explicitly deferred. [S8] |
| PWA/startup/version handling | Support installed/offline browser entry and release updates | Install/download flow, cached shell/splash, service worker, startup readiness, resume recovery | Implemented web assets/services/routes. Never-downloaded data/assets cannot be fabricated offline; cold-start/device caveats retained. |

### User roles

| Role | Responsibilities, visibility/actions, information provided/consumed | Status / evidence |
| --- | --- | --- |
| Admin | Office-wide records and configuration; CRUD, billing/export, users/impersonation, workflows, KPI/rates/rules/fuel and access controls by default; supplies assignments/settings/confirmations and consumes operational/financial records | Implemented; all capability defaults true. Application access, not server rules. [S2, S11] |
| Dispatcher | Booking/dispatch/customer coordination, dashboard billing/export, user create/read/update, support, profile, sync by default; supplies assignment/booking updates and consumes pending work/crew information | Implemented; financial/catalog/workflow administration usually requires explicit added grants. [S11] |
| Manager | Default access uses dispatcher capability map; manager fuel/financial entry responsibilities discussed; grants determine actual KPI access | Implemented role and configurable capabilities; do not assert KPI enabled by default. C4273, C4893; role model. |
| Client | Provides booking/representative/reference/photo data; sees and acts on authorized booking workflow/history, support/profile/queue | Implemented role/workflows. Specific cancellation rule initially pending/assigned, before ongoing; actual configured forms govern current transitions. C1196; [S2]. |
| Driver | Provides status/delivery evidence, availability, profile/license/vehicle information; consumes assignments/schedules, chassis-return work and own KPI/earnings projection | Implemented; driver model, assigned-home logic, crew KPI/read access. Not autonomous dispatch authority. |
| Helper | Provides permitted trip actions/evidence/availability; consumes assignments/schedules and own KPI projection | Implemented; optional assignment; original trip crew preserved. [S3, S4] |
| Investor | Model supplies own trucks/crew; own-crew account management and scoped operation; office handles booking/dispatch/billing. Dashboard/Analytics/KPI available when role grants permit | Implemented role/scopes and statement model. Default investor capabilities deny office dashboard/bookings/PM KPI and financial crew-pay windows; C4801 explicitly asks permission-enabled reporting. No dedicated Portfolio screen established merely by named capability. [S9] |
| Sub-client / member | Historical client-associated accounts/member data | Legacy term/storage present; current `normalizeRoleKey` maps both to `client`, `isSubClientRole` returns false, role list excludes sub-client. Not a separate current implemented role. [S11] |
| Custom roles | Consume/provide data according to assigned capabilities and workflow applicability | Configurable role infrastructure exists. No complete list of real deployed custom roles or duties established. |

No distinct implemented salesperson, accountant, collector, mechanic, branch administrator, or public shipment-aggregator role was established.

### Investor model in detail

The investor concept is more than a future idea in this checkout: investor scope/calculation/settings/reporting services, a statement dialog/ViewModel/workbook, user/vehicle guards, and regression tests exist. First addition of `investor_scope.dart` is September 27 (`9d2f989`). Actual investor use, contracts, truck contributions, settlement and payout are unknown. [S9]

- **Onboarding:** privileged investor-account creation is separate from ordinary user creation. Investor-created crew is linked to the investor through `parent_client_id`. Driver registration can associate/create a vehicle record; operational crew assignment remains relevant. There is no identified KYC, investment-contract, contribution-value, or legal ownership register.
- **Ownership:** a truck/Vehicle Make has no explicit owner field in the current model. `InvestorScope.investorForMake` resolves ownership from canonical driver, then helper, whose parent is an actual investor user. A truck can be in a company or investor crew silo; mixed-owner crew is guarded against. This is operational association, not proof of legal title or immutable historical ownership.
- **Operating division:** code comments explicitly say investor supplies trucks and crew; Paltranco handles booking, dispatch and billing. Statements consume existing booking/KPI records instead of creating a competing earnings ledger.
- **Visibility:** ownership checks accompany capabilities. Support contacts are restricted to main support and own crew; Dashboard/Analytics/KPI use scoped reporting when permission-enabled. Multiple investors/trucks are represented by IDs/list projections. Default grants and stale comments must not be mistaken for a complete live investor portal.
- **Financial formula:** gross billings are owned trip amounts; Paltranco share = gross billings × configured rate; investor pool = gross billings − Paltranco share; net due = investor pool − crew cost − approved expenses. Default rate is 10%; the settings store persists a shared rate with actor/time and cached/queued support. It is applied regardless of trip profitability. Negative net due is retained.
- **Crew cost:** computed per day/person-day, using ₱455 default daily pay plus matrix shares, or the office's saved daily salary. Missing route pricing can block calculation; office unconfirmed days remain visible; derived daily/share totals are independently reconciled.
- **Expenses:** bridge consumes non-voided, positive, owned-PM ledger entries in the period; recognizes fuel/maintenance/repair/tires/parts kinds. Only explicit `approved == true` reduces net due; pending costs remain visible. Fuel Ledger has an office action to **record that the investor agreed**. This is not an independently authenticated investor signature. Coverage warnings do not prove every cost was captured.
- **Output:** period statement selection, breakdown and workbook export exist. Bank payment, remittance, collection settlement, per-investor negotiated historical rates, signed approval artifacts and actual revenue-share contracts were not established.

### Financial and KPI inventory

| Metric / financial function | Current status and calculation / limit | Evidence |
| --- | --- | --- |
| Booking amount / revenue / sales proxy | Implemented. PM revenue uses non-cancelled booking amounts by original Created date; not collected cash or a sales CRM | `pm_kpi.dart`; C4273–C4274 |
| Gross billings, billed/unbilled, past unbilled | Implemented. Billing flag/selected amounts; not payment or accounting receivables balance | Dashboard VM; C3002 |
| Fuel amount / liters / missing-liter entries | Implemented ledger totals and confirmation; operator entry, not telematics measurement | [S3]; fuel dialog/store |
| Daily salary, trip shares, days worked, crew total | Implemented separate/combined projections and saved confirmations; delivery-date basis and snapshots | [S3]; crew store/tests |
| Default daily pay / route shares | Implemented configurable matrix defaults: ₱455/person-day; City Proper first 1–4 trips ₱100/₱50 driver/helper, excess ₱150/₱75; Narra ₱500/₱250; Brooke's Point ₱700/₱350; hustling full ₱100/₱50 and empty ₱50/₱25 | [S3]; `KpiRate`/salary helpers. Current saved effective matrix can differ. |
| Depreciation / maintenance | Implemented default estimated buffers: ₱50,000/₱58,000 full month; period fraction allocations. Approved actual override code can replace buffer | C4273; `pm_kpi.dart`, `kpi_cost_override.dart` |
| Total expenses | Implemented fuel + driver salary + helper salary + depreciation + maintenance | Current PM calculation |
| Gross income / gross profit | Implemented revenue − total expenses; not the investor net-due formula | Current PM calculation |
| Revenue target | Implemented ₱350,000 per PM/full month, ₱87,500 per business week equivalent | C4372; `revenueTarget` |
| Gross-income goal | Implemented planned revenue target × configured target percentage; default monthly ₱140,000 at 40% | C4526; `profitTarget` |
| Target gross income against actual revenue | Implemented actual revenue × configured target percentage, default 40%; differs from planned-revenue goal | `marginTarget`; workbook/financial discussion |
| Favorable / Unfavorable | Implemented actual gross − actual-revenue margin target | `marginVariance`; C4273 |
| Gross margin/rating | Implemented gross/revenue; default <40% Failed, ≥40% and <51% Satisfactory, ≥51% Excellent, no premature rounding; zero revenue Not rated | `kpi_rating_rules.dart`; C4525 |
| Complaints/accidents, user ratings | Implemented dated counts and thresholds; missing observation differs from confirmed zero, historical counts do not move with current truck crew | [S3]; incident/rules services |
| Fleet financial totals / rating | Implemented PM aggregation and total drill-down; context/period/permission dependent | `fleet_kpi.dart`, KPI Tracking |
| Trip utilization / active days | Implemented unique delivered trips per day/week/month, active-day counts and Total; delivery timestamp/PM mapping required | `kpi_utilization.dart`; C4815, C4943 |
| Booking/status/activity analytics | Implemented UI projections/filters; not proof of increased productivity or adoption | Analytics view; activity request/tests |
| Investor platform fee / pool / approved costs / net due | Implemented calculation and export; not actual paid amounts | [S9] |
| Admin cost / fleet net income | Earlier ₱160,000/month rule discussed in PM docs. Current fleet workbook intentionally leaves admin cost blank; Excel net income waits for entry | [S3]; conflict recorded in L |
| Receivables aging / collections / paid balance | No dedicated implementation established | Billed/unbilled must not be relabeled as these |
| End-to-end trip cost / truck profitability | Implemented bounded KPI approximations using the listed allocations/entered data. No fully reconciled accounting cost ledger confirmed | PM/fleet calculations |
| On-time delivery / completion-rate percentage / capacity utilization / fuel economy | No specific validated implemented formula established in reviewed paths | Do not infer from status/trip-count/fuel availability |

### Billing and documents: automation versus manual work

Implemented billing outputs are **Billing Statement (BS)** and **Billing Transmittal (BT)**, each with **Regular** and **Hustling** templates. Export configuration captures document and covered dates, billing-statement number, company/representative/greeting, prepared/approved names/titles, and bank/account fields. Booking rows supply delivery-receipt number, date, waybill number, van number/size, client, amount and totals. [S11]

The system stores/views **Waybill Photo**, **Delivery Form photo/number**, driver license/profile images, Support attachments and status/action records. Fuel PO/receipt references are entered in the ledger; that is not proof of a receipt-image OCR or supplier-invoice integration. KPI fleet workbook and investor statement are separate report outputs. A distinct tax invoice, official payment receipt, e-invoicing/tax integration, or automatically submitted client billing system was not identified.

Manual/controlled inputs remain: document details and selected rows, billed/unbilled decisions, original physical evidence capture, fuel amounts/references, route and salary confirmations, incidents/zero-day confirmations, cost agreement/overrides, uncertain PM attribution and conflict review. Current Excel admin cost requires manual entry. Sending the documents, obtaining client approval, collecting payment, bank reconciliation and actual payroll/investor payout are not confirmed automated. [S3, S9, S11]

### Technical foundation

| Area | Evidence-supported implementation and limit |
| --- | --- |
| Frontend | Flutter/Dart web application; Stacked MVVM, responsive shared widgets, browser-specific and stub/IO implementations. Pubspec SDK constraint `^3.11.5`; dependency constraints are not proof of every runtime version. |
| Persistence/backend | Cloud Firestore CRUD/listeners/transactions via `lib/requests`; Firebase Storage media; application business calculations/services mostly execute in Dart. No separate general REST business server was identified. Public-document fetch fallback code is not a new comprehensive API layer. |
| Data models | User/Driver, Booking, VehicleMake/catalog, Chassis/action history, Status/Form/Field, SupportThread/Message, access configs, offline queue item; KPI day/fuel/catalog/settings documents and derived reports. Booking in-memory related models are hydrated from references; June 10 discussion explicitly distinguishes backend data/response shapes. |
| Collections | `users`, legacy `client_members`, `bookings`, `vehicle_makes`, `vehicle_types`, `vehicle_sizes`, `chassis`, `statuses`, `status_forms`, `status_fields`, `support` message subcollections, `role_access`, `pm_kpi_records`, `pm_fuel_entries`, `operations_catalog`, `sync_error_logs`; `manage_count/id/cache/support/notifications` and repair archives support identity/cache/notification workflows. |
| Authentication/authorization | Custom password comparison in `AuthRequest`, password present in User serialization/local session structures; FirebaseAuthBridgeService methods are no-ops. App role/ownership/write-boundary guards exist. Repository Firestore and Storage rules both permit all reads/writes. Deployed rules were not checked. |
| Server functions | Node 22 package with Firebase Admin/Functions. Pending-booking, assignment, chassis-check and support-message FCM triggers; five-minute Asia/Manila scheduled lifecycle maintenance, four-hour delivered cutoff, bounded 400-record query. Region in source `asia-southeast1`. Latest deployment/run state unknown. |
| Hosting/release | Firebase project configuration `ptc-mvp`; Vercel static `build/web` and `/download` route. Release script builds/prepares assets/commits/pushes. Tracked web bundles and historical production hash comparisons prove past artifacts; do not prove October 4 live version. |
| Offline/file handling | Browser persistent caches/mirrors and account-scoped durable queues, stable local identities, media staging/upload retries, local drafts/image caches, reference remapping, archive/cleanup claim safeguards. Storage durability depends on browser/device availability. |
| Performance | Shared replay stream, cached filtering/hydration/calculations, lazy viewport windows of 15, ID read pages 150/live ranges capped 151, yielding every 75 hydration documents and 150 serialization documents, native compression worker where supported, cooperative Excel ZIP/XML generation. Full logical dataset still retained. |
| Monitoring/diagnostics | Error outbox/log UI plus traces/context/watchdog and independent retries; 64 local diagnostic index shards, at most 20 eligible bodies per batch, local acknowledged receipt limit 512; remote logs not automatically deleted. No complete uptime/infra/budget-monitoring system established. |
| Integrations | Firebase services, browser FCM/PWA, DOCX/XML/ZIP and XLSX template processing. No GPS, banking/payment, external ERP/accounting, public freight marketplace or third-party dispatch integration established. |

## F. WHAT IS ACTUALLY WORKING

Source and named regression tests establish working paths for booking creation/status actions, schedules and crew assignment, numeric/offline identities, chassis lifecycle/reservations, offline cache/queue replay, conflict preservation/review, photo commit safety/retry, Support/read markers, billing document generation, KPI calculations/stores, rates/fuel/crew/incidents, investor calculation/scope/exports, utilization, and responsive/lazy/selection behavior. These are bounded **implemented and test-covered** functions, not a complete live operational certification. [S2–S12]

### Recorded testing and validation

| Evidence | What was tested / learned | Limits |
| --- | --- | --- |
| May workflow feedback | User exercised flows, including failing ongoing→delivered, assignment selectors, cancellation validation and scroll behavior; requests changed repeatedly | Developer/user feedback, not signed client acceptance or a formal pilot |
| August production/login/Moreta feedback | Real user-observed app symptoms and displayed operational records | Does not prove an entire release passed all roles |
| `sync-freeze-follow-up.md` | 198 native and 30 Chrome checks; repeated scoped-status events and unchanged retry writes corrected | Not measured production FPS/heap or resolution of every browser crash |
| `disposed-view-crash.md` | Exact disposed-engine assertion reproduced in signed-out headless debug hot restarts; five subsequent restarts without assertion; 200 native/eight Chrome tests | Not full sustained user crash reproduction, hardware-GPU or authenticated stress certification; shader/Firestore hot-restart errors remain separately unproven |
| September 23 reviews | Production-source baseline 313 default tests versus evolving current suites 463/469/491; targeted fault probes reproduced account ownership, post-commit waits, chassis reservation, cache and diagnostic races | Counts reflect different revisions/stages; passing fault probes initially confirmed undesirable behavior, not correctness |
| September 23 final expanded verification | 496 full tests, 65 Chrome checks, clean analyzer, successful JS release; real-SDK local Firestore emulator: 11 scenarios, two clean native-network runs, no uncaught JS errors/renderer crashes | Synthetic users; request/ViewModel harness; queue-service reconstruction, not full browser-process restart; no Firebase Auth/Storage/live deployed rules or every UI role/device |
| October 3 preserved verification logs | `/private/tmp/selection-full-tests.log`: **1,038 passed**; `/private/tmp/selection-complete-chrome.log`: **22 passed**; `/private/tmp/selection-complete-analyze.log`: **no issues** | Historical verification checkout `/private/tmp/webapp-sync-count-verification`; logs read during research, not newly run tests or independently certified exact current-source equivalence [S12] |
| Current regression inventory | Dispatcher October 2 conflicts/fifteen photos; helper19 delivery history; Booking 83 chassis and Booking 86 uploaded-delivery retry; superseded assignment and production-sync recovery fixtures | Fixture/service regressions are not proof that every live pending item was repaired or receipt confirmed |

An artificial Firestore network-toggle harness produced an internal assertion (`b815`/watch-stream error); native-browser-network emulator runs passed. The review explicitly preserves this as an investigation/test-method limit, not a proven production cause or a claim that the SDK defect was fixed. [S6]

Evidence of iterative demos/developer use and operational data feedback exists; formal discovery attendance, client UAT signoff, pilot scope, adoption percentages, accuracy certification, commercial outcomes and current function delivery receipts remain unknown.

## G. WHAT IS PLANNED

Only directions already documented are listed here. Completed work is not relabeled as future work merely because its introduction was once a request.

| Recorded direction / next step | Classification / current position | Evidence |
| --- | --- | --- |
| Management presentation organized around Where We Are Now / Where We Are Going / What We Need | Explicit future deliverable; deliberately not created in this task | [S1] |
| Full authenticated release/operational checks with real role accounts, actual data, Storage, permissions, reconnect/conflicts | Documented validation need; broad signoff still unestablished | September 23 review/predeploy limits |
| Physical-device/GPU, long-duration memory and large-fleet timing/Firestore-cost profiling | Documented measurement need; no completed general production result | Performance and verification docs |
| Private per-account versus shared non-sensitive field history | Pending product decision; local history exists, remote private history not enabled | `docs/field-type-history.md` |
| Secure authenticated server-side boundary for private history and role/ownership protection | Documented prerequisite; intentionally permissive internal MVP today | Field-history docs; review permissions section; C4959 |
| Truly bounded per-screen datasets with server-backed search/count/export/KPI paths | Architecture direction described as necessary for further scale; no committed implementation promise or completed backend replacement | `docs/performance-followup-2026-09-23.md` |
| Mixed old/new browser-client rollout checks and reload | Recorded release requirement for cooperating locks/photo claims and migration compatibility | Review reports/photo safety |
| Workbook historical data migration/backfill/production acceptance | Explicitly not performed in KPI docs; any future import/backfill needs a separate decision | `docs/pm-kpi.md` |

No evidence establishes a confirmed migration to a named scalable backend stack, multi-branch launch, public backloading marketplace, payment gateway, GPS integration, investor fundraising target, staffing plan, or dated feature roadmap. Investor and utilization requests already have code, so their entire concepts cannot be placed in “not yet built.” No broader public-facing business plan can be inferred from an internet-accessible Vercel URL.

## H. WHAT WAS DISCARDED

1. **Original backloading MVP/concept as the solution to current operations:** discarded according to user-reported history because deeper discovery revealed a different operating model. Exact abandoned source/features/tests unknown. [S1]
2. **Earlier target/rating assumptions:** ₱280,000 monthly equivalent/₱70,000 weekly and 45% target/allowance-based rating were replaced as described in D. Historical workbook labels may still say 45%. [S3; C4372, C4525–C4526]
3. **Separate Payroll Summary and Driver/Helper Income UI:** replaced by integrated financial/Transaction History workspace; underlying calculation/export data was retained. [S3]
4. **Current KPI automatic Excel-import/PDF-format-menu direction:** toolbar import removed; workbook used as layout reference; fleet export Excel-only. Some import/report source and tests remain, so deletion of all code is not asserted. [S3]
5. **Independent current sub-client role:** current normalization absorbs sub-client/member into client; legacy data references remain. [S11]
6. **Premature photo cleanup, unsafe assignment displacement, repeated cache/status work and diagnostic index race paths:** replaced by commit-intent cleanup, reservation/activation ownership, guards/coalescing and locks. These are implementation corrections, not abandoned business requirements. [S4–S8]

Automatic private remote field history is **deferred**, not an implemented feature subsequently removed. The headless forced-freeze probe was rejected as invalid evidence for real production rendering reliability; that is a discarded test conclusion, not a discarded product feature. [S6, S8]

## I. CURRENT GAPS

The current product is an implemented internal operational MVP with substantial functionality and regression coverage. User explicitly described permissive security as intentional for the internal MVP on October 3 Manila time; do not misrepresent it as an accidental departure from their authorized scope. It still does not establish a secure production/public boundary. [C4959; S11]

Evidence-backed gaps, without priority ranking:

- Original discovery/backloading materials and precise engagement milestones are unavailable; business chronology before visible development remains partially user-reported.
- No full current authenticated live end-to-end acceptance across all roles, real uploads/functions/deployed rules/indexes, real-device concurrency and long-duration background/resume was established by the available reviews.
- Custom application password storage/comparison, no-op Firebase-auth bridge and allow-all repository rules separate current role UI from enforceable server authorization. Actual deployed configuration is unknown.
- Latest Git release/build does not alone establish the current hosted bundle or current deployed Cloud Functions. Historical production hash comparisons are dated evidence.
- Legacy bookings may lack explicit PM mapping/delivery times, hold unresolved identity/assignment histories, or need operator reconciliation; no mass backfill/repair completion can be claimed. Older deleted chassis links/files cannot be reconstructed by the new guards.
- Fuel, salary, routes, incidents, cost agreements, document details and billing flags still require valid input/review; zero shown or a visible rating is not proof of complete accounts.
- Collections/receivables aging, bank reconciliation, actual salary/investor payout, maintenance scheduling and broader sales pipeline are unestablished rather than confirmed roadmap commitments.
- Full logical booking data and retained diagnostics can still consume substantial memory/disk/read cost; lazy rows and bounded requests do not make total storage or memory bounded.
- Old tabs/clients may not participate in newer diagnostic locks, cleanup claims, history/reservation protections; rollout compatibility requires checking/reload.
- Documentation/comments conflict with current features in places, especially investor ownership/access, rating completeness, import/output options and earlier cost/target rules.

### What we need, limited to recorded evidence

| Category | Supported need or unresolved prerequisite | What is not established |
| --- | --- | --- |
| People | Access to authorized office/manager, client and crew participants for real operational validation; operator review of ambiguous booking/PM/conflict records | Named hires, team size, staffing budget or outsourcing plan |
| Development | Complete documented validation/remaining defect investigation; preserve identity/conflict/media safeguards; future bounded-data architecture if pursued; reconcile stale product documentation | A committed rewrite or named new backend framework |
| Infrastructure | Appropriate staging/test accounts/environment and real Firebase/Storage/Functions checks; mixed-client rollout verification | Approved staging procurement, current cloud spend, new hosting provider |
| Technology | Existing Flutter/Firebase/Vercel/PWA/export foundation; recorded tooling for emulator/browser validation and template regeneration | Required technology purchase or external integration contract |
| Data | Confirm fuel/salary/rates/incidents; PM/delivery attribution and archive-backed conflict decisions; distinguish layout template from live imported data | Complete migration dataset, approved historical backfill, current balances |
| Security | Authenticated server boundary before private remote history or dependable public role/ownership isolation | Signed production security scope, completed live audit, deployed enforcement |
| Operations | Defined record entry/confirmation, offline-conflict handling, current-browser rollout and document/billing review | Full operating SOP or support-service commitments |
| Business decisions | Private/shared history decision; confirm financial rules/cost agreements and investor commercial terms; interpretation of completeness/rating display | Signed revenue-share agreement or confirmed expansion/public marketplace strategy |
| Budget | No evidenced amount or approved cost forecast | No budget figures should be invented; KPI operating allocations are not project-development budgets |
| Management support | User reports boss confirmed 40% target; eventual presentation is requested; rules/acceptance decisions need actual accountable approval | Formal sponsor/approver identity, governance plan, investment authorization |
| Client/user validation | Authenticated role-specific smoke/acceptance and real device/network/data scenarios explicitly remain useful/required in reviews | Formal pilot signoff or quantified benefits |

## J. SCALABILITY

### Already implemented

Multiple users/clients/PMs/crew/chassis records, built-in/custom application capabilities, investor-ID scoping, transactional numeric reservations, version/identity checks, shared streams, account-scoped persistent queues/caches and per-PM/day deterministic KPI records form the existing multi-user foundation. Chassis supports multiple advance reservations without multiple simultaneous physical owners. Rate snapshots and original event times avoid repricing/reordering history during delayed sync. [S2–S5, S9]

Performance work includes 15-row lazy display batches, 150-document read pages, bounded live ID ranges, shared hydration/filtering/calculation results, cooperative serialization/workbook generation, optional native compression worker and sharded diagnostics. Dynamic extra PM/fuel rows in Excel support fleets beyond the reference workbook's original sample blocks. [S3, S8, S10]

### Architecture/design prepared

MVVM boundaries, repository interfaces, request/services separation, cached/offline persistence, common ownership/version policies and explicit complete-cache semantics enable extension. These foundations are present but do not demonstrate load capacity, cloud autoscaling behavior, secure multitenancy, branch isolation, or a backend migration already completed. Application investor scoping is not secure database tenant isolation under allow-all rules. [S2, S8, S9, S11]

### Recorded further direction / limits

Performance docs specifically identify that true bounded per-screen data requires separate server-backed search/count/export/KPI paths; current bounded pages still read and retain the full logical dataset. Cold load reads, listener count and cache memory can grow with fleet history. Further measurements and authenticated/network/device acceptance are documented needs. No branch architecture, externally accessible freight platform, named integration roadmap or numerical scale target was found. [S8; section G]

## K. EVIDENCE / SOURCE

`Cxxxx` citations link to dated direct conversations in the companion evidence register. File references below are relative to this report, and identify source families for all major inventory claims. Git commit chronology and complete tracked-source/test/asset inventory are in the companion source inventory.

| ID | Source | Supports |
| --- | --- | --- |
| S1 | [October 4 attached request](</Users/adrycallencatapang/.codex/attachments/23552cef-aee3-4487-99bd-33ebdb0de749/Pasted text.txt>) | User-reported discovery/backloading/pivot/B2B difficulties; requested future presentation and report structure |
| S2 | [codex.md](../../codex.md); booking/status/form/field models, `status_form_engine.dart`, booking requests/VMs | Architecture, naming, workflows, numeric identity, bounded repair/archive/reconciliation, role status structure, UX conventions |
| S3 | [pm-kpi.md](../pm-kpi.md); `lib/services/kpi/pm_kpi.dart`, rules/cost/crew/fleet/template services; PM/KPI dialogs and tests | Financial/pay/rate rules, evolution, ledgers, incident ownership, reports, manual-input requirements |
| S4 | [offline-write-audit.md](../offline-write-audit.md); mutation/media/upload/cleanup queues and offline tests | Offline paths, account scope, ordering, retained actions, support/photo/resource/lifecycle fixes and limits |
| S5 | [chassis-reservations.md](../chassis-reservations.md); chassis request/lifecycle services and reservation/history tests | Reservation versus physical ownership, lifecycle, history limits |
| S6 | [predeploy-verification-2026-09-23.md](../reviews/predeploy-verification-2026-09-23.md); all `docs/reviews` comparison/fix reports | Dated production-baseline hashes, defect reproductions/fixes, test counts, browser/emulator methodology and limits |
| S7 | [booking-photo-safety.md](../booking-photo-safety.md); photo commit/removal/retry/recovery tests | Durable staging, committed cleanup intent/claims, background upload and race handling |
| S8 | [performance-followup-2026-09-23.md](../performance-followup-2026-09-23.md), [booking-data-performance.md](../booking-data-performance.md), [lazy-list-audit.md](../lazy-list-audit.md), [field-type-history.md](../field-type-history.md), [sync-freeze-follow-up.md](../sync-freeze-follow-up.md), [disposed-view-crash.md](../disposed-view-crash.md), [sync-error-logs.md](../sync-error-logs.md) | Performance improvements/limits, local-history security prerequisite, crash/debug findings, diagnostics |
| S9 | `lib/services/investor_scope.dart`, `investor_reporting_scope.dart`, `investor_commission.dart`, `investor_commission_rate_store.dart`, `investor_expense_bridge.dart`; investor statement VM/dialog/workbook; investor tests | Investor operational association/silo, capabilities, commission/approved costs/person-days, scope/reporting implementation and limits |
| S10 | `lib/views/admin/admin_kpi_tracking.dart`, `kpi_utilization_view.dart`, `lib/services/kpi/kpi_utilization.dart`, `fleet_kpi.dart`, `kpi_diagnostic_policy.dart`; KPI and dispatcher/helper October fixtures/tests | Overview, total/utilization, current diagnostics policy and operational regressions |
| S11 | `pubspec.yaml`, Firebase/Vercel/index/CORS/rule configs, scripts/functions; `auth.request.dart`, `firebase_auth_bridge_service.dart`, `dispatcher_access_config.dart`, user/booking/vehicle models, Dashboard VM and DOCX export service | Current stack/version, custom auth/open rules, roles/data, hosting/function code, billing outputs |
| S12 | [Preserved log excerpts and original-log hashes](paltranco-verification-evidence.md); `/private/tmp/selection-full-tests.log`, `/private/tmp/selection-complete-chrome.log`, `/private/tmp/selection-complete-analyze.log`; October 3 session links and `69ceff2` selection tests | Historical 1,038 default tests, 22 Chrome checks, clean analyzer and latest selection-related implementation; no new run claimed |

The research intentionally uses local project evidence rather than outside industry material. No generic logistics practice is used to fill a missing project record.

## L. UNCERTAINTIES / CONFLICTS

1. **Project beginning:** discovery/backloading dates, requester, attendees, precise questions, original scope/features/test outcomes and discard date are not recoverable from identified contemporaneous sources. May 25 conversation and June 10 commit are lower-bound evidence of visible development, not the engagement beginning.
2. **Backloading source:** no original MVP repository/artifact was identified. Current operational workflow must not be retroactively described as the original backloading MVP.
3. **Latest deployment:** version/build `1.0.0+45` exists locally/Git; historical production comparisons concern earlier versions. No October 4 live bundle/rules/Functions state checked.
4. **Version chronology:** September 23 `1.0.1+13` followed by September 24 `1.0.0+14`. Do not infer chronology from semantic version alone or call this an identified business rollback.
5. **Stale role documentation:** top of `codex.md` lists client/admin/driver/helper; current capability model also includes investor/dispatcher/manager and custom roles. Current source governs implemented role inventory.
6. **Investor ownership/comments:** statement-dialog copy says no investor login and instructs setting a truck Investor ID; current VehicleMake has no owner field and derives association from crew. September 29 request/current scoped admin views support later investor reporting. These stale statements cannot all represent the current design simultaneously.
7. **Investor default versus configurable access:** named portfolio/trips/fleet/earnings capabilities do not prove matching standalone screens. Default investor grants deny dashboard/PM KPI; permission-enabled reporting paths exist. Deployed grants and real investor accounts are unknown.
8. **Historical ownership:** deriving owner from current canonical crew can change statement association when crew links change; immutable legal ownership/transfer history is not established. No independent acceptance of this financial consequence found.
9. **Financial revisions:** old PM docs include ₱70,000/week, 45% and allowance rating; newer decisions/current code use ₱350,000/month and 40% default. Reference workbook labels can retain 45%; template reference is not proof of current business target.
10. **Rating completeness:** PM documentation says incomplete expenses prevent a final margin rating; current `KpiRatingRules.grossRating` receives `complete` but calculates a rating regardless, with a comment to rate current amounts while checks remain unresolved. An “Excellent/Failed” label is not proof of confirmed financial completeness.
11. **Costs:** fixed buffer specification coexists with approved actual-override code. Full-month ₱50,000/₱58,000 is the default, not necessarily every selected period or every approved override. Early ₱160,000 admin-cost statement is not an automated current Excel data source.
12. **Import/PDF:** earlier docs describe import/PDF; later docs remove toolbar import and state Excel-only fleet output. Code/tests remain. Historical implementation and current exposed workflow must be distinguished.
13. **Missing mapping/errors:** suppressing historical no-PM notices or obsolete KPI diagnostics does not restore attribution or validate earnings. Unknown dates/PMs can still exclude trips from utilization.
14. **Expense consent:** office-recorded `approved`/agreement flag is not an authenticated investor approval signature. Current wording about “next period” is not proof of effective-dated consent enforcement.
15. **Validation counts:** 198/200/313/463/469/491/496 and later 1,038 refer to different dates/revisions/environments. No test total should be described as one current live end-to-end result.
16. **Historical ephemeral evidence:** review `/tmp` paths may disappear; logs directly read during this research support their recorded pass messages, but do not establish exact current-source equivalence or independently certify every earlier temporary artifact.
17. **Reported operations versus observed software:** Moreta data/feedback corroborates use of operational terminology and records; this research did not observe on-site dispatch or audit customer/financial records. Formal pilot/demo/UAT scope remains unknown.
18. **Production readiness intention:** user says intentionally unsecure internal MVP; review security gaps remain real limits for public production, while the immediate requested “safe” verification concerned end-to-end functionality. Do not conflate either statement with security certification.

## Compact status table

| Item | Status | Evidence | Notes |
| --- | --- | --- | --- |
| Initial discovery meeting | Done — user-reported | S1 | Date/participants/minutes unknown |
| Original backloading MVP | Done / Discarded — user-reported | S1 | Original features/code/tests not identified |
| B2B requirements pivot | Done — user-reported, partly corroborated | S1; C3002; operational source | Precise pivot date unknown |
| Early MVVM/admin/mock development | Done / Designed | C0000–C0352; first Git tree | May precedes first commit |
| Users/login/profile/session | MVP | S11; auth/session/profile tests | Custom auth; no Firebase-auth bridge implementation |
| Driver/helper availability and assignments | MVP / Tested | C1334; role/booking tests | Current grants/forms govern actions |
| Booking creation/history/status workflow | MVP / Tested | S2, S4 | Configurable dependencies and required evidence |
| Forms/Fields/Statuses | MVP / Designed | S2 | Shared configurable flow engine |
| Vehicle catalogs and crew-linked PMs | MVP / Tested | S3, S11 | Optional helpers; historical mapping gaps |
| Chassis lifecycle/advance reservations | MVP / Tested | S5 | One physical owner, multiple reservations |
| Waybill/Delivery Form photos | MVP / Tested | S4, S7 | Physical capture/manual references remain |
| Billed/unbilled and past-unbilled | MVP / Tested | Dashboard VM; C3002 | Not payment collection status |
| BS/BT regular/hustling DOCX | MVP / Tested | S11; export tests | Export metadata/review remain manual |
| Support/chat/read markers/media | MVP / Tested | S4, S9, S11 | Live all-role acceptance unestablished |
| FCM alerts / lifecycle functions | MVP code | functions/index.js; function tests | Latest cloud deployment/delivery unknown |
| Offline mutation/media/cleanup queues | MVP / Tested | S4, S6, S7 | Local acceptance differs from server confirmation |
| Temporary IDs/repair/conflict archives | MVP / Tested | S2; repair/review tests | Explicit identity and operator decisions |
| PM financial KPIs / fuel / salary | MVP / Designed / Tested | S3; C4273–C4274 | Completeness depends on entered/confirmed data |
| ₱350,000 monthly PM revenue target | Done / Specified | C4372; current code | Earlier target replaced |
| 40% target and editable margin/incident rules | Done / Specified / Tested | C4525–C4526; rules tests | Current rating can display while incomplete |
| Maintenance/depreciation cost buffers/overrides | MVP | PM/cost override services | Not maintenance operations module |
| Locations/effective trip-share matrices | MVP / Tested | S3 | Confirmed historical snapshots preserved |
| Fleet overview / total / crew projections | MVP / Tested | S10; fleet/crew tests | Role/scope/data dependent |
| Daily/weekly/monthly utilization | MVP / Tested | C4815; S10 | Trip/activity counts, not capacity or timeliness |
| Fleet Excel template/export | MVP / Tested | S3, S8 | Admin cost manually entered; no production backfill |
| Earlier KPI import/PDF toolbar direction | Discarded / Replaced | S3 | Related code/test artifacts remain |
| Investor role/silos/commission/statement | MVP / Designed / Tested | S9; September 27 onward history | Actual contracts/payout/use unknown |
| Investor permission-enabled reporting | MVP / Specified | C4801; scoped views/store | Default grants may deny entry; stale comments |
| PWA/offline startup/install/release configuration | MVP / Tested in bounded checks | Git history; web/config/scripts | Current live deployment/device guarantee unknown |
| Performance/shared processing/lazy lists | Done / Tested | S8, S10 | Full logical dataset remains |
| Error diagnostics/recovery fixtures | MVP / Tested | S4, S6, S8, S10 | Does not prove every live error cleared |
| Local field history | MVP / Tested | S8 | Private remote history deferred |
| Private/shared remote-history decision | Discussed / Future | field-type-history.md | Requires product/security decision |
| Further server-backed bounded datasets | Designed / Discussed | S8 | No confirmed backend rewrite |
| Full current live acceptance / device/load validation | Planned validation need | S6, S8 | No broad signoff found |
| Collections/receivables/payment ledger | Unknown | Reviewed financial source | Do not invent implementation or roadmap |
| Maintenance scheduling / multi-branch / GPS | Unknown | Reviewed source/context | No supported commitment |
| Secure public-production boundary | Future prerequisite / incomplete | Rules/auth source; S8; C4959 | Intentional internal-MVP posture today |
| Staffing/budget/commercial expansion plan | Unknown | Available context | No amounts/headcounts invented |
| Management presentation | Planned | S1 | Not created |
