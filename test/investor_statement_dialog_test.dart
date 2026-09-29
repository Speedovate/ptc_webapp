import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/models/dispatcher_access_config.dart';
import 'package:webapp/views/admin/investor_statement_dialog.dart';

import 'support/investor_fixtures.dart';
import 'support/investor_statement_harness.dart';

import 'package:webapp/models/user.dart';
import 'package:webapp/view_models/admin/investor_statement.vm.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/role_access_service.dart';

final owned = [...investorTestMakes];

/// The dialog is rendered straight into the tree rather than pushed onto a
/// navigator: the modal guard keeps process-wide state about open dialogs, and
/// eight tests sharing one guard is a test-ordering problem, not a product one.
/// The entry point itself is covered by the Vehicle Makes test that opens it.
Future<
  ({
    InvestorStatementViewModel vm,
    StubKpiStore kpi,
    MemoryCache rateCache,
    OfflineMutationQueueService rateQueue,
  })
>
open(
  WidgetTester tester, {
  List<VehicleMake>? makes,
  bool Function()? canEditRate,
}) async {
  final built = buildInvestorStatementVm(canEditRate: canEditRate);
  final vm = built.vm;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: InvestorStatementDialog(
          makes: makes ?? investorTestMakes,
          // Ownership is read off a truck's crew, so the accounts have to come
          // with them. Without these every truck reads as Paltranco and the
          // investor list is empty.
          users: InvestorFixtures.usersFor(makes ?? investorTestMakes),
          kpiStore: vm.kpiStore,
          rateStore: vm.rateStore,
        ),
      ),
    ),
  );
  await settle(tester);
  return built;
}

/// A bounded settle. The dialog's share lookup leaves a periodic timer running
/// in the queue, so `pumpAndSettle` would wait for a frame that never comes.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Releases what the dialog started: the tree, the view model, and the queue
/// retry timer behind the share lookup. All of it has to happen inside the test
/// body, because the harness checks for leaked timers before any teardown runs.
Future<void> close(
  WidgetTester tester,
  ({
    InvestorStatementViewModel vm,
    StubKpiStore kpi,
    MemoryCache rateCache,
    OfflineMutationQueueService rateQueue,
  })
  built,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await settle(tester);
  disposeInvestorStatementVm(built);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  tearDown(() => RoleAccessService.instance.setCurrentUser(null));

  // Roles carry the capability defaults the office actually ships, so these
  // tests read like the real thing rather than a hand-built permission map.
  void signInAs(String role) =>
      RoleAccessService.instance.setCurrentUser(UserModel(id: '1', role: role));

  group('the entry point', () {
    // The button that opens this sits on the Vehicle Makes screen and is gated
    // on one capability. That gate is the whole of the access control for a
    // reports-only feature, so it is pinned by role rather than left implicit.
    test('the entry is offered to an admin and withheld from a dispatcher', () {
      signInAs('admin');
      expect(
        RoleAccessService.instance.canAccess(
          DispatcherAccessCapability.investorEarningsRead,
        ),
        isTrue,
      );
      signInAs('dispatcher');
      expect(
        RoleAccessService.instance.canAccess(
          DispatcherAccessCapability.investorEarningsRead,
        ),
        isFalse,
      );
    });

    test('the platform share is admin-only to change', () {
      signInAs('admin');
      expect(
        RoleAccessService.instance.canAccess(
          DispatcherAccessCapability.investorCommissionRateUpdate,
        ),
        isTrue,
      );
      signInAs('investor');
      expect(
        RoleAccessService.instance.canAccess(
          DispatcherAccessCapability.investorCommissionRateUpdate,
        ),
        isFalse,
      );
    });
  });

  group('the dialog', () {
    testWidgets('offers the investors that own a truck', (tester) async {
      signInAs('admin');
      final built = await open(tester);
      expect(find.text('Investor Statement'), findsOneWidget);
      await tester.tap(find.text('Select Investor').last);
      await settle(tester);
      // Accounts, chosen from a list, named by the person - not typed.
      expect(find.text('Dela Cruz'), findsOneWidget);
      expect(find.text('Reyes'), findsOneWidget);
      // A company truck is not an investor.
      expect(find.text('Paltranco'), findsNothing);
      expect(tester.takeException(), isNull);
      await close(tester, built);
    });

    testWidgets('says so plainly when no truck has an owner', (tester) async {
      signInAs('admin');
      final built = await open(
        tester,
        makes: [VehicleMake(id: '7', code: 'PM7')],
      );
      expect(
        find.textContaining('No truck on file belongs to an investor'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await close(tester, built);
    });

    testWidgets('without the capability it refuses to open a statement', (
      tester,
    ) async {
      signInAs('dispatcher');
      final built = await open(tester);
      expect(
        find.textContaining('do not have access to investor earnings'),
        findsOneWidget,
      );
      expect(find.text('Generate statement'), findsNothing);
      expect(tester.takeException(), isNull);
      await close(tester, built);
    });

    testWidgets('shows the platform share and can save it', (tester) async {
      signInAs('admin');
      final built = await open(tester);
      expect(find.text('Platform share (%)'), findsWidgets);
      await tester.enterText(
        find.widgetWithText(TextField, 'Platform share (%)'),
        '12.5',
      );
      await tester.tap(find.text('Save share'));
      await settle(tester);
      expect(tester.takeException(), isNull);
      // And the field keeps what was saved.
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'Platform share (%)'),
            )
            .controller!
            .text,
        '12.5',
      );
      await close(tester, built);
    });

    testWidgets('rejects a share that is not a real percentage', (
      tester,
    ) async {
      signInAs('admin');
      final built = await open(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Platform share (%)'),
        '0',
      );
      await tester.tap(find.text('Save share'));
      await settle(tester);
      expect(
        find.textContaining('more than 0% and less than 100%'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await close(tester, built);
    });

    testWidgets('a rejected share is not a failed statement', (tester) async {
      signInAs('admin');
      final built = await open(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Platform share (%)'),
        'abc',
      );
      await tester.tap(find.text('Save share'));
      await settle(tester);
      expect(
        find.textContaining('Enter the platform share as a number'),
        findsOneWidget,
      );
      // The statement controls are still there and still usable.
      expect(find.text('Generate statement'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await close(tester, built);
    });

    testWidgets('a month can be chosen and generation is offered', (
      tester,
    ) async {
      signInAs('admin');
      final built = await open(tester);
      expect(find.text('Select Month'), findsWidgets);
      await tester.tap(find.text('Select Month').last);
      await settle(tester);
      expect(tester.takeException(), isNull);
      // This month plus seventeen back.
      expect(find.textContaining('20'), findsWidgets);
      await close(tester, built);
    });

    testWidgets('without the share capability the field is read only', (
      tester,
    ) async {
      signInAs('investor');
      final built = await open(tester);
      expect(
        find.text('You do not have access to change the platform share.'),
        findsOneWidget,
      );
      final save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save share'),
      );
      expect(save.onPressed, isNull);
      expect(tester.takeException(), isNull);
      await close(tester, built);
    });
  });
}
