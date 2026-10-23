import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:webapp/repositories/local/booking_storage_backend.dart';
import 'booking_id_resolver.dart';
import 'photo_storage_service.dart';
import 'sync_error_log_service.dart';
import 'firestore_transaction_errors.dart';

class OrphanPhotoReview {
  OrphanPhotoReview._(
    this.owner,
    this.entryId,
    this.bookingId,
    this.fileName,
    this.originalActionAt,
    this.preview,
    this.clientId,
    this.bookingStatus,
    this.bookingDescription,
    this._sourceDigest,
    this._serverDigest,
  );
  final String owner, entryId, bookingId, fileName, clientId, bookingStatus;
  final String bookingDescription;
  final String originalActionAt, _sourceDigest, _serverDigest;
  final Uint8List preview;
}

class OrphanPhotoSource {
  OrphanPhotoSource._(this.fileName, this.originalActionAt, this.preview);
  final String fileName, originalActionAt;
  final Uint8List preview;
}

/// Evidence-based recovery with automatic preservation and optional reviewed
/// association. Original data remains archived after verified server receipt.
class OrphanPhotoRecoveryService {
  static final _unassignedProbes = Expando<Map<String, DateTime>>();
  OrphanPhotoRecoveryService({
    required this.backend,
    required this.firestore,
    required this.photos,
    required this.requireOwner,
    required this.hasPending,
    required this.withQueueLock,
    required this.onResolved,
  });
  final BookingStorageBackend backend;
  final FirebaseFirestore firestore;
  final PhotoStorageService photos;
  final Future<void> Function(String owner) requireOwner;
  final Future<bool?> Function(String bookingId, String owner) hasPending;
  final Future<void> Function(Future<void> Function()) withQueueLock;
  final Future<void> Function(String owner, String entryId) onResolved;
  static String queueKey(String owner) =>
      'booking_pending_upload_queue_v1::$owner';
  static String archiveKey(String owner, String entryId) =>
      'booking_photo_recovery_archive_v1::$owner::$entryId';
  static String originalEvidenceKey(String owner, String entryId) =>
      'booking_photo_original_evidence_v1::$owner::$entryId';
  static String receiptId(String owner, String entryId) => '${owner}_$entryId';
  static String unassignedIndexKey(String owner) =>
      'booking_unassigned_photo_recovery_v1::$owner';

  /// Retire a proven orphan only after its original bytes and timestamp are
  /// archived locally and in a verified server recovery receipt. This does not
  /// create or mark a booking as synced.
  Future<void> archiveUnassigned({
    required String owner,
    required String entryId,
  }) => withQueueLock(() async {
    final row = await _source(owner, entryId);
    if (!'${row['booking_id']}'.startsWith('offline_booking_${owner}_')) {
      throw StateError('The original photo owner cannot be verified.');
    }
    await _verifyOriginalMissing(row);
    final bytes = base64Decode('${row['bytes_base64']}');
    if (bytes.isEmpty || bytes.length != row['size']) {
      throw StateError('The original photo bytes are incomplete.');
    }
    final key = archiveKey(owner, entryId);
    final saved = await backend.readStringList(key);
    final original = await backend.readStringList(
      originalEvidenceKey(owner, entryId),
    );
    if (original.isEmpty) {
      // The recovery-archive write may itself fail. Save the first failure
      // evidence separately before a retry can replace the active diagnostics.
      await _saveArchive(originalEvidenceKey(owner, entryId), row);
    }
    final archive = saved.isEmpty
        ? <String, dynamic>{
            'schema_version': 1,
            'original_entry': original.isEmpty
                ? row
                : jsonDecode(original.single),
            'archived_at': DateTime.now().toUtc().toIso8601String(),
          }
        : Map<String, dynamic>.from(jsonDecode(saved.single));
    final digest = _sourceHash(row);
    if (_sourceHash(Map<String, dynamic>.from(archive['original_entry'])) !=
        digest) {
      throw StateError(
        'The original recovery archive does not match this photo.',
      );
    }
    archive['latest_error_metadata'] = {
      for (final field in row.keys)
        if (field != 'bytes_base64') field: row[field],
    };
    archive['state'] ??= 'prepared_unassigned';
    await _saveArchive(key, archive);
    final bundle = <String, dynamic>{
      'schema_version': 1,
      'owner_id': owner,
      'queue_entry_id': entryId,
      'source_digest': digest,
      'photo_sha256': sha256.convert(bytes).toString(),
      'archived_at': archive['archived_at'],
      'original_entry': {
        ...Map<String, dynamic>.from(archive['original_entry']),
        for (final field in ['last_error', 'error_diagnostics'])
          if (archive['original_entry'][field] is String)
            field: SyncErrorLogService.sanitize(
              archive['original_entry'][field],
            ),
      },
    };
    final bundleHash = sha256
        .convert(utf8.encode(jsonEncode(bundle)))
        .toString();
    var uploaded = archive['unassigned_bundle'] is Map
        ? Map<String, dynamic>.from(archive['unassigned_bundle'])
        : null;
    if (uploaded == null || uploaded['sha256'] != bundleHash) {
      uploaded = await photos.uploadBookingRecoveryBundle(
        owner: owner,
        entryId: entryId,
        bundle: bundle,
      );
    }
    if (uploaded['sha256'] != bundleHash ||
        !'${uploaded['storage_path']}'.startsWith(
          'booking_photo_recoveries/$owner/$entryId/',
        ) ||
        Uri.tryParse('${uploaded['download_url']}')?.scheme != 'https') {
      throw StateError(
        'The server recovery bundle could not be verified. The original remains queued.',
      );
    }
    archive['unassigned_bundle'] = uploaded;
    await _saveArchive(key, archive);
    // Repeat fresh identity checks after the upload. A connection failure never
    // authorizes completion and a booking which appeared meanwhile wins.
    await _verifyOriginalMissing(row);
    await requireOwner(owner);
    final receipt = firestore
        .collection('booking_photo_recoveries')
        .doc(receiptId(owner, entryId));
    final keyForBooking = '${row['booking_id']}'.substring('offline_'.length);
    await runTransactionWithOriginalErrors<void>(firestore, (tx) async {
      final existing = await tx.get(receipt);
      final repair = await tx.get(
        firestore.collection('booking_id_repairs').doc('${row['booking_id']}'),
      );
      final reservation = await tx.get(
        firestore
            .collection('manage_id')
            .doc(BookingIdResolver.reservationId(keyForBooking)),
      );
      if (repair.exists || reservation.exists) {
        throw StateError(
          'The original booking gained an identity. Its queued photo was preserved for normal sync.',
        );
      }
      if (existing.exists) {
        if (existing.data()?['owner_id'] != owner ||
            existing.data()?['source_digest'] != digest ||
            existing.data()?['state'] != 'preserved_unassigned' ||
            existing.data()?['recovery_bundle']?['sha256'] != bundleHash) {
          throw StateError(
            'An existing recovery receipt needs verification. The original remains queued.',
          );
        }
        return;
      }
      tx.set(receipt, {
        'schema_version': 1,
        'state': 'preserved_unassigned',
        'owner_id': owner,
        'queue_entry_id': entryId,
        'source_digest': digest,
        'photo_sha256': sha256.convert(bytes).toString(),
        'original_booking_id': row['booking_id'],
        'original_status_key': row['status_key'],
        'original_action_at': row['created_at'],
        'original_file_name': row['file_name'],
        'original_error': _excerpt(
          '${archive['original_entry']['last_error'] ?? ''}',
        ),
        'original_diagnostics': _excerpt(
          '${archive['original_entry']['error_diagnostics'] ?? ''}',
        ),
        'recovery_bundle': uploaded,
        'preserved_at': archive['archived_at'],
        'booking_id': null,
      });
    });
    // The index keeps a late exact booking identity discoverable even after
    // the no-longer-actionable upload is removed from the active queue.
    final index = await backend.readStringList(unassignedIndexKey(owner));
    if (!index.contains(entryId)) {
      await backend.writeStringList(unassignedIndexKey(owner), [
        ...index,
        entryId,
      ]);
    }
    archive['state'] = 'retired_unassigned';
    await _saveArchive(key, archive);
    final active = await backend.readStringList(queueKey(owner));
    final retained = <String>[];
    var removed = 0;
    for (final raw in active) {
      final current = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      if (current['id'] != entryId) {
        retained.add(raw);
        continue;
      }
      if (_sourceHash(current) != digest) {
        throw StateError('The queued photo changed after its backup.');
      }
      removed++;
    }
    if (removed != 1) {
      throw StateError('The original photo queue changed during archival.');
    }
    await backend.writeStringList(queueKey(owner), retained);
    if ((await backend.readStringList(
      queueKey(owner),
    )).any((raw) => (jsonDecode(raw) as Map)['id'] == entryId)) {
      throw StateError('The archived photo action could not be retired.');
    }
  });

  /// Restore only legacy archives that still represent active pending work.
  /// New retired archives keep their bytes and index without a queued action.
  Future<void> restoreUnassignedPending(String owner) =>
      withQueueLock(() async {
        await requireOwner(owner);
        final index = await backend.readStringList(unassignedIndexKey(owner));
        // Browser storage returns a fixed-length list; restoration needs its
        // own growable copy before appending archived entries.
        final rows = [...await backend.readStringList(queueKey(owner))];
        final ids = rows.map((raw) => (jsonDecode(raw) as Map)['id']).toSet();
        var changed = false;
        for (final id in index) {
          if (ids.contains(id)) continue;
          final saved = await backend.readStringList(archiveKey(owner, id));
          if (saved.length != 1) continue;
          final archive = Map<String, dynamic>.from(jsonDecode(saved.single));
          if (archive['state'] != 'preserved_unassigned') continue;
          final original = Map<String, dynamic>.from(archive['original_entry']);
          if (original['id'] != id ||
              !'${original['booking_id']}'.startsWith(
                'offline_booking_${owner}_',
              )) {
            continue;
          }
          final bytes = base64Decode('${original['bytes_base64']}');
          if (bytes.isEmpty || bytes.length != original['size']) continue;
          rows.add(jsonEncode(original));
          ids.add(id);
          changed = true;
        }
        if (changed) await backend.writeStringList(queueKey(owner), rows);
      });

  Future<void> reconcileUnassigned(
    String owner,
    Future<Map<String, dynamic>?> Function(
      Map<String, dynamic> original,
      Map<String, dynamic> archive,
    )
    tryAttach, {
    bool force = false,
  }) async {
    final index = await backend.readStringList(unassignedIndexKey(owner));
    final probes = _unassignedProbes[firestore] ??= <String, DateTime>{};
    final prefix = '$owner::';
    probes.removeWhere(
      (key, _) =>
          key.startsWith(prefix) &&
          !index.contains(key.substring(prefix.length)),
    );
    final ready = index
        .where(
          (id) =>
              force || probes['$prefix$id']?.isAfter(DateTime.now()) != true,
        )
        .take(4)
        .toList();
    for (final id in ready) {
      probes['$prefix$id'] = DateTime.now().add(const Duration(minutes: 15));
      try {
        final rows = await backend.readStringList(archiveKey(owner, id));
        if (rows.length != 1) continue;
        final archive = Map<String, dynamic>.from(jsonDecode(rows.single));
        final original = Map<String, dynamic>.from(archive['original_entry']);
        final ref = firestore
            .collection('booking_photo_recoveries')
            .doc(receiptId(owner, id));
        final receipt = (await ref.get(
          const GetOptions(source: Source.server),
        )).data();
        if (receipt?['owner_id'] != owner ||
            receipt?['source_digest'] != _sourceHash(original) ||
            !const {
              'preserved_unassigned',
              'associated',
            }.contains(receipt?['state'])) {
          continue;
        }
        final attached = await tryAttach(original, archive);
        if (attached == null) continue;
        await ref.update({
          'state': 'associated',
          ...attached,
          'associated_at': DateTime.now().toUtc().toIso8601String(),
        });
        archive.addAll({'state': 'associated', ...attached});
        await _saveArchive(archiveKey(owner, id), archive);
        await withQueueLock(() async {
          final pending = await backend.readStringList(queueKey(owner));
          final retained = <String>[];
          for (final raw in pending) {
            final current = Map<String, dynamic>.from(jsonDecode(raw));
            if (current['id'] == id) {
              if (_sourceHash(current) != _sourceHash(original)) {
                throw StateError('A newer local photo remains pending.');
              }
            } else {
              retained.add(raw);
            }
          }
          await backend.writeStringList(queueKey(owner), retained);
          final latest = await backend.readStringList(
            unassignedIndexKey(owner),
          );
          await backend.writeStringList(
            unassignedIndexKey(owner),
            latest.where((entry) => entry != id).toList(),
          );
          probes.remove('$prefix$id');
        });
        await onResolved(owner, id);
      } catch (_) {
        // The original photo is already verified on the server. An unavailable
        // association keeps its acknowledged index and retries on existing ticks.
      }
    }
  }

  Future<void> _saveArchive(String key, Map<String, dynamic> archive) async {
    final encoded = jsonEncode(archive);
    await backend.writeStringList(key, [encoded]);
    final saved = await backend.readStringList(key);
    if (saved.length != 1 || saved.single != encoded) {
      throw StateError(
        'The original archive could not be verified. The queued photo was preserved.',
      );
    }
  }

  Future<OrphanPhotoSource> readSource({
    required String owner,
    required String entryId,
  }) async {
    final row = await _source(owner, entryId, allowRetired: true);
    final bytes = base64Decode('${row['bytes_base64']}');
    if (bytes.isEmpty || bytes.length != row['size']) {
      throw StateError(
        'The saved photo is incomplete. The original entry remains saved.',
      );
    }
    return OrphanPhotoSource._(
      '${row['file_name']}',
      '${row['created_at']}',
      bytes,
    );
  }

  Future<Map<String, dynamic>> _source(
    String owner,
    String id, {
    bool allowRetired = false,
  }) async {
    await requireOwner(owner);
    await backend.initialize();
    final matches = (await backend.readStringList(queueKey(owner)))
        .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
        .where((row) => row['id'] == id)
        .toList();
    if (matches.isEmpty && allowRetired) {
      final saved = await backend.readStringList(archiveKey(owner, id));
      if (saved.length == 1) {
        final archive = Map<String, dynamic>.from(jsonDecode(saved.single));
        if (archive['state'] == 'retired_unassigned' &&
            archive['original_entry'] is Map) {
          matches.add(
            Map<String, dynamic>.from(archive['original_entry'] as Map),
          );
        }
      }
    }
    if (matches.length != 1) {
      throw StateError('This saved photo changed. Reopen the queue.');
    }
    final row = matches.single;
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id) ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch('${row['field_key']}') ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch('${row['status_key']}')) {
      throw StateError(
        'The saved photo identity needs review. The original was preserved.',
      );
    }
    if (!BookingIdResolver.isTemporary(row['booking_id']?.toString()) ||
        row['wait_reason'] != 'temporary_booking_id' ||
        await hasPending('${row['booking_id']}', owner) != false) {
      throw StateError(
        'This photo still has a booking dependency. Retry its original booking first.',
      );
    }
    return row;
  }

  String _sourceHash(Map<String, dynamic> row) => _hash({
    for (final key in [
      'id',
      'booking_id',
      'status_key',
      'field_key',
      'file_name',
      'mime_type',
      'size',
      'bytes_base64',
      'created_at',
    ])
      key: row[key],
  });
  Future<void> _verifyOriginalMissing(Map<String, dynamic> row) async {
    final id = '${row['booking_id']}';
    final key = id.substring('offline_'.length);
    final parts = RegExp(
      r'^booking_([0-9]+)_([0-9]+)_([0-9]+)_([0-9]+)$',
    ).firstMatch(key);
    if (parts == null) {
      throw StateError('The original booking identity needs review.');
    }
    // Fresh evidence is required before a user-selected recovery can bypass
    // the original dependency. A failed read never means the source is absent.
    final found = await BookingIdResolver(firestore: firestore)
        .resolveRecoveryEvidence(id, 'manual_photo_${row['id']}', () async {
          final repair = await firestore
              .collection('booking_id_repairs')
              .doc(id)
              .get(const GetOptions(source: Source.server));
          final reserved = await firestore
              .collection('manage_id')
              .doc(BookingIdResolver.reservationId(key))
              .get(const GetOptions(source: Source.server));
          final originals = await firestore
              .collection('bookings')
              .where('submission_key', isEqualTo: key)
              .limit(1)
              .get(const GetOptions(source: Source.server));
          final markers = await firestore
              .collection('bookings')
              .where(
                'status_outputs.${row['status_key']}.fields.${row['field_key']}.pending_upload_id',
                isEqualTo: row['id'],
              )
              .limit(1)
              .get(const GetOptions(source: Source.server));
          if (repair.exists ||
              reserved.exists ||
              originals.docs.isNotEmpty ||
              markers.docs.isNotEmpty) {
            throw StateError(
              'The original booking has server evidence. Retry normal sync before recovering this photo.',
            );
          }
          return 'verified_missing';
        });
    if (found != 'verified_missing') {
      throw StateError(
        'Could not verify the original booking yet. Keep the photo and retry later.',
      );
    }
  }

  Future<OrphanPhotoReview> review({
    required String owner,
    required String entryId,
    required String bookingId,
  }) async {
    if (!BookingIdResolver.isNumeric(bookingId)) {
      throw StateError('Enter an existing booking number.');
    }
    final row = await _source(owner, entryId, allowRetired: true);
    await _verifyOriginalMissing(row);
    final previousReceipt = await firestore
        .collection('booking_photo_recoveries')
        .doc(receiptId(owner, entryId))
        .get(const GetOptions(source: Source.server));
    if (previousReceipt.exists &&
        (previousReceipt.data()?['booking_id'] != bookingId ||
            previousReceipt.data()?['source_digest'] != _sourceHash(row) ||
            previousReceipt.data()?['owner_id'] != owner)) {
      throw StateError(
        'This photo already has a recovery receipt. Review its recorded booking ${previousReceipt.data()?['booking_id']} to finish confirmation.',
      );
    }
    if (await hasPending(bookingId, owner) != false) {
      throw StateError('Sync the destination booking changes before recovery.');
    }
    final target = await firestore
        .collection('bookings')
        .doc(bookingId)
        .get(const GetOptions(source: Source.server));
    final data = target.data();
    final client = RegExp(
      r'^offline_booking_[0-9]+_([0-9]+)_[0-9]+_[0-9]+$',
    ).firstMatch('${row['booking_id']}')?[1];
    if (data == null ||
        data['id'] != bookingId ||
        data['client_id'] != client ||
        data['status_outputs'] is! Map) {
      throw StateError('Choose an existing booking for the original client.');
    }
    final bytes = base64Decode('${row['bytes_base64']}');
    if (bytes.isEmpty || bytes.length != row['size']) {
      throw StateError(
        'The saved photo is incomplete. Its original entry was preserved.',
      );
    }
    return OrphanPhotoReview._(
      owner,
      entryId,
      bookingId,
      '${row['file_name']}',
      '${row['created_at']}',
      bytes,
      '${data['client_id']}',
      '${data['client_status']}',
      _bookingDescription(data),
      _sourceHash(row),
      _hash(data),
    );
  }

  Future<void> apply(OrphanPhotoReview review) => withQueueLock(() async {
    final row = await _source(review.owner, review.entryId, allowRetired: true);
    if (_sourceHash(row) != review._sourceDigest) {
      throw StateError('The saved photo changed. Review it again.');
    }
    await _verifyOriginalMissing(row);
    final receipt = firestore
        .collection('booking_photo_recoveries')
        .doc(receiptId(review.owner, review.entryId));
    final previousReceipt = await receipt.get(
      const GetOptions(source: Source.server),
    );
    if (previousReceipt.exists &&
        (previousReceipt.data()?['booking_id'] != review.bookingId ||
            previousReceipt.data()?['source_digest'] != review._sourceDigest ||
            previousReceipt.data()?['owner_id'] != review.owner)) {
      throw StateError(
        'This photo already has a recovery receipt for a different booking. The original was preserved.',
      );
    }
    if (await hasPending(review.bookingId, review.owner) != false) {
      throw StateError('The destination has queued edits. Sync them first.');
    }
    final key = archiveKey(review.owner, review.entryId);
    final prior = await backend.readStringList(key);
    final originalEvidence = await backend.readStringList(
      originalEvidenceKey(review.owner, review.entryId),
    );
    final archive = prior.isEmpty
        ? <String, dynamic>{
            'schema_version': 1,
            'original_entry': originalEvidence.isEmpty
                ? row
                : jsonDecode(originalEvidence.single),
            'archived_at': DateTime.now().toUtc().toIso8601String(),
          }
        : Map<String, dynamic>.from(jsonDecode(prior.single));
    if (_sourceHash(Map<String, dynamic>.from(archive['original_entry'])) !=
        review._sourceDigest) {
      throw StateError(
        'The original recovery archive does not match this photo.',
      );
    }
    // This write must succeed before any remote upload or queue completion.
    archive['latest_error_metadata'] = {
      for (final field in row.keys)
        if (field != 'bytes_base64') field: row[field],
    };
    archive['state'] ??= 'prepared';
    archive['last_reviewed_destination_booking_id'] = review.bookingId;
    archive['last_reviewed_at'] = DateTime.now().toUtc().toIso8601String();
    await _saveArchive(key, archive);
    final historyKey = 'photo__${review.entryId}';
    Map<String, dynamic>? uploaded;
    if (previousReceipt.data()?['uploaded_photo'] is Map) {
      uploaded = Map<String, dynamic>.from(
        previousReceipt.data()!['uploaded_photo'],
      );
    }
    if (uploaded == null &&
        archive['destination_booking_id'] == review.bookingId &&
        archive['uploaded_photo'] is Map) {
      uploaded = Map<String, dynamic>.from(archive['uploaded_photo']);
    }
    uploaded ??= await photos.uploadBookingPhoto(
      bytes: base64Decode('${row['bytes_base64']}'),
      bookingId: review.bookingId,
      statusKey: historyKey,
      fieldKey: '${row['field_key']}',
      fileName: '${row['file_name']}',
      mimeType: row['mime_type']?.toString(),
      size: row['size'] as int?,
    );
    if (!'${uploaded['storage_path'] ?? ''}'.startsWith(
          'bookings/${review.bookingId}/status_outputs/$historyKey/${row['field_key']}/',
        ) ||
        Uri.tryParse('${uploaded['download_url'] ?? ''}')?.scheme != 'https') {
      throw StateError(
        'The uploaded photo could not be verified. The original remains archived and queued.',
      );
    }
    archive.addAll({
      'destination_booking_id': review.bookingId,
      'uploaded_photo': uploaded,
      'state': 'uploaded_awaiting_commit',
    });
    await _saveArchive(key, archive);
    await requireOwner(review.owner);
    final target = firestore.collection('bookings').doc(review.bookingId);
    final recoveredAt = DateTime.now().toUtc().toIso8601String();
    var confirmedRecoveredAt = recoveredAt;
    await runTransactionWithOriginalErrors<void>(firestore, (tx) async {
      confirmedRecoveredAt = recoveredAt;
      final savedReceipt = await tx.get(receipt);
      final snapshot = await tx.get(target);
      await requireOwner(review.owner);
      final data = snapshot.data();
      final history = data?['status_outputs'] is Map
          ? data!['status_outputs'][historyKey]
          : null;
      if (savedReceipt.exists) {
        if (savedReceipt.data()?['owner_id'] != review.owner ||
            savedReceipt.data()?['source_digest'] != review._sourceDigest ||
            savedReceipt.data()?['booking_id'] != review.bookingId ||
            history is! Map ||
            history['upload_id'] != review.entryId ||
            history['original_booking_id'] != row['booking_id'] ||
            _hash(history['fields']) !=
                _hash({
                  '${row['field_key']}': savedReceipt.data()?['uploaded_photo'],
                })) {
          throw StateError(
            'Recovery receipt or photo history changed. The local original was preserved.',
          );
        }
        confirmedRecoveredAt =
            savedReceipt.data()?['recovered_at']?.toString() ?? recoveredAt;
        return;
      }
      if (data == null ||
          _hash(data) != review._serverDigest ||
          history != null) {
        throw StateError(
          'The booking changed since review. Review it again; the original photo remains saved.',
        );
      }
      tx.update(target, {
        'status_outputs.$historyKey': {
          'status_key': 'photo',
          'submitted_at': row['created_at'],
          'submitted_by': review.owner,
          'recovered_photo': true,
          'original_booking_id': row['booking_id'],
          'original_status_key': row['status_key'],
          'upload_id': review.entryId,
          'recovered_at': recoveredAt,
          'fields': {'${row['field_key']}': uploaded},
        },
      });
      tx.set(receipt, {
        'schema_version': 1,
        'owner_id': review.owner,
        'queue_entry_id': review.entryId,
        'source_digest': review._sourceDigest,
        'photo_sha256': sha256
            .convert(base64Decode('${row['bytes_base64']}'))
            .toString(),
        'original_booking_id': row['booking_id'],
        'original_status_key': row['status_key'],
        'original_action_at': row['created_at'],
        'original_retry_count': archive['original_entry']['retry_count'],
        'original_wait_count': archive['original_entry']['wait_count'],
        'original_failed_at': RegExp(r'Failed at \(UTC\): ([^\n]+)')
            .firstMatch(
              '${archive['original_entry']['error_diagnostics'] ?? ''}',
            )
            ?.group(1),
        'original_error': SyncErrorLogService.sanitize(
          '${archive['original_entry']['last_error'] ?? ''}',
        ),
        'original_diagnostics': _excerpt(
          '${archive['original_entry']['error_diagnostics'] ?? ''}',
        ),
        'booking_id': review.bookingId,
        'uploaded_photo': uploaded,
        'recovered_at': recoveredAt,
      });
    });
    archive.addAll({
      'state': 'committed',
      'recovered_at': confirmedRecoveredAt,
      'completion_confirmed_at': DateTime.now().toUtc().toIso8601String(),
      'receipt_id': receipt.id,
    });
    await _saveArchive(key, archive);
    final latest = await backend.readStringList(queueKey(review.owner));
    final retained = <String>[];
    for (final raw in latest) {
      final current = Map<String, dynamic>.from(jsonDecode(raw));
      if (current['id'] == review.entryId) {
        if (_sourceHash(current) != review._sourceDigest) {
          throw StateError(
            'A newer local photo was preserved. Reopen the queue.',
          );
        }
      } else {
        retained.add(raw);
      }
    }
    await backend.writeStringList(queueKey(review.owner), retained);
    await onResolved(review.owner, review.entryId);
  });
}

String _bookingDescription(Map<String, dynamic> data) {
  final outputs = data['status_outputs'];
  if (outputs is! Map) return '';
  final originals = outputs.values
      .whereType<Map>()
      .where((event) => event['status_key'] == 'book' && event['fields'] is Map)
      .toList();
  if (originals.length != 1) return '';
  final fields = originals.single['fields'] as Map;
  return [
    '${fields['representative_name'] ?? ''}',
    '${fields['van_number'] ?? ''}',
    if (fields['origin'] != null && fields['destination'] != null)
      '${fields['origin']} → ${fields['destination']}',
  ].where((value) => value.trim().isNotEmpty).join('\n');
}

String _excerpt(String value) {
  final safe = SyncErrorLogService.sanitize(value);
  return safe.length > 16000 ? safe.substring(0, 16000) : safe;
}

String _hash(Object? value) {
  Object? canonical(Object? item) {
    if (item is Map) {
      final keys = item.keys.map((key) => '$key').toList()..sort();
      return {for (final key in keys) key: canonical(item[key])};
    }
    if (item is List) return item.map(canonical).toList();
    if (item is Timestamp) {
      return {'timestamp': item.toDate().toUtc().toIso8601String()};
    }
    return item;
  }

  return sha256.convert(utf8.encode(jsonEncode(canonical(value)))).toString();
}
