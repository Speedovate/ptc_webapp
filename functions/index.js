const {onSchedule} = require('firebase-functions/v2/scheduler');
const {onDocumentCreated, onDocumentUpdated} = require('firebase-functions/v2/firestore');
const {initializeApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {getMessaging} = require('firebase-admin/messaging');

initializeApp();

const db = getFirestore();
const staffRoles = ['admin', 'manager', 'dispatcher'];

// Sends a booking-created notification without changing Firestore. Foreground
// users receive alert.mp3 from the Flutter booking alert service.
exports.notifyPendingBooking = onDocumentCreated(
  {
    document: 'bookings/{bookingId}',
    region: 'asia-southeast1',
  },
  async event => {
    const booking = event.data.data() || {};
    if (normalize(booking.client_status) !== 'pending') {
      return;
    }

    const staffSnapshot = await db.collection('users')
      .where('role', 'in', staffRoles)
      .get();
    const recipientIds = staffSnapshot.docs
      .filter(document => document.data().is_active !== false)
      .map(document => String(document.data().id || document.id).trim())
      .filter(Boolean);
    if (recipientIds.length === 0) return;

    const tokenSnapshots = await Promise.all(recipientIds.map(userId =>
      db.collection('manage_notifications')
        .where('user_id', '==', userId)
        .where('platform', '==', 'web')
        .get(),
    ));
    const tokens = [...new Set(tokenSnapshots.flatMap(snapshot =>
      snapshot.docs
        .map(document => String(document.data().token || '').trim())
        .filter(Boolean),
    ))];
    if (tokens.length === 0) return;

    const bookingId = String(booking.id || event.params.bookingId);
    await getMessaging().sendEachForMulticast({
      tokens,
      data: {
        notificationId: `booking-pending-${bookingId}`,
        bookingId,
        title: 'New Booking',
        body: `Booking #${bookingId} is waiting for assignment.`,
        url: 'https://paltranco.vercel.app/',
      },
      webpush: {
        fcmOptions: {link: 'https://paltranco.vercel.app/'},
      },
    });
  },
);

exports.maintainChassisWorkflow = onSchedule(
  {
    schedule: 'every 5 minutes',
    timeZone: 'Asia/Manila',
    region: 'asia-southeast1',
  },
  async () => {
    await advanceDueDeliveredBookings();
  },
);

// This is deliberately separate from maintainChassisWorkflow. It only reads
// the delivered -> check transition and sends FCM; it never writes Firestore.
exports.notifyChassisCheck = onDocumentUpdated(
  {
    document: 'bookings/{bookingId}',
    region: 'asia-southeast1',
  },
  async event => {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};
    if (normalize(before.client_status) === 'check' ||
        normalize(after.client_status) !== 'check' ||
        !String(after.chassis_id || '').trim()) {
      return;
    }

    const staffSnapshot = await db.collection('users')
      .where('role', 'in', staffRoles)
      .get();
    const recipientIds = staffSnapshot.docs
      .filter(document => document.data().is_active !== false)
      .map(document => String(document.data().id || document.id).trim())
      .filter(Boolean);
    if (recipientIds.length === 0) return;

    const tokenSnapshots = await Promise.all(recipientIds.map(userId =>
      db.collection('manage_notifications')
        .where('user_id', '==', userId)
        .where('platform', '==', 'web')
        .get(),
    ));
    const tokens = [...new Set(tokenSnapshots.flatMap(snapshot =>
      snapshot.docs
        .map(document => String(document.data().token || '').trim())
        .filter(Boolean),
    ))];
    if (tokens.length === 0) return;

    const bookingId = String(after.id || event.params.bookingId);
    const chassisId = String(after.chassis_id).trim();
    await getMessaging().sendEachForMulticast({
      tokens,
      data: {
        notificationId: `chassis-check-${bookingId}`,
        bookingId,
        chassisId,
        title: 'Check Chassis',
        body: `Booking #${bookingId}: chassis #${chassisId} needs client confirmation.`,
        url: 'https://paltranco.vercel.app/',
      },
      webpush: {
        fcmOptions: {link: 'https://paltranco.vercel.app/'},
      },
    });
  },
);

// Sends the assignment notification without changing Firestore. The booking
// document is already the source of truth for client, driver, and helper IDs.
exports.notifyBookingAssignment = onDocumentUpdated(
  {
    document: 'bookings/{bookingId}',
    region: 'asia-southeast1',
  },
  async event => {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};
    if (normalize(before.client_status) !== 'pending' ||
        normalize(after.client_status) !== 'assigned') {
      return;
    }

    const recipientRoles = new Map([
      [String(after.client_id || '').trim(), 'client'],
      [String(after.driver_id || '').trim(), 'driver'],
      [String(after.helper_id || '').trim(), 'helper'],
    ]);
    const recipients = [...recipientRoles.entries()]
      .filter(([userId]) => Boolean(userId));
    if (recipients.length === 0) return;

    const bookingId = String(after.id || event.params.bookingId);
    await Promise.all(recipients.map(async ([userId, role]) => {
      const tokenSnapshot = await db.collection('manage_notifications')
        .where('user_id', '==', userId)
        .where('platform', '==', 'web')
        .get();
      const tokens = [...new Set(tokenSnapshot.docs
        .map(document => String(document.data().token || '').trim())
        .filter(Boolean))];
      if (tokens.length === 0) return;

      const body = role === 'client'
        ? `Your booking #${bookingId} has been assigned to a driver and helper.`
        : `You have been assigned to booking #${bookingId}.`;
      await getMessaging().sendEachForMulticast({
        tokens,
        data: {
          notificationId: `booking-assigned-${bookingId}-${userId}`,
          bookingId,
          title: 'Booking Assigned',
          body,
          url: 'https://paltranco.vercel.app/',
        },
        webpush: {
          fcmOptions: {link: 'https://paltranco.vercel.app/'},
        },
      });
    }));
  },
);

async function advanceDueDeliveredBookings() {
  const dueAt = new Date(Date.now() - 4 * 60 * 60 * 1000).toISOString();
  const snapshot = await db.collection('bookings')
    .where('client_status', '==', 'delivered')
    .where('chassis_id', '>', '')
    .where('delivered_at', '<=', dueAt)
    .limit(400)
    .get();
  if (snapshot.empty) return;

  const batch = db.batch();
  const now = new Date().toISOString();
  for (const document of snapshot.docs) {
    // The query filters these already; retain this guard for malformed legacy data.
    const chassisId = String(document.data().chassis_id || '').trim();
    if (!chassisId) continue;
    batch.set(document.ref, {
      client_status: 'check',
      driver_status: 'check',
      helper_status: 'check',
      updated_at: now,
    }, {merge: true});
  }
  await batch.commit();
}

function normalize(value) {
  return String(value || '').trim().toLowerCase();
}
