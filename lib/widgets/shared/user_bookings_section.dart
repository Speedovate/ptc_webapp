import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/status.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/booking.request.dart';
import 'package:webapp/requests/status.request.dart';
import 'package:webapp/repositories/interfaces/booking_repository.dart';
import 'package:webapp/repositories/interfaces/status_form_repository.dart';
import 'package:webapp/utils/functions.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/app_refresh_strip.dart';
import 'package:webapp/widgets/shared/booking_record_card.dart';

class UserBookingsSection extends StatefulWidget {
  const UserBookingsSection({
    super.key,
    required this.user,
    this.padding = EdgeInsets.zero,
    this.onViewBooking,
    this.onEditBooking,
    this.onNewBooking,
    this.useAdminListStyle = false,
    this.forceWideLayout = false,
  });

  final UserModel user;
  final EdgeInsets padding;
  final Future<void> Function(Booking booking)? onViewBooking;
  final Future<void> Function(Booking booking)? onEditBooking;
  final Future<void> Function()? onNewBooking;
  final bool useAdminListStyle;
  final bool forceWideLayout;

  @override
  State<UserBookingsSection> createState() => _UserBookingsSectionState();
}

class _UserBookingsSectionState extends State<UserBookingsSection> {
  static final Map<String, _UserBookingsCacheState> _cacheByUserKey = {};
  final BookingRepository _bookingRepository = BookingRequest.instance;
  final StatusFormRepository _statusRepository = StatusRequest.instance;

  StreamSubscription<List<Booking>>? _bookingsSubscription;
  final Map<String, Status> _statusesByKey = {};
  List<Booking> _bookings = const [];
  bool _isLoading = false;
  String? _errorMessage;
  String _searchQuery = '';
  String _statusFilter = 'All';
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    final cachedState = _cacheByUserKey[_cacheKey];
    if (cachedState != null) {
      _bookings = List<Booking>.from(cachedState.bookings);
      _statusesByKey
        ..clear()
        ..addAll(cachedState.statusesByKey);
      _errorMessage = cachedState.errorMessage;
      _isLoading = false;
    }
    _load();
  }

  @override
  void didUpdateWidget(covariant UserBookingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.id != widget.user.id ||
        oldWidget.user.role != widget.user.role ||
        oldWidget.user.parentClientId != widget.user.parentClientId) {
      _load();
    }
  }

  @override
  void dispose() {
    _bookingsSubscription?.cancel();
    super.dispose();
  }

  String get _cacheKey => [
    normalizeRoleKey(widget.user.role),
    normalizeId(widget.user.id) ?? 'no-user',
    normalizeId(widget.user.parentClientId) ?? 'no-parent',
  ].join('|');

  Future<void> _load() async {
    await _bookingsSubscription?.cancel();
    if (mounted) {
      setState(() {
        _isLoading = false;
        _errorMessage = null;
      });
    }
    try {
      await _bookingRepository.initialize();
      final statuses = await _statusRepository.getStatuses().timeout(
        const Duration(seconds: 6),
        onTimeout: () => const <Status>[],
      );
      _statusesByKey
        ..clear()
        ..addEntries(
          statuses
              .where((item) => (item.key ?? '').trim().isNotEmpty)
              .map((item) => MapEntry(item.key!.trim(), item)),
        );
      _applyBookings(
        await _bookingRepository.getBookings().timeout(
          const Duration(seconds: 6),
          onTimeout: () => const <Booking>[],
        ),
      );
      _bookingsSubscription = _bookingRepository.watchBookings().listen((
        items,
      ) {
        _applyBookings(items);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = userFacingErrorMessage(
          error,
          fallback: 'We could not load the bookings right now.',
        );
      });
    } finally {
      _cacheCurrentState();
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _applyBookings(List<Booking> allBookings) {
    final filtered = allBookings.where(_matchesUser).toList();
    filtered.sort((a, b) {
      final aId = int.tryParse(a.id ?? '');
      final bId = int.tryParse(b.id ?? '');
      if (aId != null && bId != null) {
        return bId.compareTo(aId);
      }
      if (aId != null) {
        return -1;
      }
      if (bId != null) {
        return 1;
      }
      final aDate = a.updatedAt ?? a.createdAt;
      final bDate = b.updatedAt ?? b.createdAt;
      if (aDate == null && bDate == null) {
        return (b.id ?? '').compareTo(a.id ?? '');
      }
      if (aDate == null) {
        return 1;
      }
      if (bDate == null) {
        return -1;
      }
      return bDate.compareTo(aDate);
    });
    if (!mounted) {
      return;
    }
    setState(() {
      _bookings = filtered;
    });
    _cacheCurrentState();
  }

  void _cacheCurrentState() {
    _cacheByUserKey[_cacheKey] = _UserBookingsCacheState(
      bookings: List<Booking>.from(_bookings),
      statusesByKey: Map<String, Status>.from(_statusesByKey),
      errorMessage: _errorMessage,
    );
  }

  bool _matchesUser(Booking booking) {
    final userId = normalizeId(widget.user.id);
    if (userId == null) {
      return false;
    }

    return switch (normalizeRoleKey(widget.user.role)) {
      'client' => normalizeId(booking.client?.id) == userId,
      'driver' => normalizeId(booking.driver?.id) == userId,
      'helper' => normalizeId(booking.helper?.id) == userId,
      'admin' => _bookingHasSubmittedBy(booking, userId),
      _ => false,
    };
  }

  bool _bookingHasSubmittedBy(Booking booking, String userId) {
    final outputs = booking.statusOutputs;
    if (outputs == null || outputs.isEmpty) {
      return false;
    }
    for (final value in outputs.values) {
      if (value is! Map) {
        continue;
      }
      final section = Map<String, dynamic>.from(value);
      final submittedBy = normalizeId(section['submitted_by']?.toString());
      if (submittedBy == userId) {
        return true;
      }
    }
    return false;
  }

  String _statusLabelForKey(String? statusKey) {
    final key = statusKey?.trim();
    if (key == null || key.isEmpty) {
      return '-';
    }
    final label = _statusesByKey[key]?.label?.trim();
    if (label != null && label.isNotEmpty) {
      return label;
    }
    return humanizeDropdownValue(key);
  }

  String _headlineStatusLabel(Booking booking) {
    if ((booking.localSyncStatus ?? '').trim().toLowerCase() == 'queued') {
      return 'Queued';
    }
    final role = normalizeRoleKey(widget.user.role);
    final statusKey = switch (role) {
      'driver' => booking.driverStatus ?? booking.clientStatus,
      'helper' => booking.helperStatus ?? booking.clientStatus,
      _ => booking.clientStatus,
    };
    return _statusLabelForKey(statusKey);
  }

  List<String> get _statusOptions {
    final labels =
        _bookings
            .map(_headlineStatusLabel)
            .where((label) => label.trim().isNotEmpty && label.trim() != '-')
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return ['All', ...labels];
  }

  List<Booking> get _filteredBookings {
    final query = _searchQuery.trim().toLowerCase();
    return _bookings.where((booking) {
      final statusLabel = _headlineStatusLabel(booking);
      final matchesQuery =
          query.isEmpty ||
          [
            booking.id,
            _formatBookingDateTime(booking.createdAt),
            _waybillNumber(booking),
            _vanNumber(booking),
            _vanSize(booking),
            _amount(booking),
            statusLabel,
            _userName(booking.client),
            _userName(booking.driver),
            _userName(booking.helper),
          ].whereType<String>().any(
            (value) => value.toLowerCase().contains(query),
          );

      final matchesStatus =
          _statusFilter == 'All' || statusLabel == _statusFilter;

      final createdAt = booking.createdAt;
      final matchesStartDate =
          _startDate == null ||
          (createdAt != null &&
              !_dateOnly(createdAt).isBefore(_dateOnly(_startDate!)));
      final matchesEndDate =
          _endDate == null ||
          (createdAt != null &&
              !_dateOnly(createdAt).isAfter(_dateOnly(_endDate!)));

      return matchesQuery &&
          matchesStatus &&
          matchesStartDate &&
          matchesEndDate;
    }).toList();
  }

  int get _activeFilterCount => [
    _statusFilter != 'All',
    _startDate != null,
    _endDate != null,
  ].where((isActive) => isActive).length;

  String _formatDate(DateTime? value) {
    if (value == null) {
      return 'All';
    }
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$month/$day/${value.year}';
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  String _buildEmptyMessage() {
    if (_bookings.isEmpty) {
      return 'No bookings yet.';
    }
    if (_searchQuery.trim().isNotEmpty || _activeFilterCount > 0) {
      if (_searchQuery.trim().isNotEmpty && _activeFilterCount > 0) {
        return 'No bookings matched your current search and filters.';
      }
      if (_searchQuery.trim().isNotEmpty) {
        return 'No bookings matched your current search.';
      }
      return 'No bookings matched your current filters.';
    }
    return 'No bookings yet.';
  }

  String _userName(UserModel? user) {
    final name = user?.name?.trim();
    return (name?.isNotEmpty ?? false) ? name! : '-';
  }

  String _userPhone(UserModel? user) {
    final phone = user?.phone?.trim();
    return (phone?.isNotEmpty ?? false) ? phone! : '-';
  }

  String _waybillNumber(Booking booking) =>
      BookingRecordCard.outputFieldDisplayValue(
        booking.statusOutputs,
        'waybill_number',
      );

  String _vanNumber(Booking booking) =>
      BookingRecordCard.outputFieldDisplayValue(
        booking.statusOutputs,
        'van_number',
      );

  String _vanSize(Booking booking) => BookingRecordCard.outputFieldDisplayValue(
    booking.statusOutputs,
    'van_size',
  );

  String _amount(Booking booking) => BookingRecordCard.outputFieldDisplayValue(
    booking.statusOutputs,
    'amount',
  );

  String _formatBookingDateTime(DateTime? value) {
    if (value == null) {
      return '-';
    }
    final monthNames = const [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = monthNames[value.month - 1];
    final hour = value.hour == 0
        ? 12
        : (value.hour > 12 ? value.hour - 12 : value.hour);
    final minute = value.minute.toString().padLeft(2, '0');
    final period = value.hour >= 12 ? 'PM' : 'AM';
    return '$month ${value.day}, ${value.year} | $hour:$minute $period';
  }

  Widget _buildAdminWideTable(
    List<Booking> bookings, {
    required bool allowHorizontalScroll,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const headerStyle = TextStyle(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w700,
        );
        const valueStyle = TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        );
        const defaultTrailingPadding =
            AdminListMeasurements.defaultTrailingPadding;
        const extraWidthAllowance =
            AdminListMeasurements.defaultExtraWidthAllowance;
        final textScaler = MediaQuery.textScalerOf(context);

        String longestText(Iterable<String> values) {
          var longest = '-';
          for (final value in values) {
            if (value.length > longest.length) {
              longest = value;
            }
          }
          return longest;
        }

        double resolvedColumnWidth(double measuredWidth) {
          return AdminListMeasurements.resolvedColumnWidth(
            measuredWidth,
            trailingPadding: defaultTrailingPadding,
            extraWidthAllowance: extraWidthAllowance,
          );
        }

        double maxTextWidth(String label, String value) {
          return AdminListMeasurements.maxTextWidth(
            context,
            textScaler,
            label,
            headerStyle,
            value,
            valueStyle,
          );
        }

        double maxValue(double first, double second) =>
            first > second ? first : second;

        final idWidth = maxTextWidth(
          'ID',
          longestText(bookings.map((booking) => booking.id ?? '-')),
        );
        final createdWidth = maxTextWidth(
          'Created',
          longestText(
            bookings.map(
              (booking) => _formatBookingDateTime(booking.createdAt),
            ),
          ),
        );
        final updatedWidth = maxTextWidth(
          'Updated',
          longestText(
            bookings.map(
              (booking) => _formatBookingDateTime(booking.updatedAt),
            ),
          ),
        );
        final waybillWidth = maxTextWidth(
          'Waybill Number',
          longestText(bookings.map(_waybillNumber)),
        );
        final vanNumberWidth = maxTextWidth(
          'Van Number',
          longestText(bookings.map(_vanNumber)),
        );
        final vanSizeWidth = maxTextWidth(
          'Van Size',
          longestText(bookings.map(_vanSize)),
        );
        final amountWidth = maxTextWidth(
          'Amount',
          longestText(bookings.map(_amount)),
        );
        final statusWidth = maxValue(
          AdminListMeasurements.measureTextWidth(
                context,
                textScaler,
                longestText(bookings.map(_headlineStatusLabel)),
                valueStyle,
              ) +
              32,
          AdminListMeasurements.measureTextWidth(
            context,
            textScaler,
            'Status',
            headerStyle,
          ),
        );
        final actionsWidth = maxValue(
          88,
          AdminListMeasurements.measureTextWidth(
            context,
            textScaler,
            'Actions',
            headerStyle,
          ),
        );

        final resolvedIdWidth = resolvedColumnWidth(idWidth);
        final resolvedCreatedWidth = resolvedColumnWidth(createdWidth);
        final resolvedUpdatedWidth = resolvedColumnWidth(updatedWidth);
        final resolvedWaybillWidth = resolvedColumnWidth(waybillWidth);
        final resolvedVanNumberWidth = resolvedColumnWidth(vanNumberWidth);
        final resolvedVanSizeWidth = resolvedColumnWidth(vanSizeWidth);
        final resolvedAmountWidth = resolvedColumnWidth(amountWidth);
        final resolvedStatusWidth = resolvedColumnWidth(statusWidth);
        final resolvedActionsWidth = actionsWidth + extraWidthAllowance;
        final totalMeasuredWidth =
            resolvedIdWidth +
            resolvedWaybillWidth +
            resolvedVanNumberWidth +
            resolvedVanSizeWidth +
            resolvedAmountWidth +
            resolvedStatusWidth +
            resolvedCreatedWidth +
            resolvedUpdatedWidth +
            resolvedActionsWidth +
            40;
        final useResponsiveCards =
            !allowHorizontalScroll && totalMeasuredWidth > constraints.maxWidth;

        Widget fixedSlot(double width, Widget child) =>
            AdminListFixedSlot(width: width, child: child);

        Widget headerCell(
          String label, {
          double trailingPadding = AdminListMeasurements.defaultTrailingPadding,
          Alignment alignment = Alignment.centerLeft,
          TextAlign textAlign = TextAlign.left,
        }) {
          return AdminListHeaderCell(
            label: label,
            trailingPadding: trailingPadding,
            alignment: alignment,
            textAlign: textAlign,
          );
        }

        Widget bodyCell(
          Widget child, {
          double trailingPadding = AdminListMeasurements.defaultTrailingPadding,
          Alignment alignment = Alignment.centerLeft,
        }) {
          return AdminListBodyCell(
            trailingPadding: trailingPadding,
            alignment: alignment,
            child: child,
          );
        }

        final table = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminListHeaderBar(
              minHeight: 52,
              borderRadius: 16,
              child: Row(
                children: [
                  fixedSlot(resolvedIdWidth, headerCell('ID')),
                  fixedSlot(resolvedWaybillWidth, headerCell('Waybill Number')),
                  fixedSlot(resolvedVanNumberWidth, headerCell('Van Number')),
                  fixedSlot(resolvedVanSizeWidth, headerCell('Van Size')),
                  fixedSlot(resolvedAmountWidth, headerCell('Amount')),
                  fixedSlot(resolvedStatusWidth, headerCell('Status')),
                  fixedSlot(resolvedCreatedWidth, headerCell('Created')),
                  fixedSlot(resolvedUpdatedWidth, headerCell('Updated')),
                  AdminListTrailingActionsLane(
                    width: resolvedActionsWidth,
                    child: headerCell(
                      'Actions',
                      trailingPadding: 0,
                      alignment: Alignment.centerRight,
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ...bookings.asMap().entries.map((entry) {
              final booking = entry.value;
              return Padding(
                padding: EdgeInsets.only(
                  bottom: entry.key == bookings.length - 1 ? 0 : 12,
                ),
                child: AdminListItemCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 18,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      fixedSlot(
                        resolvedIdWidth,
                        bodyCell(
                          Text(
                            booking.id ?? '-',
                            style: valueStyle,
                            softWrap: true,
                          ),
                        ),
                      ),
                      fixedSlot(
                        resolvedWaybillWidth,
                        bodyCell(
                          Text(
                            _waybillNumber(booking),
                            style: valueStyle,
                            softWrap: true,
                          ),
                        ),
                      ),
                      fixedSlot(
                        resolvedVanNumberWidth,
                        bodyCell(
                          Text(
                            _vanNumber(booking),
                            style: valueStyle,
                            softWrap: true,
                          ),
                        ),
                      ),
                      fixedSlot(
                        resolvedVanSizeWidth,
                        bodyCell(
                          Text(
                            _vanSize(booking),
                            style: valueStyle,
                            softWrap: true,
                          ),
                        ),
                      ),
                      fixedSlot(
                        resolvedAmountWidth,
                        bodyCell(
                          Text(
                            _amount(booking),
                            style: valueStyle,
                            softWrap: true,
                          ),
                        ),
                      ),
                      fixedSlot(
                        resolvedStatusWidth,
                        bodyCell(adminMetaPill(_headlineStatusLabel(booking))),
                      ),
                      fixedSlot(
                        resolvedCreatedWidth,
                        bodyCell(
                          Text(
                            _formatBookingDateTime(booking.createdAt),
                            style: valueStyle,
                            softWrap: true,
                          ),
                        ),
                      ),
                      fixedSlot(
                        resolvedUpdatedWidth,
                        bodyCell(
                          Text(
                            _formatBookingDateTime(booking.updatedAt),
                            style: valueStyle,
                            softWrap: true,
                          ),
                        ),
                      ),
                      AdminListTrailingActionsLane(
                        width: resolvedActionsWidth,
                        child: bodyCell(
                          Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (widget.onViewBooking != null)
                                AdminListActionButton(
                                  icon: Icons.visibility_rounded,
                                  backgroundColor: Colors.yellow.shade900,
                                  onTap: () {
                                    widget.onViewBooking!.call(booking);
                                  },
                                ),
                              if (widget.onEditBooking != null)
                                AdminListActionButton(
                                  icon: Icons.edit_outlined,
                                  onTap: () {
                                    widget.onEditBooking!.call(booking);
                                  },
                                ),
                            ],
                          ),
                          trailingPadding: 0,
                          alignment: Alignment.centerRight,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );

        if (useResponsiveCards) {
          return Column(
            children: [
              for (var index = 0; index < bookings.length; index++) ...[
                _buildAdminResponsiveCard(bookings[index]),
                if (index != bookings.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }

        if (allowHorizontalScroll &&
            totalMeasuredWidth > constraints.maxWidth) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: totalMeasuredWidth, child: table),
          );
        }

        return table;
      },
    );
  }

  Widget _buildAdminResponsiveCard(Booking booking) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 2 : 1;
        final spacing = 12.0;
        final itemWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;
        final items = [
          ('ID', booking.id ?? '-'),
          ('Waybill Number', _waybillNumber(booking)),
          ('Van Number', _vanNumber(booking)),
          ('Van Size', _vanSize(booking)),
          ('Amount', _amount(booking)),
          ('Status', _headlineStatusLabel(booking)),
          ('Created', _formatBookingDateTime(booking.createdAt)),
          ('Updated', _formatBookingDateTime(booking.updatedAt)),
        ];

        return AdminListItemCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  adminMetaPill(_headlineStatusLabel(booking)),
                  const Spacer(),
                  if (widget.onViewBooking != null)
                    AdminListActionButton(
                      icon: Icons.visibility_rounded,
                      backgroundColor: Colors.yellow.shade900,
                      onTap: () {
                        widget.onViewBooking!.call(booking);
                      },
                    ),
                  if (widget.onViewBooking != null &&
                      widget.onEditBooking != null)
                    const SizedBox(width: 8),
                  if (widget.onEditBooking != null)
                    AdminListActionButton(
                      icon: Icons.edit_outlined,
                      onTap: () {
                        widget.onEditBooking!.call(booking);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: spacing,
                runSpacing: 10,
                children: items
                    .map(
                      (item) => AdminListResponsiveField(
                        title: item.$1,
                        value: item.$2,
                        width: itemWidth,
                        centered: false,
                        isTitle: false,
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredBookings = _filteredBookings;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AdminSectionTitle(title: 'Bookings'),
        const SizedBox(height: 10),
        AppRefreshStrip(isVisible: _isLoading),
        if (widget.useAdminListStyle) ...[
          _UserBookingsToolbar(
            searchQuery: _searchQuery,
            statusOptions: _statusOptions,
            statusFilter: _statusFilter,
            startDate: _startDate,
            endDate: _endDate,
            dateFormatter: _formatDate,
            onSearchChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
            onStatusChanged: (value) {
              setState(() {
                _statusFilter = value ?? 'All';
              });
            },
            onStartDateChanged: (value) {
              setState(() {
                _startDate = value;
                if (_startDate != null &&
                    _endDate != null &&
                    _endDate!.isBefore(_startDate!)) {
                  _endDate = _startDate;
                }
              });
            },
            onEndDateChanged: (value) {
              setState(() {
                _endDate = value;
                if (_startDate != null &&
                    _endDate != null &&
                    _startDate!.isAfter(_endDate!)) {
                  _startDate = _endDate;
                }
              });
            },
            onClearFilters: () {
              setState(() {
                _statusFilter = 'All';
                _startDate = null;
                _endDate = null;
              });
            },
            onNewPressed: widget.onNewBooking == null
                ? null
                : () {
                    widget.onNewBooking!.call();
                  },
          ),
          const SizedBox(height: 18),
        ],
        if (_errorMessage != null)
          AdminListItemCard(
            padding: const EdgeInsets.all(24),
            child: AdminListStateText(message: _errorMessage!),
          )
        else if (filteredBookings.isEmpty)
          AdminListItemCard(
            padding: const EdgeInsets.all(24),
            child: AdminListStateText(message: _buildEmptyMessage()),
          )
        else if (widget.useAdminListStyle)
          _buildAdminWideTable(
            filteredBookings,
            allowHorizontalScroll: widget.forceWideLayout,
          )
        else
          Column(
            children: [
              for (var index = 0; index < filteredBookings.length; index++) ...[
                BookingRecordCard(
                  booking: filteredBookings[index],
                  onTap: widget.onViewBooking == null
                      ? null
                      : () {
                          widget.onViewBooking!.call(filteredBookings[index]);
                        },
                  headlineStatusLabel: _headlineStatusLabel(
                    filteredBookings[index],
                  ),
                  statusLabelForKey: _statusLabelForKey,
                  showStatusSubmissions: false,
                  clientName: _userName(filteredBookings[index].client),
                  clientPhone: _userPhone(filteredBookings[index].client),
                  driverName: _userName(filteredBookings[index].driver),
                  driverPhone: _userPhone(filteredBookings[index].driver),
                  helperName: _userName(filteredBookings[index].helper),
                  helperPhone: _userPhone(filteredBookings[index].helper),
                  trailingActions:
                      widget.onViewBooking != null ||
                          widget.onEditBooking != null
                      ? BookingRecordCardActions(
                          onViewTap: widget.onViewBooking == null
                              ? null
                              : () {
                                  widget.onViewBooking!.call(
                                    filteredBookings[index],
                                  );
                                },
                          onEditTap: widget.onEditBooking == null
                              ? null
                              : () {
                                  widget.onEditBooking!.call(
                                    filteredBookings[index],
                                  );
                                },
                        )
                      : null,
                ),
                if (index != filteredBookings.length - 1)
                  const SizedBox(height: 12),
              ],
            ],
          ),
      ],
    );

    if (widget.padding == EdgeInsets.zero) {
      return content;
    }
    return Padding(padding: widget.padding, child: content);
  }
}

class _UserBookingsCacheState {
  const _UserBookingsCacheState({
    required this.bookings,
    required this.statusesByKey,
    required this.errorMessage,
  });

  final List<Booking> bookings;
  final Map<String, Status> statusesByKey;
  final String? errorMessage;
}

class _UserBookingsToolbar extends StatelessWidget {
  const _UserBookingsToolbar({
    required this.searchQuery,
    required this.statusOptions,
    required this.statusFilter,
    required this.startDate,
    required this.endDate,
    required this.dateFormatter,
    required this.onSearchChanged,
    required this.onStatusChanged,
    required this.onStartDateChanged,
    required this.onEndDateChanged,
    required this.onClearFilters,
    required this.onNewPressed,
  });

  final String searchQuery;
  final List<String> statusOptions;
  final String statusFilter;
  final DateTime? startDate;
  final DateTime? endDate;
  final String Function(DateTime?) dateFormatter;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<DateTime?> onStartDateChanged;
  final ValueChanged<DateTime?> onEndDateChanged;
  final VoidCallback onClearFilters;
  final VoidCallback? onNewPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: AdminListToolbar(
        controlHeight: adminFilterFieldMinHeight,
        surfaceRadius: 16,
        search: AdminListSearchField(
          controlHeight: adminFilterFieldMinHeight,
          surfaceRadius: 16,
          initialValue: searchQuery,
          onChanged: onSearchChanged,
        ),
        filtersBuilder: (context, iconOnly) => AdminListDynamicFiltersPanel(
          iconOnly: iconOnly,
          filters: [
            AdminListDropdownFilterConfig(
              label: 'Status',
              value: statusFilter,
              items: statusOptions,
              onChanged: (value) => onStatusChanged(value),
            ),
            AdminListDateFilterConfig(
              label: 'Start',
              value: startDate,
              onSelected: onStartDateChanged,
              formatter: dateFormatter,
            ),
            AdminListDateFilterConfig(
              label: 'End',
              value: endDate,
              onSelected: onEndDateChanged,
              formatter: dateFormatter,
            ),
          ],
          onClear: onClearFilters,
        ),
        onNewPressed: onNewPressed,
      ),
    );
  }
}
