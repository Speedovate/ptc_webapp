const {test} = require('node:test');
const assert = require('node:assert/strict');
const {chassisCheckNotice} = require('./chassis-notices');

test('a chassis the booking still holds is named plainly', () => {
  const notice = chassisCheckNotice(
    {id: '89', chassis_id: '2'},
    {id: '2', name: '20-02', current_booking_id: '89'},
  );
  assert.equal(notice.chassisVerified, true);
  assert.equal(notice.heldByBookingId, '89');
  assert.equal(notice.title, 'Check Chassis');
  assert.equal(notice.body, 'Booking 89: chassis #20-02 needs client confirmation.');
});

test('a chassis another booking now holds is never named as this trip vehicle', () => {
  // Production case: booking 140 reports chassis 1, which the server still has
  // loaded on booking 100. Telling staff "chassis #20-01" would send them to the
  // wrong vehicle.
  const notice = chassisCheckNotice(
    {id: '140', chassis_id: '1'},
    {id: '1', name: '20-01', current_booking_id: '100'},
  );
  assert.equal(notice.chassisVerified, false);
  assert.equal(notice.heldByBookingId, '100');
  assert.equal(notice.title, 'Check Chassis');
  assert.match(notice.body, /Booking 100/);
  assert.match(notice.body, /Confirm with dispatch/);
});

test('an unassigned chassis is reported as unconfirmed rather than assumed', () => {
  const notice = chassisCheckNotice(
    {id: '144', chassis_id: '4'},
    {id: '4', name: '20-04', current_booking_id: null},
  );
  assert.equal(notice.chassisVerified, false);
  assert.equal(notice.heldByBookingId, '');
  assert.match(notice.body, /no current trip recorded/);
});

test('a deleted chassis document is reported instead of guessed at', () => {
  const notice = chassisCheckNotice({id: '91', chassis_id: '8'}, null);
  assert.equal(notice.chassisVerified, false);
  assert.equal(notice.chassisId, '8');
  assert.match(notice.body, /no longer on file/);
});

test('numeric and string booking ids compare the same', () => {
  const notice = chassisCheckNotice(
    {id: '89', chassis_id: 2},
    {id: 2, name: '20-02', current_booking_id: 89},
  );
  assert.equal(notice.chassisVerified, true);
  assert.equal(notice.body, 'Booking 89: chassis #20-02 needs client confirmation.');
});

test('a chassis with no name falls back to its id without breaking', () => {
  const notice = chassisCheckNotice(
    {id: '89', chassis_id: '2'},
    {id: '2', current_booking_id: '89'},
  );
  assert.equal(notice.chassisVerified, true);
  assert.equal(notice.body, 'Booking 89: chassis #2 needs client confirmation.');
});
