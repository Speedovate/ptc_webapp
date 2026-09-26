import 'package:webapp/services/kpi/pm_kpi.dart';

/// The company's own KPI works on a fixed weekly buffer for maintenance and
/// truck depreciation. That buffer is years of real experience, so it stays the
/// default - but an actual figure, once entered, is better than a buffer and has
/// to win.
///
/// Two rules matter here, and both are about not lying to the reader:
///
///  * a value that came from the buffer is an **estimate**, and must be shown as
///    one. It looks exactly like a real number otherwise, and somebody will
///    eventually act on it.
///  * an override only counts once it is **approved**. A figure that changes
///    someone's money cannot sit in the books at the office's word alone.
class KpiCostOverride {
  const KpiCostOverride({
    required this.amount,
    required this.source,
    this.approved = true,
    this.periodKey,
    this.enteredBy,
    this.approvedAt,
  });

  /// Reads a stored record. A record without a usable amount is treated as
  /// absent rather than zero, so a half-written entry falls back to the buffer
  /// instead of wiping a real cost out of the period.
  factory KpiCostOverride.fromRecord(Map<String, dynamic>? record) {
    if (record == null) {
      return const KpiCostOverride.estimated(0);
    }
    final amount = kpiMoney(record['amount']);
    if (amount == null) {
      return const KpiCostOverride.estimated(0);
    }
    return KpiCostOverride(
      amount: amount,
      source: record['source'] == 'actual'
          ? KpiCostSource.actual
          : KpiCostSource.buffer,
      // Only an explicit approval counts. Anything else - pending, rejected,
      // or a value we do not recognise - leaves the buffer in place, because
      // this figure reduces what somebody is paid. A record with no status at
      // all predates the field and is treated as agreed, so an existing entry
      // is not silently ignored.
      approved: switch (record['approval_status']?.toString().trim()) {
        null => true,
        final String status => status == 'approved',
      },
      periodKey: record['period_key']?.toString(),
      enteredBy: record['entered_by']?.toString(),
      approvedAt: record['approved_at']?.toString(),
    );
  }

  /// The company buffer, used when no approved actual exists.
  const KpiCostOverride.estimated(this.amount)
    : source = KpiCostSource.buffer,
      approved = true,
      periodKey = null,
      enteredBy = null,
      approvedAt = null;

  final double amount;
  final KpiCostSource source;

  /// An override the investor has not agreed to yet must not move their money.
  final bool approved;
  final String? periodKey;
  final String? enteredBy;
  final String? approvedAt;

  bool get isEstimate => source == KpiCostSource.buffer;

  /// True when this record should stand in for the buffer.
  bool get overrides => source == KpiCostSource.actual && approved;

  Map<String, dynamic> toRecord() => {
    'kind': 'cost_override',
    'source': source == KpiCostSource.actual ? 'actual' : 'buffer',
    'amount': amount,
    if (periodKey != null) 'period_key': periodKey,
    if (enteredBy != null) 'entered_by': enteredBy,
    'approval_status': approved ? 'approved' : 'pending',
    if (approvedAt != null) 'approved_at': approvedAt,
  };
}

enum KpiCostSource {
  /// Years of company experience, weeks x a constant.
  buffer,

  /// A figure somebody actually entered.
  actual,
}

/// Resolves a cost line for a period: an approved actual wins, otherwise the
/// company buffer applies and the result is flagged as an estimate.
double resolveKpiCost({
  required double bufferAmount,
  Map<String, dynamic>? overrideRecord,
}) {
  final override = KpiCostOverride.fromRecord(overrideRecord);
  if (override.overrides) {
    return override.amount;
  }
  return bufferAmount;
}

/// Whether the resolved value is an estimate, for the "est." marker.
bool kpiCostIsEstimate(Map<String, dynamic>? overrideRecord) {
  final override = KpiCostOverride.fromRecord(overrideRecord);
  return !override.overrides || override.isEstimate;
}
