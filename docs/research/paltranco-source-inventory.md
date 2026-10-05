# PALTRANCO source inventory

Research baseline: 69ceff2, Release 1.0.0+45. Current report is a documentation-only addition. Source inventory excludes generated build output and IDE configuration.

## Commit chronology

```text
490b7bd | 2026-06-10T09:47:10+08:00 | first commit
3bcf7ff | 2026-06-10T15:24:34+08:00 | refactor: firestore crud
333f9c8 | 2026-06-10T16:18:38+08:00 | refactor: remove build web from gitignore
d6fd6dc | 2026-06-10T17:12:06+08:00 | hotfix: admin register; phone field
042383e | 2026-06-10T23:38:25+08:00 | refactor: metadata
03dc2de | 2026-06-10T23:49:24+08:00 | refactor: favicon
64a5654 | 2026-06-10T23:54:21+08:00 | refactor: favicon light/dark
46b63fb | 2026-06-11T00:11:38+08:00 | refactor: favicon all
9475fe9 | 2026-06-11T00:39:00+08:00 | refactor: favicon
f15ee2d | 2026-06-11T05:02:08+08:00 | refactor: photo uploads
7f75cc1 | 2026-06-11T15:21:30+08:00 | wip: field buttons
edc3880 | 2026-06-11T17:53:10+08:00 | hotfix: fields response
5e526bc | 2026-06-12T11:42:36+08:00 | wip: form style
52dd0ce | 2026-06-12T15:46:53+08:00 | wip: export
014f2ed | 2026-06-12T17:59:27+08:00 | feat: export
eda353a | 2026-06-12T23:04:12+08:00 | style: normalize spaces
b7f5746 | 2026-06-13T01:06:30+08:00 | feat: pinch zoom; cached network image; change password
d511312 | 2026-06-28T10:48:07+08:00 | wip: fixes
3e78491 | 2026-06-29T11:29:56+08:00 | before export unbilled
0707bf8 | 2026-06-29T12:35:14+08:00 | before offline
860d5a0 | 2026-06-29T12:37:55+08:00 | wip
2e6b689 | 2026-06-29T17:52:49+08:00 | offline
a3d6f7b | 2026-06-29T18:06:23+08:00 | offline 2
90826e1 | 2026-06-29T18:14:20+08:00 | offline 3
c0345be | 2026-06-29T18:40:33+08:00 | offline 4
a81c2c8 | 2026-06-29T18:47:30+08:00 | offline 5
626a4dc | 2026-06-29T23:10:02+08:00 | offline 6
b6b7273 | 2026-08-11T22:53:29+08:00 | wip: offline function
6291162 | 2026-08-11T22:59:38+08:00 | wip: persist logout
ef3c28b | 2026-08-12T04:35:59+08:00 | feat: offline functionality
972bf34 | 2026-08-28T21:45:46+08:00 | wip: full system test
96d44b2 | 2026-08-28T22:37:16+08:00 | Prepare web release 1.0.0 (3)
62f4003 | 2026-08-28T22:38:24+08:00 | Rebuild web release 1.0.0 (3)
b9d3783 | 2026-08-28T22:47:23+08:00 | Fix prod web cache refresh and login rollout
61a4178 | 2026-08-28T22:52:01+08:00 | Harden prod login fallback
0659ded | 2026-08-28T22:57:28+08:00 | Force global web cache refresh for login rollout
bef5a48 | 2026-08-28T23:05:36+08:00 | Show real login error messages
84775fc | 2026-08-28T23:10:06+08:00 | Remove generic invalid error message
09e814c | 2026-08-28T23:20:50+08:00 | Align social browser gate and login rollout fixes
ecc4edf | 2026-08-28T23:30:13+08:00 | Show exact auth errors in snackbar
7763cb8 | 2026-08-28T23:37:00+08:00 | Show raw auth errors in snackbar
9e1a3c3 | 2026-08-28T23:52:00+08:00 | Show raw error messages across the app
8c94b8d | 2026-08-29T00:02:28+08:00 | Show raw error messages in login flow
35985df | 2026-08-29T00:10:38+08:00 | Fix auth errors and Firestore web config
6c0e576 | 2026-08-29T00:22:01+08:00 | Speed up login and show raw errors
8c9756d | 2026-08-29T00:31:12+08:00 | Speed up login and remove raw auth blockers
ddb6bf6 | 2026-08-29T00:41:33+08:00 | Speed up cold-start login and show raw errors
be7dddb | 2026-08-29T01:01:05+08:00 | Fix mobile bottom safe area color
20eb7b7 | 2026-08-29T01:15:29+08:00 | Release 1.0.0 (4) with cold-start data fixes
75bd727 | 2026-08-29T17:09:18+08:00 | Release 1.0.0 (5)
9fecae4 | 2026-08-29T18:31:06+08:00 | Release 1.0.0 (5)
50052c4 | 2026-08-31T03:49:08+08:00 | fix: admin menu items loading
88970e5 | 2026-09-01T16:18:16+08:00 | Fix support caching and form field toggles
bced2c3 | 2026-09-01T17:14:04+08:00 | Standardize online ID reservations
fa3d4ed | 2026-09-01T17:35:36+08:00 | Add camera switch and ID reservations
3e0dc24 | 2026-09-01T17:44:29+08:00 | Add visible camera switch control
01315ce | 2026-09-01T17:53:11+08:00 | Fix: Registration Camera Rotate
40e5295 | 2026-09-01T17:58:06+08:00 | Fix: Registration Camera Rotate
75f4c9e | 2026-09-01T18:07:03+08:00 | Fix: Registration Camera Rotate
02e10be | 2026-09-01T18:15:02+08:00 | Debug: Production dropdown options
78adba6 | 2026-09-01T18:23:50+08:00 | Fix: Lazy Firestore bootstrap
45bf267 | 2026-09-01T18:43:09+08:00 | Fix: Production search dropdown dialog
ac46ca8 | 2026-09-01T22:08:28+08:00 | Release 1.0.0+3: Fix booking confirmation flow
23bc46e | 2026-09-01T22:27:43+08:00 | Fix mobile booking modal scrolling and app UI
52457e1 | 2026-09-01T22:38:53+08:00 | Fix mobile safe area and booking modal scrolling
abf65c4 | 2026-09-01T22:47:36+08:00 | Fix PWA install flow and mobile safe areas
052ecf2 | 2026-09-01T22:56:31+08:00 | Fix PWA install service worker updates
e3b5b5b | 2026-09-01T23:01:31+08:00 | Match mobile safe area behavior with supermarket
8b825cb | 2026-09-01T23:10:17+08:00 | Improve Chrome PWA install fallback
ff585a1 | 2026-09-01T23:23:49+08:00 | Add standalone PWA install page
e8a4886 | 2026-09-01T23:26:39+08:00 | Add standalone PWA install page
32870a5 | 2026-09-01T23:31:02+08:00 | Configure standalone PWA install deployment
c05fe72 | 2026-09-01T23:38:38+08:00 | Align PWA download page with app UI
e039830 | 2026-09-01T23:48:09+08:00 | Center PWA install page without scrolling
1b8c0d9 | 2026-09-01T23:50:29+08:00 | Refine PWA install page and social gate branding
f6795cb | 2026-09-01T23:55:41+08:00 | Match PWA install page to login UI
d8e151c | 2026-09-02T00:12:56+08:00 | Verify installed PWA state before opening app
6393f91 | 2026-09-02T00:16:27+08:00 | Use brand purple for PWA splash
5906658 | 2026-09-02T00:27:48+08:00 | Launch installed PWA from download page
210ef48 | 2026-09-02T00:56:02+08:00 | Add admin sidebar booking and support badges
3f6e4c8 | 2026-09-02T02:25:22+08:00 | Improve analytics and role filters
7175155 | 2026-09-02T23:12:10+08:00 | Add chassis management foundation
f925a24 | 2026-09-02T23:12:49+08:00 | Add chassis management foundation
0874f8d | 2026-09-03T02:44:08+08:00 | Add chassis workflow and validation improvements
f05e822 | 2026-09-03T03:02:05+08:00 | Finalize chassis workflow migration safeguards
ca30362 | 2026-09-03T05:41:45+08:00 | Optimize app performance and chassis alerts
1162ee0 | 2026-09-03T07:36:38+08:00 | Improve offline chat persistence and sync
434bd02 | 2026-09-03T07:45:50+08:00 | Improve offline chat persistence and sync
f2f9fa8 | 2026-09-03T15:34:35+08:00 | Fix dropdown selection display and offline chat sync
fd2cba6 | 2026-09-04T00:51:13+08:00 | Fix iPhone Safari web startup
3554090 | 2026-09-04T01:01:41+08:00 | Fix Safari startup and social browser gate
4960047 | 2026-09-04T03:54:05+08:00 | Fix offline cold-start data persistence
11da619 | 2026-09-04T04:20:01+08:00 | Fix durable offline cache and splash assets
a4720f5 | 2026-09-04T04:27:06+08:00 | Prevent transient empty booking states
48ba1f2 | 2026-09-04T04:30:13+08:00 | Fit analytics content to viewport height
90a207e | 2026-09-04T05:58:00+08:00 | Add resilient offline cache fallback
ebca20c | 2026-09-04T06:10:35+08:00 | Fix durable offline data and dropdown caches
439707d | 2026-09-04T06:22:06+08:00 | Fix offline Flutter startup cache
047c860 | 2026-09-04T06:37:28+08:00 | Fix durable offline collection caches
a5f5626 | 2026-09-04T06:45:28+08:00 | Fix offline startup splash
4f464aa | 2026-09-04T07:01:21+08:00 | Fix offline startup splash
103bc38 | 2026-09-04T07:03:30+08:00 | Fix offline startup splash
caa609d | 2026-09-04T07:09:56+08:00 | Cache Flutter startup assets for offline launch
9ca1d7c | 2026-09-05T02:41:26+08:00 | Fix offline startup assets and storage CORS
53edf50 | 2026-09-05T05:10:40+08:00 | Keep branded splash visible through app startup
603bf8c | 2026-09-05T05:53:00+08:00 | Keep branded splash through initial dashboard load
86080cb | 2026-09-05T08:47:38+08:00 | Verify offline workflow reliability
06d5632 | 2026-09-05T18:34:51+08:00 | Show booking schedules for drivers and helpers
07f80a9 | 2026-09-05T18:40:41+08:00 | Combine driver helper booking schedules
7d58c89 | 2026-09-13T05:50:52+08:00 | Show schedules in driver helper booking details
f50df08 | 2026-09-13T15:10:37+08:00 | Fix offline delivery sync ordering and image memory pressure
31c6438 | 2026-09-13T16:54:56+08:00 | Fix offline delivery sync ordering and image memory pressure
2cf7c41 | 2026-09-13T19:21:25+08:00 | Reduce web image renderer pressure
508369b | 2026-09-13T19:51:29+08:00 | Optimize mobile analytics amount typography
6936f86 | 2026-09-14T08:51:29+08:00 | Polish booking forms, alerts, and analytics
1f61446 | 2026-09-19T05:03:28+08:00 | Improve performance and offline sync reliability
2351fe1 | 2026-09-19T05:56:08+08:00 | Improve performance and offline sync reliability
2f463e5 | 2026-09-19T15:43:39+08:00 | Update support UI and offline queue
0bac99e | 2026-09-19T17:09:15+08:00 | Release 1.0.1+9
2d18c93 | 2026-09-23T18:26:59+08:00 | Release 1.0.1+10
e990e01 | 2026-09-23T19:40:26+08:00 | Update error logs and sync safeguards
a7c6ad4 | 2026-09-23T21:06:16+08:00 | Release 1.0.1+11
304dffd | 2026-09-23T22:27:28+08:00 | Release 1.0.1+12
f0110c8 | 2026-09-23T23:28:04+08:00 | Release 1.0.1+13
8129b81 | 2026-09-24T07:23:26+08:00 | Release 1.0.0+14
5a3f738 | 2026-09-24T15:20:41+08:00 | Release 1.0.0+15
c166711 | 2026-09-25T01:41:24+08:00 | test: fix KPI and rates test flakes; add manage_notifications index
8de39f6 | 2026-09-25T01:47:04+08:00 | feat: crew fuel/booking-count/shares/salary in KPI view; support read-marker; image resize
f08afbf | 2026-09-25T01:51:55+08:00 | Release 1.0.0+16
98da207 | 2026-09-25T03:45:42+08:00 | fix: chassis stays wide/horizontal on desktop like other admin pages
d28fe85 | 2026-09-25T04:29:15+08:00 | chassis: remove Created/Updated columns from titles row and list items
f221fd3 | 2026-09-25T04:40:40+08:00 | chassis: auto-unassign driver when no booking is selected on save
aec0391 | 2026-09-25T19:22:02+08:00 | Release 1.0.0+17
fb53661 | 2026-09-25T20:13:34+08:00 | Release 1.0.0+18
dc43342 | 2026-09-26T02:44:46+08:00 | Release 1.0.0+19
ccf8440 | 2026-09-26T10:09:19+08:00 | Release 1.0.0+20
a02ac4e | 2026-09-26T13:14:57+08:00 | Release 1.0.0+21
56292bd | 2026-09-26T21:23:13+08:00 | Release 1.0.0+22
057d354 | 2026-09-26T22:05:13+08:00 | Debug: trace chat action target
403f966 | 2026-09-26T22:22:29+08:00 | Debug: trace chat action with unthrottled prints
d2d7a21 | 2026-09-27T01:24:20+08:00 | Release 1.0.0+25
9d2f989 | 2026-09-27T03:10:17+08:00 | Release 1.0.0+26
a46319e | 2026-09-27T03:58:40+08:00 | Release 1.0.0+27
a451c1f | 2026-09-27T13:10:40+08:00 | Release 1.0.0+28
0a3e1f5 | 2026-09-27T16:59:29+08:00 | Release 1.0.0+29
c98379b | 2026-09-29T17:50:21+08:00 | Release 1.0.0+30
11ab00f | 2026-09-29T18:03:30+08:00 | Release 1.0.0+31
9f2708a | 2026-09-29T19:08:16+08:00 | Release 1.0.0+32
fe808f3 | 2026-09-29T19:31:02+08:00 | Release 1.0.0+33
c3c2062 | 2026-09-29T19:42:57+08:00 | Release 1.0.0+34
d434d87 | 2026-09-29T20:37:08+08:00 | Release 1.0.0+36
6d1174c | 2026-09-30T12:58:42+08:00 | Release 1.0.0+37
9ac642c | 2026-09-30T15:38:21+08:00 | Release 1.0.0+38
00fed73 | 2026-10-01T01:48:25+08:00 | Release 1.0.0+39
36fd67a | 2026-10-02T12:03:02+08:00 | Release 1.0.0+40
76b733a | 2026-10-02T12:37:33+08:00 | Release 1.0.0+41
787f4fc | 2026-10-02T18:33:31+08:00 | Release 1.0.0+42
99dc7c3 | 2026-10-02T20:15:20+08:00 | Release 1.0.0+43
340dd3c | 2026-10-03T05:34:37+08:00 | Release 1.0.0+44
69ceff2 | 2026-10-03T14:05:00+08:00 | Release 1.0.0+45
```

## Repository source / documentation / tests / assets

- `.gitignore`
- `.metadata`
- `README.md`
- `analysis_options.yaml`
- `assets/KPI-2026-new.xlsx`
- `assets/export_templates/bs-hustling.docx`
- `assets/export_templates/bs-regular.docx`
- `assets/export_templates/bt-hustling.docx`
- `assets/export_templates/bt-regular.docx`
- `assets/export_templates/kpi-2026-layout.xlsx`
- `assets/sdv_footer_lite.png`
- `assets/sounds/alert.mp3`
- `assets/sounds/sound.mp3`
- `codex.md`
- `devtools_options.yaml`
- `docs/booking-data-performance.md`
- `docs/booking-photo-safety.md`
- `docs/chassis-reservations.md`
- `docs/disposed-view-crash.md`
- `docs/field-type-history.md`
- `docs/lazy-list-audit.md`
- `docs/offline-write-audit.md`
- `docs/performance-followup-2026-09-23.md`
- `docs/pm-kpi.md`
- `docs/reviews/current-vs-prod-refresh-2026-09-23.md`
- `docs/reviews/current-vs-production-final-assessment-2026-09-23.md`
- `docs/reviews/post-optimization-comparison-2026-09-23.md`
- `docs/reviews/predeploy-verification-2026-09-23.md`
- `docs/reviews/probes/post-optimization-current-probe.dart.txt`
- `docs/reviews/probes/post-optimization-prod-cache-probe.dart.txt`
- `docs/reviews/production-offline-comparison-2026-09-23.md`
- `docs/reviews/three-issue-fixes-2026-09-23.md`
- `docs/sync-error-logs.md`
- `docs/sync-freeze-follow-up.md`
- `firebase.json`
- `firestore.indexes.json`
- `firestore.rules`
- `functions/chassis-check-notice.test.js`
- `functions/chassis-notices.js`
- `functions/chassis-notices.test.js`
- `functions/chassis-workflow.js`
- `functions/chassis-workflow.test.js`
- `functions/index.js`
- `functions/package-lock.json`
- `functions/package.json`
- `functions/support-notifications.js`
- `functions/support-notifications.test.js`
- `lib/constants/app_colors.dart`
- `lib/constants/palawan_locations.dart`
- `lib/constants/puerto_princesa_barangays.dart`
- `lib/firebase_options.dart`
- `lib/main.dart`
- `lib/models/booking.dart`
- `lib/models/chassis.dart`
- `lib/models/chassis_action_history.dart`
- `lib/models/dispatcher_access_config.dart`
- `lib/models/offline_queue_item.dart`
- `lib/models/status.dart`
- `lib/models/status_field.dart`
- `lib/models/status_form.dart`
- `lib/models/support_message.dart`
- `lib/models/support_thread.dart`
- `lib/models/user.dart`
- `lib/models/vehicle_catalog_item.dart`
- `lib/models/vehicle_make.dart`
- `lib/repositories/interfaces/auth_repository.dart`
- `lib/repositories/interfaces/booking_repository.dart`
- `lib/repositories/interfaces/status_form_repository.dart`
- `lib/repositories/interfaces/vehicle_catalog_repository.dart`
- `lib/repositories/local/auth_storage_backend.dart`
- `lib/repositories/local/auth_storage_backend_stub.dart`
- `lib/repositories/local/auth_storage_backend_web.dart`
- `lib/repositories/local/booking_storage_backend.dart`
- `lib/repositories/local/booking_storage_backend_stub.dart`
- `lib/repositories/local/booking_storage_backend_web.dart`
- `lib/requests/auth.request.dart`
- `lib/requests/booking.request.dart`
- `lib/requests/cache_mirror_codec.dart`
- `lib/requests/cache_mirror_codec_stub.dart`
- `lib/requests/cache_mirror_codec_web.dart`
- `lib/requests/chassis.request.dart`
- `lib/requests/firestore_cache_persistence.dart`
- `lib/requests/firestore_cache_persistence_stub.dart`
- `lib/requests/firestore_cache_persistence_web.dart`
- `lib/requests/firestore_cache_store.dart`
- `lib/requests/role_access.request.dart`
- `lib/requests/status.request.dart`
- `lib/requests/support.request.dart`
- `lib/requests/vehicle.request.dart`
- `lib/services/app_resume_service.dart`
- `lib/services/app_session_reset.dart`
- `lib/services/app_version_service.dart`
- `lib/services/app_warmup_service.dart`
- `lib/services/app_widgets_binding.dart`
- `lib/services/auth_camera_service.dart`
- `lib/services/auth_camera_service_stub.dart`
- `lib/services/auth_camera_service_web.dart`
- `lib/services/auth_image_picker_service.dart`
- `lib/services/auth_image_picker_service_stub.dart`
- `lib/services/auth_image_picker_service_web.dart`
- `lib/services/booking_chassis_lifecycle.dart`
- `lib/services/booking_chat_alert_service.dart`
- `lib/services/booking_conflict_review_service.dart`
- `lib/services/booking_edit_archive.dart`
- `lib/services/booking_id_resolver.dart`
- `lib/services/booking_offline_upload_queue_service.dart`
- `lib/services/booking_photo_cleanup.dart`
- `lib/services/booking_photo_marker_match.dart`
- `lib/services/booking_pm_assignment.dart`
- `lib/services/booking_resolution_gate.dart`
- `lib/services/booking_status_continuation.dart`
- `lib/services/chassis_check_alert_service.dart`
- `lib/services/chassis_push_notification_service.dart`
- `lib/services/chassis_waiting_badge.dart`
- `lib/services/dashboard_docx_export_service.dart`
- `lib/services/dashboard_export_naming.dart`
- `lib/services/diagnostic_write_lock.dart`
- `lib/services/diagnostic_write_lock_stub.dart`
- `lib/services/diagnostic_write_lock_web.dart`
- `lib/services/export_file_service.dart`
- `lib/services/export_file_service_io.dart`
- `lib/services/export_file_service_shared.dart`
- `lib/services/export_file_service_stub.dart`
- `lib/services/export_file_service_web.dart`
- `lib/services/field_type_history_service.dart`
- `lib/services/firebase_auth_bridge_service.dart`
- `lib/services/firestore_offline_service.dart`
- `lib/services/firestore_public_document_fetcher.dart`
- `lib/services/firestore_public_document_fetcher_stub.dart`
- `lib/services/firestore_transaction_errors.dart`
- `lib/services/foreground_refresh_gate.dart`
- `lib/services/image_upload_processor.dart`
- `lib/services/investor_commission.dart`
- `lib/services/investor_commission_rate_store.dart`
- `lib/services/investor_expense_bridge.dart`
- `lib/services/investor_reporting_scope.dart`
- `lib/services/investor_scope.dart`
- `lib/services/kpi/crew_kpi_store.dart`
- `lib/services/kpi/fleet_kpi.dart`
- `lib/services/kpi/investor_kpi_store.dart`
- `lib/services/kpi/investor_statement_workbook.dart`
- `lib/services/kpi/kpi_activity_index.dart`
- `lib/services/kpi/kpi_all_time_period.dart`
- `lib/services/kpi/kpi_calculation_cache.dart`
- `lib/services/kpi/kpi_cost_override.dart`
- `lib/services/kpi/kpi_diagnostic_policy.dart`
- `lib/services/kpi/kpi_fleet_rating.dart`
- `lib/services/kpi/kpi_fleet_workbook.dart`
- `lib/services/kpi/kpi_incident_summary.dart`
- `lib/services/kpi/kpi_payroll_summary.dart`
- `lib/services/kpi/kpi_period_label.dart`
- `lib/services/kpi/kpi_rating_rules.dart`
- `lib/services/kpi/kpi_report_export.dart`
- `lib/services/kpi/kpi_salary_diagnostics.dart`
- `lib/services/kpi/kpi_template_workbook.dart`
- `lib/services/kpi/kpi_utilization.dart`
- `lib/services/kpi/kpi_workbook_import.dart`
- `lib/services/kpi/location_option_registry.dart`
- `lib/services/kpi/operations_catalog.dart`
- `lib/services/kpi/operations_catalog_store.dart`
- `lib/services/kpi/pm_kpi.dart`
- `lib/services/kpi/pm_kpi_store.dart`
- `lib/services/legacy_booking_repair_service.dart`
- `lib/services/local_form_draft_service.dart`
- `lib/services/network_status_events.dart`
- `lib/services/network_status_events_stub.dart`
- `lib/services/network_status_events_web.dart`
- `lib/services/offline_cleanup_queue_service.dart`
- `lib/services/offline_error_diagnostics.dart`
- `lib/services/offline_media_sync_service.dart`
- `lib/services/offline_mutation_queue_service.dart`
- `lib/services/offline_queue_coordinator_service.dart`
- `lib/services/offline_reference_mapper.dart`
- `lib/services/offline_sync_status_service.dart`
- `lib/services/paged_booking_source.dart`
- `lib/services/pending_booking_submission.dart`
- `lib/services/persistent_image_cache_service.dart`
- `lib/services/persistent_image_cache_store.dart`
- `lib/services/persistent_image_cache_store_stub.dart`
- `lib/services/persistent_image_cache_store_web.dart`
- `lib/services/persistent_image_fetcher.dart`
- `lib/services/persistent_image_fetcher_stub.dart`
- `lib/services/persistent_image_fetcher_web.dart`
- `lib/services/photo_storage_service.dart`
- `lib/services/role_access_service.dart`
- `lib/services/startup_splash.dart`
- `lib/services/startup_splash_stub.dart`
- `lib/services/startup_splash_web.dart`
- `lib/services/status_field_option_resolver.dart`
- `lib/services/status_form_engine.dart`
- `lib/services/support_alert_deduplicator.dart`
- `lib/services/support_contact_scope.dart`
- `lib/services/support_read_marker_writer.dart`
- `lib/services/support_storage_service.dart`
- `lib/services/sync_diagnostic_outbox.dart`
- `lib/services/sync_error_environment.dart`
- `lib/services/sync_error_environment_stub.dart`
- `lib/services/sync_error_environment_web.dart`
- `lib/services/sync_error_log_service.dart`
- `lib/services/web_app_install_service.dart`
- `lib/services/web_app_install_service_stub.dart`
- `lib/services/web_app_install_service_web.dart`
- `lib/services/web_file_download.dart`
- `lib/utils/booking_party_search.dart`
- `lib/utils/cached_snapshot_documents.dart`
- `lib/utils/copy_document_fields.dart`
- `lib/utils/functions.dart`
- `lib/utils/latest_value_worker.dart`
- `lib/utils/location_display.dart`
- `lib/utils/performance_trace.dart`
- `lib/utils/shared_replay_stream.dart`
- `lib/utils/support_message_identity.dart`
- `lib/utils/text_width_cache.dart`
- `lib/view_models/admin/admin_bookings.vm.dart`
- `lib/view_models/admin/admin_dashboard.vm.dart`
- `lib/view_models/admin/admin_flow.vm.dart`
- `lib/view_models/admin/admin_home.vm.dart`
- `lib/view_models/admin/admin_users.vm.dart`
- `lib/view_models/admin/admin_vehicle_makes.vm.dart`
- `lib/view_models/admin/admin_vehicle_sizes.vm.dart`
- `lib/view_models/admin/admin_vehicle_types.vm.dart`
- `lib/view_models/admin/booking_conflict_review.vm.dart`
- `lib/view_models/admin/investor_statement.vm.dart`
- `lib/view_models/auth/auth.vm.dart`
- `lib/view_models/client/client_booking_history.vm.dart`
- `lib/view_models/client/client_booking_home.vm.dart`
- `lib/view_models/client/client_home.vm.dart`
- `lib/view_models/driver/driver_home.vm.dart`
- `lib/view_models/helper/helper_home.vm.dart`
- `lib/view_models/shared/app_shell.vm.dart`
- `lib/view_models/shared/booking_workflow.vm.dart`
- `lib/view_models/shared/role_assigned_home.vm.dart`
- `lib/view_models/shared/role_platform_home.vm.dart`
- `lib/views/admin/admin_access.dart`
- `lib/views/admin/admin_analytics.dart`
- `lib/views/admin/admin_bookings.dart`
- `lib/views/admin/admin_chassis.dart`
- `lib/views/admin/admin_dashboard.dart`
- `lib/views/admin/admin_error_logs.dart`
- `lib/views/admin/admin_fields.dart`
- `lib/views/admin/admin_forms.dart`
- `lib/views/admin/admin_home.dart`
- `lib/views/admin/admin_kpi_tracking.dart`
- `lib/views/admin/admin_statuses.dart`
- `lib/views/admin/admin_users.dart`
- `lib/views/admin/admin_vehicle_makes.dart`
- `lib/views/admin/admin_vehicle_sizes.dart`
- `lib/views/admin/admin_vehicle_types.dart`
- `lib/views/admin/booking_conflict_review_dialog.dart`
- `lib/views/admin/investor_statement_dialog.dart`
- `lib/views/admin/kpi_import_dialog.dart`
- `lib/views/admin/kpi_utilization_view.dart`
- `lib/views/admin/operations_catalog_dialog.dart`
- `lib/views/admin/pm_fuel_ledger_dialog.dart`
- `lib/views/admin/pm_kpi_dialog.dart`
- `lib/views/admin/shared_kpi_rules_dialog.dart`
- `lib/views/auth/auth_view.dart`
- `lib/views/client/client_booking_history_view.dart`
- `lib/views/client/client_booking_home_view.dart`
- `lib/views/client/client_home.dart`
- `lib/views/driver/driver_home.dart`
- `lib/views/helper/helper_home.dart`
- `lib/views/shared/app_shell.dart`
- `lib/views/shared/booking_workflow_view.dart`
- `lib/views/shared/crew_kpi_profile_summary.dart`
- `lib/views/shared/crew_kpi_tracking.dart`
- `lib/views/shared/profile_view.dart`
- `lib/views/shared/role_platform_home.dart`
- `lib/views/shared/support_center_view.dart`
- `lib/widgets/admin_form_controls.dart`
- `lib/widgets/admin_modal_shell.dart`
- `lib/widgets/collapsible_sidebar.dart`
- `lib/widgets/shared/admin_action_confirmation.dart`
- `lib/widgets/shared/admin_icon_action_button.dart`
- `lib/widgets/shared/admin_list_primitives.dart`
- `lib/widgets/shared/admin_modal_form_primitives.dart`
- `lib/widgets/shared/admin_modal_record_list.dart`
- `lib/widgets/shared/admin_shell_layout_scope.dart`
- `lib/widgets/shared/app_cached_network_image.dart`
- `lib/widgets/shared/app_cached_network_image_online_listener.dart`
- `lib/widgets/shared/app_cached_network_image_online_listener_stub.dart`
- `lib/widgets/shared/app_cached_network_image_online_listener_web.dart`
- `lib/widgets/shared/app_image_source_picker.dart`
- `lib/widgets/shared/app_image_viewer.dart`
- `lib/widgets/shared/app_modal_guard.dart`
- `lib/widgets/shared/app_mouse_pressable.dart`
- `lib/widgets/shared/app_page_loading.dart`
- `lib/widgets/shared/app_page_loading_overlay.dart`
- `lib/widgets/shared/app_profile_avatar.dart`
- `lib/widgets/shared/app_refresh_strip.dart`
- `lib/widgets/shared/app_resume_recovery.dart`
- `lib/widgets/shared/app_selectable_dialog.dart`
- `lib/widgets/shared/app_selectable_popup_menu_item.dart`
- `lib/widgets/shared/app_selectable_text.dart`
- `lib/widgets/shared/app_snackbar.dart`
- `lib/widgets/shared/app_sync_status_banner.dart`
- `lib/widgets/shared/booking_form_primitives.dart`
- `lib/widgets/shared/booking_record_card.dart`
- `lib/widgets/shared/booking_section_navigation_scope.dart`
- `lib/widgets/shared/catalog_conflict_review_dialog.dart`
- `lib/widgets/shared/chassis_action_history_dialog.dart`
- `lib/widgets/shared/chassis_status_presentation.dart`
- `lib/widgets/shared/in_app_browser_guard.dart`
- `lib/widgets/shared/inline_detail_host.dart`
- `lib/widgets/shared/lazy_data_scroll_view.dart`
- `lib/widgets/shared/native_date_input.dart`
- `lib/widgets/shared/native_date_input_stub.dart`
- `lib/widgets/shared/native_date_input_web.dart`
- `lib/widgets/shared/offline_queue_status_strip.dart`
- `lib/widgets/shared/paged_data_sliver.dart`
- `lib/widgets/shared/platform_shell.dart`
- `lib/widgets/shared/record_text_link.dart`
- `lib/widgets/shared/retained_section_stack.dart`
- `lib/widgets/shared/retained_stream_builder.dart`
- `lib/widgets/shared/startup_splash_handoff.dart`
- `lib/widgets/shared/support_section_navigation_scope.dart`
- `lib/widgets/shared/type_history_input.dart`
- `lib/widgets/shared/user_bookings_section.dart`
- `lib/widgets/shared/user_session_actions_scope.dart`
- `lib/widgets/sidebar_menu_item.dart`
- `lib/widgets/status_form/status_field_editor_card.dart`
- `lib/widgets/status_form/status_form_preview.dart`
- `lib/widgets/status_form/status_form_runtime_fields.dart`
- `pubspec.yaml`
- `scripts/deploy_web.zsh`
- `scripts/prepare_kpi_template.py`
- `scripts/prepare_web_release.sh`
- `storage.cors.json`
- `storage.rules`
- `test/admin_bookings_lazy_list_test.dart`
- `test/admin_error_logs_chat_test.dart`
- `test/admin_error_logs_test.dart`
- `test/admin_kpi_tracking_test.dart`
- `test/admin_modal_record_list_test.dart`
- `test/admin_modal_shell_overflow_test.dart`
- `test/admin_role_grant_guard_test.dart`
- `test/app_resume_recovery_test.dart`
- `test/app_selectable_text_test.dart`
- `test/app_widgets_binding_test.dart`
- `test/auth_request_session_test.dart`
- `test/booking_86_uploaded_delivery_retry_test.dart`
- `test/booking_boxed_error_recovery_test.dart`
- `test/booking_chassis_replay_test.dart`
- `test/booking_chassis_request_flow_test.dart`
- `test/booking_conflict_review_test.dart`
- `test/booking_edit_archive_test.dart`
- `test/booking_filter_cache_test.dart`
- `test/booking_id_resolver_test.dart`
- `test/booking_metadata_retry_test.dart`
- `test/booking_party_search_test.dart`
- `test/booking_photo_commit_safety_test.dart`
- `test/booking_photo_connection_retry_test.dart`
- `test/booking_photo_fifo_recovery_test.dart`
- `test/booking_photo_legacy_diagnostics_test.dart`
- `test/booking_photo_marker_match_test.dart`
- `test/booking_photo_marker_recovery_test.dart`
- `test/booking_photo_read_fallback_test.dart`
- `test/booking_photo_removal_test.dart`
- `test/booking_pm_assignment_test.dart`
- `test/booking_resolution_gate_test.dart`
- `test/booking_status_continuation_test.dart`
- `test/booking_submission_order_test.dart`
- `test/booking_uploaded_photo_retry_test.dart`
- `test/catalog_conflict_review_test.dart`
- `test/chassis_action_history_test.dart`
- `test/chassis_active_transfer_test.dart`
- `test/chassis_conflict_recovery_test.dart`
- `test/chassis_offline_references_test.dart`
- `test/chassis_reservations_test.dart`
- `test/chassis_waiting_badge_test.dart`
- `test/client_booking_submission_test.dart`
- `test/crew_history_order_test.dart`
- `test/crew_kpi_booking_progress_test.dart`
- `test/crew_kpi_cross_read_test.dart`
- `test/crew_kpi_instant_render_test.dart`
- `test/crew_kpi_profile_summary_test.dart`
- `test/crew_kpi_store_test.dart`
- `test/crew_kpi_tracking_test.dart`
- `test/dashboard_docx_export_service_test.dart`
- `test/dashboard_lazy_lists_test.dart`
- `test/dispatcher_fifteen_photo_recovery_test.dart`
- `test/dispatcher_oct2_sync_conflicts_test.dart`
- `test/driver_registration_vehicle_test.dart`
- `test/emulator/firestore_sdk_network_test.dart`
- `test/field_type_history_test.dart`
- `test/filter_selection_test.dart`
- `test/firestore_cache_stale_read_test.dart`
- `test/fixtures/booking_83_chassis_conflict.json`
- `test/fixtures/booking_86_uploaded_delivery_retry.json`
- `test/fixtures/dispatcher_oct2_fifteen_photos.json`
- `test/fixtures/dispatcher_oct2_sync_conflicts.json`
- `test/fixtures/helper19_oct2_history.json`
- `test/fixtures/helper_delivery_history_conflicts.json`
- `test/fixtures/production_sync_recovery.json`
- `test/fixtures/remaining_booking_sync_conflicts.json`
- `test/fixtures/superseded_booking_assignment.json`
- `test/fleet_kpi_test.dart`
- `test/flow_lazy_lists_test.dart`
- `test/foreground_refresh_gate_test.dart`
- `test/helper19_history_recovery_test.dart`
- `test/helper_delivery_history_conflicts_test.dart`
- `test/image_aspect_ratio_test.dart`
- `test/inline_detail_host_test.dart`
- `test/investor_commission_rate_test.dart`
- `test/investor_commission_test.dart`
- `test/investor_crew_daily_test.dart`
- `test/investor_expense_bridge_test.dart`
- `test/investor_office_salary_test.dart`
- `test/investor_reporting_scope_test.dart`
- `test/investor_role_gating_test.dart`
- `test/investor_route_guard_test.dart`
- `test/investor_scope_test.dart`
- `test/investor_silo_test.dart`
- `test/investor_statement_dialog_test.dart`
- `test/investor_statement_export_test.dart`
- `test/investor_statement_vm_test.dart`
- `test/investor_truck_assignment_test.dart`
- `test/kpi_calculation_cache_test.dart`
- `test/kpi_cost_override_test.dart`
- `test/kpi_dynamic_role_access_test.dart`
- `test/kpi_fleet_rating_test.dart`
- `test/kpi_fleet_workbook_test.dart`
- `test/kpi_fuel_summary_test.dart`
- `test/kpi_incident_summary_test.dart`
- `test/kpi_issue_diagnostics_test.dart`
- `test/kpi_legacy_matching_test.dart`
- `test/kpi_local_persistence_test.dart`
- `test/kpi_modal_states_test.dart`
- `test/kpi_parallel_load_test.dart`
- `test/kpi_rating_rules_test.dart`
- `test/kpi_report_tools_test.dart`
- `test/kpi_role_access_test.dart`
- `test/kpi_template_workbook_test.dart`
- `test/kpi_utilization_test.dart`
- `test/latest_value_worker_test.dart`
- `test/lazy_data_scroll_view_test.dart`
- `test/legacy_booking_repair_service_test.dart`
- `test/location_classification_test.dart`
- `test/location_display_test.dart`
- `test/modal_outside_dismiss_test.dart`
- `test/modal_text_selection_test.dart`
- `test/models/status_field_text_case_test.dart`
- `test/native_date_input_web_test.dart`
- `test/offline_cleanup_queue_test.dart`
- `test/offline_linked_create_test.dart`
- `test/offline_queue_display_test.dart`
- `test/offline_queue_resilience_test.dart`
- `test/offline_reference_map_copy_test.dart`
- `test/offline_remaining_paths_test.dart`
- `test/offline_resource_delete_test.dart`
- `test/offline_resource_identity_test.dart`
- `test/offline_support_identity_test.dart`
- `test/offline_sync_services_test.dart`
- `test/offline_workflow_action_test.dart`
- `test/online_transition_regression_test.dart`
- `test/operations_catalog_test.dart`
- `test/operations_dialog_test.dart`
- `test/operations_store_test.dart`
- `test/paged_booking_source_test.dart`
- `test/paged_data_sliver_test.dart`
- `test/pm_kpi_all_time_test.dart`
- `test/pm_kpi_dialog_test.dart`
- `test/pm_kpi_queue_test.dart`
- `test/pm_kpi_test.dart`
- `test/popup_menu_selection_test.dart`
- `test/production_sync_replay_test.dart`
- `test/profile_view_test.dart`
- `test/queue_reclaim_diagnostic_test.dart`
- `test/queue_reclaim_resolution_test.dart`
- `test/rates_activation_test.dart`
- `test/remaining_booking_sync_conflicts_test.dart`
- `test/remaining_lazy_lists_test.dart`
- `test/retained_section_selection_test.dart`
- `test/retained_section_stack_test.dart`
- `test/retained_stream_builder_test.dart`
- `test/role_assigned_startup_test.dart`
- `test/search_dropdown_dismiss_test.dart`
- `test/services/booking_chassis_lifecycle_test.dart`
- `test/shared_replay_stream_test.dart`
- `test/startup_splash_handoff_test.dart`
- `test/superseded_booking_assignment_test.dart`
- `test/support/investor_fixtures.dart`
- `test/support/investor_statement_harness.dart`
- `test/support/merge_aware_firestore.dart`
- `test/support_alert_deduplicator_test.dart`
- `test/support_contact_scope_test.dart`
- `test/support_grouped_lazy_list_test.dart`
- `test/support_manual_retry_test.dart`
- `test/support_message_identity_test.dart`
- `test/support_read_marker_order_test.dart`
- `test/support_snapshot_documents_test.dart`
- `test/sync_dependency_recovery_test.dart`
- `test/sync_diagnostic_outbox_test.dart`
- `test/sync_error_count_reconciliation_test.dart`
- `test/sync_error_log_service_test.dart`
- `test/sync_recovery_regression_test.dart`
- `test/sync_transition_regression_test.dart`
- `test/text_width_cache_test.dart`
- `test/user_activity_test.dart`
- `test/user_bookings_lazy_list_test.dart`
- `test/vehicle_make_helper_test.dart`
- `test/web/cache_mirror_codec_test.dart`
- `test/web/diagnostic_write_lock_test.dart`
- `test/web/firestore_cache_recovery_test.dart`
- `test/web/offline_browser_persistence_test.dart`
- `test/web/persisted_chat_image_test.dart`
- `test/widget_test.dart`
- `tool/cleanup_chassis_orphan_drivers.mjs`
- `tool/emulator_release_validation.dart`
- `tool/firebase.emulator.json`
- `tool/run_emulator_release_validation.mjs`
- `vercel.json`
- `web/app_service_worker.js`
- `web/download.html`
- `web/favicon.png`
- `web/firebase-messaging-sw.js`
- `web/flutter_bootstrap.js`
- `web/icons/Icon-192.png`
- `web/icons/Icon-512.png`
- `web/icons/Icon-maskable-192.png`
- `web/icons/Icon-maskable-512.png`
- `web/icons/apple-touch-icon-152.png`
- `web/icons/apple-touch-icon-167.png`
- `web/icons/apple-touch-icon-180.png`
- `web/index.html`
- `web/manifest.json`
- `web/script/installpwa.js`
- `web/social-preview.png`

## Accessible project conversation files

254 session files had the exact workspace cwd. Includes archived records and duplicate/forked histories; this is not a count of meetings or unique tasks. The earliest matching session begins May 25, 2026 in Asia/Manila. Direct requests were indexed; approval-review transcript copies were excluded from the selected evidence register.

- [rollout-2026-05-25T00-58-43-019e5aec-b7ef-71f1-a7c3-b59c627609a0.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/05/25/rollout-2026-05-25T00-58-43-019e5aec-b7ef-71f1-a7c3-b59c627609a0.jsonl)
- [rollout-2026-06-10T09-48-06-019eaf37-2241-7450-aef0-e2e021384d95.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/06/10/rollout-2026-06-10T09-48-06-019eaf37-2241-7450-aef0-e2e021384d95.jsonl)
- [rollout-2026-06-25T11-56-17-019efceb-dffd-7a12-ac43-8d468c7e130f.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/06/25/rollout-2026-06-25T11-56-17-019efceb-dffd-7a12-ac43-8d468c7e130f.jsonl)
- [rollout-2026-07-03T02-48-43-019f2429-7056-79d1-9df1-6bc1949b9ec3.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/07/03/rollout-2026-07-03T02-48-43-019f2429-7056-79d1-9df1-6bc1949b9ec3.jsonl)
- [rollout-2026-08-11T00-57-50-019fec9b-f0fa-7e63-867d-d7802b3e5a6a.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/08/11/rollout-2026-08-11T00-57-50-019fec9b-f0fa-7e63-867d-d7802b3e5a6a.jsonl)
- [rollout-2026-08-27T13-19-37-01a041a8-ce36-7e81-bbba-2c53a285873a.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/08/27/rollout-2026-08-27T13-19-37-01a041a8-ce36-7e81-bbba-2c53a285873a.jsonl)
- [rollout-2026-08-29T17-08-54-01a04cc7-727f-71e1-94c2-67685046b8e9.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/08/29/rollout-2026-08-29T17-08-54-01a04cc7-727f-71e1-94c2-67685046b8e9.jsonl)
- [rollout-2026-09-01T00-05-37-01a05891-acfa-7a53-a7e9-c2f9bfbc8ede.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/01/rollout-2026-09-01T00-05-37-01a05891-acfa-7a53-a7e9-c2f9bfbc8ede.jsonl)
- [rollout-2026-09-01T04-31-44-01a05985-50dc-7140-b06c-96aaf8169b18.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/01/rollout-2026-09-01T04-31-44-01a05985-50dc-7140-b06c-96aaf8169b18.jsonl)
- [rollout-2026-09-01T04-58-34-01a0599d-e18b-7313-9366-7e7283d7dd3f.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/01/rollout-2026-09-01T04-58-34-01a0599d-e18b-7313-9366-7e7283d7dd3f.jsonl)
- [rollout-2026-09-01T05-49-24-01a059cc-6e49-72c3-9730-04b9df07ad0b.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/01/rollout-2026-09-01T05-49-24-01a059cc-6e49-72c3-9730-04b9df07ad0b.jsonl)
- [rollout-2026-09-01T13-33-58-01a05b75-bf38-7721-a795-c6865e03ef0c.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/01/rollout-2026-09-01T13-33-58-01a05b75-bf38-7721-a795-c6865e03ef0c.jsonl)
- [rollout-2026-09-01T14-56-39-01a05bc1-72db-7bb2-9e0f-853108df250d.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/01/rollout-2026-09-01T14-56-39-01a05bc1-72db-7bb2-9e0f-853108df250d.jsonl)
- [rollout-2026-09-01T16-59-53-01a05c32-4486-7aa0-897a-38a5a8fbcc98.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/01/rollout-2026-09-01T16-59-53-01a05c32-4486-7aa0-897a-38a5a8fbcc98.jsonl)
- [rollout-2026-09-01T20-49-34-01a05d04-8dd4-7471-8c1a-5f12409d24e2.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/01/rollout-2026-09-01T20-49-34-01a05d04-8dd4-7471-8c1a-5f12409d24e2.jsonl)
- [rollout-2026-09-01T21-58-37-01a05d43-c415-74c1-b9f9-d028cf80f1be.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/01/rollout-2026-09-01T21-58-37-01a05d43-c415-74c1-b9f9-d028cf80f1be.jsonl)
- [rollout-2026-09-01T22-18-04-01a05d55-930c-7ab0-84e4-434b8c2f61d2.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/01/rollout-2026-09-01T22-18-04-01a05d55-930c-7ab0-84e4-434b8c2f61d2.jsonl)
- [rollout-2026-09-01T23-04-04-01a05d7f-afe8-7d53-be1f-b30a31dc065a.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/01/rollout-2026-09-01T23-04-04-01a05d7f-afe8-7d53-be1f-b30a31dc065a.jsonl)
- [rollout-2026-09-02T00-34-37-01a05dd2-973e-7261-9678-2c67bb17dec4.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/02/rollout-2026-09-02T00-34-37-01a05dd2-973e-7261-9678-2c67bb17dec4.jsonl)
- [rollout-2026-09-02T00-46-20-01a05ddd-51ff-7453-b8a8-b0e005603780.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/02/rollout-2026-09-02T00-46-20-01a05ddd-51ff-7453-b8a8-b0e005603780.jsonl)
- [rollout-2026-09-02T01-40-36-01a05e0f-0101-74d2-9d45-8d610d5597f9.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/02/rollout-2026-09-02T01-40-36-01a05e0f-0101-74d2-9d45-8d610d5597f9.jsonl)
- [rollout-2026-09-02T02-14-22-01a05e2d-e9c3-7780-8132-d5ca5553fc43.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/02/rollout-2026-09-02T02-14-22-01a05e2d-e9c3-7780-8132-d5ca5553fc43.jsonl)
- [rollout-2026-09-02T03-46-18-01a05e82-1477-70d2-a377-fe9542e66a9a.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/02/rollout-2026-09-02T03-46-18-01a05e82-1477-70d2-a377-fe9542e66a9a.jsonl)
- [rollout-2026-09-02T03-57-02-01a05e8b-ea0b-7ad0-bdcb-2eb990ab20d9.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/02/rollout-2026-09-02T03-57-02-01a05e8b-ea0b-7ad0-bdcb-2eb990ab20d9.jsonl)
- [rollout-2026-09-02T04-15-20-01a05e9c-aadf-7020-b087-154dc7c25f17.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/02/rollout-2026-09-02T04-15-20-01a05e9c-aadf-7020-b087-154dc7c25f17.jsonl)
- [rollout-2026-09-02T04-20-38-01a05ea1-827e-7311-a1d1-8d1d9edde22f.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/02/rollout-2026-09-02T04-20-38-01a05ea1-827e-7311-a1d1-8d1d9edde22f.jsonl)
- [rollout-2026-09-02T05-52-27-01a05ef5-9401-7ef1-8db2-9bc60ad4256d.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/02/rollout-2026-09-02T05-52-27-01a05ef5-9401-7ef1-8db2-9bc60ad4256d.jsonl)
- [rollout-2026-09-02T13-11-12-01a06087-3f1c-7402-a0a7-7e9dbf28746c.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/02/rollout-2026-09-02T13-11-12-01a06087-3f1c-7402-a0a7-7e9dbf28746c.jsonl)
- [rollout-2026-09-02T18-27-17-01a061a8-a33b-7740-adc4-5bbf55ed5d40.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/02/rollout-2026-09-02T18-27-17-01a061a8-a33b-7740-adc4-5bbf55ed5d40.jsonl)
- [rollout-2026-09-02T19-40-40-01a061eb-d284-7a31-ab81-2ef4a40bf37c.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/02/rollout-2026-09-02T19-40-40-01a061eb-d284-7a31-ab81-2ef4a40bf37c.jsonl)
- [rollout-2026-09-02T21-05-12-01a06239-39c5-70c2-a960-382016cfc598.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/02/rollout-2026-09-02T21-05-12-01a06239-39c5-70c2-a960-382016cfc598.jsonl)
- [rollout-2026-09-02T21-07-08-01a0623a-ff05-7be0-b738-f638259cd0de.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/02/rollout-2026-09-02T21-07-08-01a0623a-ff05-7be0-b738-f638259cd0de.jsonl)
- [rollout-2026-09-03T01-08-05-01a06317-9691-74a1-8685-972827671a25.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/03/rollout-2026-09-03T01-08-05-01a06317-9691-74a1-8685-972827671a25.jsonl)
- [rollout-2026-09-03T02-00-18-01a06347-6633-7cc0-a7b3-6197797e3217.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/03/rollout-2026-09-03T02-00-18-01a06347-6633-7cc0-a7b3-6197797e3217.jsonl)
- [rollout-2026-09-03T03-35-43-01a0639e-c17e-7bf0-88b0-8f7c49f68e7b.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/03/rollout-2026-09-03T03-35-43-01a0639e-c17e-7bf0-88b0-8f7c49f68e7b.jsonl)
- [rollout-2026-09-03T04-24-39-01a063cb-8d29-7892-9f14-7b62f5312928.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/03/rollout-2026-09-03T04-24-39-01a063cb-8d29-7892-9f14-7b62f5312928.jsonl)
- [rollout-2026-09-03T04-34-22-01a063d4-70f0-7d00-95a0-e099e0e10f09.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/03/rollout-2026-09-03T04-34-22-01a063d4-70f0-7d00-95a0-e099e0e10f09.jsonl)
- [rollout-2026-09-03T04-57-54-01a063e9-fc57-7793-8e8f-9ed152115af8.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/03/rollout-2026-09-03T04-57-54-01a063e9-fc57-7793-8e8f-9ed152115af8.jsonl)
- [rollout-2026-09-03T05-38-18-01a0640e-fa3b-7991-8341-f05247e1ed80.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/03/rollout-2026-09-03T05-38-18-01a0640e-fa3b-7991-8341-f05247e1ed80.jsonl)
- [rollout-2026-09-03T06-07-37-01a06429-d276-7af3-a7bc-1e766bd404f4.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/03/rollout-2026-09-03T06-07-37-01a06429-d276-7af3-a7bc-1e766bd404f4.jsonl)
- [rollout-2026-09-03T06-31-43-01a0643f-e0ba-7c32-a1d1-8179322198fa.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/03/rollout-2026-09-03T06-31-43-01a0643f-e0ba-7c32-a1d1-8179322198fa.jsonl)
- [rollout-2026-09-03T06-39-50-01a06447-4f44-74b3-a99a-e3bc1d9a76a6.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/03/rollout-2026-09-03T06-39-50-01a06447-4f44-74b3-a99a-e3bc1d9a76a6.jsonl)
- [rollout-2026-09-03T06-43-53-01a0644b-0664-7013-8133-afcf55baf036.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/03/rollout-2026-09-03T06-43-53-01a0644b-0664-7013-8133-afcf55baf036.jsonl)
- [rollout-2026-09-03T06-54-38-01a06454-ddbd-7052-972b-c66d7fe57356.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/03/rollout-2026-09-03T06-54-38-01a06454-ddbd-7052-972b-c66d7fe57356.jsonl)
- [rollout-2026-09-03T07-33-19-01a06478-498a-7a80-82c9-f861169e7b97.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/03/rollout-2026-09-03T07-33-19-01a06478-498a-7a80-82c9-f861169e7b97.jsonl)
- [rollout-2026-09-03T15-23-41-01a06626-eb77-7f32-b422-616198093393.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/03/rollout-2026-09-03T15-23-41-01a06626-eb77-7f32-b422-616198093393.jsonl)
- [rollout-2026-09-04T04-12-12-01a068e6-8309-7832-ae5b-31b6cd55497a.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/04/rollout-2026-09-04T04-12-12-01a068e6-8309-7832-ae5b-31b6cd55497a.jsonl)
- [rollout-2026-09-04T05-53-15-01a06943-0754-7f12-b84a-b6fb37da78b6.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/04/rollout-2026-09-04T05-53-15-01a06943-0754-7f12-b84a-b6fb37da78b6.jsonl)
- [rollout-2026-09-04T06-04-26-01a0694d-4530-7082-8bea-79c913f46b1f.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/04/rollout-2026-09-04T06-04-26-01a0694d-4530-7082-8bea-79c913f46b1f.jsonl)
- [rollout-2026-09-04T06-19-22-01a0695a-ef84-7af3-8df3-47acc8760a65.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/04/rollout-2026-09-04T06-19-22-01a0695a-ef84-7af3-8df3-47acc8760a65.jsonl)
- [rollout-2026-09-04T06-44-20-01a06971-c9d8-7730-af96-f2598aef0753.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/04/rollout-2026-09-04T06-44-20-01a06971-c9d8-7730-af96-f2598aef0753.jsonl)
- [rollout-2026-09-04T06-49-48-01a06976-ccaf-75a2-b0f8-826ec359c89d.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/04/rollout-2026-09-04T06-49-48-01a06976-ccaf-75a2-b0f8-826ec359c89d.jsonl)
- [rollout-2026-09-04T07-06-06-01a06985-b903-7830-bdab-57dbe4999243.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/04/rollout-2026-09-04T07-06-06-01a06985-b903-7830-bdab-57dbe4999243.jsonl)
- [rollout-2026-09-05T05-07-20-01a06e3f-5919-7a02-b909-ed163de94e53.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/05/rollout-2026-09-05T05-07-20-01a06e3f-5919-7a02-b909-ed163de94e53.jsonl)
- [rollout-2026-09-05T06-02-38-01a06e71-f8d0-7750-b6dd-18c8a2167e65.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/05/rollout-2026-09-05T06-02-38-01a06e71-f8d0-7750-b6dd-18c8a2167e65.jsonl)
- [rollout-2026-09-05T06-44-51-01a06e98-a247-7e63-8ac4-1c119d12d29b.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/05/rollout-2026-09-05T06-44-51-01a06e98-a247-7e63-8ac4-1c119d12d29b.jsonl)
- [rollout-2026-09-05T06-56-00-01a06ea2-d69c-7d23-9e31-faa412835229.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/05/rollout-2026-09-05T06-56-00-01a06ea2-d69c-7d23-9e31-faa412835229.jsonl)
- [rollout-2026-09-05T07-01-39-01a06ea8-0324-7072-8c7b-68df693699a3.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/05/rollout-2026-09-05T07-01-39-01a06ea8-0324-7072-8c7b-68df693699a3.jsonl)
- [rollout-2026-09-05T07-17-49-01a06eb6-ce1b-7fc0-a722-a02ded22c5d6.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/05/rollout-2026-09-05T07-17-49-01a06eb6-ce1b-7fc0-a722-a02ded22c5d6.jsonl)
- [rollout-2026-09-05T07-43-08-01a06ecd-fb88-7f22-9eda-e418b850d91b.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/05/rollout-2026-09-05T07-43-08-01a06ecd-fb88-7f22-9eda-e418b850d91b.jsonl)
- [rollout-2026-09-05T08-02-47-01a06edf-fa5b-7af2-8860-2702f5391508.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/05/rollout-2026-09-05T08-02-47-01a06edf-fa5b-7af2-8860-2702f5391508.jsonl)
- [rollout-2026-09-05T08-20-29-01a06ef0-2eb2-7500-aaa5-77f8eb966e94.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/05/rollout-2026-09-05T08-20-29-01a06ef0-2eb2-7500-aaa5-77f8eb966e94.jsonl)
- [rollout-2026-09-05T08-38-37-01a06f00-c882-7550-a3c5-15c2dd3b21e9.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/05/rollout-2026-09-05T08-38-37-01a06f00-c882-7550-a3c5-15c2dd3b21e9.jsonl)
- [rollout-2026-09-13T06-35-35-01a097c3-03c0-7c70-ac64-915561d7d57b.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/13/rollout-2026-09-13T06-35-35-01a097c3-03c0-7c70-ac64-915561d7d57b.jsonl)
- [rollout-2026-09-13T06-53-33-01a097d3-78ad-72f1-9479-7fe63e3d0207.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/13/rollout-2026-09-13T06-53-33-01a097d3-78ad-72f1-9479-7fe63e3d0207.jsonl)
- [rollout-2026-09-13T07-27-14-01a097f2-4d38-7152-adf6-0d8f7f97259c.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/13/rollout-2026-09-13T07-27-14-01a097f2-4d38-7152-adf6-0d8f7f97259c.jsonl)
- [rollout-2026-09-13T15-09-02-019fec9b-f0fa-7e63-867d-d7802b3e5a6a_01a09999-16f7-7fc2-a520-ebed55430067.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/13/rollout-2026-09-13T15-09-02-019fec9b-f0fa-7e63-867d-d7802b3e5a6a_01a09999-16f7-7fc2-a520-ebed55430067.jsonl)
- [rollout-2026-09-13T15-09-02-01a09999-17ec-7ef3-bf3e-47c1b51dc7aa.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/13/rollout-2026-09-13T15-09-02-01a09999-17ec-7ef3-bf3e-47c1b51dc7aa.jsonl)
- [rollout-2026-09-13T17-33-46-01a09a1d-99fe-7f30-adca-3905c28ced54.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/13/rollout-2026-09-13T17-33-46-01a09a1d-99fe-7f30-adca-3905c28ced54.jsonl)
- [rollout-2026-09-14T03-39-57-01a09c48-94d7-71b3-9868-58c6798df577.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/14/rollout-2026-09-14T03-39-57-01a09c48-94d7-71b3-9868-58c6798df577.jsonl)
- [rollout-2026-09-14T03-59-50-019fec9b-f0fa-7e63-867d-d7802b3e5a6a_01a09c5a-c713-7191-8db7-d4c5a2ea7bc9.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/14/rollout-2026-09-14T03-59-50-019fec9b-f0fa-7e63-867d-d7802b3e5a6a_01a09c5a-c713-7191-8db7-d4c5a2ea7bc9.jsonl)
- [rollout-2026-09-14T03-59-50-01a09c5a-c7dc-7b61-bcae-8e76908b66b2.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/14/rollout-2026-09-14T03-59-50-01a09c5a-c7dc-7b61-bcae-8e76908b66b2.jsonl)
- [rollout-2026-09-14T04-00-21-01a09c5b-41c6-7d41-9028-dea741d5f735.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/14/rollout-2026-09-14T04-00-21-01a09c5b-41c6-7d41-9028-dea741d5f735.jsonl)
- [rollout-2026-09-14T05-24-58-019fec9b-f0fa-7e63-867d-d7802b3e5a6a_01a09ca8-b8f9-75e2-90f8-50f1c0314a96.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/14/rollout-2026-09-14T05-24-58-019fec9b-f0fa-7e63-867d-d7802b3e5a6a_01a09ca8-b8f9-75e2-90f8-50f1c0314a96.jsonl)
- [rollout-2026-09-14T05-27-07-01a09caa-b187-7f31-8d5f-a2a2912a8cb2.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/14/rollout-2026-09-14T05-27-07-01a09caa-b187-7f31-8d5f-a2a2912a8cb2.jsonl)
- [rollout-2026-09-14T07-16-48-01a09d0f-1c9f-73f3-bb2f-a384f89f2af0.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/14/rollout-2026-09-14T07-16-48-01a09d0f-1c9f-73f3-bb2f-a384f89f2af0.jsonl)
- [rollout-2026-09-14T08-14-33-019fec9b-f0fa-7e63-867d-d7802b3e5a6a_01a09d43-fbec-7990-ab68-643b360d23c8.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/14/rollout-2026-09-14T08-14-33-019fec9b-f0fa-7e63-867d-d7802b3e5a6a_01a09d43-fbec-7990-ab68-643b360d23c8.jsonl)
- [rollout-2026-09-14T08-14-33-01a09d43-fd06-7b00-8c1e-c9cbae346384.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/14/rollout-2026-09-14T08-14-33-01a09d43-fd06-7b00-8c1e-c9cbae346384.jsonl)
- [rollout-2026-09-14T08-27-42-01a09d50-0583-7a10-bde4-1b7279f06bf2.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/14/rollout-2026-09-14T08-27-42-01a09d50-0583-7a10-bde4-1b7279f06bf2.jsonl)
- [rollout-2026-09-17T03-29-03-01a0abb1-af40-70c1-ba07-3f1e85571b60.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/17/rollout-2026-09-17T03-29-03-01a0abb1-af40-70c1-ba07-3f1e85571b60.jsonl)
- [rollout-2026-09-17T03-43-31-01a0abbe-ed5b-77a3-9615-6ce215548b0d.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/17/rollout-2026-09-17T03-43-31-01a0abbe-ed5b-77a3-9615-6ce215548b0d.jsonl)
- [rollout-2026-09-17T04-29-22-01a0abe8-e7f3-79f0-b85a-a8bf78af461d.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/17/rollout-2026-09-17T04-29-22-01a0abe8-e7f3-79f0-b85a-a8bf78af461d.jsonl)
- [rollout-2026-09-18T10-15-14-01a0b24b-eb0e-7163-bd35-d45f8dd7507b.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/18/rollout-2026-09-18T10-15-14-01a0b24b-eb0e-7163-bd35-d45f8dd7507b.jsonl)
- [rollout-2026-09-18T10-53-58-01a0b26f-5ec7-75b3-b053-04918ac56207.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/18/rollout-2026-09-18T10-53-58-01a0b26f-5ec7-75b3-b053-04918ac56207.jsonl)
- [rollout-2026-09-18T18-00-59-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0b3f6-5122-7d31-ba64-e8a59ba4cf08.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/18/rollout-2026-09-18T18-00-59-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0b3f6-5122-7d31-ba64-e8a59ba4cf08.jsonl)
- [rollout-2026-09-18T18-01-01-01a0b3f6-582c-7a62-8ce8-237baeeb4f9b.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/18/rollout-2026-09-18T18-01-01-01a0b3f6-582c-7a62-8ce8-237baeeb4f9b.jsonl)
- [rollout-2026-09-18T18-14-08-01a0b402-5d33-75a2-9586-b395c139abfd.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/18/rollout-2026-09-18T18-14-08-01a0b402-5d33-75a2-9586-b395c139abfd.jsonl)
- [rollout-2026-09-18T18-21-34-01a0b409-27c8-7ac3-be08-8ab14fea37f1.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/18/rollout-2026-09-18T18-21-34-01a0b409-27c8-7ac3-be08-8ab14fea37f1.jsonl)
- [rollout-2026-09-18T23-47-20-01a0b533-6a37-7e70-a210-ad54d82e7b94.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/18/rollout-2026-09-18T23-47-20-01a0b533-6a37-7e70-a210-ad54d82e7b94.jsonl)
- [rollout-2026-09-19T01-10-22-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0b57f-6d71-7412-8ce5-c723500f6487.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T01-10-22-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0b57f-6d71-7412-8ce5-c723500f6487.jsonl)
- [rollout-2026-09-19T01-10-22-01a0b57f-6ee0-71a1-8899-14d763c416d8.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T01-10-22-01a0b57f-6ee0-71a1-8899-14d763c416d8.jsonl)
- [rollout-2026-09-19T01-13-18-01a0b582-1c35-77e0-9080-ffe49e9d81a4.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T01-13-18-01a0b582-1c35-77e0-9080-ffe49e9d81a4.jsonl)
- [rollout-2026-09-19T01-20-19-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0b588-8a23-7322-a5d1-47379af7f68a.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T01-20-19-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0b588-8a23-7322-a5d1-47379af7f68a.jsonl)
- [rollout-2026-09-19T01-20-19-01a0b588-8bba-7462-a4f3-77eadcc3e706.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T01-20-19-01a0b588-8bba-7462-a4f3-77eadcc3e706.jsonl)
- [rollout-2026-09-19T01-36-47-01a0b597-9b81-76c3-8b7a-d135441b0460.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T01-36-47-01a0b597-9b81-76c3-8b7a-d135441b0460.jsonl)
- [rollout-2026-09-19T02-33-33-01a0b5cb-97d6-7093-92f3-8574fc113317.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T02-33-33-01a0b5cb-97d6-7093-92f3-8574fc113317.jsonl)
- [rollout-2026-09-19T02-56-48-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0b5e0-e0f3-7bf1-9d1e-6f45f5be994f.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T02-56-48-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0b5e0-e0f3-7bf1-9d1e-6f45f5be994f.jsonl)
- [rollout-2026-09-19T02-56-49-01a0b5e0-e265-75e1-a824-b7536a11f347.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T02-56-49-01a0b5e0-e265-75e1-a824-b7536a11f347.jsonl)
- [rollout-2026-09-19T02-58-45-01a0b5e2-a77b-7110-9a10-1fb618cf3b8f.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T02-58-45-01a0b5e2-a77b-7110-9a10-1fb618cf3b8f.jsonl)
- [rollout-2026-09-19T03-57-57-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0b618-dbe7-76a2-9a02-340b7c74cf49.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T03-57-57-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0b618-dbe7-76a2-9a02-340b7c74cf49.jsonl)
- [rollout-2026-09-19T03-57-58-01a0b618-dd84-75a2-a2f8-1f4c7d174fa5.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T03-57-58-01a0b618-dd84-75a2-a2f8-1f4c7d174fa5.jsonl)
- [rollout-2026-09-19T03-58-16-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0b619-260e-7791-8633-9e6e841e1f39.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T03-58-16-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0b619-260e-7791-8633-9e6e841e1f39.jsonl)
- [rollout-2026-09-19T03-58-16-01a0b619-2744-7771-933d-661a6b1fb765.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T03-58-16-01a0b619-2744-7771-933d-661a6b1fb765.jsonl)
- [rollout-2026-09-19T03-58-28-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0b619-52ba-7240-87b8-40e49a94105a.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T03-58-28-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0b619-52ba-7240-87b8-40e49a94105a.jsonl)
- [rollout-2026-09-19T03-58-28-01a0b619-53e4-7260-ae13-3e70947f2d24.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T03-58-28-01a0b619-53e4-7260-ae13-3e70947f2d24.jsonl)
- [rollout-2026-09-19T04-00-11-01a0b61a-e852-74b1-b91e-fa72e2513122.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T04-00-11-01a0b61a-e852-74b1-b91e-fa72e2513122.jsonl)
- [rollout-2026-09-19T04-37-36-01a0b63d-270f-72d1-b73a-cc8c0a18c56e.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T04-37-36-01a0b63d-270f-72d1-b73a-cc8c0a18c56e.jsonl)
- [rollout-2026-09-19T06-41-18-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0b6ae-66d9-7883-b2a6-c5c132616484.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T06-41-18-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0b6ae-66d9-7883-b2a6-c5c132616484.jsonl)
- [rollout-2026-09-19T06-41-18-01a0b6ae-6947-7792-9251-96a49f657f8c.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T06-41-18-01a0b6ae-6947-7792-9251-96a49f657f8c.jsonl)
- [rollout-2026-09-19T06-43-14-01a0b6b0-2dd1-79d2-a0d0-b574aca3b2b9.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T06-43-14-01a0b6b0-2dd1-79d2-a0d0-b574aca3b2b9.jsonl)
- [rollout-2026-09-19T07-01-56-01a0b6c1-4bd7-7220-ad1d-edde004b60ce.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T07-01-56-01a0b6c1-4bd7-7220-ad1d-edde004b60ce.jsonl)
- [rollout-2026-09-19T07-46-46-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0b6ea-5670-7a61-98eb-c9c69555ac0b.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T07-46-46-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0b6ea-5670-7a61-98eb-c9c69555ac0b.jsonl)
- [rollout-2026-09-19T07-46-46-01a0b6ea-57da-7903-8cdb-39bf6c8eac5e.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T07-46-46-01a0b6ea-57da-7903-8cdb-39bf6c8eac5e.jsonl)
- [rollout-2026-09-19T07-48-22-01a0b6eb-d005-7432-bf6a-8730180bdeba.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T07-48-22-01a0b6eb-d005-7432-bf6a-8730180bdeba.jsonl)
- [rollout-2026-09-19T09-20-54-01a0b740-85dc-7af0-8161-1f624753b618.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T09-20-54-01a0b740-85dc-7af0-8161-1f624753b618.jsonl)
- [rollout-2026-09-19T15-47-44-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0b8a2-af37-7493-be3d-79997dbbc600.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T15-47-44-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0b8a2-af37-7493-be3d-79997dbbc600.jsonl)
- [rollout-2026-09-19T15-47-45-01a0b8a2-b0ba-72d0-9ba9-d9d9fd053d74.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T15-47-45-01a0b8a2-b0ba-72d0-9ba9-d9d9fd053d74.jsonl)
- [rollout-2026-09-19T15-51-55-01a0b8a6-8505-7883-a49e-1608abf8c554.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T15-51-55-01a0b8a6-8505-7883-a49e-1608abf8c554.jsonl)
- [rollout-2026-09-19T16-57-33-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0b8e2-98b8-7031-918b-fd0127ebe9f9.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T16-57-33-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0b8e2-98b8-7031-918b-fd0127ebe9f9.jsonl)
- [rollout-2026-09-19T16-57-33-01a0b8e2-9a30-7b13-8f23-f61014a5eeff.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T16-57-33-01a0b8e2-9a30-7b13-8f23-f61014a5eeff.jsonl)
- [rollout-2026-09-19T17-06-22-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0b8ea-abbe-7120-8c5d-674b7e04c76e.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T17-06-22-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0b8ea-abbe-7120-8c5d-674b7e04c76e.jsonl)
- [rollout-2026-09-19T17-06-22-01a0b8ea-ac44-7281-8862-29892559cb68.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T17-06-22-01a0b8ea-ac44-7281-8862-29892559cb68.jsonl)
- [rollout-2026-09-19T20-42-57-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0b9b0-f7a0-70f1-b696-f62f3ca72a9c.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T20-42-57-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0b9b0-f7a0-70f1-b696-f62f3ca72a9c.jsonl)
- [rollout-2026-09-19T20-42-58-01a0b9b0-f8f0-75f3-a5b8-65541542047d.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T20-42-58-01a0b9b0-f8f0-75f3-a5b8-65541542047d.jsonl)
- [rollout-2026-09-19T20-44-53-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0b9b2-b9c5-7473-be99-f1bad671cfaa.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T20-44-53-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0b9b2-b9c5-7473-be99-f1bad671cfaa.jsonl)
- [rollout-2026-09-19T20-44-53-01a0b9b2-bb05-7c53-b809-972e77733484.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T20-44-53-01a0b9b2-bb05-7c53-b809-972e77733484.jsonl)
- [rollout-2026-09-19T23-06-43-01a0ba34-971b-7af2-8737-d8b4673e5f1f.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T23-06-43-01a0ba34-971b-7af2-8737-d8b4673e5f1f.jsonl)
- [rollout-2026-09-19T23-18-55-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0ba3f-bf31-7713-a5a6-18d092974d2f.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T23-18-55-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0ba3f-bf31-7713-a5a6-18d092974d2f.jsonl)
- [rollout-2026-09-19T23-18-55-01a0ba3f-c095-7a02-9505-dfa22108c153.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T23-18-55-01a0ba3f-c095-7a02-9505-dfa22108c153.jsonl)
- [rollout-2026-09-19T23-32-19-01a0ba4c-0742-7192-aa30-079c75c1ab92.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T23-32-19-01a0ba4c-0742-7192-aa30-079c75c1ab92.jsonl)
- [rollout-2026-09-19T23-45-42-01a0ba58-459f-7a90-bf05-9a2f71022a61.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/19/rollout-2026-09-19T23-45-42-01a0ba58-459f-7a90-bf05-9a2f71022a61.jsonl)
- [rollout-2026-09-20T00-50-07-01a0ba93-4050-70b3-85c0-b941595ff3e1.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/20/rollout-2026-09-20T00-50-07-01a0ba93-4050-70b3-85c0-b941595ff3e1.jsonl)
- [rollout-2026-09-20T00-56-17-01a0ba98-e622-7712-beb4-20a259924926.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/20/rollout-2026-09-20T00-56-17-01a0ba98-e622-7712-beb4-20a259924926.jsonl)
- [rollout-2026-09-20T01-39-31-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0bac0-7927-75b3-a271-b8eff2d14697.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/20/rollout-2026-09-20T01-39-31-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0bac0-7927-75b3-a271-b8eff2d14697.jsonl)
- [rollout-2026-09-20T01-39-31-01a0bac0-7ac5-7091-97cb-601a4307c2fe.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/20/rollout-2026-09-20T01-39-31-01a0bac0-7ac5-7091-97cb-601a4307c2fe.jsonl)
- [rollout-2026-09-20T01-39-43-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0bac0-a829-7162-8261-164e10ae613e.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/20/rollout-2026-09-20T01-39-43-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0bac0-a829-7162-8261-164e10ae613e.jsonl)
- [rollout-2026-09-20T01-39-43-01a0bac0-a96d-7ff2-9585-2a5b8e1e7d26.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/20/rollout-2026-09-20T01-39-43-01a0bac0-a96d-7ff2-9585-2a5b8e1e7d26.jsonl)
- [rollout-2026-09-20T01-44-39-01a0bac5-2e7a-79b0-92fb-81da1e28fe21.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/20/rollout-2026-09-20T01-44-39-01a0bac5-2e7a-79b0-92fb-81da1e28fe21.jsonl)
- [rollout-2026-09-20T02-01-48-01a0bad4-df52-7893-9f87-e38b86367d45.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/20/rollout-2026-09-20T02-01-48-01a0bad4-df52-7893-9f87-e38b86367d45.jsonl)
- [rollout-2026-09-20T03-28-11-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0bb23-f754-7d81-a258-2d79279a6708.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/20/rollout-2026-09-20T03-28-11-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0bb23-f754-7d81-a258-2d79279a6708.jsonl)
- [rollout-2026-09-20T03-28-12-01a0bb23-f9bc-7651-953b-59fe2e68ee56.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/20/rollout-2026-09-20T03-28-12-01a0bb23-f9bc-7651-953b-59fe2e68ee56.jsonl)
- [rollout-2026-09-20T03-29-43-01a0bb25-5e96-79e0-95fb-301a470b2852.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/20/rollout-2026-09-20T03-29-43-01a0bb25-5e96-79e0-95fb-301a470b2852.jsonl)
- [rollout-2026-09-20T05-22-05-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0bb8c-3df5-7e71-b623-1aa9996ca3e3.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/20/rollout-2026-09-20T05-22-05-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0bb8c-3df5-7e71-b623-1aa9996ca3e3.jsonl)
- [rollout-2026-09-20T05-22-05-01a0bb8c-3fd1-7731-b87b-3ccaeec1ebbe.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/20/rollout-2026-09-20T05-22-05-01a0bb8c-3fd1-7731-b87b-3ccaeec1ebbe.jsonl)
- [rollout-2026-09-20T14-25-22-01a0bd7d-a39e-7382-9772-f16ca75a9de4.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/20/rollout-2026-09-20T14-25-22-01a0bd7d-a39e-7382-9772-f16ca75a9de4.jsonl)
- [rollout-2026-09-20T15-31-38-01a0bdba-4d79-78b1-9959-055c0be3ea54.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/20/rollout-2026-09-20T15-31-38-01a0bdba-4d79-78b1-9959-055c0be3ea54.jsonl)
- [rollout-2026-09-20T17-39-08-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0be2f-08c3-77b3-b915-c518770d145d.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/20/rollout-2026-09-20T17-39-08-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0be2f-08c3-77b3-b915-c518770d145d.jsonl)
- [rollout-2026-09-20T17-39-09-01a0be2f-0a41-7a01-8423-1765f0405c90.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/20/rollout-2026-09-20T17-39-09-01a0be2f-0a41-7a01-8423-1765f0405c90.jsonl)
- [rollout-2026-09-20T17-56-26-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0be3e-dd4f-7e53-bf18-6324f0ec9c9e.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/20/rollout-2026-09-20T17-56-26-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0be3e-dd4f-7e53-bf18-6324f0ec9c9e.jsonl)
- [rollout-2026-09-20T17-56-26-01a0be3e-df9f-7292-9d16-7e97841eba63.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/20/rollout-2026-09-20T17-56-26-01a0be3e-df9f-7292-9d16-7e97841eba63.jsonl)
- [rollout-2026-09-20T18-11-03-01a0be4c-3f23-78e2-a0da-f15d3198c7ef.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/20/rollout-2026-09-20T18-11-03-01a0be4c-3f23-78e2-a0da-f15d3198c7ef.jsonl)
- [rollout-2026-09-20T19-19-17-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0be8a-badd-7692-bc1d-8d1e0da79b60.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/20/rollout-2026-09-20T19-19-17-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0be8a-badd-7692-bc1d-8d1e0da79b60.jsonl)
- [rollout-2026-09-20T19-19-18-01a0be8a-bc80-7af3-956e-230ae9c6fd99.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/20/rollout-2026-09-20T19-19-18-01a0be8a-bc80-7af3-956e-230ae9c6fd99.jsonl)
- [rollout-2026-09-20T19-26-46-01a0be91-9180-7153-87d3-6451619b5f8d.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/20/rollout-2026-09-20T19-26-46-01a0be91-9180-7153-87d3-6451619b5f8d.jsonl)
- [rollout-2026-09-21T05-31-18-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0c0bb-09a8-73e1-abb8-8f278e85f5a6.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/21/rollout-2026-09-21T05-31-18-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0c0bb-09a8-73e1-abb8-8f278e85f5a6.jsonl)
- [rollout-2026-09-21T05-31-18-01a0c0bb-0b5d-7671-b84e-d8c7d6edd771.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/21/rollout-2026-09-21T05-31-18-01a0c0bb-0b5d-7671-b84e-d8c7d6edd771.jsonl)
- [rollout-2026-09-21T05-43-44-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0c0c6-6c4a-7512-b661-a78c58e09e3a.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/21/rollout-2026-09-21T05-43-44-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0c0c6-6c4a-7512-b661-a78c58e09e3a.jsonl)
- [rollout-2026-09-21T05-43-44-01a0c0c6-6de2-70c0-8883-fd1eea288be0.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/21/rollout-2026-09-21T05-43-44-01a0c0c6-6de2-70c0-8883-fd1eea288be0.jsonl)
- [rollout-2026-09-21T05-44-23-01a0c0c7-0602-71b0-b790-4d57ae689aa7.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/21/rollout-2026-09-21T05-44-23-01a0c0c7-0602-71b0-b790-4d57ae689aa7.jsonl)
- [rollout-2026-09-21T15-43-49-01a0c2eb-cfd4-73a2-ba53-04717af2a5b6.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/21/rollout-2026-09-21T15-43-49-01a0c2eb-cfd4-73a2-ba53-04717af2a5b6.jsonl)
- [rollout-2026-09-21T15-57-07-01a0c2f7-ffa6-7003-9499-ee5bfe1508a9.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/21/rollout-2026-09-21T15-57-07-01a0c2f7-ffa6-7003-9499-ee5bfe1508a9.jsonl)
- [rollout-2026-09-21T17-45-38-01a0c35b-56c6-70e1-959f-dc0eb3402e12.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/21/rollout-2026-09-21T17-45-38-01a0c35b-56c6-70e1-959f-dc0eb3402e12.jsonl)
- [rollout-2026-09-21T20-58-06-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0c40b-8e3a-77c0-aae3-00b36f51fc6d.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/21/rollout-2026-09-21T20-58-06-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0c40b-8e3a-77c0-aae3-00b36f51fc6d.jsonl)
- [rollout-2026-09-21T20-58-07-01a0c40b-8fad-7901-a9ab-4800f494cf76.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/21/rollout-2026-09-21T20-58-07-01a0c40b-8fad-7901-a9ab-4800f494cf76.jsonl)
- [rollout-2026-09-21T22-30-29-01a0c460-2031-7971-b50e-2b43b40c19f4.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/21/rollout-2026-09-21T22-30-29-01a0c460-2031-7971-b50e-2b43b40c19f4.jsonl)
- [rollout-2026-09-22T02-54-06-01a0c551-7b4c-7742-9b80-d5c6d6f4b6ff.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/22/rollout-2026-09-22T02-54-06-01a0c551-7b4c-7742-9b80-d5c6d6f4b6ff.jsonl)
- [rollout-2026-09-22T04-40-45-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0c5b3-1f0c-78b3-8cfe-ad50654b5f3d.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/22/rollout-2026-09-22T04-40-45-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0c5b3-1f0c-78b3-8cfe-ad50654b5f3d.jsonl)
- [rollout-2026-09-22T04-40-45-01a0c5b3-208a-72f0-b9e6-db65acf45a20.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/22/rollout-2026-09-22T04-40-45-01a0c5b3-208a-72f0-b9e6-db65acf45a20.jsonl)
- [rollout-2026-09-22T04-41-33-01a0c5b3-d870-7bb0-98f5-13dc1b149439.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/22/rollout-2026-09-22T04-41-33-01a0c5b3-d870-7bb0-98f5-13dc1b149439.jsonl)
- [rollout-2026-09-22T05-10-28-01a0c5ce-5411-7d61-84e1-c58ef213f412.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/22/rollout-2026-09-22T05-10-28-01a0c5ce-5411-7d61-84e1-c58ef213f412.jsonl)
- [rollout-2026-09-22T07-54-37-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0c664-9ca2-7e60-9660-6d6b7f613a32.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/22/rollout-2026-09-22T07-54-37-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0c664-9ca2-7e60-9660-6d6b7f613a32.jsonl)
- [rollout-2026-09-22T07-54-38-01a0c664-9e34-76c1-95e0-ac4f942c8446.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/22/rollout-2026-09-22T07-54-38-01a0c664-9e34-76c1-95e0-ac4f942c8446.jsonl)
- [rollout-2026-09-22T07-55-22-01a0c665-4ce6-71a0-bf91-ccf3d47ba773.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/22/rollout-2026-09-22T07-55-22-01a0c665-4ce6-71a0-bf91-ccf3d47ba773.jsonl)
- [rollout-2026-09-22T08-16-48-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0c678-ebd5-7560-9e5a-e879e2614cd2.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/22/rollout-2026-09-22T08-16-48-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0c678-ebd5-7560-9e5a-e879e2614cd2.jsonl)
- [rollout-2026-09-22T08-16-49-01a0c678-edb1-7161-bcd4-33f3fc831941.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/22/rollout-2026-09-22T08-16-49-01a0c678-edb1-7161-bcd4-33f3fc831941.jsonl)
- [rollout-2026-09-22T08-19-14-01a0c67b-2561-7870-9908-443afda079ca.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/22/rollout-2026-09-22T08-19-14-01a0c67b-2561-7870-9908-443afda079ca.jsonl)
- [rollout-2026-09-22T08-40-37-01a0c68e-bac0-7003-af06-f51e50ca99e6.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/22/rollout-2026-09-22T08-40-37-01a0c68e-bac0-7003-af06-f51e50ca99e6.jsonl)
- [rollout-2026-09-22T10-02-15-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0c6d9-779d-7500-8598-a9dc8441a14e.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/22/rollout-2026-09-22T10-02-15-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0c6d9-779d-7500-8598-a9dc8441a14e.jsonl)
- [rollout-2026-09-22T10-02-16-01a0c6d9-791f-7bc3-ab62-ee9897770b7f.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/22/rollout-2026-09-22T10-02-16-01a0c6d9-791f-7bc3-ab62-ee9897770b7f.jsonl)
- [rollout-2026-09-22T10-03-25-01a0c6da-8973-7be0-8244-a884bb9021a1.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/22/rollout-2026-09-22T10-03-25-01a0c6da-8973-7be0-8244-a884bb9021a1.jsonl)
- [rollout-2026-09-23T13-34-01-01a0ccc1-b4e6-7b31-8567-4cfb5861dd00.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/23/rollout-2026-09-23T13-34-01-01a0ccc1-b4e6-7b31-8567-4cfb5861dd00.jsonl)
- [rollout-2026-09-23T13-41-17-01a0ccc8-5b45-71c0-b564-b7af6f92db50.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/23/rollout-2026-09-23T13-41-17-01a0ccc8-5b45-71c0-b564-b7af6f92db50.jsonl)
- [rollout-2026-09-23T13-41-17-01a0ccc8-5bef-7363-bed6-4086a2413f8b.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/23/rollout-2026-09-23T13-41-17-01a0ccc8-5bef-7363-bed6-4086a2413f8b.jsonl)
- [rollout-2026-09-23T14-37-42-01a0ccfc-0243-7fc1-98fd-f0fbada3b8cb.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/23/rollout-2026-09-23T14-37-42-01a0ccfc-0243-7fc1-98fd-f0fbada3b8cb.jsonl)
- [rollout-2026-09-23T15-31-24-01a0cd2d-2a4a-7212-893f-9e22b1385e15.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/23/rollout-2026-09-23T15-31-24-01a0cd2d-2a4a-7212-893f-9e22b1385e15.jsonl)
- [rollout-2026-09-23T16-23-21-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0cd5c-bc86-7da3-873e-83807a48f0e3.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/23/rollout-2026-09-23T16-23-21-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0cd5c-bc86-7da3-873e-83807a48f0e3.jsonl)
- [rollout-2026-09-23T16-23-22-01a0cd5c-bd37-73f2-a0c4-a9cc93688632.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/23/rollout-2026-09-23T16-23-22-01a0cd5c-bd37-73f2-a0c4-a9cc93688632.jsonl)
- [rollout-2026-09-23T16-59-16-01a0cd7d-9d47-7672-b4dc-4e2bd8c20027.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/23/rollout-2026-09-23T16-59-16-01a0cd7d-9d47-7672-b4dc-4e2bd8c20027.jsonl)
- [rollout-2026-09-23T16-59-20-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0cd7d-ac34-7543-a0f0-eccb7bf790bd.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/23/rollout-2026-09-23T16-59-20-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0cd7d-ac34-7543-a0f0-eccb7bf790bd.jsonl)
- [rollout-2026-09-23T16-59-20-01a0cd7d-ac98-7f20-aa92-69ae8979b1fa.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/23/rollout-2026-09-23T16-59-20-01a0cd7d-ac98-7f20-aa92-69ae8979b1fa.jsonl)
- [rollout-2026-09-23T18-01-58-01a0cdb7-0597-7f92-ae82-e4241a64f2f3.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/23/rollout-2026-09-23T18-01-58-01a0cdb7-0597-7f92-ae82-e4241a64f2f3.jsonl)
- [rollout-2026-09-23T18-25-33-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0cdcc-99fa-7e53-8959-962d739ec318.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/23/rollout-2026-09-23T18-25-33-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0cdcc-99fa-7e53-8959-962d739ec318.jsonl)
- [rollout-2026-09-23T18-25-33-01a0cdcc-9a7a-7291-bf51-eed173eb5f0a.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/23/rollout-2026-09-23T18-25-33-01a0cdcc-9a7a-7291-bf51-eed173eb5f0a.jsonl)
- [rollout-2026-09-23T18-25-44-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0cdcc-c63e-7401-99df-4bfcb6a8ebd4.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/23/rollout-2026-09-23T18-25-44-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0cdcc-c63e-7401-99df-4bfcb6a8ebd4.jsonl)
- [rollout-2026-09-23T18-25-44-01a0cdcc-c698-7f41-93c3-7a7b255bb04e.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/23/rollout-2026-09-23T18-25-44-01a0cdcc-c698-7f41-93c3-7a7b255bb04e.jsonl)
- [rollout-2026-09-23T18-32-15-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0cdd2-beed-7652-8475-57841f2b1ba6.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/23/rollout-2026-09-23T18-32-15-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0cdd2-beed-7652-8475-57841f2b1ba6.jsonl)
- [rollout-2026-09-23T18-32-16-01a0cdd2-bf76-7950-8561-96297abe6093.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/23/rollout-2026-09-23T18-32-16-01a0cdd2-bf76-7950-8561-96297abe6093.jsonl)
- [rollout-2026-09-23T19-47-07-01a0ce17-488d-7073-9643-95e7b4420d76.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/23/rollout-2026-09-23T19-47-07-01a0ce17-488d-7073-9643-95e7b4420d76.jsonl)
- [rollout-2026-09-23T20-17-33-01a0ce33-24a9-7631-b9ec-85f9b12e41b4.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/23/rollout-2026-09-23T20-17-33-01a0ce33-24a9-7631-b9ec-85f9b12e41b4.jsonl)
- [rollout-2026-09-23T20-20-30-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0ce35-d777-77c2-a2a3-e473864eb289.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/23/rollout-2026-09-23T20-20-30-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0ce35-d777-77c2-a2a3-e473864eb289.jsonl)
- [rollout-2026-09-23T20-20-30-01a0ce35-d81a-7262-81f2-1e8319be0346.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/23/rollout-2026-09-23T20-20-30-01a0ce35-d81a-7262-81f2-1e8319be0346.jsonl)
- [rollout-2026-09-23T22-01-50-01a0ce92-9f83-7251-853e-5c0f174d6a20.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/23/rollout-2026-09-23T22-01-50-01a0ce92-9f83-7251-853e-5c0f174d6a20.jsonl)
- [rollout-2026-09-23T22-53-14-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0cec1-ace5-7f82-b8f1-5669b19142d4.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/23/rollout-2026-09-23T22-53-14-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0cec1-ace5-7f82-b8f1-5669b19142d4.jsonl)
- [rollout-2026-09-23T22-53-14-01a0cec1-ad93-7371-8019-5d8db28aa5ce.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/23/rollout-2026-09-23T22-53-14-01a0cec1-ad93-7371-8019-5d8db28aa5ce.jsonl)
- [rollout-2026-09-24T03-23-42-01a0cfb9-4c3d-7493-9271-d86a7841ab2c.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/24/rollout-2026-09-24T03-23-42-01a0cfb9-4c3d-7493-9271-d86a7841ab2c.jsonl)
- [rollout-2026-09-24T03-27-14-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0cfbc-8718-7481-9fb9-cd9bef6e6972.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/24/rollout-2026-09-24T03-27-14-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0cfbc-8718-7481-9fb9-cd9bef6e6972.jsonl)
- [rollout-2026-09-24T03-27-14-01a0cfbc-87b0-7080-89fa-3dde0e15d733.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/24/rollout-2026-09-24T03-27-14-01a0cfbc-87b0-7080-89fa-3dde0e15d733.jsonl)
- [rollout-2026-09-24T04-52-50-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0d00a-e8b5-7350-9d68-093d65d9f1b2.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/24/rollout-2026-09-24T04-52-50-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0d00a-e8b5-7350-9d68-093d65d9f1b2.jsonl)
- [rollout-2026-09-24T04-52-51-01a0d00a-e975-7502-8a7b-455022947d07.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/24/rollout-2026-09-24T04-52-51-01a0d00a-e975-7502-8a7b-455022947d07.jsonl)
- [rollout-2026-09-24T04-57-47-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0d00f-6e0d-7053-9c83-b1cbf47de63e.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/24/rollout-2026-09-24T04-57-47-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0d00f-6e0d-7053-9c83-b1cbf47de63e.jsonl)
- [rollout-2026-09-24T04-57-47-01a0d00f-6ec3-7e11-9116-3dc1ff601460.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/24/rollout-2026-09-24T04-57-47-01a0d00f-6ec3-7e11-9116-3dc1ff601460.jsonl)
- [rollout-2026-09-24T05-44-14-01a0d039-f660-7553-8207-228b38d092a4.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/24/rollout-2026-09-24T05-44-14-01a0d039-f660-7553-8207-228b38d092a4.jsonl)
- [rollout-2026-09-24T07-01-21-01a0d080-910d-7f91-8fef-28f255533721.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/24/rollout-2026-09-24T07-01-21-01a0d080-910d-7f91-8fef-28f255533721.jsonl)
- [rollout-2026-09-24T07-08-35-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0d087-3028-7d83-99fb-bb57d5748cdd.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/24/rollout-2026-09-24T07-08-35-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0d087-3028-7d83-99fb-bb57d5748cdd.jsonl)
- [rollout-2026-09-24T07-08-35-01a0d087-30cf-7223-9d26-22b7b8864a23.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/24/rollout-2026-09-24T07-08-35-01a0d087-30cf-7223-9d26-22b7b8864a23.jsonl)
- [rollout-2026-09-24T14-47-51-01a0d22b-a60e-7331-8388-29da06f10b61.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/24/rollout-2026-09-24T14-47-51-01a0d22b-a60e-7331-8388-29da06f10b61.jsonl)
- [rollout-2026-09-24T15-23-22-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0d24c-2cca-7350-a987-155e6d6d7fc9.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/24/rollout-2026-09-24T15-23-22-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0d24c-2cca-7350-a987-155e6d6d7fc9.jsonl)
- [rollout-2026-09-24T15-23-22-01a0d24c-2d6e-7921-8aea-ad74da1b4b9c.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/24/rollout-2026-09-24T15-23-22-01a0d24c-2d6e-7921-8aea-ad74da1b4b9c.jsonl)
- [rollout-2026-09-25T00-17-52-01a0d435-8363-7c62-b8ae-b2966f5d5d42.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/25/rollout-2026-09-25T00-17-52-01a0d435-8363-7c62-b8ae-b2966f5d5d42.jsonl)
- [rollout-2026-09-25T17-52-34-01a0d7fb-2033-72f3-a318-78a80bedcefd.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/25/rollout-2026-09-25T17-52-34-01a0d7fb-2033-72f3-a318-78a80bedcefd.jsonl)
- [rollout-2026-09-29T17-27-50-01a0ec7d-ea4c-7c31-bfbe-d5209e716577.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/29/rollout-2026-09-29T17-27-50-01a0ec7d-ea4c-7c31-bfbe-d5209e716577.jsonl)
- [rollout-2026-09-29T19-57-13-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0ed06-adce-75f2-989e-7ee73847933f.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/29/rollout-2026-09-29T19-57-13-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0ed06-adce-75f2-989e-7ee73847933f.jsonl)
- [rollout-2026-09-29T19-57-13-01a0ed06-ae71-7110-b41a-887fae3b0199.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/09/29/rollout-2026-09-29T19-57-13-01a0ed06-ae71-7110-b41a-887fae3b0199.jsonl)
- [rollout-2026-10-01T19-14-45-01a0f72c-872a-77c1-93f6-4ff4a179f1ee.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/10/01/rollout-2026-10-01T19-14-45-01a0f72c-872a-77c1-93f6-4ff4a179f1ee.jsonl)
- [rollout-2026-10-01T19-24-52-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0f735-ca87-7330-b7d9-eb90561d19cd.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/10/01/rollout-2026-10-01T19-24-52-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0f735-ca87-7330-b7d9-eb90561d19cd.jsonl)
- [rollout-2026-10-01T19-24-52-01a0f735-cb24-79a2-b122-b3a6e082eea5.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/10/01/rollout-2026-10-01T19-24-52-01a0f735-cb24-79a2-b122-b3a6e082eea5.jsonl)
- [rollout-2026-10-01T19-52-37-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0f74f-30b5-7b83-9093-610e735022ea.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/10/01/rollout-2026-10-01T19-52-37-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0f74f-30b5-7b83-9093-610e735022ea.jsonl)
- [rollout-2026-10-01T19-52-37-01a0f74f-3162-70c0-9a13-279067dff1fb.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/10/01/rollout-2026-10-01T19-52-37-01a0f74f-3162-70c0-9a13-279067dff1fb.jsonl)
- [rollout-2026-10-01T20-05-17-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0f75a-cb4c-7552-a765-652e058705e9.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/10/01/rollout-2026-10-01T20-05-17-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0f75a-cb4c-7552-a765-652e058705e9.jsonl)
- [rollout-2026-10-01T20-05-17-01a0f75a-cbeb-7a50-a952-f4954aeb374e.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/10/01/rollout-2026-10-01T20-05-17-01a0f75a-cbeb-7a50-a952-f4954aeb374e.jsonl)
- [rollout-2026-10-01T22-46-35-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0f7ee-750b-7c10-b24b-14c826daf7d5.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/10/01/rollout-2026-10-01T22-46-35-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0f7ee-750b-7c10-b24b-14c826daf7d5.jsonl)
- [rollout-2026-10-01T22-46-35-01a0f7ee-75e8-7a10-82ae-e06f7051b308.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/10/01/rollout-2026-10-01T22-46-35-01a0f7ee-75e8-7a10-82ae-e06f7051b308.jsonl)
- [rollout-2026-10-02T00-13-09-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0f83d-b8c0-7631-bc2a-3888f457a5f4.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/10/02/rollout-2026-10-02T00-13-09-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0f83d-b8c0-7631-bc2a-3888f457a5f4.jsonl)
- [rollout-2026-10-02T00-13-09-01a0f83d-b98b-79c2-b3ab-dd97fc580185.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/10/02/rollout-2026-10-02T00-13-09-01a0f83d-b98b-79c2-b3ab-dd97fc580185.jsonl)
- [rollout-2026-10-02T07-04-17-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0f9b6-2060-7890-b9b5-0ee0cb5fa7b9.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/10/02/rollout-2026-10-02T07-04-17-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0f9b6-2060-7890-b9b5-0ee0cb5fa7b9.jsonl)
- [rollout-2026-10-02T07-04-18-01a0f9b6-216f-7ae0-b3a5-b5edaa3d8ee5.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/10/02/rollout-2026-10-02T07-04-18-01a0f9b6-216f-7ae0-b3a5-b5edaa3d8ee5.jsonl)
- [rollout-2026-10-02T14-28-35-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0fb4c-e3ec-7a31-935f-93b739bf6aa3.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/10/02/rollout-2026-10-02T14-28-35-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0fb4c-e3ec-7a31-935f-93b739bf6aa3.jsonl)
- [rollout-2026-10-02T14-28-35-01a0fb4c-e4c1-7263-94d5-2eb22f6495db.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/10/02/rollout-2026-10-02T14-28-35-01a0fb4c-e4c1-7263-94d5-2eb22f6495db.jsonl)
- [rollout-2026-10-02T17-50-24-01a0fc05-a73d-7a40-baa2-b4ed83fc5032.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/10/02/rollout-2026-10-02T17-50-24-01a0fc05-a73d-7a40-baa2-b4ed83fc5032.jsonl)
- [rollout-2026-10-02T18-20-17-01a0fc21-04fe-7d00-8f53-8219bf410e3e.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/10/02/rollout-2026-10-02T18-20-17-01a0fc21-04fe-7d00-8f53-8219bf410e3e.jsonl)
- [rollout-2026-10-02T19-24-29-01a0fc5b-cb45-7940-874e-e249cfe24839.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/10/02/rollout-2026-10-02T19-24-29-01a0fc5b-cb45-7940-874e-e249cfe24839.jsonl)
- [rollout-2026-10-02T22-28-12-01a0fd03-ffcd-7993-9b52-8fb0ba438480.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/10/02/rollout-2026-10-02T22-28-12-01a0fd03-ffcd-7993-9b52-8fb0ba438480.jsonl)
- [rollout-2026-10-03T03-14-51-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0fe0a-6e97-7df1-bab2-36ab08dbd296.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/10/03/rollout-2026-10-03T03-14-51-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a0fe0a-6e97-7df1-bab2-36ab08dbd296.jsonl)
- [rollout-2026-10-03T03-14-51-01a0fe0a-6f67-7782-ac06-d46db7f9868a.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/10/03/rollout-2026-10-03T03-14-51-01a0fe0a-6f67-7782-ac06-d46db7f9868a.jsonl)
- [rollout-2026-10-03T03-24-58-01a0fe13-b0f6-7c82-9d10-f2fd2305eeef.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/10/03/rollout-2026-10-03T03-24-58-01a0fe13-b0f6-7c82-9d10-f2fd2305eeef.jsonl)
- [rollout-2026-10-03T04-15-02-01a0fe41-882b-7f91-b160-4fab971cc6dd.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/10/03/rollout-2026-10-03T04-15-02-01a0fe41-882b-7f91-b160-4fab971cc6dd.jsonl)
- [rollout-2026-10-03T04-43-55-01a0fe5b-f81c-7b00-bfef-53087f59c1d0.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/10/03/rollout-2026-10-03T04-43-55-01a0fe5b-f81c-7b00-bfef-53087f59c1d0.jsonl)
- [rollout-2026-10-03T05-14-00-01a0fe77-829c-7660-a45a-2eb705e114d8.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/10/03/rollout-2026-10-03T05-14-00-01a0fe77-829c-7660-a45a-2eb705e114d8.jsonl)
- [rollout-2026-10-03T13-24-35-01a10038-a8a4-7750-92c2-8b92d07c7d71.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/10/03/rollout-2026-10-03T13-24-35-01a10038-a8a4-7750-92c2-8b92d07c7d71.jsonl)
- [rollout-2026-10-03T13-27-47-01a1003b-95df-7700-a91e-3bbf368371fa.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/10/03/rollout-2026-10-03T13-27-47-01a1003b-95df-7700-a91e-3bbf368371fa.jsonl)
- [rollout-2026-10-03T13-45-25-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a1004b-bcca-7241-9dd0-337c8a9db03a.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/10/03/rollout-2026-10-03T13-45-25-01a0abb1-af40-70c1-ba07-3f1e85571b60_01a1004b-bcca-7241-9dd0-337c8a9db03a.jsonl)
- [rollout-2026-10-03T13-45-26-01a1004b-bd82-7723-a3f8-aa60a7f094a2.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/10/03/rollout-2026-10-03T13-45-26-01a1004b-bd82-7723-a3f8-aa60a7f094a2.jsonl)
- [rollout-2026-10-04T15-30-32-01a105d2-54de-7d01-a1fd-a7cd8015fa4f.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/10/04/rollout-2026-10-04T15-30-32-01a105d2-54de-7d01-a1fd-a7cd8015fa4f.jsonl)
- [rollout-2026-10-04T15-31-28-01a105d3-2f94-72f3-9021-51cadece6206.jsonl](/Users/adrycallencatapang/.codex/sessions/2026/10/04/rollout-2026-10-04T15-31-28-01a105d3-2f94-72f3-9021-51cadece6206.jsonl)
