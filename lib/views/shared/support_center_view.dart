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
import 'package:webapp/services/network_status_events.dart';
import 'package:webapp/services/offline_media_sync_service.dart';
import 'package:webapp/utils/functions.dart';
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
  final SupportRequest _supportRequest = SupportRequest.instance;
  final BookingRequest _bookingRequest = BookingRequest.instance;
  final AuthRequest _authRequest = AuthRequest.instance;
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
  List<_PendingSupportAttachment> _pendingAttachments = const [];
  String? _pendingInitialAdminUserId;
  int _chatScrollRequestTick = 0;

  bool get _isAdmin => isBackOfficeRole(widget.user.role);

  @override
  void initState() {
    super.initState();
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

  Future<void> _loadAccessibleBookings() async {
    if (_isAdmin) {
      return;
    }
    setState(() {
      _isLoadingBookings = true;
    });
    try {
      await _bookingRequest.initialize();
      final allBookings = await _bookingRequest.getBookings();
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
        final hasSelectedBooking = filtered.any(
          (booking) =>
              normalizeId(booking.id) == normalizeId(_selectedBookingId),
        );
        if (!hasSelectedBooking) {
          _selectedBookingId = null;
        }
      });
    } catch (error) {
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
    }
  }

  Future<void> _loadAdminUsers() async {
    setState(() {
      _isLoadingAdminUsers = true;
    });
    try {
      final users = await _authRequest.getUsers();
      if (!mounted) {
        return;
      }
      final currentUserId = normalizeId(widget.user.id);
      final filtered =
          users.where((user) {
            final userId = normalizeId(user.id);
            return userId != null && userId != currentUserId;
          }).toList()..sort((left, right) {
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
      setState(() {
        _adminUsers = filtered;
      });
      await _applyPendingInitialAdminUser(filtered);
    } catch (error) {
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
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAdminUsers = false;
        });
      }
    }
  }

  Future<void> _applyPendingInitialAdminUser(List<UserModel> users) async {
    final targetUserId = normalizeId(_pendingInitialAdminUserId);
    if (targetUserId == null) {
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
      final thread = await _supportRequest.findAdminDirectThread(
        targetUser: targetUser,
      );
      if (!mounted) {
        _pendingInitialAdminUserId = null;
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
    setState(() {
      _isLoadingSupportAgent = true;
    });
    try {
      final users = await _authRequest.getUsers();
      if (!mounted) {
        return;
      }
      final supportAgent = users.where((user) {
        return normalizeId(user.id) == '1';
      }).firstOrNull;
      setState(() {
        _supportAgentUser = supportAgent;
      });
    } catch (error) {
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
    if (_isAdmin && threadId == null && _selectedAdminDraftUser != null) {
      try {
        final thread = await _supportRequest.ensureAdminDirectThread(
          targetUser: _selectedAdminDraftUser!,
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _selectedThreadId = thread.id;
          _selectedAdminDraftUser = null;
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
    final shouldLockComposer = currentNetworkStatus();

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
      if (mounted && shouldLockComposer) {
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
    final content = _isAdmin
        ? StreamBuilder<List<SupportThread>>(
            stream: _supportRequest.watchAllThreads(),
            builder: (context, snapshot) {
              final threads = (snapshot.data ?? const <SupportThread>[])
                  .where((thread) => thread.hasConversation)
                  .toList();
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
    return AppPageLoadingOverlay(
      isVisible: isLoading,
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
                        onSearchChanged: () => setState(() {}),
                        onSelect: (thread) {
                          setState(() {
                            _selectedThreadId = thread.id;
                            _selectedAdminDraftUser = null;
                            _showMobileChat = true;
                          });
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
                        selectedTopicKey: _selectedTopicKey,
                        selectedBookingId: _selectedBookingId,
                        accessibleBookings: _accessibleBookings,
                        onSelectThread: (thread) {
                          setState(() {
                            _selectedThreadId = thread.id;
                            _showMobileChat = true;
                          });
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
                  counterpartUser: _isAdmin ? null : _supportAgentUser,
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
                  supportRequest: _supportRequest,
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
                                      counterpartUser: null,
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
                                      supportRequest: _supportRequest,
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
    required this.onSearchChanged,
    required this.onSelect,
    required this.onSelectUser,
  });

  final UserModel currentUser;
  final List<SupportThread> threads;
  final List<UserModel> users;
  final TextEditingController searchController;
  final String? selectedThreadId;
  final VoidCallback onSearchChanged;
  final ValueChanged<SupportThread> onSelect;
  final ValueChanged<UserModel> onSelectUser;

  static const double _horizontalInset = 20;

  @override
  Widget build(BuildContext context) {
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
                          final isSelected =
                              thread != null &&
                              normalizeId(thread.id) ==
                                  normalizeId(selectedThreadId);
                          return _SupportUserThreadTile(
                            currentUser: currentUser,
                            user: user,
                            thread: thread,
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
    required this.isSelected,
    required this.onTap,
  });

  final UserModel currentUser;
  final UserModel user;
  final SupportThread? thread;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
    final trailingTime = thread == null
        ? null
        : _supportThreadListTimestamp(
            thread!.updatedAt ?? thread!.lastMessageAt ?? thread!.createdAt,
          );
    final showUnreadDot =
        thread != null &&
        !isSelected &&
        _supportThreadHasUnreadLikeState(
          thread: thread!,
          currentUserId: normalizeId(currentUser.id),
        );
    return AppMousePressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEDE7FF) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryColor
                : AppColors.primaryBorder,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AppProfileAvatar(
              radius: 22,
              photo: user.photo,
              fallbackText: _supportInitials(title),
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
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (showUnreadDot) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.primaryColor.withValues(
                              alpha: 0.72,
                            ),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (trailingTime != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          trailingTime,
                          style: TextStyle(
                            color: AppColors.primaryColor.withValues(
                              alpha: 0.6,
                            ),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
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
    required this.isSelected,
    required this.onTap,
  });

  final UserModel currentUser;
  final SupportThread thread;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = thread.requesterName?.trim().isNotEmpty == true
        ? thread.requesterName!.trim()
        : (thread.bookingLabel?.trim().isNotEmpty == true
              ? thread.bookingLabel!.trim()
              : 'Support Chat');
    final subtitle = _supportThreadPreviewText(
      thread: thread,
      currentUserId: normalizeId(currentUser.id),
    );
    final trailingTime = _supportThreadListTimestamp(
      thread.updatedAt ?? thread.lastMessageAt ?? thread.createdAt,
    );
    final showUnreadDot =
        !isSelected &&
        _supportThreadHasUnreadLikeState(
          thread: thread,
          currentUserId: normalizeId(currentUser.id),
        );
    return AppMousePressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEDE7FF) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryColor
                : AppColors.primaryBorder,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AppProfileAvatar(
              radius: 22,
              photo: thread.requesterPhoto,
              fallbackText: _supportInitials(title),
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
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (showUnreadDot) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.primaryColor.withValues(
                              alpha: 0.72,
                            ),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (trailingTime.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          trailingTime,
                          style: TextStyle(
                            color: AppColors.primaryColor.withValues(
                              alpha: 0.6,
                            ),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
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
    required this.subtitleOverride,
    required this.onBack,
    required this.messageController,
    required this.pendingAttachments,
    required this.isSending,
    required this.onPickAttachments,
    required this.onRemovePendingAttachment,
    required this.onSend,
    required this.supportRequest,
    required this.scrollController,
    required this.scrollRequestTick,
  });

  final UserModel currentUser;
  final SupportThread? thread;
  final UserModel? draftUser;
  final UserModel? counterpartUser;
  final String? subtitleOverride;
  final VoidCallback? onBack;
  final TextEditingController messageController;
  final List<_PendingSupportAttachment> pendingAttachments;
  final bool isSending;
  final Future<void> Function() onPickAttachments;
  final ValueChanged<int> onRemovePendingAttachment;
  final Future<void> Function() onSend;
  final SupportRequest supportRequest;
  final ScrollController scrollController;
  final int scrollRequestTick;

  @override
  State<_SupportChatPanel> createState() => _SupportChatPanelState();
}

class _SupportChatPanelState extends State<_SupportChatPanel> {
  int _lastMessageCount = 0;
  int _lastScrollRequestTick = 0;
  String? _lastLatestMessageSignature;

  @override
  void initState() {
    super.initState();
    _lastScrollRequestTick = widget.scrollRequestTick;
  }

  @override
  void didUpdateWidget(covariant _SupportChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scrollRequestTick != _lastScrollRequestTick) {
      _lastScrollRequestTick = widget.scrollRequestTick;
      _scheduleScrollToLatest();
    }
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
    final canCompose = !widget.isSending || !currentNetworkStatus();
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

    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                  radius: 22,
                  photo:
                      widget.counterpartUser?.photo ??
                      widget.thread?.requesterPhoto ??
                      widget.draftUser?.photo,
                  fallbackText: _supportInitials(activeTitle),
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
                          color: AppColors.primaryColor.withValues(alpha: 0.72),
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
                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: index == messages.length - 1 ? 0 : 12,
                              ),
                              child: _SupportMessageBubble(
                                currentUser: widget.currentUser,
                                primaryCounterpartUserId:
                                    widget.counterpartUser?.id ??
                                    widget.thread?.requesterUserId ??
                                    widget.draftUser?.id,
                                message: message,
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
                                showTimestamp:
                                    _shouldShowSupportMessageTimestamp(
                                      messages: messages,
                                      index: index,
                                    ),
                              ),
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
                      return _PendingAttachmentChip(
                        fileName: entry.value.fileName,
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
                      onPressed: canCompose ? widget.onPickAttachments : null,
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
                          if (event is KeyDownEvent &&
                              isEnter &&
                              !HardwareKeyboard.instance.isShiftPressed) {
                            if (canCompose) {
                              widget.onSend();
                            }
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: TextField(
                          controller: widget.messageController,
                          minLines: 1,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: 'Type your message',
                            filled: true,
                            fillColor: AppColors.primarySurface,
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
                      onPressed: canCompose ? widget.onSend : null,
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
    required this.isMine,
    required this.showSenderMeta,
    required this.showTimestamp,
  });

  final UserModel currentUser;
  final String? primaryCounterpartUserId;
  final SupportMessage message;
  final bool isMine;
  final bool showSenderMeta;
  final bool showTimestamp;

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
    final timestamp = showTimestamp
        ? _supportMessageTimestampForBubble(message)
        : '';
    final normalizedPrimaryCounterpartId = normalizeId(
      primaryCounterpartUserId,
    );
    final normalizedSenderId = normalizeId(message.senderUserId);
    final canShowSenderMeta =
        !isMine &&
        normalizedSenderId != null &&
        normalizedPrimaryCounterpartId != null &&
        normalizedSenderId != normalizedPrimaryCounterpartId;
    final senderName = (message.senderName?.trim().isNotEmpty == true)
        ? _supportShortPersonName(message.senderName!)
        : (() {
            final fallback = humanizeDropdownValue(message.senderRole);
            return fallback.trim().isNotEmpty ? fallback : 'Support';
          })();
    final senderRoleLabel = humanizeDropdownValue(message.senderRole).trim();
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
              Text(
                senderMetaLabel,
                style: TextStyle(
                  color: AppColors.primaryColor.withValues(alpha: 0.82),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
            ],
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (canShowSenderMeta) ...[
                  AppProfileAvatar(
                    radius: 16,
                    photo: message.senderPhoto,
                    fallbackText: _supportInitials(senderName),
                  ),
                  const SizedBox(width: 8),
                ],
                if (hasBubbleContent)
                  Flexible(
                    child: Container(
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
                            ...fileAttachments.asMap().entries.map((entry) {
                              return Padding(
                                padding: EdgeInsets.only(
                                  bottom:
                                      entry.key == fileAttachments.length - 1
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
                  ),
              ],
            ),
            if (imageAttachments.isNotEmpty) ...[
              if (hasBubbleContent) const SizedBox(height: 10),
              ...imageAttachments.asMap().entries.map((entry) {
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: entry.key == imageAttachments.length - 1 ? 0 : 10,
                  ),
                  child: _SupportAttachmentCard(
                    attachment: entry.value,
                    lightText: isMine,
                  ),
                );
              }),
            ],
            if (timestamp.isNotEmpty) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  timestamp,
                  style: TextStyle(
                    color: AppColors.primaryColor.withValues(alpha: 0.64),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
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
          child: AppCachedNetworkImage(
            imageUrl: downloadUrl,
            height: imageSize,
            width: imageSize,
            fit: BoxFit.cover,
            errorBuilder: (context, error) {
              return Container(
                height: imageSize,
                width: imageSize,
                color: AppColors.primarySurface,
                alignment: Alignment.center,
                child: const Text(
                  'Image unavailable',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            },
          ),
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

class _PendingAttachmentChip extends StatelessWidget {
  const _PendingAttachmentChip({
    required this.fileName,
    required this.onRemove,
  });

  final String fileName;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
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
            fileName,
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

class _SupportTopicDropdown extends StatelessWidget {
  const _SupportTopicDropdown({
    required this.selectedTopicKey,
    required this.onChanged,
  });

  final String selectedTopicKey;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: selectedTopicKey,
      items: supportTopicKeys.map((topicKey) {
        return DropdownMenuItem<String>(
          value: topicKey,
          child: Text(supportTopicLabel(topicKey)),
        );
      }).toList(),
      onChanged: (value) {
        if (value == null) {
          return;
        }
        onChanged(value);
      },
      decoration: const InputDecoration(
        labelText: 'Topic',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(),
      ),
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
    return DropdownButtonFormField<String>(
      initialValue: selectedBookingId,
      items: bookings.map((booking) {
        final value = booking.id ?? '';
        return DropdownMenuItem<String>(
          value: value,
          child: Text(_bookingDisplayLabel(booking)),
        );
      }).toList(),
      onChanged: onChanged,
      decoration: const InputDecoration(
        labelText: 'Booking',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(),
      ),
    );
  }
}

List<Booking> _accessibleBookingsForUser(
  UserModel user,
  List<Booking> allBookings,
) {
  final currentUserId = normalizeId(user.id) ?? '';
  final effectiveClientId = isSubClientRole(user.role)
      ? (normalizeId(user.parentClientId) ?? currentUserId)
      : currentUserId;
  return switch (normalizeRoleKey(user.role)) {
    'client' =>
      allBookings
          .where((booking) => normalizeId(booking.client?.id) == currentUserId)
          .toList(),
    'sub-client' =>
      allBookings
          .where(
            (booking) => normalizeId(booking.client?.id) == effectiveClientId,
          )
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

bool _shouldShowSupportMessageTimestamp({
  required List<SupportMessage> messages,
  required int index,
}) {
  if (index < 0 || index >= messages.length) {
    return false;
  }
  if (messages[index].isPendingUpload) {
    return true;
  }
  final currentLabel = _supportMessageTimestampForBubble(messages[index]);
  if (currentLabel.isEmpty) {
    return false;
  }
  if (index == messages.length - 1) {
    return true;
  }
  final nextLabel = _supportMessageTimestampForBubble(messages[index + 1]);
  return currentLabel != nextLabel;
}

bool _supportThreadHasUnreadLikeState({
  required SupportThread thread,
  required String? currentUserId,
}) {
  final senderId = normalizeId(thread.lastSenderUserId);
  return senderId != null &&
      currentUserId != null &&
      senderId != currentUserId &&
      (thread.lastMessageText?.trim().isNotEmpty == true);
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
  final counterpartId = normalizeId(primaryCounterpartUserId);
  if (senderId == null ||
      senderId == currentUserId ||
      senderId == counterpartId) {
    return false;
  }
  if (index == 0) {
    return true;
  }
  final previousSenderId = normalizeId(messages[index - 1].senderUserId);
  return previousSenderId != senderId;
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
  return _supportMessageTimestampLabel(value);
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
