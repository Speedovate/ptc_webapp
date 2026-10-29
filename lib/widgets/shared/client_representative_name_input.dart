import 'package:flutter/material.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/services/client_representative_suggestions.dart';
import 'type_history_input.dart';

/// Adds the same client-scoped representative lookup to controller-based editors.
class ClientRepresentativeNameInput extends StatefulWidget {
  const ClientRepresentativeNameInput({
    super.key,
    required this.clientId,
    required this.bookings,
    required this.nameController,
    required this.phoneController,
    required this.child,
  });
  final String? clientId;
  final List<Booking> bookings;
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final Widget child;

  @override
  State<ClientRepresentativeNameInput> createState() =>
      _ClientRepresentativeNameInputState();
}

class _ClientRepresentativeNameInputState
    extends State<ClientRepresentativeNameInput> {
  final _autofill = RepresentativePhoneAutofill();
  bool _settingPhone = false;
  List<String> _names = const [];
  Map<String, String> _phones = const {};

  void _resolve() {
    _names = clientRepresentativeSuggestions(widget.bookings, widget.clientId);
    _phones = clientRepresentativePhones(widget.bookings, widget.clientId);
  }

  void _phoneChanged() {
    if (!_settingPhone) _autofill.markManualEdit();
  }

  @override
  void initState() {
    super.initState();
    _resolve();
    widget.phoneController.addListener(_phoneChanged);
  }

  @override
  void didUpdateWidget(covariant ClientRepresentativeNameInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phoneController != widget.phoneController) {
      oldWidget.phoneController.removeListener(_phoneChanged);
      widget.phoneController.addListener(_phoneChanged);
      _autofill.reset();
    }
    if (oldWidget.clientId != widget.clientId ||
        !identical(oldWidget.bookings, widget.bookings)) {
      _resolve();
    }
  }

  void _selected(String name) {
    final key = name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    final value = _autofill.valueForSelection(
      suggestedPhone: _phones[key],
      currentPhone: widget.phoneController.text,
    );
    if (value == null) return;
    _settingPhone = true;
    try {
      widget.phoneController.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    } finally {
      _settingPhone = false;
    }
  }

  @override
  void dispose() {
    widget.phoneController.removeListener(_phoneChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TypeHistoryInput(
    controller: widget.nameController,
    historyKey: null,
    browseOptionsOnFocus: true,
    suggestionLimit: 10,
    includeExactMatch: true,
    matchInputOnly: true,
    options: _names,
    suggestionDetail: (name) =>
        _phones[name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase()] ??
        'Walang phone number',
    onSelected: _selected,
    child: widget.child,
  );
}
