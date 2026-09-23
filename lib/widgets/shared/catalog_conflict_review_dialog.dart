import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';
import 'package:webapp/widgets/shared/admin_modal_record_list.dart';

List<List<String>> catalogConflictRows(CatalogConflictReview review) {
  Map<String, String> flatten(Map<String, dynamic> document) {
    final result = <String, String>{};
    void walk(Object? value, String path) {
      if (value is Map && value.isNotEmpty) {
        for (final entry in value.entries) {
          walk(
            entry.value,
            path.isEmpty ? '${entry.key}' : '$path / ${entry.key}',
          );
        }
      } else if (value is List && value.isNotEmpty) {
        for (var i = 0; i < value.length; i++) {
          final item = value[i];
          final label = item is Map ? item['id'] ?? item['name'] ?? i : i;
          walk(item, '$path / $label');
        }
      } else {
        result[path] = value is String ? value : jsonEncode(value);
      }
    }

    walk(document, '');
    return result;
  }

  final remoteVersions = [
    ...(review.server['matrix_versions'] as List? ?? []).whereType<Map>(),
    ...review.serverVersions,
  ];
  final versions = <String, Map>{
    for (final version in remoteVersions) '${version['id']}': version,
    for (final version
        in (review.proposed['matrix_versions'] as List? ?? []).whereType<Map>())
      '${version['id']}': version,
  };
  final local = flatten({
    ...review.proposed,
    'matrix_versions': versions.values.toList(),
  });
  final server = flatten({...review.server, 'matrix_versions': remoteVersions});
  final fields = {...local.keys, ...server.keys}.toList()..sort();
  return [
    for (final field in fields)
      if (local[field] != server[field])
        [
          field.replaceAll('_', ' '),
          local[field] ?? 'Not present',
          server[field] ?? 'Not present',
        ],
  ];
}

class CatalogConflictReviewDialog extends StatefulWidget {
  const CatalogConflictReviewDialog({
    super.key,
    required this.review,
    required this.onApply,
  });
  final CatalogConflictReview review;
  final Future<void> Function() onApply;
  @override
  State<CatalogConflictReviewDialog> createState() =>
      _CatalogConflictReviewDialogState();
}

class _CatalogConflictReviewDialogState
    extends State<CatalogConflictReviewDialog> {
  bool _saving = false;
  String? _error;
  @override
  Widget build(BuildContext context) {
    final rows = catalogConflictRows(widget.review);
    return AdminModalShell(
      title: 'Review Trip Rates',
      maxWidth: 1100,
      flexibleBody: true,
      bodyHandlesScrolling: true,
      actions: [
        TextButton(
          onPressed: () => Clipboard.setData(
            ClipboardData(
              text: rows
                  .map((r) => '${r[0]}\nPending: ${r[1]}\nServer: ${r[2]}')
                  .join('\n\n'),
            ),
          ),
          child: const Text('Copy'),
        ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Back'),
        ),
        TextButton(
          onPressed: _saving
              ? null
              : () async {
                  setState(() {
                    _saving = true;
                    _error = null;
                  });
                  try {
                    await widget.onApply();
                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                  } catch (error) {
                    if (mounted) {
                      setState(() {
                        _error = error.toString();
                        _saving = false;
                      });
                    }
                  }
                },
          child: Text(_saving ? 'Applying…' : 'Apply pending changes'),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SelectableText(
              'Review the differences below. Applying uses the pending settings and retains existing matrix history. A newer server change will stop the sync.',
            ),
            if (_error != null) SelectableText(_error!),
            const SizedBox(height: 12),
            Expanded(
              child: AdminModalRecordList(
                titles: const ['Field', 'Pending', 'Server'],
                itemCount: rows.length,
                valuesAt: (i) => rows[i],
                selectableCells: true,
                wrappingColumn: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
