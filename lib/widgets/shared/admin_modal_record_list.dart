import 'package:webapp/widgets/shared/app_selectable_text.dart';
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
    this.titleBuilder,
    this.onRowTap,
    this.hiddenColumnsAt,
    this.fullWidthRowColumnAt,
    this.leadingColumnSpanAt,
    this.rowGroupKey,
    this.dividerAfterRow,
    this.columnStyles = const {},
    this.columnExtraWidths = const {},
    this.wrappingColumn,
    this.selectableCells = false,
    this.trailingActions = false,
    this.shrinkWrap = false,
    this.horizontalOnDesktop = false,
    this.horizontalOnMobile = false,
    this.pinFirstColumn = false,
    this.centerFirstColumn = false,
    this.fixedFirstColumnWidth,
    this.firstColumnBackgroundColor = Colors.white,
    this.firstColumnHeaderColor = AppColors.primarySurface,
    this.squareCorners = false,
    this.compactLastColumn = false,
    this.firstColumnTrailingPadding =
        AdminListMeasurements.defaultTrailingPadding,
    this.showTitlesRow = true,
    this.scrollHeader,
    this.scrollHeaderItems,
    this.scrollController,
    this.scrollPhysics,
    this.scrollFooter,
    this.emptyMessage,
    this.pageSize = 15,
    this.virtualizeGroups = false,
  });

  /// Presentation batching only; callers retain complete data for search,
  /// totals, copying, and sync. Null opts out for a small fixed table.
  final int? pageSize;
  final bool virtualizeGroups;
  final String? emptyMessage;
  final List<String> titles;
  final int itemCount;
  final List<String> Function(int index) valuesAt;

  final Widget? Function(int row, int column)? cellBuilder;
  final Widget? Function(int column)? titleBuilder;
  final ValueChanged<int>? onRowTap;

  /// Hide row-specific fields, retaining desktop column alignment.
  final Set<int> Function(int row)? hiddenColumnsAt;

  /// Render this column across the row, with optional trailing actions.
  final int? Function(int row)? fullWidthRowColumnAt;

  /// Merge leading columns into column zero while keeping later columns aligned.
  final int Function(int row)? leadingColumnSpanAt;

  /// Adjacent rows with the same key share a card. The first row is the
  /// summary, separated from its expanded detail rows by one divider.
  final Object Function(int index)? rowGroupKey;
  final bool Function(int index)? dividerAfterRow;
  final Map<int, TextStyle> columnStyles;
  final Map<int, double> columnExtraWidths;
  final int? wrappingColumn;
  final bool selectableCells;
  final bool trailingActions;

  /// Let an enclosing scroll view own vertical scrolling.
  final bool shrinkWrap;
  final bool horizontalOnDesktop;
  final bool horizontalOnMobile;
  final bool pinFirstColumn;
  final bool centerFirstColumn;

  /// Full frozen column width, including the card's left border/inset.
  final double? fixedFirstColumnWidth;
  final Color firstColumnBackgroundColor;
  final Color firstColumnHeaderColor;
  final bool squareCorners;
  final bool compactLastColumn;
  final double firstColumnTrailingPadding;
  final bool showTitlesRow;

  /// Header and rows share one lazy vertical viewport when supplied.
  final Widget? scrollHeader;

  /// Separate header sections share the lazy viewport instead of laying out
  /// an entire (potentially fleet-sized) Column as one list child.
  final List<Widget>? scrollHeaderItems;
  final Widget? scrollFooter;
  final ScrollController? scrollController;
  final ScrollPhysics? scrollPhysics;

  static final _measurements = TextWidthCache(capacity: 1024);
  // Both header and item cards inset content by 16px padding plus a 1px
  // border on each side. Include both when deciding whether rows fit.
  static const _horizontalInsets = 2 * (16.0 + 1.0);

  @override
  Widget build(BuildContext context) {
    if (!shrinkWrap && pageSize != null && itemCount > pageSize!) {
      return _PagedModalRecords(list: this);
    }
    return _buildRecords(context, itemCount);
  }

  Widget _buildRecords(BuildContext context, int visibleCount) {
    final itemCount = visibleCount;
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
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      if (fullWidthRowColumnAt?.call(rowIndex) != null) continue;
      final row = rows[rowIndex];
      for (var i = 0; i < titles.length; i++) {
        if (i < (leadingColumnSpanAt?.call(rowIndex) ?? 1) &&
            (leadingColumnSpanAt?.call(rowIndex) ?? 1) > 1) {
          continue;
        }
        for (final line in row[i].split('\n')) {
          widths[i] = AdminListMeasurements.maxValue(
            widths[i],
            measure(line, valueStyles[i]) + (columnExtraWidths[i] ?? 0),
          );
        }
      }
    }
    for (var i = 0; i < widths.length; i++) {
      widths[i] = AdminListMeasurements.resolvedColumnWidth(
        widths[i],
        trailingPadding: compactLastColumn && i == widths.length - 1
            ? 0
            : i == 0
            ? firstColumnTrailingPadding
            : AdminListMeasurements.defaultTrailingPadding,
        // Keep the text allowance even when outer trailing padding is removed.
        // SelectableText needs room beyond the measured glyph width.
        extraWidthAllowance: AdminListMeasurements.defaultExtraWidthAllowance,
      );
    }
    if (pinFirstColumn && widths.isNotEmpty) {
      widths[0] = fixedFirstColumnWidth != null
          ? math.max(1, fixedFirstColumnWidth! - 17)
          : widths[0] - AdminListMeasurements.defaultExtraWidthAllowance;
    }
    for (var row = 0; row < rows.length; row++) {
      final span = leadingColumnSpanAt?.call(row) ?? 1;
      if (span <= 1 || fullWidthRowColumnAt?.call(row) != null) continue;
      final available = widths.take(span).fold<double>(0, (sum, w) => sum + w);
      final required = AdminListMeasurements.resolvedColumnWidth(
        measure(rows[row][0], headerStyle),
      );
      if (required > available) widths[span - 1] += required - available;
    }
    Widget valueText(String text, TextStyle style, {bool centered = false}) =>
        selectableCells
        ? AppSelectableText(
            text,
            style: style,
            textAlign: centered ? TextAlign.center : TextAlign.start,
          )
        : Text(
            text,
            style: style,
            softWrap: true,
            textAlign: centered ? TextAlign.center : TextAlign.start,
          );
    Widget header(
      String title, {
      bool trailing = false,
      bool compact = false,
    }) => selectableCells
        ? AdminListBodyCell(
            alignment: trailing ? Alignment.centerRight : Alignment.centerLeft,
            trailingPadding: trailing || compact
                ? 0
                : AdminListMeasurements.defaultTrailingPadding,
            // A title is static text, not a scrollable read-only editor.
            // SelectionArea preserves selection without caret reveal scrolling.
            child: Text(
              title,
              style: headerStyle.copyWith(
                color: AppColors.primaryColor.withValues(alpha: 0.72),
              ),
            ),
          )
        : AdminListHeaderCell(
            label: title,
            alignment: trailing ? Alignment.centerRight : Alignment.centerLeft,
            trailingPadding: trailing || compact
                ? 0
                : AdminListMeasurements.defaultTrailingPadding,
          );
    final list = LayoutBuilder(
      builder: (context, constraints) {
        final layoutWidths = List<double>.of(widths);
        final wrapping = wrappingColumn;
        if (wrapping != null) {
          final otherWidth = widths.indexed
              .where((entry) => entry.$1 != wrapping)
              .fold<double>(_horizontalInsets, (sum, entry) => sum + entry.$2);
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
          _horizontalInsets + (pinFirstColumn ? 32 : 0),
          (sum, width) => sum + width,
        );
        final desktopRows =
            horizontalOnMobile ||
            (horizontalOnDesktop && MediaQuery.sizeOf(context).width >= 900);
        final wide = desktopRows || tableWidth <= constraints.maxWidth;
        final pinLeading = pinFirstColumn && desktopRows;
        Widget pinnedRow(
          Widget row,
          Widget leading,
          Color color, {
          bool isHeader = false,
        }) => pinLeading
            ? _PinnedRecordRow(
                row: row,
                leading: leading,
                width: layoutWidths.first,
                viewportWidth: constraints.maxWidth,
                color: color,
                verticalInset: isHeader ? 15 : 17,
                radius: squareCorners ? 0 : (isHeader ? 16 : 18),
                centerLeading: isHeader || centerFirstColumn,
              )
            : row;
        Widget listContainer({required Widget child}) =>
            shrinkWrap ? child : Expanded(child: child);
        final tableHeader = AdminListHeaderBar(
          minHeight: 48,
          borderRadius: squareCorners ? 0 : 16,
          horizontalPadding: 16,
          child: wide
              ? pinnedRow(
                  Row(
                    children: [
                      for (var i = 0; i < titles.length; i++) ...[
                        if (pinFirstColumn && i == 1) const SizedBox(width: 32),
                        if (trailingActions && i == titles.length - 1)
                          const Spacer(),
                        AdminListFixedSlot(
                          width: layoutWidths[i],
                          child: (pinLeading && i == 0)
                              ? const SizedBox.shrink()
                              : titleBuilder?.call(i) ??
                                    header(
                                      titles[i],
                                      compact:
                                          compactLastColumn &&
                                          i == titles.length - 1,
                                      trailing:
                                          trailingActions &&
                                          i == titles.length - 1,
                                    ),
                        ),
                      ],
                    ],
                  ),
                  titleBuilder?.call(0) ?? header(titles.first),
                  firstColumnHeaderColor,
                  isHeader: true,
                )
              : titleBuilder?.call(0) ?? header(titles.first),
        );
        Widget buildRowContent(BuildContext context, int index) {
          final values = rows[index];
          final fullWidthColumn = fullWidthRowColumnAt?.call(index);
          if (fullWidthColumn != null) {
            return Row(
              children: [
                Expanded(
                  child:
                      cellBuilder?.call(index, fullWidthColumn) ??
                      valueText(
                        values[fullWidthColumn],
                        valueStyles[fullWidthColumn],
                      ),
                ),
                if (trailingActions) ...[
                  const SizedBox(width: 8),
                  cellBuilder?.call(index, titles.length - 1) ??
                      const SizedBox.shrink(),
                ],
              ],
            );
          }
          final hidden = hiddenColumnsAt?.call(index) ?? const <int>{};
          final leadingSpan = leadingColumnSpanAt?.call(index) ?? 1;
          final visible = [
            for (var i = 0; i < titles.length; i++)
              if (!hidden.contains(i) && (i == 0 || i >= leadingSpan)) i,
          ];
          return wide
              ? pinnedRow(
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      for (var i = 0; i < titles.length; i++)
                        if (i == 0 || i >= leadingSpan) ...[
                          if (pinFirstColumn && i == 1)
                            const SizedBox(width: 32),
                          if (trailingActions && i == titles.length - 1)
                            const Spacer(),
                          AdminListFixedSlot(
                            width: i == 0
                                ? layoutWidths
                                      .take(leadingSpan)
                                      .fold<double>(
                                        0,
                                        (sum, width) => sum + width,
                                      )
                                : layoutWidths[i],
                            child: hidden.contains(i) || (pinLeading && i == 0)
                                ? const SizedBox.shrink()
                                : AdminListBodyCell(
                                    alignment:
                                        trailingActions &&
                                            i == titles.length - 1
                                        ? Alignment.centerRight
                                        : i == 0 && centerFirstColumn
                                        ? Alignment.center
                                        : Alignment.centerLeft,
                                    trailingPadding:
                                        compactLastColumn &&
                                            i == titles.length - 1
                                        ? 0
                                        : trailingActions &&
                                              i == titles.length - 1
                                        ? 0
                                        : i == 0 && centerFirstColumn
                                        ? 0
                                        : i == 0
                                        ? firstColumnTrailingPadding
                                        : AdminListMeasurements
                                              .defaultTrailingPadding,
                                    child:
                                        cellBuilder?.call(index, i) ??
                                        valueText(
                                          values[i],
                                          valueStyles[i],
                                          centered: i == 0 && centerFirstColumn,
                                        ),
                                  ),
                          ),
                        ],
                    ],
                  ),
                  AdminListBodyCell(
                    alignment: centerFirstColumn
                        ? Alignment.center
                        : Alignment.centerLeft,
                    trailingPadding: centerFirstColumn
                        ? 0
                        : firstColumnTrailingPadding,
                    child:
                        cellBuilder?.call(index, 0) ??
                        valueText(
                          values[0],
                          valueStyles[0],
                          centered: centerFirstColumn,
                        ),
                  ),
                  firstColumnBackgroundColor,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final i in visible) ...[
                      if (i != visible.first) const SizedBox(height: 12),
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
        final showEmpty = groups.isEmpty && emptyMessage != null;
        final lazyGroups = virtualizeGroups && rowGroupKey != null;
        final groupCount = showEmpty
            ? 1
            : lazyGroups
            ? itemCount
            : groups.length;
        bool sameGroup(int a, int b) =>
            lazyGroups &&
            a >= 0 &&
            b < itemCount &&
            rowGroupKey!(a) == rowGroupKey!(b);
        double groupGap(int index) => sameGroup(index, index + 1) ? 0 : 12;
        Widget buildGroup(BuildContext context, int index) {
          if (showEmpty) {
            return AdminListItemCard(
              borderRadius: BorderRadius.circular(squareCorners ? 0 : 18),
              padding: const EdgeInsets.all(24),
              child: AdminListStateText(message: emptyMessage!),
            );
          }
          if (lazyGroups) {
            final first = !sameGroup(index - 1, index);
            final last = !sameGroup(index, index + 1);
            final divider =
                !last && (first || (dividerAfterRow?.call(index) ?? false));
            return CustomPaint(
              key: ValueKey('admin-record-group-row-$index'),
              painter: _GroupRowBorder(
                first: first,
                last: last,
                radius: squareCorners ? 0 : 18,
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  17,
                  first ? 17 : 0,
                  17,
                  last ? 17 : 0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    buildRowContent(context, index),
                    if (divider)
                      const Divider(height: 25, color: AppColors.primaryBorder)
                    else if (!last)
                      const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          }
          final group = groups[index];
          final card = AdminListItemCard(
            borderRadius: BorderRadius.circular(squareCorners ? 0 : 18),
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
                        if (row > group.start + 1 &&
                            !(dividerAfterRow?.call(row - 1) ?? false))
                          const SizedBox(height: 16),
                        buildRowContent(context, row),
                        if (dividerAfterRow?.call(row) ?? false)
                          const Divider(
                            height: 25,
                            color: AppColors.primaryBorder,
                          ),
                      ],
                    ],
                  ),
          );
          if (onRowTap == null) return card;
          return Semantics(
            button: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(squareCorners ? 0 : 16),
              onTap: () => onRowTap!(group.start),
              child: card,
            ),
          );
        }

        final headerCount = scrollHeaderItems?.length ?? 1;
        final rowStart = headerCount + (showTitlesRow ? 1 : 0);
        final content = scrollHeader != null || scrollHeaderItems != null
            ? ListView.separated(
                controller: scrollController,
                physics: scrollPhysics,
                primary: false,
                padding: EdgeInsets.zero,
                itemCount:
                    groupCount + rowStart + (scrollFooter == null ? 0 : 1),
                separatorBuilder: (_, index) => SizedBox(
                  height: index < headerCount
                      ? 0
                      : index < rowStart
                      ? 12
                      : groupGap(index - rowStart),
                ),
                itemBuilder: (context, index) {
                  if (index < headerCount) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: constraints.maxWidth,
                        child: scrollHeaderItems?[index] ?? scrollHeader,
                      ),
                    );
                  }
                  if (showTitlesRow && index == headerCount) return tableHeader;
                  if (index == groupCount + rowStart) return scrollFooter!;
                  return buildGroup(context, index - rowStart);
                },
              )
            : Column(
                mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
                children: [
                  if (showTitlesRow) ...[
                    tableHeader,
                    const SizedBox(height: 12),
                  ],
                  listContainer(
                    child: ListView.separated(
                      controller: scrollController,
                      shrinkWrap: shrinkWrap,
                      physics: shrinkWrap
                          ? const NeverScrollableScrollPhysics()
                          : scrollPhysics,
                      primary: false,
                      itemCount: groupCount + (scrollFooter == null ? 0 : 1),
                      separatorBuilder: (_, index) =>
                          SizedBox(height: groupGap(index)),
                      itemBuilder: (context, index) => index == groupCount
                          ? scrollFooter!
                          : buildGroup(context, index),
                    ),
                  ),
                ],
              );
        if (desktopRows &&
            (pinFirstColumn || tableWidth > constraints.maxWidth)) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: math.max(tableWidth, constraints.maxWidth),
              height: shrinkWrap ? null : constraints.maxHeight,
              child: content,
            ),
          );
        }
        return content;
      },
    );
    return selectableCells && SelectionContainer.maybeOf(context) == null
        ? SelectionArea(child: list)
        : list;
  }
}

/// Paint the leading cell at the viewport's left edge while retaining one
/// shared lazy vertical list and one horizontal scroll position.
class _PinnedRecordRow extends StatelessWidget {
  const _PinnedRecordRow({
    required this.row,
    required this.leading,
    required this.width,
    required this.viewportWidth,
    required this.color,
    required this.verticalInset,
    required this.radius,
    required this.centerLeading,
  });
  final Widget row;
  final Widget leading;
  final double width;
  final double viewportWidth;
  final Color color;
  final double verticalInset;
  final double radius;
  final bool centerLeading;

  @override
  Widget build(BuildContext context) {
    final position = Scrollable.of(context, axis: Axis.horizontal).position;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRect(
          clipper: _PinnedRecordContentClipper(position, width + 32),
          child: row,
        ),
        AnimatedBuilder(
          animation: position,
          child: Container(
            padding: EdgeInsets.only(left: centerLeading ? 0 : 16),
            decoration: BoxDecoration(
              color: color,
              border: Border.all(color: AppColors.primaryBorder, width: 1),
              borderRadius: BorderRadius.horizontal(
                left: Radius.circular(radius),
              ),
            ),
            child: Align(
              alignment: centerLeading
                  ? Alignment.center
                  : Alignment.centerLeft,
              child: leading,
            ),
          ),
          builder: (context, child) => Positioned(
            left: position.pixels - 17,
            top: -verticalInset,
            bottom: -verticalInset,
            width: width + 17,
            child: ColoredBox(color: Colors.white, child: child!),
          ),
        ),
        AnimatedBuilder(
          animation: position,
          child: const ColoredBox(color: AppColors.primaryBorder),
          builder: (context, child) => Positioned(
            // Row content begins 17px inside its card. Keep the border on
            // the viewport edge instead of at the offscreen end of the table.
            left: position.pixels + viewportWidth - 18,
            top: -verticalInset,
            bottom: -verticalInset,
            width: 1,
            child: IgnorePointer(child: child!),
          ),
        ),
      ],
    );
  }
}

class _PinnedRecordContentClipper extends CustomClipper<Rect> {
  _PinnedRecordContentClipper(this.position, this.leadingWidth)
    : super(reclip: position);

  final ScrollPosition position;
  final double leadingWidth;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    (position.pixels + leadingWidth).clamp(0.0, size.width),
    0,
    size.width,
    size.height,
  );

  @override
  bool shouldReclip(_PinnedRecordContentClipper oldClipper) =>
      oldClipper.position != position ||
      oldClipper.leadingWidth != leadingWidth;
}

class _PagedModalRecords extends StatefulWidget {
  const _PagedModalRecords({required this.list});
  final AdminModalRecordList list;
  @override
  State<_PagedModalRecords> createState() => _PagedModalRecordsState();
}

class _PagedModalRecordsState extends State<_PagedModalRecords> {
  late int visible = widget.list.pageSize!;
  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: (notice) {
          if (notice.metrics.axis == Axis.vertical &&
              notice.metrics.extentAfter < 240 &&
              ((notice is ScrollUpdateNotification &&
                      (notice.scrollDelta ?? 0) > 0) ||
                  (notice is OverscrollNotification &&
                      notice.overscroll > 0)) &&
              visible < widget.list.itemCount) {
            setState(
              () => visible = (visible + widget.list.pageSize!).clamp(
                0,
                widget.list.itemCount,
              ),
            );
          }
          return false;
        },
        child: widget.list._buildRecords(
          context,
          visible.clamp(0, widget.list.itemCount),
        ),
      );
}

class _GroupRowBorder extends CustomPainter {
  const _GroupRowBorder({
    required this.first,
    required this.last,
    required this.radius,
  });
  final bool first, last;
  final double radius;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        rect,
        topLeft: Radius.circular(first ? radius : 0),
        topRight: Radius.circular(first ? radius : 0),
        bottomLeft: Radius.circular(last ? radius : 0),
        bottomRight: Radius.circular(last ? radius : 0),
      ),
      Paint()..color = Colors.white,
    );
    final r = radius.clamp(0.0, size.height / 2);
    final right = size.width - 0.5;
    final bottom = size.height - 0.5;
    final path = Path();
    path.moveTo(0.5, first ? r : 0);
    if (first) {
      path.quadraticBezierTo(0.5, 0.5, r, 0.5);
      path.lineTo(right - r, 0.5);
      path.quadraticBezierTo(right, 0.5, right, r);
    } else {
      path.moveTo(right, 0);
    }
    path.lineTo(right, last ? bottom - r : size.height);
    if (last) {
      path.quadraticBezierTo(right, bottom, right - r, bottom);
      path.lineTo(r, bottom);
      path.quadraticBezierTo(0.5, bottom, 0.5, bottom - r);
    } else {
      path.moveTo(0.5, size.height);
    }
    path.lineTo(0.5, first ? r : 0);
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.primaryBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _GroupRowBorder oldDelegate) =>
      first != oldDelegate.first ||
      last != oldDelegate.last ||
      radius != oldDelegate.radius;
}
