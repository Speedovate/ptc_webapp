import 'pm_kpi.dart';

String kpiPeriodLabel(KpiPeriod period, {String mode = 'Range', int week = 1}) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  String date(DateTime value, {bool year = true}) =>
      '${months[value.month - 1]} ${value.day}${year ? ', ${value.year}' : ''}';
  return switch (mode) {
    'All Time' => 'All Time',
    'Weekly' => 'Week $week',
    'Monthly' => '${months[period.start.month - 1]} ${period.start.year}',
    _ =>
      '${date(period.start)} - ${date(period.end, year: period.start.year != period.end.year)}',
  };
}
