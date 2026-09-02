const {onSchedule} = require('firebase-functions/v2/scheduler');
const {initializeApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');

initializeApp();

const db = getFirestore();
const workflowVersionRef = db.collection('manage_cache').doc('chassis_workflow_v1');
const workflowRoles = ['client', 'admin', 'driver', 'helper', 'manager', 'dispatcher'];
const staffRoles = ['admin', 'manager', 'dispatcher'];

exports.maintainChassisWorkflow = onSchedule(
  {
    schedule: 'every 5 minutes',
    timeZone: 'Asia/Manila',
    region: 'asia-southeast1',
  },
  async () => {
    await ensureChassisWorkflowConfiguration();
    await advanceDueDeliveredBookings();
  },
);

async function ensureChassisWorkflowConfiguration() {
  const marker = await workflowVersionRef.get();
  if (marker.exists) return;

  const now = new Date().toISOString();
  await db.runTransaction(async transaction => {
    const currentMarker = await transaction.get(workflowVersionRef);
    if (currentMarker.exists) return;

    const [statusesSnapshot, formsSnapshot, fieldsSnapshot] = await Promise.all([
      transaction.get(db.collection('statuses')),
      transaction.get(db.collection('status_forms')),
      transaction.get(db.collection('status_fields')),
    ]);
    const statuses = statusesSnapshot.docs.map(doc => ({id: doc.id, ...doc.data()}));
    const forms = formsSnapshot.docs.map(doc => ({id: doc.id, ...doc.data()}));
    const fields = fieldsSnapshot.docs.map(doc => ({id: doc.id, ...doc.data()}));
    let nextStatusId = nextNumericId(statuses);
    let nextFormId = nextNumericId(forms);
    let nextFieldId = nextNumericId(fields);

    const requiredStatuses = [
      ['check', 'Confirm with the client whether the chassis is empty.'],
      ['empty', 'Assign a driver to return the chassis.'],
      ['return', 'The assigned driver must confirm the chassis return.'],
      ['confirm', 'Chassis has been returned and is ready for use.'],
    ];
    for (const [key, description] of requiredStatuses) {
      if (statuses.some(status => normalize(status.key) === key)) continue;
      const id = String(nextStatusId++);
      transaction.set(db.collection('statuses').doc(id), {
        id,
        key,
        label: 'Delivered',
        description,
        applicable_roles: workflowRoles,
        role_messages: roleMessagesFor(key),
        sort_order: nextStatusId,
        is_active: true,
        created_at: now,
        updated_at: now,
      });
    }

    const assignedCancellation = forms.find(form =>
      normalize(form.current_status_key) === 'assigned' &&
      normalize(form.next_status_key) === 'cancelled',
    );
    if (assignedCancellation) {
      transaction.set(db.collection('status_forms').doc(assignedCancellation.id), {
        roles: staffRoles,
        role: 'admin',
        updated_at: now,
      }, {merge: true});
    }

    const returnDriverFieldId = ensureField({
      key: 'return_driver_id',
      title: 'Return Driver',
      type: 'dropdown',
      placeholder: 'Select Return Driver',
      option_source_key: 'drivers',
      required: true,
    });
    const locationFieldId = ensureField({
      key: 'chassis_location',
      title: 'Chassis Location',
      type: 'text',
      placeholder: 'Enter location or Google Maps link',
      required: true,
    });

    ensureForm({
      current: 'check',
      next: 'empty',
      button: 'Confirm Empty',
      roles: staffRoles,
      fieldIds: [locationFieldId],
    });
    ensureForm({
      current: 'empty',
      next: 'return',
      button: 'Assign Return',
      roles: staffRoles,
      fieldIds: [returnDriverFieldId],
    });
    ensureForm({
      current: 'return',
      next: 'confirm',
      button: 'Confirm Return',
      roles: ['driver'],
      fieldIds: [],
    });
    ensureForm({
      current: 'confirm',
      next: null,
      button: null,
      roles: workflowRoles,
      fieldIds: [],
    });

    transaction.set(workflowVersionRef, {
      version: 1,
      updated_at: now,
      created_at: now,
    });

    function ensureField(input) {
      const existing = fields.find(field => normalize(field.key) === input.key);
      if (existing) return String(existing.id);
      const id = String(nextFieldId++);
      transaction.set(db.collection('status_fields').doc(id), {
        id,
        is_active: true,
        options: [],
        created_at: now,
        updated_at: now,
        ...input,
      });
      return id;
    }

    function ensureForm(input) {
      const existing = forms.find(form =>
        normalize(form.current_status_key) === input.current &&
        normalize(form.next_status_key) === (input.next || '') &&
        normalize(form.button_text) === normalize(input.button),
      );
      if (existing) return;
      const id = String(nextFormId++);
      transaction.set(db.collection('status_forms').doc(id), {
        id,
        role: input.roles[0],
        roles: input.roles,
        is_main_form: true,
        current_status_key: input.current,
        next_status_key: input.next,
        status_text: null,
        status_subtext: null,
        button_text: input.button,
        field_ids: input.fieldIds,
        field_overrides: {},
        dependencies: [],
        blocked_message: '',
        is_active: true,
        created_at: now,
        updated_at: now,
      });
    }
  });
}

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

function nextNumericId(records) {
  return records.reduce((highest, record) => {
    const value = Number.parseInt(String(record.id || ''), 10);
    return Number.isFinite(value) ? Math.max(highest, value) : highest;
  }, 0) + 1;
}

function normalize(value) {
  return String(value || '').trim().toLowerCase();
}

function roleMessagesFor(status) {
  if (status === 'check') {
    return {
      client: 'Chassis confirmation is in progress.',
      driver: 'No chassis action is required.',
      helper: 'No chassis action is required.',
      admin: 'Confirm with the client whether the chassis is empty.',
      manager: 'Confirm with the client whether the chassis is empty.',
      dispatcher: 'Confirm with the client whether the chassis is empty.',
    };
  }
  if (status === 'empty') {
    return {
      client: 'The chassis is empty and waiting for return assignment.',
      driver: 'No chassis action is required.',
      helper: 'No chassis action is required.',
      admin: 'Assign a driver to return the chassis.',
      manager: 'Assign a driver to return the chassis.',
      dispatcher: 'Assign a driver to return the chassis.',
    };
  }
  if (status === 'return') {
    return {
      client: 'The chassis is being returned.',
      driver: 'Confirm once the chassis has returned.',
      helper: 'The chassis is being returned.',
      admin: 'Wait for the assigned driver to confirm return.',
      manager: 'Wait for the assigned driver to confirm return.',
      dispatcher: 'Wait for the assigned driver to confirm return.',
    };
  }
  return Object.fromEntries(workflowRoles.map(role => [role, 'Chassis has been returned and is ready for use.']));
}
