import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/client_member.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/utils/functions.dart';
import 'package:webapp/views/admin/admin_users.dart';
import 'package:webapp/view_models/client/client_members.vm.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/admin_modal_form_primitives.dart';
import 'package:webapp/widgets/shared/admin_action_confirmation.dart';
import 'package:webapp/widgets/shared/app_page_loading.dart';
import 'package:webapp/widgets/shared/app_page_loading_overlay.dart';
import 'package:webapp/widgets/shared/app_image_source_picker.dart';
import 'package:webapp/widgets/shared/app_profile_avatar.dart';
import 'package:webapp/widgets/shared/app_snackbar.dart';
import 'package:webapp/views/shared/profile_view.dart';
import 'package:webapp/widgets/shared/user_bookings_section.dart';

class ClientMembersView extends StatefulWidget {
  const ClientMembersView({
    super.key,
    required this.clientUser,
    this.scrollable = true,
    this.padding = const EdgeInsets.fromLTRB(24, 24, 24, 24),
    this.onViewUser,
    this.forceWideLayout = false,
    this.onViewBooking,
    this.onEditBooking,
    this.onNewBooking,
    this.allowDelete = true,
  });

  final UserModel clientUser;
  final bool scrollable;
  final EdgeInsets padding;
  final ValueChanged<UserModel>? onViewUser;
  final bool forceWideLayout;
  final Future<void> Function(Booking booking)? onViewBooking;
  final Future<void> Function(Booking booking)? onEditBooking;
  final Future<void> Function()? onNewBooking;
  final bool allowDelete;

  @override
  State<ClientMembersView> createState() => _ClientMembersViewState();
}

class _ClientMemberDialogResult {
  const _ClientMemberDialogResult({
    required this.member,
    required this.email,
    this.password,
    this.pendingPhotoUpload,
  });

  final ClientMember member;
  final String email;
  final String? password;
  final _PendingMemberImageUpload? pendingPhotoUpload;
}

class _PendingMemberImageUpload {
  const _PendingMemberImageUpload({
    required this.bytes,
    required this.fileName,
    required this.size,
    this.mimeType,
  });

  final Uint8List bytes;
  final String fileName;
  final int size;
  final String? mimeType;
}

class _ClientMembersViewState extends State<ClientMembersView> {
  final AuthRepository _authRepository = AuthRequest.instance;
  ClientMember? _viewedMember;

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<ClientMembersViewModel>.reactive(
      viewModelBuilder: ClientMembersViewModel.new,
      onViewModelReady: (vm) {
        final clientId = widget.clientUser.id?.trim();
        if (clientId?.isNotEmpty == true) {
          vm.load(clientId!);
        }
      },
      builder: (context, vm, _) {
        final viewedMember = _viewedMember == null
            ? null
            : vm.members.where((member) => member.id == _viewedMember!.id).firstOrNull ??
                _viewedMember;
        if (viewedMember != null) {
          final viewedUser = UserModel(
            id: viewedMember.id,
            role: 'client',
            parentClientId: viewedMember.clientId,
            email: viewedMember.email,
            name: viewedMember.name,
            photo: viewedMember.photo,
            phone: viewedMember.phone,
            position: viewedMember.position,
            isActive: viewedMember.isActive ?? true,
            createdAt: viewedMember.createdAt,
            updatedAt: viewedMember.updatedAt,
          );
          final detailContent = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ClientMemberDetailHeader(
                member: viewedMember,
                onBack: () {
                  setState(() {
                    _viewedMember = null;
                  });
                },
              ),
              const SizedBox(height: 12),
              ProfileView(
                key: profileViewRefreshKey(viewedUser),
                user: viewedUser,
                scrollable: false,
                padding: EdgeInsets.zero,
                businessUser: widget.clientUser,
                onEditPressed: () => _openMemberDialog(
                  context,
                  vm,
                  existingMember: viewedMember,
                ),
              ),
              const SizedBox(height: 18),
              UserBookingsSection(
                user: viewedUser,
                useAdminListStyle: true,
                forceWideLayout: false,
                onViewBooking: widget.onViewBooking,
                onEditBooking: widget.onEditBooking,
                onNewBooking: widget.onNewBooking,
              ),
            ],
          );
          return AppPageLoadingOverlay(
            isVisible: vm.isBusy,
            message: 'Loading members ...',
            child: widget.scrollable
                ? SingleChildScrollView(
                    padding: widget.padding,
                    child: detailContent,
                  )
                : Padding(
                    padding: widget.padding,
                    child: detailContent,
                  ),
          );
        }

        final filteredMembers = vm.members.where(vm.matches).toList();
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AdminSectionTitle(title: 'Members'),
            const SizedBox(height: 10),
            _MembersToolbar(vm: vm, onNewPressed: () => _openMemberDialog(context, vm)),
            const SizedBox(height: 18),
            if (vm.isBusy && vm.members.isEmpty)
              const SizedBox(
                height: 220,
                child: Center(
                  child: AppPageLoading(
                    message: 'Loading members ...',
                    padding: EdgeInsets.zero,
                    compact: true,
                  ),
                ),
              )
            else if (filteredMembers.isEmpty)
              _ClientMembersEmptyState(
                message: AdminUsersView.buildEmptyStateMessage(
                  noun: 'members',
                  hasSearch: vm.searchQuery.trim().isNotEmpty,
                  activeFilterCount: [
                    vm.activeFilter != 'All',
                    vm.startDate != null,
                    vm.endDate != null,
                  ].where((isActive) => isActive).length,
                ),
              )
            else
              _ClientMembersTable(
                members: filteredMembers,
                forceWideLayout: widget.forceWideLayout,
                onView: (member) => _openMemberView(context, member),
                onEdit: (member) => _openMemberDialog(
                  context,
                  vm,
                  existingMember: member,
                ),
                onToggleActive: (member) =>
                    _toggleMemberActive(context, vm, member),
                onDelete: widget.allowDelete
                    ? (member) => _deleteMember(context, vm, member)
                    : null,
              ),
          ],
        );
        return AppPageLoadingOverlay(
          isVisible: vm.isBusy,
          message: 'Loading members ...',
          child: widget.scrollable
              ? SingleChildScrollView(
                  padding: widget.padding,
                  child: content,
                )
              : Padding(
                  padding: widget.padding,
                  child: content,
                ),
        );
      },
    );
  }

  Future<void> _openMemberDialog(
    BuildContext context,
    ClientMembersViewModel vm, {
    ClientMember? existingMember,
  }) async {
    final clientId = widget.clientUser.id?.trim();
    if (clientId == null || clientId.isEmpty) {
      AppSnackbar.showError(context, 'Client ID is required.');
      return;
    }
    final result = await showDialog<_ClientMemberDialogResult>(
      context: context,
      builder: (dialogContext) => _ClientMemberDialog(
        initialMember:
            existingMember ??
            ClientMember(
              clientId: clientId,
              isActive: true,
            ),
      ),
    );
    if (result == null || !context.mounted) {
      return;
    }
    try {
      final users = await _authRepository.getUsers();
      final existingLinkedUser = existingMember?.userId == null
          ? null
          : users.where((user) => user.id == existingMember!.userId).firstOrNull;
      final savedUser = await _authRepository.saveUser(
        UserModel(
          id: existingLinkedUser?.id ?? existingMember?.userId,
          role: 'client',
          parentClientId: clientId,
          email: result.email,
          name: result.member.name,
          phone: result.member.phone,
          position: result.member.position,
          password:
              result.password?.trim().isNotEmpty == true
                  ? result.password!.trim()
                  : existingLinkedUser?.password,
          isActive: result.member.isActive ?? true,
          isOnline: existingLinkedUser?.isOnline ?? false,
          createdAt: existingLinkedUser?.createdAt,
          photo: existingLinkedUser?.photo,
        ),
      );
      var uploadedUser = savedUser;
      final pendingPhotoUpload = result.pendingPhotoUpload;
      if (pendingPhotoUpload != null && savedUser.id?.trim().isNotEmpty == true) {
        uploadedUser = await _authRepository.saveUserPhoto(
          userId: savedUser.id!.trim(),
          bytes: pendingPhotoUpload.bytes,
          fileName: pendingPhotoUpload.fileName,
          mimeType: pendingPhotoUpload.mimeType,
          size: pendingPhotoUpload.size,
        );
      }
      final saved = await vm.save(
        result.member.copyWith(
          id: uploadedUser.id,
          clientId: clientId,
          userId: uploadedUser.id,
          email: uploadedUser.email,
          photo: uploadedUser.photo,
          createdAt: existingMember?.createdAt,
        ),
      );
      final previousMemberId = existingMember?.id?.trim();
      final savedMemberId = saved.id?.trim();
      if (previousMemberId != null &&
          previousMemberId.isNotEmpty &&
          savedMemberId != null &&
          savedMemberId.isNotEmpty &&
          previousMemberId != savedMemberId) {
        await vm.delete(existingMember!);
      }
      if (!context.mounted) {
        return;
      }
      AppSnackbar.showSuccess(
        context,
        existingMember == null ? 'Member added.' : 'Member updated.',
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      AppSnackbar.showError(
        context,
        userFacingErrorMessage(
          error,
          fallback: 'We could not save the member right now.',
        ),
      );
    }
  }

  Future<void> _openMemberView(
    BuildContext context,
    ClientMember member,
  ) async {
    final onViewUser = widget.onViewUser;
    if (onViewUser != null) {
      onViewUser(
        UserModel(
          id: member.id,
          role: 'client',
          parentClientId: member.clientId,
          email: member.email,
          name: member.name,
          photo: member.photo,
          phone: member.phone,
          position: member.position,
          isActive: member.isActive ?? true,
          createdAt: member.createdAt,
          updatedAt: member.updatedAt,
        ),
      );
      return;
    }
    setState(() {
      _viewedMember = member;
    });
  }

  Future<void> _toggleMemberActive(
    BuildContext context,
    ClientMembersViewModel vm,
    ClientMember member,
  ) async {
    final willBeActive = !(member.isActive ?? true);
    final confirmed = await showAdminActionConfirmation(
      context,
      title: '${willBeActive ? 'Activate' : 'Deactivate'} Member',
      message:
          'Are you sure you want to ${willBeActive ? 'activate' : 'deactivate'} ${member.displayName}?',
      confirmLabel: willBeActive ? 'Activate' : 'Deactivate',
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    try {
      await vm.save(member.copyWith(isActive: willBeActive));
      if (!context.mounted) {
        return;
      }
      AppSnackbar.showSuccess(
        context,
        willBeActive ? 'Member activated.' : 'Member deactivated.',
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      AppSnackbar.showError(
        context,
        userFacingErrorMessage(
          error,
          fallback: 'We could not update the member right now.',
        ),
      );
    }
  }

  Future<void> _deleteMember(
    BuildContext context,
    ClientMembersViewModel vm,
    ClientMember member,
  ) async {
    final confirmed = await showAdminActionConfirmation(
      context,
      title: 'Delete Member',
      message: 'Are you sure you want to delete ${member.displayName}?',
      confirmLabel: 'Delete',
      isDanger: true,
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    try {
      await vm.delete(member);
      if (!context.mounted) {
        return;
      }
      AppSnackbar.showSuccess(
        context,
        'Member deleted.',
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      AppSnackbar.showError(
        context,
        userFacingErrorMessage(
          error,
          fallback: 'We could not delete the member right now.',
        ),
      );
    }
  }
}

class _ClientMembersTable extends StatelessWidget {
  const _ClientMembersTable({
    required this.members,
    required this.forceWideLayout,
    required this.onView,
    required this.onEdit,
    required this.onToggleActive,
    this.onDelete,
  });

  final List<ClientMember> members;
  final bool forceWideLayout;
  final ValueChanged<ClientMember> onView;
  final ValueChanged<ClientMember> onEdit;
  final ValueChanged<ClientMember> onToggleActive;
  final ValueChanged<ClientMember>? onDelete;

  static const _headerStyle = TextStyle(
    color: AppColors.textSecondary,
    fontWeight: FontWeight.w700,
  );

  static const _valueStyle = TextStyle(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w600,
  );

  static const _nameStyle = TextStyle(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w700,
  );

  static const _defaultTrailingPadding =
      AdminListMeasurements.defaultTrailingPadding;
  static const _extraWidthAllowance =
      AdminListMeasurements.defaultExtraWidthAllowance;
  @override
  Widget build(BuildContext context) {
    final longestIdValue = _longestText(members.map((member) => member.id ?? '-'));
    final longestNameValue = _longestText(
      members.map((member) => member.displayName),
    );
    final longestPhoneValue = _longestText(
      members.map((member) => member.normalizedPhone.isNotEmpty ? member.normalizedPhone : '-'),
    );
    final longestEmailValue = _longestText(
      members.map((member) => (member.email?.trim().isNotEmpty == true) ? member.email!.trim() : '-'),
    );
    final longestPositionValue = _longestText(
      members.map((member) => (member.position?.trim().isNotEmpty == true) ? member.position!.trim() : '-'),
    );
    final longestCreatedAtValue = _longestText(
      members.map(
        (member) => member.createdAt == null ? '-' : _formatDateTime(member.createdAt!),
      ),
    );
    final longestUpdatedAtValue = _longestText(
      members.map(
        (member) => member.updatedAt == null ? '-' : _formatDateTime(member.updatedAt!),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScaler = MediaQuery.textScalerOf(context);
        final idWidth = _maxTextWidth(context, textScaler, 'ID', longestIdValue);
        final photoWidth = _maxValue(
          44,
          AdminListMeasurements.measureTextWidth(
            context,
            textScaler,
            'Photo',
            _headerStyle,
          ),
        );
        final nameWidth = _maxTextWidth(context, textScaler, 'Name', longestNameValue);
        final phoneWidth = _maxTextWidth(context, textScaler, 'Phone', longestPhoneValue);
        final emailWidth = _maxTextWidth(context, textScaler, 'Email', longestEmailValue);
        final positionWidth = _maxTextWidth(context, textScaler, 'Position', longestPositionValue);
        final createdAtWidth = _maxTextWidth(context, textScaler, 'Created', longestCreatedAtValue);
        final updatedAtWidth = _maxTextWidth(context, textScaler, 'Updated', longestUpdatedAtValue);
        final actionsWidth = _maxValue(
          176,
          AdminListMeasurements.measureTextWidth(
            context,
            textScaler,
            'Actions',
            _headerStyle,
          ),
        );

        final resolvedIdWidth = _resolvedColumnWidth(idWidth);
        final resolvedPhotoWidth = _resolvedColumnWidth(photoWidth);
        final resolvedNameWidth = _resolvedColumnWidth(nameWidth);
        final resolvedPhoneWidth = _resolvedColumnWidth(phoneWidth);
        final resolvedEmailWidth = _resolvedColumnWidth(emailWidth);
        final resolvedPositionWidth = _resolvedColumnWidth(positionWidth);
        final resolvedCreatedAtWidth = _resolvedColumnWidth(createdAtWidth);
        final resolvedUpdatedAtWidth = _resolvedColumnWidth(updatedAtWidth);
        final resolvedActionsWidth = actionsWidth + _extraWidthAllowance;
        final totalMeasuredWidth =
            resolvedIdWidth +
            resolvedPhotoWidth +
            resolvedNameWidth +
            resolvedPhoneWidth +
            resolvedEmailWidth +
            resolvedPositionWidth +
            resolvedCreatedAtWidth +
            resolvedUpdatedAtWidth +
            resolvedActionsWidth +
            40;
        final shouldFlexNameAndEmail =
            totalMeasuredWidth > constraints.maxWidth;
        final useResponsiveCards =
            !forceWideLayout && shouldFlexNameAndEmail;
        if (useResponsiveCards) {
          return Column(
            children: members
                .asMap()
                .entries
                .map(
                  (entry) => Padding(
                    padding: EdgeInsets.only(
                      bottom: entry.key == members.length - 1 ? 0 : 12,
                    ),
                    child: _ClientMemberResponsiveCard(
                      member: entry.value,
                      onView: () => onView(entry.value),
                      onEdit: () => onEdit(entry.value),
                      onToggleActive: () => onToggleActive(entry.value),
                      onDelete: onDelete == null
                          ? null
                          : () => onDelete!(entry.value),
                    ),
                  ),
                )
                .toList(),
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
                  _ClientMembersFixedSlot(
                    width: resolvedIdWidth,
                    child: const _ClientMembersHeader(label: 'ID'),
                  ),
                  _ClientMembersFixedSlot(
                    width: resolvedPhotoWidth,
                    child: const _ClientMembersHeader(label: 'Photo'),
                  ),
                  if (shouldFlexNameAndEmail)
                    const Expanded(
                      child: _ClientMembersHeader(label: 'Name'),
                    )
                  else
                    _ClientMembersFixedSlot(
                      width: resolvedNameWidth,
                      child: const _ClientMembersHeader(label: 'Name'),
                    ),
                  _ClientMembersFixedSlot(
                    width: resolvedPhoneWidth,
                    child: const _ClientMembersHeader(label: 'Phone'),
                  ),
                  if (shouldFlexNameAndEmail)
                    const Expanded(
                      child: _ClientMembersHeader(label: 'Email'),
                    )
                  else
                    _ClientMembersFixedSlot(
                      width: resolvedEmailWidth,
                      child: const _ClientMembersHeader(label: 'Email'),
                    ),
                  _ClientMembersFixedSlot(
                    width: resolvedPositionWidth,
                    child: const _ClientMembersHeader(label: 'Position'),
                  ),
                  _ClientMembersFixedSlot(
                    width: resolvedCreatedAtWidth,
                    child: const _ClientMembersHeader(label: 'Created'),
                  ),
                  _ClientMembersFixedSlot(
                    width: resolvedUpdatedAtWidth,
                    child: const _ClientMembersHeader(label: 'Updated'),
                  ),
                  if (forceWideLayout)
                    _ClientMembersFixedSlot(
                      width: resolvedActionsWidth,
                      child: const _ClientMembersHeader(
                        label: 'Actions',
                        trailingPadding: 0,
                        alignment: Alignment.centerRight,
                        textAlign: TextAlign.right,
                      ),
                    )
                  else
                    AdminListTrailingActionsLane(
                      width: resolvedActionsWidth,
                      child: const _ClientMembersHeader(
                        label: 'Actions',
                        trailingPadding: 0,
                        alignment: Alignment.centerRight,
                        textAlign: TextAlign.right,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ...members.asMap().entries.map(
              (entry) => Padding(
                padding: EdgeInsets.only(
                  bottom: entry.key == members.length - 1 ? 0 : 12,
                ),
                child: _ClientMembersWideRow(
                  member: entry.value,
                  shouldFlexNameAndEmail: shouldFlexNameAndEmail,
                  resolvedIdWidth: resolvedIdWidth,
                  resolvedPhotoWidth: resolvedPhotoWidth,
                  resolvedNameWidth: resolvedNameWidth,
                  resolvedPhoneWidth: resolvedPhoneWidth,
                  resolvedEmailWidth: resolvedEmailWidth,
                  resolvedPositionWidth: resolvedPositionWidth,
                  resolvedCreatedAtWidth: resolvedCreatedAtWidth,
                  resolvedUpdatedAtWidth: resolvedUpdatedAtWidth,
                  resolvedActionsWidth: resolvedActionsWidth,
                  onView: () => onView(entry.value),
                  onEdit: () => onEdit(entry.value),
                  onToggleActive: () => onToggleActive(entry.value),
                  onDelete: onDelete == null
                      ? null
                      : () => onDelete!(entry.value),
                ),
              ),
            ),
          ],
        );
        if (forceWideLayout && totalMeasuredWidth > constraints.maxWidth) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: totalMeasuredWidth,
              child: table,
            ),
          );
        }

        return table;
      },
    );
  }

  static double _maxValue(double first, double second) =>
      first > second ? first : second;

  static String _longestText(Iterable<String> values) {
    var longest = '-';
    for (final value in values) {
      if (value.length > longest.length) {
        longest = value;
      }
    }
    return longest;
  }

  static double _resolvedColumnWidth(double measuredWidth) {
    return AdminListMeasurements.resolvedColumnWidth(
      measuredWidth,
      trailingPadding: _defaultTrailingPadding,
      extraWidthAllowance: _extraWidthAllowance,
    );
  }

  static double _maxTextWidth(
    BuildContext context,
    TextScaler textScaler,
    String label,
    String value,
  ) {
    return AdminListMeasurements.maxTextWidth(
      context,
      textScaler,
      label,
      _headerStyle,
      value,
      _valueStyle,
    );
  }
}

class _ClientMembersWideRow extends StatelessWidget {
  const _ClientMembersWideRow({
    required this.member,
    required this.shouldFlexNameAndEmail,
    required this.resolvedIdWidth,
    required this.resolvedPhotoWidth,
    required this.resolvedNameWidth,
    required this.resolvedPhoneWidth,
    required this.resolvedEmailWidth,
    required this.resolvedPositionWidth,
    required this.resolvedCreatedAtWidth,
    required this.resolvedUpdatedAtWidth,
    required this.resolvedActionsWidth,
    required this.onView,
    required this.onEdit,
    required this.onToggleActive,
    this.onDelete,
  });

  final ClientMember member;
  final bool shouldFlexNameAndEmail;
  final double resolvedIdWidth;
  final double resolvedPhotoWidth;
  final double resolvedNameWidth;
  final double resolvedPhoneWidth;
  final double resolvedEmailWidth;
  final double resolvedPositionWidth;
  final double resolvedCreatedAtWidth;
  final double resolvedUpdatedAtWidth;
  final double resolvedActionsWidth;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final isActive = member.isActive ?? true;
    return AdminListItemCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _ClientMembersFixedSlot(
            width: resolvedIdWidth,
            child: _ClientMembersCell(
              child: Text(member.id ?? '-', style: _ClientMembersTable._valueStyle),
            ),
          ),
          _ClientMembersFixedSlot(
            width: resolvedPhotoWidth,
            child: _ClientMembersCell(
              child: AppProfileAvatar(
                photo: member.photo,
                fallbackText: _memberInitials(member.displayName),
                radius: 22,
                enablePreview: true,
                previewTitle: member.displayName,
              ),
            ),
          ),
          if (shouldFlexNameAndEmail)
            Expanded(
              child: _ClientMembersCell(
                child: Text(
                  member.displayName,
                  style: _ClientMembersTable._nameStyle.copyWith(
                    color: isActive ? AppColors.textPrimary : AppColors.textSecondary,
                  ),
                  softWrap: true,
                ),
              ),
            )
          else
            _ClientMembersFixedSlot(
              width: resolvedNameWidth,
              child: _ClientMembersCell(
                child: Text(
                  member.displayName,
                  style: _ClientMembersTable._nameStyle.copyWith(
                    color: isActive ? AppColors.textPrimary : AppColors.textSecondary,
                  ),
                  softWrap: true,
                ),
              ),
            ),
          _ClientMembersFixedSlot(
            width: resolvedPhoneWidth,
            child: _ClientMembersCell(
              child: Text(
                member.normalizedPhone.isNotEmpty ? member.normalizedPhone : '-',
                style: _ClientMembersTable._valueStyle,
                softWrap: true,
              ),
            ),
          ),
          if (shouldFlexNameAndEmail)
            Expanded(
              child: _ClientMembersCell(
                child: Text(
                  member.email?.trim().isNotEmpty == true ? member.email!.trim() : '-',
                  style: _ClientMembersTable._valueStyle,
                  softWrap: true,
                ),
              ),
            )
          else
            _ClientMembersFixedSlot(
              width: resolvedEmailWidth,
              child: _ClientMembersCell(
                child: Text(
                  member.email?.trim().isNotEmpty == true ? member.email!.trim() : '-',
                  style: _ClientMembersTable._valueStyle,
                  softWrap: true,
                ),
              ),
            ),
          _ClientMembersFixedSlot(
            width: resolvedPositionWidth,
            child: _ClientMembersCell(
              child: Text(
                member.position?.trim().isNotEmpty == true
                    ? member.position!.trim()
                    : '-',
                style: _ClientMembersTable._valueStyle,
                softWrap: true,
              ),
            ),
          ),
          _ClientMembersFixedSlot(
            width: resolvedCreatedAtWidth,
            child: _ClientMembersCell(
              child: Text(
                member.createdAt == null ? '-' : _formatDateTime(member.createdAt!),
                style: _ClientMembersTable._valueStyle,
                softWrap: true,
              ),
            ),
          ),
          _ClientMembersFixedSlot(
            width: resolvedUpdatedAtWidth,
            child: _ClientMembersCell(
              child: Text(
                member.updatedAt == null ? '-' : _formatDateTime(member.updatedAt!),
                style: _ClientMembersTable._valueStyle,
                softWrap: true,
              ),
            ),
          ),
          AdminListTrailingActionsLane(
            width: resolvedActionsWidth,
            child: _ClientMembersCell(
              trailingPadding: 0,
              alignment: Alignment.centerRight,
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ClientMemberActionButton(
                    icon: Icons.visibility_rounded,
                    backgroundColor: Colors.yellow.shade900,
                    onTap: onView,
                  ),
                  _ClientMemberActionButton(
                    icon: Icons.edit_rounded,
                    onTap: onEdit,
                  ),
                  _ClientMemberActionButton(
                    icon: isActive ? Icons.close_rounded : Icons.check_rounded,
                    backgroundColor: isActive
                        ? AppColors.dangerStrong
                        : const Color(0xFF2EAD62),
                    onTap: onToggleActive,
                  ),
                  if (onDelete != null)
                    _ClientMemberActionButton(
                      icon: Icons.delete_rounded,
                      isDanger: true,
                      onTap: onDelete!,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientMemberResponsiveCard extends StatelessWidget {
  const _ClientMemberResponsiveCard({
    required this.member,
    required this.onView,
    required this.onEdit,
    required this.onToggleActive,
    this.onDelete,
  });

  final ClientMember member;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback? onDelete;

  static final _labelStyle = TextStyle(
    color: AppColors.primaryColor.withValues(alpha: 0.72),
    fontWeight: FontWeight.w700,
  );

  static const _valueStyle = TextStyle(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w600,
  );

  @override
  Widget build(BuildContext context) {
    final isActive = member.isActive ?? true;
    final fields = [
      ('ID', member.id ?? '-'),
      ('Name', member.displayName),
      ('Phone', member.normalizedPhone.isNotEmpty ? member.normalizedPhone : '-'),
      ('Email', member.email?.trim().isNotEmpty == true ? member.email!.trim() : '-'),
      ('Position', member.position?.trim().isNotEmpty == true ? member.position!.trim() : '-'),
      ('Created', member.createdAt == null ? '-' : _formatDateTime(member.createdAt!)),
      ('Updated', member.updatedAt == null ? '-' : _formatDateTime(member.updatedAt!)),
      ('Status', isActive ? 'Active' : 'Inactive'),
    ];

    return AdminListItemCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppProfileAvatar(
                photo: member.photo,
                fallbackText: _memberInitials(member.displayName),
                radius: 24,
                enablePreview: true,
                previewTitle: member.displayName,
              ),
              const Spacer(),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 10,
                children: [
                  _ClientMemberActionButton(
                    icon: Icons.visibility_rounded,
                    backgroundColor: Colors.yellow.shade900,
                    onTap: onView,
                  ),
                  _ClientMemberActionButton(icon: Icons.edit_rounded, onTap: onEdit),
                  _ClientMemberActionButton(
                    icon: isActive ? Icons.close_rounded : Icons.check_rounded,
                    backgroundColor: isActive
                        ? AppColors.dangerStrong
                        : const Color(0xFF2EAD62),
                    onTap: onToggleActive,
                  ),
                  if (onDelete != null)
                    _ClientMemberActionButton(
                      icon: Icons.delete_rounded,
                      isDanger: true,
                      onTap: onDelete!,
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: fields
                .map(
                  (field) => ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 140, maxWidth: 280),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(field.$1, style: _labelStyle),
                        const SizedBox(height: 4),
                        Text(field.$2, style: _valueStyle, softWrap: true),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _ClientMembersFixedSlot extends StatelessWidget {
  const _ClientMembersFixedSlot({required this.child, required this.width});

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    return AdminListFixedSlot(width: width, child: child);
  }
}

class _ClientMembersHeader extends StatelessWidget {
  const _ClientMembersHeader({
    required this.label,
    this.trailingPadding = AdminListMeasurements.defaultTrailingPadding,
    this.alignment = Alignment.centerLeft,
    this.textAlign = TextAlign.left,
  });

  final String label;
  final double trailingPadding;
  final Alignment alignment;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return AdminListHeaderCell(
      label: label,
      trailingPadding: trailingPadding,
      alignment: alignment,
      textAlign: textAlign,
    );
  }
}

class _ClientMembersCell extends StatelessWidget {
  const _ClientMembersCell({
    required this.child,
    this.trailingPadding = AdminListMeasurements.defaultTrailingPadding,
    this.alignment = Alignment.centerLeft,
  });

  final Widget child;
  final double trailingPadding;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return AdminListBodyCell(
      trailingPadding: trailingPadding,
      alignment: alignment,
      child: child,
    );
  }
}

class _ClientMemberActionButton extends StatelessWidget {
  const _ClientMemberActionButton({
    required this.icon,
    required this.onTap,
    this.backgroundColor,
    this.isDanger = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color? backgroundColor;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    return AdminListActionButton(
      icon: icon,
      onTap: onTap,
      backgroundColor: backgroundColor,
      isDanger: isDanger,
    );
  }
}

class _ClientMembersEmptyState extends StatelessWidget {
  const _ClientMembersEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AdminListItemCard(
      padding: const EdgeInsets.all(24),
      child: Text(
        message,
        style: TextStyle(
          color: AppColors.primaryColor.withValues(alpha: 0.72),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ClientMemberDetailHeader extends StatelessWidget {
  const _ClientMemberDetailHeader({required this.member, required this.onBack});

  final ClientMember member;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Transform.translate(
            offset: const Offset(-8, 0),
            child: Row(
              children: [
                IconButton(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: AppColors.primaryColor,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  visualDensity: VisualDensity.compact,
                  splashRadius: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Member ${member.id ?? '-'}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ClientMemberDialog extends StatefulWidget {
  const _ClientMemberDialog({required this.initialMember});

  final ClientMember initialMember;

  @override
  State<_ClientMemberDialog> createState() => _ClientMemberDialogState();
}

class _ClientMemberDialogState extends State<_ClientMemberDialog> {
  late final TextEditingController _emailController;
  late final TextEditingController _photoController;
  late final TextEditingController _passwordController;
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _positionController;
  late final FocusNode _emailFocusNode;
  late final FocusNode _nameFocusNode;
  late final FocusNode _photoFocusNode;
  late final FocusNode _phoneFocusNode;
  late final FocusNode _positionFocusNode;
  late final FocusNode _passwordFocusNode;
  bool _isActive = true;
  _PendingMemberImageUpload? _pendingPhotoUpload;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(
      text: widget.initialMember.email?.trim() ?? '',
    );
    _photoController = TextEditingController(
      text: widget.initialMember.photo?.trim() ?? '',
    );
    _passwordController = TextEditingController();
    _nameController = TextEditingController(
      text: widget.initialMember.name?.trim() ?? '',
    );
    _phoneController = TextEditingController(
      text: widget.initialMember.phone?.trim() ?? '',
    );
    _positionController = TextEditingController(
      text: widget.initialMember.position?.trim() ?? '',
    );
    _emailFocusNode = FocusNode(debugLabel: 'member_email');
    _nameFocusNode = FocusNode(debugLabel: 'member_name');
    _photoFocusNode = FocusNode(debugLabel: 'member_photo');
    _phoneFocusNode = FocusNode(debugLabel: 'member_phone');
    _positionFocusNode = FocusNode(debugLabel: 'member_position');
    _passwordFocusNode = FocusNode(debugLabel: 'member_password');
    _isActive = widget.initialMember.isActive ?? true;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _photoController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _positionController.dispose();
    _emailFocusNode.dispose();
    _nameFocusNode.dispose();
    _photoFocusNode.dispose();
    _phoneFocusNode.dispose();
    _positionFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.initialMember.id?.trim().isNotEmpty == true;

  void _handleFieldSubmit(FocusNode? nextFocusNode) {
    if (_isEditing) {
      _submit();
      return;
    }
    if (nextFocusNode == null) {
      _submit();
      return;
    }
    FocusScope.of(context).requestFocus(nextFocusNode);
  }

  void _submit() {
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final position = _positionController.text.trim();
    if (email.isEmpty) {
      AppSnackbar.showError(context, 'Member email is required.');
      return;
    }
    final emailRegex = RegExp(
      r"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$",
      caseSensitive: false,
    );
    if (!emailRegex.hasMatch(email)) {
      AppSnackbar.showError(context, 'Enter a valid email address.');
      return;
    }
    if (!_isEditing && password.isEmpty) {
      AppSnackbar.showError(context, 'Password is required.');
      return;
    }
    if (password.isNotEmpty && password.length < 6) {
      AppSnackbar.showError(context, 'Password must be at least 6 characters.');
      return;
    }
    if (name.isEmpty) {
      AppSnackbar.showError(context, 'Member name is required.');
      return;
    }
    if (phone.isEmpty) {
      AppSnackbar.showError(context, 'Representative phone is required.');
      return;
    }
    if (!isValidPhilippinePhone(phone)) {
      AppSnackbar.showError(context, 'Enter a valid PH mobile number.');
      return;
    }
    if (position.isEmpty) {
      AppSnackbar.showError(context, 'Representative position is required.');
      return;
    }
    Navigator.of(context).pop(
      _ClientMemberDialogResult(
        email: email,
        password: password.isEmpty ? null : password,
        pendingPhotoUpload: _pendingPhotoUpload,
        member: widget.initialMember.copyWith(
          email: email,
          photo: _photoController.text.trim(),
          name: name,
          phone: phone,
          position: position,
          isActive: _isActive,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminModalShell(
      title: _isEditing ? 'Edit Member' : 'New Member',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(_isEditing ? 'Save' : 'Create'),
        ),
      ],
      child: AdminModalFormBody(
        children: [
          AdminModalFieldsSection(
            children: [
              AdminModalTextField(
                controller: _emailController,
                label: 'Email',
                focusNode: _emailFocusNode,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _handleFieldSubmit(_nameFocusNode),
              ),
              AdminModalTextField(
                controller: _nameController,
                label: 'Name',
                focusNode: _nameFocusNode,
                textCapitalization: TextCapitalization.words,
                inputFormatters: const [NameCaseTextInputFormatter()],
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _handleFieldSubmit(_photoFocusNode),
              ),
              AdminModalActionField(
                label: 'Photo',
                focusNode: _photoFocusNode,
                activateOnFocus: !_isEditing,
                valueText: _photoController.text.trim().isNotEmpty
                    ? _photoController.text.trim()
                    : null,
                hintText: 'Upload member photo',
                onTap: _pickPhoto,
                onSubmitted: () {
                  if (_isEditing) {
                    _submit();
                    return;
                  }
                  _pickPhoto(nextFocusNode: _phoneFocusNode);
                },
                suffixIcon: _photoController.text.trim().isNotEmpty
                    ? const Icon(Icons.photo_camera_rounded)
                    : const Icon(Icons.upload_rounded),
              ),
              AdminModalTextField(
                controller: _phoneController,
                label: 'Phone',
                focusNode: _phoneFocusNode,
                keyboardType: TextInputType.phone,
                inputFormatters: const [PhilippinesPhoneInputFormatter()],
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _handleFieldSubmit(_positionFocusNode),
              ),
              AdminModalTextField(
                controller: _positionController,
                label: 'Position',
                focusNode: _positionFocusNode,
                textCapitalization: TextCapitalization.none,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _handleFieldSubmit(_passwordFocusNode),
              ),
              AdminModalTextField(
                controller: _passwordController,
                label: _isEditing ? 'New Password (Optional)' : 'Password',
                focusNode: _passwordFocusNode,
                obscureText: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
          const SizedBox(height: 6),
          AdminModalToggleRow(
            title: 'Active',
            value: _isActive,
            onChanged: (value) => setState(() => _isActive = value),
          ),
        ],
      ),
    );
  }

  Future<void> _pickPhoto({FocusNode? nextFocusNode}) async {
    final image = await showAppImageSourcePicker(context);
    if (image == null) {
      return;
    }
    setState(() {
      _pendingPhotoUpload = _PendingMemberImageUpload(
        bytes: image.bytes,
        fileName: image.fileName,
        size: image.size,
        mimeType: image.mimeType,
      );
      _photoController.text = image.fileName;
    });
    if (!mounted || nextFocusNode == null) {
      return;
    }
    FocusScope.of(context).requestFocus(nextFocusNode);
  }
}

class _MembersToolbar extends StatelessWidget {
  const _MembersToolbar({required this.vm, required this.onNewPressed});

  final ClientMembersViewModel vm;
  final VoidCallback onNewPressed;

  @override
  Widget build(BuildContext context) {
    return AdminListToolbar(
      controlHeight: 52,
      surfaceRadius: 16,
      search: AdminListSearchField(
        controlHeight: 52,
        surfaceRadius: 16,
        initialValue: vm.searchQuery,
        onChanged: vm.setSearchQuery,
      ),
      filtersBuilder: (context, iconOnly) =>
          _MembersFiltersPanel(vm: vm, iconOnly: iconOnly),
      onNewPressed: onNewPressed,
    );
  }
}

class _MembersFiltersPanel extends StatefulWidget {
  const _MembersFiltersPanel({required this.vm, required this.iconOnly});

  final ClientMembersViewModel vm;
  final bool iconOnly;

  @override
  State<_MembersFiltersPanel> createState() => _MembersFiltersPanelState();
}

class _MembersFiltersPanelState extends State<_MembersFiltersPanel> {
  late final FocusNode _activeFocusNode;

  @override
  void initState() {
    super.initState();
    _activeFocusNode = FocusNode()..canRequestFocus = false;
  }

  @override
  void dispose() {
    _activeFocusNode.dispose();
    super.dispose();
  }

  void _unfocusFilterFields() {
    _activeFocusNode.unfocus();
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    const overlayRightPadding = 24.0;
    const filterItemWidth = 180.0;
    const overlayPadding = 14.0;
    const desiredOverlayWidth = filterItemWidth + (overlayPadding * 2);
    final overlayWidth = (screenWidth - 32 - overlayRightPadding).clamp(
      1.0,
      desiredOverlayWidth,
    );
    final contentWidth = (overlayWidth - (overlayPadding * 2)).clamp(
      1.0,
      desiredOverlayWidth,
    );
    final itemWidth = contentWidth;

    return AdminListFiltersButton(
      controlHeight: adminFilterFieldMinHeight,
      surfaceRadius: 16,
      iconOnly: widget.iconOnly,
      menuChildren: [
        SizedBox(
          width: overlayWidth,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _unfocusFilterFields,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: itemWidth,
                    height: adminFilterFieldMinHeight,
                    child: _MembersFilterDropdown(
                      label: 'Is Active',
                      value: widget.vm.activeFilter,
                      focusNode: _activeFocusNode,
                      items: const ['All', 'Active', 'Inactive'],
                      onChanged: widget.vm.updateActiveFilter,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: itemWidth,
                    height: adminFilterFieldMinHeight,
                    child: _MembersDateFilter(
                      label: 'Start Date',
                      value: widget.vm.startDate,
                      formatter: widget.vm.formatDate,
                      onSelected: widget.vm.updateStartDate,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: itemWidth,
                    height: adminFilterFieldMinHeight,
                    child: _MembersDateFilter(
                      label: 'End Date',
                      value: widget.vm.endDate,
                      formatter: widget.vm.formatDate,
                      onSelected: widget.vm.updateEndDate,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: itemWidth,
                    height: adminFilterFieldMinHeight,
                    child: FilledButton(
                      onPressed: () {
                        _unfocusFilterFields();
                        widget.vm.clearFilters();
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Clear',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MembersFilterDropdown extends StatelessWidget {
  const _MembersFilterDropdown({
    required this.label,
    required this.value,
    required this.focusNode,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String value;
  final FocusNode focusNode;
  final List<String> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return AdminDropdownFormField<String>(
      initialValue: value,
      focusNode: focusNode,
      iconEnabledColor: AppColors.primaryColor,
      decoration: adminFormInputDecoration(
        label,
        radius: 16,
        minHeight: adminFilterFieldMinHeight,
      ),
      style: adminDropdownDisplayTextStyle,
      items: items
          .map(
            (item) => DropdownMenuItem<String>(
              value: item,
              child: Text(item, style: adminDropdownDisplayTextStyle),
            ),
          )
          .toList(),
      onChanged: (nextValue) {
        final resolvedValue = nextValue?.trim();
        if (resolvedValue == null || resolvedValue.isEmpty) {
          return;
        }
        onChanged(resolvedValue);
      },
    );
  }
}

class _MembersDateFilter extends StatefulWidget {
  const _MembersDateFilter({
    required this.label,
    required this.value,
    required this.formatter,
    required this.onSelected,
  });

  final String label;
  final DateTime? value;
  final String Function(DateTime?) formatter;
  final ValueChanged<DateTime?> onSelected;

  @override
  State<_MembersDateFilter> createState() => _MembersDateFilterState();
}

class _MembersDateFilterState extends State<_MembersDateFilter> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _displayValue);
    _focusNode = FocusNode()..canRequestFocus = false;
  }

  @override
  void didUpdateWidget(covariant _MembersDateFilter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != _displayValue) {
      _controller.value = _controller.value.copyWith(
        text: _displayValue,
        selection: TextSelection.collapsed(offset: _displayValue.length),
        composing: TextRange.empty,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String get _displayValue =>
      widget.value == null ? '' : widget.formatter(widget.value);

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.value ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (context.mounted) {
      widget.onSelected(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeFillColor = appFieldInteractiveFillColor(context);
    return SizedBox(
      height: adminFilterFieldMinHeight,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() {
          _isHovered = false;
          _isPressed = false;
        }),
        child: Listener(
          onPointerDown: (_) => setState(() => _isPressed = true),
          onPointerUp: (_) => setState(() => _isPressed = false),
          onPointerCancel: (_) => setState(() => _isPressed = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _pickDate,
            child: IgnorePointer(
              child: TextFormField(
                controller: _controller,
                focusNode: _focusNode,
                readOnly: true,
                showCursor: false,
                enableInteractiveSelection: false,
                style: adminDropdownDisplayTextStyle,
                decoration: adminFormInputDecoration(
                  widget.label,
                  radius: 16,
                  minHeight: adminFilterFieldMinHeight,
                ).copyWith(
                  fillColor: _isHovered || _isPressed
                      ? activeFillColor
                      : AppColors.primarySurface,
                  suffixIcon: const Icon(
                    Icons.calendar_today_rounded,
                    color: AppColors.primaryColor,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _memberInitials(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .toList();
  if (parts.isEmpty) {
    return '';
  }
  return parts.map((part) => part[0].toUpperCase()).join();
}

String _formatDateTime(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final year = value.year.toString();
  return '$month/$day/$year';
}
