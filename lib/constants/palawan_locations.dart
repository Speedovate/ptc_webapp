import 'package:webapp/services/kpi/location_option_registry.dart';

const defaultPalawanLocationOptions = <String>[
  'Aborlan',
  'Agutaya',
  'Araceli',
  'Balabac',
  'Bataraza',
  "Brooke's Point",
  'Busuanga',
  'Cagayancillo',
  'Coron',
  'Cuyo',
  'Dumaran',
  'El Nido',
  'Kalayaan',
  'Linapacan',
  'Magsaysay',
  'Narra',
  'Puerto Princesa City',
  'Quezon',
  'Rizal',
  'Roxas',
  'San Vicente',
  'Sofronio Espanola',
  'Taytay',
];

bool isPalawanLocationFieldKey(String? key) {
  final normalized = key?.trim().toLowerCase();
  return normalized == 'origin' || normalized == 'destination';
}

bool isValidPalawanLocationOption(String? value, {String fieldKey = 'origin'}) {
  final normalized = value?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) {
    return false;
  }
  return LocationOptionRegistry.accepts(
    fieldKey,
    normalized,
    palawanLocationOptions,
  );
}

List<String> get palawanLocationOptions =>
    LocationOptionRegistry.options('cities', defaultPalawanLocationOptions);

List<String> locationOptionsFor(String key) =>
    LocationOptionRegistry.options(key, palawanLocationOptions);
