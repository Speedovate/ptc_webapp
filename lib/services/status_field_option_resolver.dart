import 'client_route_suggestions.dart';
import 'package:webapp/constants/palawan_locations.dart';
import 'client_representative_suggestions.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/services/kpi/location_option_registry.dart';
import 'package:webapp/services/kpi/operations_catalog_store.dart';
import 'package:webapp/constants/puerto_princesa_barangays.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/models/status_form.dart';
import 'package:webapp/models/chassis.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/requests/booking.request.dart';
import 'package:webapp/requests/chassis.request.dart';
import 'package:webapp/requests/status.request.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/repositories/interfaces/booking_repository.dart';
import 'package:webapp/repositories/interfaces/status_form_repository.dart';
import 'package:webapp/repositories/interfaces/vehicle_catalog_repository.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:webapp/utils/functions.dart';

class StatusFieldOptionResolver {
  StatusFieldOptionResolver({
    AuthRepository? authRepository,
    VehicleCatalogRepository? vehicleCatalogRepository,
    StatusFormRepository? statusFormRepository,
    BookingRepository? bookingRepository,
  }) : _authRepository = authRepository ?? AuthRequest.instance,
       _vehicleCatalogRepository =
           vehicleCatalogRepository ?? VehicleRequest.instance,
       _statusFormRepository = statusFormRepository ?? StatusRequest.instance,
       _bookingRepository = bookingRepository ?? BookingRequest.instance;

  final AuthRepository _authRepository;
  final VehicleCatalogRepository _vehicleCatalogRepository;
  final StatusFormRepository _statusFormRepository;
  final BookingRepository _bookingRepository;
  List<Booking> _representativeBookings = const [];
  final Map<String, List<Map<String, String>>> _routesByRepresentative = {};
  final Map<String, List<String>> _representativesByClient = {};
  final Map<String, Map<String, String>> _representativePhonesByClient = {};

  /// Reuse one history snapshot across fields and keystrokes.
  void setBookingHistory(List<Booking> bookings) {
    _representativeBookings = List.of(bookings);
    _routesByRepresentative.clear();
    _representativesByClient.clear();
    _representativePhonesByClient.clear();
  }

  /// Update optional suggestions only after the booking write succeeds.
  void rememberSavedBooking(Booking booking) {
    _ensureRepresentativeSnapshot();
    _representativeBookings = [
      ..._representativeBookings.where(
        (existing) => booking.id == null || existing.id != booking.id,
      ),
      booking,
    ];
    _routesByRepresentative.clear();
    _representativesByClient.clear();
    _representativePhonesByClient.clear();
  }

  void _ensureRepresentativeSnapshot() {
    if (_representativeBookings.isEmpty &&
        BookingRequest.hydratedBookingCount > 0) {
      _representativeBookings = BookingRequest.hydratedBookingsSnapshot;
      _routesByRepresentative.clear();
      _representativesByClient.clear();
      _representativePhonesByClient.clear();
    }
  }

  String? representativePhone(String? clientId, String name) {
    _ensureRepresentativeSnapshot();
    final id = normalizeId(clientId);
    if (id == null) return null;
    final phones = _representativePhonesByClient.putIfAbsent(
      id,
      () => clientRepresentativePhones(_representativeBookings, id),
    );
    return phones[name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase()];
  }

  List<StatusField> withClientRepresentativeSuggestions(
    List<StatusField> fields, {
    required String? clientId,
    Map<String, dynamic> answers = const {},
  }) {
    if (!fields.any(
      (field) =>
          field.usesClientRepresentativeSuggestions ||
          isBookingRouteFieldKey(field.key),
    )) {
      return fields;
    }
    _ensureRepresentativeSnapshot();
    final id = normalizeId(clientId);
    // Resolve once per client per loaded snapshot, rather than scanning all
    // booking history on every text edit. Hydration invalidates this cache.
    final suggestions = id == null
        ? const <String>[]
        : _representativesByClient.putIfAbsent(
            id,
            () => clientRepresentativeSuggestions(_representativeBookings, id),
          );
    final name = answers['representative_name']
        ?.toString()
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
    // Partial/new names have no saved route association. Avoid rescanning the
    // full booking history and retaining an empty cache entry per keystroke.
    final hasSavedName =
        name != null && suggestions.any((value) => value.toLowerCase() == name);
    final routes = id == null || name == null || name.isEmpty || !hasSavedName
        ? const <Map<String, String>>[]
        : _routesByRepresentative.putIfAbsent(
            '$id::$name',
            () => clientRepresentativeRoutes(_representativeBookings, id, name),
          );
    return fields
        .map(
          (field) => field.usesClientRepresentativeSuggestions
              ? field.copyWith(options: suggestions)
              : isBookingRouteFieldKey(field.key)
              ? field.copyWith(
                  options: _uniqueOptions([
                    ...routeFieldSuggestions(routes, field.key!, answers),
                    ...(field.key!.endsWith('_barangay')
                        ? barangayOptionsFor(field.key!)
                        : locationOptionsFor(field.key!)),
                  ]),
                )
              : field,
        )
        .toList();
  }

  final RoleAccessService _roleAccessService = RoleAccessService.instance;

  List<StatusField> hydrateFieldsFromResolvedSnapshots(
    List<StatusField> fields,
  ) {
    return _hydrateFieldsWithResolvedSources(
      fields,
      users: AuthRequest.hasResolvedUsers
          ? AuthRequest.hydratedUsersSnapshot
          : const [],
      makes: VehicleRequest.hasResolvedMakes
          ? VehicleRequest.hydratedMakesSnapshot
          : const [],
      types: VehicleRequest.hasResolvedTypes
          ? VehicleRequest.hydratedTypesSnapshot
          : const [],
      sizes: VehicleRequest.hasResolvedSizes
          ? VehicleRequest.hydratedSizesSnapshot
          : const [],
      chassis: ChassisRequest.instance.hasResolvedChassis
          ? ChassisRequest.instance.hydratedChassisSnapshot
          : const [],
      statuses: StatusRequest.hasResolvedStatuses
          ? StatusRequest.hydratedStatusesSnapshot
          : const [],
      forms: StatusRequest.hasResolvedForms
          ? StatusRequest.hydratedFormsSnapshot
          : const [],
      fieldLibrary: StatusRequest.hasResolvedFields
          ? StatusRequest.hydratedFieldsSnapshot
          : const [],
      bookings: BookingRequest.hasResolvedBookings
          ? BookingRequest.hydratedBookingsSnapshot
          : const [],
    );
  }

  Future<List<StatusField>> hydrateFields(List<StatusField> fields) async {
    if (fields.any(
      (f) => LocationOptionRegistry.supports(f.key) || f.isChassisLocationInput,
    )) {
      try {
        await OperationsCatalogStore.instance.restore();
        OperationsCatalogStore.instance.load().catchError(
          (Object _) => OperationsCatalogStore.instance.current,
        );
      } catch (_) {
        /* Keep existing offline/default choices. */
      }
    }
    final sourceKeys = fields
        .map(_resolvedOptionSourceKey)
        .whereType<String>()
        .toSet();

    List<dynamic> users = const [];
    List<dynamic> makes = const [];
    List<dynamic> types = const [];
    List<dynamic> sizes = const [];
    List<Chassis> chassis = const [];
    List<dynamic> statuses = const [];
    List<StatusForm> forms = const [];
    List<StatusField> fieldLibrary = const [];
    List<dynamic> bookings = const [];

    final tasks = <Future<void>>[];
    if (_needsUsers(sourceKeys) && AuthRequest.hasResolvedUsers) {
      users = AuthRequest.hydratedUsersSnapshot;
    } else if (_needsUsers(sourceKeys)) {
      tasks.add(
        _authRepository.getUsers().then((value) {
          users = value;
        }),
      );
    }
    if (sourceKeys.contains(statusFieldOptionSourceVehicleMakes) &&
        VehicleRequest.hasResolvedMakes) {
      makes = VehicleRequest.hydratedMakesSnapshot;
    } else if (sourceKeys.contains(statusFieldOptionSourceVehicleMakes)) {
      tasks.add(
        _vehicleCatalogRepository.getMakes().then((value) {
          makes = value;
        }),
      );
    }
    if (sourceKeys.contains(statusFieldOptionSourceVehicleTypes) &&
        VehicleRequest.hasResolvedTypes) {
      types = VehicleRequest.hydratedTypesSnapshot;
    } else if (sourceKeys.contains(statusFieldOptionSourceVehicleTypes)) {
      tasks.add(
        _vehicleCatalogRepository.getTypes().then((value) {
          types = value;
        }),
      );
    }
    if (sourceKeys.contains(statusFieldOptionSourceVehicleSizes) &&
        VehicleRequest.hasResolvedSizes) {
      sizes = VehicleRequest.hydratedSizesSnapshot;
    } else if (sourceKeys.contains(statusFieldOptionSourceVehicleSizes)) {
      tasks.add(
        _vehicleCatalogRepository.getSizes().then((value) {
          sizes = value;
        }),
      );
    }
    if (sourceKeys.contains(statusFieldOptionSourceChassis) &&
        ChassisRequest.instance.hasResolvedChassis) {
      chassis = ChassisRequest.instance.hydratedChassisSnapshot;
    } else if (sourceKeys.contains(statusFieldOptionSourceChassis)) {
      tasks.add(
        ChassisRequest.instance.getChassis().then((value) {
          chassis = value;
        }),
      );
    }
    if (sourceKeys.contains(statusFieldOptionSourceStatuses) &&
        StatusRequest.hasResolvedStatuses) {
      statuses = StatusRequest.hydratedStatusesSnapshot;
    } else if (sourceKeys.contains(statusFieldOptionSourceStatuses)) {
      tasks.add(
        _statusFormRepository.getStatuses().then((value) {
          statuses = value;
        }),
      );
    }
    if (sourceKeys.contains(statusFieldOptionSourceForms) &&
        StatusRequest.hasResolvedForms) {
      forms = StatusRequest.hydratedFormsSnapshot;
    } else if (sourceKeys.contains(statusFieldOptionSourceForms)) {
      tasks.add(
        _statusFormRepository.getStatusForms().then((value) {
          forms = value;
        }),
      );
    }
    if (sourceKeys.contains(statusFieldOptionSourceFields) &&
        StatusRequest.hasResolvedFields) {
      fieldLibrary = StatusRequest.hydratedFieldsSnapshot;
    } else if (sourceKeys.contains(statusFieldOptionSourceFields)) {
      tasks.add(
        _statusFormRepository.getAllFields().then((value) {
          fieldLibrary = value;
        }),
      );
    }
    final needsRepresentativeHistory =
        sourceKeys.contains(statusFieldOptionSourceClientRepresentatives) ||
        fields.any((field) => isBookingRouteFieldKey(field.key));
    if ((sourceKeys.contains(statusFieldOptionSourceBookings) ||
            needsRepresentativeHistory) &&
        (BookingRequest.hasResolvedBookings ||
            BookingRequest.isAuthoritativeSyncInFlight)) {
      bookings = BookingRequest.hydratedBookingsSnapshot;
    } else if (sourceKeys.contains(statusFieldOptionSourceBookings)) {
      tasks.add(
        _bookingRepository.getBookings().then((value) {
          bookings = value;
        }),
      );
    } else if (needsRepresentativeHistory) {
      // Optional suggestions never prevent manual entry or block form loading.
      tasks.add(
        _bookingRepository
            .getBookings()
            .timeout(
              const Duration(seconds: 3),
              onTimeout: () => const <Booking>[],
            )
            .then<void>((value) {
              bookings = value;
            }, onError: (Object _) {}),
      );
    }
    if (tasks.isNotEmpty) {
      await Future.wait(tasks);
    }

    return _hydrateFieldsWithResolvedSources(
      fields,
      users: users,
      makes: makes,
      types: types,
      sizes: sizes,
      chassis: chassis,
      statuses: statuses,
      forms: forms,
      fieldLibrary: fieldLibrary,
      bookings: bookings,
    );
  }

  List<StatusField> _hydrateFieldsWithResolvedSources(
    List<StatusField> fields, {
    required List<dynamic> users,
    required List<dynamic> makes,
    required List<dynamic> types,
    required List<dynamic> sizes,
    required List<Chassis> chassis,
    required List<dynamic> statuses,
    required List<StatusForm> forms,
    required List<StatusField> fieldLibrary,
    required List<dynamic> bookings,
  }) {
    if (fields.any(
      (field) =>
          field.usesClientRepresentativeSuggestions ||
          isBookingRouteFieldKey(field.key),
    )) {
      _representativeBookings = bookings.whereType<Booking>().toList();
      _routesByRepresentative.clear();
      _representativesByClient.clear();
      _representativePhonesByClient.clear();
    }
    final userOptions = _uniqueSortedOptions(
      users
          .where((item) => item.isActive != false)
          .map(_userDisplay)
          .whereType<String>(),
    );
    final clientOptions = _uniqueSortedOptions(
      users
          .where(
            (item) => isPrimaryClientRole(item.role) && item.isActive != false,
          )
          .map(_userDisplay)
          .whereType<String>(),
    );
    final adminOptions = _uniqueSortedOptions(
      users
          .where(
            (item) =>
                _roleAccessService.usesAdminShell(role: item.role) &&
                item.isActive != false,
          )
          .map(_userDisplay)
          .whereType<String>(),
    );
    final driverOptions = users
        .where(
          (item) =>
              normalizeRoleKey(item.role) == 'driver' &&
              item.isActive != false &&
              item.isOnline == true,
        )
        .map(_userDisplay)
        .whereType<String>()
        .where((item) => item.isNotEmpty)
        .toList();
    final helperOptions = users
        .where(
          (item) =>
              normalizeRoleKey(item.role) == 'helper' &&
              item.isActive != false &&
              item.isOnline == true,
        )
        .map(_userDisplay)
        .whereType<String>()
        .where((item) => item.isNotEmpty)
        .toList();
    final makeOptions = _uniqueSortedOptions(
      makes
          .where((item) => item.isActive != false)
          .map(_vehicleMakeDisplay)
          .whereType<String>(),
    );
    final typeOptions = _uniqueSortedOptions(
      types
          .where((item) => item.isActive != false)
          .map((item) => _catalogItemDisplay(item.name, item.slug, item.id))
          .whereType<String>(),
    );
    final sizeOptions = _uniqueOptions(
      sizes
          .where((item) => item.isActive != false)
          .map((item) => item.id?.trim())
          .whereType<String>(),
    );
    final chassisOptions = _uniqueOptions(
      chassis.where((item) => item.isActive).map((item) => '${item.id}'),
    );
    final statusOptions = _uniqueSortedOptions(
      statuses
          .where((item) => item.isActive != false)
          .map((item) => _catalogItemDisplay(item.label, item.key, item.id))
          .whereType<String>(),
    );
    final formOptions = _uniqueSortedOptions(
      forms
          .where((item) => item.isActive != false)
          .map(_statusFormDisplay)
          .whereType<String>(),
    );
    final fieldOptions = _uniqueSortedOptions(
      fieldLibrary
          .where((item) => item.isActive != false)
          .map((item) => _catalogItemDisplay(item.title, item.key, item.id))
          .whereType<String>(),
    );
    final bookingOptions = _uniqueSortedOptions(
      bookings.map((item) => _bookingDisplay(item.id)).whereType<String>(),
    );
    final puertoPrincesaBarangayOptionsResolved = _uniqueSortedOptions(
      puertoPrincesaBarangayOptions,
    );

    final resolved = fields.map((field) {
      final sourceKey = _resolvedOptionSourceKey(field);
      final resolvedOptions = switch (sourceKey) {
        statusFieldOptionSourceClientRepresentatives => const <String>[],
        statusFieldOptionSourceUsers => userOptions,
        statusFieldOptionSourceClients => clientOptions,
        statusFieldOptionSourceAdmins => adminOptions,
        statusFieldOptionSourceDrivers => driverOptions,
        statusFieldOptionSourceHelpers => helperOptions,
        statusFieldOptionSourceClientMembers => clientOptions,
        statusFieldOptionSourceVehicleMakes => makeOptions,
        statusFieldOptionSourceVehicleTypes => typeOptions,
        statusFieldOptionSourceVehicleSizes => sizeOptions,
        statusFieldOptionSourceChassis => chassisOptions,
        statusFieldOptionSourceStatuses => statusOptions,
        statusFieldOptionSourceForms => formOptions,
        statusFieldOptionSourceFields => fieldOptions,
        statusFieldOptionSourceBookings => bookingOptions,
        statusFieldOptionSourcePuertoPrincesaBarangays =>
          puertoPrincesaBarangayOptionsResolved,
        _ => field.options,
      };
      if (LocationOptionRegistry.supports(field.key)) {
        return field.copyWith(
          // Historical values remain valid through Registry.accepts(), but
          // must never reappear as active choices in new booking fields.
          options: LocationOptionRegistry.options(field.key, resolvedOptions),
        );
      }
      return field.copyWith(options: resolvedOptions);
    }).toList();
    return resolved;
  }

  bool _needsUsers(Set<String> sourceKeys) {
    return sourceKeys.contains(statusFieldOptionSourceUsers) ||
        sourceKeys.contains(statusFieldOptionSourceClients) ||
        sourceKeys.contains(statusFieldOptionSourceAdmins) ||
        sourceKeys.contains(statusFieldOptionSourceDrivers) ||
        sourceKeys.contains(statusFieldOptionSourceHelpers);
  }

  static String? resolvedOptionSourceKey(StatusField field) {
    return _resolvedOptionSourceKey(field);
  }

  static String? _resolvedOptionSourceKey(StatusField field) {
    final explicit = field.optionSourceKey?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    final fieldKey = (field.key ?? '').trim().toLowerCase();
    return switch (fieldKey) {
      'user_id' => statusFieldOptionSourceUsers,
      'client_id' => statusFieldOptionSourceClients,
      'admin_id' => statusFieldOptionSourceAdmins,
      'driver_id' => statusFieldOptionSourceDrivers,
      'helper_id' => statusFieldOptionSourceHelpers,
      'vehicle_make_id' => statusFieldOptionSourceVehicleMakes,
      'vehicle_type_id' => statusFieldOptionSourceVehicleTypes,
      'van_size' => statusFieldOptionSourceVehicleSizes,
      'chassis_id' => statusFieldOptionSourceChassis,
      'status_id' => statusFieldOptionSourceStatuses,
      'form_id' => statusFieldOptionSourceForms,
      'field_id' => statusFieldOptionSourceFields,
      'booking_id' => statusFieldOptionSourceBookings,
      'origin_barangay' => statusFieldOptionSourcePuertoPrincesaBarangays,
      'destination_barangay' => statusFieldOptionSourcePuertoPrincesaBarangays,
      _ => null,
    };
  }

  static List<String> _uniqueSortedOptions(Iterable<String> values) {
    final unique = values
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
    unique.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return unique;
  }

  static List<String> _uniqueOptions(Iterable<String> values) {
    final unique = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final normalized = value.trim();
      if (normalized.isEmpty || !seen.add(normalized)) {
        continue;
      }
      unique.add(normalized);
    }
    return unique;
  }

  static String? _userDisplay(dynamic user) {
    final name = user.name?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    final email = user.email?.trim();
    if (email != null && email.isNotEmpty) {
      return email;
    }
    final id = user.id?.trim();
    if (id != null && id.isNotEmpty) {
      return 'User $id';
    }
    return null;
  }

  static String? _vehicleMakeDisplay(dynamic make) {
    final code = make.code?.trim();
    if (code != null && code.isNotEmpty) {
      return code;
    }
    final id = make.id?.trim();
    if (id != null && id.isNotEmpty) {
      return 'Vehicle Make $id';
    }
    return null;
  }

  static String? _catalogItemDisplay(
    String? primary,
    String? secondary,
    String? id,
  ) {
    final trimmedPrimary = primary?.trim();
    if (trimmedPrimary != null && trimmedPrimary.isNotEmpty) {
      return trimmedPrimary;
    }
    final trimmedSecondary = secondary?.trim();
    if (trimmedSecondary != null && trimmedSecondary.isNotEmpty) {
      return trimmedSecondary;
    }
    final trimmedId = id?.trim();
    if (trimmedId != null && trimmedId.isNotEmpty) {
      return trimmedId;
    }
    return null;
  }

  static String? _statusFormDisplay(StatusForm form) {
    final currentStatusKey = form.currentStatusKey?.trim();
    final nextStatusKey = form.nextStatusKey?.trim();
    if (currentStatusKey != null &&
        currentStatusKey.isNotEmpty &&
        nextStatusKey != null &&
        nextStatusKey.isNotEmpty) {
      return '${_humanizeKey(currentStatusKey)} -> ${_humanizeKey(nextStatusKey)}';
    }
    final buttonText = form.buttonText?.trim();
    if (buttonText != null && buttonText.isNotEmpty) {
      return buttonText;
    }
    final id = form.id?.trim();
    if (id != null && id.isNotEmpty) {
      return 'Form $id';
    }
    return null;
  }

  static String? _bookingDisplay(String? id) {
    final trimmedId = id?.trim();
    if (trimmedId == null || trimmedId.isEmpty) {
      return null;
    }
    return 'ID $trimmedId';
  }

  static String _humanizeKey(String value) {
    return value
        .split('_')
        .where((item) => item.trim().isNotEmpty)
        .map((item) {
          final trimmed = item.trim();
          return '${trimmed[0].toUpperCase()}${trimmed.substring(1)}';
        })
        .join(' ');
  }
}
