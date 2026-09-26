import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/kpi/kpi_cost_override.dart';

/// The buffer is the company's real experience, so it stays the default. What
/// these tests pin is the part that is easy to get wrong: a figure that changes
/// an investor's money must be approved first, and anything unapproved or
/// unparseable has to fall back to the buffer rather than quietly zero a cost
/// out of a period.
void main() {
  const buffer = 14500.0;

  group('the company buffer is the default', () {
    test('with no record at all, the buffer stands', () {
      expect(resolveKpiCost(bufferAmount: buffer), buffer);
      expect(kpiCostIsEstimate(null), isTrue);
    });

    test('an unparseable amount falls back instead of becoming zero', () {
      // A half-written record must not wipe a real cost out of the period.
      for (final bad in <Object?>[null, '', 'abc', 'NaN', -1]) {
        final record = {
          'kind': 'cost_override',
          'source': 'actual',
          'amount': bad,
          'approval_status': 'approved',
        };
        expect(
          resolveKpiCost(bufferAmount: buffer, overrideRecord: record),
          buffer,
          reason: 'amount=$bad should fall back to the buffer',
        );
      }
    });
  });

  group('an approved actual beats the buffer', () {
    final approved = {
      'kind': 'cost_override',
      'source': 'actual',
      'amount': 8200.0,
      'approval_status': 'approved',
      'entered_by': '1',
    };

    test('it is used', () {
      expect(
        resolveKpiCost(bufferAmount: buffer, overrideRecord: approved),
        8200.0,
      );
    });

    test('and it is not an estimate', () {
      expect(kpiCostIsEstimate(approved), isFalse);
    });

    test('a record with no status field counts as approved', () {
      // Older or hand-written records have no status; treating them as pending
      // would silently ignore a figure the office already agreed to.
      final legacy = {
        'kind': 'cost_override',
        'source': 'actual',
        'amount': 9100.0,
      };
      expect(
        resolveKpiCost(bufferAmount: buffer, overrideRecord: legacy),
        9100.0,
      );
    });
  });

  group('a pending actual never moves money', () {
    final pending = {
      'kind': 'cost_override',
      'source': 'actual',
      'amount': 40000.0,
      'approval_status': 'pending',
      'entered_by': '1',
    };

    test('the buffer is used instead', () {
      expect(
        resolveKpiCost(bufferAmount: buffer, overrideRecord: pending),
        buffer,
        reason: 'an unapproved figure must not reduce what an investor is owed',
      );
    });

    test('and it still reads as an estimate', () {
      expect(kpiCostIsEstimate(pending), isTrue);
    });
  });

  test('a buffer record is a buffer even when marked approved', () {
    final record = {
      'kind': 'cost_override',
      'source': 'buffer',
      'amount': 14500.0,
      'approval_status': 'approved',
    };
    expect(
      resolveKpiCost(bufferAmount: buffer, overrideRecord: record),
      14500.0,
    );
    expect(kpiCostIsEstimate(record), isTrue);
  });

  test('a lower actual is honoured, not treated as a correction', () {
    // Maintenance can genuinely come in under the buffer, and that is real
    // information rather than an error to be clamped away.
    final cheap = {
      'kind': 'cost_override',
      'source': 'actual',
      'amount': 100.0,
      'approval_status': 'approved',
    };
    expect(resolveKpiCost(bufferAmount: buffer, overrideRecord: cheap), 100.0);
  });

  test('a rejected record is ignored the same way a pending one is', () {
    final rejected = {
      'kind': 'cost_override',
      'source': 'actual',
      'amount': 50000.0,
      'approval_status': 'rejected',
    };
    expect(
      resolveKpiCost(bufferAmount: buffer, overrideRecord: rejected),
      buffer,
    );
  });

  group('round-tripping a record', () {
    test('an approved actual survives being written and read back', () {
      const original = KpiCostOverride(
        amount: 12345.5,
        source: KpiCostSource.actual,
        periodKey: '2026-09',
        enteredBy: '1',
        approvedAt: '2026-09-26T10:00:00Z',
      );
      final restored = KpiCostOverride.fromRecord(original.toRecord());
      expect(restored.amount, 12345.5);
      expect(restored.overrides, isTrue);
      expect(restored.isEstimate, isFalse);
      expect(restored.periodKey, '2026-09');
      expect(restored.enteredBy, '1');
    });

    test('a pending actual survives as pending', () {
      const original = KpiCostOverride(
        amount: 900.0,
        source: KpiCostSource.actual,
        approved: false,
      );
      final restored = KpiCostOverride.fromRecord(original.toRecord());
      expect(restored.approved, isFalse);
      expect(
        restored.overrides,
        isFalse,
        reason: 'approval must not be lost in storage',
      );
    });
  });
}
