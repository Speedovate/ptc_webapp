# Lazy rendering audit

Long record lists now use bounded builder viewports:

- Admin Bookings and Dashboard completed bookings; export candidate selection.
- Users, Chassis, vehicle makes/types/sizes, Forms, Fields, Statuses and Access roles.
- Client booking history and driver/helper assigned bookings.
- Shared profile/user-detail booking history across roles.
- Support conversations, topic groups and messages.
- Booking ID conflict selection/comparison rows and Sync Review conflict cards.
- Searchable picker results (already used builders).

Page lists use a single vertical sliver viewport. The export form keeps a bounded
candidate-selection viewport so its editable controls stay mounted. Booking
conflict review opts into a bounded modal body with its own viewport; ordinary
modals keep the previous scroll behavior. Full conflict JSON is built only when
expanded. Sync Review no longer uses a shrink-wrapped list.

Intentionally retained eager groups:

- Editable and reorderable form fields, validation controls, and form previews.
- Fixed navigation, toolbars, permission toggles and analytics metric cards.
- Chart axis labels (part of the chart), booking details within a record, and
  attachments within a single chat message or current draft.

These are not independent long record-list pages. Changing them to scrolling
lists would need separate UX/state handling, particularly for unsaved input.

Tests cover 1,000-item fixtures, narrow/wide layouts, actions, filtering, live
fixture updates, and conflict-review guards. This verifies rendering behavior;
it does not measure authenticated production performance. Data fetching,
filtering and chart calculations can still have costs independent of row layout.
No Firestore mutation, offline queue or ID resolution logic changed in this work.
