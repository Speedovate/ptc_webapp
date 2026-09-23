import 'package:flutter/rendering.dart';
import 'package:webapp/services/sync_error_log_service.dart';
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

class TestDiagnostics extends SyncErrorLogService {
  final captured = <Map<String, dynamic>>[];
  @override
  Future<void> capture({
    required String source,
    required String operation,
    required String entryId,
    required String target,
    required String error,
    required String stack,
    required int attempt,
    String? owner,
    String? actionAt,
    String? failedAt,
    String kind = 'queue_failure',
    bool? attentionRequired,
    Map<String, dynamic> details = const {},
  }) async {
    captured.add({
      'kind': kind,
      'operation': operation,
      'error': error,
      'stack': stack,
      'details': details,
      'attention_required': attentionRequired,
    });
  }
}

final testDiagnostics = TestDiagnostics();

class TestStore extends PmKpiStore {
  @override
  bool get canRead => true;
  @override
  bool get canReadFuel => true;
  @override
  bool get canReadCatalog => true;
  bool incomeAllowed = true;
  @override
  bool get canReadIncome => incomeAllowed;
  final updates = StreamController<List<Booking>>.broadcast();
  final records = <Map<String, dynamic>>[];
  Map<String, dynamic> settings = {};
  bool failSave = false;
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
  Future<Map<String, dynamic>> loadFleetRules({bool localOnly = false}) async =>
      settings;

  @override
  Future<void> save({
    required String makeId,
    required Map<String, dynamic> data,
    required Map<String, dynamic> previous,
  }) async {
    if (failSave) throw StateError('Save failed');
    if (data['kind'] == 'settings') {
      settings = {...data};
    } else {
      records.add({...data, 'make_id': makeId});
    }
  }
}

class EmptyKpiStore extends TestStore {
  bool stall = false;
  @override
  Future<KpiStoredData?> readCached(String makeId, KpiPeriod period) async =>
      null;
  @override
  Future<List<Booking>> bookings() async => [];
  @override
  Future<KpiStoredData> load(String makeId, KpiPeriod period) => stall
      ? Completer<KpiStoredData>().future
      : Future.value(const KpiStoredData([], {}, false));
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
  testWidgets('income permission hides crew details and transactions', (
    tester,
  ) async {
    final store = TestStore()..incomeAllowed = false;
    addTearDown(store.updates.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PmKpiDialog(
            diagnostics: testDiagnostics,
            make: const VehicleMake(id: '4', code: 'PM4'),
            store: store,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final list = tester.widget<AdminModalRecordList>(
      find.byType(AdminModalRecordList),
    );
    expect(list.itemCount, 0);
    expect(list.showTitlesRow, false);
    expect(
      list.emptyMessage,
      'You do not have access to driver/helper income.',
    );
    expect(find.text('Trip Shares'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  for (final stalled in [false, true]) {
    testWidgets('null KPI cache and empty data settle; stalled=$stalled', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = EmptyKpiStore()..stall = stalled;
      addTearDown(store.updates.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PmKpiDialog(
              diagnostics: testDiagnostics,
              make: const VehicleMake(id: '4', code: 'PM4'),
              store: store,
            ),
          ),
        ),
      );
      await tester.pump();
      if (stalled) await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final list = tester.widget<AdminModalRecordList>(
        find.byType(AdminModalRecordList),
      );
      expect(list.itemCount, 0);
      expect(
        list.emptyMessage,
        stalled
            ? isNull
            : 'No delivered trips or recorded expenses in this period.',
      );
      if (stalled) {
        expect(find.text('Retry'), findsOneWidget);
        expect(
          find.text(
            'Refresh KPI records, fuel, rates and settings took too long. Select Retry to try again.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('TimeoutException'), findsNothing);
        expect(find.text('Data could not be refreshed'), findsNothing);
        final report = testDiagnostics.captured.last;
        expect(report['kind'], 'kpi_diagnostic');
        expect(report['attention_required'], isTrue);
        expect(report['error'], contains('TimeoutException'));
        expect(
          (report['details'] as Map)['failed_step'],
          'Refresh KPI records, fuel, rates and settings',
        );
        expect((report['details'] as Map)['diagnostics'], contains('pm_id'));

        store.stall = false;
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(find.text('Retry'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      } else {
        expect(find.text('Retry'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }

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
              diagnostics: testDiagnostics,
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
              diagnostics: testDiagnostics,
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
              diagnostics: testDiagnostics,
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
          .onChanged!('Range');
      await tester.pumpAndSettle();
      expect(find.text('Date Range'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AdminDropdownFormField<int>), findsNothing);
      expect(label().contains(' – '), isTrue);
    },
  );

  testWidgets('KPI section buttons match the existing New button surface', (
    tester,
  ) async {
    final store = TestStore();
    addTearDown(store.updates.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AdminListNewButton(
              controlHeight: 52,
              surfaceRadius: 16,
              iconOnly: false,
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final reference = find.descendant(
      of: find.byType(FilledButton),
      matching: find.byType(Material),
    );
    final referenceHeight = tester.getSize(reference).height;
    final referenceShape = tester.widget<Material>(reference).shape;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PmKpiDialog(
            diagnostics: testDiagnostics,
            make: const VehicleMake(id: '4', code: 'PM4'),
            store: store,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final label in ['Fuel', 'Rates', 'Rules']) {
      final button = find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      );
      final surface = find.descendant(
        of: button,
        matching: find.byType(Material),
      );
      expect(tester.getSize(surface).height, referenceHeight, reason: label);
      expect(
        tester.widget<Material>(surface).shape,
        referenceShape,
        reason: label,
      );
    }
    expect(tester.takeException(), isNull);
  });

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
            diagnostics: testDiagnostics,
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
    final selector = tester.widget<AdminDropdownFormField<String>>(
      find.byType(AdminDropdownFormField<String>),
    );
    expect(selector.items!.map((item) => item.value), [
      'Range',
      'Weekly',
      'Monthly',
      'All Time',
    ]);
    final dropdownRect = tester.getRect(dropdown);
    final buttonRect = tester.getRect(button);
    expect(
      dropdownRect.height,
      buttonRect.height,
      reason: 'Dropdown $dropdownRect, date $buttonRect',
    );
    expect(dropdownRect.center.dy, buttonRect.center.dy);
    expect(buttonRect.height, 48);
    expect(find.byTooltip('Refresh KPI'), findsNothing);
    expect(find.text('Retry'), findsNothing);
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
    final titleRect = tester.getRect(find.text('PM4 KPI'));
    expect(paintedDate.top - titleRect.bottom, 20);
    final financialTable = find.ancestor(
      of: find.text('Item'),
      matching: find.byType(Table),
    );
    expect(tester.getRect(financialTable).top - paintedDate.bottom, 20);
    expect(
      paintedDropdown,
      Rect.fromLTWH(
        paintedDropdown.left,
        paintedDate.top,
        paintedDropdown.width,
        paintedDate.height,
      ),
    );
    final desktopDateWidth = tester.getSize(button).width;
    tester.view.physicalSize = const Size(950, 1000);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(button).width,
      desktopDateWidth,
      reason: 'Non-mobile controls stay content-sized when the toolbar wraps',
    );
    tester.view.physicalSize = const Size(1200, 1000);
    await tester.pumpAndSettle();
    for (final mode in ['Monthly', 'Range']) {
      if (mode == 'Range') {
        // Modal guard uses wall-clock debounce across dialog instances.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 400)),
        );
        selector.onChanged!('Range');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }
      final selectedText = find.text(mode);
      final selectedField = find.ancestor(
        of: selectedText,
        matching: find.byType(InputDecorator),
      );
      expect(
        tester.getRect(selectedText).center.dy,
        closeTo(tester.getRect(selectedField).center.dy, 0.5),
        reason: '$mode selected text center',
      );
      final dateText = find.descendant(of: button, matching: find.byType(Text));
      expect(tester.widget<Text>(dateText).style!.fontSize, 14);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: dateText, matching: find.byType(RichText)),
      );
      expect(
        paragraph.size.width + 0.01,
        greaterThanOrEqualTo(paragraph.getMaxIntrinsicWidth(double.infinity)),
        reason: '$mode must have room for every date character',
      );

      expect(
        tester.getRect(dateText).center.dy,
        closeTo(tester.getRect(button).center.dy, 0.5),
        reason: '$mode date text center',
      );
      expect(
        tester.getRect(find.byIcon(Icons.date_range)).center.dy,
        closeTo(tester.getRect(button).center.dy, 0.5),
        reason: '$mode icon center',
      );
    }
    tester.view.physicalSize = const Size(375, 1000);
    await tester.pumpAndSettle();
    final rangeText = find.descendant(of: button, matching: find.byType(Text));
    expect(
      tester.widget<Text>(rangeText).overflow,
      isNot(TextOverflow.ellipsis),
    );
    expect(tester.widget<Text>(rangeText).maxLines, 1);
    expect(tester.getRect(button).height, 48);
    expect(
      tester.getRect(rangeText).right,
      lessThanOrEqualTo(tester.getRect(button).right),
    );
    expect(tester.takeException(), isNull);
    selector.onChanged!('Monthly');
    for (final width in [375.0, 600.0, 850.0]) {
      tester.view.physicalSize = Size(width, 1000);
      await tester.pumpAndSettle();
      Finder section(String label) => find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      );
      final fuel = tester.getRect(section('Fuel'));
      final rules = tester.getRect(section('Rules'));
      final period = tester.getRect(
        find.ancestor(
          of: find.text('Monthly'),
          matching: find.byType(InputDecorator),
        ),
      );
      final date = tester.getRect(button);
      expect(period.left, fuel.left, reason: 'mobile left edge at $width');
      expect(
        date.right,
        closeTo(rules.right, 0.01),
        reason: 'mobile right edge at $width',
      );
      expect(fuel.width, closeTo(rules.width, 0.01));
      expect(date.bottom, lessThan(fuel.top));
      expect(tester.takeException(), isNull);
    }
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
                    diagnostics: testDiagnostics,
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
      for (final section in ['Fuel', 'Rules']) {
        final sectionButton = find.ancestor(
          of: find.text(section),
          matching: find.byWidgetPredicate((widget) => widget is FilledButton),
        );
        await Scrollable.ensureVisible(
          tester.element(sectionButton),
          alignment: 0.5,
        );
        await tester.pumpAndSettle();
        await tester.tap(sectionButton);
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
            diagnostics: testDiagnostics,
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
              diagnostics: testDiagnostics,
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
            diagnostics: testDiagnostics,
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
            diagnostics: testDiagnostics,
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
                      diagnostics: testDiagnostics,
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
            diagnostics: testDiagnostics,
            make: const VehicleMake(id: '4', code: 'PM 4'),
            store: store,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.text('Rules');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Rule'), findsOneWidget);
    expect(find.text('Value'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('kpi-rule-edit-0')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '101');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Check threshold order'), findsOneWidget);
    expect(store.settings['rating_rules'], isNull);
    store.failSave = true;
    await tester.enterText(find.byType(TextField).first, '35');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Bad state: Save failed'), findsOneWidget);
    expect(find.text('Edit Rule'), findsOneWidget);
    expect(store.settings['rating_rules'], isNull);
    store.failSave = false;
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsNothing);
    expect(find.text('Back to KPI'), findsOneWidget);
    expect(
      (store.settings['rating_rules'] as Map)['gross_satisfactory_min'],
      35,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 400));
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
              diagnostics: testDiagnostics,
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
