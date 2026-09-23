import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/kpi/kpi_rating_rules.dart';

void main() {
  const rules = KpiRatingRules();
  test('margin ratings cover fractional percentages and boundaries', () {
    for (final entry in {
      39.0: 'Failed',
      39.9: 'Failed',
      40.0: 'Satisfactory',
      50.0: 'Satisfactory',
      50.9: 'Satisfactory',
      51.0: 'Excellent',
      70.0: 'Excellent',
    }.entries) {
      expect(rules.grossRating(100, entry.key, complete: true), entry.value);
    }
    expect(rules.grossRating(100, -92.51, complete: false), 'Failed');
    expect(rules.grossRating(0, 0, complete: true), 'Not rated');
    expect(rules.grossRating(100, 70, complete: false), 'Excellent');
  });
  test('unknown incidents are not assumed zero', () {
    expect(rules.complaintsRating(null), 'Not recorded');
    expect(rules.accidentsRating(null), 'Not recorded');
    expect(rules.complaintsRating(0), 'Excellent');
    expect(rules.complaintsRating(1), 'Satisfactory');
    expect(rules.complaintsRating(2), 'Failed');
    expect(rules.accidentsRating(0), 'Excellent');
    expect(rules.accidentsRating(1), 'Failed');
  });
  test('edited rules round trip independently of old allowance', () {
    const edited = KpiRatingRules(
      grossSatisfactoryMin: 35,
      grossExcellentMin: 55,
      complaintsExcellentMax: 1,
      complaintsSatisfactoryMax: 2,
      accidentsExcellentMax: 1,
    );
    final restored = KpiRatingRules.fromMap({
      'threshold': 10000,
      'rating_rules': edited.toMap(),
    });
    expect(restored.grossRating(100, 40, complete: true), 'Satisfactory');
    expect(restored.complaintsRating(1), 'Excellent');
    expect(restored.accidentsRating(1), 'Excellent');
  });
}
