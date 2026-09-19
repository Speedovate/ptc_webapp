import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/utils/text_width_cache.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';

/// Modal lists share the existing page header, cells and responsive item cards.
class AdminModalRecordList extends StatelessWidget {
  const AdminModalRecordList({
    super.key,
    required this.titles,
    required this.itemCount,
    required this.valuesAt,
    this.cellBuilder,
    this.columnStyles = const {},
    this.columnExtraWidths = const {},
    this.wrappingColumn,
    this.selectableCells = false,
  });
  final List<String> titles;
  final int itemCount;
  final List<String> Function(int index) valuesAt;

  final Widget? Function(int row, int column)? cellBuilder;
  final Map<int, TextStyle> columnStyles;
  final Map<int, double> columnExtraWidths;
  final int? wrappingColumn;
  final bool selectableCells;

  static final _measurements = TextWidthCache(capacity: 1024);

  @override
  Widget build(BuildContext context) {
    final rows = List.generate(itemCount, valuesAt, growable: false);
    final inherited = DefaultTextStyle.of(context).style;
    final headerStyle = inherited.merge(
      const TextStyle(fontWeight: FontWeight.w700),
    );
    final valueStyles = [
      for (var i = 0; i < titles.length; i++)
        inherited.merge(
          columnStyles[i] ??
              TextStyle(
                color: AppColors.textPrimary,
                fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w500,
              ),
        ),
    ];
    double measure(String text, TextStyle style) => _measurements.measure(
      text: text,
      style: style,
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
      locale: Localizations.maybeLocaleOf(context),
    );
    final widths = [for (final title in titles) measure(title, headerStyle)];
    for (final row in rows) {
      for (var i = 0; i < titles.length; i++) {
        for (final line in row[i].split('\n')) {
          widths[i] = AdminListMeasurements.maxValue(
            widths[i],
            measure(line, valueStyles[i]) + (columnExtraWidths[i] ?? 0),
          );
        }
      }
    }
    for (var i = 0; i < widths.length; i++) {
      widths[i] = AdminListMeasurements.resolvedColumnWidth(widths[i]);
    }
    Widget valueText(String text, TextStyle style) => selectableCells
        ? SelectableText(text, style: style)
        : Text(text, style: style, softWrap: true);
    Widget header(String title) => selectableCells
        ? AdminListBodyCell(
            child: SelectableText(
              title,
              style: headerStyle.copyWith(
                color: AppColors.primaryColor.withValues(alpha: 0.72),
              ),
            ),
          )
        : AdminListHeaderCell(label: title);
    return LayoutBuilder(
      builder: (context, constraints) {
        final layoutWidths = List<double>.of(widths);
        final wrapping = wrappingColumn;
        if (wrapping != null) {
          final otherWidth = widths.indexed
              .where((entry) => entry.$1 != wrapping)
              .fold<double>(32, (sum, entry) => sum + entry.$2);
          final available = constraints.maxWidth - otherWidth;
          final minimum = math.max(
            160.0,
            AdminListMeasurements.resolvedColumnWidth(
              measure(titles[wrapping], headerStyle),
            ),
          );
          // Keep short values content-sized; long status/error text uses the
          // remaining table space and grows vertically instead of widening it.
          layoutWidths[wrapping] = math.min(
            widths[wrapping],
            math.max(minimum, math.min(320.0, available)),
          );
        }
        final tableWidth = layoutWidths.fold<double>(
          32,
          (sum, width) => sum + width,
        );
        final wide = tableWidth <= constraints.maxWidth;
        return Column(
          children: [
            AdminListHeaderBar(
              minHeight: 48,
              borderRadius: 16,
              horizontalPadding: 16,
              child: wide
                  ? Row(
                      children: [
                        for (var i = 0; i < titles.length; i++)
                          AdminListFixedSlot(
                            width: layoutWidths[i],
                            child: header(titles[i]),
                          ),
                      ],
                    )
                  : header(titles.first),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                primary: false,
                itemCount: itemCount,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final values = rows[index];
                  return AdminListItemCard(
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              for (var i = 0; i < titles.length; i++)
                                AdminListFixedSlot(
                                  width: layoutWidths[i],
                                  child: AdminListBodyCell(
                                    child:
                                        cellBuilder?.call(index, i) ??
                                        valueText(values[i], valueStyles[i]),
                                  ),
                                ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var i = 0; i < titles.length; i++) ...[
                                if (i > 0) const SizedBox(height: 12),
                                if (cellBuilder?.call(index, i)
                                    case final Widget cell)
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      AdminListHeaderCell(label: titles[i]),
                                      const SizedBox(height: 6),
                                      cell,
                                    ],
                                  )
                                else if (selectableCells)
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      header(titles[i]),
                                      const SizedBox(height: 6),
                                      valueText(values[i], valueStyles[i]),
                                    ],
                                  )
                                else
                                  AdminListResponsiveField(
                                    title: titles[i],
                                    value: values[i],
                                    width: double.infinity,
                                    centered: false,
                                    isTitle: i == 0,
                                  ),
                              ],
                            ],
                          ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
