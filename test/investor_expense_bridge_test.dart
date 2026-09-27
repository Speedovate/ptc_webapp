import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/investor_commission.dart';
import 'package:webapp/services/investor_expense_bridge.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';

/// Two things decide whether a cost may reduce an investor's payout: it must be
/// on a truck that investor owns, and it must be approved. Both are enforced
/// here, because getting either wrong moves real money.
void main() {
  final period = KpiPeriod(DateTime.utc(2026, 9, 1), DateTime.utc(2026, 9, 30));
  const owned = {'4'};

  Map<String, dynamic> entry({
    String id = 'e1',
    String makeId = '4',
    String day = '2026-09-15',
    String amount = '1200',
    String? kind = 'fuel',
    bool approved = true,
    bool voided = false,
    String? reference = 'PO-2026-01',
    String? description = 'Diesel, Roxas run',
  }) => {
    'id': id,
    'make_id': makeId,
    'day': day,
    'amount': amount,
    'kind': ?kind,
    'approved': approved,
    'voided': voided,
    'reference': ?reference,
    'description': ?description,
  };

  List<InvestorExpense> bridge(List<Map<String, dynamic>> entries) =>
      investorExpensesFrom(
        entries: entries,
        ownedMakeIds: owned,
        period: period,
      );

  group('ownership', () {
    test("another investor's truck is not on this statement", () {
      final expenses = bridge([entry(makeId: '9')]);
      expect(expenses, isEmpty);
    });

    test('an entry with no truck recorded is not silently included', () {
      expect(bridge([entry(makeId: '')]), isEmpty);
    });

    test('a vehicle id that differs only by spacing still matches', () {
      expect(bridge([entry(makeId: ' 4 ')]), hasLength(1));
    });
  });

  group('the period', () {
    test('an entry outside the period is excluded', () {
      expect(bridge([entry(day: '2026-08-31')]), isEmpty);
      expect(bridge([entry(day: '2026-10-01')]), isEmpty);
      expect(bridge([entry(day: '2026-09-01')]), hasLength(1));
      expect(bridge([entry(day: '2026-09-30')]), hasLength(1));
    });

    test('a missing or unparseable date is excluded, not guessed', () {
      expect(bridge([entry(day: '')]), isEmpty);
      expect(bridge([entry(day: 'not-a-date')]), isEmpty);
    });
  });

  group('approval is the whole point', () {
    test('an unapproved cost is read but does not count', () {
      final expenses = bridge([entry(approved: false, amount: '9000')]);
      expect(expenses, hasLength(1), reason: 'it must stay visible');
      expect(expenses.single.approved, isFalse);
      expect(expenses.single.amount, 9000);
    });

    test('an entry with no approval field at all is unapproved', () {
      // Approval defaults to false. Anything the office typed in without
      // thinking about the investor must not move their money.
      final raw = entry()..remove('approved');
      expect(bridge([raw]).single.approved, isFalse);
    });

    test('onlyApproved filters the unapproved ones out entirely', () {
      final entries = [entry(id: 'a'), entry(id: 'b', approved: false)];
      final approvedOnly = investorExpensesFrom(
        entries: entries,
        ownedMakeIds: owned,
        period: period,
        onlyApproved: true,
      );
      expect(approvedOnly, hasLength(1));
      expect(approvedOnly.single.amount, 1200);
    });
  });

  group('entries that are not costs', () {
    test('a voided entry is a correction, not a charge', () {
      expect(bridge([entry(voided: true)]), isEmpty);
    });

    test('a zero or unparseable amount is dropped', () {
      expect(bridge([entry(amount: '0')]), isEmpty);
      expect(bridge([entry(amount: 'abc')]), isEmpty);
      expect(bridge([entry(amount: '-50')]), isEmpty);
    });
  });

  group('categories', () {
    test('the stored kind becomes a readable label', () {
      expect(bridge([entry(kind: 'fuel')]).single.category, 'Fuel');
      expect(
        bridge([entry(kind: 'maintenance')]).single.category,
        'Maintenance',
      );
      expect(bridge([entry(kind: 'repair')]).single.category, 'Repair');
      expect(bridge([entry(kind: 'tires')]).single.category, 'Tires');
      expect(bridge([entry(kind: 'parts')]).single.category, 'Parts');
    });

    test('an unrecognised kind is still shown rather than dropped', () {
      // A category nobody anticipated must not make a real cost disappear.
      expect(bridge([entry(kind: 'towing')]).single.category, 'Towing');
      expect(bridge([entry(kind: null)]).single.category, 'Fuel');
    });
  });

  test('the reference and description survive for the statement line', () {
    final expense = bridge([
      entry(reference: 'PO-77', description: 'Diesel, Roxas run'),
    ]).single;
    expect(expense.reference, 'PO-77');
    expect(expense.description, 'Diesel, Roxas run');
  });

  test('notes stand in when there is no description', () {
    final raw = entry()..remove('description');
    raw['notes'] = 'topped up at San Manuel';
    expect(bridge([raw]).single.description, 'topped up at San Manuel');
  });

  group('coverage', () {
    test('a period with trips and no costs is flagged as not final', () {
      final coverage = investorCostCoverage(
        expenses: const [],
        tripCount: 12,
        allEntries: const [],
      );
      expect(coverage.recorded, 0);
      expect(coverage.missing, greaterThan(0));
    });

    test('a period with approved costs is not flagged', () {
      final coverage = investorCostCoverage(
        expenses: bridge([entry()]),
        tripCount: 12,
        allEntries: const [],
      );
      expect(coverage.recorded, 1);
      expect(coverage.missing, 0);
    });

    test('a quiet period is never flagged', () {
      final coverage = investorCostCoverage(
        expenses: const [],
        tripCount: 0,
        allEntries: const [],
      );
      expect(coverage.missing, 0);
    });
  });
}
