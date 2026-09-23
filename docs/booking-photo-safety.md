# Booking photo commit and replay safety

Photo bytes are staged durably in the upload queue before saving their pending
markers. The form does not await Storage upload. New staged photos wait for their
matching committed booking marker; observing the old photo during a slow save
must not discard the new bytes. Background uploads have a 30-second deadline and
retain failures for retry. Image preparation/local persistence and the booking
write still take time; this is not a promise of instant completion.

Direct and queued booking transactions compute `photo_cleanup_paths` from the
previous document and commit that intent with the replacement document. Paths
still referenced anywhere in status history are retained. Failed transactions
cannot create cleanup intent. Cleanup scheduling runs after acknowledgement;
normal booking hydration reschedules committed intents after interruption.

The cleanup worker transactionally verifies the intent and absence of references,
then records `photo_cleanup_claims` before deleting the Storage object. Updated
booking writers preserve claims and reject restoring a claimed path. This guards
against a concurrent save reintroducing a photo during deletion. Storage deletion
and acknowledgement are bounded and retryable; successful deletion removes the
pending intent, retaining the claim. Old clients must be upgraded to participate
in this protection. Previously deleted files are not restored by this change.

Tests in `test/booking_photo_commit_safety_test.dart` cover failed saves,
acknowledged replay, retained history references, claimed-path restoration, and
foreground completion while a background upload is held unresolved.
