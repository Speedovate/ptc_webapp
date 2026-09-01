import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/support_message.dart';
import 'package:webapp/models/support_thread.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/requests/booking.request.dart';
import 'package:webapp/requests/support.request.dart';
import 'package:webapp/services/app_warmup_service.dart';
import 'package:webapp/services/network_status_events.dart';
import 'package:webapp/services/offline_media_sync_service.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:webapp/utils/functions.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/app_cached_network_image.dart';
import 'package:webapp/widgets/shared/app_image_viewer.dart';
import 'package:webapp/widgets/shared/app_mouse_pressable.dart';
import 'package:webapp/widgets/shared/app_page_loading_overlay.dart';
import 'package:webapp/widgets/shared/app_profile_avatar.dart';
import 'package:webapp/widgets/shared/app_snackbar.dart';
import 'package:webapp/widgets/shared/support_section_navigation_scope.dart';

class SupportCenterView extends StatefulWidget {
  const SupportCenterView({
    super.key,
    required this.user,
    this.embedded = false,
    this.initialTopicKey,
    this.initialBookingId,
    this.initialUserId,
  });

  final UserModel user;
  final bool embedded;
  final String? initialTopicKey;
  final String? initialBookingId;
  final String? initialUserId;

  @override
  State<SupportCenterView> createState() => _SupportCenterViewState();
}

Future<void> openSupportCenter(
  BuildContext context, {
  required UserModel user,
  String? initialTopicKey,
  String? initialBookingId,
  String? initialUserId,
}) async {
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SupportCenterView(
        user: user,
        initialTopicKey: initialTopicKey,
        initialBookingId: initialBookingId,
        initialUserId: initialUserId,
      ),
    ),
  );
}

Future<void> openSupportDestination(
  BuildContext context, {
  required UserModel user,
  String? initialTopicKey,
  String? initialBookingId,
  String? initialUserId,
}) async {
  final embeddedNavigator = SupportSectionNavigationScope.maybeOf(context);
  if (embeddedNavigator != null) {
    embeddedNavigator.onOpenSupport(
      initialTopicKey: initialTopicKey,
      initialBookingId: initialBookingId,
      initialUserId: initialUserId,
    );
    return;
  }
  await openSupportCenter(
    context,
    user: user,
    initialTopicKey: initialTopicKey,
    initialBookingId: initialBookingId,
    initialUserId: initialUserId,
  );
}

class _PendingSupportAttachment {
  const _PendingSupportAttachment({
    required this.bytes,
    required this.fileName,
    this.mimeType,
    this.size,
  });

  final Uint8List bytes;
  final String fileName;
  final String? mimeType;
  final int? size;
}

class _SupportCenterViewState extends State<SupportCenterView> {
  static const Duration _supportLoadTimeout = Duration(seconds: 6);
  static const Duration _supportThreadLookupTimeout = Duration(seconds: 3);
  static List<Booking> _cachedAccessibleBookings = const [];
  static List<UserModel> _cachedAdminUsers = const [];
  static UserModel? _cachedSupportAgentUser;
  static bool _cachedHasLoadedBookings = false;
  static bool _cachedHasLoadedAdminUsers = false;
  static bool _cachedHasLoadedSupportAgent = false;
  final SupportRequest _supportRequest = SupportRequest.instance;
  final BookingRequest _bookingRequest = BookingRequest.instance;
  final AuthRequest _authRequest = AuthRequest.instance;
  final AppWarmupService _warmupService = AppWarmupService.instance;
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _adminSearchController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  String _selectedTopicKey = supportTopicBooking;
  String? _selectedBookingId;
  String? _selectedThreadId;
  UserModel? _selectedAdminDraftUser;
  UserModel? _supportAgentUser;
  bool _isLoadingBookings = false;
  bool _isLoadingAdminUsers = false;
  bool _isLoadingSupportAgent = false;
  bool _isSending = false;
  bool _showMobileChat = false;
  List<Booking> _accessibleBookings = const [];
  List<UserModel> _adminUsers = const [];
  bool _didScheduleAdminUsersWarmRetry = false;
  List<_PendingSupportAttachment> _pendingAttachments = const [];
  Map<String, String> _threadReadMarkersById = const <String, String>{};
  String? _pendingInitialAdminUserId;
  int _chatScrollRequestTick = 0;
  final RoleAccessService _roleAccessService = RoleAccessService.instance;
  bool? _lastBlockingOverlayVisible;

  String? get _effectiveRole =>
      _roleAccessService.effectiveRoleKey(widget.user.role);

  bool get _canReadSupport =>
      _roleAccessService.canAccess('support.read', role: _effectiveRole);

  bool get _canCreateSupport =>
      _roleAccessService.canAccess('support.create', role: _effectiveRole);

  bool get _canUpdateSupport =>
      _roleAccessService.canAccess('support.update', role: _effectiveRole);

  bool get _isAdmin =>
      _canReadSupport &&
      _roleAccessService.canAccess('users.read', role: _effectiveRole);

  bool get _hasStableAdminSelection =>
      _isAdmin &&
      normalizeId(_selectedThreadId) != null &&
      _selectedAdminDraftUser == null;

  List<UserModel> _filteredAdminUsersFrom(List<UserModel> users) {
    final currentUserId = normalizeId(widget.user.id);
    final filtered = users.where((user) {
      final userId = normalizeId(user.id);
      return userId != null && userId != currentUserId;
    }).toList();
    filtered.sort((left, right) {
      final leftName = (left.name ?? '').trim().toLowerCase();
      final rightName = (right.name ?? '').trim().toLowerCase();
      final byName = leftName.compareTo(rightName);
      if (byName != 0) {
        return byName;
      }
      final leftId = normalizeId(left.id) ?? '';
      final rightId = normalizeId(right.id) ?? '';
      return leftId.compareTo(rightId);
    });
    return filtered;
  }

  List<SupportThread> _initialSupportThreadsForCurrentUser() {
    if (!SupportRequest.hasResolvedAllThreads) {
      return const <SupportThread>[];
    }
    final allThreads = SupportRequest.hydratedAllThreadsSnapshot;
    if (_isAdmin) {
      return allThreads;
    }
    final currentUserId = normalizeId(widget.user.id);
    if (currentUserId == null) {
      return const <SupportThread>[];
    }
    return allThreads
        .where((thread) {
          return normalizeId(thread.requesterUserId) == currentUserId;
        })
        .toList(growable: false)
      ..sort((left, right) {
        final leftDate = left.updatedAt ?? left.createdAt;
        final rightDate = right.updatedAt ?? right.createdAt;
        if (leftDate == null && rightDate == null) {
          return 0;
        }
        if (leftDate == null) {
          return 1;
        }
        if (rightDate == null) {
          return -1;
        }
        return rightDate.compareTo(leftDate);
      });
  }

  @override
  void initState() {
    super.initState();
    _accessibleBookings = List<Booking>.from(_cachedAccessibleBookings);
    _adminUsers = List<UserModel>.from(_cachedAdminUsers);
    _supportAgentUser = _cachedSupportAgentUser;
    if (_isAdmin && AuthRequest.hasResolvedUsers) {
      final sharedAdminUsers = _filteredAdminUsersFrom(
        AuthRequest.hydratedUsersSnapshot,
      );
      _adminUsers = List<UserModel>.from(sharedAdminUsers);
      _cachedAdminUsers = List<UserModel>.from(sharedAdminUsers);
      _cachedHasLoadedAdminUsers = true;
    } else if (!_isAdmin && AuthRequest.hasResolvedUsers) {
      final sharedSupportAgent = AuthRequest.hydratedUsersSnapshot.where((
        user,
      ) {
        return normalizeId(user.id) == '1';
      }).firstOrNull;
      _supportAgentUser = sharedSupportAgent;
      _cachedSupportAgentUser = sharedSupportAgent;
      _cachedHasLoadedSupportAgent = true;
    }
    _selectedBookingId = normalizeId(widget.initialBookingId);
    _pendingInitialAdminUserId = normalizeId(widget.initialUserId);
    _selectedTopicKey =
        (widget.initialTopicKey?.trim().isNotEmpty == true
                ? widget.initialTopicKey
                : (_selectedBookingId != null || _isAdmin
                      ? supportTopicBooking
                      : supportTopicGeneral))!
            .trim()
            .toLowerCase();
    _loadThreadReadMarkers();
    _loadAccessibleBookings();
    if (_isAdmin) {
      _loadAdminUsers();
    } else {
      _loadSupportAgentUser();
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _adminSearchController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _requestScrollToLatest() {
    if (!mounted) {
      return;
    }
    setState(() {
      _chatScrollRequestTick += 1;
    });
  }

  Future<void> _loadThreadReadMarkers() async {
    final markers = await _supportRequest.readThreadReadMarkers(
      widget.user.id ?? '',
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _threadReadMarkersById = markers;
    });
  }

  Future<void> _markThreadReadFromThread(SupportThread? thread) async {
    if (thread == null) {
      return;
    }
    final currentUserId = normalizeId(widget.user.id);
    final threadId = normalizeId(thread.id);
    final lastSenderId = normalizeId(thread.lastSenderUserId);
    if (currentUserId == null ||
        threadId == null ||
        lastSenderId == null ||
        lastSenderId == currentUserId ||
        !thread.hasConversation) {
      return;
    }
    final marker = _supportRequest.threadReadMarkerForThread(thread);
    if (marker.isEmpty || _threadReadMarkersById[threadId] == marker) {
      return;
    }
    final nextMarkers = <String, String>{
      ..._threadReadMarkersById,
      threadId: marker,
    };
    if (mounted) {
      setState(() {
        _threadReadMarkersById = nextMarkers;
      });
    }
    await _supportRequest.markThreadRead(
      userId: currentUserId,
      threadId: threadId,
      marker: marker,
    );
  }

  Future<void> _markThreadReadFromMessages(
    String threadId,
    List<SupportMessage> messages,
  ) async {
    final normalizedThreadId = normalizeId(threadId);
    final currentUserId = normalizeId(widget.user.id);
    if (normalizedThreadId == null ||
        currentUserId == null ||
        messages.isEmpty) {
      return;
    }
    final latestMessage = messages.last;
    final latestSenderId = normalizeId(latestMessage.senderUserId);
    if (latestSenderId == null || latestSenderId == currentUserId) {
      return;
    }
    final marker = _supportRequest.threadReadMarkerForMessage(latestMessage);
    if (marker.isEmpty ||
        _threadReadMarkersById[normalizedThreadId] == marker) {
      return;
    }
    final nextMarkers = <String, String>{
      ..._threadReadMarkersById,
      normalizedThreadId: marker,
    };
    if (mounted) {
      setState(() {
        _threadReadMarkersById = nextMarkers;
      });
    }
    await _supportRequest.markThreadRead(
      userId: currentUserId,
      threadId: normalizedThreadId,
      marker: marker,
    );
  }

  bool _isThreadUnreadForCurrentUser(SupportThread? thread) {
    if (thread == null) {
      return false;
    }
    final currentUserId = normalizeId(widget.user.id);
    final threadId = normalizeId(thread.id);
    final senderId = normalizeId(thread.lastSenderUserId);
    if (currentUserId == null ||
        threadId == null ||
        senderId == null ||
        senderId == currentUserId ||
        !thread.hasConversation) {
      return false;
    }
    final latestMarker = _supportRequest.threadReadMarkerForThread(thread);
    if (latestMarker.isEmpty) {
      return false;
    }
    final savedMarker = _threadReadMarkersById[threadId];
    if (savedMarker == null || savedMarker.isEmpty) {
      return false;
    }
    return savedMarker != latestMarker;
  }

  Future<void> _loadAccessibleBookings() async {
    if (_isAdmin) {
      return;
    }
    final shouldShowBlockingLoading =
        !_cachedHasLoadedBookings && _accessibleBookings.isEmpty;
    _log(
      'load start section=support-bookings visible=${!shouldShowBlockingLoading} local=${_accessibleBookings.length} cached=${_cachedAccessibleBookings.length}',
    );
    setState(() {
      _isLoadingBookings = shouldShowBlockingLoading;
    });
    try {
      await _bookingRequest.initialize();
      await _warmupService.warmBookings();
      final allBookings = await _bookingRequest.getBookings().timeout(
        _supportLoadTimeout,
        onTimeout: () => const <Booking>[],
      );
      final filtered = _accessibleBookingsForUser(widget.user, allBookings)
        ..sort((left, right) {
          final leftDate = left.updatedAt ?? left.createdAt;
          final rightDate = right.updatedAt ?? right.createdAt;
          if (leftDate == null && rightDate == null) {
            return 0;
          }
          if (leftDate == null) {
            return 1;
          }
          if (rightDate == null) {
            return -1;
          }
          return rightDate.compareTo(leftDate);
        });
      if (!mounted) {
        return;
      }
      setState(() {
        _accessibleBookings = filtered;
        _cachedAccessibleBookings = List<Booking>.from(filtered);
        _cachedHasLoadedBookings = true;
        final hasSelectedBooking = filtered.any(
          (booking) =>
              normalizeId(booking.id) == normalizeId(_selectedBookingId),
        );
        if (!hasSelectedBooking) {
          _selectedBookingId = null;
        }
      });
      _log('load resolved section=support-bookings count=${filtered.length}');
    } catch (error) {
      _log('load error section=support-bookings error=$error');
      if (!mounted) {
        return;
      }
      AppSnackbar.showError(
        context,
        userFacingErrorMessage(
          error,
          fallback: 'We could not load your bookings right now.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingBookings = false;
        });
      }
      _log(
        'load finish section=support-bookings loading=$_isLoadingBookings count=${_accessibleBookings.length}',
      );
    }
  }

  Future<void> _loadAdminUsers() async {
    final sharedUsersResolved = AuthRequest.hasResolvedUsers;
    final sharedAdminUsers = sharedUsersResolved
        ? _filteredAdminUsersFrom(AuthRequest.hydratedUsersSnapshot)
        : const <UserModel>[];
    if (sharedUsersResolved &&
        (_adminUsers.isEmpty || _cachedAdminUsers.isEmpty)) {
      _adminUsers = List<UserModel>.from(sharedAdminUsers);
      _cachedAdminUsers = List<UserModel>.from(sharedAdminUsers);
      _cachedHasLoadedAdminUsers = true;
    }
    final shouldShowBlockingLoading =
        !_cachedHasLoadedAdminUsers && _adminUsers.isEmpty;
    _log(
      'load start section=support-users visible=${!shouldShowBlockingLoading} local=${_adminUsers.length} cached=${_cachedAdminUsers.length} shared=${sharedAdminUsers.length} sharedResolved=$sharedUsersResolved',
    );
    setState(() {
      _isLoadingAdminUsers = shouldShowBlockingLoading;
    });
    try {
      await _warmupService.warmUsers();
      final users = await _authRequest.getUsers().timeout(
        _supportLoadTimeout,
        onTimeout: () => List<UserModel>.from(_adminUsers),
      );
      if (!mounted) {
        return;
      }
      final filtered = _filteredAdminUsersFrom(users);
      setState(() {
        _adminUsers = filtered;
        _cachedAdminUsers = List<UserModel>.from(filtered);
        _cachedHasLoadedAdminUsers = true;
      });
      _log('load resolved section=support-users count=${filtered.length}');
      await _applyPendingInitialAdminUser(filtered);
    } catch (error) {
      _log('load error section=support-users error=$error');
      if (!mounted) {
        return;
      }
      AppSnackbar.showError(
        context,
        userFacingErrorMessage(
          error,
          fallback: 'We could not load the user inbox right now.',
        ),
      );
      _scheduleAdminUsersWarmRetryIfNeeded();
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAdminUsers = false;
        });
      }
      _log(
        'load finish section=support-users loading=$_isLoadingAdminUsers count=${_adminUsers.length}',
      );
    }
  }

  void _scheduleAdminUsersWarmRetryIfNeeded() {
    if (_didScheduleAdminUsersWarmRetry ||
        !currentNetworkStatus() ||
        _cachedHasLoadedAdminUsers ||
        _adminUsers.isNotEmpty) {
      return;
    }
    _didScheduleAdminUsersWarmRetry = true;
    unawaited(_retryLoadAdminUsersAfterWarmup());
  }

  Future<void> _retryLoadAdminUsersAfterWarmup() async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted || !_isAdmin) {
      return;
    }
    _didScheduleAdminUsersWarmRetry = false;
    await _loadAdminUsers();
  }

  Future<void> _applyPendingInitialAdminUser(List<UserModel> users) async {
    final targetUserId = normalizeId(_pendingInitialAdminUserId);
    if (targetUserId == null) {
      return;
    }
    if (_hasStableAdminSelection) {
      if (mounted) {
        setState(() {
          _pendingInitialAdminUserId = null;
        });
      } else {
        _pendingInitialAdminUserId = null;
      }
      return;
    }
    final targetUser = users.where((user) {
      return normalizeId(user.id) == targetUserId;
    }).firstOrNull;
    if (targetUser == null) {
      if (mounted) {
        setState(() {
          _pendingInitialAdminUserId = null;
        });
      } else {
        _pendingInitialAdminUserId = null;
      }
      return;
    }
    try {
      final thread = await _supportRequest
          .findAdminDirectThread(targetUser: targetUser)
          .timeout(_supportThreadLookupTimeout, onTimeout: () => null);
      if (!mounted) {
        _pendingInitialAdminUserId = null;
        return;
      }
      if (_hasStableAdminSelection) {
        setState(() {
          _pendingInitialAdminUserId = null;
        });
        return;
      }
      setState(() {
        _selectedThreadId = thread?.id;
        _selectedAdminDraftUser = thread == null ? targetUser : null;
        _pendingInitialAdminUserId = null;
        _showMobileChat = true;
      });
      _requestScrollToLatest();
    } catch (_) {
      if (!mounted) {
        _pendingInitialAdminUserId = null;
        return;
      }
      if (_hasStableAdminSelection) {
        setState(() {
          _pendingInitialAdminUserId = null;
        });
        return;
      }
      setState(() {
        _selectedThreadId = null;
        _selectedAdminDraftUser = targetUser;
        _pendingInitialAdminUserId = null;
        _showMobileChat = true;
      });
      _requestScrollToLatest();
    }
  }

  Future<void> _loadSupportAgentUser() async {
    final sharedUsersResolved = AuthRequest.hasResolvedUsers;
    final sharedSupportAgent = sharedUsersResolved
        ? AuthRequest.hydratedUsersSnapshot.where((user) {
            return normalizeId(user.id) == '1';
          }).firstOrNull
        : null;
    if (sharedUsersResolved && _supportAgentUser == null) {
      _supportAgentUser = sharedSupportAgent;
      _cachedSupportAgentUser = sharedSupportAgent;
      _cachedHasLoadedSupportAgent = true;
    }
    final shouldShowBlockingLoading =
        !_cachedHasLoadedSupportAgent && _supportAgentUser == null;
    _log(
      'load start section=support-agent visible=${!shouldShowBlockingLoading} local=${normalizeId(_supportAgentUser?.id) ?? "-"} cached=${normalizeId(_cachedSupportAgentUser?.id) ?? "-"} shared=${normalizeId(sharedSupportAgent?.id) ?? "-"} sharedResolved=$sharedUsersResolved',
    );
    setState(() {
      _isLoadingSupportAgent = shouldShowBlockingLoading;
    });
    try {
      await _warmupService.warmUsers();
      final users = await _authRequest.getUsers().timeout(
        _supportLoadTimeout,
        onTimeout: () => const <UserModel>[],
      );
      if (!mounted) {
        return;
      }
      final supportAgent = users.where((user) {
        return normalizeId(user.id) == '1';
      }).firstOrNull;
      setState(() {
        _supportAgentUser = supportAgent;
        _cachedSupportAgentUser = supportAgent;
        _cachedHasLoadedSupportAgent = true;
      });
      _log(
        'load resolved section=support-agent user=${normalizeId(supportAgent?.id) ?? "-"}',
      );
    } catch (error) {
      _log('load error section=support-agent error=$error');
      if (!mounted) {
        return;
      }
      AppSnackbar.showError(
        context,
        userFacingErrorMessage(
          error,
          fallback: 'We could not load client support right now.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingSupportAgent = false;
        });
      }
      _log(
        'load finish section=support-agent loading=$_isLoadingSupportAgent user=${normalizeId(_supportAgentUser?.id) ?? "-"}',
      );
    }
  }

  Future<void> _pickAttachments() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (!mounted || result == null) {
      return;
    }
    final next = List<_PendingSupportAttachment>.from(_pendingAttachments);
    for (final file in result.files) {
      if (file.bytes == null) {
        continue;
      }
      next.add(
        _PendingSupportAttachment(
          bytes: file.bytes!,
          fileName: file.name,
          mimeType: file.extension == null
              ? null
              : _fileMimeTypeFromExtension(file.extension!),
          size: file.size,
        ),
      );
    }
    setState(() {
      _pendingAttachments = next;
    });
  }

  Future<void> _ensureSelectedThread() async {
    if (!_canCreateSupport) {
      AppSnackbar.showError(
        context,
        'You do not have access to start a support conversation.',
      );
      return;
    }
    if (_isAdmin) {
      return;
    }
    if (_selectedTopicKey == supportTopicBooking &&
        normalizeId(_selectedBookingId) == null) {
      AppSnackbar.showError(context, 'Select a booking first.');
      return;
    }
    final booking = _accessibleBookings.where((item) {
      return normalizeId(item.id) == normalizeId(_selectedBookingId);
    }).firstOrNull;
    final thread = await _supportRequest.ensureThread(
      requester: widget.user,
      topicKey: _selectedTopicKey,
      booking: booking,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedThreadId = thread.id;
      _showMobileChat = true;
    });
    _requestScrollToLatest();
  }

  Future<void> _sendMessage() async {
    if (!_isAdmin && normalizeId(_selectedThreadId) == null) {
      await _ensureSelectedThread();
    }
    if (!mounted) {
      return;
    }
    final trimmedMessage = _messageController.text.trim();
    if (trimmedMessage.isEmpty && _pendingAttachments.isEmpty) {
      return;
    }

    String? threadId = normalizeId(_selectedThreadId);
    final List<SupportMessage> cachedMessages = threadId == null
        ? const <SupportMessage>[]
        : (_supportRequest.peekLastVisibleMessages(threadId) ??
              const <SupportMessage>[]);
    final isStartingConversation = threadId == null || cachedMessages.isEmpty;
    final canSendCurrentMessage = isStartingConversation
        ? _canCreateSupport
        : _canUpdateSupport;
    if (!canSendCurrentMessage) {
      AppSnackbar.showError(
        context,
        isStartingConversation
            ? 'You do not have access to start a support conversation.'
            : 'You do not have access to reply in this support conversation.',
      );
      return;
    }
    if (_isAdmin && threadId == null && _selectedAdminDraftUser != null) {
      try {
        final thread = await _supportRequest
            .createLocalAdminDirectThreadForSend(
              targetUser: _selectedAdminDraftUser!,
            );
        if (!mounted) {
          return;
        }
        setState(() {
          _selectedThreadId = thread.id;
        });
        threadId = normalizeId(thread.id);
        _requestScrollToLatest();
      } catch (error) {
        if (!mounted) {
          return;
        }
        AppSnackbar.showError(
          context,
          userFacingErrorMessage(
            error,
            fallback: 'We could not open this support chat right now.',
          ),
        );
        return;
      }
    }

    if (threadId == null) {
      AppSnackbar.showError(
        context,
        _isAdmin
            ? 'Select a support request first.'
            : 'Open a support chat first.',
      );
      return;
    }

    final attachmentsToSend = _pendingAttachments
        .map(
          (attachment) => QueuedSupportAttachmentInput(
            bytes: attachment.bytes,
            fileName: attachment.fileName,
            mimeType: attachment.mimeType,
            size: attachment.size,
          ),
        )
        .toList(growable: false);
    const shouldLockComposer = false;
    setState(() {
      _isSending = shouldLockComposer;
      _messageController.clear();
      _pendingAttachments = const [];
    });
    _requestScrollToLatest();
    try {
      final queuedForSync = await _supportRequest.sendMessageWithAttachments(
        threadId: threadId,
        sender: widget.user,
        text: trimmedMessage,
        attachments: attachmentsToSend,
      );
      if (!mounted) {
        return;
      }
      if (queuedForSync) {
        AppSnackbar.showSuccess(
          context,
          'Message queued. It will send once your internet is back.',
        );
      }
      _requestScrollToLatest();
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppSnackbar.showError(
        context,
        userFacingErrorMessage(
          error,
          fallback: 'We could not send the support message right now.',
        ),
      );
      setState(() {
        _messageController.text = trimmedMessage;
        _messageController.selection = TextSelection.collapsed(
          offset: _messageController.text.length,
        );
        _pendingAttachments = attachmentsToSend
            .map(
              (attachment) => _PendingSupportAttachment(
                bytes: attachment.bytes,
                fileName: attachment.fileName,
                mimeType: attachment.mimeType,
                size: attachment.size,
              ),
            )
            .toList(growable: false);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  Future<void> _openAdminThreadForUser(
    UserModel user,
    List<SupportThread> threads,
  ) async {
    final existingThread = threads.where((thread) {
      return normalizeId(thread.requesterUserId) == normalizeId(user.id);
    }).firstOrNull;
    if (existingThread != null) {
      setState(() {
        _selectedThreadId = existingThread.id;
        _selectedAdminDraftUser = null;
        _showMobileChat = true;
      });
      unawaited(_markThreadReadFromThread(existingThread));
      _requestScrollToLatest();
      return;
    }

    setState(() {
      _selectedThreadId = null;
      _selectedAdminDraftUser = user;
      _showMobileChat = true;
    });
    _requestScrollToLatest();
  }

  @override
  Widget build(BuildContext context) {
    if (!_canReadSupport) {
      return const Center(
        child: AdminListStateText(
          message: 'You do not have access to view support.',
        ),
      );
    }
    final content = _isAdmin
        ? StreamBuilder<List<SupportThread>>(
            initialData: _initialSupportThreadsForCurrentUser(),
            stream: _supportRequest.watchAllThreads(),
            builder: (context, snapshot) {
              final threads = (snapshot.data ?? const <SupportThread>[]).where((
                thread,
              ) {
                final isSelectedThread =
                    normalizeId(thread.id) == normalizeId(_selectedThreadId);
                final matchesDraftUser =
                    _selectedAdminDraftUser != null &&
                    normalizeId(thread.requesterUserId) ==
                        normalizeId(_selectedAdminDraftUser!.id);
                return thread.hasConversation ||
                    isSelectedThread ||
                    matchesDraftUser;
              }).toList();
              _selectedThreadId = _resolvedSelectedThreadId(
                currentSelectedThreadId: _selectedThreadId,
                threads: threads,
                preferredTopicKey: _selectedTopicKey,
                preferredBookingId: _selectedBookingId,
                allowEmptySelection: _selectedAdminDraftUser != null,
              );
              return _buildSurface(
                threads: threads,
                isLoading:
                    snapshot.connectionState == ConnectionState.waiting ||
                    _isLoadingAdminUsers,
              );
            },
          )
        : StreamBuilder<List<SupportThread>>(
            initialData: _initialSupportThreadsForCurrentUser(),
            stream: _supportRequest.watchThreadsForUser(widget.user.id ?? ''),
            builder: (context, snapshot) {
              final threads = snapshot.data ?? const <SupportThread>[];
              _selectedThreadId = _resolvedSelectedThreadId(
                currentSelectedThreadId: _selectedThreadId,
                threads: threads,
                preferredTopicKey: _selectedTopicKey,
                preferredBookingId: _selectedBookingId,
              );
              return _buildSurface(
                threads: threads,
                isLoading:
                    snapshot.connectionState == ConnectionState.waiting ||
                    _isLoadingBookings ||
                    _isLoadingSupportAgent,
              );
            },
          );

    if (widget.embedded) {
      return content;
    }
    return SelectionArea(
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F7FB),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: content,
          ),
        ),
      ),
    );
  }

  Widget _buildSurface({
    required List<SupportThread> threads,
    required bool isLoading,
  }) {
    final selectedThread = threads.where((thread) {
      return normalizeId(thread.id) == normalizeId(_selectedThreadId);
    }).firstOrNull;
    final hasVisibleChatTarget =
        selectedThread != null || _selectedAdminDraftUser != null;
    final hasVisibleThreadList = threads.isNotEmpty || _adminUsers.isNotEmpty;
    final showBlockingLoading =
        isLoading && !hasVisibleChatTarget && !hasVisibleThreadList;
    if (_lastBlockingOverlayVisible != showBlockingLoading) {
      _lastBlockingOverlayVisible = showBlockingLoading;
      _log(
        '${showBlockingLoading ? "overlay show" : "overlay hide"} section=support reason=isLoading=$isLoading visibleChat=$hasVisibleChatTarget visibleList=$hasVisibleThreadList threads=${threads.length} users=${_adminUsers.length} bookings=${_accessibleBookings.length}',
      );
    }
    return AppPageLoadingOverlay(
      isVisible: showBlockingLoading,
      message: 'Loading, please wait ...',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.embedded) ...[
            _StandaloneSupportHeader(
              title: _isAdmin ? 'Support' : 'Paltranco Support',
              onBack: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(height: 16),
          ],
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final useWideLayout = constraints.maxWidth >= 1080;
                final sidebar = _isAdmin
                    ? _AdminSupportThreadList(
                        currentUser: widget.user,
                        threads: threads,
                        users: _adminUsers,
                        searchController: _adminSearchController,
                        selectedThreadId: _selectedThreadId,
                        selectedDraftUserId: _selectedAdminDraftUser?.id,
                        isThreadUnread: _isThreadUnreadForCurrentUser,
                        onSearchChanged: () => setState(() {}),
                        onSelect: (thread) {
                          setState(() {
                            _selectedThreadId = thread.id;
                            _selectedAdminDraftUser = null;
                            _showMobileChat = true;
                          });
                          unawaited(_markThreadReadFromThread(thread));
                        },
                        onSelectUser: (user) {
                          setState(() {
                            _adminSearchController.clear();
                          });
                          _openAdminThreadForUser(user, threads);
                        },
                      )
                    : _UserSupportSidebar(
                        currentUser: widget.user,
                        threads: threads,
                        selectedThreadId: _selectedThreadId,
                        isThreadUnread: _isThreadUnreadForCurrentUser,
                        selectedTopicKey: _selectedTopicKey,
                        selectedBookingId: _selectedBookingId,
                        accessibleBookings: _accessibleBookings,
                        onSelectThread: (thread) {
                          setState(() {
                            _selectedThreadId = thread.id;
                            _showMobileChat = true;
                          });
                          unawaited(_markThreadReadFromThread(thread));
                        },
                        onTopicChanged: (value) {
                          setState(() {
                            _selectedTopicKey = value;
                            if (value != supportTopicBooking) {
                              _selectedBookingId = null;
                            }
                          });
                        },
                        onBookingChanged: (value) {
                          setState(() {
                            _selectedBookingId = value;
                          });
                        },
                        onOpenThread: _ensureSelectedThread,
                      );
                final selectedCounterpartUser = _isAdmin
                    ? _resolvedThreadRequesterUser(selectedThread)
                    : _supportAgentUser;
                final supportUsersById = _supportUsersById();
                final chatPanel = _SupportChatPanel(
                  key: ValueKey(
                    '${selectedThread?.id ?? 'none'}:'
                    '${_selectedAdminDraftUser?.id ?? 'draft-none'}:'
                    '${widget.user.id ?? '-'}',
                  ),
                  currentUser: widget.user,
                  thread: selectedThread,
                  draftUser: _isAdmin
                      ? _selectedAdminDraftUser
                      : _supportAgentUser,
                  counterpartUser: selectedCounterpartUser,
                  usersById: supportUsersById,
                  subtitleOverride: _isAdmin ? null : 'Client Support',
                  onBack: _isAdmin
                      ? () {
                          setState(() {
                            _showMobileChat = false;
                          });
                        }
                      : null,
                  messageController: _messageController,
                  pendingAttachments: _pendingAttachments,
                  isSending: _isSending,
                  onPickAttachments: _pickAttachments,
                  onRemovePendingAttachment: (index) {
                    setState(() {
                      final next = List<_PendingSupportAttachment>.from(
                        _pendingAttachments,
                      )..removeAt(index);
                      _pendingAttachments = next;
                    });
                  },
                  onSend: _sendMessage,
                  canCompose: _canCreateSupport || _canUpdateSupport,
                  supportRequest: _supportRequest,
                  onMessagesVisible: (messages) {
                    final threadId = selectedThread?.id;
                    if (threadId == null) {
                      return;
                    }
                    unawaited(_markThreadReadFromMessages(threadId, messages));
                  },
                  scrollController: _chatScrollController,
                  scrollRequestTick: _chatScrollRequestTick,
                );
                return AdminListItemCard(
                  padding: EdgeInsets.zero,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(18),
                    ),
                    child: _isAdmin
                        ? () {
                            final useMobileLayout = constraints.maxWidth < 760;
                            if (useWideLayout) {
                              return Row(
                                children: [
                                  SizedBox(
                                    width: 370,
                                    child: _SupportSidebarSurface(
                                      child: sidebar,
                                    ),
                                  ),
                                  const VerticalDivider(
                                    width: 1,
                                    thickness: 1,
                                    color: AppColors.primaryBorder,
                                  ),
                                  Expanded(
                                    child: _SupportChatPanel(
                                      key: chatPanel.key,
                                      currentUser: widget.user,
                                      thread: selectedThread,
                                      draftUser: _selectedAdminDraftUser,
                                      counterpartUser: selectedCounterpartUser,
                                      usersById: supportUsersById,
                                      subtitleOverride: null,
                                      onBack: null,
                                      messageController: _messageController,
                                      pendingAttachments: _pendingAttachments,
                                      isSending: _isSending,
                                      onPickAttachments: _pickAttachments,
                                      onRemovePendingAttachment: (index) {
                                        setState(() {
                                          final next =
                                              List<
                                                  _PendingSupportAttachment
                                                >.from(_pendingAttachments)
                                                ..removeAt(index);
                                          _pendingAttachments = next;
                                        });
                                      },
                                      onSend: _sendMessage,
                                      canCompose:
                                          _canCreateSupport ||
                                          _canUpdateSupport,
                                      supportRequest: _supportRequest,
                                      onMessagesVisible: (messages) {
                                        final threadId = selectedThread?.id;
                                        if (threadId == null) {
                                          return;
                                        }
                                        unawaited(
                                          _markThreadReadFromMessages(
                                            threadId,
                                            messages,
                                          ),
                                        );
                                      },
                                      scrollController: _chatScrollController,
                                      scrollRequestTick: _chatScrollRequestTick,
                                    ),
                                  ),
                                ],
                              );
                            }
                            if (useMobileLayout) {
                              return _showMobileChat && hasVisibleChatTarget
                                  ? chatPanel
                                  : _SupportSidebarSurface(child: sidebar);
                            }
                            return Column(
                              children: [
                                SizedBox(
                                  height: 320,
                                  child: _SupportSidebarSurface(child: sidebar),
                                ),
                                const Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: AppColors.primaryBorder,
                                ),
                                Expanded(child: chatPanel),
                              ],
                            );
                          }()
                        : chatPanel,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  UserModel? _resolvedThreadRequesterUser(SupportThread? thread) {
    final requesterId = normalizeId(thread?.requesterUserId);
    if (requesterId == null) {
      return null;
    }
    return _adminUsers
            .where((user) => normalizeId(user.id) == requesterId)
            .firstOrNull ??
        AuthRequest.hydratedUsersSnapshot
            .where((user) => normalizeId(user.id) == requesterId)
            .firstOrNull;
  }

  Map<String, UserModel> _supportUsersById() {
    final usersById = <String, UserModel>{};
    void addUser(UserModel? user) {
      final userId = normalizeId(user?.id);
      if (userId != null && user != null) {
        usersById[userId] = user;
      }
    }

    addUser(widget.user);
    addUser(_supportAgentUser);
    for (final user in _adminUsers) {
      addUser(user);
    }
    for (final user in AuthRequest.hydratedUsersSnapshot) {
      addUser(user);
    }
    return usersById;
  }

  String? _resolvedSelectedThreadId({
    required String? currentSelectedThreadId,
    required List<SupportThread> threads,
    String? preferredTopicKey,
    String? preferredBookingId,
    bool allowEmptySelection = false,
  }) {
    final normalizedCurrent = normalizeId(currentSelectedThreadId);
    if (normalizedCurrent != null &&
        threads.any((thread) => normalizeId(thread.id) == normalizedCurrent)) {
      return normalizedCurrent;
    }
    if (allowEmptySelection) {
      return null;
    }
    if (threads.isEmpty) {
      return null;
    }
    final normalizedTopic = preferredTopicKey?.trim().toLowerCase();
    final normalizedBookingId = normalizeId(preferredBookingId);
    for (final thread in threads) {
      if (normalizedTopic != null &&
          normalizedTopic.isNotEmpty &&
          (thread.topicKey ?? '').trim().toLowerCase() != normalizedTopic) {
        continue;
      }
      if (normalizedBookingId != null &&
          normalizeId(thread.bookingId) != normalizedBookingId) {
        continue;
      }
      return thread.id;
    }
    return threads.first.id;
  }

  void _log(String message) {
    // Temporary debug logging removed.
  }
}

class _StandaloneSupportHeader extends StatelessWidget {
  const _StandaloneSupportHeader({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
          color: AppColors.primaryColor,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          visualDensity: VisualDensity.compact,
          splashRadius: 22,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _SupportSidebarSurface extends StatelessWidget {
  const _SupportSidebarSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(color: const Color(0xFFF9F7FF), child: child);
  }
}

class _UserSupportSidebar extends StatelessWidget {
  const _UserSupportSidebar({
    required this.currentUser,
    required this.threads,
    required this.selectedThreadId,
    required this.isThreadUnread,
    required this.selectedTopicKey,
    required this.selectedBookingId,
    required this.accessibleBookings,
    required this.onSelectThread,
    required this.onTopicChanged,
    required this.onBookingChanged,
    required this.onOpenThread,
  });

  final UserModel currentUser;
  final List<SupportThread> threads;
  final String? selectedThreadId;
  final bool Function(SupportThread thread) isThreadUnread;
  final String selectedTopicKey;
  final String? selectedBookingId;
  final List<Booking> accessibleBookings;
  final ValueChanged<SupportThread> onSelectThread;
  final ValueChanged<String> onTopicChanged;
  final ValueChanged<String?> onBookingChanged;
  final Future<void> Function() onOpenThread;

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<SupportThread>>{};
    for (final thread in threads) {
      grouped
          .putIfAbsent(thread.resolvedTopicLabel, () => <SupportThread>[])
          .add(thread);
    }
    final topicKeys = grouped.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.primaryBorder)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Topics',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Choose a topic and continue your conversation with support.',
                style: TextStyle(
                  color: AppColors.primaryColor.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              _SupportTopicDropdown(
                selectedTopicKey: selectedTopicKey,
                onChanged: onTopicChanged,
              ),
              if (selectedTopicKey == supportTopicBooking) ...[
                const SizedBox(height: 12),
                _SupportBookingDropdown(
                  bookings: accessibleBookings,
                  selectedBookingId: selectedBookingId,
                  onChanged: onBookingChanged,
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onOpenThread,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('Open Chat'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: threads.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: AdminListStateText(message: 'No support chats yet.'),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
                  children: [
                    for (final topicKey in topicKeys) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
                        child: Text(
                          topicKey,
                          style: TextStyle(
                            color: AppColors.primaryColor.withValues(
                              alpha: 0.72,
                            ),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      ...grouped[topicKey]!.asMap().entries.map((entry) {
                        final thread = entry.value;
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: entry.key == grouped[topicKey]!.length - 1
                                ? 0
                                : 8,
                          ),
                          child: _SupportThreadTile(
                            currentUser: currentUser,
                            thread: thread,
                            isUnread: isThreadUnread(thread),
                            isSelected:
                                normalizeId(thread.id) ==
                                normalizeId(selectedThreadId),
                            onTap: () => onSelectThread(thread),
                          ),
                        );
                      }),
                      if (topicKey != topicKeys.last)
                        const SizedBox(height: 14),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _AdminSupportThreadList extends StatelessWidget {
  const _AdminSupportThreadList({
    required this.currentUser,
    required this.threads,
    required this.users,
    required this.searchController,
    required this.selectedThreadId,
    required this.selectedDraftUserId,
    required this.isThreadUnread,
    required this.onSearchChanged,
    required this.onSelect,
    required this.onSelectUser,
  });

  final UserModel currentUser;
  final List<SupportThread> threads;
  final List<UserModel> users;
  final TextEditingController searchController;
  final String? selectedThreadId;
  final String? selectedDraftUserId;
  final bool Function(SupportThread thread) isThreadUnread;
  final VoidCallback onSearchChanged;
  final ValueChanged<SupportThread> onSelect;
  final ValueChanged<UserModel> onSelectUser;

  static const double _horizontalInset = 20;

  @override
  Widget build(BuildContext context) {
    final usersById = <String, UserModel>{
      for (final user in users)
        if (normalizeId(user.id) != null) normalizeId(user.id)!: user,
    };
    final searchQuery = searchController.text.trim().toLowerCase();
    final latestThreadByUserId = <String, SupportThread>{};
    for (final thread in threads) {
      final requesterId = normalizeId(thread.requesterUserId);
      if (requesterId == null ||
          latestThreadByUserId.containsKey(requesterId)) {
        continue;
      }
      latestThreadByUserId[requesterId] = thread;
    }
    final matchingUsers = searchQuery.isEmpty
        ? const <UserModel>[]
        : users.where((user) {
            final name = (user.name ?? '').trim().toLowerCase();
            final email = (user.email ?? '').trim().toLowerCase();
            final phone = (user.phone ?? '').trim().toLowerCase();
            final role = normalizeRoleKey(user.role);
            return name.contains(searchQuery) ||
                email.contains(searchQuery) ||
                phone.contains(searchQuery) ||
                role.contains(searchQuery);
          }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(
            _horizontalInset,
            20,
            _horizontalInset,
            0,
          ),
          child: TextField(
            controller: searchController,
            onChanged: (_) => onSearchChanged(),
            decoration: InputDecoration(
              hintText: 'Search user',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        searchController.clear();
                        onSearchChanged();
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(color: AppColors.primaryBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(color: AppColors.primaryBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(color: AppColors.primaryColor),
              ),
            ),
          ),
        ),
        Expanded(
          child: searchQuery.isNotEmpty
              ? (matchingUsers.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: AdminListStateText(
                            message: 'No users matched your search.',
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(
                          _horizontalInset,
                          20,
                          _horizontalInset,
                          16,
                        ),
                        itemCount: matchingUsers.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final user = matchingUsers[index];
                          final thread =
                              latestThreadByUserId[normalizeId(user.id) ?? ''];
                          final normalizedUserId = normalizeId(user.id);
                          final isSelected =
                              normalizeId(selectedDraftUserId) ==
                                  normalizedUserId ||
                              (thread != null &&
                                  (normalizeId(thread.id) ==
                                          normalizeId(selectedThreadId) ||
                                      normalizeId(thread.requesterUserId) ==
                                          normalizeId(selectedDraftUserId)));
                          return _SupportUserThreadTile(
                            currentUser: currentUser,
                            user: user,
                            thread: thread,
                            isUnread: thread != null && isThreadUnread(thread),
                            isSelected: isSelected,
                            onTap: () => onSelectUser(user),
                          );
                        },
                      ))
              : threads.isEmpty
              ? const SizedBox.shrink()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    _horizontalInset,
                    20,
                    _horizontalInset,
                    16,
                  ),
                  itemCount: threads.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final thread = threads[index];
                    return _SupportThreadTile(
                      currentUser: currentUser,
                      thread: thread,
                      requesterUser:
                          usersById[normalizeId(thread.requesterUserId)],
                      isUnread: isThreadUnread(thread),
                      isSelected:
                          normalizeId(thread.id) ==
                          normalizeId(selectedThreadId),
                      onTap: () => onSelect(thread),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SupportUserThreadTile extends StatelessWidget {
  const _SupportUserThreadTile({
    required this.currentUser,
    required this.user,
    required this.thread,
    required this.isUnread,
    required this.isSelected,
    required this.onTap,
  });

  final UserModel currentUser;
  final UserModel user;
  final SupportThread? thread;
  final bool isUnread;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unselectedBorderColor = AppColors.primaryBorder.withValues(
      alpha: 0.58,
    );
    const avatarBorderColor = AppColors.primarySurfaceAlt;
    final title = (user.name ?? '').trim().isNotEmpty
        ? user.name!.trim()
        : 'User';
    final previewText = thread == null
        ? null
        : _supportThreadPreviewText(
            thread: thread!,
            currentUserId: normalizeId(currentUser.id),
          );
    final subtitleParts = <String>[
      humanizeDropdownValue(user.role),
      if (previewText?.isNotEmpty == true) previewText!,
    ];
    final subtitle = subtitleParts.join(' • ');
    final trailingTime = thread == null || !thread!.hasConversation
        ? null
        : _supportThreadListTimestamp(
            thread!.updatedAt ?? thread!.lastMessageAt ?? thread!.createdAt,
          );
    final subtitleWithTimestamp = [
      if (subtitle.trim().isNotEmpty) subtitle.trim(),
      if (trailingTime?.trim().isNotEmpty == true) trailingTime!.trim(),
    ].join(' • ');
    final titleStyle = TextStyle(
      color: AppColors.textPrimary,
      fontWeight: isUnread ? FontWeight.w800 : FontWeight.w600,
    );
    final subtitleStyle = TextStyle(
      color: AppColors.primaryColor.withValues(alpha: isUnread ? 0.88 : 0.68),
      fontWeight: isUnread ? FontWeight.w700 : FontWeight.w500,
    );
    return AppMousePressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? AppColors.primaryColor : unselectedBorderColor,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AppProfileAvatar(
              key: ValueKey<String>(
                'support-user-avatar:${normalizeId(user.id) ?? '-'}:${user.photo?.trim() ?? ''}',
              ),
              radius: 22,
              photo: user.photo,
              fallbackText: _supportInitials(title),
              borderColor: avatarBorderColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          subtitleWithTimestamp,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: subtitleStyle,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportThreadTile extends StatelessWidget {
  const _SupportThreadTile({
    required this.currentUser,
    required this.thread,
    this.requesterUser,
    required this.isUnread,
    required this.isSelected,
    required this.onTap,
  });

  final UserModel currentUser;
  final SupportThread thread;
  final UserModel? requesterUser;
  final bool isUnread;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final requesterPhoto = requesterUser?.photo ?? thread.requesterPhoto;
    final unselectedBorderColor = AppColors.primaryBorder.withValues(
      alpha: 0.58,
    );
    const avatarBorderColor = AppColors.primarySurfaceAlt;
    final title = thread.requesterName?.trim().isNotEmpty == true
        ? thread.requesterName!.trim()
        : (thread.bookingLabel?.trim().isNotEmpty == true
              ? thread.bookingLabel!.trim()
              : 'Support Chat');
    final subtitle = _supportThreadPreviewText(
      thread: thread,
      currentUserId: normalizeId(currentUser.id),
    );
    final trailingTime = thread.hasConversation
        ? _supportThreadListTimestamp(
            thread.updatedAt ?? thread.lastMessageAt ?? thread.createdAt,
          )
        : '';
    final subtitleWithTimestamp = [
      if (subtitle.trim().isNotEmpty) subtitle.trim(),
      if (trailingTime.trim().isNotEmpty) trailingTime.trim(),
    ].join(' • ');
    final titleStyle = TextStyle(
      color: AppColors.textPrimary,
      fontWeight: isUnread ? FontWeight.w800 : FontWeight.w600,
    );
    final subtitleStyle = TextStyle(
      color: AppColors.primaryColor.withValues(alpha: isUnread ? 0.88 : 0.68),
      fontWeight: isUnread ? FontWeight.w700 : FontWeight.w500,
    );
    return AppMousePressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? AppColors.primaryColor : unselectedBorderColor,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AppProfileAvatar(
              key: ValueKey<String>(
                'support-thread-avatar:${normalizeId(thread.id) ?? '-'}:${requesterPhoto?.trim() ?? ''}',
              ),
              radius: 22,
              photo: requesterPhoto,
              fallbackText: _supportInitials(title),
              borderColor: avatarBorderColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          subtitleWithTimestamp,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: subtitleStyle,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportChatPanel extends StatefulWidget {
  const _SupportChatPanel({
    super.key,
    required this.currentUser,
    required this.thread,
    required this.draftUser,
    required this.counterpartUser,
    required this.usersById,
    required this.subtitleOverride,
    required this.onBack,
    required this.messageController,
    required this.pendingAttachments,
    required this.isSending,
    required this.onPickAttachments,
    required this.onRemovePendingAttachment,
    required this.onSend,
    required this.canCompose,
    required this.supportRequest,
    required this.onMessagesVisible,
    required this.scrollController,
    required this.scrollRequestTick,
  });

  final UserModel currentUser;
  final SupportThread? thread;
  final UserModel? draftUser;
  final UserModel? counterpartUser;
  final Map<String, UserModel> usersById;
  final String? subtitleOverride;
  final VoidCallback? onBack;
  final TextEditingController messageController;
  final List<_PendingSupportAttachment> pendingAttachments;
  final bool isSending;
  final Future<void> Function() onPickAttachments;
  final ValueChanged<int> onRemovePendingAttachment;
  final Future<void> Function() onSend;
  final bool canCompose;
  final SupportRequest supportRequest;
  final ValueChanged<List<SupportMessage>> onMessagesVisible;
  final ScrollController scrollController;
  final int scrollRequestTick;

  @override
  State<_SupportChatPanel> createState() => _SupportChatPanelState();
}

class _SupportChatPanelState extends State<_SupportChatPanel> {
  int _lastMessageCount = 0;
  int _lastScrollRequestTick = 0;
  String? _lastLatestMessageSignature;
  String? _lastReadNotificationSignature;
  late bool _hasComposerContent;

  @override
  void initState() {
    super.initState();
    _lastScrollRequestTick = widget.scrollRequestTick;
    _hasComposerContent = widget.messageController.text.trim().isNotEmpty;
    widget.messageController.addListener(_handleComposerChanged);
  }

  @override
  void didUpdateWidget(covariant _SupportChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messageController != widget.messageController) {
      oldWidget.messageController.removeListener(_handleComposerChanged);
      widget.messageController.addListener(_handleComposerChanged);
      _hasComposerContent = widget.messageController.text.trim().isNotEmpty;
    }
    if (widget.scrollRequestTick != _lastScrollRequestTick) {
      _lastScrollRequestTick = widget.scrollRequestTick;
      _scheduleScrollToLatest();
    }
    if (normalizeId(oldWidget.thread?.id) != normalizeId(widget.thread?.id)) {
      _lastReadNotificationSignature = null;
    }
  }

  @override
  void dispose() {
    widget.messageController.removeListener(_handleComposerChanged);
    super.dispose();
  }

  void _handleComposerChanged() {
    final nextHasContent = widget.messageController.text.trim().isNotEmpty;
    if (nextHasContent == _hasComposerContent) {
      return;
    }
    setState(() {
      _hasComposerContent = nextHasContent;
    });
  }

  void _scheduleScrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _scrollToLatest();
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (!mounted) {
          return;
        }
        _scrollToLatest();
      });
    });
  }

  void _scrollToLatest() {
    if (!widget.scrollController.hasClients) {
      return;
    }
    final position = widget.scrollController.position;
    widget.scrollController.animateTo(
      position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final canTriggerSend =
        widget.canCompose &&
        (_hasComposerContent || widget.pendingAttachments.isNotEmpty);
    if (widget.thread == null && widget.draftUser == null) {
      return const SizedBox.shrink();
    }

    final activeTitle = widget.counterpartUser?.name?.trim().isNotEmpty == true
        ? widget.counterpartUser!.name!.trim()
        : widget.thread != null
        ? _threadTitle(widget.thread!, widget.currentUser)
        : ((widget.draftUser?.name ?? '').trim().isNotEmpty
              ? widget.draftUser!.name!.trim()
              : 'Support Chat');
    final activeSubtitle =
        widget.subtitleOverride ??
        (widget.thread != null
            ? _threadSubtitle(widget.thread!)
            : humanizeDropdownValue(widget.draftUser?.role));
    const rolesWithoutChatHeader = <String>{'client', 'driver', 'helper'};
    final showChatHeader = !rolesWithoutChatHeader.contains(
      widget.currentUser.role?.trim().toLowerCase(),
    );

    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showChatHeader)
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.primaryBorder),
                ),
              ),
              child: Row(
                children: [
                  if (widget.onBack != null) ...[
                    IconButton(
                      onPressed: widget.onBack,
                      icon: const Icon(Icons.arrow_back_rounded),
                      color: AppColors.primaryColor,
                      splashRadius: 20,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 10),
                  ],
                  AppProfileAvatar(
                    key: ValueKey<String>(
                      'support-header-avatar:${normalizeId(widget.counterpartUser?.id) ?? normalizeId(widget.thread?.requesterUserId) ?? normalizeId(widget.draftUser?.id) ?? '-'}:${(widget.counterpartUser?.photo ?? widget.thread?.requesterPhoto ?? widget.draftUser?.photo ?? '').trim()}',
                    ),
                    radius: 22,
                    photo:
                        widget.counterpartUser?.photo ??
                        widget.thread?.requesterPhoto ??
                        widget.draftUser?.photo,
                    fallbackText: _supportInitials(activeTitle),
                    borderColor: AppColors.primarySurfaceAlt,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          activeTitle,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          activeSubtitle,
                          style: TextStyle(
                            color: AppColors.primaryColor.withValues(
                              alpha: 0.72,
                            ),
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: widget.thread == null
                ? const ColoredBox(
                    color: Color(0xFFF8F7FC),
                    child: Center(
                      child: AdminListStateText(
                        message:
                            'Send the first message to start this support conversation.',
                      ),
                    ),
                  )
                : StreamBuilder<List<SupportMessage>>(
                    key: ValueKey('messages:${widget.thread!.id ?? ''}'),
                    initialData: widget.supportRequest.peekLastVisibleMessages(
                      widget.thread!.id ?? '',
                    ),
                    stream: widget.supportRequest.watchMessages(
                      widget.thread!.id ?? '',
                    ),
                    builder: (context, snapshot) {
                      final messages =
                          snapshot.data ?? const <SupportMessage>[];
                      final latestMessageSignature = messages.isEmpty
                          ? null
                          : _supportMessageSignature(messages.last);
                      if (messages.length != _lastMessageCount ||
                          latestMessageSignature !=
                              _lastLatestMessageSignature) {
                        _lastMessageCount = messages.length;
                        _lastLatestMessageSignature = latestMessageSignature;
                        _scheduleScrollToLatest();
                      }
                      if (latestMessageSignature != null &&
                          latestMessageSignature !=
                              _lastReadNotificationSignature) {
                        _lastReadNotificationSignature = latestMessageSignature;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) {
                            return;
                          }
                          widget.onMessagesVisible(messages);
                        });
                      }
                      final threadHasKnownConversation =
                          widget.thread?.hasConversation == true;
                      final shouldShowInitialLoading =
                          messages.isEmpty &&
                          (threadHasKnownConversation ||
                              !snapshot.hasData ||
                              snapshot.connectionState !=
                                  ConnectionState.active);
                      if (shouldShowInitialLoading) {
                        return const Center(
                          child: AdminListStateText(
                            message: 'Loading messages ...',
                          ),
                        );
                      }
                      if (messages.isEmpty) {
                        return const Center(
                          child: AdminListStateText(
                            message:
                                'No messages yet. Start the conversation here.',
                          ),
                        );
                      }
                      return Container(
                        color: const Color(0xFFF8F7FC),
                        child: ListView.builder(
                          controller: widget.scrollController,
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final message = messages[index];
                            final isMine =
                                normalizeId(message.senderUserId) ==
                                normalizeId(widget.currentUser.id);
                            final nextMessage = index < messages.length - 1
                                ? messages[index + 1]
                                : null;
                            final showTimestampHeader =
                                _shouldShowSupportMessageTimestampHeader(
                                  messages: messages,
                                  index: index,
                                );
                            final isFollowedBySameVisualGroup =
                                nextMessage != null &&
                                _isSameSupportMessageVisualGroup(
                                  current: message,
                                  next: nextMessage,
                                );
                            return Column(
                              children: [
                                if (showTimestampHeader) ...[
                                  Center(
                                    child: Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Text(
                                        _supportMessageTimestampForBubble(
                                          message,
                                        ),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: AppColors.primaryColor
                                              .withValues(alpha: 0.64),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                Padding(
                                  padding: EdgeInsets.only(
                                    bottom: index == messages.length - 1
                                        ? 0
                                        : (isFollowedBySameVisualGroup
                                              ? 6
                                              : 12),
                                  ),
                                  child: _SupportMessageBubble(
                                    currentUser: widget.currentUser,
                                    primaryCounterpartUserId:
                                        widget.counterpartUser?.id ??
                                        widget.thread?.requesterUserId ??
                                        widget.draftUser?.id,
                                    message: message,
                                    senderUser:
                                        widget.usersById[normalizeId(
                                          message.senderUserId,
                                        )],
                                    isMine: isMine,
                                    showSenderMeta:
                                        _shouldShowSupportMessageSenderMeta(
                                          messages: messages,
                                          index: index,
                                          currentUser: widget.currentUser,
                                          primaryCounterpartUserId:
                                              widget.counterpartUser?.id ??
                                              widget.thread?.requesterUserId ??
                                              widget.draftUser?.id,
                                        ),
                                    showAvatar: _shouldShowSupportMessageAvatar(
                                      messages: messages,
                                      index: index,
                                      currentUser: widget.currentUser,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.primaryBorder)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.pendingAttachments.isNotEmpty) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.pendingAttachments.asMap().entries.map((
                      entry,
                    ) {
                      return _PendingAttachmentPreviewCard(
                        attachment: entry.value,
                        onRemove: () =>
                            widget.onRemovePendingAttachment(entry.key),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: widget.canCompose
                          ? widget.onPickAttachments
                          : null,
                      icon: const Icon(Icons.attach_file_rounded),
                      color: AppColors.primaryColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Focus(
                        onKeyEvent: (node, event) {
                          final isEnter =
                              event.logicalKey == LogicalKeyboardKey.enter ||
                              event.logicalKey ==
                                  LogicalKeyboardKey.numpadEnter;
                          if (event is KeyDownEvent) {}
                          if (event is KeyDownEvent &&
                              isEnter &&
                              !HardwareKeyboard.instance.isShiftPressed) {
                            if (widget.canCompose && canTriggerSend) {
                              widget.onSend();
                            }
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: TextField(
                          controller: widget.messageController,
                          onChanged: (_) {
                            if (!mounted) {
                              return;
                            }
                            final nextHasContent = widget.messageController.text
                                .trim()
                                .isNotEmpty;
                            if (nextHasContent == _hasComposerContent) {
                              return;
                            }
                            setState(() {
                              _hasComposerContent = nextHasContent;
                            });
                          },
                          minLines: 1,
                          maxLines: 4,
                          enabled: widget.canCompose,
                          decoration: InputDecoration(
                            hintText: widget.canCompose
                                ? 'Type your message'
                                : 'Messaging is unavailable for this role',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: const BorderSide(
                                color: AppColors.primaryBorder,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: const BorderSide(
                                color: AppColors.primaryBorder,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: const BorderSide(
                                color: AppColors.primaryColor,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: widget.canCompose && canTriggerSend
                          ? () {
                              widget.onSend();
                            }
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 18,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: const Text('Send'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _threadTitle(SupportThread thread, UserModel currentUser) {
    final requesterName = thread.requesterName?.trim();
    if (isBackOfficeRole(currentUser.role) &&
        requesterName != null &&
        requesterName.isNotEmpty) {
      return requesterName;
    }
    if (thread.bookingLabel?.trim().isNotEmpty == true) {
      return thread.bookingLabel!.trim();
    }
    return thread.resolvedTopicLabel;
  }

  static String _threadSubtitle(SupportThread thread) {
    return humanizeDropdownValue(thread.requesterRole);
  }
}

class _SupportMessageBubble extends StatelessWidget {
  const _SupportMessageBubble({
    required this.currentUser,
    required this.primaryCounterpartUserId,
    required this.message,
    this.senderUser,
    required this.isMine,
    required this.showSenderMeta,
    required this.showAvatar,
  });

  final UserModel currentUser;
  final String? primaryCounterpartUserId;
  final SupportMessage message;
  final UserModel? senderUser;
  final bool isMine;
  final bool showSenderMeta;
  final bool showAvatar;

  @override
  Widget build(BuildContext context) {
    final bubbleColor = isMine
        ? AppColors.primaryColor
        : AppColors.primarySurface;
    final textColor = isMine ? Colors.white : AppColors.textPrimary;
    final hasText = message.text?.trim().isNotEmpty == true;
    final imageAttachments = message.attachments
        .where((attachment) => attachment.isImage)
        .toList(growable: false);
    final fileAttachments = message.attachments
        .where((attachment) => !attachment.isImage)
        .toList(growable: false);
    final hasBubbleContent = hasText || fileAttachments.isNotEmpty;
    final canShowSenderMeta = !isMine;
    final resolvedSenderName = senderUser?.name ?? message.senderName;
    final senderName = (resolvedSenderName?.trim().isNotEmpty == true)
        ? _supportShortPersonName(resolvedSenderName!)
        : (() {
            final fallback = humanizeDropdownValue(
              senderUser?.role ?? message.senderRole,
            );
            return fallback.trim().isNotEmpty ? fallback : 'Support';
          })();
    final senderRoleLabel = humanizeDropdownValue(
      senderUser?.role ?? message.senderRole,
    ).trim();
    final senderMetaLabel = senderRoleLabel.isNotEmpty
        ? '$senderName | $senderRoleLabel'
        : senderName;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: isMine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (canShowSenderMeta && showSenderMeta) ...[
              Padding(
                padding: const EdgeInsets.only(left: 40),
                child: Text(
                  senderMetaLabel,
                  style: TextStyle(
                    color: AppColors.primaryColor.withValues(alpha: 0.82),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ],
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (canShowSenderMeta) ...[
                  if (showAvatar)
                    AppProfileAvatar(
                      key: ValueKey<String>(
                        'support-message-avatar:${normalizeId(message.id) ?? '-'}:${normalizeId(message.senderUserId) ?? '-'}:${(senderUser?.photo ?? message.senderPhoto ?? '').trim()}',
                      ),
                      radius: 16,
                      photo: senderUser?.photo ?? message.senderPhoto,
                      fallbackText: _supportInitials(senderName),
                      borderColor: AppColors.primarySurfaceAlt,
                    )
                  else
                    const SizedBox(width: 32),
                  const SizedBox(width: 8),
                ],
                if (hasBubbleContent || imageAttachments.isNotEmpty)
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (hasBubbleContent)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: bubbleColor,
                              borderRadius: BorderRadius.circular(18),
                              border: isMine
                                  ? null
                                  : Border.all(color: AppColors.primaryBorder),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (hasText)
                                  Text(
                                    message.text!.trim(),
                                    style: TextStyle(
                                      color: textColor,
                                      height: 1.35,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                if (fileAttachments.isNotEmpty) ...[
                                  if (hasText) const SizedBox(height: 10),
                                  ...fileAttachments.asMap().entries.map((
                                    entry,
                                  ) {
                                    return Padding(
                                      padding: EdgeInsets.only(
                                        bottom:
                                            entry.key ==
                                                fileAttachments.length - 1
                                            ? 0
                                            : 10,
                                      ),
                                      child: _SupportAttachmentCard(
                                        attachment: entry.value,
                                        lightText: isMine,
                                      ),
                                    );
                                  }),
                                ],
                              ],
                            ),
                          ),
                        if (imageAttachments.isNotEmpty) ...[
                          if (hasBubbleContent) const SizedBox(height: 10),
                          ...imageAttachments.asMap().entries.map((entry) {
                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: entry.key == imageAttachments.length - 1
                                    ? 0
                                    : 10,
                              ),
                              child: _SupportAttachmentCard(
                                attachment: entry.value,
                                lightText: isMine,
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportAttachmentCard extends StatelessWidget {
  const _SupportAttachmentCard({
    required this.attachment,
    required this.lightText,
  });

  final SupportAttachment attachment;
  final bool lightText;

  @override
  Widget build(BuildContext context) {
    final downloadUrl = attachment.downloadUrl?.trim();
    final textColor = lightText ? Colors.white : AppColors.textPrimary;
    final borderColor = lightText
        ? Colors.white.withValues(alpha: 0.24)
        : AppColors.primaryBorder;
    final backgroundColor = lightText
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white;
    if (attachment.isImage && downloadUrl != null && downloadUrl.isNotEmpty) {
      const imageSize = 220.0;
      final placeholderColor = lightText
          ? AppColors.primaryColor
          : AppColors.primaryColor.withValues(alpha: 0.92);
      final placeholderBorderColor = lightText
          ? Colors.white.withValues(alpha: 0.28)
          : AppColors.primaryColor;
      return AppMousePressable(
        onTap: () {
          showAppImageViewer(
            context,
            title: attachment.name ?? 'Attachment',
            imageUrl: downloadUrl,
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: imageSize,
            width: imageSize,
            decoration: BoxDecoration(
              color: placeholderColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: placeholderBorderColor),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: Icon(
                    Icons.image_rounded,
                    color: Colors.white.withValues(alpha: 0.92),
                    size: 40,
                  ),
                ),
                AppCachedNetworkImage(
                  imageUrl: downloadUrl,
                  height: imageSize,
                  width: imageSize,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error) {
                    return Container(
                      height: imageSize,
                      width: imageSize,
                      color: AppColors.primaryColor.withValues(alpha: 0.92),
                      alignment: Alignment.center,
                      child: const Text(
                        'Image unavailable',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (attachment.isImage) {
      const imageSize = 220.0;
      final placeholderColor = lightText
          ? AppColors.primaryColor
          : AppColors.primaryColor.withValues(alpha: 0.92);
      final placeholderBorderColor = lightText
          ? Colors.white.withValues(alpha: 0.28)
          : AppColors.primaryColor;
      return Container(
        height: imageSize,
        width: imageSize,
        decoration: BoxDecoration(
          color: placeholderColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: placeholderBorderColor),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.image_rounded,
              color: Colors.white.withValues(alpha: 0.92),
              size: 42,
            ),
            const SizedBox(height: 10),
            Text(
              'Photo sending',
              style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
    }
    return AppMousePressable(
      onTap: downloadUrl == null || downloadUrl.isEmpty
          ? null
          : () async {
              await launchUrl(Uri.parse(downloadUrl));
            },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              attachment.name?.trim().isNotEmpty == true
                  ? attachment.name!.trim()
                  : 'Attachment',
              style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingAttachmentPreviewCard extends StatelessWidget {
  const _PendingAttachmentPreviewCard({
    required this.attachment,
    required this.onRemove,
  });

  final _PendingSupportAttachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final isImage = _isImageFileName(attachment.fileName, attachment.mimeType);
    if (isImage) {
      return Stack(
        children: [
          AppMousePressable(
            onTap: () {
              showAppImageViewer(
                context,
                title: attachment.fileName,
                memoryBytes: attachment.bytes,
              );
            },
            borderRadius: BorderRadius.circular(16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: AppColors.primaryColor.withValues(alpha: 0.12),
                  border: Border.all(color: AppColors.primaryBorder),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Image.memory(
                  attachment.bytes,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: AppColors.primaryColor.withValues(alpha: 0.14),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.image_rounded,
                        color: AppColors.primaryColor,
                        size: 28,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: AppMousePressable(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.58),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.primaryBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            attachment.fileName,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          AppMousePressable(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(999),
            child: const Icon(
              Icons.close_rounded,
              size: 16,
              color: AppColors.dangerStrong,
            ),
          ),
        ],
      ),
    );
  }
}

bool _isImageFileName(String fileName, String? mimeType) {
  final normalizedMime = mimeType?.trim().toLowerCase() ?? '';
  if (normalizedMime.startsWith('image/')) {
    return true;
  }
  final normalizedName = fileName.trim().toLowerCase();
  return normalizedName.endsWith('.png') ||
      normalizedName.endsWith('.jpg') ||
      normalizedName.endsWith('.jpeg') ||
      normalizedName.endsWith('.gif') ||
      normalizedName.endsWith('.webp') ||
      normalizedName.endsWith('.bmp');
}

class _SupportTopicDropdown extends StatelessWidget {
  const _SupportTopicDropdown({
    required this.selectedTopicKey,
    required this.onChanged,
  });

  final String selectedTopicKey;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return AdminDropdownFormField<String>(
      initialValue: selectedTopicKey,
      iconEnabledColor: AppColors.primaryColor,
      style: adminDropdownDisplayTextStyle,
      decoration: adminPlainDropdownDecoration('Topic', radius: 16).copyWith(
        constraints: const BoxConstraints(minHeight: adminModalFieldMinHeight),
      ),
      items: supportTopicKeys
          .map(
            (topicKey) => DropdownMenuItem<String>(
              value: topicKey,
              child: Text(
                supportTopicLabel(topicKey),
                style: adminDropdownDisplayTextStyle,
              ),
            ),
          )
          .toList(growable: false),
      onChanged: (value) {
        if (value == null) {
          return;
        }
        onChanged(value);
      },
    );
  }
}

class _SupportBookingDropdown extends StatelessWidget {
  const _SupportBookingDropdown({
    required this.bookings,
    required this.selectedBookingId,
    required this.onChanged,
  });

  final List<Booking> bookings;
  final String? selectedBookingId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return AdminDropdownFormField<String>(
      initialValue: selectedBookingId,
      iconEnabledColor: AppColors.primaryColor,
      style: adminDropdownDisplayTextStyle,
      decoration: adminPlainDropdownDecoration('Booking', radius: 16).copyWith(
        constraints: const BoxConstraints(minHeight: adminModalFieldMinHeight),
      ),
      items: bookings
          .map((booking) {
            final value = booking.id ?? '';
            return DropdownMenuItem<String>(
              value: value,
              child: Text(
                _bookingDisplayLabel(booking),
                style: adminDropdownDisplayTextStyle,
              ),
            );
          })
          .toList(growable: false),
      onChanged: onChanged,
    );
  }
}

List<Booking> _accessibleBookingsForUser(
  UserModel user,
  List<Booking> allBookings,
) {
  final currentUserId = normalizeId(user.id) ?? '';
  return switch (normalizeRoleKey(user.role)) {
    'client' =>
      allBookings
          .where((booking) => normalizeId(booking.client?.id) == currentUserId)
          .toList(),
    'driver' =>
      allBookings
          .where((booking) => normalizeId(booking.driver?.id) == currentUserId)
          .toList(),
    'helper' =>
      allBookings
          .where((booking) => normalizeId(booking.helper?.id) == currentUserId)
          .toList(),
    _ => const <Booking>[],
  };
}

String _bookingDisplayLabel(Booking booking) {
  final bookingId = booking.id?.trim();
  final status = booking.clientStatus?.trim();
  if (bookingId == null || bookingId.isEmpty) {
    return status?.isNotEmpty == true ? status! : 'Booking';
  }
  if (status?.isNotEmpty == true) {
    return 'Booking $bookingId • ${humanizeDropdownValue(status!)}';
  }
  return 'Booking $bookingId';
}

String _supportInitials(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .toList();
  if (parts.isEmpty) {
    return 'S';
  }
  return parts.map((part) => part.substring(0, 1).toUpperCase()).join();
}

String _supportShortPersonName(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) {
    return 'Support';
  }
  if (parts.length == 1) {
    return toTitleCase(parts.first);
  }
  final firstName = toTitleCase(parts.first);
  final lastInitial = parts.last.substring(0, 1).toUpperCase();
  return '$firstName $lastInitial.';
}

String _supportThreadPreviewText({
  required SupportThread thread,
  required String? currentUserId,
}) {
  final preview = _supportSingleLineText(thread.lastMessageText);
  if (preview.isEmpty) {
    return '';
  }
  if (normalizeId(thread.lastSenderUserId) == currentUserId) {
    return 'You: $preview';
  }
  return preview;
}

String _supportSingleLineText(String? value) {
  if (value == null) {
    return '';
  }
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

bool _shouldShowSupportMessageTimestampHeader({
  required List<SupportMessage> messages,
  required int index,
}) {
  if (index < 0 || index >= messages.length) {
    return false;
  }
  final currentLabel = _supportMessageTimestampForBubble(messages[index]);
  if (currentLabel.isEmpty) {
    return false;
  }
  if (index == 0) {
    return true;
  }
  final previousLabel = _supportMessageTimestampForBubble(messages[index - 1]);
  return currentLabel != previousLabel;
}

bool _shouldShowSupportMessageSenderMeta({
  required List<SupportMessage> messages,
  required int index,
  required UserModel currentUser,
  required String? primaryCounterpartUserId,
}) {
  final message = messages[index];
  final currentUserId = normalizeId(currentUser.id);
  final senderId = normalizeId(message.senderUserId);
  if (senderId == null || senderId == currentUserId) {
    return false;
  }
  if (index == 0) {
    return true;
  }
  final previousMessage = messages[index - 1];
  final previousSenderId = normalizeId(previousMessage.senderUserId);
  if (previousSenderId != senderId) {
    return true;
  }
  return _supportMessageTimestampForBubble(previousMessage) !=
      _supportMessageTimestampForBubble(message);
}

bool _shouldShowSupportMessageAvatar({
  required List<SupportMessage> messages,
  required int index,
  required UserModel currentUser,
}) {
  final message = messages[index];
  final currentUserId = normalizeId(currentUser.id);
  final senderId = normalizeId(message.senderUserId);
  if (senderId == null || senderId == currentUserId) {
    return false;
  }
  if (index == messages.length - 1) {
    return true;
  }
  final nextMessage = messages[index + 1];
  final nextSenderId = normalizeId(nextMessage.senderUserId);
  if (nextSenderId != senderId) {
    return true;
  }
  return _supportMessageTimestampForBubble(nextMessage) !=
      _supportMessageTimestampForBubble(message);
}

bool _isSameSupportMessageVisualGroup({
  required SupportMessage current,
  required SupportMessage next,
}) {
  return normalizeId(current.senderUserId) == normalizeId(next.senderUserId) &&
      _supportMessageTimestampForBubble(current) ==
          _supportMessageTimestampForBubble(next);
}

String _supportTimeLabel(DateTime? value) {
  if (value == null) {
    return '';
  }
  final local = value.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final suffix = local.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $suffix';
}

String _supportThreadListTimestamp(DateTime? value) {
  if (value == null) {
    return '';
  }
  final local = value.toLocal();
  final now = DateTime.now();
  final localDate = DateTime(local.year, local.month, local.day);
  final todayDate = DateTime(now.year, now.month, now.day);
  final difference = todayDate.difference(localDate).inDays;
  if (difference == 0) {
    return _supportTimeLabel(local);
  }
  if (_isSameCalendarWeek(localDate, todayDate)) {
    return _weekdayShortLabel(local.weekday);
  }
  if (local.year == now.year) {
    return '${_monthLabel(local.month)} ${local.day.toString().padLeft(2, '0')}';
  }
  return '${_monthLabel(local.month)} ${local.day.toString().padLeft(2, '0')} ${local.year}';
}

String _supportMessageTimestampForBubble(SupportMessage message) {
  if (message.isPendingUpload) {
    return 'Sending';
  }
  return _supportMessageTimestampLabel(message.createdAt ?? message.updatedAt);
}

String _supportMessageSignature(SupportMessage message) {
  return [
    message.id?.trim() ?? '',
    message.localOrderKey?.trim() ?? '',
    message.senderUserId?.trim() ?? '',
    message.createdAt?.toIso8601String() ?? '',
    message.updatedAt?.toIso8601String() ?? '',
    message.text?.trim() ?? '',
    '${message.attachments.length}',
  ].join('|');
}

String _supportMessageTimestampLabel(DateTime? value) {
  if (value == null) {
    return '';
  }
  final local = value.toLocal();
  final now = DateTime.now();
  final localDate = DateTime(local.year, local.month, local.day);
  final todayDate = DateTime(now.year, now.month, now.day);
  final difference = todayDate.difference(localDate).inDays;
  final time = _supportTimeLabel(local);
  if (difference == 0) {
    return time;
  }
  final month = _monthLabel(local.month);
  return '$month ${local.day}, ${local.year} $time';
}

bool _isSameCalendarWeek(DateTime left, DateTime right) {
  final leftWeekStart = left.subtract(Duration(days: left.weekday - 1));
  final rightWeekStart = right.subtract(Duration(days: right.weekday - 1));
  return leftWeekStart.year == rightWeekStart.year &&
      leftWeekStart.month == rightWeekStart.month &&
      leftWeekStart.day == rightWeekStart.day;
}

String _monthLabel(int month) {
  return switch (month) {
    1 => 'Jan',
    2 => 'Feb',
    3 => 'Mar',
    4 => 'Apr',
    5 => 'May',
    6 => 'Jun',
    7 => 'Jul',
    8 => 'Aug',
    9 => 'Sep',
    10 => 'Oct',
    11 => 'Nov',
    12 => 'Dec',
    _ => '',
  };
}

String _weekdayShortLabel(int weekday) {
  return switch (weekday) {
    DateTime.monday => 'Mon',
    DateTime.tuesday => 'Tue',
    DateTime.wednesday => 'Wed',
    DateTime.thursday => 'Thu',
    DateTime.friday => 'Fri',
    DateTime.saturday => 'Sat',
    DateTime.sunday => 'Sun',
    _ => '',
  };
}

String? _fileMimeTypeFromExtension(String extension) {
  return switch (extension.trim().toLowerCase()) {
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'bmp' => 'image/bmp',
    'pdf' => 'application/pdf',
    'txt' => 'text/plain',
    'doc' => 'application/msword',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    _ => null,
  };
}
