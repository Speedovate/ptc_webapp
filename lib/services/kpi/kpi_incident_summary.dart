import 'pm_kpi.dart';

/// Date-based observations can be summed across overlapping report periods
/// without counting a weekly and monthly entry twice.
class KpiIncidentSummary {
  KpiIncidentSummary(
    Map<String, dynamic> settings,
    KpiPeriod period,
    DateTime today,
  ) {
    final raw = settings['incident_counts'];
    final records = raw is Map ? raw : const {};
    for (
      var day = period.start;
      !day.isAfter(period.end) && !day.isAfter(today);
      day = day.add(const Duration(days: 1))
    ) {
      days++;
      final value = records[kpiDayKey(day)];
      final complaint = value is Map ? count(value['complaints']) : null;
      final accident = value is Map ? count(value['accidents']) : null;
      if (complaint == null) {
        missingComplaints++;
      } else {
        complaints += complaint;
      }
      if (accident == null) {
        missingAccidents++;
      } else {
        accidents += accident;
      }
    }
  }
  factory KpiIncidentSummary.forUser(
    Map<String, dynamic> settings,
    String userId,
    KpiPeriod period,
    DateTime today,
  ) {
    final users = settings['user_incident_counts'];
    final records = users is Map ? users[userId] : null;
    return KpiIncidentSummary(
      {'incident_counts': records is Map ? records : const {}},
      period,
      today,
    );
  }

  int days = 0;
  int complaints = 0;
  int accidents = 0;
  int missingComplaints = 0;
  int missingAccidents = 0;
  int? get confirmedComplaints =>
      days > 0 && missingComplaints == 0 ? complaints : null;
  int? get confirmedAccidents =>
      days > 0 && missingAccidents == 0 ? accidents : null;
  static int? count(Object? value) =>
      value is num &&
          value.isFinite &&
          value >= 0 &&
          value == value.truncateToDouble()
      ? value.toInt()
      : null;
}
