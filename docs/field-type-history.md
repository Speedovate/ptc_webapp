# Field type history

Implemented scope: shared runtime flow text/email/phone/number inputs, and New/
Edit Chassis name and location. Existing specialized location/dropdown selectors
are unchanged. Eligible fields use stable field IDs; provisional field identities
are not mixed into permanent history. Waybill/delivery-form identifiers, reference
IDs, passwords, tokens, secrets, and PIN fields are excluded. Other unique fields
must be explicitly identified before enabling history for them.

Suggestions reuse the existing input/controller/formatters and do not submit or
validate the form themselves. The existing Firestore schema `options` list is
merged with local history; no remote read is made per keystroke. A 300 ms debounce,
10-option result limit, composition guard, generation check, and disposed timer
prevent excess work and stale results. Empty matches add no suggestion panel.

Only successful booking/workflow saves (including accepted durable offline saves)
and successful chassis-editor saves record history. Original action times and the
originating account are captured before save. History writes are separate and
best-effort: failures cannot change a successful business save into a failed one.
No booking schema, identity resolver, business queue, or validation is modified.
Local records are scoped by account and field, capped at 30 values per field and
500 per account, with case-insensitive deduplication. Selecting a suggestion applies
the same text formatter used by typing. No history write occurs on typing/cancel.

## Firestore history constraint

Automatic remote history storage is NOT enabled. The repository's Firestore rules
currently allow all reads and writes, and FirebaseAuthBridgeService has no session
implementation. A user-ID filter is not an authorization boundary. The pending
product decision is private per-account history versus shared non-sensitive
suggestions. Private Firestore history requires a secure authenticated access
boundary, which cannot be guaranteed by adding a narrower rule alongside the
existing allow-all rule. Existing configured field options already in Firestore
are supported without new collections, rules, functions, or deployments.

There is no migration/backfill of historical bookings. Local history starts after
this feature is enabled. This does not resolve the separately reported debug
hot-restart renderer/runtime failures. No production deployment was performed.
