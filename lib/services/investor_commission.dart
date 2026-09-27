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
    required List<InvestorExpense> expenses,
  }) : _expenses = expenses;

  factory InvestorCommission.calculate({
    required String investorId,
    required String periodKey,
    required double rate,
    required List<KpiTrip> trips,
    required Map<String, String> routes,
    List<VehicleMake> makes = const [],
    List<InvestorExpense> expenses = const [],
    List<KpiRate> matrix = KpiRate.matrix,
    double dailyRate = 455,
  }) {
    // Ownership comes from the canonical make record, never from the copy
    // embedded in the booking. A booking cached before investors existed
    // carries a make with no investor_id on it, and trusting that copy would
    // silently drop a real trip off an investor's statement.
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
      return InvestorScope.investorForMake(makesById[id] ?? embedded) ==
          investorId;
    }).toList();

    final salary = kpiSalary(
      ownedTrips,
      routes,
      matrix: matrix,
      dailyRate: dailyRate,
    );
    // kpiSalary reports one combined figure. The statement shows daily and
    // per-trip separately, because they scale differently: the daily is flat
    // per person per day, the trip share follows the route.
    final people = <String>{};
    for (final trip in ownedTrips) {
      for (final id in [trip.booking.driver?.id, trip.booking.helper?.id]) {
        final normalized = normalizeId(id);
        if (normalized != null) {
          people.add(normalized);
        }
      }
    }
    final daily = dailyRate * people.length;
    // kpiSalary's driver/helper totals already contain both the daily and the
    // per-trip part, so the trip share is the rates list on its own. Deriving it
    // from the combined total as well would count it twice and quietly hand the
    // trip share back to the investor.
    final tripShare = salary.rates.fold<double>(
      0,
      (sum, row) =>
          sum + ((row['driver'] as num?) ?? 0) + ((row['helper'] as num?) ?? 0),
    );
    // Reconcile rather than trust. If the rate card ever changes shape, this
    // fails here instead of producing a plausible-looking statement.
    final combined = salary.driver + salary.helper;
    final expected = daily + tripShare;
    if ((combined - expected).abs() > 0.005) {
      throw StateError(
        'Crew cost does not reconcile: $combined reported against $expected.',
      );
    }

    return InvestorCommission._(
      investorId: investorId,
      periodKey: periodKey,
      rate: rate,
      trips: ownedTrips,
      crewDaily: daily,
      crewTripShare: tripShare,
      expenses: expenses,
    );
  }

  final String investorId;
  final String periodKey;
  final double rate;
  final List<KpiTrip> trips;
  final double crewDaily;
  final double crewTripShare;
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
  double get netDue =>
      investorPool - crewDaily - crewTripShare - approvedExpensesTotal;

  /// The full line-by-line breakdown, in the order an investor reads it.
  List<(String, double)> get statement => [
    ('Gross billings', grossBillings),
    ('Paltranco share (${(rate * 100).toStringAsFixed(0)}%)', -platformFee),
    ('Crew daily salary', -crewDaily),
    ('Crew trip share', -crewTripShare),
    if (approvedExpenses.isNotEmpty)
      ('Approved expenses', -approvedExpensesTotal),
    ('Net due', netDue),
  ];
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
