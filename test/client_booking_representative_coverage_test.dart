import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/status_form.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/repositories/interfaces/booking_repository.dart';
import 'package:webapp/services/status_field_option_resolver.dart';
import 'package:webapp/view_models/client/client_booking_home.vm.dart';
import 'package:webapp/views/client/client_booking_home_view.dart';
import 'package:webapp/widgets/status_form/status_form_preview.dart';

const fields = [
  StatusField(
    id: 'name',
    key: 'representative_name',
    title: 'Representative Name',
    type: 'text',
    optionSourceKey: statusFieldOptionSourceClientRepresentatives,
  ),
  StatusField(
    id: 'phone',
    key: 'representative_phone',
    title: 'Representative Phone',
    type: 'phone',
  ),
];
const form = StatusForm(
  id: 'book',
  role: 'client',
  currentStatusKey: 'book',
  nextStatusKey: 'pending',
  isActive: true,
  isMainForm: true,
  fields: fields,
);
final history = [
  Booking(
    id: 'no-phone',
    client: const UserModel(id: 'a'),
    statusOutputs: {
      'pending': {
        'fields': {'representative_name': 'Contact Without Phone'},
      },
    },
  ),
  Booking(
    id: 'a-trip',
    createdAt: DateTime.utc(2026, 10, 29),
    client: const UserModel(id: 'a'),
    statusOutputs: {
      'pending': {
        'fields': {
          'representative_name': 'Alice',
          'representative_phone': '09171234567',
        },
      },
    },
  ),
  Booking(
    id: 'a-older-trip',
    client: const UserModel(id: 'a'),
    createdAt: DateTime.utc(2026, 10, 1),
    statusOutputs: {
      'pending': {
        'fields': {
          'representative_name': 'Alice',
          'representative_phone': '09179876543',
        },
      },
    },
  ),
  Booking(
    id: 'b-trip',
    client: const UserModel(id: 'b'),
    statusOutputs: {
      'pending': {
        'fields': {
          'representative_name': 'Bob',
          'representative_phone': '09179876543',
        },
      },
    },
  ),
];

class _Bookings implements BookingRepository {
  @override
  Future<void> initialize() async {}
  @override
  Future<List<Booking>> getBookings() async => history;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ReadyForm extends ClientBookingHomeViewModel {
  _ReadyForm(this.resolver) {
    mainForms = [form];
    this.form = form;
  }
  final StatusFieldOptionResolver resolver;
  @override
  Future<void> load(UserModel clientUser) async {}
  @override
  void syncClient(UserModel clientUser) {}
  @override
  List<StatusField> fieldsForForm(
    StatusForm form, {
    Map<String, dynamic>? answers,
    String? clientId,
  }) =>
      resolver.withClientRepresentativeSuggestions(fields, clientId: clientId);
  @override
  String? representativePhoneForSelection(String name, {String? clientId}) =>
      resolver.representativePhone(clientId, name);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ClientBookingHomeViewModel.clearCachedState();
  });
  for (final client in ['a', 'b']) {
    testWidgets(
      'full New Booking/client form fills the paired phone for client $client',
      (tester) async {
        final resolver = StatusFieldOptionResolver(
          bookingRepository: _Bookings(),
        );
        await resolver.hydrateFields(fields);
        final vm = _ReadyForm(resolver);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ClientBookingHomeView(
                user: UserModel(id: client, role: 'client', isActive: true),
                viewModel: vm,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).last, '09175555555');
        await tester.tap(find.byType(TextField).first);
        await tester.pump();
        expect(find.widgetWithText(TextButton, 'Alice'), findsNothing);
        expect(find.widgetWithText(TextButton, 'Bob'), findsNothing);
        expect(
          find.widgetWithText(TextButton, 'Contact Without Phone'),
          findsNothing,
        );
        await tester.enterText(find.byType(TextField).first, 'Contact');
        await tester.pump();
        if (client == 'a') {
          expect(find.text('Contact Without Phone'), findsOneWidget);
          expect(find.text('Walang phone number'), findsOneWidget);
        } else {
          expect(find.text('Contact Without Phone'), findsNothing);
        }
        final name = client == 'a' ? 'Alice' : 'Bob';
        await tester.enterText(find.byType(TextField).first, name);
        await tester.pump();
        expect(find.text(name), findsNWidgets(2));
        final row = find.ancestor(
          of: find.text(name),
          matching: find.byType(TextButton),
        );
        expect(
          find.descendant(
            of: row,
            matching: find.text(
              client == 'a' ? '+639171234567' : '+639179876543',
            ),
          ),
          findsOneWidget,
        );
        expect(find.text(client == 'a' ? 'Bob' : 'Alice'), findsNothing);
        await tester.tap(find.widgetWithText(TextButton, name));
        await tester.pump();
        final inputs = tester
            .widgetList<TextField>(find.byType(TextField))
            .toList();
        expect(inputs[0].controller!.text, name);
        expect(
          inputs[1].controller!.text,
          client == 'a' ? '+639171234567' : '+639179876543',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets(
    'designer preview without client context does not expose mixed-client names',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatusFormPreview(
                form: form,
                fields: [
                  fields.first.copyWith(options: ['Alice', 'Bob']),
                  fields.last,
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      expect(find.text('Alice'), findsNothing);
      expect(find.text('Bob'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
