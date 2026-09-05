import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/utils/functions.dart';
import 'package:webapp/widgets/shared/app_image_viewer.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/app_mouse_pressable.dart';

class BookingRecordCard extends StatelessWidget {
  const BookingRecordCard({
    super.key,
    required this.booking,
    required this.headlineStatusLabel,
    required this.statusLabelForKey,
    this.onTap,
    this.showStatusSubmissions = true,
    this.showAllDetails = false,
    this.showScheduleDetails = false,
    this.originValue = '-',
    this.destinationValue = '-',
    this.clientName = '-',
    this.clientPhone = '-',
    this.driverName = '-',
    this.driverPhone = '-',
    this.helperName = '-',
    this.helperPhone = '-',
    this.clientId,
    this.driverId,
    this.helperId,
    this.onLinkedUserTap,
    this.linkedUserDisplayForField,
    this.onLinkedUserTapForField,
    this.trailingActions,
  });

  final Booking booking;
  final String headlineStatusLabel;
  final String Function(String? statusKey) statusLabelForKey;
  final VoidCallback? onTap;
  final bool showStatusSubmissions;
  final bool showAllDetails;
  final bool showScheduleDetails;
  final String originValue;
  final String destinationValue;
  final String clientName;
  final String clientPhone;
  final String driverName;
  final String driverPhone;
  final String helperName;
  final String helperPhone;
  final String? clientId;
  final String? driverId;
  final String? helperId;
  final ValueChanged<String>? onLinkedUserTap;
  final String? Function(String fieldKey, String rawValue)?
  linkedUserDisplayForField;
  final VoidCallback? Function(String fieldKey, String rawValue)?
  onLinkedUserTapForField;
  final Widget? trailingActions;

  @override
  Widget build(BuildContext context) {
    final waybillNumber = outputFieldDisplayValue(
      booking.statusOutputs,
      'waybill_number',
    );
    final vanNumber = outputFieldDisplayValue(
      booking.statusOutputs,
      'van_number',
    );
    final vanSize = outputFieldDisplayValue(booking.statusOutputs, 'van_size');
    final amount = outputFieldDisplayValue(booking.statusOutputs, 'amount');
    final compactItems = [
      _BookingMetaData(label: 'Waybill Number', value: waybillNumber),
      _BookingMetaData(label: 'Van Number', value: vanNumber),
      _BookingMetaData(label: 'Van Size', value: vanSize),
      _BookingMetaData(label: 'Amount', value: amount),
      if (showScheduleDetails) ...[
        _BookingMetaData(
          label: 'Pickup',
          value: _scheduleDateTimeDisplay(
            booking.statusOutputs,
            dateFieldKey: 'pick_up_date',
            timeFieldKey: 'pick_up_time',
          ),
        ),
        _BookingMetaData(
          label: 'Dropoff',
          value: _scheduleDateTimeDisplay(
            booking.statusOutputs,
            dateFieldKey: 'drop_off_date',
            timeFieldKey: 'drop_off_time',
          ),
        ),
      ],
    ];

    return AppMousePressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Builder(
        builder: (context) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: appPressableActive(context)
                ? AppColors.primarySurfaceAlt.withValues(alpha: 0.28)
                : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.primaryBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final useSingleRowCompactLayout =
                      !showAllDetails &&
                      _compactRowContentWidth(
                            context,
                            bookingIdLabel: 'Booking ${booking.id ?? '-'}',
                            createdAtLabel: _formatDateTime(booking.createdAt),
                            headlineStatusLabel: headlineStatusLabel,
                            items: compactItems,
                          ) <=
                          constraints.maxWidth;
                  if (useSingleRowCompactLayout) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _BookingHeaderColumn(
                          title: 'Booking ${booking.id ?? '-'}',
                          subtitle: _formatDateTime(booking.createdAt),
                        ),
                        const Spacer(),
                        ...compactItems.asMap().entries.expand((entry) {
                          final index = entry.key;
                          final item = entry.value;
                          return [
                            _BookingMetaItem(item: item),
                            if (index != compactItems.length - 1)
                              const Spacer(),
                          ];
                        }),
                        if (headlineStatusLabel.trim().isNotEmpty) ...[
                          const Spacer(),
                          _BookingStatusPill(label: headlineStatusLabel),
                        ],
                        if (trailingActions != null) ...[
                          const SizedBox(width: 12),
                          trailingActions!,
                        ],
                      ],
                    );
                  }

                  final columns = constraints.maxWidth >= 860
                      ? 3
                      : constraints.maxWidth >= 560
                      ? 2
                      : 1;
                  final spacing = 12.0;
                  final itemWidth =
                      (constraints.maxWidth - (spacing * (columns - 1))) /
                      columns;

                  final items = [
                    ...compactItems,
                    if (showAllDetails) ...[
                      _BookingMetaData(label: 'Origin', value: originValue),
                      _BookingMetaData(
                        label: 'Destination',
                        value: destinationValue,
                      ),
                      _BookingMetaData(
                        label: 'Client',
                        value: clientName,
                        linkedUserId: clientId,
                        linkedUserDisplay: _linkedUserDisplay(
                          clientId,
                          clientName,
                        ),
                        onLinkedUserTap: _linkedUserTap(clientId),
                      ),
                      _BookingMetaData(
                        label: 'Driver',
                        value: driverName,
                        linkedUserId: driverId,
                        linkedUserDisplay: _linkedUserDisplay(
                          driverId,
                          driverName,
                        ),
                        onLinkedUserTap: _linkedUserTap(driverId),
                      ),
                      _BookingMetaData(
                        label: 'Helper',
                        value: helperName,
                        linkedUserId: helperId,
                        linkedUserDisplay: _linkedUserDisplay(
                          helperId,
                          helperName,
                        ),
                        onLinkedUserTap: _linkedUserTap(helperId),
                      ),
                      _BookingMetaData(label: 'Client No.', value: clientPhone),
                      _BookingMetaData(label: 'Driver No.', value: driverPhone),
                      _BookingMetaData(label: 'Helper No.', value: helperPhone),
                    ],
                  ];

                  if (!showAllDetails) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _BookingHeaderColumn(
                                title: 'Booking ${booking.id ?? '-'}',
                                subtitle: _formatDateTime(booking.createdAt),
                              ),
                            ),
                            if (headlineStatusLabel.trim().isNotEmpty ||
                                trailingActions != null)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (headlineStatusLabel.trim().isNotEmpty)
                                    _BookingStatusPill(
                                      label: headlineStatusLabel,
                                    ),
                                  if (trailingActions != null) ...[
                                    if (headlineStatusLabel.trim().isNotEmpty)
                                      const SizedBox(width: 12),
                                    trailingActions!,
                                  ],
                                ],
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 24,
                          runSpacing: 10,
                          children: compactItems
                              .map((item) => _BookingMetaItem(item: item))
                              .toList(),
                        ),
                      ],
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _BookingHeaderColumn(
                              title: 'Booking ${booking.id ?? '-'}',
                              subtitle: _formatDateTime(booking.createdAt),
                            ),
                          ),
                          if (headlineStatusLabel.trim().isNotEmpty ||
                              trailingActions != null)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (headlineStatusLabel.trim().isNotEmpty)
                                  _BookingStatusPill(
                                    label: headlineStatusLabel,
                                  ),
                                if (trailingActions != null) ...[
                                  if (headlineStatusLabel.trim().isNotEmpty)
                                    const SizedBox(width: 12),
                                  trailingActions!,
                                ],
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: spacing,
                        runSpacing: 10,
                        children: items
                            .map(
                              (item) => SizedBox(
                                width: itemWidth,
                                child: _BookingMetaItem(item: item),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _linkedUserDisplay(String? userId, String name) {
    final normalizedId = normalizeId(userId);
    final trimmedName = name.trim();
    if (normalizedId == null || trimmedName.isEmpty || trimmedName == '-') {
      return null;
    }
    return '$normalizedId | $trimmedName';
  }

  VoidCallback? _linkedUserTap(String? userId) {
    final normalizedId = normalizeId(userId);
    if (normalizedId == null || onLinkedUserTap == null) {
      return null;
    }
    return () => onLinkedUserTap!(normalizedId);
  }

  static List<_BookingOutputSection> _extractOutputSections(
    Map<String, dynamic>? outputs,
  ) {
    if (outputs == null || outputs.isEmpty) {
      return const [];
    }

    final sections = outputs.entries
        .toList()
        .asMap()
        .entries
        .where((entry) => entry.value.value is Map)
        .map((entry) {
          final mapEntry = entry.value;
          final raw = Map<String, dynamic>.from(mapEntry.value as Map);
          final fields = raw['fields'] is Map
              ? Map<String, dynamic>.from(raw['fields'] as Map)
              : const <String, dynamic>{};
          return _BookingOutputSection(
            sourceIndex: entry.key,
            statusKey: _displayStatusKeyForEntry(mapEntry.key, raw),
            fields: fields,
            submittedAt: _toDateTime(raw['submitted_at']),
            submittedRole: raw['submitted_role']?.toString(),
            submittedBy: raw['submitted_by']?.toString(),
          );
        })
        .toList();

    sections.sort((a, b) {
      final aSubmittedAt = a.submittedAt;
      final bSubmittedAt = b.submittedAt;
      if (aSubmittedAt != null && bSubmittedAt != null) {
        return bSubmittedAt.compareTo(aSubmittedAt);
      }
      if (aSubmittedAt != null) {
        return -1;
      }
      if (bSubmittedAt != null) {
        return 1;
      }
      return a.sourceIndex.compareTo(b.sourceIndex);
    });

    return sections;
  }

  static String outputFieldDisplayValue(
    Map<String, dynamic>? outputs,
    String fieldKey,
  ) {
    final rawValue = outputFieldValue(outputs, fieldKey);
    return _displayValueForField(fieldKey, rawValue);
  }

  static dynamic outputFieldValue(
    Map<String, dynamic>? outputs,
    String fieldKey,
  ) {
    if (outputs == null || outputs.isEmpty) {
      return null;
    }

    final orderedSections = _extractOutputSections(outputs);

    for (final candidateKey in _candidateFieldKeys(fieldKey)) {
      for (final section in orderedSections) {
        if (section.displayStatusKey != 'pending') {
          continue;
        }
        final value = section.fields[candidateKey];
        final normalized = _simpleDisplayValue(value);
        if (normalized != '-') {
          return value;
        }
      }
    }

    for (final section in orderedSections) {
      final fields = section.fields;
      for (final candidateKey in _candidateFieldKeys(fieldKey)) {
        final value = fields[candidateKey];
        final normalized = _simpleDisplayValue(value);
        if (normalized != '-') {
          return value;
        }
      }
    }
    return null;
  }

  static String _displayStatusKeyForEntry(
    String entryKey,
    Map<String, dynamic> raw,
  ) {
    final explicitStatusKey = raw['status_key']?.toString().trim();
    if (explicitStatusKey != null && explicitStatusKey.isNotEmpty) {
      return explicitStatusKey;
    }
    final separatorIndex = entryKey.indexOf('__');
    if (separatorIndex > 0) {
      return entryKey.substring(0, separatorIndex);
    }
    return entryKey;
  }
}

List<String> _candidateFieldKeys(String fieldKey) {
  return [fieldKey];
}

class BookingRecordCardActions extends StatelessWidget {
  const BookingRecordCardActions({super.key, this.onViewTap, this.onEditTap});

  final VoidCallback? onViewTap;
  final VoidCallback? onEditTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AdminListActionButton(
          icon: Icons.visibility_rounded,
          backgroundColor: Colors.yellow.shade900,
          onTap: onViewTap,
        ),
        const SizedBox(width: 10),
        AdminListActionButton(icon: Icons.edit_outlined, onTap: onEditTap),
      ],
    );
  }
}

String _displayValueForField(String fieldKey, dynamic value) {
  if (fieldKey == 'van_size') {
    return VehicleRequest.instance.displayVehicleSizeLabel(value?.toString());
  }
  if (fieldKey == 'amount') {
    return _currencyDisplayValue(value);
  }
  return _simpleDisplayValue(value);
}

String _currencyDisplayValue(dynamic value) {
  final raw = _simpleDisplayValue(value);
  if (raw == '-') {
    return raw;
  }

  final normalized = raw.replaceAll('₱', '').replaceAll(',', '').trim();
  final parsed = num.tryParse(normalized);
  if (parsed == null) {
    return '₱$raw';
  }

  final isWhole = parsed == parsed.roundToDouble();
  final digits = isWhole
      ? parsed.toInt().toString()
      : parsed.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  return '₱${_addThousandsSeparators(digits)}';
}

String _addThousandsSeparators(String value) {
  final negative = value.startsWith('-');
  final trimmed = negative ? value.substring(1) : value;
  final parts = trimmed.split('.');
  final whole = parts.first;
  final decimal = parts.length > 1 ? '.${parts.sublist(1).join('.')}' : '';
  final buffer = StringBuffer();

  for (var i = 0; i < whole.length; i++) {
    final reverseIndex = whole.length - i;
    buffer.write(whole[i]);
    if (reverseIndex > 1 && reverseIndex % 3 == 1) {
      buffer.write(',');
    }
  }

  return '${negative ? '-' : ''}${buffer.toString()}$decimal';
}

String _simpleDisplayValue(dynamic value) {
  if (value == null) {
    return '-';
  }
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? '-' : trimmed;
  }
  return '$value';
}

const TextStyle _bookingHeaderTitleTextStyle = TextStyle(
  color: AppColors.textPrimary,
  fontSize: 15,
  fontWeight: FontWeight.w800,
  height: 1.2,
);

const TextStyle _bookingHeaderSubtitleTextStyle = TextStyle(
  color: AppColors.textSecondary,
  fontSize: 12,
  fontWeight: FontWeight.w500,
  height: 1.2,
);

const TextStyle _bookingItemLabelTextStyle = TextStyle(
  color: AppColors.primaryColor,
  fontWeight: FontWeight.w700,
  fontSize: 10,
  height: 1.15,
);

const TextStyle _bookingItemValueTextStyle = TextStyle(
  color: AppColors.textPrimary,
  fontWeight: FontWeight.w700,
  fontSize: 12,
  height: 1.2,
);

double _compactRowContentWidth(
  BuildContext context, {
  required String bookingIdLabel,
  required String createdAtLabel,
  required String headlineStatusLabel,
  required List<_BookingMetaData> items,
}) {
  final textScaler = MediaQuery.textScalerOf(context);

  final headerWidth = _maxMeasuredWidth([
    _measureTextWidth(bookingIdLabel, _bookingHeaderTitleTextStyle, textScaler),
    _measureTextWidth(
      createdAtLabel,
      _bookingHeaderSubtitleTextStyle,
      textScaler,
    ),
  ]);

  final itemWidths = items
      .map((item) => _bookingMetaItemWidth(context, item))
      .toList();
  final detailsWidth = itemWidths.fold<double>(0, (sum, width) => sum + width);
  final detailsGapWidth = itemWidths.length > 1
      ? (itemWidths.length - 1) * 24
      : 0;
  final statusPillWidth = headlineStatusLabel.trim().isNotEmpty
      ? _bookingStatusPillWidth(context, headlineStatusLabel)
      : 0;
  final majorGapCount = headlineStatusLabel.trim().isNotEmpty ? 2 : 1;
  final majorGapWidth = majorGapCount * 24;

  return headerWidth +
      detailsWidth +
      detailsGapWidth +
      statusPillWidth +
      majorGapWidth;
}

double _bookingMetaItemWidth(BuildContext context, _BookingMetaData item) {
  final textScaler = MediaQuery.textScalerOf(context);
  return _maxMeasuredWidth([
    _measureTextWidth(
      item.label,
      _bookingItemLabelTextStyle.copyWith(
        color: AppColors.primaryColor.withValues(alpha: 0.72),
      ),
      textScaler,
    ),
    _measureTextWidth(item.value, _bookingItemValueTextStyle, textScaler),
  ]);
}

double _bookingStatusPillWidth(BuildContext context, String label) {
  final textScaler = MediaQuery.textScalerOf(context);
  return _measureTextWidth(
        label,
        TextStyle(
          color: AppColors.primaryColor.withValues(alpha: 0.72),
          fontWeight: FontWeight.w700,
          fontSize: 14,
          height: 1,
        ),
        textScaler,
      ) +
      20;
}

double _measureTextWidth(String text, TextStyle style, TextScaler textScaler) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
    maxLines: 1,
  )..layout();
  return painter.width;
}

double _maxMeasuredWidth(List<double> values) {
  if (values.isEmpty) {
    return 0;
  }
  return values.reduce((current, next) => current > next ? current : next);
}

class BookingStatusSubmissionsSection extends StatelessWidget {
  const BookingStatusSubmissionsSection({
    super.key,
    required this.booking,
    required this.statusLabelForKey,
    required this.userNameForId,
    required this.userRoleForId,
    this.linkedUserDisplayForField,
    this.onLinkedUserTapForField,
  });

  final Booking booking;
  final String Function(String? statusKey) statusLabelForKey;
  final String Function(String? userId) userNameForId;
  final String Function(String? userId, String fallbackRole) userRoleForId;
  final String? Function(String fieldKey, String rawValue)?
  linkedUserDisplayForField;
  final VoidCallback? Function(String fieldKey, String rawValue)?
  onLinkedUserTapForField;

  @override
  Widget build(BuildContext context) {
    final outputSections = BookingRecordCard._extractOutputSections(
      booking.statusOutputs,
    );
    if (outputSections.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: outputSections.asMap().entries.map((sectionEntry) {
        final sectionIndex = sectionEntry.key;
        final section = sectionEntry.value;
        return Padding(
          padding: EdgeInsets.only(
            bottom: sectionIndex == outputSections.length - 1 ? 0 : 12,
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.primaryBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            section.headerLabel(userNameForId, userRoleForId),
                            style: _bookingHeaderTitleTextStyle,
                          ),
                          if (section.submittedAt != null) ...[
                            Text(
                              _formatDateTime(section.submittedAt),
                              style: _bookingHeaderSubtitleTextStyle,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _BookingStatusPill(
                      label: statusLabelForKey(section.displayStatusKey),
                    ),
                  ],
                ),
                if (section.fields.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 860
                          ? 3
                          : constraints.maxWidth >= 560
                          ? 2
                          : 1;
                      final spacing = 12.0;
                      final itemWidth =
                          (constraints.maxWidth - (spacing * (columns - 1))) /
                          columns;
                      final items = [
                        ...section.fields.entries.map(
                          (field) => _BookingFieldData(
                            fieldKey: field.key,
                            label: _titleCase(field.key.replaceAll('_', ' ')),
                            value: field.value,
                            linkedUserDisplay: _resolvedLinkedUserDisplay(
                              field.key,
                              field.value,
                            ),
                            onLinkedUserTap: _resolvedLinkedUserTap(
                              field.key,
                              field.value,
                            ),
                          ),
                        ),
                      ];

                      return Wrap(
                        spacing: spacing,
                        runSpacing: 10,
                        children: items
                            .map(
                              (item) => SizedBox(
                                width: itemWidth,
                                child: _BookingFieldItem(item: item),
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  String? _resolvedLinkedUserDisplay(String fieldKey, dynamic value) {
    final rawValue = value?.toString().trim();
    if (rawValue == null || rawValue.isEmpty) {
      return null;
    }
    return linkedUserDisplayForField?.call(fieldKey, rawValue);
  }

  VoidCallback? _resolvedLinkedUserTap(String fieldKey, dynamic value) {
    final rawValue = value?.toString().trim();
    if (rawValue == null || rawValue.isEmpty) {
      return null;
    }
    return onLinkedUserTapForField?.call(fieldKey, rawValue);
  }
}

class _BookingMetaData {
  const _BookingMetaData({
    required this.label,
    required this.value,
    this.linkedUserId,
    this.linkedUserDisplay,
    this.onLinkedUserTap,
  });

  final String label;
  final String value;
  final String? linkedUserId;
  final String? linkedUserDisplay;
  final VoidCallback? onLinkedUserTap;
}

class _BookingHeaderColumn extends StatelessWidget {
  const _BookingHeaderColumn({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: _bookingHeaderTitleTextStyle),
        Text(subtitle, style: _bookingHeaderSubtitleTextStyle),
      ],
    );
  }
}

class _BookingStatusPill extends StatelessWidget {
  const _BookingStatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = adminMetaPillPalette(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      constraints: const BoxConstraints(minHeight: 32),
      decoration: BoxDecoration(
        color: palette.backgroundColor,
        borderRadius: BorderRadius.circular(1000),
        border: Border.all(color: palette.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            textHeightBehavior: const TextHeightBehavior(
              applyHeightToFirstAscent: false,
              applyHeightToLastDescent: false,
            ),
            style: TextStyle(
              color: palette.textColor,
              fontWeight: FontWeight.w700,
              fontSize: 14,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _BookingFieldData {
  const _BookingFieldData({
    required this.fieldKey,
    required this.label,
    required this.value,
    this.linkedUserDisplay,
    this.onLinkedUserTap,
  });

  final String fieldKey;
  final String label;
  final dynamic value;
  final String? linkedUserDisplay;
  final VoidCallback? onLinkedUserTap;
}

class _BookingMetaItem extends StatelessWidget {
  const _BookingMetaItem({required this.item});

  final _BookingMetaData item;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.label,
          style: _bookingItemLabelTextStyle.copyWith(
            color: AppColors.primaryColor.withValues(alpha: 0.72),
          ),
        ),
        _BookingValueContent(
          value: item.value,
          linkedUserDisplay: item.linkedUserDisplay,
          onLinkedUserTap: item.onLinkedUserTap,
        ),
      ],
    );
  }
}

class _BookingFieldItem extends StatelessWidget {
  const _BookingFieldItem({required this.item});

  final _BookingFieldData item;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.label,
          style: _bookingItemLabelTextStyle.copyWith(
            color: AppColors.primaryColor.withValues(alpha: 0.72),
          ),
        ),
        _BookingValueContent(
          value: item.value,
          linkedUserDisplay: item.linkedUserDisplay,
          onLinkedUserTap: item.onLinkedUserTap,
        ),
      ],
    );
  }
}

class _BookingValueContent extends StatelessWidget {
  const _BookingValueContent({
    required this.value,
    this.linkedUserDisplay,
    this.onLinkedUserTap,
  });

  final dynamic value;
  final String? linkedUserDisplay;
  final VoidCallback? onLinkedUserTap;

  @override
  Widget build(BuildContext context) {
    if (linkedUserDisplay?.trim().isNotEmpty == true) {
      return _BookingLinkedUserValue(
        label: linkedUserDisplay!,
        onTap: onLinkedUserTap,
      );
    }
    if (value == null) {
      return const Text('-', style: _bookingItemValueTextStyle);
    }

    if (value is Map) {
      final mapValue = Map<String, dynamic>.from(value as Map);
      final bytes = decodePhotoBytes(mapValue);
      final downloadUrl = photoDownloadUrl(mapValue);
      final name = mapValue['name']?.toString().trim();

      if (name?.isNotEmpty == true || bytes != null || downloadUrl != null) {
        return _BookingPhotoValue(
          fileName: name?.isNotEmpty == true ? name! : 'Attached image',
          previewBytes: bytes,
          previewUrl: downloadUrl,
        );
      }

      final visibleEntries = mapValue.entries
          .where(
            (entry) =>
                entry.key != 'bytes' &&
                entry.key != 'download_url' &&
                entry.key != 'storage_path',
          )
          .map((entry) => '${_titleCase(entry.key)}: ${entry.value}')
          .join(' | ');

      return Text(
        visibleEntries.isEmpty ? '-' : visibleEntries,
        style: _bookingItemValueTextStyle,
      );
    }

    if (value is List) {
      final items = value
          .where((item) => item != null)
          .map((item) => '$item')
          .toList();
      return Text(
        items.isEmpty ? '-' : items.join(', '),
        style: _bookingItemValueTextStyle,
      );
    }

    return Text('$value', style: _bookingItemValueTextStyle);
  }
}

class _BookingLinkedUserValue extends StatelessWidget {
  const _BookingLinkedUserValue({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(child: Text(label, style: _bookingItemValueTextStyle)),
        if (onTap != null) ...[
          const SizedBox(width: 4),
          AppMousePressable(
            borderRadius: BorderRadius.circular(999),
            onTap: onTap,
            child: Builder(
              builder: (context) => Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: appPressableActive(context)
                      ? AppColors.primarySurfaceAlt.withValues(alpha: 0.34)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Icon(
                  Icons.visibility_outlined,
                  size: 18,
                  color: AppColors.primaryColor,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _BookingPhotoValue extends StatelessWidget {
  const _BookingPhotoValue({
    required this.fileName,
    required this.previewBytes,
    required this.previewUrl,
  });

  final String fileName;
  final Uint8List? previewBytes;
  final String? previewUrl;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(child: Text(fileName, style: _bookingItemValueTextStyle)),
        if (previewBytes != null || previewUrl?.trim().isNotEmpty == true) ...[
          const SizedBox(width: 4),
          AppMousePressable(
            borderRadius: BorderRadius.circular(999),
            onTap: () {
              showAppImageViewer(
                context,
                title: fileName,
                memoryBytes: previewBytes,
                imageUrl: previewUrl,
              );
            },
            child: Builder(
              builder: (context) => Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: appPressableActive(context)
                      ? AppColors.primarySurfaceAlt.withValues(alpha: 0.34)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Icon(
                  Icons.visibility_outlined,
                  size: 18,
                  color: AppColors.primaryColor,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _BookingOutputSection {
  const _BookingOutputSection({
    required this.sourceIndex,
    required this.statusKey,
    required this.fields,
    required this.submittedAt,
    required this.submittedRole,
    required this.submittedBy,
  });

  final int sourceIndex;
  final String statusKey;
  final Map<String, dynamic> fields;
  final DateTime? submittedAt;
  final String? submittedRole;
  final String? submittedBy;

  String headerLabel(
    String Function(String? userId) userNameForId,
    String Function(String? userId, String fallbackRole) userRoleForId,
  ) {
    final normalizedRole = submittedRole?.trim();
    final userId = submittedBy?.trim();
    final fallbackRole = normalizedRole != null && normalizedRole.isNotEmpty
        ? normalizedRole
        : 'client';
    final roleLabel = _titleCase(
      userId == null || userId.isEmpty
          ? fallbackRole
          : userRoleForId(userId, fallbackRole),
    );
    if (userId == null || userId.isEmpty) {
      return roleLabel;
    }
    return '$roleLabel $userId | ${userNameForId(userId)}';
  }

  String get displayStatusKey => statusKey;
}

String _titleCase(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) {
    return '-';
  }

  return normalized
      .split('_')
      .expand((segment) => segment.split(' '))
      .where((segment) => segment.isNotEmpty)
      .map(
        (segment) => segment.length == 1
            ? segment.toUpperCase()
            : '${segment[0].toUpperCase()}${segment.substring(1).toLowerCase()}',
      )
      .join(' ');
}

String _formatDateTime(DateTime? value) {
  if (value == null) {
    return '-';
  }

  final monthNames = const [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final month = monthNames[value.month - 1];
  final hour = value.hour == 0
      ? 12
      : (value.hour > 12 ? value.hour - 12 : value.hour);
  final minute = value.minute.toString().padLeft(2, '0');
  final period = value.hour >= 12 ? 'PM' : 'AM';
  return '$month ${value.day}, ${value.year} | $hour:$minute $period';
}

String _scheduleDateTimeDisplay(
  Map<String, dynamic>? outputs, {
  required String dateFieldKey,
  required String timeFieldKey,
}) {
  final rawDate = BookingRecordCard.outputFieldValue(outputs, dateFieldKey);
  final rawTime = BookingRecordCard.outputFieldValue(outputs, timeFieldKey);
  final date = _toDateTime(rawDate);
  final time = _parseScheduleTime(rawTime);
  if (date == null || time == null) {
    return '-';
  }

  return _formatDateTime(
    DateTime(date.year, date.month, date.day, time.$1, time.$2),
  ).replaceFirst(' | ', ' - ');
}

(int, int)? _parseScheduleTime(dynamic value) {
  final normalized = value?.toString().trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }

  final match = RegExp(
    r'^(\d{1,2}):(\d{2})(?:\s*([AaPp][Mm]))?$',
  ).firstMatch(normalized);
  if (match == null) {
    return null;
  }
  var hour = int.tryParse(match.group(1) ?? '');
  final minute = int.tryParse(match.group(2) ?? '');
  final period = match.group(3)?.toUpperCase();
  if (hour == null || minute == null || minute > 59) {
    return null;
  }

  if (period != null) {
    if (hour < 1 || hour > 12) {
      return null;
    }
    if (hour == 12) {
      hour = 0;
    }
    if (period == 'PM') {
      hour += 12;
    }
  } else if (hour > 23) {
    return null;
  }
  return (hour, minute);
}

DateTime? _toDateTime(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value;
  }
  return DateTime.tryParse(value.toString());
}
