import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/constants/palawan_locations.dart';
import 'package:webapp/constants/puerto_princesa_barangays.dart';
import 'package:webapp/services/kpi/location_option_registry.dart';
import 'package:webapp/services/kpi/operations_catalog.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/services/status_field_option_resolver.dart';

void main() {
  test(
    'location timestamps survive normalization, serialization and activation',
    () {
      final created = DateTime.utc(2026, 9, 22, 1);
      final updated = DateTime.utc(2026, 9, 22, 2);
      final location = OperationLocation(
        'Sta. Monica',
        'barangay',
        createdAt: created,
        updatedAt: created,
      );
      final catalog = OperationsCatalog({
        'locations': [location.toMap()],
      });
      final edited = catalog.locations.single.copyActive(
        false,
        updatedAt: updated,
      );
      final restored = OperationLocation.fromMap(edited.toMap());
      expect(restored.name, 'Santa Monica');
      expect(restored.createdAt, created);
      expect(restored.updatedAt, updated);
      expect(restored.active, false);
      expect(OperationLocation.fromMap({'name': 'Legacy'}).createdAt, isNull);
    },
  );
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => LocationOptionRegistry.apply({}, {}));
  test(
    'hydrated booking fields do not append historical values to selectable options',
    () {
      const catalog = OperationsCatalog({});
      LocationOptionRegistry.apply(catalog.options, catalog.retired);
      final fields = StatusFieldOptionResolver()
          .hydrateFieldsFromResolvedSnapshots([
            const StatusField(
              key: 'origin_barangay',
              type: 'dropdown',
              options: ['Bacungan', 'San Jose', 'San Manuel'],
            ),
            const StatusField(
              key: 'destination',
              type: 'dropdown',
              options: ['Agutaya', 'Roxas'],
            ),
          ]);
      expect(fields.first.options, barangayOptionsFor('origin_barangay'));
      expect(fields.first.options, isNot(contains('Bacungan')));
      expect(fields.last.options, locationOptionsFor('destination'));
      expect(fields.last.options, isNot(contains('Agutaya')));
    },
  );
  test(
    'cold-start dropdowns use matrix order and exclude unpriced defaults',
    () {
      LocationOptionRegistry.apply({}, {});
      expect(locationOptionsFor('origin').take(5), [
        'Sabang',
        'Roxas',
        'San Vicente',
        'Taytay',
        'El Nido',
      ]);
      expect(barangayOptionsFor('destination_barangay'), [
        'San Manuel',
        'San Jose',
        'Tagburos',
        'Santa Lourdes',
        'San Rafael',
        'Santa Monica',
        'Sicsican',
        'Irawan',
        'Inagawan',
        'Bagong Pag-asa',
      ]);
      expect(locationOptionsFor('destination'), isNot(contains('Agutaya')));
      expect(
        barangayOptionsFor('origin_barangay'),
        isNot(contains('Bacungan')),
      );
      expect(locationOptionsFor('origin'), isNot(contains('City Proper')));
      expect(locationOptionsFor('origin'), contains('Puerto Princesa City'));
      expect(isValidPalawanLocationOption('Agutaya'), isTrue);
    },
  );
  test('City Proper is a rate category, never a selectable location', () {
    for (final c in [
      const OperationsCatalog({}),
      OperationsCatalog({
        'locations': [
          const OperationLocation('City Proper', 'location').toMap(),
          const OperationLocation('Puerto Princesa City', 'city').toMap(),
        ],
      }),
    ]) {
      expect(
        c.locations.singleWhere((l) => l.name == 'City Proper').kind,
        'rate_category',
      );
      for (final options in c.options.values) {
        expect(options, isNot(contains('City Proper')));
      }
      expect(c.options['origin'], contains('Puerto Princesa City'));
      expect(
        c.matrixFor(DateTime.utc(2026)).rates.first.usesCityPremium,
        isTrue,
      );
      final saved = OperationsCatalog(c.withLocations(c.locations));
      expect(saved.options['destination'], isNot(contains('City Proper')));
    }
  });
  test(
    'matrix order uses the supplied route sequence before extra locations',
    () {
      const c = OperationsCatalog({});
      expect(c.locations.take(25).map((l) => l.name), [
        'City Proper',
        'San Manuel',
        'San Jose',
        'Tagburos',
        'Santa Lourdes',
        'San Rafael',
        'Sabang',
        'Roxas',
        'San Vicente',
        'Taytay',
        'El Nido',
        'Santa Monica',
        'Sicsican',
        'Irawan',
        'Inagawan',
        'Aborlan',
        'Narra',
        'Sofronio Espanola',
        'Quezon',
        'Berong',
        'Rizal',
        "Brooke's Point",
        'Bataraza',
        'Rio Tuba',
        'Buliluyan',
      ]);
      final saved = OperationsCatalog(
        c.withLocations(c.locations.reversed.toList()),
      );
      expect(
        saved.locations.map((l) => l.name),
        c.locations.map((l) => l.name),
      );
    },
  );
  test(
    'unset rates stay editable but unavailable; city remains a barangay parent',
    () {
      const c = OperationsCatalog({});
      final day = DateTime.utc(2026);
      expect(
        c.hasActiveRate(
          c.locations.singleWhere((l) => l.name == 'Agutaya'),
          day,
        ),
        isFalse,
      );
      expect(c.options['origin'], isNot(contains('Agutaya')));
      expect(c.options['origin_barangay'], isNot(contains('Bacungan')));
      expect(c.options['origin'], contains('Puerto Princesa City'));
      expect(c.options['origin_barangay'], contains('San Manuel'));
      LocationOptionRegistry.apply(c.options, c.retired);
      expect(isValidPalawanLocationOption('Agutaya'), isTrue);
      final updated = OperationsCatalog({
        ...c.withLocations(c.locations),
        'matrix_versions': [
          TripMatrixVersion(
            id: 'added',
            effectiveFrom: DateTime.utc(2020),
            rates: [...KpiRate.matrix, const KpiRate('Agutaya', 100, 50)],
          ).toMap(),
        ],
      });
      expect(updated.options['origin'], contains('Agutaya'));
      expect(
        updated.hasActiveRate(
          updated.locations.singleWhere((l) => l.name == 'Agutaya'),
          day,
        ),
        isTrue,
      );
    },
  );
  test('default catalog separates the city from 22 municipalities', () {
    const catalog = OperationsCatalog({});
    expect(
      catalog.locations.where((l) => l.kind == 'city').map((l) => l.name),
      ['Puerto Princesa City'],
    );
    expect(
      catalog.locations.where((l) => l.kind == 'municipality'),
      hasLength(22),
    );
    expect(
      catalog.locations.map((l) => l.name),
      containsAll(defaultPalawanLocationOptions),
    );
    expect(
      catalog.options['origin'],
      containsAll(['Puerto Princesa City', 'Narra']),
    );
    expect(
      catalog.options['destination'],
      containsAll(['Puerto Princesa City', 'Narra']),
    );
  });
  test(
    'legacy combined type separates on read and survives saving offline',
    () {
      final catalog = OperationsCatalog({
        'locations': [
          const OperationLocation('Puerto Princesa City', 'city').toMap(),
          const OperationLocation('Narra', 'city', active: false).toMap(),
          const OperationLocation('Española', 'city').toMap(),
        ],
      });
      final saved = OperationsCatalog(catalog.withLocations(catalog.locations));
      expect(
        saved.locations.singleWhere((l) => l.name == 'Narra').kindLabel,
        'Municipality',
      );
      expect(
        saved.locations.singleWhere((l) => l.name == 'Narra').active,
        isFalse,
      );
      expect(
        saved.locations.singleWhere((l) => l.name == 'Sofronio Espanola').kind,
        'municipality',
      );
      expect(
        saved.locations
            .singleWhere((l) => l.name == 'Puerto Princesa City')
            .kindLabel,
        'City',
      );
    },
  );
  test(
    'every existing option appears with its original wording and no invented rates',
    () {
      const catalog = OperationsCatalog({});
      expect(
        catalog.locations.map((l) => l.name),
        containsAll(defaultPalawanLocationOptions),
      );
      expect(
        catalog.locations.map((l) => l.name),
        containsAll(defaultPuertoPrincesaBarangayOptions),
      );
      expect(catalog.options['origin'], catalog.options['destination']);
      expect(
        catalog.options['origin_barangay'],
        catalog.options['destination_barangay'],
      );
      expect(catalog.locations, hasLength(80));
      expect(catalog.matrixFor(DateTime.utc(2026)).rates, hasLength(26));
      final lourdes = catalog.locations.singleWhere(
        (l) => l.name == 'Santa Lourdes',
      );
      expect(lourdes.aliases, contains('Sta. Lourdes'));
      final espanola = catalog.locations.singleWhere(
        (l) => l.name == 'Sofronio Espanola',
      );
      expect(espanola.aliases, contains('Española'));
    },
  );
  test(
    'saved catalog adopts booking wording without changing historical rates',
    () {
      final version = TripMatrixVersion.defaults.toMap();
      final catalog = OperationsCatalog({
        'locations': [
          const OperationLocation(
            'Sta. Monica',
            'barangay',
            active: false,
          ).toMap(),
          const OperationLocation('Española', 'city').toMap(),
        ],
        'matrix_versions': [version],
      });
      expect(
        catalog.locations.map((l) => l.name),
        containsAll(['Santa Monica', 'Sofronio Espanola']),
      );
      expect(
        catalog.locations.singleWhere((l) => l.name == 'Santa Monica').active,
        isFalse,
      );
      expect(catalog.versions.last.toMap(), version);
      LocationOptionRegistry.apply(catalog.options, catalog.retired);
      expect(LocationOptionRegistry.accepts('cities', 'Española', []), isTrue);
    },
  );
  test(
    'defaults preserve locations and seed routes without calling barangays municipalities',
    () {
      const c = OperationsCatalog({});
      expect(c.options['cities'], contains('Puerto Princesa City'));
      expect(c.options['cities'], isNot(contains('City Proper')));
      expect(c.options['origin'], contains('Sabang'));
      expect(c.options['destination'], contains('Rio Tuba'));
      expect(c.options['origin_barangay'], contains('San Manuel'));
    },
  );
  test(
    'city edits propagate to both booking selectors and retain historical names',
    () {
      const c = OperationsCatalog({});
      final values =
          (c.options['cities'] as List)
              .cast<String>()
              .where((s) => s != 'Narra')
              .toList()
            ..add('New municipality');
      final next = OperationsCatalog(c.changeOptions('cities', values));
      LocationOptionRegistry.apply(next.options, next.retired);
      expect(next.locations.map((l) => l.name), contains('New municipality'));
      expect(locationOptionsFor('origin'), isNot(contains('New municipality')));
      expect(
        locationOptionsFor('destination'),
        isNot(contains('New municipality')),
      );
      expect(locationOptionsFor('origin'), isNot(contains('Narra')));
      expect(isValidPalawanLocationOption('Narra'), isTrue);
    },
  );
  test('legacy origin edits update both selectors from one catalog', () {
    final c = OperationsCatalog(
      const OperationsCatalog({}).changeOptions('origin', ['Custom origin']),
    );
    LocationOptionRegistry.apply(c.options, c.retired);
    expect(c.locations.map((l) => l.name), contains('Custom origin'));
    expect(locationOptionsFor('origin'), isEmpty);
    expect(locationOptionsFor('destination'), isEmpty);
  });
  test(
    'legacy direction lists merge, matrix aliases share one location, and inactive values remain valid historically',
    () {
      final catalog = OperationsCatalog({
        'options': {
          'origin': ['Origin-only place'],
          'destination': ['Destination-only place'],
          'origin_barangay': ['Santa Lourdes'],
          'destination_barangay': ['New barangay'],
        },
      });
      expect(catalog.options['origin'], catalog.options['destination']);
      expect(
        catalog.locations.map((l) => l.name),
        containsAll(['Origin-only place', 'Destination-only place']),
      );
      expect(
        catalog.options['origin_barangay'],
        catalog.options['destination_barangay'],
      );
      expect(
        catalog.locations.where((l) => l.name == 'Santa Lourdes'),
        hasLength(1),
      );
      expect(catalog.locations.where((l) => l.name == 'Sta. Lourdes'), isEmpty);
      final removed = OperationsCatalog(
        catalog.withLocations([
          for (final l in catalog.locations)
            l.name == 'Santa Lourdes' ? l.copyActive(false) : l,
        ]),
      );
      LocationOptionRegistry.apply(removed.options, removed.retired);
      expect(
        removed.options['origin_barangay'],
        isNot(contains('Santa Lourdes')),
      );
      expect(
        LocationOptionRegistry.accepts('origin_barangay', 'Santa Lourdes', []),
        isTrue,
      );
      expect(
        removed
            .matrixFor(DateTime.utc(2020))
            .rates
            .firstWhere((r) => r.name == 'Sta. Lourdes')
            .driver,
        100,
      );
    },
  );

  test('effective versions do not rewrite past matrix amounts', () {
    final newer = TripMatrixVersion(
      id: 'new',
      effectiveFrom: DateTime.utc(2026, 10, 1),
      rates: const [KpiRate('Narra', 900, 450)],
      pay: const TripPaySchedule(daily: 500),
    );
    final c = OperationsCatalog({
      'matrix_versions': [newer.toMap()],
    });
    expect(
      c
          .matrixFor(DateTime.utc(2026, 9, 30))
          .rates
          .firstWhere((r) => r.name == 'Narra')
          .driver,
      500,
    );
    expect(c.matrixFor(DateTime.utc(2026, 10, 1)).rates.single.driver, 900);
    expect(c.matrixFor(DateTime.utc(2026, 10, 1)).pay.daily, 500);
    expect(TripMatrixVersion.fromMap(newer.toMap()).toMap(), newer.toMap());
  });
  test('City Proper premium survives renaming and serialization', () {
    const rate = KpiRate('Renamed CP', 100, 50, cityProper: true);
    expect(KpiRate.fromMap(rate.toMap()).usesCityPremium, isTrue);
    expect(
      KpiRate.fromMap(const KpiRate('Roxas', 600, 300).toMap()).usesCityPremium,
      isFalse,
    );
  });
  test(
    'ledger totals count each entry, omit voids, and invalidate old confirmation',
    () {
      final period = KpiPeriod.week(2026, 9, 1);
      final entries = [
        {
          'id': 'a',
          'make_id': '4',
          'day': '2026-09-01',
          'amount': 1000,
          'updated_at': 'v1',
        },
        {
          'id': 'b',
          'make_id': '4',
          'day': '2026-09-01',
          'amount': 500,
          'updated_at': 'v2',
        },
        {
          'id': 'c',
          'make_id': '4',
          'day': '2026-09-01',
          'amount': 900,
          'voided': true,
        },
      ];
      final first = PmKpi.calculate(
        makeId: '4',
        period: period,
        bookings: [],
        records: [],
        fuelEntries: entries,
      );
      expect(first.fuel, 1500);
      expect(first.days.first.fuelComplete, isFalse);
      final confirmed = {
        'make_id': '4',
        'day': '2026-09-01',
        'fuel_confirmed': true,
        'fuel_source': 'ledger',
        'fuel_signature': first.days.first.record['fuel_signature_live'],
      };
      final second = PmKpi.calculate(
        makeId: '4',
        period: period,
        bookings: [],
        records: [confirmed],
        fuelEntries: entries,
      );
      expect(second.days.first.fuelComplete, isTrue);
      final edited = [...entries]
        ..[0] = {...entries.first, 'amount': 1200, 'updated_at': 'v3'};
      final third = PmKpi.calculate(
        makeId: '4',
        period: period,
        bookings: [],
        records: [confirmed],
        fuelEntries: edited,
      );
      expect(third.fuel, 1700);
      expect(third.days.first.fuelComplete, isFalse);
    },
  );
}
