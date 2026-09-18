import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/status_form.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/repositories/interfaces/booking_repository.dart';
import 'package:webapp/view_models/client/client_booking_home.vm.dart';

class _Bookings extends Fake implements BookingRepository {
  final attempts = <Booking>[];
  bool fail = true;
  @override
  Future<Booking> saveBooking(Booking booking) async {
    attempts.add(booking);
    if (fail) {
      throw StateError('save failed');
    }
    return booking.copyWith(id: 'offline_${booking.submissionKey}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'form retries preserve original time and event; changed form gets new key',
    () async {
      final repository = _Bookings();
      final vm = ClientBookingHomeViewModel(bookingRepository: repository);
      addTearDown(vm.dispose);
      const form = StatusForm(
        id: '1',
        currentStatusKey: 'book',
        nextStatusKey: 'pending',
      );
      Future<Booking?> submit(int amount) => vm.submitForm(
        activeForm: form,
        formAnswers: {'amount': amount},
        clientUser: const UserModel(id: '9'),
        submittedByUserId: '8',
        submittedByUserRole: 'dispatcher',
      );
      await expectLater(submit(100), throwsStateError);
      await expectLater(submit(100), throwsStateError);
      expect(repository.attempts[1].toMap(), repository.attempts[0].toMap());
      await expectLater(submit(200), throwsStateError);
      expect(
        repository.attempts[2].submissionKey,
        isNot(repository.attempts[0].submissionKey),
      );
      vm.resetPendingSubmission();
      await expectLater(submit(200), throwsStateError);
      expect(
        repository.attempts[3].submissionKey,
        isNot(repository.attempts[2].submissionKey),
      );
      repository.fail = false;
      final saved = await submit(200);
      expect(saved!.createdAt, repository.attempts[3].createdAt);
      final next = await submit(200);
      expect(next!.submissionKey, isNot(saved.submissionKey));
    },
  );
}
