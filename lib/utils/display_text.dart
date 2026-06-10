String humanizeDropdownValue(String? value) {
  final normalized = value?.trim() ?? '';
  if (normalized.isEmpty) {
    return '';
  }

  return normalized
      .split(RegExp(r'[_\s]+'))
      .where((part) => part.isNotEmpty)
      .map(_titleCasePart)
      .join(' ');
}

String _titleCasePart(String part) {
  return part
      .split('-')
      .where((segment) => segment.isNotEmpty)
      .map((segment) {
        if (segment.length == 1) {
          return segment.toUpperCase();
        }
        return '${segment[0].toUpperCase()}${segment.substring(1).toLowerCase()}';
      })
      .join('-');
}
