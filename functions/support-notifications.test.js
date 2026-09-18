const {test} = require('node:test');
const assert = require('node:assert/strict');
const {supportRecipients, supportPreview} = require('./support-notifications');
const users = ['admin', 'manager', 'dispatcher', 'client', 'driver', 'helper']
  .map(role => ({id: role, role}));
for (const role of ['client', 'driver', 'helper', 'admin', 'manager', 'dispatcher']) {
  test(`support reply reaches ${role}, excluding sender and unrelated accounts`, () => {
    const sender = role === 'admin' ? 'manager' : 'admin';
    const recipients = supportRecipients({requester_user_id: role}, sender, users);
    assert.ok(recipients.includes(role));
    assert.ok(!recipients.includes(sender));
    for (const other of ['client', 'driver', 'helper']) {
      if (other !== role) assert.ok(!recipients.includes(other));
    }
  });
}
test('requester message goes to active staff only, deduplicated', () => {
  assert.deepEqual(supportRecipients({requester_user_id: 'driver'}, 'driver', [
    ...users, users[0], {id: 'disabled', role: 'admin', is_active: false},
  ]), ['admin', 'manager', 'dispatcher']);
});
test('missing identities cannot broadcast', () => {
  assert.deepEqual(supportRecipients({}, 'driver', users), []);
  assert.deepEqual(supportRecipients({requester_user_id: 'driver'}, '', users), []);
});
test('attachment previews match thread summaries', () => {
  assert.equal(supportPreview({text: ' Hi '}), 'Hi');
  assert.equal(supportPreview({attachments: [{}]}), 'Sent an attachment');
  assert.equal(supportPreview({attachments: [{}, {}]}), 'Sent 2 attachments');
});
