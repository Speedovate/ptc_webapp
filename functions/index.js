const {onSchedule} = require('firebase-functions/v2/scheduler');
const {onDocumentUpdated} = require('firebase-functions/v2/firestore');
const {initializeApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {getMessaging} = require('firebase-admin/messaging');

initializeApp();

const db = getFirestore();
const staffRoles = ['admin', 'manager', 'dispatcher'];

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
    const response = await getMessaging().sendEachForMulticast({
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
    console.log(
      `notifyChassisCheck booking=${bookingId} sent=${response.successCount} failed=${response.failureCount}`,
    );
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
