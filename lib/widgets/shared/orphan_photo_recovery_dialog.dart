import 'package:flutter/material.dart';
import 'package:webapp/services/orphan_photo_recovery_service.dart';
import 'app_selectable_text.dart';
import 'app_text_input_focus_policy.dart';

class OrphanPhotoRecoveryDialog extends StatefulWidget {
  const OrphanPhotoRecoveryDialog({
    super.key,
    required this.service,
    required this.owner,
    required this.entryId,
  });
  final OrphanPhotoRecoveryService service;
  final String owner, entryId;
  @override
  State<OrphanPhotoRecoveryDialog> createState() =>
      _OrphanPhotoRecoveryDialogState();
}

class _OrphanPhotoRecoveryDialogState extends State<OrphanPhotoRecoveryDialog> {
  final _booking = TextEditingController();
  OrphanPhotoReview? _review;
  String? _error;
  bool _busy = false, _confirmed = false;
  late final Future<OrphanPhotoSource> _source;

  @override
  void initState() {
    super.initState();
    _source = widget.service.readSource(
      owner: widget.owner,
      entryId: widget.entryId,
    );
  }

  @override
  void dispose() {
    _booking.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = _booking.text.trim();
    setState(() {
      _busy = true;
      _error = null;
      _review = null;
      _confirmed = false;
    });
    try {
      final review = await widget.service.review(
        owner: widget.owner,
        entryId: widget.entryId,
        bookingId: id,
      );
      if (mounted && _booking.text.trim() == id) {
        setState(() => _review = review);
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    final review = _review;
    if (review == null || !_confirmed) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.apply(review);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _confirmed = false;
          _review = null;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AppTextInputFocusPolicy(
      child: AlertDialog(
        title: const Text('Recover saved photo'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSelectableText(
                  'Select the existing booking this photo belongs to. If the original offline booking is missing, create and save its replacement first. Review the photo and booking before attaching it; the original photo, timestamp, and error details remain archived.',
                ),
                const SizedBox(height: 16),
                FutureBuilder<OrphanPhotoSource>(
                  future: _source,
                  builder: (context, snapshot) {
                    final source = snapshot.data;
                    if (source == null) {
                      return snapshot.hasError
                          ? AppSelectableText('${snapshot.error}')
                          : const LinearProgressIndicator();
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Image.memory(
                          _review?.preview ?? source.preview,
                          height: 200,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const Text(
                            'Preview unavailable. Original photo remains saved.',
                          ),
                        ),
                        AppSelectableText(
                          '${_review?.fileName ?? source.fileName}\nOriginally saved: ${_review?.originalActionAt ?? source.originalActionAt}',
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _booking,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Booking number',
                  ),
                  onChanged: (_) => setState(() {
                    _review = null;
                    _confirmed = false;
                  }),
                ),
                if (_review case final review?) ...[
                  const SizedBox(height: 16),
                  AppSelectableText(
                    'Destination: Booking ${review.bookingId}\nClient ${review.clientId} · ${review.bookingStatus}\n${review.bookingDescription}',
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'I checked the photo and selected the correct booking.',
                    ),
                    value: _confirmed,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _confirmed = value == true),
                  ),
                ],
                if (_error != null) AppSelectableText(_error!),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          if (_review == null)
            FilledButton(
              onPressed: _busy ? null : _load,
              child: const Text('Review photo and booking'),
            )
          else
            FilledButton(
              onPressed: _busy || !_confirmed ? null : _apply,
              child: const Text('Recover to booking history'),
            ),
        ],
      ),
    ),
  );
}
