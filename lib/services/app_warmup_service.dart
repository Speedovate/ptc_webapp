import 'package:webapp/models/support_thread.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/dispatcher_access_config.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/requests/booking.request.dart';
import 'package:webapp/requests/chassis.request.dart';
import 'package:webapp/requests/status.request.dart';
import 'package:webapp/requests/support.request.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:webapp/utils/functions.dart';

class AppWarmupService {
  AppWarmupService({
    AuthRequest? authRequest,
    BookingRequest? bookingRequest,
    StatusRequest? statusRequest,
    VehicleRequest? vehicleRequest,
    ChassisRequest? chassisRequest,
    SupportRequest? supportRequest,
  }) : _providedAuthRequest = authRequest,
       _providedBookingRequest = bookingRequest,
       _providedStatusRequest = statusRequest,
       _providedVehicleRequest = vehicleRequest,
       _providedChassisRequest = chassisRequest,
       _providedSupportRequest = supportRequest;

  static final AppWarmupService instance = AppWarmupService();

  final AuthRequest? _providedAuthRequest;
  AuthRequest get _authRequest => _providedAuthRequest ?? AuthRequest.instance;
  final BookingRequest? _providedBookingRequest;
  BookingRequest get _bookingRequest =>
      _providedBookingRequest ?? BookingRequest.instance;
  final StatusRequest? _providedStatusRequest;
  StatusRequest get _statusRequest =>
      _providedStatusRequest ?? StatusRequest.instance;
  final VehicleRequest? _providedVehicleRequest;
  VehicleRequest get _vehicleRequest =>
      _providedVehicleRequest ?? VehicleRequest.instance;
  final ChassisRequest? _providedChassisRequest;
  ChassisRequest get _chassisRequest =>
      _providedChassisRequest ?? ChassisRequest.instance;
  final SupportRequest? _providedSupportRequest;
  SupportRequest get _supportRequest =>
      _providedSupportRequest ?? SupportRequest.instance;
  final RoleAccessService _roleAccessService = RoleAccessService.instance;
  final Map<String, Future<void>> _inFlightTasks = <String, Future<void>>{};
  final Set<String> _completedTasks = <String>{};

  static const String _taskBookings = 'bookings';
  static const String _taskUsers = 'users';
  static const String _taskVehicleMakes = 'vehicle_makes';
  static const String _taskVehicleTypes = 'vehicle_types';
  static const String _taskVehicleSizes = 'vehicle_sizes';
  static const String _taskChassis = 'chassis';
  static const String _taskStatuses = 'statuses';
  static const String _taskStatusFields = 'status_fields';
  static const String _taskStatusForms = 'status_forms';
  static const String _taskRoleAccess = 'role_access';

  Future<void> warmUpGlobalData() async {
    _log('warmUpGlobalData start');
    final bookingsWarmup = warmBookings();
    final flowWarmup = _warmFlowData();
    final vehicleWarmup = _warmVehicleCatalogData();
    final roleAccessWarmup = warmRoleAccess();
    final usersWarmup = warmUsers();
    await bookingsWarmup;
    await flowWarmup;
    await vehicleWarmup;
    await roleAccessWarmup;
    await usersWarmup;
    _log('warmUpGlobalData done');
  }

  Future<void> warmUpForUser(UserModel? user) async {
    _log(
      'warmUpForUser start user=${normalizeId(user?.id) ?? "-"} role=${user?.role ?? "-"}',
    );
    final flowWarmup = _warmFlowData();
    _log('warmUpForUser step=vehicles start');
    await _warmVehicleCatalogData();
    _log('warmUpForUser step=vehicles done');
    if (user == null) {
      _log('warmUpForUser step=role-access start');
      await warmRoleAccess();
      _log('warmUpForUser step=role-access done');
      _log('warmUpForUser step=flows start');
      await flowWarmup;
      _log('warmUpForUser step=flows done');
      _log('warmUpForUser step=users start');
      await warmUsers();
      _log('warmUpForUser step=users done');
      _log('warmUpForUser done no-user');
      return;
    }

    _log('warmUpForUser step=support start');
    final threads = await _prefetchSupportDataForUser(user);
    if (threads.isNotEmpty) {
      await _runSharedTask<void>(
        _supportMessagesTaskKey(threads),
        () => _runSafely(
          () => _supportRequest.prefetchMessagesForThreads(threads),
        ),
      );
    }
    _log('warmUpForUser step=support done threads=${threads.length}');
    _log('warmUpForUser step=role-access start');
    await warmRoleAccess();
    _log('warmUpForUser step=role-access done');
    _log('warmUpForUser step=flows start');
    await flowWarmup;
    _log('warmUpForUser step=flows done');
    _log('warmUpForUser step=users start');
    await warmUsers();
    _log('warmUpForUser step=users done');
    _log('warmUpForUser done threads=${threads.length}');
  }

  Future<void> warmBookings() {
    return _runSharedTask<void>(
      _taskBookings,
      () => _bookingRequest.getBookings(),
    );
  }

  Future<void> warmUsers() {
    return _runSharedTask<void>(_taskUsers, () => _authRequest.getUsers());
  }

  Future<void> warmVehicleMakes() {
    return _runSharedTask<void>(
      _taskVehicleMakes,
      () => _vehicleRequest.getMakes(),
    );
  }

  Future<void> warmVehicleTypes() {
    return _runSharedTask<void>(
      _taskVehicleTypes,
      () => _vehicleRequest.getTypes(),
    );
  }

  Future<void> warmVehicleSizes() {
    return _runSharedTask<void>(
      _taskVehicleSizes,
      () => _vehicleRequest.getSizes(),
    );
  }

  Future<void> warmChassis() {
    return _runSharedTask<void>(
      _taskChassis,
      () => _chassisRequest.getChassis(),
    );
  }

  Future<void> warmStatuses() {
    return _runSharedTask<void>(
      _taskStatuses,
      () => _statusRequest.getStatuses(),
    );
  }

  Future<void> warmStatusFields() {
    return _runSharedTask<void>(
      _taskStatusFields,
      () => _statusRequest.getAllFields(),
    );
  }

  Future<void> warmStatusForms() {
    return _runSharedTask<void>(
      _taskStatusForms,
      () => _statusRequest.getStatusForms(),
    );
  }

  Future<void> warmRoleAccess() {
    return _runSharedTask<void>(
      _taskRoleAccess,
      () => _roleAccessService.refresh(),
    );
  }

  Future<void> _warmVehicleCatalogData() async {
    await warmVehicleMakes();
    await warmVehicleTypes();
    await warmVehicleSizes();
    await warmChassis();
  }

  Future<void> _warmFlowData() async {
    await warmStatuses();
    await warmStatusForms();
    await warmStatusFields();
  }

  Future<List<SupportThread>> _prefetchSupportDataForUser(
    UserModel user,
  ) async {
    final canViewInbox =
        _roleAccessService.canAccess(
          DispatcherAccessCapability.supportRead,
          role: user.role,
        ) &&
        _roleAccessService.canAccess(
          DispatcherAccessCapability.usersRead,
          role: user.role,
        );
    if (canViewInbox) {
      return await _runSharedListTask<SupportThread>(
        'support_threads:all',
        () => _runSafelyList(() => _supportRequest.prefetchAllThreads()),
      );
    }
    final normalizedUserId = normalizeId(user.id);
    if (normalizedUserId == null) {
      return const <SupportThread>[];
    }
    return await _runSharedListTask<SupportThread>(
      'support_threads:user:$normalizedUserId',
      () => _runSafelyList(
        () => _supportRequest.prefetchThreadsForUser(normalizedUserId),
      ),
    );
  }

  String _supportMessagesTaskKey(List<SupportThread> threads) {
    final normalizedIds =
        threads
            .map((thread) => normalizeId(thread.id))
            .whereType<String>()
            .where((id) => id.isNotEmpty)
            .toList(growable: false)
          ..sort();
    if (normalizedIds.isEmpty) {
      return 'support_messages:none';
    }
    return 'support_messages:${normalizedIds.join(",")}';
  }

  Future<void> _runSharedTask<T>(
    String key,
    Future<T> Function() action,
  ) async {
    if (_completedTasks.contains(key)) {
      _log('task skip-completed key=$key');
      return;
    }
    final existing = _inFlightTasks[key];
    if (existing != null) {
      _log('task join-inflight key=$key');
      await existing;
      return;
    }
    _log('task start key=$key');
    final future = () async {
      var succeeded = false;
      try {
        await action();
        succeeded = true;
      } catch (_) {
        _log('task error key=$key');
      } finally {
        if (succeeded) {
          _completedTasks.add(key);
        }
        _inFlightTasks.remove(key);
        _log(succeeded ? 'task done key=$key' : 'task incomplete key=$key');
      }
    }();
    _inFlightTasks[key] = future;
    await future;
  }

  Future<List<T>> _runSharedListTask<T>(
    String key,
    Future<List<T>> Function() action,
  ) async {
    List<T> result = <T>[];
    await _runSharedTask<List<T>>(key, () async {
      result = await action();
      return result;
    });
    return result;
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

  void _log(String message) {
    // Temporary debug logging removed.
  }
}
