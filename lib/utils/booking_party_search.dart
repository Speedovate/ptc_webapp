import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';

/// Uses loaded user records, falling back to the booking's offline snapshot.
Iterable<String> bookingPartySearchTerms(
  Booking booking,
  Map<String, UserModel> users,
) sync* {
  for (final party in [booking.client, booking.driver, booking.helper]) {
    final currentName = users[party?.id]?.name?.trim();
    yield currentName?.isNotEmpty == true ? currentName! : party?.name ?? '';
  }
}
