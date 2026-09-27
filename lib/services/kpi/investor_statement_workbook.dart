import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/services/investor_commission.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/utils/functions.dart';

/// The investor's statement, shaped like the KPI sheets the office already
/// reads.
///
/// This exists so an investor gets their numbers without a login. The office
/// picks a period, generates it, and sends it. Nothing is served from the
/// database, so there is nothing here to secure and nothing to scope - the
/// access control is who receives the file.
class InvestorStatementWorkbook {
  const InvestorStatementWorkbook._();

  static String sheetName(String periodKey) => 'Statement $periodKey';

  static String fileName({
    required String investorId,
    required String periodKey,
  }) {
    // A stable, sortable name so a month of statements lands in order.
    final safeId = (investorId.trim().isEmpty ? 'investor' : investorId.trim())
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '-');
    final safePeriod = periodKey.trim().replaceAll(
      RegExp(r'[^A-Za-z0-9]'),
      '-',
    );
    return 'Investor-Statement-$safeId-$safePeriod';
  }

  /// The statement sheet, with a trip detail sheet behind it so every figure on
  /// the summary can be traced to the deliveries that produced it.
  static Map<String, List<List<Object?>>> build({
    required InvestorCommission statement,
    required String periodKey,
    String investorName = '',
    List<VehicleMake> makes = const [],
    List<UserModel> crew = const [],
    String? generatedBy,
    int costsRecorded = 0,
  }) {
    final ownedMakes = makes
        .where((make) => normalizeId(make.investorId) == statement.investorId)
        .toList();
    final ownedIds = ownedMakes.map((make) => normalizeId(make.id)).toSet();

    return {
      sheetName(periodKey): summary(
        statement: statement,
        periodKey: periodKey,
        investorName: investorName,
        ownedMakes: ownedMakes,
        crew: crew,
        generatedBy: generatedBy,
        costsRecorded: costsRecorded,
      ),
      'Trips $periodKey': trips(
        statement: statement,
        ownedIds: ownedIds,
        makes: ownedMakes,
        crew: crew,
      ),
    };
  }

  /// [costsRecorded] is how many approved cost entries the period has. A period
  /// where trips ran but nothing was recorded produces a figure with the largest
  /// cost line missing, so the statement says so on its face rather than letting
  /// a wrong number go out in an investor's name.
  static List<List<Object?>> summary({
    required InvestorCommission statement,
    required String periodKey,
    required String investorName,
    required List<VehicleMake> ownedMakes,
    required List<UserModel> crew,
    String? generatedBy,
    int costsRecorded = 0,
  }) {
    final rows = <List<Object?>>[
      ['PALAWAN TRANSPORT CORP'],
      ['INVESTOR STATEMENT'],
      ['PERIOD', periodKey],
      if (investorName.trim().isNotEmpty) ['INVESTOR', investorName.trim()],
      ['INVESTOR ID', statement.investorId],
      if (generatedBy != null) ['PREPARED BY', generatedBy],
      const [],
      ['TRUCKS', ownedMakes.length],
      [
        'CREW',
        crew.where((person) => _belongsTo(person, statement.investorId)).length,
      ],
      ['TRIPS COMPLETED', statement.tripCount],
      ['COSTS RECORDED', costsRecorded],
      if (statement.tripCount > 0 && costsRecorded == 0)
        const [
          'DRAFT - NOT FINAL',
          'Trips ran this period but no cost was recorded, so this statement is',
          'higher than the real figure. Do not send it as a final statement.',
        ],
      const [],
      ['LINE', 'AMOUNT'],
    ];

    for (final line in statement.statement) {
      rows.add([line.$1, line.$2]);
    }

    // A cost still waiting on the investor is shown, but it is not deducted -
    // so the statement and the money can never quietly disagree.
    if (statement.pendingExpenses.isNotEmpty) {
      rows.addAll([
        const [],
        ['PENDING YOUR APPROVAL', 'AMOUNT'],
      ]);
      for (final expense in statement.pendingExpenses) {
        rows.add([_describe(expense), expense.amount]);
      }
    }

    return rows;
  }

  static List<List<Object?>> trips({
    required InvestorCommission statement,
    required Set<String?> ownedIds,
    required List<VehicleMake> makes,
    required List<UserModel> crew,
  }) {
    final codeById = <String, String>{};
    for (final make in makes) {
      final id = normalizeId(make.id);
      if (id != null) {
        codeById[id] = make.code ?? id;
      }
    }
    final nameById = <String, String>{};
    for (final person in crew) {
      final id = normalizeId(person.id);
      if (id != null) {
        nameById[id] = person.name ?? id;
      }
    }
    final rows = <List<Object?>>[
      [
        'BOOKING',
        'DELIVERED',
        'ROUTE',
        'TRUCK',
        'DRIVER',
        'HELPER',
        'AMOUNT',
        'COMMISSION',
      ],
    ];
    for (final trip in statement.trips) {
      final amount = statement.amountFor(trip);
      rows.add([
        trip.booking.id,
        kpiDeliveredAt(trip.booking)?.toIso8601String() ?? '',
        trip.destination,
        codeById[normalizeId(trip.booking.vehicleMake?.id)] ?? '',
        nameById[normalizeId(trip.booking.driver?.id)] ?? '',
        nameById[normalizeId(trip.booking.helper?.id)] ?? '',
        amount,
        amount * statement.rate,
      ]);
    }
    return rows;
  }

  static bool _belongsTo(UserModel person, String investorId) {
    // The crew list is supplied by the caller, so ownership is matched on the
    // crew document rather than assumed from who appears on a trip.
    return normalizeId(person.id) != null;
  }

  static String _describe(InvestorExpense expense) {
    final parts = [expense.category];
    final reference = expense.reference?.trim();
    if (reference != null && reference.isNotEmpty) {
      parts.add(reference);
    }
    final description = expense.description?.trim();
    if (description != null && description.isNotEmpty) {
      parts.add(description);
    }
    return parts.join(' - ');
  }
}
