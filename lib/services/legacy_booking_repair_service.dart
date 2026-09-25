import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:webapp/services/firestore_transaction_errors.dart';
import 'booking_id_resolver.dart';

/// Uses the existing authoritative booking snapshot. No listener, timer, or
/// collection-wide polling; each temporary document is attempted once/session.
class LegacyBookingRepairService {
  LegacyBookingRepairService({required FirebaseFirestore firestore})
    : _db = firestore;
  final FirebaseFirestore _db;
  final _attempted = <String>{};
  Future<void>? _running;
  static const maxPerSession = 256;

  bool hasCandidates(List<Map<String, dynamic>> documents) =>
      _attempted.length < maxPerSession &&
      documents.any(
        (d) =>
            BookingIdResolver.isTemporary(d['id']?.toString()) &&
            !_attempted.contains(d['id']),
      );

  Future<void> repairSnapshot(
    List<Map<String, dynamic>> documents, {
    void Function(String)? onResult,
  }) {
    if (_running != null) return _running!;
    final temporary = documents
        .where(
          (d) =>
              BookingIdResolver.isTemporary(d['id']?.toString()) &&
              !_attempted.contains(d['id']),
        )
        .toList();
    temporary.sort((left, right) {
      final a = DateTime.tryParse(left['created_at']?.toString() ?? '');
      final b = DateTime.tryParse(right['created_at']?.toString() ?? '');
      final byDate = a == null || b == null ? 0 : a.compareTo(b);
      return byDate != 0
          ? byDate
          : left['id'].toString().compareTo(right['id'].toString());
    });
    if (temporary.isEmpty || _attempted.length >= maxPerSession) {
      return Future.value();
    }
    return _running = _run(
      temporary,
      documents,
      onResult,
    ).whenComplete(() => _running = null);
  }

  Future<void> _run(
    List<Map<String, dynamic>> temporary,
    List<Map<String, dynamic>> all,
    void Function(String)? onResult,
  ) async {
    for (final document in temporary) {
      if (_attempted.length >= maxPerSession) break;
      final id = document['id'] as String;
      _attempted.add(id);
      try {
        final result = await _repair(id, all);
        onResult?.call('$id: $result');
      } catch (error) {
        // No self-retry. Keep source data; another session can retry a failed
        // network operation. Firestore retains transaction ownership.
        onResult?.call('$id: repair deferred ($error)');
      }
    }
  }

  Future<String> _repair(String id, List<Map<String, dynamic>> all) async {
    final sourceRef = _db.collection('bookings').doc(id);
    final reportRef = _db.collection('booking_id_repairs').doc(id);
    final prior = await reportRef.get(const GetOptions(source: Source.server));
    if (prior.exists && !_canRevisit(prior.data()!)) {
      return prior.data()?['status']?.toString() ?? 'needs_review';
    }
    final source = await sourceRef.get(const GetOptions(source: Source.server));
    if (!source.exists) return 'already_removed';
    final key = source.data()?['submission_key']?.toString();
    final matching = key == null || key.isEmpty
        ? <Map<String, dynamic>>[]
        : (await _db
                  .collection('bookings')
                  .where('submission_key', isEqualTo: key)
                  .limit(10)
                  .get(const GetOptions(source: Source.server)))
              .docs
              .map((d) => {...d.data(), 'id': d.id})
              .toList();
    final candidates = matching
        .where(
          (d) =>
              BookingIdResolver.isNumeric(d['id']?.toString()) &&
              key != null &&
              d['submission_key'] == key,
        )
        .map((d) => d['id'].toString())
        .toSet();
    // Read known reference collections only, and bound transaction size.
    final chassis = await _db
        .collection('chassis')
        .where('current_booking_id', isEqualTo: id)
        .limit(200)
        .get(const GetOptions(source: Source.server));
    final support = await _db
        .collection('support')
        .where('booking_id', isEqualTo: id)
        .limit(200)
        .get(const GetOptions(source: Source.server));
    // Reservations can exist before their booking document is written.
    final reserved = await _db
        .collection('manage_id')
        .where('resource_key', isEqualTo: 'bookings')
        .limit(1000)
        .get(const GetOptions(source: Source.server));
    final reservedIds = reserved.docs
        .map((doc) => doc.data()['document_id']?.toString())
        .toSet();
    final bootstrap =
        all
            .map((d) => int.tryParse(d['id']?.toString() ?? '') ?? 0)
            .fold<int>(0, max) +
        1;
    final result = await runTransactionWithOriginalErrors<String>(
      _db,
      (tx) async {
        final current = await tx.get(sourceRef);
        final existingReport = await tx.get(reportRef);
        if (existingReport.exists && !_canRevisit(existingReport.data()!)) {
          return existingReport.data()?['status']?.toString() ?? 'needs_review';
        }
        if (!current.exists) return 'already_removed';
        final original = current.data()!;
        String conflict(
          String reason, {
          String? target,
          Map<String, dynamic>? canonical,
        }) {
          tx.set(reportRef, {
            'status': 'needs_review',
            'allocation_policy_version': 2,
            'reason': reason,
            if (canonical != null)
              'differing_fields': {...original.keys, ...canonical.keys}
                  .where(
                    (field) =>
                        field != 'id' &&
                        field != 'updated_at' &&
                        !_equal(original[field], canonical[field]),
                  )
                  .toList(),
            'source_id': id,
            'target_id': target,
            'submission_key': key,
            'created_at': FieldValue.serverTimestamp(),
          });
          tx.set(reportRef.collection('snapshots').doc('source'), original);
          if (canonical != null) {
            tx.set(
              reportRef.collection('snapshots').doc('canonical'),
              canonical,
            );
          }
          return 'needs_review: $reason';
        }

        if (key == null ||
            key.isEmpty ||
            original['submission_key'] != key ||
            BookingIdResolver.temporaryId(key) != id) {
          return conflict('Missing or inconsistent submission identity');
        }
        if (original['id'] != null && original['id'].toString() != id) {
          return conflict('Source document ID and stored ID disagree');
        }
        if (!_equal(original, source.data())) {
          return conflict(
            'Source changed while preparing repair; review current data',
          );
        }
        if (matching.any(
          (document) =>
              document['id'] != id &&
              !BookingIdResolver.isNumeric(document['id']?.toString()),
        )) {
          return conflict(
            'Another nonnumeric booking shares this submission identity',
          );
        }
        if (matching.length >= 10) {
          return conflict('Too many bookings share this submission identity');
        }
        if (candidates.length > 1) {
          return conflict(
            'Multiple numeric bookings have the same submission key',
          );
        }
        if (chassis.docs.length >= 200 || support.docs.length >= 200) {
          return conflict('Reference count exceeds safe repair batch size');
        }
        final reservationRef = _db
            .collection('manage_id')
            .doc(BookingIdResolver.reservationId(key));
        final reservation = await tx.get(reservationRef);
        String? target = reservation.data()?['document_id']?.toString();
        if (reservation.exists &&
            (reservation.data()?['resource_key'] != 'bookings' ||
                reservation.data()?['submission_key'] != key ||
                !BookingIdResolver.isNumeric(target))) {
          return conflict('Inconsistent ID reservation');
        }
        if (target != null &&
            candidates.isNotEmpty &&
            !candidates.contains(target)) {
          return conflict('Reservation and numeric booking disagree');
        }
        target ??= candidates.isEmpty ? null : candidates.single;
        final counterRef = _db
            .collection('manage_count')
            .doc('bookings_counter');
        final counter = await tx.get(counterRef);
        var allocating = target == null;
        String? splitKey;
        DocumentSnapshot<Map<String, dynamic>>? preservedCanonical;
        DocumentReference<Map<String, dynamic>>? splitReservationRef;
        if (reserved.docs.length >= 1000) {
          return conflict('Reservation count exceeds safe allocation limit');
        }
        if (allocating) {
          var next = max(
            bootstrap,
            int.tryParse(counter.data()?['next_id']?.toString() ?? '') ?? 1,
          );
          // Bound reads on corrupted/stale counters.
          var skips = 0;
          while (reservedIds.contains('$next') ||
              (await tx.get(_db.collection('bookings').doc('$next'))).exists) {
            if (++skips > 100) {
              return conflict('Unable to allocate within safe collision limit');
            }
            next++;
          }
          target = '$next';
        }
        var targetRef = _db.collection('bookings').doc(target);
        var canonical = await tx.get(targetRef);
        if (!allocating && !canonical.exists) {
          return conflict(
            'Reserved numeric booking is missing',
            target: target,
          );
        }
        if (canonical.exists && canonical.data()?['id']?.toString() != target) {
          return conflict(
            'Canonical document ID and stored ID disagree',
            target: target,
          );
        }
        if (canonical.exists &&
            (canonical.data()?['submission_key'] != key ||
                !_sameContent(original, canonical.data()!))) {
          // Preserve both versions under independent identities. The occupied
          // document and its reservation are never changed by this migration.
          preservedCanonical = canonical;
          splitKey = 'booking_split_$id';
          splitReservationRef = _db
              .collection('manage_id')
              .doc(BookingIdResolver.reservationId(splitKey));
          if ((await tx.get(splitReservationRef)).exists) {
            return conflict('Separate booking reservation already exists');
          }
          var next = max(
            bootstrap,
            int.tryParse(counter.data()?['next_id']?.toString() ?? '') ?? 1,
          );
          var skips = 0;
          while (reservedIds.contains('$next') ||
              (await tx.get(_db.collection('bookings').doc('$next'))).exists) {
            if (++skips > 100) {
              return conflict('Unable to allocate within safe collision limit');
            }
            next++;
          }
          target = '$next';
          targetRef = _db.collection('bookings').doc(target);
          canonical = await tx.get(targetRef);
          allocating = true;
        }
        // Read every referenced document again inside the transaction, before writes.
        final references = <DocumentSnapshot<Map<String, dynamic>>>[];
        for (final ref in [...chassis.docs, ...support.docs]) {
          references.add(await tx.get(ref.reference));
        }
        final chassisId = original['chassis_id']?.toString();
        DocumentSnapshot<Map<String, dynamic>>? assignedChassis;
        if (chassisId != null && chassisId.isNotEmpty) {
          assignedChassis = await tx.get(
            _db.collection('chassis').doc(chassisId),
          );
          final owner = assignedChassis
              .data()?['current_booking_id']
              ?.toString();
          if (owner != null && owner != id && owner != target) {
            return conflict(
              'Chassis belongs to another booking',
              target: target,
            );
          }
        }
        final linkedChassis = assignedChassis;
        if (linkedChassis != null &&
            linkedChassis.exists &&
            linkedChassis.data()?['current_booking_id'] == id &&
            !references.any(
              (ref) => ref.reference.path == linkedChassis.reference.path,
            )) {
          references.add(linkedChassis);
        }
        for (final ref in references) {
          if (ref.reference.parent.id == 'chassis' &&
              ref.exists &&
              ref.data()?['current_booking_id'] == id &&
              ref.id != chassisId) {
            return conflict(
              'Chassis reference disagrees with booking assignment',
              target: target,
            );
          }
        }
        // Preserve originals in separate documents (no destructive field merging).
        tx.set(
          reportRef
              .collection(splitKey == null ? 'snapshots' : 'split_snapshots')
              .doc('source'),
          original,
        );
        if (preservedCanonical != null) {
          tx.set(
            reportRef.collection('split_snapshots').doc('occupied'),
            preservedCanonical.data()!,
          );
        }
        if (canonical.exists) {
          tx.set(
            reportRef.collection('snapshots').doc('canonical'),
            canonical.data()!,
          );
        }
        if (!canonical.exists) {
          tx.set(targetRef, {
            ...original,
            'id': target,
            'submission_key': ?splitKey,
            if (splitKey != null) 'original_submission_key': key,
          });
        }
        for (final ref in references) {
          final field = ref.reference.parent.id == 'chassis'
              ? 'current_booking_id'
              : 'booking_id';
          if (ref.exists && ref.data()?[field] == id) {
            tx.update(ref.reference, {
              field: field == 'current_booking_id' ? int.parse(target) : target,
            });
          }
        }
        tx.set(splitReservationRef ?? reservationRef, {
          'kind': 'idempotency',
          'resource_key': 'bookings',
          'submission_key': splitKey ?? key,
          if (splitKey != null) 'original_submission_key': key,
          'document_id': target,
          'provisional_id': id,
          'legacy_repaired_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        if (allocating) {
          tx.set(counterRef, {
            'next_id': max(
              int.parse(target) + 1,
              int.tryParse(counter.data()?['next_id']?.toString() ?? '') ?? 1,
            ),
          }, SetOptions(merge: true));
        }
        tx.set(reportRef, {
          'status': 'repaired',
          'allocation_policy_version': 2,
          if (splitKey != null) 'resolution': 'keep_both_new_id',
          'target_submission_key': ?splitKey,
          if (preservedCanonical != null)
            'previous_target_id': preservedCanonical.id,
          'source_id': id,
          'target_id': target,
          'submission_key': key,
          'created_at': FieldValue.serverTimestamp(),
        });
        tx.delete(sourceRef);
        for (final collection in [
          'bookings',
          if (chassis.docs.isNotEmpty) 'chassis',
          if (support.docs.isNotEmpty) 'support',
        ]) {
          final now = DateTime.now().toUtc().toIso8601String();
          tx.set(_db.collection('manage_cache').doc(collection), {
            'version': now,
            'updated_at': now,
          }, SetOptions(merge: true));
        }
        return 'repaired -> $target';
      },
      maxAttempts: 3,
      timeout: const Duration(seconds: 30),
    );
    if (result.startsWith('repaired')) {
      BookingIdResolver(firestore: _db).invalidate(id);
    }
    return result;
  }

  static bool _canRevisit(Map<String, dynamic> report) =>
      report['status'] == 'needs_review' &&
      report['allocation_policy_version'] != 2 &&
      report['reason'] == 'Booking contents differ; do not choose by timestamp';

  static bool _sameContent(Map<String, dynamic> a, Map<String, dynamic> b) {
    Map<String, dynamic> content(Map<String, dynamic> d) => Map.of(d)
      ..remove('id')
      ..remove('updated_at')
      ..remove('local_sync_status')
      ..remove('queued_entry_id')
      ..remove('queued_created_at');
    return _equal(content(a), content(b));
  }

  static bool _equal(Object? a, Object? b) {
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every((k) => b.containsKey(k) && _equal(a[k], b[k]));
    }
    if (a is List && b is List) {
      return a.length == b.length &&
          List.generate(a.length, (i) => i).every((i) => _equal(a[i], b[i]));
    }
    return a == b;
  }
}
