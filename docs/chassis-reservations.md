# Shared chassis reservations

Booking `chassis_id` is the reservation/history link. Multiple bookings may
reference the same chassis, with independent `driver_id` and `helper_id` values.
Chassis `current_booking_id` and `current_driver_id` describe its physical
assignment; assigning another advance booking must not overwrite them.

`pending` and `assigned` bookings reserve the chassis. A new reservation does not
acquire the physical pointer or change its status/location. Starting a trip
acquires the chassis transactionally. Another active owner blocks activation,
while preserving the saved reservation. Confirmation releases the current owner;
cancelling or editing another reservation cannot release that owner's chassis.

For compatibility, a legacy pointer to a ready, pending/assigned booking remains
readable and editable. Actual activation of another reserved booking may replace
that ready pointer, without deleting the legacy booking's chassis link. A loaded
or returning chassis is never displaced this way.

Direct booking writes, queued booking updates, offline booking creation and the
chassis editor use the same ownership decision. Coalesced chassis-editor actions
retain every selected booking link, including when replayed after reconnect.
Existing identity/version conflict checks remain in place.

The history lists linked bookings as Reserved, Active or Historical, with each
booking's saved driver/helper and pickup schedule. This is not an immutable audit
of every crew edit: the booking's saved assignment is displayed. Links deleted by
older clients cannot be reconstructed without historical source data.

Regression coverage: `test/chassis_reservations_test.dart`, booking lifecycle and
replay tests, plus the mobile/desktop `test/chassis_action_history_test.dart`.
