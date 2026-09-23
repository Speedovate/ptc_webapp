import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/admin_modal_record_list.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/services/kpi/pm_kpi_store.dart';
import 'package:webapp/views/admin/pm_kpi_dialog.dart';
import 'package:webapp/widgets/shared/app_modal_guard.dart';

class TestStore extends PmKpiStore {
  @override
  bool get canRead => true;
  @override
  bool get canReadFuel => true;
  @override
  bool get canReadIncome => true;
  final updates = StreamController<List<Booking>>.broadcast();
  final records = <Map<String, dynamic>>[];
  Map<String, dynamic> settings = {};
  int loads = 0;
  int exportLoads = 0;
  @override
  Future<List<VehicleMake>> exportMakes() async {
    exportLoads++;
    return const [VehicleMake(id: '4', code: 'PM4')];
  }

  @override
  List<UserModel> get incidentUsers => const [
    UserModel(id: '22', role: 'driver', name: 'Replacement'),
  ];
  @override
  Future<KpiStoredData?> readCached(String makeId, KpiPeriod period) async =>
      KpiStoredData(records, settings, true);
  @override
  bool get canReadBookings => true;
  @override
  bool get canEdit => true;
  @override
  bool get canOpenUsers => true;
  @override
  bool get bookingsVerified => true;
  @override
  Future<UserModel?> currentUser() async =>
      const UserModel(id: '1', role: 'admin');
  @override
  Future<List<Booking>> bookings() async => [
    const Booking(
      id: '1',
      vehicleMake: VehicleMake(id: '4'),
      helper: UserModel(id: '9', role: 'helper', name: 'Helper Name'),
    ),
  ];
  @override
  Stream<List<Booking>> watchBookings() => updates.stream;
  @override
  Future<KpiStoredData> load(String makeId, KpiPeriod period) async {
    loads++;
    return KpiStoredData(records, settings, false);
  }

  @override
  Future<void> save({
    required String makeId,
    required Map<String, dynamic> data,
    required Map<String, dynamic> previous,
  }) async {
    if (data['kind'] == 'settings') {
      settings = {...data};
    } else {
      records.add({...data, 'make_id': makeId});
    }
  }
}

class HydratedBookingsStore extends DelayedRefreshStore {
  bool requestedBookings = false;
  @override
  List<Booking>? get cachedBookings => const [Booking(id: 'cached')];
  @override
  Future<List<Booking>> bookings() {
    requestedBookings = true;
    return Completer<List<Booking>>().future;
  }
}

class DelayedRefreshStore extends TestStore {
  final refresh = Completer<KpiStoredData>();
  @override
  Future<KpiStoredData> load(String makeId, KpiPeriod period) => refresh.future;
}

class ManyTripsStore extends TestStore {
  @override
  Future<List<Booking>> bookings() async => List.generate(
    40,
    (i) => Booking(
      id: '${i + 1}',
      vehicleMake: const VehicleMake(id: '4'),
      driver: const UserModel(id: '8'),
      helper: const UserModel(id: '9'),
      clientStatus: 'delivered',
      createdAt: DateTime(DateTime.now().year, DateTime.now().month, 1),
      deliveredAt: DateTime(DateTime.now().year, DateTime.now().month, 1, 8, i),
    ),
  );
}

Future<void> expandDay(WidgetTester tester, DateTime day) async {
  final key = find.byKey(ValueKey('kpi-expand-${kpiDayKey(day)}'));
  await tester.scrollUntilVisible(
    key,
    300,
    scrollable: find
        .byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        )
        .first,
  );
  await Scrollable.ensureVisible(tester.element(key), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(key);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Export opens Excel confirmation directly and Cancel does not export',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = TestStore();
      addTearDown(store.updates.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PmKpiDialog(
              make: const VehicleMake(id: '4', code: 'PM4'),
              store: store,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Export'));
      await tester.pumpAndSettle();
      expect(find.text('Export KPI'), findsOneWidget);
      expect(find.textContaining('as an Excel file?'), findsOneWidget);
      expect(find.text('Excel (Fleet)'), findsNothing);
      expect(find.text('PDF (Fleet)'), findsNothing);
      expect(store.exportLoads, 0);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Export KPI'), findsNothing);
      expect(store.exportLoads, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'replacement incidents stay with selected user and preserve legacy PM counts',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = TestStore()
        ..settings = {
          'unrelated_setting': 'preserved',
          'incident_counts': {
            '2026-09-01': {'complaints': 5, 'accidents': 2},
          },
          'user_incident_counts': {
            '8': {
              '2026-09-01': {'complaints': 3},
            },
          },
        };
      addTearDown(store.updates.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PmKpiDialog(
              make: const VehicleMake(
                id: '4',
                code: 'PM4',
                driver: UserModel(
                  id: '8',
                  role: 'driver',
                  name: 'Regular driver',
                ),
                helper: UserModel(id: '9', role: 'helper', name: 'Helper'),
              ),
              store: store,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('kpi-add-complaints-8'));
      expect(find.byKey(const ValueKey('kpi-add-accidents-8')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('kpi-add-complaints-9')),
        findsOneWidget,
      );
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      tester
          .widget<AdminDropdownFormField<String>>(
            find.byWidgetPredicate(
              (w) =>
                  w is AdminDropdownFormField<String> &&
                  w.decoration?.labelText == 'Driver / Helper',
            ),
          )
          .onChanged!('22');
      await tester.pumpAndSettle();
      Finder input(String label) => find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == label,
      );
      await tester.enterText(input('Customer complaints'), '1');
      await tester.enterText(input('Accidents'), '0');
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        false,
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      final today = kpiDate(DateTime.now());
      final users = store.settings['user_incident_counts'] as Map;
      final entries = users['22'] as Map;
      expect(users['8']['2026-09-01']['complaints'], 3);
      expect(users.containsKey('9'), isFalse);
      expect(
        (store.settings['incident_counts'] as Map)['2026-09-01']['complaints'],
        5,
      );
      expect(entries[kpiDayKey(today)]['user_id'], '22');
      expect(entries[kpiDayKey(today)]['complaints'], 1);
      expect(entries[kpiDayKey(today)]['accidents'], 0);
      expect(entries.length, today.day);
      expect(store.settings['unrelated_setting'], 'preserved');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'weekly and monthly use month selection; custom uses only range',
    (tester) async {
      final store = TestStore();
      addTearDown(store.updates.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PmKpiDialog(
              make: const VehicleMake(id: '4', code: 'PM4'),
              store: store,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('kpi-period-date-field'));
      String label() => tester
          .widget<Text>(find.descendant(of: field, matching: find.byType(Text)))
          .data!;
      expect(label().contains(' – '), isFalse);
      expect(find.byType(AdminDropdownFormField<int>), findsNothing);
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(find.text('Select Month'), findsOneWidget);
      expect(find.byType(DatePickerDialog), findsNothing);
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      tester
          .widget<AdminDropdownFormField<String>>(
            find.byType(AdminDropdownFormField<String>),
          )
          .onChanged!('Weekly');
      await tester.pumpAndSettle();
      expect(find.byType(AdminDropdownFormField<int>), findsOneWidget);
      expect(label().contains(' – '), isFalse);
      tester
          .widget<AdminDropdownFormField<String>>(
            find.byType(AdminDropdownFormField<String>),
          )
          .onChanged!('Custom range');
      await tester.pumpAndSettle();
      expect(find.text('Date Range'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AdminDropdownFormField<int>), findsNothing);
      expect(label().contains(' – '), isTrue);
    },
  );

  testWidgets('period controls have equal rendered bounds', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = TestStore();
    addTearDown(store.updates.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PmKpiDialog(
            make: const VehicleMake(id: '4', code: 'PM4'),
            store: store,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final dropdown = find.ancestor(
      of: find.text('Monthly'),
      matching: find.byType(InputDecorator),
    );
    final button = find.byKey(const ValueKey('kpi-period-date-field'));
    final dropdownRect = tester.getRect(dropdown);
    final buttonRect = tester.getRect(button);
    expect(
      dropdownRect.height,
      buttonRect.height,
      reason: 'Dropdown $dropdownRect, date $buttonRect',
    );
    expect(dropdownRect.center.dy, buttonRect.center.dy);
    final refreshRect = tester.getRect(
      find.byKey(const ValueKey('kpi-refresh-control')),
    );
    final refreshIconRect = tester.getRect(find.byIcon(Icons.refresh));
    expect(refreshRect.height, dropdownRect.height);
    expect(refreshRect.center.dy, dropdownRect.center.dy);
    expect(refreshIconRect.center, refreshRect.center);
    final dropdownContainer = InputDecorator.containerOf(
      tester.element(find.text('Monthly')),
    )!;
    final dateContainer = InputDecorator.containerOf(
      tester.element(find.byIcon(Icons.date_range)),
    )!;
    final paintedDropdown =
        dropdownContainer.localToGlobal(Offset.zero) & dropdownContainer.size;
    final paintedDate =
        dateContainer.localToGlobal(Offset.zero) & dateContainer.size;
    expect(
      paintedDropdown,
      Rect.fromLTWH(
        paintedDropdown.left,
        paintedDate.top,
        paintedDropdown.width,
        paintedDate.height,
      ),
    );
    expect(refreshIconRect.center.dy, paintedDate.center.dy);
  });

  testWidgets(
    'KPI sections reuse one modal and return to the selected period',
    (tester) async {
      final store = TestStore();
      addTearDown(store.updates.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAppDialog<void>(
                  context: context,
                  builder: (_) => PmKpiDialog(
                    make: const VehicleMake(id: '4', code: 'PM4'),
                    store: store,
                  ),
                ),
                child: const Text('Open KPI'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open KPI'));
      await tester.pumpAndSettle();
      expect(find.text('Payroll Summary'), findsNothing);
      expect(find.text('Import Excel'), findsNothing);
      for (final section in ['Fuel Requests']) {
        await Scrollable.ensureVisible(
          tester.element(find.text(section)),
          alignment: 0.5,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(section));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
        expect(find.text('Back to KPI'), findsOneWidget);
        expect(find.text('Monthly'), findsNothing);
        await tester.tap(find.text('Back to KPI'));
        await tester.pumpAndSettle();
        expect(find.text('Monthly'), findsOneWidget);
        expect(find.byType(Dialog), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    },
  );
  testWidgets('transaction booking link opens the selected booking', (
    tester,
  ) async {
    final store = ManyTripsStore();
    addTearDown(store.updates.close);
    Booking? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PmKpiDialog(
            make: const VehicleMake(id: '4', code: 'PM4'),
            store: store,
            onOpenBooking: (current, booking) => opened = booking,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final vertical = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );
    await expandDay(
      tester,
      DateTime.utc(DateTime.now().year, DateTime.now().month, 1),
    );
    await tester.scrollUntilVisible(
      find.text('Booking 40'),
      400,
      scrollable: vertical,
    );
    await Scrollable.ensureVisible(
      tester.element(find.text('Booking 40')),
      alignment: 0.2,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Booking 40'));
    expect(opened?.id, '40');
    expect(
      tester.widget<Text>(find.text('Booking 40')).style?.decoration,
      TextDecoration.underline,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'hydrated bookings show persisted KPI without waiting for booking fetch',
    (tester) async {
      final store = HydratedBookingsStore();
      addTearDown(store.updates.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PmKpiDialog(
              make: const VehicleMake(id: '4', code: 'PM4'),
              store: store,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(store.requestedBookings, false);
      expect(find.byType(AdminModalRecordList), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('checking'), findsNothing);
      store.refresh.complete(const KpiStoredData([], {}, false));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('cached KPI remains visible while server refresh is pending', (
    tester,
  ) async {
    final store = DelayedRefreshStore();
    addTearDown(store.updates.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PmKpiDialog(
            make: const VehicleMake(id: '4', code: 'PM4'),
            store: store,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(AdminModalRecordList), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('checking'), findsNothing);
    store.refresh.complete(const KpiStoredData([], {}, false));
    await tester.pumpAndSettle();
    expect(find.byType(AdminModalRecordList), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('KPI history adds 15 rows with one vertical viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = ManyTripsStore();
    addTearDown(store.updates.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PmKpiDialog(
            make: const VehicleMake(id: '4', code: 'PM4'),
            store: store,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    AdminModalRecordList list() =>
        tester.widget(find.byType(AdminModalRecordList));
    expect(list().itemCount, 1);
    expect(list().valuesAt(0)[4], 'Total');
    expect(find.text('Driver / Helper Income'), findsNothing);
    final day = DateTime.utc(DateTime.now().year, DateTime.now().month, 1);
    await expandDay(tester, day);
    expect(list().itemCount, 15);
    expect(list().shrinkWrap, isFalse);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
      findsOneWidget,
    );
    final controller = list().scrollController!;
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(list().itemCount, 30);
    final vertical = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );
    for (var i = 0; i < 20 && list().itemCount < 42; i++) {
      await tester.drag(vertical, const Offset(0, -500));
      await tester.pumpAndSettle();
    }
    expect(list().itemCount, 42);
    // Salary and shares are separate child rows, yet one daily total remains.
    final values = [
      for (var i = 0; i < list().itemCount; i++) list().valuesAt(i),
    ];
    expect(values.where((r) => r[4] == 'Total').length, 1);
    expect(values.where((r) => r[4] == 'Salary').length, 1);
    expect(values.where((r) => r[4] == 'Share').length, 40);
    expect(values[1][4], 'Salary');
    expect(values[2][0], 'Booking 40');
    final dailyCard = find.ancestor(
      of: find.byKey(ValueKey('kpi-expand-${kpiDayKey(day)}')),
      matching: find.byType(AdminListItemCard),
    );
    expect(dailyCard, findsOneWidget);
    expect(
      find.descendant(
        of: dailyCard,
        matching: find.text('${values.first[0].split(',').first} Pay'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dailyCard, matching: find.text('Booking 40')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dailyCard, matching: find.byType(Divider)),
      findsOneWidget,
    );

    controller.jumpTo(0);
    await tester.pumpAndSettle();
    await expandDay(tester, day); // Toggle the same day closed.
    expect(list().itemCount, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final width in [375.0, 1200.0]) {
    testWidgets(
      'PM modal filters, user links and outside dismissal at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? openedUserId;
        final store = TestStore();
        addTearDown(store.updates.close);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showAppDialog<void>(
                    context: context,
                    modalKey: 'kpi-layout-$width',
                    builder: (_) => PmKpiDialog(
                      make: const VehicleMake(
                        id: '4',
                        code: 'PM 4',
                        driver: UserModel(id: '8', name: 'Driver Name'),
                        helper: UserModel(id: '10', name: 'Assigned Helper'),
                      ),
                      store: store,
                      onOpenUser: (_, user) => openedUserId = user.id,
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.text('PM 4 KPI'), findsOneWidget);
        expect(find.byIcon(Icons.open_in_new), findsNothing);
        final driver = find.text('8 | Driver Name');
        expect(tester.widget<Text>(driver).style?.fontWeight, FontWeight.w700);
        expect(
          tester.widget<Text>(driver).style?.decoration,
          TextDecoration.underline,
        );
        await tester.ensureVisible(driver);
        await tester.pumpAndSettle();
        await tester.tap(driver);
        expect(openedUserId, '8');
        await tester.ensureVisible(find.text('10 | Assigned Helper'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('10 | Assigned Helper'));
        expect(openedUserId, '10');
        expect(find.text('10 | Assigned Helper'), findsOneWidget);
        expect(find.text('9 | Helper Name'), findsNothing);
        expect(store.updates.hasListener, isTrue);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Monthly'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Monthly'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Weekly').last);
        await tester.pumpAndSettle();
        expect(find.text('Week 1'), findsNWidgets(2));
        expect(find.text('Gross income (actual)'), findsOneWidget);
        expect(find.text('Total expenses'), findsOneWidget);
        expect(find.text('Target gross income (40%)'), findsOneWidget);
        expect(find.text('Favorable / Unfavorable'), findsOneWidget);
        expect(store.loads, 2);
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
        expect(find.text('PM 4 KPI'), findsNothing);
        expect(store.updates.hasListener, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('editable rating rules persist and update UI', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = TestStore();
    addTearDown(store.updates.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PmKpiDialog(
            make: const VehicleMake(id: '4', code: 'PM 4'),
            store: store,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.text('Rating Rules');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '35');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(
      (store.settings['rating_rules'] as Map)['gross_satisfactory_min'],
      35,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'manager confirms fuel and zero-trip salary without changing bookings',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = TestStore();
      addTearDown(store.updates.close);
      final now = kpiDate(DateTime.now());
      final day = DateTime.utc(now.year, now.month, 1);
      store.records.add({'make_id': '4', 'day': kpiDayKey(day), 'fuel': 0});
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PmKpiDialog(
              make: const VehicleMake(id: '4', code: 'PM 4'),
              store: store,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expandDay(tester, day);
      final row = find.byKey(ValueKey('kpi-day-${kpiDayKey(day)}'));
      await tester.scrollUntilVisible(
        row,
        300,
        scrollable: find
            .byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            )
            .first,
      );
      expect(
        find.byKey(
          ValueKey('kpi-day-${kpiDayKey(day.add(const Duration(days: 1)))}'),
        ),
        findsNothing,
      );
      store.records.clear();
      await Scrollable.ensureVisible(tester.element(row), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
      // A short editor should fit its content, rather than fill the viewport.
      final editor = find
          .descendant(
            of: find.byType(Dialog).last,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Material && widget.type == MaterialType.card,
            ),
          )
          .first;
      expect(
        tester.getSize(editor).height,
        lessThan(tester.view.physicalSize.height * 0.7),
      );
      final salary = find.text('Confirm daily salary and trip totals');
      await tester.ensureVisible(salary);
      await tester.tap(salary);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(store.records.single['fuel'], 0);
      expect(store.records.single['salary_confirmed'], true);
      expect(store.records.single['driver_salary'], 0);
      expect(store.records.single['helper_salary'], 0);
      expect(store.records.single['day'], kpiDayKey(day));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
