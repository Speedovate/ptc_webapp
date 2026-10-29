import 'package:flutter/material.dart';
import 'package:webapp/services/booking_edit_fields.dart';
import 'package:webapp/widgets/status_form/status_form_runtime_fields.dart';

class BookingAdditionalFieldsEditor extends StatelessWidget {
  const BookingAdditionalFieldsEditor({
    super.key,
    required this.controller,
    required this.baseAnswers,
    required this.clientId,
  });
  final BookingEditFields controller;
  final Map<String, dynamic> baseAnswers;
  final String? clientId;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, child) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.isLoading)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (controller.loadError case final String error) ...[
          Text(error),
          TextButton(
            onPressed: () => controller.load(refresh: true),
            child: const Text('Retry'),
          ),
        ],
        for (final field in controller.visibleFields(baseAnswers, clientId))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: StatusFormRuntimeFieldCard(
              key: ValueKey(field.key),
              field: field,
              initialValue: controller.values[field.key],
              errorText: controller.errors[field.key],
              onChanged: (value) => controller.update(field.key!, value),
            ),
          ),
      ],
    ),
  );
}
