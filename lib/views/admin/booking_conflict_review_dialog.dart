import 'package:webapp/widgets/shared/lazy_data_scroll_view.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webapp/services/booking_conflict_review_service.dart';
import 'package:webapp/view_models/admin/booking_conflict_review.vm.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';

class BookingConflictReviewDialog extends StatefulWidget {
  const BookingConflictReviewDialog({super.key, required this.viewModel});
  final BookingConflictReviewViewModel viewModel;
  @override
  State<BookingConflictReviewDialog> createState() =>
      _BookingConflictReviewDialogState();
}

class _BookingConflictReviewDialogState
    extends State<BookingConflictReviewDialog> {
  BookingConflictReviewViewModel get vm => widget.viewModel;
  @override
  void initState() {
    super.initState();
    vm.load();
  }

  @override
  void dispose() {
    vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: vm,
    builder: (context, _) {
      final preview = vm.preview;
      return PopScope(
        canPop: !vm.busy,
        child: AdminModalShell(
          title: 'Booking ID conflicts',
          maxWidth: 1000,
          flexibleBody: true,
          bodyHandlesScrolling: true,
          actionsInset: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          actions: [
            TextButton(
              onPressed: vm.busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
          child: LazyDataScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SliverSection(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Compare both copies before choosing which booking data to keep. The numeric ID and its original creation time will remain. Both versions are archived.',
                ),
                const SizedBox(height: 12),
                if (vm.busy) const LinearProgressIndicator(),
                if (vm.error != null)
                  Text(
                    vm.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (vm.success != null) Text(vm.success!),
                TextButton(
                  onPressed: vm.busy ? null : vm.load,
                  child: const Text('Refresh conflicts'),
                ),
                LazySliverList(
                  items: vm.conflicts,
                  itemBuilder: (context, id) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton(
                      onPressed: vm.busy ? null : () => vm.select(id),
                      child: Text('Review $id'),
                    ),
                  ),
                ),
                if (!vm.busy && vm.conflicts.isEmpty)
                  const Text(
                    'No pending ID conflicts. If a temporary booking was just detected, refresh after its repair check finishes.',
                  ),
                if (preview != null) ...[
                  const Divider(),
                  Text(
                    'Temporary copy → Booking ${preview.targetId ?? "unverified"}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(preview.reason),
                  const SizedBox(height: 12),
                  LazySliverList(
                    items: _differences(
                      preview.source ?? {},
                      preview.canonical ?? {},
                    ),
                    itemBuilder: (context, entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.key.replaceAll('_', ' '),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final values = [
                                _value('Temporary copy', entry.value.$1),
                                _value('Numeric booking', entry.value.$2),
                              ];
                              if (constraints.maxWidth < 600) {
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: values,
                                );
                              }
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: values[0]),
                                  const SizedBox(width: 12),
                                  Expanded(child: values[1]),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  ExpansionTile(
                    title: const Text('Full records and workflow history'),
                    children: [
                      Builder(
                        builder: (_) =>
                            _value('Temporary copy', preview.source),
                      ),
                      Builder(
                        builder: (_) =>
                            _value('Numeric booking', preview.canonical),
                      ),
                    ],
                  ),
                  if (!preview.canApply)
                    const Text(
                      'Identity is incomplete or inconsistent. Reconciliation is disabled; no records will be changed.',
                    ),
                  if (preview.canApply) ...[
                    if (!preview.canUseTemporary)
                      const Text(
                        'The workflow has progressed beyond a supported assignment correction. Keep the numeric version or resolve this through the booking workflow.',
                      ),
                    DropdownButtonFormField<BookingConflictChoice>(
                      key: ValueKey('${preview.id}-${vm.choice}'),
                      initialValue: vm.choice,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Version to keep',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: BookingConflictChoice.keepNumeric,
                          child: Text('Keep numeric booking data'),
                        ),
                        DropdownMenuItem(
                          enabled: preview.canUseTemporary,
                          value: BookingConflictChoice.useTemporary,
                          child: Text(
                            'Use temporary copy data under numeric ID',
                          ),
                        ),
                      ],
                      onChanged: vm.busy ? null : vm.choose,
                    ),
                    if (vm.choice != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          vm.choice == BookingConflictChoice.keepNumeric
                              ? 'Keep the numeric booking’s status, assignment and history. Archive and remove the temporary duplicate.'
                              : 'Replace the numeric booking’s status, assignment and history with the temporary copy. Its cancellation or missing chassis will also apply. The old history stays in the archive.',
                        ),
                      ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: vm.acknowledged,
                      onChanged: vm.busy || vm.choice == null
                          ? null
                          : (value) => vm.acknowledge(value ?? false),
                      title: const Text(
                        'I reviewed both copies and confirm this version and its assignments.',
                      ),
                    ),
                  ],
                  FilledButton(
                    onPressed: vm.canApply ? vm.apply : null,
                    child: const Text('Apply selected version'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
  Widget _value(String label, Object? value) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    margin: const EdgeInsets.only(top: 4),
    decoration: BoxDecoration(
      border: Border.all(color: Colors.grey.shade300),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(
          value == null
              ? 'Not set'
              : JsonEncoder.withIndent(
                  '  ',
                  (value) => value.toString(),
                ).convert(value),
        ),
      ],
    ),
  );
  List<MapEntry<String, (Object?, Object?)>> _differences(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final keys = {...a.keys, ...b.keys}.toList()..sort();
    return [
      for (final key in keys)
        if (!BookingConflictReviewService.same(a[key], b[key]))
          MapEntry(key, (
            a.containsKey(key) ? a[key] : 'Missing field',
            b.containsKey(key) ? b[key] : 'Missing field',
          )),
    ];
  }
}
