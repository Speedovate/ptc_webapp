import 'package:webapp/widgets/shared/booking_record_card.dart';
import 'package:webapp/utils/location_display.dart';
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
    this.emptyLabel,
  });
  final String? emptyLabel;
  final ChassisActionHistory history;
  final ValueListenable<DateTime> clock;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<DateTime>(
    valueListenable: clock,
    builder: (context, now, child) {
      final label = history.elapsedLabel(now) ?? emptyLabel;
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
    this.currentStatus,
    this.currentStatusAt,
  });
  final Map<String, UserModel> usersById;
  final String name;
  final String? currentStatus;
  final DateTime? currentStatusAt;

  bool get _showCurrentRow {
    final status = currentStatus?.trim().toLowerCase();
    if (status == null || status.isEmpty) return false;
    final latest = history.events
        .where((event) => event.chassisStatus != null)
        .firstOrNull;
    return latest?.chassisStatus?.trim().toLowerCase() != status;
  }

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
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: AdminModalShell(
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
          const TabBar(
            tabs: [
              Tab(text: 'Actions'),
              Tab(text: 'Booking assignments'),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TabBarView(
              children: [
                history.events.isEmpty && !_showCurrentRow
                    ? const Center(
                        child: Text('No recorded actions available.'),
                      )
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
                          itemCount:
                              history.events.length + (_showCurrentRow ? 1 : 0),
                          columnStyles: const {
                            0: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          },
                          columnExtraWidths: const {0: 26},
                          cellBuilder: (row, column) => column == 0
                              ? ChassisStatusPill(
                                  status: _showCurrentRow && row == 0
                                      ? currentStatus!
                                      : history
                                                .events[row -
                                                    (_showCurrentRow ? 1 : 0)]
                                                .chassisStatus ??
                                            '',
                                )
                              : null,
                          valuesAt: (index) {
                            if (_showCurrentRow && index == 0) {
                              return [
                                chassisStatusLabel(currentStatus!),
                                '—',
                                currentStatusAt == null
                                    ? 'Not recorded'
                                    : AdminUsersView.formatCreatedAt(
                                        currentStatusAt!.toLocal(),
                                      ),
                                history.currentLocation?.trim().isNotEmpty ==
                                        true
                                    ? locationDisplayLabel(
                                        history.currentLocation!,
                                      )
                                    : '—',
                                'Current status',
                              ];
                            }
                            final event = history
                                .events[index - (_showCurrentRow ? 1 : 0)];
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
                              AdminUsersView.formatCreatedAt(
                                event.at.toLocal(),
                              ),
                              history.locationLabel(event),
                              details.isEmpty ? '—' : details.join('\n'),
                            ];
                          },
                        ),
                      ),
                _assignmentList(),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _assignmentList() {
    final bookings = history.assignments.toList();
    final pickups = {
      for (final booking in bookings)
        booking: BookingRecordCard.pickupDateTime(booking.statusOutputs),
    };
    bookings.sort((a, b) {
      final left = pickups[a];
      final right = pickups[b];
      if (left == null && right != null) return 1;
      if (left != null && right == null) return -1;
      final order = left == null ? 0 : left.compareTo(right!);
      return order != 0 ? order : (a.id ?? '').compareTo(b.id ?? '');
    });
    if (bookings.isEmpty) {
      return const Center(child: Text('No booking assignments available.'));
    }
    String crewLabel(UserModel? user, String role) {
      if (user == null) return '—';
      final id = user.id?.trim();
      if (id == null || id.isEmpty) return user.name ?? '—';
      if (usersById.containsKey(id)) return _userLabel(id, recordedRole: role);
      return '${humanizeDropdownValue(role)} $id | ${user.name ?? '—'}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: AdminModalRecordList(
        titles: const [
          'Booking',
          'Status',
          'Assignment',
          'Pickup schedule',
          'Driver',
          'Helper',
        ],
        itemCount: bookings.length,
        valuesAt: (index) {
          final booking = bookings[index];
          final pickup = pickups[booking];
          final status = booking.clientStatus?.trim();
          return [
            'Booking ${booking.id ?? '—'}',
            status == null || status.isEmpty
                ? '—'
                : humanizeDropdownValue(status),
            history.assignmentLabel(booking),
            pickup == null
                ? 'Not recorded'
                : AdminUsersView.formatCreatedAt(pickup.toLocal()),
            crewLabel(booking.driver, 'driver'),
            crewLabel(booking.helper, 'helper'),
          ];
        },
      ),
    );
  }
}
