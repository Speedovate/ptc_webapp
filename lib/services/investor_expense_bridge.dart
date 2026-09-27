import 'package:webapp/services/investor_commission.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/utils/functions.dart';

/// Turns the cost entries already on file into the lines on an investor's
/// statement.
///
/// The storage is not new: `pm_fuel_entries` already holds a truck, a day, an
/// amount, a PO reference and a `kind`. What this adds is the two things a
/// payout needs and a fuel ledger does not carry by itself:
///
///  * **ownership** - only entries on this investor's own trucks
///  * **approval** - an entry counts only once the investor has signed it off,
///    so a cost the office typed in cannot quietly reduce their pay
///
/// Approval defaults to **false**. A cost that is nobody's business yet deducts
/// nothing, and the statement still shows it as pending so it is never hidden.
List<InvestorExpense> investorExpensesFrom({
  required List<Map<String, dynamic>> entries,
  required Set<String> ownedMakeIds,
  required KpiPeriod period,
  bool onlyApproved = false,
}) {
  final result = <InvestorExpense>[];
  for (final entry in entries) {
    // A voided entry is a correction, not a cost.
    if (entry['voided'] == true) continue;
    final makeId = normalizeId(entry['make_id']);
    if (makeId == null || !ownedMakeIds.contains(makeId)) continue;
    final day = _dayOf(entry);
    if (day == null || !period.contains(day)) continue;
    final amount = kpiMoney(entry['amount']);
    if (amount == null || amount <= 0) continue;

    final expense = InvestorExpense(
      amount: amount,
      category: _categoryOf(entry),
      approved: entry['approved'] == true,
      tripBookingId: entry['booking_id']?.toString(),
      incurredAt: day,
      reference: entry['reference']?.toString(),
      description: _descriptionOf(entry),
    );
    if (onlyApproved && !expense.approved) continue;
    result.add(expense);
  }
  return result;
}

String _categoryOf(Map<String, dynamic> entry) {
  final kind = (entry['kind'] ?? '').toString().trim().toLowerCase();
  if (kind.isEmpty || kind == 'fuel') return 'Fuel';
  if (kind == 'maintenance') return 'Maintenance';
  if (kind == 'repair') return 'Repair';
  if (kind == 'tires' || kind == 'tyre') return 'Tires';
  if (kind == 'parts') return 'Parts';
  return kind[0].toUpperCase() + kind.substring(1);
}

String? _descriptionOf(Map<String, dynamic> entry) {
  final description = (entry['description'] ?? '').toString().trim();
  if (description.isNotEmpty) return description;
  final notes = (entry['notes'] ?? '').toString().trim();
  return notes.isEmpty ? null : notes;
}

DateTime? _dayOf(Map<String, dynamic> entry) {
  final raw = entry['day'] ?? entry['incurred_at'] ?? entry['date'];
  if (raw is DateTime) return kpiDate(raw);
  return DateTime.tryParse('${raw ?? ''}T00:00:00Z');
}

/// Whether a statement is safe to hand over.
///
/// A period where trips ran but no cost was recorded is not a real number, it
/// is a number with the biggest cost line left out. Rather than refuse to build
/// the statement - which an office under pressure will route around - the
/// statement is produced and marked, so the recipient can see the gap.
({int recorded, int missing}) investorCostCoverage({
  required List<InvestorExpense> expenses,
  required int tripCount,
  required List<Map<String, dynamic>> allEntries,
}) {
  final recorded = expenses.where((expense) => expense.approved).length;
  return (
    recorded: recorded,
    // One entry per worked day is the least that counts as a real ledger.
    missing: tripCount > 0 && recorded == 0 ? tripCount : 0,
  );
}
