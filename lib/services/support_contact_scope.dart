import 'package:webapp/models/user.dart';
import 'package:webapp/utils/functions.dart';

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
