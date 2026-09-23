import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/utils/booking_party_search.dart';

void main() {
  const booking = Booking(
    client: UserModel(id: '1', name: 'Acme Client'),
    driver: UserModel(id: '2', name: 'Juan Driver'),
    helper: UserModel(id: '3', name: 'Pedro Helper'),
  );
  test(
    'client, driver and helper names remain searchable from offline booking data',
    () {
      final terms = bookingPartySearchTerms(
        booking,
        {},
      ).join(' ').toLowerCase();
      for (final query in ['acme', 'juan', 'pedro']) {
        expect(terms.contains(query), isTrue);
      }
    },
  );
  test(
    'loaded names take precedence, but blank loaded names preserve snapshot fallback',
    () {
      expect(
        bookingPartySearchTerms(booking, {
          '1': const UserModel(id: '1', name: 'Updated Client'),
          '2': const UserModel(id: '2', name: ' '),
        }),
        ['Updated Client', 'Juan Driver', 'Pedro Helper'],
      );
      expect(bookingPartySearchTerms(const Booking(), {}), ['', '', '']);
    },
  );
}
