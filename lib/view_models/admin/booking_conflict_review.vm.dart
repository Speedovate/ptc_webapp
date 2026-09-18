import 'package:flutter/foundation.dart';
import 'package:webapp/services/booking_conflict_review_service.dart';

class BookingConflictReviewViewModel extends ChangeNotifier {
  BookingConflictReviewViewModel({
    required this.service,
    required this.adminId,
  });
  final BookingConflictReviewService service;
  final String adminId;
  List<String> conflicts = [];
  BookingConflictPreview? preview;
  BookingConflictChoice? choice;
  bool acknowledged = false, busy = false, _disposed = false;
  String? error, success;
  bool get canApply =>
      !busy && preview?.canApply == true && choice != null && acknowledged;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    if (busy) return;
    busy = true;
    error = null;
    preview = null;
    choice = null;
    acknowledged = false;
    _emit();
    try {
      conflicts = await service.listConflicts();
    } catch (e) {
      error = e.toString();
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<void> select(String id) async {
    if (busy) return;
    busy = true;
    error = null;
    success = null;
    preview = null;
    choice = null;
    acknowledged = false;
    _emit();
    try {
      preview = await service.preview(id);
    } catch (e) {
      error = e.toString();
    } finally {
      busy = false;
      _emit();
    }
  }

  void choose(BookingConflictChoice? value) {
    if (busy) return;
    choice = value;
    acknowledged = false;
    _emit();
  }

  void acknowledge(bool value) {
    if (busy) return;
    acknowledged = value;
    _emit();
  }

  Future<void> apply() async {
    if (!canApply) return;
    final selected = preview!;
    final decision = choice!;
    busy = true;
    error = null;
    _emit();
    try {
      await service.apply(selected, decision, adminId: adminId);
      conflicts.remove(selected.id);
      preview = null;
      choice = null;
      acknowledged = false;
      success =
          'Booking #${selected.targetId} reconciled. The temporary copy and both original versions were archived.';
    } catch (e) {
      error = e.toString();
      acknowledged = false;
    } finally {
      busy = false;
      _emit();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
