import 'package:webapp/constants/puerto_princesa_barangays.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/models/status_form.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/requests/booking.request.dart';
import 'package:webapp/requests/status.request.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/repositories/interfaces/booking_repository.dart';
import 'package:webapp/repositories/interfaces/status_form_repository.dart';
import 'package:webapp/repositories/interfaces/vehicle_catalog_repository.dart';

class StatusFieldOptionResolver {
  StatusFieldOptionResolver({
    AuthRepository? authRepository,
    VehicleCatalogRepository? vehicleCatalogRepository,
    StatusFormRepository? statusFormRepository,
    BookingRepository? bookingRepository,
  }) : _authRepository = authRepository ?? AuthRequest.instance,
       _vehicleCatalogRepository =
           vehicleCatalogRepository ?? VehicleRequest.instance,
       _statusFormRepository =
           statusFormRepository ?? StatusRequest.instance,
       _bookingRepository = bookingRepository ?? BookingRequest.instance;

  final AuthRepository _authRepository;
  final VehicleCatalogRepository _vehicleCatalogRepository;
  final StatusFormRepository _statusFormRepository;
  final BookingRepository _bookingRepository;

  Future<List<StatusField>> hydrateFields(List<StatusField> fields) async {
    final results = await Future.wait([
      _authRepository.getUsers(),
      _vehicleCatalogRepository.getMakes(),
      _vehicleCatalogRepository.getTypes(),
      _vehicleCatalogRepository.getSizes(),
      _statusFormRepository.getStatuses(),
      _statusFormRepository.getStatusForms(),
      _statusFormRepository.getAllFields(),
      _bookingRepository.getBookings(),
    ]);
    final users = results[0] as List<dynamic>;
    final makes = results[1] as List<dynamic>;
    final types = results[2] as List<dynamic>;
    final sizes = results[3] as List<dynamic>;
    final statuses = results[4] as List<dynamic>;
    final forms = results[5] as List<StatusForm>;
    final fieldLibrary = results[6] as List<StatusField>;
    final bookings = results[7] as List<dynamic>;

    final userOptions = _uniqueSortedOptions(
      users
          .where((item) => item.isActive != false)
          .map(_userDisplay)
          .whereType<String>(),
    );
    final clientOptions = _uniqueSortedOptions(
      users
          .where((item) => item.role == 'client' && item.isActive != false)
          .map(_userDisplay)
          .whereType<String>(),
    );
    final adminOptions = _uniqueSortedOptions(
      users
          .where((item) => item.role == 'admin' && item.isActive != false)
          .map(_userDisplay)
          .whereType<String>(),
    );
    final driverOptions = users
        .where(
          (item) =>
              (item.role ?? '').trim().toLowerCase() == 'driver' &&
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
              (item.role ?? '').trim().toLowerCase() == 'helper' &&
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
    final statusOptions = _uniqueSortedOptions(
      statuses
          .where((item) => item.isActive != false)
          .map(
            (item) => _catalogItemDisplay(item.label, item.key, item.id),
          )
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
          .map(
            (item) => _catalogItemDisplay(item.title, item.key, item.id),
          )
          .whereType<String>(),
    );
    final bookingOptions = _uniqueSortedOptions(
      bookings.map((item) => _bookingDisplay(item.id)).whereType<String>(),
    );
    final puertoPrincesaBarangayOptionsResolved = _uniqueSortedOptions(
      puertoPrincesaBarangayOptions,
    );

    return fields.map((field) {
      final sourceKey = _resolvedOptionSourceKey(field);
      final resolvedOptions = switch (sourceKey) {
        statusFieldOptionSourceUsers => userOptions,
        statusFieldOptionSourceClients => clientOptions,
        statusFieldOptionSourceAdmins => adminOptions,
        statusFieldOptionSourceDrivers => driverOptions,
        statusFieldOptionSourceHelpers => helperOptions,
        statusFieldOptionSourceClientMembers => field.options,
        statusFieldOptionSourceVehicleMakes => makeOptions,
        statusFieldOptionSourceVehicleTypes => typeOptions,
        statusFieldOptionSourceVehicleSizes => sizeOptions,
        statusFieldOptionSourceStatuses => statusOptions,
        statusFieldOptionSourceForms => formOptions,
        statusFieldOptionSourceFields => fieldOptions,
        statusFieldOptionSourceBookings => bookingOptions,
        statusFieldOptionSourcePuertoPrincesaBarangays =>
          puertoPrincesaBarangayOptionsResolved,
        _ => field.options,
      };
      return field.copyWith(options: resolvedOptions);
    }).toList();
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
      'member_id' => statusFieldOptionSourceClientMembers,
      'truck_id' => statusFieldOptionSourceVehicleMakes,
      'vehicle_make_id' => statusFieldOptionSourceVehicleMakes,
      'vehicle_type_id' => statusFieldOptionSourceVehicleTypes,
      'van_size' => statusFieldOptionSourceVehicleSizes,
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
