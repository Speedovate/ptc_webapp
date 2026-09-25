'use strict';

// The chassis number on a booking is the vehicle that ran the trip, which is not
// the same question as whether that vehicle is still assigned to the trip. A
// late status report can name a chassis that another booking has since taken, so
// a notice must never send staff to a vehicle the booking does not hold.
//
// This module is deliberately pure so the wording can be tested without Firestore.

const id = value => String(value ?? '').trim();

/**
 * Describes what staff should be told when a delivered booking needs checking.
 *
 * `verified` is true only when the chassis document still lists this booking as
 * its current trip. In every other case the notice names the booking that does
 * hold the vehicle instead of asserting a chassis the trip does not own.
 */
function chassisCheckNotice(booking, chassis) {
  const bookingId = id(booking.id);
  const chassisId = id(booking.chassis_id);
  const chassisName = id(chassis && chassis.name);
  const label = chassisName ? `chassis #${chassisName}` : `chassis #${chassisId}`;
  const holderId = id(chassis && chassis.current_booking_id);

  if (!chassis) {
    return {
      chassisId,
      chassisVerified: false,
      heldByBookingId: '',
      title: 'Check Chassis',
      body: `Booking ${bookingId}: ${label} is no longer on file. Confirm with dispatch which vehicle to check.`,
    };
  }
  if (holderId && holderId === bookingId) {
    return {
      chassisId,
      chassisVerified: true,
      heldByBookingId: bookingId,
      title: 'Check Chassis',
      body: `Booking ${bookingId}: ${label} needs client confirmation.`,
    };
  }
  if (holderId) {
    return {
      chassisId,
      chassisVerified: false,
      heldByBookingId: holderId,
      title: 'Check Chassis',
      body: `Booking ${bookingId}: ${label} is recorded on Booking ${holderId} instead. Confirm with dispatch before release.`,
    };
  }
  // No current trip on the chassis document, so the assignment cannot be
  // confirmed either way. Say so rather than imply the trip still holds it.
  return {
    chassisId,
    chassisVerified: false,
    heldByBookingId: '',
    title: 'Check Chassis',
    body: `Booking ${bookingId}: ${label} has no current trip recorded. Confirm with dispatch which vehicle to check.`,
  };
}

module.exports = {chassisCheckNotice};
