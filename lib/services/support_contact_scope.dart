import 'package:webapp/models/user.dart';
import 'package:webapp/models/support_thread.dart';
import 'package:webapp/utils/functions.dart';

bool canSeeSupportThread({
  required UserModel viewer,
  required SupportThread thread,
  required bool canBrowseAllThreads,
  Iterable<UserModel> contacts = const [],
}) {
  final viewerId = normalizeId(viewer.id);
  final requesterId = normalizeId(thread.requesterUserId);
  if (viewerId == null) return false;
  if (!canBrowseAllThreads) return requesterId == viewerId;
  if (normalizeRoleKey(viewer.role) != 'investor') return true;
  if (requesterId == viewerId) return true;
  return requesterId != '1' &&
      contacts.any(
        (contact) =>
            normalizeId(contact.id) == requesterId &&
            canSeeSupportContact(viewer, contact),
      );
}

bool canSeeSupportContact(UserModel viewer, UserModel contact) {
  if (normalizeRoleKey(viewer.role) != 'investor') {
    return true;
  }
  final viewerId = normalizeId(viewer.id);
  final contactId = normalizeId(contact.id);
  if (viewerId == null || contactId == null || contactId == viewerId) {
    return false;
  }
  return contactId == '1' ||
      (const {'driver', 'helper'}.contains(normalizeRoleKey(contact.role)) &&
          normalizeId(contact.parentClientId) == viewerId);
}
