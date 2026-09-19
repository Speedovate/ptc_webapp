import 'package:webapp/utils/functions.dart';
import 'package:webapp/views/admin/admin_users.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/chassis_action_history.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/widgets/shared/chassis_status_presentation.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';
import 'package:webapp/widgets/shared/admin_modal_record_list.dart';

class ChassisElapsedText extends StatelessWidget {
  const ChassisElapsedText({
    super.key,
    required this.history,
    required this.clock,
  });
  final ChassisActionHistory history;
  final ValueListenable<DateTime> clock;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<DateTime>(
    valueListenable: clock,
    builder: (context, now, child) {
      final label = history.elapsedLabel(now);
      if (label == null) return const SizedBox.shrink();
      return Text(
        label,
        maxLines: 1,
        style: const TextStyle(
          color: AppColors.primaryColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      );
    },
  );
}

class ChassisActionHistoryDialog extends StatelessWidget {
  const ChassisActionHistoryDialog({
    super.key,
    required this.name,
    required this.history,
    required this.clock,
    this.usersById = const {},
  });
  final Map<String, UserModel> usersById;
  final String name;
  final ChassisActionHistory history;
  final ValueListenable<DateTime> clock;
  String _userLabel(String id, {String? recordedRole}) {
    final user = usersById[id];
    final role =
        (recordedRole?.trim().isNotEmpty == true ? recordedRole : user?.role)
            ?.trim();
    final roleLabel = role == null || role.isEmpty
        ? 'User'
        : role
              .split('_')
              .map(
                (part) => part.isEmpty
                    ? part
                    : '${part[0].toUpperCase()}${part.substring(1)}',
              )
              .join(' ');
    final name = user?.name?.trim();
    return '$roleLabel $id | ${name == null || name.isEmpty ? '—' : name}';
  }

  @override
  Widget build(BuildContext context) => AdminModalShell(
    selectable: true,
    title: 'Chassis $name History',
    maxWidth: 960,
    bodyHandlesScrolling: true,
    flexibleBody: true,
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ChassisElapsedText(history: history, clock: clock),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: history.events.isEmpty
              ? const Center(child: Text('No recorded actions available.'))
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: AdminModalRecordList(
                    titles: const [
                      'Status',
                      'Booking',
                      'DateTime',
                      'Location',
                      'Details',
                    ],
                    itemCount: history.events.length,
                    columnStyles: const {
                      0: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    },
                    columnExtraWidths: const {0: 26},
                    cellBuilder: (row, column) => column == 0
                        ? ChassisStatusPill(
                            status: history.events[row].chassisStatus ?? '',
                          )
                        : null,
                    valuesAt: (index) {
                      final event = history.events[index];
                      final stage = chassisStatusLabel(
                        event.chassisStatus ?? '',
                      );
                      final details = <String>[
                        history.claimLabel(event) ??
                            humanizeDropdownValue(event.stage),
                        if (event.actor != null)
                          _userLabel(
                            event.actor!,
                            recordedRole: event.actorRole,
                          ),
                        if (event.driverId != null)
                          'Return: ${_userLabel(event.driverId!, recordedRole: 'driver')}',
                      ];
                      return [
                        stage,
                        'Booking ${event.bookingId}',
                        AdminUsersView.formatCreatedAt(event.at.toLocal()),
                        history.locationLabel(event),
                        details.isEmpty ? '—' : details.join('\n'),
                      ];
                    },
                  ),
                ),
        ),
      ],
    ),
  );
}
