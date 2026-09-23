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
    this.rowGroupKey,
    this.columnStyles = const {},
    this.columnExtraWidths = const {},
    this.wrappingColumn,
    this.selectableCells = false,
    this.trailingActions = false,
    this.shrinkWrap = false,
    this.horizontalOnDesktop = false,
    this.scrollHeader,
    this.scrollController,
    this.scrollFooter,
  });
  final List<String> titles;
  final int itemCount;
  final List<String> Function(int index) valuesAt;

  final Widget? Function(int row, int column)? cellBuilder;

  /// Adjacent rows with the same key share a card. The first row is the
  /// summary, separated from its expanded detail rows by one divider.
  final Object Function(int index)? rowGroupKey;
  final Map<int, TextStyle> columnStyles;
  final Map<int, double> columnExtraWidths;
  final int? wrappingColumn;
  final bool selectableCells;
  final bool trailingActions;

  /// Let an enclosing scroll view own vertical scrolling.
  final bool shrinkWrap;
  final bool horizontalOnDesktop;

  /// Header and rows share one lazy vertical viewport when supplied.
  final Widget? scrollHeader;
  final Widget? scrollFooter;
  final ScrollController? scrollController;

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
    Widget header(String title, {bool trailing = false}) => selectableCells
        ? AdminListBodyCell(
            child: SelectableText(
              title,
              style: headerStyle.copyWith(
                color: AppColors.primaryColor.withValues(alpha: 0.72),
              ),
            ),
          )
        : AdminListHeaderCell(
            label: title,
            alignment: trailing ? Alignment.centerRight : Alignment.centerLeft,
            trailingPadding: trailing
                ? 0
                : AdminListMeasurements.defaultTrailingPadding,
          );
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
        final desktopRows =
            horizontalOnDesktop && MediaQuery.sizeOf(context).width >= 900;
        final wide = desktopRows || tableWidth <= constraints.maxWidth;
        Widget listContainer({required Widget child}) =>
            shrinkWrap ? child : Expanded(child: child);
        final tableHeader = AdminListHeaderBar(
          minHeight: 48,
          borderRadius: 16,
          horizontalPadding: 16,
          child: wide
              ? Row(
                  children: [
                    for (var i = 0; i < titles.length; i++) ...[
                      if (trailingActions && i == titles.length - 1)
                        const Spacer(),
                      AdminListFixedSlot(
                        width: layoutWidths[i],
                        child: header(
                          titles[i],
                          trailing: trailingActions && i == titles.length - 1,
                        ),
                      ),
                    ],
                  ],
                )
              : header(titles.first),
        );
        Widget buildRowContent(BuildContext context, int index) {
          final values = rows[index];
          return wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    for (var i = 0; i < titles.length; i++) ...[
                      if (trailingActions && i == titles.length - 1)
                        const Spacer(),
                      AdminListFixedSlot(
                        width: layoutWidths[i],
                        child: AdminListBodyCell(
                          alignment: trailingActions && i == titles.length - 1
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          trailingPadding:
                              trailingActions && i == titles.length - 1
                              ? 0
                              : AdminListMeasurements.defaultTrailingPadding,
                          child:
                              cellBuilder?.call(index, i) ??
                              valueText(values[i], valueStyles[i]),
                        ),
                      ),
                    ],
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < titles.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      if (cellBuilder?.call(index, i) case final Widget cell)
                        Column(
                          crossAxisAlignment:
                              trailingActions && i == titles.length - 1
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            header(
                              titles[i],
                              trailing:
                                  trailingActions && i == titles.length - 1,
                            ),
                            const SizedBox(height: 6),
                            cell,
                          ],
                        )
                      else if (selectableCells)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                );
        }

        final groups = <({int start, int end})>[];
        for (var start = 0; start < itemCount;) {
          var end = start + 1;
          if (rowGroupKey != null) {
            final key = rowGroupKey!(start);
            while (end < itemCount && rowGroupKey!(end) == key) {
              end++;
            }
          }
          groups.add((start: start, end: end));
          start = end;
        }
        Widget buildGroup(BuildContext context, int index) {
          final group = groups[index];
          return AdminListItemCard(
            child: group.end == group.start + 1
                ? buildRowContent(context, group.start)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      buildRowContent(context, group.start),
                      const Divider(height: 25, color: AppColors.primaryBorder),
                      for (
                        var row = group.start + 1;
                        row < group.end;
                        row++
                      ) ...[
                        if (row > group.start + 1) const SizedBox(height: 16),
                        buildRowContent(context, row),
                      ],
                    ],
                  ),
          );
        }

        final content = scrollHeader != null
            ? ListView.separated(
                controller: scrollController,
                primary: false,
                padding: EdgeInsets.zero,
                itemCount: groups.length + 2 + (scrollFooter == null ? 0 : 1),
                separatorBuilder: (_, index) =>
                    SizedBox(height: index == 0 ? 0 : 12),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: constraints.maxWidth,
                        child: scrollHeader,
                      ),
                    );
                  }
                  if (index == 1) return tableHeader;
                  if (index == groups.length + 2) return scrollFooter!;
                  return buildGroup(context, index - 2);
                },
              )
            : Column(
                mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
                children: [
                  tableHeader,
                  const SizedBox(height: 12),
                  listContainer(
                    child: ListView.separated(
                      shrinkWrap: shrinkWrap,
                      physics: shrinkWrap
                          ? const NeverScrollableScrollPhysics()
                          : null,
                      primary: false,
                      itemCount: groups.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: buildGroup,
                    ),
                  ),
                ],
              );
        if (desktopRows && tableWidth > constraints.maxWidth) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth + 2,
              height: shrinkWrap ? null : constraints.maxHeight,
              child: content,
            ),
          );
        }
        return content;
      },
    );
  }
}
