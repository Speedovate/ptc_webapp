import 'package:webapp/constants/palawan_locations.dart';
import 'package:webapp/constants/puerto_princesa_barangays.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';

class TripPaySchedule {
  const TripPaySchedule({
    this.daily = 455,
    this.cityAfter = 4,
    this.cityDriver = 150,
    this.cityHelper = 75,
    this.fullDriver = 100,
    this.fullHelper = 50,
    this.emptyDriver = 50,
    this.emptyHelper = 25,
  });
  final double daily,
      cityDriver,
      cityHelper,
      fullDriver,
      fullHelper,
      emptyDriver,
      emptyHelper;
  final int cityAfter;
  Map<String, dynamic> toMap() => {
    'daily': daily,
    'city_after': cityAfter,
    'city_driver': cityDriver,
    'city_helper': cityHelper,
    'full_driver': fullDriver,
    'full_helper': fullHelper,
    'empty_driver': emptyDriver,
    'empty_helper': emptyHelper,
  };
  factory TripPaySchedule.fromMap(Map data) => TripPaySchedule(
    daily: kpiMoney(data['daily']) ?? 455,
    cityAfter: (data['city_after'] as num?)?.toInt() ?? 4,
    cityDriver: kpiMoney(data['city_driver']) ?? 150,
    cityHelper: kpiMoney(data['city_helper']) ?? 75,
    fullDriver: kpiMoney(data['full_driver']) ?? 100,
    fullHelper: kpiMoney(data['full_helper']) ?? 50,
    emptyDriver: kpiMoney(data['empty_driver']) ?? 50,
    emptyHelper: kpiMoney(data['empty_helper']) ?? 25,
  );
}

class TripMatrixVersion {
  TripMatrixVersion({
    required this.id,
    required this.effectiveFrom,
    required this.rates,
    this.pay = const TripPaySchedule(),
  });
  final String id;
  final DateTime effectiveFrom;
  final List<KpiRate> rates;
  final TripPaySchedule pay;
  Map<String, dynamic> toMap() => {
    'id': id,
    'effective_from': kpiDayKey(effectiveFrom),
    'rates': rates.map((r) => r.toMap()).toList(),
    'pay': pay.toMap(),
  };
  factory TripMatrixVersion.fromMap(Map map) => TripMatrixVersion(
    id: map['id'].toString(),
    effectiveFrom: DateTime.parse('${map['effective_from']}T00:00:00Z'),
    rates: (map['rates'] as List)
        .whereType<Map>()
        .map(KpiRate.fromMap)
        .toList(),
    pay: TripPaySchedule.fromMap(map['pay'] is Map ? map['pay'] as Map : {}),
  );
  static TripMatrixVersion get defaults => TripMatrixVersion(
    id: 'provided-2019',
    effectiveFrom: DateTime.utc(2019),
    rates: KpiRate.matrix,
  );
}

class OperationsCatalog {
  const OperationsCatalog(this.document);
  final Map<String, dynamic> document;
  // Confirmed by PALTRANCO: use the effective City Proper schedule when no
  // explicit named rate exists. Explicit matrix overrides still take priority.
  static const confirmedCityProperLocations = ['Bagong Pag-asa'];
  // Keep the wording already used by booking selectors. Matrix spellings
  // remain aliases so existing bookings and effective rate versions still match.
  static String _bookingLocationName(String name) =>
      switch (name.trim().toLowerCase()) {
        'sta. lourdes' => 'Santa Lourdes',
        'sta. monica' => 'Santa Monica',
        'española' || 'sofronio española' => 'Sofronio Espanola',
        _ => name,
      };

  static OperationLocation _bookingLocation(OperationLocation location) {
    final name = _bookingLocationName(location.name);
    return OperationLocation(
      name,
      location.isCityProperCategory
          ? 'rate_category'
          : location.kind == 'city' &&
                defaultPalawanLocationOptions.any(
                  (n) => n.toLowerCase() == name.toLowerCase(),
                )
          ? _placeKind(name)
          : location.kind,
      active: location.active,
      createdAt: location.createdAt,
      updatedAt: location.updatedAt,
      aliases: unique([
        ...location.aliases,
        if (name != location.name) location.name,
      ]),
    );
  }

  static String _placeKind(String name) =>
      name.trim().toLowerCase() == 'puerto princesa city'
      ? 'city'
      : 'municipality';

  static List<String> unique(Iterable<String> values) {
    final seen = <String>{};
    return values
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && seen.add(s.toLowerCase()))
        .toList()
      ..sort();
  }

  KpiRate? rateFor(OperationLocation location, DateTime day) => matrixFor(day)
      .rates
      .where(
        (r) => [r.name, ...r.aliases].any(
          (n) => [
            location.name,
            ...location.aliases,
          ].any((v) => v.toLowerCase() == n.toLowerCase()),
        ),
      )
      .firstOrNull;

  bool hasActiveRate(OperationLocation location, DateTime day) {
    final rate = rateFor(location, day);
    return location.active &&
        rate != null &&
        rate.active &&
        rate.driver.isFinite &&
        rate.driver >= 0 &&
        rate.helper.isFinite &&
        rate.helper >= 0;
  }

  List<OperationLocation> _matrixOrder(Iterable<OperationLocation> values) {
    int rank(OperationLocation location) {
      final index = KpiRate.matrix.indexWhere(
        (r) => [r.name, ...r.aliases].any(
          (n) => [
            location.name,
            ...location.aliases,
          ].any((v) => n.toLowerCase() == v.toLowerCase()),
        ),
      );
      return index < 0 ? KpiRate.matrix.length : index;
    }

    return values.toList()..sort((a, b) {
      final order = rank(a).compareTo(rank(b));
      return order == 0 ? a.name.compareTo(b.name) : order;
    });
  }

  /// One location identity feeds both booking directions and matrix editing.
  List<OperationLocation> get locations {
    final saved = document['locations'];
    if (saved is List) {
      return _matrixOrder(
        saved
            .whereType<Map>()
            .map(OperationLocation.fromMap)
            .map(_bookingLocation),
      );
    }
    final legacy = document['options'] is Map ? document['options'] as Map : {};
    List<String> values(String key, List<String> fallback) =>
        legacy[key] is List
        ? (legacy[key] as List).whereType<String>().toList()
        : fallback;
    final cityNames = values('cities', defaultPalawanLocationOptions);
    final barangayNames = unique([
      ...values('origin_barangay', defaultPuertoPrincesaBarangayOptions),
      ...values('destination_barangay', defaultPuertoPrincesaBarangayOptions),
    ]);
    final rates = matrixFor(kpiDate(DateTime.now())).rates;
    final retiredNames =
        (document['retired'] is Map ? document['retired'] as Map : {}).values
            .whereType<List>()
            .expand((v) => v.whereType<String>())
            .map((v) => v.toLowerCase())
            .toSet();
    final candidates = unique([
      ...cityNames,
      ...barangayNames,
      ...values('origin', defaultPalawanLocationOptions),
      ...values('destination', defaultPalawanLocationOptions),
      ...rates
          .where(
            (r) => r.active && !retiredNames.contains(r.name.toLowerCase()),
          )
          .map((r) => r.name),
    ]);
    final merged = <String, OperationLocation>{};
    for (final name in candidates) {
      final rate = rates
          .where(
            (r) => [
              r.name,
              ...r.aliases,
            ].any((n) => n.toLowerCase() == name.toLowerCase()),
          )
          .firstOrNull;
      final canonical = _bookingLocationName(rate?.name ?? name);
      final names = [
        canonical,
        name,
        ...?rate?.aliases,
      ].map((n) => n.toLowerCase()).toSet();
      final kind = names.contains('city proper')
          ? 'rate_category'
          : cityNames.any((n) => names.contains(n.toLowerCase()))
          ? _placeKind(canonical)
          : barangayNames.any((n) => names.contains(n.toLowerCase()))
          ? 'barangay'
          : 'location';
      merged[canonical.toLowerCase()] = OperationLocation(
        canonical,
        kind,
        aliases: unique([
          ...?rate?.aliases,
          if (rate != null && rate.name != canonical) rate.name,
          if (name != canonical) name,
          ...?merged[canonical.toLowerCase()]?.aliases,
        ]),
      );
    }
    return _matrixOrder(merged.values);
  }

  Map<String, dynamic> get options {
    final day = kpiDate(DateTime.now());
    final active = locations.where(
      (l) =>
          hasActiveRate(l, day) ||
          // This is the parent selector for the rated Puerto Princesa barangays,
          // not a standalone trip rate or an alias for City Proper.
          (l.active && l.kind == 'city' && l.name == 'Puerto Princesa City'),
    );
    final places = active
        .where((l) => l.kind != 'barangay' && l.kind != 'rate_category')
        .map((l) => l.name)
        .toList();
    final barangays = active
        .where((l) => l.kind == 'barangay')
        .map((l) => l.name)
        .toList();
    return {
      'cities': active
          // Legacy field key includes both types; keep existing flow options.
          .where((l) => l.kind == 'city' || l.kind == 'municipality')
          .map((l) => l.name)
          .toList(),
      'origin': places,
      'destination': places,
      'origin_barangay': barangays,
      'destination_barangay': barangays,
    };
  }

  Map<String, String> labelsFor(DateTime day) => {
    for (final location in locations)
      for (final name in [location.name, ...location.aliases])
        name: locationLabel(location, day, name: name),
  };

  String locationLabel(
    OperationLocation location,
    DateTime day, {
    String? name,
  }) {
    final distance = rateFor(location, day)?.distance;
    final category =
        location.isCityProperCategory ||
            rateFor(location, day)?.usesCityPremium == true
        ? 'CP'
        : distance != null && distance >= 1 && distance <= 7
        ? 'CP'
        : distance != null && distance > 7
        ? 'OT'
        : null;
    final label = name ?? location.name;
    return category == null ? label : '$label | $category';
  }

  Map<String, dynamic> withLocations(List<OperationLocation> values) {
    final former = locations;
    final retiredNames = unique([
      for (final old in former)
        if (!values.any(
          (next) =>
              next.active && next.name.toLowerCase() == old.name.toLowerCase(),
        ))
          old.name,
      for (final next in values) ...next.aliases,
    ]);
    final next = OperationsCatalog({
      ...document,
      'locations': values.map((l) => l.toMap()).toList(),
      'retired': {
        for (final key in [
          'cities',
          'origin',
          'destination',
          'origin_barangay',
          'destination_barangay',
        ])
          key: unique([
            ...(retired[key] as List? ?? []).whereType<String>(),
            ...retiredNames,
          ]),
      },
    });
    // Mirror legacy keys so existing booking readers remain compatible.
    return {...next.document, 'options': next.options};
  }

  Map<String, dynamic> get retired {
    final previous = document['retired'] is Map
        ? document['retired'] as Map
        : {};
    final historicalNames = unique([
      for (final location in locations) location.name,
      for (final location in locations) ...location.aliases,
    ]);
    return {
      for (final key in [
        'cities',
        'origin',
        'destination',
        'origin_barangay',
        'destination_barangay',
      ])
        key: unique([
          ...(previous[key] as List? ?? []).whereType<String>(),
          ...historicalNames,
        ]),
    };
  }

  List<TripMatrixVersion> get versions => [
    TripMatrixVersion.defaults,
    if (document['matrix_versions'] is List)
      ...(document['matrix_versions'] as List).whereType<Map>().map(
        TripMatrixVersion.fromMap,
      ),
  ];
  TripMatrixVersion matrixFor(DateTime day) {
    final applicable =
        versions.where((v) => !v.effectiveFrom.isAfter(day)).toList()
          ..sort((a, b) {
            final d = a.effectiveFrom.compareTo(b.effectiveFrom);
            return d != 0 ? d : a.id.compareTo(b.id);
          });
    final base = applicable.isEmpty
        ? TripMatrixVersion.defaults
        : applicable.last;
    final city = base.rates
        .where((r) => r.name == 'City Proper' && r.active)
        .firstOrNull;
    if (city == null) return base;
    final learned = unique([
      ...confirmedCityProperLocations,
      ...(document['city_proper_locations'] as List? ?? const [])
          .whereType<String>(),
    ]);
    return TripMatrixVersion(
      id: base.id,
      effectiveFrom: base.effectiveFrom,
      pay: base.pay,
      rates: [
        ...base.rates,
        for (final name in learned)
          if (!base.rates.any(
            (r) => [r.name, ...r.aliases].any(
              (alias) =>
                  normalizeKpiLocation(alias) == normalizeKpiLocation(name),
            ),
          ))
            KpiRate(name, city.driver, city.helper, cityProper: true),
      ],
    );
  }

  KpiDay resolveSalary(KpiDay day, Set<String> issues) {
    if (day.salaryComplete) {
      return day;
    }
    final matrix = matrixFor(day.date);
    final trips = [...day.trips]
      ..sort((a, b) {
        final order = kpiDeliveredAt(
          a.booking,
        )!.compareTo(kpiDeliveredAt(b.booking)!);
        return order == 0 ? a.identity.compareTo(b.identity) : order;
      });
    final routes = <String, String>{};
    final savedRates = (day.record['trip_rates'] as List? ?? const [])
        .whereType<Map>();
    var complete = true;
    for (final trip in trips) {
      // A saved choice belongs only to this exact trip version. Do not reuse
      // it after a route, delivery date, or crew change changes the signature.
      final savedRoute = savedRates
          .where((rate) => rate['signature'] == trip.signature)
          .map((rate) => rate['route']?.toString())
          .whereType<String>()
          .firstOrNull;
      final selectedRate = matrix.rates
          .where((rate) => rate.name == savedRoute)
          .firstOrNull;
      final match = matchKpiTripRate(trip, matrix.rates);
      if (selectedRate != null) {
        routes[trip.identity] = selectedRate.name;
      } else if (match.rate == null) {
        issues.add(
          'Booking ${trip.booking.id ?? trip.identity}: ${match.issue}',
        );
        complete = false;
      } else {
        routes[trip.identity] = match.rate!.name;
      }
      if ((trip.booking.driver?.id?.isEmpty ?? true) ||
          (trip.booking.helper?.id?.isEmpty ?? true)) {
        issues.add(
          'Booking ${trip.booking.id ?? trip.identity}: Driver or Helper missing',
        );
        complete = false;
      }
    }
    // Missing data on one trip must not erase pay earned on other trips.
    // Keep incomplete totals explicit, and never invent a crew assignment.
    final payableTrips = trips
        .where(
          (trip) =>
              (trip.booking.driver?.id?.isNotEmpty ?? false) &&
              (trip.booking.helper?.id?.isNotEmpty ?? false),
        )
        .toList();
    final pay = matrix.pay;
    final salary = kpiSalary(
      payableTrips,
      routes,
      matrix: matrix.rates,
      dailyRate: pay.daily,
      cityAfter: pay.cityAfter,
      cityDriverRate: pay.cityDriver,
      cityHelperRate: pay.cityHelper,
      fullDriverRate: pay.fullDriver,
      fullHelperRate: pay.fullHelper,
      emptyDriverRate: pay.emptyDriver,
      emptyHelperRate: pay.emptyHelper,
      fulls: int.tryParse('${day.record['hustling_fulls'] ?? 0}') ?? 0,
      empties: int.tryParse('${day.record['hustling_empties'] ?? 0}') ?? 0,
    );
    return KpiDay(
      day.date,
      day.trips,
      day.record,
      estimate: KpiSalaryEstimate(
        complete: complete,
        driver: salary.driver,
        helper: salary.helper,
        dailyRate: pay.daily,
        rates: salary.rates,
      ),
    );
  }

  Map<String, dynamic> changeOptions(String group, List<String> values) {
    final barangay = group.endsWith('_barangay');
    bool included(OperationLocation l) => barangay
        ? l.kind == 'barangay'
        : group == 'cities'
        ? l.kind == 'city' || l.kind == 'municipality'
        : l.kind != 'barangay' && l.kind != 'rate_category';
    final normalized = unique(values);
    return withLocations([
      for (final location in locations)
        if (!included(location))
          location
        else if (!normalized.any(
          (n) => n.toLowerCase() == location.name.toLowerCase(),
        ))
          OperationLocation(
            location.name,
            location.kind,
            active: false,
            aliases: location.aliases,
            createdAt: location.createdAt,
            updatedAt: location.updatedAt,
          ),
      for (final name in normalized)
        locations
                .where((l) => l.name.toLowerCase() == name.toLowerCase())
                .firstOrNull
                ?.copyActive(true) ??
            OperationLocation(
              name,
              barangay
                  ? 'barangay'
                  : group == 'cities'
                  ? _placeKind(name)
                  : 'location',
            ),
    ]);
  }
}

class OperationLocation {
  const OperationLocation(
    this.name,
    this.kind, {
    this.active = true,
    this.aliases = const [],
    this.createdAt,
    this.updatedAt,
  });
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String name;
  final String kind;
  final bool active;
  final List<String> aliases;
  bool get isCityProperCategory => [
    name,
    ...aliases,
  ].any((value) => value.trim().toLowerCase() == 'city proper');
  String get kindLabel => switch (kind) {
    'rate_category' => 'Rate Category',
    'city' => 'City',
    'municipality' => 'Municipality',
    'barangay' => 'Barangay',
    _ => 'Area / Route',
  };
  OperationLocation copyActive(bool value, {DateTime? updatedAt}) =>
      OperationLocation(
        name,
        kind,
        active: value,
        aliases: aliases,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  Map<String, dynamic> toMap() => {
    'name': name,
    'kind': kind,
    'active': active,
    'aliases': aliases,
    if (createdAt != null) 'created_at': createdAt!.toUtc().toIso8601String(),
    if (updatedAt != null) 'updated_at': updatedAt!.toUtc().toIso8601String(),
  };
  factory OperationLocation.fromMap(Map map) => OperationLocation(
    map['name'].toString(),
    createdAt: DateTime.tryParse('${map['created_at']}'),
    updatedAt: DateTime.tryParse('${map['updated_at']}'),
    map['kind']?.toString() ?? 'location',
    active: map['active'] != false,
    aliases: (map['aliases'] as List? ?? []).whereType<String>().toList(),
  );
}
