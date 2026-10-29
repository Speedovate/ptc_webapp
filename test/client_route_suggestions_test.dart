import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/models/status_form.dart';
import 'package:webapp/repositories/interfaces/status_form_repository.dart';
import 'package:webapp/services/client_route_suggestions.dart';
import 'package:webapp/services/status_field_option_resolver.dart';
import 'package:webapp/services/status_form_engine.dart';
import 'package:webapp/widgets/status_form/status_form_runtime_fields.dart';

class _Forms extends Fake implements StatusFormRepository {}

final engine = StatusFormEngine(_Forms());
final fields = [
  for (final key in bookingRouteKeys)
    StatusField(
      id: key,
      key: key,
      type: 'dropdown',
      placeholder: 'Enter location',
      required: true,
      options: const ['Known option'],
    ),
];
Booking saved(
  String client,
  String representative,
  Map<String, String> route,
) => Booking(
  id: '$client:$representative:${route.values.join()}',
  client: UserModel(id: client),
  statusOutputs: {
    'book': {
      'submitted_at': '2026-10-29T08:00:00Z',
      'fields': {'representative_name': representative, ...route},
    },
  },
);

class _ObservedBooking extends Booking {
  _ObservedBooking() : super(client: const UserModel(id: 'a'));
  int historyReads = 0;
  @override
  Map<String, dynamic> get statusOutputs {
    historyReads++;
    return {
      'book': {
        'fields': {
          'representative_name': 'Rep One',
          'origin': 'Saved custom origin',
        },
      },
    };
  }
}

void main() {
  test(
    'history is scoped to main client and representative, with independent fields',
    () {
      final bookings = [
        saved('a', 'Rep One', {
          'origin': 'Custom origin',
          'destination': 'Puerto Princesa City',
          'destination_barangay': 'City Proper - San Pedro',
        }),
        saved('a', 'Rep Two', {'origin': 'Other representative area'}),
        saved('b', 'Rep One', {'origin': 'Other client area'}),
      ];
      final routes = clientRepresentativeRoutes(bookings, 'a', ' rep one ');
      expect(routeFieldSuggestions(routes, 'origin', {}), ['Custom origin']);
      expect(routeFieldSuggestions(routes, 'destination', {}), [
        'Puerto Princesa City',
      ]);
      expect(
        routeFieldSuggestions(routes, 'destination_barangay', {
          'destination': 'PPC',
        }),
        ['City Proper - San Pedro'],
      );
      expect(
        routeFieldSuggestions(routes, 'destination_barangay', {
          'destination': 'Roxas',
        }),
        isEmpty,
      );
      expect(clientRepresentativeRoutes(bookings, 'a', null), isEmpty);
    },
  );
  test(
    'new saved values refresh cached suggestions without changing answers or amounts',
    () {
      final resolver = StatusFieldOptionResolver();
      final answers = <String, dynamic>{
        'representative_name': 'Rep One',
        'origin': 'Puerto Princesa City',
        'destination': 'Puerto Princesa City',
        'amount': 4100,
      };
      List<StatusField> options() =>
          resolver.withClientRepresentativeSuggestions(
            fields,
            clientId: 'a',
            answers: answers,
          );
      expect(options().first.options, isNot(contains('Bayan to San Pedro')));
      resolver.rememberSavedBooking(
        saved('a', 'Rep One', {
          'origin': 'Bayan to San Pedro',
          'destination': 'Lagpas ng San Pedro',
          'origin_barangay': 'City Proper',
          'destination_barangay': 'City Proper - beyond San Pedro',
        }),
      );
      expect(options().first.options, contains('Bayan to San Pedro'));
      expect(
        options().firstWhere((f) => f.key == 'destination').options,
        contains('Lagpas ng San Pedro'),
      );
      expect(answers['origin'], 'Puerto Princesa City');
      expect(answers['amount'], 4100);
      final other = resolver.withClientRepresentativeSuggestions(
        fields,
        clientId: 'a',
        answers: {...answers, 'representative_name': 'Rep Two'},
      );
      expect(other.first.options, isNot(contains('Bayan to San Pedro')));
    },
  );
  test('custom strings validate and save; barangays show only for PPC', () {
    final answers = <String, dynamic>{
      'representative_name': 'Rep One',
      'origin': 'PPC',
      'origin_barangay': 'City Proper - San Pedro',
      'destination': 'Custom destination',
      'destination_barangay': 'Stale barangay',
      'amount': 3500,
    };
    expect(engine.validateFields(fields, answers), isEmpty);
    expect(
      StatusFormEngine.visibleFields(fields, answers).map((f) => f.key),
      isNot(contains('destination_barangay')),
    );
    expect(
      engine.validateFields(fields, {...answers, 'origin_barangay': ''}),
      contains('origin_barangay'),
    );
    final result = engine.applyOutputToBooking(
      const Booking(),
      const StatusForm(currentStatusKey: 'book', nextStatusKey: 'pending'),
      fields,
      answers,
      'user',
      'client',
    );
    final stored =
        (result.statusOutputs!.values.single as Map)['fields'] as Map;
    expect(stored['origin_barangay'], 'City Proper - San Pedro');
    expect(stored['destination'], 'Custom destination');
    expect(stored.containsKey('destination_barangay'), isFalse);
    expect(stored['amount'], 3500);
  });
  test(
    'partial representative typing reuses history instead of rescanning all bookings',
    () {
      final history = List.generate(1000, (_) => _ObservedBooking());
      final resolver = StatusFieldOptionResolver()..setBookingHistory(history);
      List<StatusField> options(String name) =>
          resolver.withClientRepresentativeSuggestions(
            fields,
            clientId: 'a',
            answers: {'representative_name': name},
          );
      options('R');
      final reads = history.fold(
        0,
        (total, booking) => total + booking.historyReads,
      );
      for (final query in ['Re', 'Rep', 'Rep O', 'Rep On', 'Never saved']) {
        options(query);
      }
      expect(
        history.fold(0, (total, booking) => total + booking.historyReads),
        reads,
      );
      expect(options('Rep One').first.options, contains('Saved custom origin'));
      final matchedReads = history.fold(
        0,
        (total, booking) => total + booking.historyReads,
      );
      options('Rep One');
      expect(
        history.fold(0, (total, booking) => total + booking.historyReads),
        matchedReads,
      );
    },
  );
  testWidgets(
    'all four fields accept arbitrary text and selecting one changes only that field',
    (tester) async {
      final resolver = StatusFieldOptionResolver();
      resolver.rememberSavedBooking(
        saved('a', 'Rep One', {
          'origin': 'Custom saved origin',
          'destination': 'Custom saved destination',
          'origin_barangay': 'City Proper - San Pedro',
          'destination_barangay': 'Beyond San Pedro',
        }),
      );
      var answers = <String, dynamic>{
        'representative_name': 'Rep One',
        'origin': 'PPC',
        'destination': 'PPC',
        'amount': 4100,
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, update) {
                  final resolved = resolver.withClientRepresentativeSuggestions(
                    fields,
                    clientId: 'a',
                    answers: answers,
                  );
                  return Column(
                    children: [
                      for (final field in resolved)
                        StatusFormRuntimeFieldInput(
                          key: ValueKey<String>(field.key!),
                          field: field,
                          initialValue: answers[field.key],
                          onChanged: (value) => update(
                            () => answers = {...answers, field.key!: value},
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
      final origin = find.descendant(
        of: find.byKey(const ValueKey('origin')),
        matching: find.byType(TextField),
      );
      await tester.tap(origin);
      await tester.pump();
      expect(find.byType(TextButton), findsNothing);
      await tester.enterText(origin, 'saved origin');
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Custom saved origin'));
      await tester.pump();
      expect(answers['origin'], 'Custom saved origin');
      expect(answers['destination'], 'PPC');
      expect(answers['amount'], 4100);
      for (final key in bookingRouteKeys) {
        final input = find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(TextField),
        );
        await tester.ensureVisible(input);
        await tester.enterText(input, 'New manual $key');
        await tester.pump();
        expect(answers[key], 'New manual $key');
      }
      expect(answers['amount'], 4100);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
