import 'package:flutter/material.dart';

// Non-web fallback; web uses the browser's native input[type=date].
class NativeDateInput extends StatelessWidget {
  const NativeDateInput({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  @override
  Widget build(BuildContext context) => TextFormField(
    initialValue: value?.toIso8601String().split('T').first,
    decoration: InputDecoration(labelText: label, hintText: 'YYYY-MM-DD'),
    onChanged: (value) => onChanged(DateTime.tryParse(value)),
  );
}
