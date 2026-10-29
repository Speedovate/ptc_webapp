import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/services/field_type_history_service.dart';

/// Adds optional suggestions below an existing input without replacing its
/// controller, focus handling, validation, or submission callbacks.
class TypeHistoryInput extends StatefulWidget {
  const TypeHistoryInput({
    super.key,
    required this.controller,
    required this.historyKey,
    required this.child,
    this.inputFormatters,
    this.service,
    this.options = const [],
    this.optionsBottomSpacing = 6,
    this.browseOptionsOnFocus = false,
    this.suggestionLimit,
    this.includeExactMatch = false,
    this.matchInputOnly = false,
    this.onSelected,
    this.suggestionDetail,
  });
  final TextEditingController controller;
  final String? historyKey;
  final Widget child;
  final List<TextInputFormatter>? inputFormatters;
  final FieldTypeHistoryService? service;

  /// Existing field options already loaded with the Firestore form schema.
  final List<String> options;
  final double optionsBottomSpacing;

  /// Show supplied choices immediately when focusing a prefilled field.
  final bool browseOptionsOnFocus;
  final int? suggestionLimit;

  /// Keep an already typed value selectable for linked-field autofill.
  final bool includeExactMatch;

  /// Filter even on focus and show no options for an empty query.
  final bool matchInputOnly;
  final ValueChanged<String>? onSelected;
  final String? Function(String)? suggestionDetail;
  @override
  State<TypeHistoryInput> createState() => _TypeHistoryInputState();
}

class _TypeHistoryInputState extends State<TypeHistoryInput> {
  Timer? _debounce;
  int _generation = 0;
  bool _focused = false;
  late TextEditingValue _lastValue;
  bool _selecting = false;
  List<String> _options = const [];

  @override
  void initState() {
    super.initState();
    _lastValue = widget.controller.value;
    widget.controller.addListener(_controllerChanged);
  }

  @override
  void didUpdateWidget(covariant TypeHistoryInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_controllerChanged);
      _lastValue = widget.controller.value;
      widget.controller.addListener(_controllerChanged);
    }
    if (oldWidget.historyKey != widget.historyKey ||
        oldWidget.controller != widget.controller ||
        !listEquals(oldWidget.options, widget.options)) {
      _changed();
    }
  }

  void _controllerChanged() {
    final value = widget.controller.value;
    final unchanged =
        value.text == _lastValue.text &&
        value.composing == _lastValue.composing;
    _lastValue = value;
    if (widget.browseOptionsOnFocus && unchanged) return;
    _changed();
  }

  void _changed({bool browse = false}) {
    _debounce?.cancel();
    final generation = ++_generation;
    if (mounted && _options.isNotEmpty) setState(() => _options = []);
    if (!_focused ||
        _selecting ||
        (widget.historyKey == null && !widget.browseOptionsOnFocus) ||
        !widget.controller.value.composing.isCollapsed) {
      return;
    }
    final key = widget.historyKey;
    final text = widget.controller.text;
    String normalized(String value) =>
        value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    final query = browse && !widget.matchInputOnly ? '' : normalized(text);
    if (widget.matchInputOnly && query.isEmpty) return;
    List<String> matchingOptions(List<String> history) {
      final seen = <String>{};
      final matching = [...history, ...widget.options].where((value) {
        final candidate = normalized(value);
        return candidate.isNotEmpty &&
            (widget.matchInputOnly
                ? candidate.contains(query)
                : candidate.startsWith(query)) &&
            (widget.includeExactMatch || value != text) &&
            seen.add(candidate);
      });
      final sorted = matching.toList();
      if (widget.matchInputOnly) {
        int rank(String value) => normalized(value) == query
            ? 0
            : normalized(value).startsWith(query)
            ? 1
            : 2;
        // Bucket by relevance while preserving history order for equal matches.
        final ranked = [
          for (var score = 0; score <= 2; score++)
            ...sorted.where((value) => rank(value) == score),
        ];
        sorted
          ..clear()
          ..addAll(ranked);
      }
      final limit =
          widget.suggestionLimit ?? (widget.browseOptionsOnFocus ? null : 10);
      return (limit == null ? sorted : sorted.take(limit)).toList();
    }

    if (widget.browseOptionsOnFocus) {
      setState(() => _options = matchingOptions(const []));
    }
    if (key == null) return;
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final options = await (widget.service ?? FieldTypeHistoryService.instance)
          .suggestions(key, query);
      if (!mounted || !_focused || generation != _generation) return;
      setState(() => _options = matchingOptions(options));
    });
  }

  void _select(String value) {
    _selecting = true;
    try {
      final old = widget.controller.value;
      var next = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
      for (final formatter
          in widget.inputFormatters ?? <TextInputFormatter>[]) {
        next = formatter.formatEditUpdate(old, next);
      }
      widget.controller.value = next;
      _debounce?.cancel();
      ++_generation;
      setState(() => _options = []);
      widget.onSelected?.call(widget.controller.text);
    } finally {
      _selecting = false;
    }
  }

  @override
  void dispose() {
    ++_generation;
    _debounce?.cancel();
    widget.controller.removeListener(_controllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onFocusChange: (value) {
      _focused = value;
      _changed(browse: value && widget.browseOptionsOnFocus);
    },
    child: TextFieldTapRegion(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          widget.child,
          if (_options.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: AppColors.primaryBorder),
                borderRadius: BorderRadius.circular(16),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                primary: false,
                padding: EdgeInsets.zero,
                itemCount: _options.length,
                itemBuilder: (context, index) => TextButton(
                  style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    foregroundColor: AppColors.primaryColor,
                    backgroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    minimumSize: const Size(0, 48),
                  ),
                  onPressed: () => _select(_options[index]),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _options[index],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (widget.suggestionDetail?.call(_options[index])
                            case final String detail) ...[
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              detail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_options.isNotEmpty)
            SizedBox(height: widget.optionsBottomSpacing),
        ],
      ),
    ),
  );
}
