import 'package:webapp/services/kpi/pm_kpi.dart';

/// Each truck has equal weight, regardless of revenue or row pagination.
String averageFleetRating(Iterable<PmKpi> reports) {
  final rows = reports.toList();
  if (rows.isEmpty) return 'Not rated';
  final rules = rows.first.ratingRules;
  var sum = 0.0;
  for (final row in rows) {
    if (!row.revenue.isFinite ||
        row.revenue <= 0 ||
        !row.gross.isFinite ||
        row.ratingRules.grossSatisfactoryMin != rules.grossSatisfactoryMin ||
        row.ratingRules.grossExcellentMin != rules.grossExcellentMin) {
      return 'Not rated';
    }
    sum += row.gross / row.revenue * 100;
  }
  return rules.grossRating(
    100,
    sum / rows.length,
    complete: rows.every((r) => r.complete),
  );
}
