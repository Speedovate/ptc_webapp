// Recheck inside the write transaction: a scheduler query can already be stale.
async function advanceDeliveredBooking(db, reference, dueAt, now) {
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) return false;
    const data = snapshot.data();
    const deliveredAt = data.delivered_at;
    if (String(data.client_status || '').trim().toLowerCase() !== 'delivered' ||
        !String(data.chassis_id || '').trim() ||
        typeof deliveredAt !== 'string' ||
        !Number.isFinite(Date.parse(deliveredAt)) ||
        Date.parse(deliveredAt) > Date.parse(dueAt)) return false;
    transaction.set(reference, {
      client_status: 'check', driver_status: 'check', helper_status: 'check', updated_at: now,
    }, {merge: true});
    return true;
  });
}
module.exports = {advanceDeliveredBooking};
