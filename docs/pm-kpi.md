# Per-prime-mover KPI

Vehicles → Makes → View opens the PM KPI modal. New/Edit vehicle behavior is unchanged. Driver and helper use the existing user-details modal. Driver and helper can be assigned in New/Edit Vehicle Make. KPI displays the helper assigned to the make; an unassigned make stays unassigned instead of borrowing a helper from an older booking. Chassis is taken from individual bookings and is not a fixed bundle member. Helper is optional and can be cleared using Not assigned; existing trip earnings retain the crew recorded on each booking. The helper_id reference uses existing user-ID remapping during offline sync.

## Rules

- Calendar dates use Asia/Manila (UTC+8), independently of browser timezone.
- Week 1: days 1–7; Week 2: 8–14; Week 3: 15–21; Week 4: 22–month-end.
- Revenue uses non-cancelled booking amounts on original Created dates. Delivered trip earnings use original Delivered dates, including offline action timestamps, never sync/Updated dates.
- Depreciation: 12,500/week; maintenance: 14,500/week. Exactly 50,000 + 58,000 for a whole month.
- Revenue goal: 70,000/week/PM. Gross-profit goal: 31,500/week/PM. No fixed 350,000 fleet goal.
- Separate margin benchmark: actual revenue × 45%. Favorable/unfavorable compares actual gross profit against that benchmark.
- One delivered booking counts as one matrix trip. Multiple booking copies with the same submission identity are counted once; conflicting copies keep the result provisional. A cancelled booking with a recorded delivery requires salary review rather than silently erasing earned pay.
- Daily pay: 455 per driver/helper with at least one delivery that day, plus matrix trip shares. City Proper trips 1–4 pay 100/50, subsequent CP trips that day pay 150/75. Corrected Narra: 500/250; Brooke’s Point: 700/350. Additional hustling fulls: 100/50; empties: 50/25.
- Manager selects/confirms the trip's matrix route; exact matching destinations can preselect it. Unknown destinations are not guessed. Rates and crew/chassis references are saved with the daily earnings confirmation.
- Editable weekly rating allowance defaults to 10,000. Excellent: gross > goal + allowance; Failed: gross < goal − allowance; inclusive band: Satisfactory.
- Monthly allowance/targets multiply by four. For custom ranges, allocations and allowance use the fraction of each covered business week. This makes adjacent custom ranges reconcile to a full month. Maximum custom range: 367 calendar days.
- Admin cost (160,000/month) belongs to fleet net income, not per-PM gross profit; no admin deduction in this modal.

## Completeness and persistence

Fuel ledger totals and salary confirmation are recorded per calendar day. Explicit confirmed zero is different from missing data. A changed delivered-trip set or changed trip details invalidate salary confirmation. Future days cannot be confirmed. Missing values, unverified cached reads, queued changes, identity conflicts or missing delivery timestamps keep the result provisional; no final rating is shown.

The feature writes only the new `pm_kpi_records`, `pm_fuel_entries`, and `operations_catalog` collections. IDs are deterministic per PM/day, not sequential booking IDs. Existing booking, vehicle, chassis and user documents are not rewritten. New provisional PMs must finish syncing before KPI entries can be attached. Existing numeric-ID reservations and ID repair are unchanged.

Reads occur on modal open, period change or manual refresh. Daily summaries are lazy. Booking updates use the existing shared booking stream only while the modal is mounted, and cancel on close. No additional recurring timer is introduced.

Writes reuse the existing account-scoped persisted offline mutation queue, action timestamps and optimistic-version conflict checks. Concurrent first creates cannot overwrite another manager's record. Local cached entries survive closing/reopening and queue drain. Blocked conflicts are surfaced through the existing Queued Actions review flow. Server reads use document-ID ranges and require no composite index. Existing Firebase access rules are unchanged; production deployment must permit authorized access to the new collections.

UI access requires vehicle-makes read, bookings read, and the new PM KPI read capability; editing uses PM KPI update. User links respect users-read access. There is no Excel import, production backfill, deployed function, or production data migration in this change.

## Validation

Calculation tests cover calendar boundaries/leap years, custom-range allocation, Philippine dates, independent revenue/delivery periods, cancellation and identity deduplication, pay/matrix rules, completeness, and rating boundaries. Queue tests use fake Firestore to exercise offline → online persistence, account isolation, idempotent replay and concurrent-write protection. Widget tests exercise mobile/desktop layout, filters, editable allowance, user-link visibility and dismissal/subscription cleanup. These tests do not substitute for a production-data acceptance run.

## Locations and trip-share administration

Vehicles → Makes → Locations & Trip Shares opens shared origin, destination, barangay, city/municipality, and trip-share settings. The same settings are accessible from the PM KPI modal. Existing defaults are retained; route points are added to origin/destination choices without pretending they are municipalities. Existing Puerto Princesa barangay visibility rules remain unchanged.

Renamed/removed choices remain valid for historical records but are not offered for new selections. City edits propagate to both origin and destination; those two lists can also be customized independently. Forms hydrate from the account cache and perform a bounded server refresh. There is no permanent catalog listener or new retry loop.

Trip shares include distance, aliases, active status, daily pay, City Proper excess-trip premium, and hustling rates. Each edit publishes a new effective-dated immutable matrix document and updates settings in one optimistic-version transaction. Daily confirmations store their matrix snapshot, so new rates do not reprice confirmed historical earnings. Concurrent edits are blocked for review rather than overwriting another manager's changes.

## Fuel and income ledgers

The PM KPI modal has Fuel Ledger and Driver/Helper Income actions. Fuel entries record original fuel date, PO/receipt reference, supplier, optional liters/unit price/odometer, amount, and notes. Liters × price suggests the amount; the receipt amount can be entered directly. Edits keep prior versions. Void excludes an entry from totals while retaining its history. An entry's original date cannot be edited; void and recreate to correct a wrong date.

When adding the first ledger entry to a day with an old positive daily fuel aggregate, a deterministic legacy entry preserves that aggregate once. Additional entries are summed without counting the old aggregate twice. Any changed total/signature requires the manager to reconfirm the day's fuel. New positive fuel amounts are entered through the ledger; the daily form still permits confirming zero. The ledger total includes recorded ledger entries; legacy daily amounts remain in KPI totals until converted.

Driver/helper income shows confirmed daily pay, per-trip shares, hustling counts, and saved crew/chassis references. Days worked and revenue derive from deliveries and bookings, avoiding duplicate manual ledgers. Depreciation and maintenance retain the confirmed fixed-cost rules; no actual repair expense is added on top of the 58,000 maintenance allocation. A changed trip signature, including origin/destination barangays, requires salary review and does not overwrite the prior confirmation.

Fuel entries have stable document IDs before upload and reuse the existing persisted queue; they do not reserve or change booking numbers. No production backfill or deployment has been performed. Fake-Firestore and widget tests cover offline migration, edits/voids, atomic matrix publishing, stale edit protection, and mobile/desktop form entry; live production-data acceptance remains separate.

## Dynamic role access and offline availability

Role Access exposes separate PM KPI read/update, fuel ledger read/update, driver/helper income read, and locations/trip-share read/update permissions. New keys default ON only for admin, and OFF for dispatcher, manager, client, driver, helper, and custom roles. Existing role documents lacking these keys use those defaults without altering their other permissions. Vehicle Makes read still controls the parent page; a role without KPI access retains the original vehicle-details View action.

Settings permissions control administration, not using location choices in an already-authorized booking form. Booking selectors continue consuming cached choices for every authorized booking role. Read permissions hide the corresponding financial/settings modals and updates are also checked at the write boundary. Open modals react to role-access changes. These are application access checks, not replacement Firestore Security Rules; existing server rules are unchanged.

Role configurations use the existing persisted role-access cache and queue. KPI, fuel, and catalog data use account-scoped persistent caches and the existing mutation queue. Previously loaded data and locally saved changes remain available offline after reopening; never-downloaded remote data cannot be supplied offline. Fresh-store tests verify disk-backed cache restoration and account separation, in addition to offline queue replay tests.

## Shared UI

KPI daily records, income, fuel entries/history, and location/matrix lists use the existing `AdminModalRecordList` titles rows, responsive item cards, and content-based column widths. Actions use the shared admin action buttons; selectors use `AdminDropdownFormField`; editors use the existing admin form decoration and modal text fields. KPI summary cards use `AdminListItemCard` and `AdminListResponsiveField`. The shared modal shell retains selection and outside-tap dismissal. Populated desktop/mobile tables, nested edit forms, period filters, and saves are covered by widget and Chrome tests.

### Shared locations and trip shares

Locations & Trip Shares now has one list and one editor per location. `locations`
in operations settings stores the canonical name, kind, aliases and active flag.
Cities/municipalities and areas feed both origin/destination selectors; barangays
feed both barangay selectors. Legacy direction-specific options are merged when
reading older settings, and known matrix aliases are consolidated. Saves mirror
legacy option keys for existing readers. Old names remain accepted for historical
records; booking documents are not rewritten.

Optional driver/helper rates are edited alongside the location. Both must be
provided together; blank amounts mean no configured rate, not zero pay. Rates
still use immutable effective-date versions and confirmed salary snapshots stay
unchanged. Location and new matrix version changes use the existing atomic queued
catalog save, role permissions and account-scoped offline cache.

## Ledger and report additions (September 2026)

- Fuel Ledger displays total non-voided liters, the count of entries without
  liters, unit price, and notes/route in addition to its amount total.
- Exported payroll summaries group the selected dates into the configured four
  monthly weeks. The separate Payroll Summary UI has been removed; use the
  financial breakdown and expandable daily Transaction History in the KPI modal.
- Export / Print downloads Excel or a printable PDF containing the full period's
  financial comparison, payroll summary, transactions, fuel, and issues. Display
  pagination does not restrict exported rows. The PDF uses PHP and a standard
  Latin font; Excel retains Unicode text and numeric amounts.
- Import Excel accepts PALTRANCO monthly ledger sheets for the selected PM. It
  ignores calculated monthly/weekly summaries and total rows. The preview starts
  with no selected rows and shows 15 at a time. Missing dates and combined salary
  splits require administrator input. Original source sheet/row and period are
  retained. Nothing is imported until Import Selected is pressed.
- Fuel imports reuse stable IDs and the account-scoped offline queue. Repeated
  sources already in the local ledger are skipped. Server version conflicts keep
  the existing record rather than overwriting it.
- Historical salary import is restricted to months without delivered-trip
  payroll and dates without existing KPI records, to avoid duplicating calculated
  earnings. Existing booking payroll is reviewed through its salary editor.
- This is a UI implementation; the workbook has not been migrated to production.

## Consolidated KPI workspace

Makes → View opens the selected PM's KPI workspace. The section controls at the
start of its summary switch the existing modal to Fuel Ledger,
Locations & Trip Shares, or Import Excel. Back to KPI
restores the selected period and summary scroll position and refreshes totals
through the existing store. Only the active section is mounted; switching does
not add a second dialog route or preload every ledger. Individual record editors
and date pickers remain focused dialogs.

Income & Expenses, Performance vs Plan, crew totals, Transaction History,
Export / Print, and diagnostic Copy remain in the summary. KPI-enabled roles no
longer see the duplicate catalog shortcut above the Makes list. Catalog-only
roles retain that shortcut so their existing permission still has an entry.
Section permissions, calculations, persistence, and sync storage are unchanged.


## Daily transaction history

Transaction History replaces the separate Driver / Helper Income section. Each
worked day starts collapsed with driver, helper, and combined earnings totals.
Tap its date or expand action to see the salary and individual booking shares;
tap again to collapse. Days and their transactions are newest first. Salary is
grouped under the worked day while retaining its next-day midnight posting time.
Child rows retain booking navigation, status, timestamps, and edit actions.
The expanded rows share the modal's single lazy viewport and 15-row load batches.
Export continues to include every individual transaction regardless of expansion
or pagination; no daily summary rows are added to the transaction export.


## Rating rules

The allowance-based rating editor is replaced by per-PM Rating Rules, persisted
through the existing settings store and offline queue. Gross-income rating uses
actual gross income / actual revenue: below 40% Failed, 40% to below 51%
Satisfactory, and 51% or higher Excellent. Fractional values are not rounded
before classification. Incomplete expenses prevent a final margin rating; zero
revenue is Not rated. Editable complaint defaults are 0 Excellent, 1 Satisfactory,
and 2+ Failed. Accident defaults are 0 Excellent, 1+ Failed.

The owner confirmed 40% replaces the previous 45% financial target. The target
percentage is separately editable in Rating Rules. At the default, the monthly
350,000 revenue target corresponds to a 140,000 gross-income goal.

Authorized KPI editors record complaints and accidents per date and PM through
Record Complaints / Accidents. Weekly/monthly/custom views sum the same dated
observations, through today only, without duplicating counts. Unrecorded days
prevent a final incident rating. An unchecked-by-default option lets the editor
explicitly confirm other unrecorded days in the selected period as zero; existing
counts are retained. Future dates cannot be confirmed. Settings and original
recorded-at/by metadata use the existing local cache, offline queue, and version
conflict checks. Editing a count retains the prior settings in revision history.


### Per-user complaints and accidents

Driver and Helper cards show recorded complaint and accident counts above Trip
Shares, Salary, and Total, with separate square plus actions for authorized
editors. The editor defaults to that user and one additional incident for the
chosen metric; nothing is saved until Save. An actual replacement may be selected
from cached crew/users or previously recorded replacements. Entries retain
user ID/name/role, PM context, incident date, and original recording metadata.
They are stored separately per user under `user_incident_counts` in the existing
PM settings document, preserving revision and offline conflict handling.

Changing a truck assignment never reattributes these counts. Each user has their
own period ratings, and recorded replacements remain visible in the ratings
section. Zero on a card means zero recorded incidents, not proof that missing
days were confirmed. Existing zero-day confirmation applies only to the selected
user. Legacy `incident_counts` remain separate and are marked unassigned; they
are never automatically copied to the currently assigned crew.


### Fleet workbook export (September 22 update)

Import Excel has been removed from the KPI toolbar; the workbook is a structure
reference, not a source of automatic imports. Export reads the whole fleet on
request, including inactive PM records, for the selected period only. It does
not add listeners or perform writes. KPI export supports Excel only.

Excel uses the actual layouts extracted from `KPI-2026-new.xlsx`, bundled as
`assets/export_templates/kpi-2026-layout.xlsx`. Only selected-month ledger tabs,
Monthly, and selected-month weekly tabs are exported, in that order. Original
month-specific columns, styles, widths, row heights, merged headings and page
settings are retained. October–December extend the September layout. Additional
PMs repeat the existing PM block; extra fuel entries insert styled rows without
dropping transactions. Monthly keeps the original month positions, with data only
for selected months; cross-year ranges have separate year-labelled columns.

Regenerate the sanitized asset using `python3 scripts/prepare_kpi_template.py
/path/to/KPI-2026-new.xlsx`. This removes transactions, cached formula results,
staff remarks and external references while keeping presentation and labels.
The export fills data from the app and regenerates totals and internal Monthly
links. Excel print areas cover the complete exported sheets rather than the
reference's accidentally truncated ranges. January's Monthly gross-income label
merges are removed when January is selected so they do not hide its results.

The four existing app-defined weeks and selected-date filtering still apply;
this layout change does not redefine payroll periods. The template's fifth-week
slots remain empty. Admin cost stays blank because it has no app data source;
net income calculates only after an admin cost is entered in Excel. Historical
sample amounts are never used as defaults. No additional Data Checks tab is
included in Excel, to keep the requested sheet structure; completeness details
remain in the KPI dialog. The Export button opens a date-range confirmation and then downloads Excel, without a format menu.
Export requires KPI, bookings, fuel and trip-income read access.
