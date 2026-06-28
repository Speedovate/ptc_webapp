const palawanLocationOptions = <String>[
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

bool isValidPalawanLocationOption(String? value) {
  final normalized = value?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) {
    return false;
  }
  return palawanLocationOptions.any(
    (option) => option.trim().toLowerCase() == normalized,
  );
}
