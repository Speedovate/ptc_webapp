import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/widgets/shared/admin_modal_form_primitives.dart';
import 'package:webapp/widgets/shared/client_representative_name_input.dart';

final history = [
  Booking(
    id: 'no-phone',
    client: const UserModel(id: 'moreta'),
    statusOutputs: {
      'pending': {
        'fields': {'representative_name': 'New Contact Without Phone'},
      },
    },
  ),
  Booking(
    id: '1',
    client: const UserModel(id: 'moreta'),
    statusOutputs: {
      'pending': {
        'fields': {
          'representative_name': 'New Panay',
          'representative_phone': '09171234567',
        },
      },
    },
  ),
  Booking(
    id: '2',
    client: const UserModel(id: 'other'),
    statusOutputs: {
      'pending': {
        'fields': {
          'representative_name': 'New Other Client',
          'representative_phone': '09179876543',
        },
      },
    },
  ),
];
Widget editor({
  required String client,
  required TextEditingController name,
  required TextEditingController phone,
}) => Column(
  children: [
    ClientRepresentativeNameInput(
      clientId: client,
      bookings: history,
      nameController: name,
      phoneController: phone,
      child: AdminModalTextField(
        controller: name,
        label: 'Representative Name',
        bottomPadding: 0,
      ),
    ),
    AdminModalTextField(controller: phone, label: 'Representative Phone'),
  ],
);
void main() {
  testWidgets(
    'edit booking name input shows matching saved names and fills phone on selection',
    (tester) async {
      final name = TextEditingController();
      final phone = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: editor(client: 'moreta', name: name, phone: phone),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField).first, 'New');
      await tester.pump();
      expect(find.text('New Panay'), findsOneWidget);
      expect(find.text('New Other Client'), findsNothing);
      expect(find.text('+639171234567'), findsOneWidget);
      expect(find.text('New Contact Without Phone'), findsOneWidget);
      expect(find.text('Walang phone number'), findsOneWidget);
      await tester.tap(find.text('New Panay'));
      await tester.pump();
      expect(name.text, 'New Panay');
      expect(phone.text, '+639171234567');
      await tester.enterText(
        find.byType(TextField).first,
        'A new representative',
      );
      expect(name.text, 'A New Representative');
      await tester.pumpWidget(const SizedBox());
      name.dispose();
      phone.dispose();
    },
  );
  testWidgets('exact typed name remains selectable and fills the phone', (
    tester,
  ) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: editor(client: 'moreta', name: name, phone: phone),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'New Panay');
    await tester.pump();
    final suggestion = find.widgetWithText(TextButton, 'New Panay');
    expect(suggestion, findsOneWidget);
    expect(find.text('+639171234567'), findsOneWidget);
    expect(phone.text, isEmpty);
    await tester.tap(suggestion);
    await tester.pump();
    expect(name.text, 'New Panay');
    expect(phone.text, '+639171234567');
    expect(suggestion, findsNothing);
    await tester.pumpWidget(const SizedBox());
    name.dispose();
    phone.dispose();
  });
  testWidgets('changing Booked By removes the previous client suggestions', (
    tester,
  ) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    var client = 'moreta';
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return editor(client: client, name: name, phone: phone);
            },
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'New');
    await tester.pump();
    expect(find.text('New Panay'), findsOneWidget);
    update(() => client = 'other');
    await tester.pump();
    expect(name.text, 'New');
    expect(find.text('New Panay'), findsNothing);
    expect(find.text('New Other Client'), findsOneWidget);
    await tester.tap(find.text('New Other Client'));
    await tester.pump();
    expect(phone.text, '+639179876543');
    await tester.pumpWidget(const SizedBox());
    name.dispose();
    phone.dispose();
  });
  testWidgets('selecting a representative replaces a manually edited phone', (
    tester,
  ) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: editor(client: 'moreta', name: name, phone: phone),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).last, '09175555555');
    await tester.enterText(find.byType(TextField).first, 'New');
    await tester.pump();
    await tester.tap(find.text('New Panay'));
    await tester.pump();
    expect(phone.text, '+639171234567');
    await tester.pumpWidget(const SizedBox());
    name.dispose();
    phone.dispose();
  });
}
