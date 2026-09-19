const {test} = require('node:test');
const assert = require('node:assert/strict');
const {advanceDeliveredBooking} = require('./chassis-workflow');
const due = '2026-09-19T04:00:00Z';
const now = '2026-09-19T08:00:00Z';
for (const status of ['delivered', 'empty', 'return', 'confirm', 'cancelled']) {
  test(`scheduler rechecks live ${status} status before changing booking`, async () => {
    let writes = 0;
    const data = {client_status: status, delivered_at: due, chassis_id: '3'};
    const db = {runTransaction: (fn) => fn({
      get: async () => ({exists: true, data: () => data}),
      set: (_, patch, options) => { writes++; assert.equal(patch.client_status, 'check'); assert.equal(options.merge, true); },
    })};
    await advanceDeliveredBooking(db, {}, due, now);
    assert.equal(writes, status === 'delivered' ? 1 : 0);
  });
}
test('not-yet-due, missing chassis and missing dates stay unchanged', async () => {
  for (const extra of [{delivered_at: now}, {delivered_at: null}, {delivered_at: 'bad'}, {chassis_id: ''}]) {
    const data = {client_status: 'delivered', delivered_at: due, chassis_id: '3', ...extra};
    await advanceDeliveredBooking({runTransaction: (fn) => fn({
      get: async () => ({exists: true, data: () => data}),
      set: () => assert.fail('must not update'),
    })}, {}, due, now);
  }
});
