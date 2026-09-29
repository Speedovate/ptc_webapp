import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/services/booking_pm_assignment.dart';
import 'package:webapp/services/investor_scope.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/utils/functions.dart';
import 'package:webapp/widgets/shared/booking_record_card.dart';

/// One investor's statement for one period.
///
///   Paltranco = Amount x rate                (10%, every trip, unconditionally)
///   Investor  = (Amount x (1 - rate))
///                - crew daily salary
///                - crew trip share
///                - approved expenses
///
/// Amounts and crew costs are read with the same helpers the office KPI uses -
/// `outputFieldValue` and `kpiSalary` - so this statement and the PM's own
/// report cannot drift apart. The first person to notice a mismatch stops
/// trusting both, so the second source of truth is not worth the convenience.
class InvestorCommission {
  const InvestorCommission._({
    required this.investorId,
    required this.periodKey,
    required this.rate,
    required this.trips,
    required this.crewDaily,
    required this.crewTripShare,
    required this.crewCost,
    required this.officeDayCount,
    required this.unconfirmedDays,
    required List<InvestorExpense> expenses,
  }) : _expenses = expenses;

  factory InvestorCommission.calculate({
    required String investorId,
    required String periodKey,
    required double rate,
    required List<KpiTrip> trips,
    required Map<String, String> routes,
    List<VehicleMake> makes = const [],
    List<UserModel> users = const [],
    List<InvestorExpense> expenses = const [],
    List<KpiRate> matrix = KpiRate.matrix,
    double dailyRate = 455,
    Map<String, KpiDay> officeDays = const {},
  }) {
    // Ownership comes from the canonical make record, never from the copy
    // embedded in the booking. A booking cached before investors existed
    // carries a make with no owner on it, and trusting that copy would
    // silently drop a real trip off an investor's statement.
    // A truck has no owner field. Who owns it is read off whoever is crewed on
    // it, so the users have to be in hand to resolve that.
    final usersById = <String, UserModel>{};
    for (final user in users) {
      final userId = normalizeId(user.id);
      if (userId != null) usersById[userId] = user;
    }
    final makesById = <String, VehicleMake>{};
    for (final make in makes) {
      final id = normalizeId(make.id);
      if (id != null) makesById[id] = make;
    }
    final ownedTrips = trips.where((trip) {
      final embedded = resolveBookingPm(trip.booking, makes);
      final id =
          normalizeId(embedded?.id) ??
          normalizeId(trip.booking.vehicleMake?.id);
      if (id == null) {
        return false;
      }
      return InvestorScope.investorForMake(
            makesById[id] ?? embedded,
            usersById,
          ) ==
          investorId;
    }).toList();

    // Every owned trip must be priced before any money is computed.
    //
    // A trip with no route has no crew trip share: kpiSalary charges nothing,
    // the statement looks perfectly well-formed, and the investor is quietly
    // paid the crew's share instead of Paltranco. The reconciliation check below
    // cannot catch it, because kpiSalary derived its own total from the same
    // empty map - it would certify the wrong answer as consistent.
    //
    // So refuse instead. The office KPI dialog already refuses to save a salary
    // with a trip unpriced; an investor statement is held to the same rule
    // because the person reading it has less ability to check than the office
    // does.
    // Only days the office has not already priced need a rate from the card. A
    // day with the office's own figure is already answered, so an unmatched
    // route there is not a gap in the statement - it is a gap in the card.
    final unpriced = <KpiTrip>[];
    for (final trip in ownedTrips) {
      final day = officeDays[kpiDayKey(trip.day)];
      if (day != null && day.hasSavedSalary) {
        continue;
      }
      final route = routes[trip.identity]?.trim() ?? '';
      if (route.isEmpty || !matrix.any((r) => r.name == route)) {
        unpriced.add(trip);
      }
    }
    if (unpriced.isNotEmpty) {
      final shown = unpriced
          .take(3)
          .map((trip) {
            final where = trip.destination.trim().isEmpty
                ? 'no drop-off recorded'
                : trip.destination.trim();
            return '$where (${trip.identity})';
          })
          .join('; ');
      throw StateError(
        'Cannot price ${unpriced.length} of ${ownedTrips.length} '
        'trip${ownedTrips.length == 1 ? '' : 's'} on the rate card, so the '
        'crew share cannot be calculated: $shown'
        '${unpriced.length > 3 ? '; and ${unpriced.length - 3} more' : ''}. '
        'Set a trip rate for each one first.',
      );
    }

    // Priced one day at a time, exactly the way the office prices each day.
    //
    // This is not a style choice. kpiSalary pays a daily per *distinct person
    // in the list it is given*, which is correct for one day and badly wrong
    // for a month: handing it every trip in the period counts a driver who
    // worked twenty days as one person, and the nineteen dailies never get
    // charged. The crew is short-paid, the difference silently becomes the
    // investor's, and every total still reconciles because both sides were
    // computed from the same mistake.
    final byDay = <String, List<KpiTrip>>{};
    for (final trip in ownedTrips) {
      byDay.putIfAbsent(kpiDayKey(trip.day), () => []).add(trip);
    }
    var derivedTotal = 0.0;
    var tripShare = 0.0;
    var personDays = 0;
    var officeTotal = 0.0;
    var officeDayCount = 0;
    var unconfirmedDays = 0;
    for (final dayTrips in byDay.values) {
      // What the office entered wins. They know the run; the card does not, and
      // the card is silent on any route it does not carry.
      final office = officeDays[kpiDayKey(dayTrips.first.day)];
      if (office != null && office.hasSavedSalary) {
        officeTotal += office.savedDriverSalary + office.savedHelperSalary;
        officeDayCount++;
        if (!office.salaryComplete) unconfirmedDays++;
        continue;
      }
      final day = kpiSalary(
        dayTrips,
        routes,
        matrix: matrix,
        dailyRate: dailyRate,
      );
      derivedTotal += day.driver + day.helper;
      // The rates list is the per-trip part on its own. The driver/helper
      // totals already contain both, so reading the daily out of them as well
      // would count it twice and quietly hand the trip share back.
      tripShare += day.rates.fold<double>(
        0,
        (sum, row) =>
            sum +
            ((row['driver'] as num?) ?? 0) +
            ((row['helper'] as num?) ?? 0),
      );
      // A person is paid a daily for a day they turned up, counted per day.
      final crew = <String>{};
      for (final trip in dayTrips) {
        for (final id in [trip.booking.driver?.id, trip.booking.helper?.id]) {
          final normalized = normalizeId(id);
          if (normalized != null) crew.add(normalized);
        }
      }
      personDays += crew.length;
    }
    // The daily is stated as a flat figure per person-day, counted here
    // independently of kpiSalary so the reconciliation below compares two
    // different calculations rather than one calculation with itself.
    final daily = dailyRate * personDays;
    // Reconcile rather than trust, over the days this statement derived itself.
    // If the rate card ever changes shape, or the office's own daily rule
    // changes, this fails here instead of producing a plausible-looking
    // statement. The office's own figures are not second-guessed - that is the
    // whole reason they are trusted.
    final expected = daily + tripShare;
    if ((derivedTotal - expected).abs() > 0.005) {
      throw StateError(
        'Crew cost does not reconcile: $derivedTotal reported against '
        '$expected.',
      );
    }
    final combined = derivedTotal + officeTotal;

    return InvestorCommission._(
      investorId: investorId,
      periodKey: periodKey,
      rate: rate,
      trips: ownedTrips,
      crewDaily: daily,
      crewTripShare: tripShare,
      crewCost: combined,
      officeDayCount: officeDayCount,
      unconfirmedDays: unconfirmedDays,
      expenses: expenses,
    );
  }

  final String investorId;
  final String periodKey;
  final double rate;
  final List<KpiTrip> trips;
  final double crewDaily;
  final double crewTripShare;

  /// Every peso of crew cost on the statement, however it was arrived at.
  final double crewCost;

  /// Days the office priced itself, and how many of those it has not ticked
  /// off. Surfaced rather than hidden: an unconfirmed figure is still the
  /// office's best answer, but the reader should know it was not signed off.
  final int officeDayCount;
  final int unconfirmedDays;
  final List<InvestorExpense> _expenses;

  /// Every cost on file, approved or not, so the statement can show what is
  /// still waiting on the investor.
  List<InvestorExpense> get expenses => List.unmodifiable(_expenses);

  List<InvestorExpense> get approvedExpenses =>
      _expenses.where((expense) => expense.approved).toList();

  List<InvestorExpense> get pendingExpenses =>
      _expenses.where((expense) => !expense.approved).toList();

  /// The delivery amount, read through the same resolver the KPI uses.
  double amountFor(KpiTrip trip) {
    final raw = BookingRecordCard.outputFieldValue(
      trip.booking.statusOutputs,
      'amount',
    );
    return kpiMoney(raw) ?? 0;
  }

  int get tripCount => trips.length;

  double get grossBillings =>
      trips.fold<double>(0, (sum, trip) => sum + amountFor(trip));

  /// Paltranco's cut. Flat, and unaffected by whether the trip made money.
  double get platformFee => grossBillings * rate;

  double get investorPool => grossBillings - platformFee;

  double get approvedExpensesTotal =>
      approvedExpenses.fold<double>(0, (sum, expense) => sum + expense.amount);

  /// What the investor is owed for the period. Not clamped: a period that comes
  /// out negative is a real answer that the office needs to see, not something
  /// to quietly floor at zero.
  double get netDue => investorPool - crewCost - approvedExpensesTotal;

  /// The full line-by-line breakdown, in the order an investor reads it.
  List<(String, double)> get statement => [
    ('Gross billings', grossBillings),
    ('Paltranco share (${(rate * 100).toStringAsFixed(0)}%)', -platformFee),
    // The split only means something when this statement did the pricing. When
    // the office priced the days, one honest line beats a split nobody can
    // substantiate.
    if (officeDayCount > 0)
      (
        'Crew cost ($officeDayCount day${officeDayCount == 1 ? '' : 's'} '
            'per office KPI)',
        -officeCrewCost,
      )
    else ...[
      ('Crew daily salary', -crewDaily),
      ('Crew trip share', -crewTripShare),
    ],
    if (approvedExpenses.isNotEmpty)
      ('Approved expenses', -approvedExpensesTotal),
    ('Net due', netDue),
  ];

  /// The part of the crew cost the office entered, for the line above.
  double get officeCrewCost => crewCost - crewDaily - crewTripShare;
}

/// A cost charged to an investor.
///
/// Approval is the point of this class: a figure the office entered still comes
/// out of somebody's payout, so it does not count until the investor has signed
/// it. A pending cost stays visible and simply does not move the number.
class InvestorExpense {
  const InvestorExpense({
    required this.amount,
    required this.category,
    this.approved = false,
    this.tripBookingId,
    this.incurredAt,
    this.reference,
    this.description,
  });

  final double amount;
  final String category;
  final bool approved;
  final String? tripBookingId;
  final DateTime? incurredAt;

  /// The PO or receipt reference, so every deduction can be traced.
  final String? reference;
  final String? description;

  InvestorExpense copyWith({bool? approved}) => InvestorExpense(
    amount: amount,
    category: category,
    approved: approved ?? this.approved,
    tripBookingId: tripBookingId,
    incurredAt: incurredAt,
    reference: reference,
    description: description,
  );
}

/// A single trip on an investor's statement.
class InvestorTripLine {
  const InvestorTripLine({
    required this.bookingId,
    required this.deliveredAt,
    required this.route,
    required this.makeCode,
    required this.amount,
    required this.commission,
  });

  final String bookingId;
  final DateTime? deliveredAt;
  final String route;
  final String makeCode;
  final double amount;
  final double commission;
}
