import 'package:webapp/widgets/shared/paged_data_sliver.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/status.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/repositories/interfaces/booking_repository.dart';
import 'package:webapp/repositories/interfaces/status_form_repository.dart';
import 'package:webapp/widgets/shared/lazy_data_scroll_view.dart';
import 'package:webapp/widgets/shared/user_bookings_section.dart';

class _Bookings extends Fake implements BookingRepository {
  _Bookings(this.items, {this.pending});
  final Future<List<Booking>>? pending;
  final List<Booking> items;
  final updates = StreamController<List<Booking>>.broadcast();
  @override
  Future<void> initialize() async {}
  @override
  Future<List<Booking>> getBookings() async =>
      pending == null ? items : await pending!;
  @override
  Stream<List<Booking>> watchBookings() => updates.stream;
}

class _Statuses extends Fake implements StatusFormRepository {
  _Statuses({this.pending});
  final Future<List<Status>>? pending;
  @override
  Future<List<Status>> getStatuses() async =>
      pending == null ? [] : await pending!;
}

void main() {
  testWidgets(
    'bookings load before labels and stale reads cannot replace live data',
    (tester) async {
      final labels = Completer<List<Status>>();
      final initial = Completer<List<Booking>>();
      final user = UserModel(id: 'delayed-profile', role: 'client');
      final repo = _Bookings([], pending: initial.future);
      addTearDown(repo.updates.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PagedScrollObserver(
              child: LazyDataScrollView(
                child: UserBookingsSection(
                  user: user,
                  bookingRepository: repo,
                  statusRepository: _Statuses(pending: labels.future),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      repo.updates.add([Booking(id: '901', client: user)]);
      await tester.pumpAndSettle();
      expect(find.byType(PagedDataSliver<Booking>), findsOneWidget);
      initial.complete([]);
      await tester.pumpAndSettle();
      expect(find.byType(PagedDataSliver<Booking>), findsOneWidget);
      labels.complete([]);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      expect(repo.updates.hasListener, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'switching profile clears old rows and ignores disposed pending loads',
    (tester) async {
      final initial = Completer<List<Booking>>();
      final labels = Completer<List<Status>>();
      final first = UserModel(id: 'switch-first', role: 'client');
      final second = UserModel(id: 'switch-second', role: 'client');
      final repo = _Bookings([], pending: initial.future);
      final statuses = _Statuses(pending: labels.future);
      addTearDown(repo.updates.close);
      Widget host(UserModel user) => MaterialApp(
        home: Scaffold(
          body: PagedScrollObserver(
            child: LazyDataScrollView(
              child: UserBookingsSection(
                user: user,
                bookingRepository: repo,
                statusRepository: statuses,
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(host(first));
      await tester.pump();
      repo.updates.add([Booking(id: '902', client: first)]);
      await tester.pumpAndSettle();
      expect(find.byType(PagedDataSliver<Booking>), findsOneWidget);
      await tester.pumpWidget(host(second));
      await tester.pump();
      expect(find.byType(PagedDataSliver<Booking>), findsNothing);
      await tester.pumpWidget(const SizedBox());
      initial.complete([Booking(id: '902', client: first)]);
      labels.complete([]);
      await tester.pumpAndSettle();
      expect(repo.updates.hasListener, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  for (final role in ['admin', 'client', 'driver', 'helper']) {
    for (final width in [400.0, 2400.0]) {
      testWidgets(
        '$role profile bookings at $width stay lazy and update from stream',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 800));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final user = UserModel(id: '$role-$width', role: role);
          final repo = _Bookings(
            List.generate(
              1000,
              (i) => Booking(
                id: '$i',
                client: user,
                driver: user,
                helper: user,
                statusOutputs: {
                  'submitted': {'submitted_by': user.id},
                },
              ),
            ),
          );
          addTearDown(repo.updates.close);
          String? opened;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: PagedScrollObserver(
                  child: LazyDataScrollView(
                    child: SliverSection(
                      children: [
                        const SizedBox(height: 120, child: Text('Profile')),
                        UserBookingsSection(
                          user: user,
                          padding: const EdgeInsets.all(24),
                          useAdminListStyle: role == 'admin',
                          bookingRepository: repo,
                          statusRepository: _Statuses(),
                          onViewBooking: (booking) async {
                            opened = booking.id;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byType(Text).evaluate().length, lessThan(400));
          final action = find.byIcon(Icons.visibility_rounded);
          expect(action, findsWidgets);
          await tester.tap(action.first);
          expect(opened, '999');
          await tester.drag(
            find.byType(CustomScrollView),
            const Offset(0, -600),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byType(Text).evaluate().length, lessThan(400));
          repo.updates.add([]);
          await tester.pumpAndSettle();
          expect(find.text('No bookings yet.'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          expect(repo.updates.hasListener, isFalse);
        },
      );
    }
  }
}
