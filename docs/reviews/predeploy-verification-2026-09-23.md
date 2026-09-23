# Pre-deployment verification — September 23, 2026

Scope: verify the current local candidate after the three cache/listener/diagnostic
fixes. The initial pass below made no application edits or account logins. The
expanded pass at the end adds a bounded queue fix and synthetic local-emulator
account tests. No deployment or production business writes were performed.
The user has no staging/test accounts.

## Automated results

| Check | Result | What it establishes |
| --- | --- | --- |
| Full Flutter suite | 496 passed | Existing unit/widget/request regressions, including offline actions, booking/chassis lifecycle, photos, support, KPI and account flows |
| Expanded Chrome suite | 65 passed | Browser storage/queue reopening, replay, image persistence, cache recovery, locking, and selected account/booking/photo/chat tests |
| Static analysis | No issues | Analyzer checks on the final source |
| JavaScript release build | Passed | Final candidate compiles as the normal web release |
| Diff whitespace check | Passed | No whitespace errors in tracked changes |

Chrome backend interactions in those tests use fake Firestore/storage. Real browser
persistence and cross-context locking are exercised; real Firebase permissions,
authentication, Storage, latency and production account transitions are not.

Commands:

```sh
flutter test --reporter expanded
flutter analyze --no-pub
flutter test --platform chrome --reporter expanded test/web test/native_date_input_web_test.dart test/sync_error_log_service_test.dart test/paged_booking_source_test.dart test/sync_transition_regression_test.dart test/sync_diagnostic_outbox_test.dart test/online_transition_regression_test.dart test/auth_request_session_test.dart test/booking_chassis_request_flow_test.dart test/booking_photo_commit_safety_test.dart test/support_message_identity_test.dart test/support_manual_retry_test.dart
flutter build web --release --output /tmp/ptc-predeploy-release
```

The existing Wasm dry-run warning for `in_app_browser_guard.dart` / `dart:html`
remains; the normal JavaScript build succeeds. WebAssembly was not the target.

## Candidate identity

- Version remains 1.0.1+9; no version bump was made.
- 365 source/test/web/asset/package files were hashed in
  `/tmp/ptc-predeploy-source-manifest.json`.
- Manifest SHA-256: `f01496982d4fb400d08c4a540d54651fbc0bbcb75ff6e1020ff7ee4d61384f88`.
- Release output: `/tmp/ptc-predeploy-release` (tracked `build/web` is not refreshed).
- main.dart.js: 5,827,324 bytes; local gzip: 1,649,971 bytes.
- main.dart.js SHA-256: `7df193c683ddb9633d73fded82c5bb69d90383c75398bb2e6ae19e95451982cc`.

The deployment script commits/pushes all workspace changes and serves `build/web`.
It was not run. A later deployment must build/package the reviewed source rather
than assume the existing tracked bundle contains these fixes.

## Release browser checks and limits

The release was served locally with a fresh isolated headless Chrome profile. A
test hostname was marked secure in Chrome so the production service-worker path
could run; localhost deliberately disables registration in this app. No user was
signed in. Screenshots, browser exceptions, visibility, animation-frame activity,
long tasks and heap snapshots were recorded.

An initial forced `Page.setWebLifecycleState(frozen/active)` sequence left Chrome
hidden even after `active`; animation frames stopped on the subsequent reload.
Default macOS headless rendering also produced blank-content screenshots and
CVDisplayLink errors. The same initial sequence against the existing production
artifact produced the same blank-content symptoms. Those runs are inconclusive
for app foreground recovery, not evidence of a new candidate-specific regression.

The corrected sequence uses software rendering, explicit foreground/semantic
checks, and a real second-tab switch instead of forced freeze. It checks online
cold/warm loads, offline reload from the service-worker cache, tab return while
offline, reconnect, and reconnect reload. Final result: all eight observations retained the visible login screen, with
zero uncaught JavaScript exceptions and zero renderer crashes. Online/offline
state and the offline banner switched correctly. The only console error was the
expected Firestore `unavailable` warning while network access was deliberately
disabled. Screenshots were visually inspected, including offline reload and the
final reconnected reload.

| Release scenario | Result |
| --- | --- |
| Cold online load / warm reload | Login rendered |
| Offline transition | Login retained; offline banner appeared |
| Offline reload with active service worker | Login rendered from cached shell |
| Return from a second tab while offline | Login visible; frame callbacks resumed |
| Reconnect | Login retained; offline banner cleared |
| Reload after reconnect | Login rendered |

This is a short login-screen smoke check, not a no-freeze/no-leak guarantee.
Software rendering and a test secure-origin override were used. The first hardware
headless run remains unsuitable for judging physical-device GPU reliability.
No app source change was made in response to the invalid forced-freeze result.

Evidence: `/tmp/ptc-predeploy-browser-tabs/report.json` and its PNG screenshots;
runner: `/tmp/ptc-predeploy-smoke-tabs.mjs`. Logs: `/tmp/ptc-predeploy-full-tests.log`,
`/tmp/ptc-predeploy-chrome-tests.log`, `/tmp/ptc-predeploy-analyze.log`, and
`/tmp/ptc-predeploy-release.log`.

## Remaining release limits

- No authenticated live end-to-end test across admin/client/driver/helper; no
  staging or test accounts are available. Simulated-server tests cannot certify
  deployed Firebase rules, indexes, account access, uploads or actual conflicts.
- No physical mobile/device GPU, long-duration memory, or full authenticated
  fleet-data FPS benchmark. Login-screen timings do not measure booking lists,
  KPI, export or loaded support chats.
- All old tabs must reload on rollout to participate in the new diagnostic lock.
  Already-orphaned diagnostic index entries are not reconstructed by that fix.

Automated checks passing remove the known reproduced blockers, but do not establish
unconditional production safety. Authenticated release smoke checks remain the
release gate for a full production endorsement.


## Expanded verification: real SDK and local emulator

The final-source full suite passed **496 tests** again. The normal app source
change in this pass removes an unbounded, redundant booking conflict `get()`
before queue replay. The existing Firestore transaction still checks submission
identity and server version atomically; it rejects conflicting remote edits.
No conflict protection was intentionally removed.

A JavaScript release harness uses real application requests/view models, real
browser local queue storage and real Firestore transactions against
`demo-paltranco-regression` on `127.0.0.1:18081`. The browser runner switches
native Chrome networking through CDP, allowing the SDK to handle reconnection.
**11 scenarios passed in two clean-fixture runs**, with zero uncaught JavaScript
errors and zero renderer crashes:

- Driver and helper: offline Finish, Complete and Delivered; reconstruct queue
  service, reconnect, replay, preserve original action/creation timestamps,
  validate booking/chassis results, and replay again without changing the record.
- Two concurrent ID reservations skip an occupied ID; repeat reservation is
  idempotent and the occupied booking remains unchanged.
- App account login, admin impersonation of driver/helper, return to original
  admin, and logout, using synthetic emulator user records.
- Conflicting remote edit remains intact and the pending local action is retained.
- Admin and client offline creates retain action time and resolve numeric IDs.

“Reopen” in this harness means a newly constructed queue service reading persisted
browser storage, **not a full browser-process restart**. Firestore SDK persistence
is disabled to isolate the app's own local queue. These are request/view-model
integration tests in release mode, not a click-through of every production screen.
The harness overrides unrelated startup listeners. Firebase Auth/Storage, live
security rules/indexes, every role, long-lived listeners and uploads are not
certified by these results.

### Test-method findings

An earlier artificial test toggled `Firestore.disableNetwork()/enableNetwork()`
and overrode browser connectivity while keeping app services alive. That sequence
reproduced Firestore 12.14.0 internal assertion `b815`, with a watch-stream
`TypeError` reading `tt`; subsequent operations could stall. Removing the redundant
preflight alone did not resolve that assertion. A SDK-only ten-cycle transaction
probe passed, and both clean native-CDP network runs passed. Application `lib/`
does not call those SDK network-toggle methods. The artificial failure is retained
as a test-method/SDK investigation limit, **not a proven production root cause or
an assertion that the SDK problem was fixed**.

One repeat initially failed its fixed expected IDs because the prior run had
already reserved 4001/4002; it correctly allocated 4003/4004. The reusable runner
now resets only the explicitly named local demo emulator before each run.

Evidence: `/tmp/ptc-emulator-real-network-browser/report.json` and
`/tmp/ptc-emulator-browser-1790157860149/report.json`. Artificial-failure evidence:
`/tmp/ptc-emulator-release-browser/report.json`. Full-suite log:
`/tmp/ptc-final-expanded-tests.log`.

### Reproduce the real-network release integration tests

Requires Java 21+, Firebase CLI, Flutter, Node with native WebSocket, Python 3 and
Chrome. These commands do not deploy. Do not run another test against the same
local demo project concurrently because the runner clears its synthetic records.

```sh
firebase emulators:start --only firestore --project demo-paltranco-regression --config tool/firebase.emulator.json
# In another terminal:
flutter build web --release --target tool/emulator_release_validation.dart --output /tmp/ptc-emulator-release-validation
node tool/run_emulator_release_validation.mjs
```

The runner exits nonzero on failed assertions, uncaught JS errors or renderer
crashes. It creates an isolated temporary browser profile and report, and closes
its own browser/server. It never opens the user's existing browser profile.

### Final expanded-pass checks

- Full suite: **496 passed** (`/tmp/ptc-final-expanded-tests.log`).
- Chrome regressions: **65 passed** (`/tmp/ptc-expanded-final-chrome.log`).
- Static analysis: **no issues** (`/tmp/ptc-final-expanded-analyze.log`).
- Final normal JavaScript app release: **built successfully**, output
  `/tmp/ptc-verified-final-release`; existing Wasm dry-run warning remains.
- Final `main.dart.js` SHA-256: `315dc47b1b125ef9209a1d7675b231a4a725510711c829c6e6b79f91c23f789b`.
- Tracked `build/web` was not replaced and no deployment was performed.

The earlier candidate hash and login-screen smoke belong to the initial pass,
not this rebuilt artifact. The expanded tests strengthen queue/account validation
but do not prove all production UI/network/device scenarios. The artificial SDK
failure above remains explicitly unclaimed as fixed.
