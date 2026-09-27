import 'package:flutter/foundation.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/services/investor_commission.dart';
import 'package:webapp/services/investor_commission_rate_store.dart';
import 'package:webapp/services/investor_expense_bridge.dart';
import 'package:webapp/services/investor_scope.dart';
import 'package:webapp/services/kpi/investor_statement_workbook.dart';
import 'package:webapp/services/kpi/kpi_report_export.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/services/kpi/pm_kpi_store.dart';
import 'package:webapp/utils/functions.dart';

/// The period key a statement is filed under. Statements are monthly because
/// that is how a driver, a crew and an investor read a month; an arbitrary date
/// range would produce a document nobody can compare to the one before it.
String kpiMonthKey(KpiPeriod period) {
  final month = period.start.month.toString().padLeft(2, '0');
  return '${period.start.year}-$month';
}

String kpiMonthLabel(KpiPeriod period) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[period.start.month - 1]} ${period.start.year}';
}

/// Assembles one investor's statement for one month, from the same records the
/// office KPI reads.
///
/// The office picks the investor and the month and sends the file. Nothing is
/// served from the database, so the access control is who receives the document
/// - which is why this refuses to produce a half-priced one instead of quietly
/// understating what the crew earned.
class InvestorStatementViewModel extends ChangeNotifier {
  InvestorStatementViewModel({
    PmKpiStore? kpiStore,
    InvestorCommissionRateStore? rateStore,
  }) : _kpi = kpiStore ?? PmKpiStore.instance,
       _rates = rateStore ?? InvestorCommissionRateStore.instance;

  final PmKpiStore _kpi;
  final InvestorCommissionRateStore _rates;

  /// Exposed so a caller that already has this view model - the dialog, or a
  /// test - can hand the same stores to something else rather than building a
  /// second set pointed at a different cache.
  PmKpiStore get kpiStore => _kpi;
  InvestorCommissionRateStore get rateStore => _rates;

  List<VehicleMake> _makes = const [];
  String? _investorId;
  KpiPeriod _period = _currentMonth();
  InvestorCommission? _statement;
  List<VehicleMake> _owned = const [];
  bool _busy = false;
  String? _error;
  bool _fromCache = false;
  String? _errorForShare;

  static KpiPeriod _currentMonth() {
    final now = DateTime.now().toUtc();
    return KpiPeriod.month(now.year, now.month);
  }

  List<VehicleMake> get makes => _makes;
  String? get investorId => _investorId;
  KpiPeriod get period => _period;
  InvestorCommission? get statement => _statement;
  List<VehicleMake> get ownedMakes => _owned;
  bool get busy => _busy;
  String? get error => _error;
  bool get fromCache => _fromCache;

  /// A rejected share, kept apart from [error] so a typo in the share field
  /// never blanks a statement the office is already reading.
  String? get errorForShare => _errorForShare;
  set errorForShare(String? value) {
    if (_errorForShare == value) return;
    _errorForShare = value;
    notifyListeners();
  }

  double get platformShare => InvestorCommissionRateStore.toPercent(
    _statement?.rate ?? InvestorCommissionRateStore.defaultRate,
  );

  bool get canRead => _rates.canRead;
  bool get canEditRate => _rates.canEdit;

  /// The investors that actually own something, in a stable order.
  ///
  /// Derived from the trucks on file rather than a directory of investors,
  /// because no such directory exists and inventing one is a separate decision.
  /// An id with no truck cannot be owed anything, so it is not offered.
  List<String> get investors {
    final ids = <String>{};
    for (final make in _makes) {
      final id = normalizeId(make.investorId);
      if (id != null) ids.add(id);
    }
    final list = ids.toList()..sort();
    return list;
  }

  bool get hasInvestors => investors.isNotEmpty;

  void selectInvestor(String? id) {
    if (_investorId == id) return;
    _investorId = id;
    // A statement belongs to one investor; leaving the old one on screen after
    // switching would show figures that are not the selected investor's.
    _statement = null;
    _owned = const [];
    notifyListeners();
  }

  void selectPeriod(KpiPeriod period) {
    if (_period.start == period.start && _period.end == period.end) return;
    _period = period;
    _statement = null;
    _owned = const [];
    notifyListeners();
  }

  void setMakes(List<VehicleMake> makes) {
    _makes = makes;
    // Keep the selection only if it still owns a truck. A deleted make should
    // not leave a statement on screen for an investor who no longer exists.
    if (_investorId != null && !investors.contains(_investorId)) {
      _investorId = null;
      _statement = null;
      _owned = const [];
    }
    notifyListeners();
  }

  /// Loads the current platform share so the office can see it before editing.
  Future<double> loadPlatformShare() async {
    final rate = await _rates.loadRate();
    notifyListeners();
    return InvestorCommissionRateStore.toPercent(rate);
  }

  /// Sets the share every future statement is priced at.
  Future<void> savePlatformShare(double percent) async {
    if (!canEditRate) {
      throw StateError('You do not have access to change the platform share.');
    }
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await _rates.saveRate(
        InvestorCommissionRateStore.validatePercent(percent),
      );
      // What is on screen was priced at the old share. Leaving it there would
      // show one number and print another.
      _statement = null;
    } catch (error) {
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Reads every record the statement is built from, for the selected investor
  /// and month.
  ///
  /// Every truck the investor owns is read separately because the office KPI is
  /// per truck; the results are then merged, since an investor's statement is
  /// about the investor rather than about any one vehicle.
  Future<InvestorCommission?> generate() async {
    final id = _investorId;
    if (id == null) {
      _error = 'Choose an investor first.';
      notifyListeners();
      return null;
    }
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      _owned = _makes
          .where((make) => InvestorScope.investorForMake(make) == id)
          .toList();
      if (_owned.isEmpty) {
        _error = 'That investor does not own any trucks on file.';
        notifyListeners();
        return null;
      }
      final bookings = await _kpi.bookings();
      final trips = <KpiTrip>[];
      final savedRates = <Map<String, dynamic>>[];
      final officeDays = <String, KpiDay>{};
      final fuelEntries = <Map<String, dynamic>>[];
      var usedCache = false;
      for (final make in _owned) {
        final makeId = make.id;
        if (makeId == null) continue;
        final data = await _kpi.load(makeId, _period);
        if (data.fromCache) usedCache = true;
        final kpi = PmKpi.calculate(
          makeId: makeId,
          period: _period,
          bookings: bookings,
          records: data.records,
          fuelEntries: data.fuel,
          makes: _makes,
        );
        for (final day in kpi.days) {
          trips.addAll(day.trips);
          // What the office entered for this day, kept so the statement can
          // stand on the office's own figure instead of re-deriving it.
          if (day.hasSavedSalary) officeDays[kpiDayKey(day.date)] = day;
          final saved = day.record['trip_rates'];
          if (saved is List) {
            savedRates.addAll(
              saved.whereType<Map>().map(
                (row) => row.map((k, v) => MapEntry(k.toString(), v)),
              ),
            );
          }
        }
        fuelEntries.addAll(data.fuel);
      }
      _fromCache = usedCache;

      // One resolution across every truck, so a route the office confirmed for
      // a trip is found the same way whether the truck is read first or last.
      final resolution = resolveKpiTripRoutes(
        trips,
        rates: KpiRate.matrix,
        savedTripRates: savedRates,
      );
      if (!resolution.complete) {
        throw StateError(
          'Cannot price ${resolution.unresolved.length} of ${trips.length} '
          'trip${trips.length == 1 ? '' : 's'} on the rate card, so the crew '
          'share cannot be calculated. Set a trip rate for each one in the PM '
          'KPI first.',
        );
      }

      final rate = await _rates.loadRate();
      final ownedIds = _owned
          .map((make) => make.id)
          .whereType<String>()
          .toSet();
      final expenses = investorExpensesFrom(
        entries: fuelEntries,
        ownedMakeIds: ownedIds,
        period: _period,
      );
      _statement = InvestorCommission.calculate(
        investorId: id,
        periodKey: kpiMonthKey(_period),
        rate: rate,
        trips: trips,
        routes: resolution.routes,
        makes: _makes,
        expenses: expenses,
        officeDays: officeDays,
      );
      return _statement;
    } catch (error) {
      _error = error.toString();
      _statement = null;
      return null;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Map<String, List<List<Object?>>> _sheets(InvestorCommission statement) {
    final crew = <UserModel>[];
    final seen = <String>{};
    for (final trip in statement.trips) {
      for (final person in [trip.booking.driver, trip.booking.helper]) {
        final personId = normalizeId(person?.id);
        if (personId != null && seen.add(personId)) crew.add(person!);
      }
    }
    return InvestorStatementWorkbook.build(
      statement: statement,
      periodKey: statement.periodKey,
      makes: _makes,
      crew: crew,
      costsRecorded: statement.expenses.length,
    );
  }

  /// The files the office can send. One period, one document per format.
  Map<String, Uint8List> files(InvestorCommission statement) {
    final name = InvestorStatementWorkbook.fileName(
      investorId: statement.investorId,
      periodKey: statement.periodKey,
    );
    final sheets = _sheets(statement);
    return {
      '$name.xlsx': KpiReportExport.excel(sheets, styled: true),
      '$name.pdf': KpiReportExport.pdf(sheets),
    };
  }
}
