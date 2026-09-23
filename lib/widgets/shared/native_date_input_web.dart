// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/material.dart';

/// Uses the browser's date control, including its device-specific calendar.
class NativeDateInput extends StatefulWidget {
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
  State<NativeDateInput> createState() => _NativeDateInputState();
}

class _NativeDateInputState extends State<NativeDateInput> {
  html.InputElement? _input;
  StreamSubscription<html.Event>? _change;
  String _date(DateTime? value) => value == null
      ? ''
      : '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  @override
  void didUpdateWidget(covariant NativeDateInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _input?.value = _date(widget.value);
  }

  @override
  void dispose() {
    _change?.cancel();
    _input = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(widget.label),
      const SizedBox(height: 8),
      SizedBox(
        height: 48,
        child: HtmlElementView.fromTagName(
          tagName: 'input',
          onElementCreated: (element) {
            final input = element as html.InputElement;
            _input = input;
            input
              ..type = 'date'
              ..min = '2000-01-01'
              ..max = '2100-12-31'
              ..value = _date(widget.value)
              ..setAttribute('aria-label', widget.label)
              ..style.cssText =
                  'width:100%;height:100%;box-sizing:border-box;border:1px solid #E4D8FF;border-radius:12px;padding:10px 12px;background:white;color:#221A3F;font:inherit;color-scheme:light;';
            _change = input.onInput.listen((_) {
              final date = DateTime.tryParse(input.value ?? '');
              widget.onChanged(
                date == null
                    ? null
                    : DateTime.utc(date.year, date.month, date.day),
              );
            });
          },
        ),
      ),
    ],
  );
}
