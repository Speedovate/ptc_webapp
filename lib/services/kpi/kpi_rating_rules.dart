/// Editable KPI thresholds. Unknown counts and zero revenue are not successes.
class KpiRatingRules {
  const KpiRatingRules({
    this.targetPercent = 40,
    this.grossSatisfactoryMin = 40,
    this.grossExcellentMin = 51,
    this.complaintsExcellentMax = 0,
    this.complaintsSatisfactoryMax = 1,
    this.accidentsExcellentMax = 0,
  });
  final double targetPercent;
  String get targetLabel => targetPercent == targetPercent.truncateToDouble()
      ? targetPercent.toInt().toString()
      : targetPercent.toString();
  final double grossSatisfactoryMin;
  final double grossExcellentMin;
  final int complaintsExcellentMax;
  final int complaintsSatisfactoryMax;
  final int accidentsExcellentMax;

  bool get valid =>
      targetPercent.isFinite &&
      targetPercent >= 0 &&
      targetPercent <= 100 &&
      grossSatisfactoryMin.isFinite &&
      grossExcellentMin.isFinite &&
      grossSatisfactoryMin >= 0 &&
      grossSatisfactoryMin < grossExcellentMin &&
      grossExcellentMin <= 100 &&
      complaintsExcellentMax >= 0 &&
      complaintsSatisfactoryMax > complaintsExcellentMax &&
      accidentsExcellentMax >= 0;

  factory KpiRatingRules.fromMap(Map<String, dynamic> map) {
    final value = map['rating_rules'];
    if (value is! Map) return const KpiRatingRules();
    num read(String key, num fallback) =>
        value[key] is num ? value[key] as num : fallback;
    final rules = KpiRatingRules(
      targetPercent: read('target_percent', 40).toDouble(),
      grossSatisfactoryMin: read('gross_satisfactory_min', 40).toDouble(),
      grossExcellentMin: read('gross_excellent_min', 51).toDouble(),
      complaintsExcellentMax: read('complaints_excellent_max', 0).toInt(),
      complaintsSatisfactoryMax: read('complaints_satisfactory_max', 1).toInt(),
      accidentsExcellentMax: read('accidents_excellent_max', 0).toInt(),
    );
    return rules.valid ? rules : const KpiRatingRules();
  }

  Map<String, dynamic> toMap() => {
    'target_percent': targetPercent,
    'gross_satisfactory_min': grossSatisfactoryMin,
    'gross_excellent_min': grossExcellentMin,
    'complaints_excellent_max': complaintsExcellentMax,
    'complaints_satisfactory_max': complaintsSatisfactoryMax,
    'accidents_excellent_max': accidentsExcellentMax,
  };

  String grossRating(double revenue, double gross, {required bool complete}) {
    // Rate current amounts even while data checks remain unresolved.
    if (!revenue.isFinite || !gross.isFinite || revenue <= 0) {
      return 'Not rated';
    }
    final percent = gross / revenue * 100;
    if (percent >= grossExcellentMin) return 'Excellent';
    if (percent >= grossSatisfactoryMin) return 'Satisfactory';
    return 'Failed';
  }

  String complaintsRating(int? count) {
    if (count == null || count < 0) return 'Not recorded';
    if (count <= complaintsExcellentMax) return 'Excellent';
    if (count <= complaintsSatisfactoryMax) return 'Satisfactory';
    return 'Failed';
  }

  String accidentsRating(int? count) {
    if (count == null || count < 0) return 'Not recorded';
    return count <= accidentsExcellentMax ? 'Excellent' : 'Failed';
  }
}
