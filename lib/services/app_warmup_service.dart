import 'package:webapp/models/support_thread.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/requests/booking.request.dart';
import 'package:webapp/requests/client_member.request.dart';
import 'package:webapp/requests/status.request.dart';
import 'package:webapp/requests/support.request.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/utils/functions.dart';

class AppWarmupService {
  AppWarmupService({
    AuthRequest? authRequest,
    BookingRequest? bookingRequest,
    StatusRequest? statusRequest,
    VehicleRequest? vehicleRequest,
    ClientMemberRequest? clientMemberRequest,
    SupportRequest? supportRequest,
  }) : _authRequest = authRequest ?? AuthRequest.instance,
       _bookingRequest = bookingRequest ?? BookingRequest.instance,
       _statusRequest = statusRequest ?? StatusRequest.instance,
       _vehicleRequest = vehicleRequest ?? VehicleRequest.instance,
       _clientMemberRequest =
           clientMemberRequest ?? ClientMemberRequest.instance,
       _supportRequest = supportRequest ?? SupportRequest.instance;

  static final AppWarmupService instance = AppWarmupService();

  final AuthRequest _authRequest;
  final BookingRequest _bookingRequest;
  final StatusRequest _statusRequest;
  final VehicleRequest _vehicleRequest;
  final ClientMemberRequest _clientMemberRequest;
  final SupportRequest _supportRequest;

  Future<void> warmUpGlobalData() async {
    await Future.wait([
      _runSafely(() => _vehicleRequest.getTypes()),
      _runSafely(() => _vehicleRequest.getSizes()),
      _runSafely(() => _vehicleRequest.getMakes()),
      _runSafely(() => _authRequest.getUsers()),
      _runSafely(() => _bookingRequest.getBookings()),
      _runSafely(() => _statusRequest.getStatuses()),
      _runSafely(() => _statusRequest.getAllFields()),
      _runSafely(() => _statusRequest.getStatusForms()),
    ]);
  }

  Future<void> warmUpForUser(UserModel? user) async {
    await warmUpGlobalData();
    if (user == null) {
      return;
    }

    final normalizedRole = normalizeRoleKey(user.role);
    final normalizedUserId = normalizeId(user.id);
    final normalizedClientId = isSubClientRole(user.role)
        ? normalizeId(user.parentClientId)
        : normalizedUserId;

    if (normalizedClientId != null &&
        (normalizedRole == 'client' || normalizedRole == 'sub-client')) {
      await _runSafely(
        () => _clientMemberRequest.getMembersForClient(normalizedClientId),
      );
    }

    final threads = await _prefetchSupportDataForUser(user);
    if (threads.isNotEmpty) {
      await _runSafely(
        () => _supportRequest.prefetchMessagesForThreads(threads),
      );
    }
  }

  Future<List<SupportThread>> _prefetchSupportDataForUser(
    UserModel user,
  ) async {
    if (isBackOfficeRole(user.role)) {
      return await _runSafelyList(() => _supportRequest.prefetchAllThreads());
    }
    final normalizedUserId = normalizeId(user.id);
    if (normalizedUserId == null) {
      return const <SupportThread>[];
    }
    return await _runSafelyList(
      () => _supportRequest.prefetchThreadsForUser(normalizedUserId),
    );
  }

  Future<void> _runSafely<T>(Future<T> Function() action) async {
    try {
      await action();
    } catch (_) {}
  }

  Future<List<T>> _runSafelyList<T>(Future<List<T>> Function() action) async {
    try {
      return await action();
    } catch (_) {
      return <T>[];
    }
  }
}
