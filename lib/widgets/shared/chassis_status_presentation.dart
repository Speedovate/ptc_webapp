import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/chassis.dart';

class ChassisStatusPalette {
  const ChassisStatusPalette({
    required this.backgroundColor,
    required this.borderColor,
    required this.textColor,
  });

  final Color backgroundColor;
  final Color borderColor;
  final Color textColor;
}

String chassisStatusLabel(String status) {
  final normalized = status.trim().toLowerCase();
  return switch (normalized) {
    Chassis.ready => 'Ready',
    Chassis.loaded => 'Loaded',
    Chassis.empty => 'Empty',
    Chassis.returning => 'Return',
    _ =>
      normalized.isEmpty
          ? '-'
          : '${normalized[0].toUpperCase()}${normalized.substring(1)}',
  };
}

ChassisStatusPalette chassisStatusPalette(String status) {
  return switch (status.trim().toLowerCase()) {
    Chassis.ready => const ChassisStatusPalette(
      backgroundColor: Color(0xFFE9F8EF),
      borderColor: Color(0xFFB9E7C8),
      textColor: Color(0xFF2EAD62),
    ),
    Chassis.loaded => const ChassisStatusPalette(
      backgroundColor: AppColors.primarySurface,
      borderColor: AppColors.primaryBorder,
      textColor: AppColors.primaryColor,
    ),
    Chassis.empty => const ChassisStatusPalette(
      backgroundColor: AppColors.dangerSurfaceAlt,
      borderColor: AppColors.dangerBorderAlt,
      textColor: AppColors.danger,
    ),
    Chassis.returning => const ChassisStatusPalette(
      backgroundColor: AppColors.primarySurface,
      borderColor: AppColors.primaryBorder,
      textColor: AppColors.primaryColor,
    ),
    _ => const ChassisStatusPalette(
      backgroundColor: AppColors.primarySurface,
      borderColor: AppColors.primaryBorder,
      textColor: AppColors.primaryColor,
    ),
  };
}

class ChassisStatusPill extends StatelessWidget {
  const ChassisStatusPill({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final palette = chassisStatusPalette(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: palette.backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.borderColor),
      ),
      child: Text(
        chassisStatusLabel(status),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: palette.textColor,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class ChassisStatusOptionLabel extends StatelessWidget {
  const ChassisStatusOptionLabel({
    super.key,
    required this.label,
    required this.status,
    this.showStatusSuffix = true,
  });

  final String label;
  final String status;
  final bool showStatusSuffix;

  @override
  Widget build(BuildContext context) {
    final palette = chassisStatusPalette(status);
    return Row(
      children: [
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: showStatusSuffix
                  ? AppColors.textPrimary
                  : palette.textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (showStatusSuffix) ...[
          const SizedBox(width: 8),
          Text(
            chassisStatusLabel(status),
            style: TextStyle(
              color: palette.textColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}
