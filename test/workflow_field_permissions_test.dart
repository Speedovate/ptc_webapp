import 'package:webapp/services/status_form_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/dispatcher_access_config.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/models/status_form.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/role_access.request.dart';
import 'package:webapp/repositories/interfaces/status_form_repository.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:webapp/view_models/shared/booking_workflow.vm.dart';
import 'package:webapp/views/shared/booking_workflow_view.dart';

class _Roles extends RoleAccessRequest {
  @override
  Future<List<DispatcherAccessConfig>> getAllRoleAccessConfigs() async => [];
  @override
  Stream<void> watchRoleAccessCacheUpdates() => const Stream.empty();
  @override
  Future<DispatcherAccessConfig> saveRoleAccess(
    DispatcherAccessConfig config,
  ) async => config;
}

class _Forms extends Fake implements StatusFormRepository {
  int writes = 0;
  @override
  Future<void> saveField(StatusField field) async {
    writes++;
  }

  @override
  Future<void> saveStatusForm(StatusForm form) async {
    writes++;
  }

  @override
  Future<void> saveFields(String formId, List<StatusField> fields) async {
    writes++;
  }

  @override
  Future<List<StatusField>> getAllFields() async => [assigned, extra];
}

const assigned = StatusField(
  id: '1',
  key: 'office_note',
  type: 'text',
  title: 'Office Note',
);
const extra = StatusField(
  id: '2',
  key: 'extra_note',
  type: 'text',
  title: 'Extra Note',
);
const dispatcher = UserModel(id: 'dispatcher-permissions', role: 'dispatcher');
const booking = Booking(id: 'permissions-booking', clientStatus: 'pending');
const form = StatusForm(
  id: 'assign',
  role: 'admin',
  currentStatusKey: 'pending',
  nextStatusKey: 'assigned',
  statusText: 'Assign Booking',
  buttonText: 'Assign Booking',
  fields: [assigned],
);
final management = [
  DispatcherAccessCapability.fieldsCreate,
  DispatcherAccessCapability.fieldsUpdate,
  DispatcherAccessCapability.fieldsDelete,
  DispatcherAccessCapability.formsUpdate,
];
Future<void> configure(RoleAccessService access, Iterable<String> enabled) =>
    access.saveRoleAccess(
      DispatcherAccessConfig.defaults(roleKey: 'dispatcher').copyWith(
        capabilities: {
          DispatcherAccessCapability.bookingsRead: true,
          DispatcherAccessCapability.bookingsUpdate: true,
          DispatcherAccessCapability.usersRead: true,
          DispatcherAccessCapability.fieldsRead: false,
          DispatcherAccessCapability.formsRead: false,
          for (final key in management) key: enabled.contains(key),
        },
      ),
    );

class _ReadyWorkflow extends BookingWorkflowViewModel {
  int pageBuilds = 0;
  @override
  String currentStatusLabel() {
    pageBuilds++;
    return super.currentStatusLabel();
  }

  _ReadyWorkflow(RoleAccessService access, _Forms repo)
    : super(roleAccessService: access, statusRepository: repo) {
    user = dispatcher;
    this.booking = booking;
    this.form = form;
    mainForms = [form];
    fields = [assigned];
    fieldLibrary = [assigned, extra];
  }
  @override
  Future<void> load({
    required UserModel user,
    required Booking booking,
    bool hydrateInitialAnswers = true,
  }) async {}
  @override
  List<StatusField> fieldsForForm(
    StatusForm activeForm, {
    Map<String, dynamic>? answers,
  }) => StatusFormEngine.visibleFields(fields, answers ?? this.answers);
  @override
  bool isFormAssignedField(StatusField field) =>
      fields.any((f) => f.id == field.id);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'four permissions independently gate mutations; viewing and answering remains available',
    () async {
      final access = RoleAccessService(request: _Roles());
      addTearDown(access.dispose);
      final repo = _Forms();
      final vm =
          BookingWorkflowViewModel(
              roleAccessService: access,
              statusRepository: repo,
            )
            ..user = dispatcher
            ..booking = booking
            ..form = form
            ..mainForms = [form]
            ..fields = [assigned]
            ..fieldLibrary = [assigned, extra];
      addTearDown(vm.dispose);
      await configure(access, []);
      expect(vm.fields, [assigned]);
      vm.updateAnswer('office_note', 'Dispatch note');
      expect(vm.answers['office_note'], 'Dispatch note');
      expect(vm.canUpdateBooking, isTrue);
      expect(vm.supportsAdditionalFields, isFalse);
      await expectLater(
        vm.saveLibraryField(assigned.copyWith(title: 'Changed')),
        throwsStateError,
      );
      await expectLater(
        vm.saveLibraryField(
          const StatusField(id: 'new', key: 'new', type: 'text'),
        ),
        throwsStateError,
      );
      await vm.addExistingField('2');
      vm.removeManagedField(assigned);
      vm.reorderManagedFields([assigned], 0, 0);
      expect(repo.writes, 0);
      expect(vm.fields, [assigned]);
      await configure(access, [DispatcherAccessCapability.fieldsUpdate]);
      expect(vm.canEditWorkflowFields, isTrue);
      expect(vm.canAddWorkflowFields, isFalse);
      expect(vm.canRemoveWorkflowFields, isFalse);
      expect(vm.canReorderWorkflowFields, isFalse);
      await vm.saveLibraryField(assigned.copyWith(title: 'Renamed'));
      expect(repo.writes, 1);
      await configure(access, [DispatcherAccessCapability.fieldsCreate]);
      expect(
        vm.canAddWorkflowFields,
        isFalse,
        reason: 'Assigning a field also changes the form',
      );
      await configure(access, [DispatcherAccessCapability.formsUpdate]);
      expect(vm.canReorderWorkflowFields, isTrue);
      expect(vm.canEditWorkflowFields, isFalse);
      expect(vm.canRemoveWorkflowFields, isFalse);
      await configure(access, [
        DispatcherAccessCapability.fieldsCreate,
        DispatcherAccessCapability.formsUpdate,
      ]);
      expect(vm.canAddWorkflowFields, isTrue);
      await vm.addExistingField('2');
      expect(vm.fields.map((f) => f.key), contains('extra_note'));
      await configure(access, [DispatcherAccessCapability.fieldsDelete]);
      expect(vm.canRemoveWorkflowFields, isFalse);
      await configure(access, [
        DispatcherAccessCapability.fieldsDelete,
        DispatcherAccessCapability.formsUpdate,
      ]);
      expect(vm.canRemoveWorkflowFields, isTrue);
      vm.removeManagedField(extra);
      expect(vm.fields.map((f) => f.key), isNot(contains('extra_note')));
      await configure(access, []);
      final writes = repo.writes;
      vm.removeManagedField(assigned);
      expect(
        repo.writes,
        writes,
        reason: 'Revoked permissions also block an already-open workflow',
      );
    },
  );
  testWidgets(
    'typing updates only the form while conditional fields and resets still work',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final access = RoleAccessService(request: _Roles());
      addTearDown(access.dispose);
      final vm = _ReadyWorkflow(access, _Forms());
      addTearDown(vm.dispose);
      vm.fields = [
        assigned,
        const StatusField(
          id: 'follow',
          key: 'follow_up',
          type: 'text',
          title: 'Follow Up',
          required: true,
          visibilityControllerKey: 'office_note',
          visibilityOptionValues: ['show'],
        ),
      ];
      vm.form = form.copyWith(fields: vm.fields);
      await configure(access, []);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BookingWorkflowView(
              user: dispatcher,
              booking: booking,
              viewModel: vm,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final pageBuilds = vm.pageBuilds;
      expect(find.text('Follow Up'), findsNothing);
      for (final value in ['s', 'sh', 'show']) {
        await tester.enterText(find.byType(TextField).first, value);
        await tester.pump();
        expect(vm.answers['office_note'], value);
        expect(
          vm.pageBuilds,
          pageBuilds,
          reason: 'Typing must not rebuild the booking page',
        );
      }
      expect(find.text('Follow Up *'), findsOneWidget);
      expect(vm.validateForSubmit(), isFalse);
      await tester.pumpAndSettle();
      expect(find.text('Follow Up is required.'), findsOneWidget);
      final validationBuilds = vm.pageBuilds;
      await tester.enterText(find.byType(TextField).last, 'Ready');
      await tester.pump();
      expect(vm.pageBuilds, validationBuilds);
      expect(find.text('Follow Up is required.'), findsNothing);
      expect(vm.validateForSubmit(), isTrue);
      vm.clearForm();
      await tester.pumpAndSettle();
      expect(find.text('Follow Up'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'assigned fields stay visible with management and view-library permissions off; controls follow live grants',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final access = RoleAccessService(request: _Roles());
      addTearDown(access.dispose);
      final vm = _ReadyWorkflow(access, _Forms());
      addTearDown(vm.dispose);
      await configure(access, []);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BookingWorkflowView(
              user: dispatcher,
              booking: booking,
              viewModel: vm,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Office Note'), findsOneWidget);
      expect(find.byIcon(Icons.delete_rounded), findsNothing);
      expect(find.byIcon(Icons.edit_rounded), findsNothing);
      expect(find.byIcon(Icons.drag_indicator_rounded), findsNothing);
      expect(find.text('Add Field'), findsNothing);
      await configure(access, [DispatcherAccessCapability.fieldsUpdate]);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.edit_rounded), findsOneWidget);
      expect(find.byIcon(Icons.delete_rounded), findsNothing);
      expect(find.byIcon(Icons.drag_indicator_rounded), findsNothing);
      await configure(access, management);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.delete_rounded), findsOneWidget);
      expect(find.byIcon(Icons.drag_indicator_rounded), findsOneWidget);
      expect(find.text('Add Field'), findsOneWidget);
      await configure(access, []);
      await tester.pumpAndSettle();
      expect(find.text('Office Note'), findsOneWidget);
      expect(find.byIcon(Icons.edit_rounded), findsNothing);
      expect(find.byIcon(Icons.delete_rounded), findsNothing);
      expect(find.text('Add Field'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
