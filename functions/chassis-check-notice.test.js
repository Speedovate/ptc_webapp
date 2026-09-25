// Exercises the real notifyChassisCheck handler with a stubbed admin SDK, so the
// wiring in index.js (not just the pure helper) is covered: the chassis lookup,
// the guard clauses, and the exact payload that reaches FCM.
const {test} = require('node:test');
const assert = require('node:assert/strict');

const sent = [];
const staffUsers = {
  docs: [
    {id: '8', data: () => ({id: '8', role: 'dispatcher', is_active: true})},
    {id: '9', data: () => ({id: '9', role: 'admin', is_active: true})},
    {id: '10', data: () => ({id: '10', role: 'helper', is_active: true})},
    {id: '11', data: () => ({id: '11', role: 'manager', is_active: false})},
  ],
};

const db = {
  collection(name) {
    if (name === 'users') {
      return {where: () => ({get: async () => staffUsers})};
    }
    if (name === 'manage_notifications') {
      // The real code chains where('user_id').where('platform').get().
      const query = {
        get: async () => ({docs: [{data: () => ({token: 'token-1'})}]}),
      };
      query.where = () => query;
      return query;
    }
    if (name === 'chassis') {
      return {
        doc: (id) => ({
          get: async () => ({
            exists: global.__chassisDocs__[id] !== undefined,
            data: () => global.__chassisDocs__[id],
          }),
        }),
      };
    }
    throw new Error(`unexpected collection ${name}`);
  },
};

global.__chassisDocs__ = {};
global.__admin__ = {
  db,
  messaging: {
    sendEachForMulticast: async (message) => {
      sent.push(message);
      return {successCount: message.tokens.length};
    },
  },
};

const Module = require('node:module');
const originalLoad = Module._load;
Module._load = function (request, parent, isMain) {
  if (request === 'firebase-admin/firestore') {
    return {getFirestore: () => db};
  }
  if (request === 'firebase-admin/messaging') {
    return {getMessaging: () => global.__admin__.messaging};
  }
  if (request === 'firebase-admin/app') {
    return {initializeApp: () => ({})};
  }
  if (request === 'firebase-functions/v2/firestore') {
    // Strip the trigger decorator so the raw handler can be called directly.
    const passthrough = (_opts, handler) => handler;
    return {onDocumentCreated: passthrough, onDocumentUpdated: passthrough};
  }
  if (request === 'firebase-functions/v2/scheduler') {
    return {onSchedule: () => () => {}};
  }
  return originalLoad(request, parent, isMain);
};

const {notifyChassisCheck} = require('./index');

function run(after, before = {client_status: 'delivered'}) {
  sent.length = 0;
  return notifyChassisCheck({
    data: {
      before: {data: () => before},
      after: {data: () => after},
    },
    params: {bookingId: String(after.id)},
  });
}

test('names the chassis only when the booking still holds it', async () => {
  global.__chassisDocs__ = {
    '2': {id: '2', name: '20-02', current_booking_id: '89'},
  };
  await run({id: '89', client_status: 'check', chassis_id: '2'});
  assert.equal(sent.length, 1);
  const [message] = sent;
  assert.equal(message.data.title, 'Check Chassis');
  assert.equal(
    message.data.body,
    'Booking 89: chassis #20-02 needs client confirmation.',
  );
  assert.equal(message.data.chassisVerified, 'true');
  assert.equal(message.data.heldByBookingId, '89');
  assert.equal(message.data.chassisId, '2');
  // Only staff roles receive it, and only when the status just became check.
  assert.deepEqual([...new Set(message.tokens)], ['token-1']);
});

test('production booking 140 no longer points staff at the wrong vehicle', async () => {
  global.__chassisDocs__ = {
    '1': {id: '1', name: '20-01', current_booking_id: '100'},
  };
  await run({id: '140', client_status: 'check', chassis_id: '1'});
  const [message] = sent;
  assert.equal(message.data.chassisVerified, 'false');
  assert.equal(message.data.heldByBookingId, '100');
  assert.match(message.data.body, /recorded on Booking 100/);
  assert.doesNotMatch(
    message.data.body,
    /^Booking 140: chassis #20-01 needs client confirmation\.$/,
    'must not claim this trip holds chassis 1',
  );
});

test('a missing chassis document still alerts, without inventing a vehicle', async () => {
  global.__chassisDocs__ = {};
  await run({id: '91', client_status: 'check', chassis_id: '8'});
  const [message] = sent;
  assert.equal(message.data.chassisVerified, 'false');
  assert.match(message.data.body, /no longer on file/);
  assert.equal(message.data.chassisId, '8');
});

test('no alert when the booking did not just enter check, or names no chassis', async () => {
  global.__chassisDocs__ = {'3': {id: '3', name: '20-03', current_booking_id: '89'}};
  await run({id: '89', client_status: 'check', chassis_id: '3'}, {client_status: 'check'});
  assert.equal(sent.length, 0, 'already at check before this update');
  await run({id: '89', client_status: 'check', chassis_id: ''});
  assert.equal(sent.length, 0, 'no chassis recorded');
  await run({id: '89', client_status: 'delivered', chassis_id: '3'});
  assert.equal(sent.length, 0, 'not yet at check');
});
