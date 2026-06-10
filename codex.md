# Paltranco Development Basis

This file is the working basis for succeeding development in Paltranco.

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

Paltranco is a trucking and logistics MVP.

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
  - `Paltranco`
  - `Digital Platform`
- `Digital Platform` should be slightly smaller than `Paltranco`, readable, and not bold
- do not place an extra `SizedBox` spacer between those two text lines
- do not add helper subtext below that two-line brand stack

Keep the header minimal, premium, and consistent with the current purple Paltranco branding.

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
