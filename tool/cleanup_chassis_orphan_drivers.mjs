#!/usr/bin/env node
// One-off cleanup: chassis with a driver assigned but NO current booking
// (current_driver_id set while current_booking_id is absent/null/empty).
//
// Matches the app's own clear-driver write semantics exactly:
//   - lib/requests/chassis.request.dart:408-449 (writeAssignmentOnline)
//   - uses FieldValue.delete() for current_driver_id when a prior chassis
//     is displaced / when the booking is removed (the field is deleted, not
//     set to null) so the client's `_asNullableText` maps it back to null.
//
// Default is DRY-RUN: it only counts and lists affected chassis, it makes no
// writes. Pass `--apply` to actually perform the fix.
//
// Targets the Firestore emulator by default (safe). To target production,
// authenticate with Application Default Credentials and pass
// `--project <project-id>`. ADC resolves from either:
//   - GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
//   - `gcloud auth application-default login` (a local ADC session)
// Safety guards for the production path:
//   - FIRESTORE_EMULATOR_HOST must be unset, so prod runs cannot silently hit
//     the local emulator.
//   - The project id the credentials resolve to must exactly match --project.
//   - Default mode is still DRY-RUN; writes require --apply.
//
// Usage:
//   FIRESTORE_EMULATOR_HOST=127.0.0.1:18081 \
//     node tool/cleanup_chassis_orphan_drivers.mjs                        # emulator dry-run
//   FIRESTORE_EMULATOR_HOST=127.0.0.1:18081 \
//     node tool/cleanup_chassis_orphan_drivers.mjs --apply                 # emulator apply
//   node tool/cleanup_chassis_orphan_drivers.mjs --project ptc-mvp        # prod dry-run
//   node tool/cleanup_chassis_orphan_drivers.mjs --project ptc-mvp --apply # prod apply

import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {createRequire} from 'node:module';

const require = createRequire(import.meta.url);
const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, '..');

// firebase-admin lives in functions/node_modules; reuse it so we only
// maintain a single admin dependency (no separate install).
const functionsDir = path.resolve(repoRoot, 'functions');
const requireFromFunctions = createRequire(path.join(functionsDir, 'package.json'));
const {initializeApp, applicationDefault} = requireFromFunctions('firebase-admin/app');
const {getFirestore, FieldValue} = requireFromFunctions('firebase-admin/firestore');

const apply = process.argv.includes('--apply');
const projectArg = (() => {
  const i = process.argv.indexOf('--project');
  return i >= 0 ? process.argv[i + 1] : null;
})();

// Firestore collection for chassis (matches lib/requests/chassis.request.dart resourceKey).
const CHASSIS_COLLECTION = 'chassis';
// manage_cache bump key (matches the app's manageCache version write).
const MANAGE_CACHE_KEY = 'chassis';

async function main() {
  // --- resolve target project: emulator unless a project is given ---
  let adminApp;
  let projectId;
  if (projectArg != null) {
    // Production: use Application Default Credentials. This resolves from
    // GOOGLE_APPLICATION_CREDENTIALS (service-account JSON) or from a local
    // `gcloud auth application-default login` session, whichever is present.
    // FIRESTORE_EMULATOR_HOST must NOT be set here, otherwise the Admin SDK
    // would silently talk to the local emulator while claiming to target prod.
    if (process.env.FIRESTORE_EMULATOR_HOST) {
      throw new Error(
        'FIRESTORE_EMULATOR_HOST is set while --project was given. ' +
          'Unset it so production is actually targeted, or drop --project ' +
          'to run against the local emulator.',
      );
    }
    adminApp = initializeApp({
      projectId: projectArg,
      credential: applicationDefault(),
    });
    projectId = projectArg;
    // Project-match guard: the Admin SDK must have resolved the exact project
    // we were told to target, so a stray --project can never redirect writes.
    const resolved = adminApp.options.projectId;
    if (resolved !== projectArg) {
      throw new Error(
        `Project mismatch: requested ${projectArg} but credentials resolve ` +
          `to ${resolved}. Refusing to write.`,
      );
    }
  } else {
    // Emulator: single-project mode uses the demo project; the port is
    // governed by FIRESTORE_EMULATOR_HOST.
    if (!process.env.FIRESTORE_EMULATOR_HOST) {
      throw new Error(
        'No FIRESTORE_EMULATOR_HOST set and no --project given. ' +
        'Run the emulator first, or pass --project with credentials.',
      );
    }
    adminApp = initializeApp({projectId: 'demo-paltranco-regression'});
    projectId = 'demo-paltranco-regression';
  }

  const db = getFirestore(adminApp);
  const now = new Date().toISOString();

  console.log(
    `[cleanup] target=${projectId} host=${process.env.FIRESTORE_EMULATOR_HOST ?? 'prod'} mode=${apply ? 'APPLY' : 'DRY-RUN'}`,
  );

  // --- find affected chassis: driver set, no booking ---
  const snapshot = await db.collection(CHASSIS_COLLECTION).get();
  const affected = [];
  let scanned = 0;
  for (const doc of snapshot.docs) {
    scanned++;
    const d = doc.data() ?? {};
    const driverId = d.current_driver_id?.toString().trim() ?? '';
    const bookingId = d.current_booking_id?.toString().trim() ?? '';
    if (driverId !== '' && bookingId === '') {
      affected.push({
        id: doc.id,
        name: d.name?.toString() ?? '',
        status: d.current_status?.toString() ?? '',
        driverId,
      });
    }
  }

  console.log(
    `[cleanup] scanned=${scanned} affected=${affected.length} ` +
      `(chassis with a driver but no current booking)`,
  );
  for (const a of affected.slice(0, 50)) {
    console.log(
      `  - chassis ${a.id} "${a.name}" status=${a.status} driver=${a.driverId}`,
    );
  }
  if (affected.length > 50) {
    console.log(`  ... and ${affected.length - 50} more`);
  }
  if (affected.length === 0) {
    console.log('[cleanup] nothing to fix.');
    return;
  }

  if (!apply) {
    console.log(
      '\n[cleanup] DRY-RUN — no writes made. Re-run with --apply to clear ' +
        'the driver reference on these chassis.',
    );
    return;
  }

  // --- apply: delete current_driver_id + bump manage_cache (matches app write) ---
  const BATCH_SIZE = 400;
  let updated = 0;
  const chunks = [];
  for (let i = 0; i < affected.length; i += BATCH_SIZE) {
    chunks.push(affected.slice(i, i + BATCH_SIZE));
  }
  for (const chunk of chunks) {
    const batch = db.batch();
    for (const a of chunk) {
      const ref = db.collection(CHASSIS_COLLECTION).doc(a.id);
      batch.set(ref, {
        current_driver_id: FieldValue.delete(),
        updated_at: now,
      }, {merge: true});
    }
    // One manage_cache bump per chunk mirrors the app bump on save.
    const cacheRef = db.collection('manage_cache').doc(MANAGE_CACHE_KEY);
    batch.set(cacheRef, {version: now, updated_at: now}, {merge: true});
    await batch.commit();
    updated += chunk.length;
    console.log(`[cleanup] applied ${updated}/${affected.length}`);
  }

  console.log(
    `\n[cleanup] DONE — cleared driver reference on ${updated} chassis. ` +
      `manage_cache/${MANAGE_CACHE_KEY} bumped so devices re-sync.`,
  );
}

main().then(
  () => process.exit(0),
  (err) => {
    console.error(`[cleanup] FAILED: ${err?.message ?? err}`);
    process.exit(1);
  },
);
