/// Shortens a barangay/city display label without changing its stored value.
String locationDisplayLabel(String value) {
  final text = value.trim();
  if (RegExp(r'^https?://', caseSensitive: false).hasMatch(text)) {
    return text;
  }
  final shortened = text
      .replaceFirst(
        RegExp(r',\s*Puerto\s+Princesa(?:\s+City)?\s*$', caseSensitive: false),
        '',
      )
      .trim();
  return shortened.isEmpty ? text : shortened;
}
