import 'package:cloud_firestore/cloud_firestore.dart';
import 'booking_id_resolver.dart';

enum BookingConflictChoice { keepNumeric, useTemporary }

class BookingConflictPreview {
  BookingConflictPreview({
    required this.id,
    required this.report,
    required this.source,
    required this.canonical,
    required this.reservation,
    required this.references,
  });
  final String id;
  final Map<String, dynamic> report;
  final Map<String, dynamic>? source, canonical, reservation;
  final Map<String, Map<String, dynamic>?> references;
  String? get targetId => report['target_id']?.toString();
  String get reason => report['reason']?.toString() ?? 'Review required';
  bool get canUseTemporary {
    final from = canonical?['client_status'];
    final to = source?['client_status'];
    return (from == to && (to == 'assigned' || to == 'pending')) ||
        (from == 'assigned' &&
            to == 'cancelled' &&
            source?['chassis_id'] == null);
  }

  bool get canApply =>
      source != null &&
      canonical != null &&
      BookingIdResolver.isTemporary(id) &&
      BookingIdResolver.isNumeric(targetId) &&
      source!['submission_key'] != null &&
      BookingIdResolver.temporaryId(source!['submission_key'].toString()) ==
          id &&
      canonical!['submission_key'] == source!['submission_key'] &&
      reservation?['submission_key'] == source!['submission_key'] &&
      reservation?['resource_key'] == 'bookings' &&
      reservation?['document_id']?.toString() == targetId &&
      source!['id']?.toString() == id &&
      canonical!['id']?.toString() == targetId;
}

/// Explicit admin actions only. No subscriptions, startup reads, or retries.
class BookingConflictReviewService {
  BookingConflictReviewService({required FirebaseFirestore firestore})
    : _db = firestore;
  final FirebaseFirestore _db;
  Future<List<String>> listConflicts() async =>
      (await _db
              .collection('booking_id_repairs')
              .where('status', isEqualTo: 'needs_review')
              .limit(100)
              .get(const GetOptions(source: Source.server)))
          .docs
          .map((d) => d.id)
          .toList();

  Future<BookingConflictPreview> preview(String id) async {
    final report =
        (await _db
                .collection('booking_id_repairs')
                .doc(id)
                .get(const GetOptions(source: Source.server)))
            .data();
    if (report == null || report['status'] != 'needs_review') {
      throw StateError('This conflict is no longer pending. Refresh the list.');
    }
    final source =
        (await _db
                .collection('bookings')
                .doc(id)
                .get(const GetOptions(source: Source.server)))
            .data();
    final target = report['target_id']?.toString();
    final canonical = BookingIdResolver.isNumeric(target)
        ? (await _db
                  .collection('bookings')
                  .doc(target)
                  .get(const GetOptions(source: Source.server)))
              .data()
        : null;
    final key = source?['submission_key']?.toString();
    final reservation = key == null
        ? null
        : (await _db
                  .collection('manage_id')
                  .doc(BookingIdResolver.reservationId(key))
                  .get(const GetOptions(source: Source.server)))
              .data();
    final refs = <String, Map<String, dynamic>?>{};
    final chassis = await _db
        .collection('chassis')
        .where(
          'current_booking_id',
          whereIn: [
            id,
            if (BookingIdResolver.isNumeric(target)) ...[
              target,
              int.parse(target!),
            ],
          ],
        )
        .limit(200)
        .get(const GetOptions(source: Source.server));
    final support = await _db
        .collection('support')
        .where('booking_id', isEqualTo: id)
        .limit(200)
        .get(const GetOptions(source: Source.server));
    if (chassis.docs.length >= 200 || support.docs.length >= 200) {
      throw StateError(
        'Too many linked records for one safe reconciliation. No changes were made.',
      );
    }
    for (final doc in [...chassis.docs, ...support.docs]) {
      refs[doc.reference.path] = doc.data();
    }
    for (final doc in [source, canonical]) {
      final chassisId = doc?['chassis_id']?.toString();
      if (chassisId != null && chassisId.isNotEmpty) {
        final path = 'chassis/$chassisId';
        if (!refs.containsKey(path)) {
          refs[path] =
              (await _db.doc(path).get(const GetOptions(source: Source.server)))
                  .data();
        }
      }
    }
    return BookingConflictPreview(
      id: id,
      report: report,
      source: source,
      canonical: canonical,
      reservation: reservation,
      references: refs,
    );
  }

  Future<void> apply(
    BookingConflictPreview preview,
    BookingConflictChoice choice, {
    required String adminId,
  }) async {
    if (!preview.canApply) {
      throw StateError(
        'The booking identity cannot be verified. No changes were made.',
      );
    }
    if (choice == BookingConflictChoice.useTemporary &&
        !preview.canUseTemporary) {
      throw StateError(
        'This workflow transition requires a booking workflow review. No changes were made.',
      );
    }
    final target = preview.targetId!;
    final key = preview.source!['submission_key'].toString();
    await _db.runTransaction<void>(
      (tx) async {
        final actor = await tx.get(_db.collection('users').doc(adminId));
        if (actor.data()?['role'] != 'admin' ||
            actor.data()?['is_active'] == false) {
          throw StateError('An active admin account is required.');
        }
        final sourceRef = _db.collection('bookings').doc(preview.id);
        final targetRef = _db.collection('bookings').doc(target);
        final reportRef = _db.collection('booking_id_repairs').doc(preview.id);
        final reservationRef = _db
            .collection('manage_id')
            .doc(BookingIdResolver.reservationId(key));
        final source = await tx.get(sourceRef);
        final canonical = await tx.get(targetRef);
        final report = await tx.get(reportRef);
        final reservation = await tx.get(reservationRef);
        if (!same(source.data(), preview.source) ||
            !same(canonical.data(), preview.canonical) ||
            !same(report.data(), preview.report) ||
            !same(reservation.data(), preview.reservation)) {
          throw StateError(
            'Records changed since this comparison. Reload the comparison before applying.',
          );
        }
        final references = <String, Map<String, dynamic>?>{};
        for (final entry in preview.references.entries) {
          final current = await tx.get(_db.doc(entry.key));
          if (!same(current.data(), entry.value)) {
            throw StateError(
              'A linked assignment changed. Reload the comparison before applying.',
            );
          }
          references[entry.key] = current.data();
        }
        final chosen =
            Map<String, dynamic>.from(
                choice == BookingConflictChoice.keepNumeric
                    ? canonical.data()!
                    : source.data()!,
              )
              ..['id'] = target
              ..['created_at'] = canonical.data()!['created_at']
              ..remove('local_sync_status')
              ..remove('queued_entry_id')
              ..remove('queued_created_at');
        final chassisId = chosen['chassis_id']?.toString();
        final chosenPath = chassisId == null || chassisId.isEmpty
            ? null
            : 'chassis/$chassisId';
        if (chosenPath != null) {
          final chassis = references[chosenPath];
          final owner = chassis?['current_booking_id']?.toString();
          if (chassis == null ||
              (owner != null && owner != target && owner != preview.id)) {
            throw StateError(
              'The selected chassis is missing or belongs to another booking. No changes were made.',
            );
          }
        }
        final now = DateTime.now().toUtc().toIso8601String();
        tx.set(
          reportRef.collection('decision_snapshots').doc('source'),
          source.data()!,
        );
        tx.set(
          reportRef.collection('decision_snapshots').doc('canonical'),
          canonical.data()!,
        );
        for (final entry in references.entries) {
          final data = entry.value;
          if (data == null) continue;
          if (entry.key.startsWith('support/')) {
            if (data['booking_id'] == preview.id) {
              tx.update(_db.doc(entry.key), {'booking_id': target});
            }
            continue;
          }
          final owner = data['current_booking_id']?.toString();
          if (entry.key == chosenPath) {
            if (choice == BookingConflictChoice.useTemporary ||
                owner == preview.id) {
              tx.update(_db.doc(entry.key), {
                'current_booking_id': int.parse(target),
                'current_driver_id': chosen['driver_id'] == null
                    ? FieldValue.delete()
                    : (int.tryParse(chosen['driver_id'].toString()) ??
                          chosen['driver_id']),
                'updated_at': now,
              });
            }
          } else if (owner == preview.id ||
              (owner == target &&
                  choice == BookingConflictChoice.useTemporary)) {
            tx.update(_db.doc(entry.key), {
              'current_booking_id': FieldValue.delete(),
              'current_driver_id': FieldValue.delete(),
              'current_status': 'ready',
              'updated_at': now,
            });
          }
        }
        if (choice == BookingConflictChoice.useTemporary) {
          tx.set(targetRef, {...chosen, 'updated_at': now});
        }
        tx.update(reservationRef, {
          'provisional_id': preview.id,
          'reconciled_at': now,
        });
        tx.update(reportRef, {
          'status': 'repaired',
          'resolution': choice.name,
          'resolved_by': adminId,
          'resolved_at': now,
        });
        tx.delete(sourceRef);
        for (final name in ['bookings', 'chassis', 'support']) {
          tx.set(_db.collection('manage_cache').doc(name), {
            'version': now,
            'updated_at': now,
          }, SetOptions(merge: true));
        }
      },
      maxAttempts: 3,
      timeout: const Duration(seconds: 30),
    );
    BookingIdResolver(firestore: _db).invalidate(preview.id);
  }

  static bool same(Object? a, Object? b) {
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every((k) => b.containsKey(k) && same(a[k], b[k]));
    }
    if (a is List && b is List) {
      return a.length == b.length &&
          List.generate(a.length, (i) => i).every((i) => same(a[i], b[i]));
    }
    return a == b;
  }
}
