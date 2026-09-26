import 'kpi_rating_rules.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/services/booking_pm_assignment.dart';
import 'package:webapp/services/kpi/kpi_cost_override.dart';
import 'dart:convert';

import 'package:webapp/models/booking.dart';
import 'package:webapp/widgets/shared/booking_record_card.dart';

/// Calendar dates in PALTRANCO's operating timezone, independent of browser TZ.
DateTime kpiDate(DateTime value) {
  final date = value.toUtc().add(const Duration(hours: 8));
  return DateTime.utc(date.year, date.month, date.day);
}

String kpiDayKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class KpiPeriod {
  KpiPeriod(this.start, this.end) {
    if (end.isBefore(start)) {
      throw ArgumentError('End must not precede start');
    }
  }
  factory KpiPeriod.month(int year, int month) =>
      KpiPeriod(DateTime.utc(year, month), DateTime.utc(year, month + 1, 0));
  factory KpiPeriod.week(int year, int month, int week) {
    if (week < 1 || week > 4) {
      throw ArgumentError.value(week);
    }
    return KpiPeriod(
      DateTime.utc(year, month, (week - 1) * 7 + 1),
      week == 4
          ? DateTime.utc(year, month + 1, 0)
          : DateTime.utc(year, month, week * 7),
    );
  }
  final DateTime start;
  final DateTime end;
  bool contains(DateTime day) => !day.isBefore(start) && !day.isAfter(end);
  Iterable<DateTime> get days sync* {
    for (
      var day = start;
      !day.isAfter(end);
      day = day.add(const Duration(days: 1))
    ) {
      yield day;
    }
  }

  /// A partial custom range consumes a fraction of each business week.
  double get weeks => days.fold(0, (total, day) {
    final length = day.day <= 21
        ? 7
        : DateTime.utc(day.year, day.month + 1, 0).day - 21;
    return total + 1 / length;
  });
}

class KpiRate {
  const KpiRate(
    this.name,
    this.driver,
    this.helper, {
    this.distance,
    this.aliases = const [],
    this.active = true,
    this.cityProper,
  });
  final double? distance;
  final List<String> aliases;
  final bool active;
  final bool? cityProper;
  bool get usesCityPremium => cityProper ?? name == 'City Proper';
  Map<String, dynamic> toMap() => {
    'name': name,
    'driver': driver,
    'helper': helper,
    'distance': distance,
    'aliases': aliases,
    'active': active,
    'city_proper': usesCityPremium,
  };
  factory KpiRate.fromMap(Map map) => KpiRate(
    map['name'].toString(),
    kpiMoney(map['driver']) ?? 0,
    kpiMoney(map['helper']) ?? 0,
    distance: kpiMoney(map['distance']),
    aliases: (map['aliases'] as List? ?? []).whereType<String>().toList(),
    active: map['active'] != false,
    cityProper: map['city_proper'] as bool?,
  );
  final String name;
  final double driver;
  final double helper;
  static const matrix = <KpiRate>[
    KpiRate('City Proper', 100, 50),
    KpiRate('San Manuel', 100, 50, distance: 8),
    KpiRate('San Jose', 100, 50, distance: 8),
    KpiRate('Tagburos', 100, 50, distance: 13),
    KpiRate('Sta. Lourdes', 100, 50, distance: 15, aliases: ['Santa Lourdes']),
    KpiRate('San Rafael', 200, 100, distance: 61),
    KpiRate('Sabang', 500, 250, distance: 83),
    KpiRate('Roxas', 600, 300, distance: 142),
    KpiRate('San Vicente', 700, 350, distance: 167),
    KpiRate('Taytay', 700, 350, distance: 167),
    KpiRate('El Nido', 1000, 500, distance: 282),
    KpiRate('Sta. Monica', 100, 50, distance: 6, aliases: ['Santa Monica']),
    KpiRate('Sicsican', 100, 50, distance: 10),
    KpiRate('Irawan', 100, 50, distance: 13),
    KpiRate('Inagawan', 150, 50, distance: 57),
    KpiRate('Aborlan', 400, 200, distance: 69),
    KpiRate('Narra', 500, 250, distance: 93),
    KpiRate(
      'Española',
      700,
      350,
      distance: 164,
      aliases: ['Sofronio Espanola', 'Sofronio Española'],
    ),
    KpiRate('Quezon', 700, 350, distance: 164),
    KpiRate('Berong', 800, 400, distance: 194),
    KpiRate('Rizal', 800, 400, distance: 209),
    KpiRate("Brooke's Point", 700, 350, distance: 192),
    KpiRate('Bataraza', 800, 400, distance: 227),
    KpiRate('Rio Tuba', 1000, 500, distance: 257),
    KpiRate('Buliluyan', 1000, 500, distance: 296),
  ];
}

double? kpiMoney(dynamic value) {
  final text = value?.toString().replaceAll(',', '').replaceAll('₱', '').trim();
  final amount = text == null ? null : double.tryParse(text);
  return amount != null && amount.isFinite && amount >= 0 ? amount : null;
}

class KpiTrip {
  KpiTrip(this.booking, this.day);
  final Booking booking;
  final DateTime day;
  String get identity => (booking.submissionKey?.trim().isNotEmpty ?? false)
      ? booking.submissionKey!
      : booking.id ?? '';
  String get destination => BookingRecordCard.outputFieldDisplayValue(
    booking.statusOutputs,
    'destination',
  );
  String get origin => BookingRecordCard.outputFieldDisplayValue(
    booking.statusOutputs,
    'origin',
  );
  String get originBarangay => BookingRecordCard.outputFieldDisplayValue(
    booking.statusOutputs,
    'origin_barangay',
  );
  String get destinationBarangay => BookingRecordCard.outputFieldDisplayValue(
    booking.statusOutputs,
    'destination_barangay',
  );
  String get signature => jsonEncode([
    identity,
    booking.deliveredAt?.toUtc().toIso8601String(),
    kpiDayKey(day),
    booking.driver?.id,
    booking.helper?.id,
    destination,
    booking.chassisId,
    origin,
    originBarangay,
    destinationBarangay,
  ]);
}

String normalizeKpiLocation(String value) => value
    .trim()
    .toLowerCase()
    .replaceFirst(RegExp(r'\s*\|\s*(cp|ot)\s*$'), '')
    .replaceAll('ñ', 'n')
    .replaceAll(RegExp(r'\bsta\.?\s+'), 'santa ')
    .replaceFirst(RegExp(r'^(barangay|brgy\.?)\s+'), '')
    .replaceAll(RegExp(r'[^a-z0-9]'), '');

({KpiRate? rate, String? issue}) matchKpiTripRate(
  KpiTrip trip,
  List<KpiRate> rates,
) {
  List<KpiRate> matches(String value) {
    final key = normalizeKpiLocation(value);
    if (key.isEmpty) return [];
    return rates
        .where(
          (r) =>
              r.active &&
              [
                r.name,
                ...r.aliases,
              ].any((name) => normalizeKpiLocation(name) == key),
        )
        .toList();
  }

  final destination = matches(trip.destination);
  final barangay = matches(trip.destinationBarangay);
  final candidates = <KpiRate>{...destination, ...barangay};
  if (candidates.length == 1) {
    return (rate: candidates.single, issue: null);
  }
  return (
    rate: null,
    issue: candidates.isEmpty
        ? 'No active trip rate for drop-off: ${trip.destinationBarangay == '-' || trip.destinationBarangay.isEmpty ? trip.destination : '${trip.destinationBarangay}, ${trip.destination}'}'
        : 'Multiple active trip rates match drop-off ${trip.destination} / ${trip.destinationBarangay}: ${candidates.map((r) => r.name).join(', ')}',
  );
}

class KpiSalaryEstimate {
  const KpiSalaryEstimate({
    required this.driver,
    required this.helper,
    required this.dailyRate,
    required this.rates,
    this.complete = true,
  });
  final double driver, helper, dailyRate;
  final List<Map<String, dynamic>> rates;
  final bool complete;
}

DateTime? kpiDeliveredAt(Booking booking) {
  if (booking.deliveredAt != null) {
    return booking.deliveredAt;
  }
  DateTime? first;
  for (final entry in (booking.statusOutputs ?? <String, dynamic>{}).entries) {
    final raw = entry.value;
    if (raw is! Map) {
      continue;
    }
    final form = raw['status_form'];
    final stage =
        ((form is Map ? form['next_status_key'] : null) ??
                raw['status_key'] ??
                entry.key.split('__').first)
            .toString()
            .toLowerCase();
    if (stage != 'delivered') {
      continue;
    }
    final date = DateTime.tryParse(
      (raw['submitted_at'] ?? raw['created_at'] ?? '').toString(),
    );
    if (date != null && (first == null || date.isBefore(first))) {
      first = date;
    }
  }
  return first;
}

/// How much of a crew member's assigned work actually got delivered.
///
/// Both sides are anchored to the same date - the delivery date when the trip
/// reached delivery, otherwise the date it was created - so a booking can only
/// ever be counted once and `delivered` can never exceed `total`.
({int delivered, int total}) kpiBookingProgress(
  Iterable<Map<String, dynamic>> bookings, {
  required KpiPeriod period,
  String? role,
  String? userId,
  DateTime? now,
}) {
  final today = kpiDate(now ?? DateTime.now());
  var delivered = 0;
  var total = 0;
  for (final raw in bookings) {
    // A stale or shared snapshot must never let one crew member's trip count as
    // another's, so the assignment is re-checked here rather than trusted.
    if (role != null && userId != null && userId.isNotEmpty) {
      final assigned = raw['${role}_id']?.toString().trim() ?? '';
      if (assigned != userId) continue;
    }
    final booking = Booking.fromMap(raw);
    final deliveredAt = kpiDeliveredAt(booking);
    final date = kpiDate(
      deliveredAt ??
          booking.createdAt ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
    if (date.isAfter(today) || !period.contains(date)) continue;
    total++;
    if (deliveredAt != null ||
        Booking.isDeliveredWorkflowStatus(booking.clientStatus)) {
      delivered++;
    }
  }
  return (delivered: delivered, total: total);
}

class KpiDay {
  KpiDay(this.date, this.trips, this.record, {this.estimate});
  final KpiSalaryEstimate? estimate;
  bool get salaryEstimated => !salaryComplete && estimate != null;
  bool get salaryCalculated => salaryComplete || estimate?.complete == true;
  final DateTime date;
  final List<KpiTrip> trips;
  final Map<String, dynamic> record;
  String get signature {
    final signatures = trips.map((t) => t.signature).toList()..sort();
    return jsonEncode(signatures);
  }

  bool get fuelComplete =>
      record['fuel_confirmed'] == true &&
      kpiMoney(record['fuel']) != null &&
      (record['fuel_source'] != 'ledger' ||
          record['fuel_signature'] == record['fuel_signature_live']);
  bool get salaryComplete =>
      record['salary_confirmed'] == true &&
      record['trip_signature'] == signature &&
      kpiMoney(record['driver_salary']) != null &&
      kpiMoney(record['helper_salary']) != null &&
      trips.every(
        (t) =>
            (t.booking.driver?.id?.isNotEmpty ?? false) &&
            (t.booking.helper?.id?.isNotEmpty ?? false),
      );
  double get fuel => kpiMoney(record['fuel']) ?? 0;
  double get driverSalary => salaryComplete
      ? kpiMoney(record['driver_salary'])!
      : estimate?.driver ?? 0;
  double get helperSalary => salaryComplete
      ? kpiMoney(record['helper_salary'])!
      : estimate?.helper ?? 0;
}

class PmKpi {
  PmKpi({
    required this.period,
    required this.days,
    required this.revenue,
    required this.bookingCount,
    required this.issues,
    required this.threshold,
    this.ratingRules = const KpiRatingRules(),
    this.costOverrides = const {},
  });
  final KpiPeriod period;

  /// Period cost overrides keyed by 'maintenance' / 'depreciation'. A record
  /// only takes effect once approved, so a pending figure never moves money.
  final Map<String, Map<String, dynamic>> costOverrides;
  final List<KpiDay> days;
  final double revenue;
  final int bookingCount;
  final Set<String> issues;
  final double threshold;
  final KpiRatingRules ratingRules;
  double get fuel => days.fold(0, (sum, d) => sum + d.fuel);
  double get driverSalary => days.fold(0, (sum, d) => sum + d.driverSalary);
  double get helperSalary => days.fold(0, (sum, d) => sum + d.helperSalary);

  /// The company buffers. Years of real experience, so they remain the default.
  double get depreciationBuffer => period.weeks * 12500;
  double get maintenanceBuffer => period.weeks * 14500;

  /// A resolved figure, and whether it is a real number or the buffer. Both are
  /// surfaced so a reader is never shown an estimate dressed as a fact.
  ({double amount, bool isEstimate}) depreciationCost() =>
      _cost(depreciationBuffer, 'depreciation');
  ({double amount, bool isEstimate}) maintenanceCost() =>
      _cost(maintenanceBuffer, 'maintenance');

  double get depreciation => depreciationCost().amount;
  double get maintenance => maintenanceCost().amount;
  bool get depreciationEstimated => depreciationCost().isEstimate;
  bool get maintenanceEstimated => maintenanceCost().isEstimate;

  ({double amount, bool isEstimate}) _cost(double buffer, String key) {
    final record = costOverrides[key];
    return (
      amount: resolveKpiCost(bufferAmount: buffer, overrideRecord: record),
      isEstimate: kpiCostIsEstimate(record),
    );
  }

  double get expenses =>
      fuel + driverSalary + helperSalary + depreciation + maintenance;
  double get gross => revenue - expenses;
  double get revenueTarget => period.weeks * (350000 / 4);
  double get profitTarget => revenueTarget * ratingRules.targetPercent / 100;
  double get marginTarget => revenue * ratingRules.targetPercent / 100;
  double get marginVariance => gross - marginTarget;
  bool get complete =>
      issues.isEmpty && days.every((d) => d.fuelComplete && d.salaryCalculated);
  String get rating =>
      ratingRules.grossRating(revenue, gross, complete: complete);

  static PmKpi calculate({
    required String makeId,
    required KpiPeriod period,
    required List<Booking> bookings,
    required List<Map<String, dynamic>> records,
    double threshold = 10000,
    KpiRatingRules ratingRules = const KpiRatingRules(),
    List<Map<String, dynamic>> fuelEntries = const [],
    KpiDay Function(KpiDay day, Set<String> issues)? resolveSalary,
    List<VehicleMake> makes = const [],
    Map<String, Map<String, dynamic>> costOverrides = const {},
  }) {
    final issues = <String>{};
    final unique = <String, Booking>{};
    for (final b in bookings) {
      final status = b.clientStatus?.trim().toLowerCase() ?? '';
      final reachedDelivery =
          Booking.isDeliveredWorkflowStatus(status) ||
          ((status.isEmpty || status == 'cancelled') &&
              kpiDeliveredAt(b) != null);
      if (!reachedDelivery) {
        continue;
      }
      final pm = resolveBookingPm(b, makes);
      if (pm == null) {
        final delivered = kpiDeliveredAt(b);
        final reachedDelivery =
            delivered != null ||
            Booking.isDeliveredWorkflowStatus(b.clientStatus);
        final date = delivered ?? b.createdAt;
        if (reachedDelivery && date != null && period.contains(kpiDate(date))) {
          issues.add('Booking ${b.id}: ${bookingPmAssignmentIssue(b, makes)}');
        }
        continue;
      }
      if (pm.id != makeId) {
        continue;
      }
      final key = (b.submissionKey?.isNotEmpty ?? false)
          ? b.submissionKey!
          : b.id;
      if (key == null || key.isEmpty) {
        issues.add('Booking identity missing');
        continue;
      }
      final previous = unique[key];
      if (previous != null &&
          (previous.createdAt != b.createdAt ||
              previous.driver?.id != b.driver?.id ||
              previous.helper?.id != b.helper?.id ||
              BookingRecordCard.outputFieldDisplayValue(
                    previous.statusOutputs,
                    'amount',
                  ) !=
                  BookingRecordCard.outputFieldDisplayValue(
                    b.statusOutputs,
                    'amount',
                  ))) {
        issues.add('Booking identity conflict: $key');
      }
      if (previous == null ||
          (b.updatedAt ?? DateTime(1900)).isAfter(
            previous.updatedAt ?? DateTime(1900),
          )) {
        unique[key] = b;
      }
    }
    var revenue = 0.0;
    var count = 0;
    final trips = <String, List<KpiTrip>>{};
    for (final b in unique.values) {
      final created = b.createdAt;
      if (created == null) {
        issues.add('Booking ${b.id}: Created date missing');
      }
      final cancelled = b.clientStatus?.toLowerCase() == 'cancelled';
      if (!cancelled && created != null && period.contains(kpiDate(created))) {
        count++;
        final amount = kpiMoney(
          BookingRecordCard.outputFieldValue(b.statusOutputs, 'amount'),
        );
        if (amount == null) {
          issues.add('Booking ${b.id}: amount missing');
        } else {
          revenue += amount;
        }
        if ((b.localSyncStatus ?? '').isNotEmpty) {
          issues.add('Bookings awaiting sync');
        }
      }
      final delivered = kpiDeliveredAt(b);
      if (delivered == null &&
          Booking.isDeliveredWorkflowStatus(b.clientStatus)) {
        issues.add('Booking ${b.id}: Delivered date missing');
      }
      if (delivered != null && period.contains(kpiDate(delivered))) {
        if (cancelled) {
          issues.add(
            'Booking ${b.id}: cancelled after delivery; review earned salary',
          );
        }
        final day = kpiDate(delivered);
        trips.putIfAbsent(kpiDayKey(day), () => []).add(KpiTrip(b, day));
        if ((b.localSyncStatus ?? '').isNotEmpty) {
          issues.add('Delivered trips awaiting sync');
        }
      }
    }
    final byDay = {
      for (final r in records)
        if (r['make_id'] == makeId && r['day'] != null) r['day'].toString(): r,
    };
    final fuelByDay = <String, List<Map<String, dynamic>>>{};
    for (final entry in fuelEntries.where((e) => e['make_id'] == makeId)) {
      fuelByDay.putIfAbsent(entry['day'].toString(), () => []).add(entry);
    }
    for (final entry in fuelByDay.entries) {
      final records = entry.value
        ..sort((a, b) => a['id'].toString().compareTo(b['id'].toString()));
      final signature = jsonEncode(
        records
            .map((r) => [r['id'], r['updated_at'], r['amount'], r['voided']])
            .toList(),
      );
      var total = 0.0;
      for (final fuel in records) {
        if (fuel['voided'] != true) {
          total += kpiMoney(fuel['amount']) ?? 0;
        }
      }
      final previous = byDay[entry.key] ?? <String, dynamic>{};
      byDay[entry.key] = {
        ...previous,
        'fuel': total,
        'fuel_source': 'ledger',
        'fuel_signature_live': signature,
      };
      final date = DateTime.tryParse('${entry.key}T00:00:00Z');
      if (date != null && period.contains(date)) {
        if (records.any((r) => r['local_sync_status'] != null)) {
          issues.add('Fuel entries awaiting sync');
        }
        if (records.any((r) => kpiMoney(r['amount']) == null)) {
          issues.add('Invalid fuel entry amount');
        }
      }
    }
    final rawDays = [
      for (final day in period.days)
        KpiDay(day, trips[kpiDayKey(day)] ?? [], byDay[kpiDayKey(day)] ?? {}),
    ];
    final days = [
      for (final day in rawDays)
        resolveSalary == null ? day : resolveSalary(day, issues),
    ];
    for (final d in days) {
      if (d.record['local_sync_status'] != null) {
        issues.add('KPI changes awaiting sync');
      }
    }
    final bookingStatuses = <String, String>{};
    for (final booking in bookings) {
      final raw = booking.clientStatus?.trim() ?? '';
      final words = raw
          .replaceAll('_', ' ')
          .split(' ')
          .where((word) => word.isNotEmpty);
      bookingStatuses[booking.id ?? ''] = raw.isEmpty
          ? 'Not recorded'
          : words
                .map(
                  (word) =>
                      '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
                )
                .join(' ');
    }
    final issueBooking = RegExp(r'^Booking ([^:]+):');
    final detailedIssues = {
      for (final issue in issues)
        if (issueBooking.firstMatch(issue) case final match?
            when bookingStatuses.containsKey(match.group(1)))
          '$issue [Status: ${bookingStatuses[match.group(1)] ?? 'Not recorded'}]'
        else
          issue,
    };
    return PmKpi(
      period: period,
      days: days,
      revenue: revenue,
      bookingCount: count,
      issues: detailedIssues,
      threshold: threshold,
      ratingRules: ratingRules,
      costOverrides: costOverrides,
    );
  }
}

({double driver, double helper, List<Map<String, dynamic>> rates}) kpiSalary(
  List<KpiTrip> trips,
  Map<String, String> routes, {
  int fulls = 0,
  int empties = 0,
  List<KpiRate> matrix = KpiRate.matrix,
  double dailyRate = 455,
  int cityAfter = 4,
  double cityDriverRate = 150,
  double cityHelperRate = 75,
  double fullDriverRate = 100,
  double fullHelperRate = 50,
  double emptyDriverRate = 50,
  double emptyHelperRate = 25,
}) {
  final driverDays = trips
      .map((t) => t.booking.driver?.id)
      .whereType<String>()
      .toSet()
      .length;
  final helperDays = trips
      .map((t) => t.booking.helper?.id)
      .whereType<String>()
      .toSet()
      .length;
  var driver = dailyRate * driverDays;
  var helper = dailyRate * helperDays;
  final cityDriver = <String?, int>{};
  final cityHelper = <String?, int>{};
  final rates = <Map<String, dynamic>>[];
  for (final trip in trips) {
    final rate = matrix
        .where((r) => r.name == routes[trip.identity])
        .firstOrNull;
    if (rate == null) {
      continue;
    }
    var d = rate.driver;
    var h = rate.helper;
    if (rate.usesCityPremium) {
      final did = trip.booking.driver?.id;
      final hid = trip.booking.helper?.id;
      cityDriver[did] = (cityDriver[did] ?? 0) + 1;
      cityHelper[hid] = (cityHelper[hid] ?? 0) + 1;
      if (cityDriver[did]! > cityAfter) {
        d = cityDriverRate;
      }
      if (cityHelper[hid]! > cityAfter) {
        h = cityHelperRate;
      }
    }
    driver += d;
    helper += h;
    rates.add({
      'signature': trip.signature,
      'booking_id': int.tryParse(trip.booking.id ?? '') != null
          ? trip.booking.id
          : null,
      'booking_submission_key': trip.booking.submissionKey,
      'driver_id': trip.booking.driver?.id,
      'helper_id': trip.booking.helper?.id,
      'chassis_id': trip.booking.chassisId,
      'route': rate.name,
      'driver': d,
      'helper': h,
    });
  }
  driver += fulls * fullDriverRate + empties * emptyDriverRate;
  helper += fulls * fullHelperRate + empties * emptyHelperRate;
  return (driver: driver, helper: helper, rates: rates);
}
