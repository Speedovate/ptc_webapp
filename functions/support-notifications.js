'use strict';

const staffRoles = new Set(['admin', 'manager', 'dispatcher']);
const id = value => String(value ?? '').trim();

// Match the support inbox: staff see all threads, other users only their own.
function supportRecipients(thread, senderId, users) {
  const sender = id(senderId);
  const requester = id(thread.requester_user_id);
  if (!sender || !requester) return [];
  return [...new Set(users.filter(user => user.is_active !== false &&
    id(user.id) !== sender &&
    (staffRoles.has(id(user.role).toLowerCase()) || id(user.id) === requester))
    .map(user => id(user.id)).filter(Boolean))];
}

function supportPreview(message) {
  const text = id(message.text);
  if (text) return text;
  const count = Array.isArray(message.attachments) ? message.attachments.length : 0;
  return count === 1 ? 'Sent an attachment' : `Sent ${count} attachments`;
}

module.exports = {supportRecipients, supportPreview};
