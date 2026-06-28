import 'package:webapp/models/client_member.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/repositories/interfaces/client_member_repository.dart';
import 'package:webapp/utils/functions.dart';

class ClientMemberRequest implements ClientMemberRepository {
  ClientMemberRequest({AuthRepository? authRepository})
    : _authRepository = authRepository ?? AuthRequest.instance;

  static final ClientMemberRequest instance = ClientMemberRequest();

  static const resourceKeyPrefix = 'client_members';

  final AuthRepository _authRepository;

  @override
  Future<void> initialize() async {
    await _authRepository.initialize();
  }

  @override
  Future<List<ClientMember>> getMembersForClient(String clientId) async {
    final normalizedClientId = normalizeId(clientId);
    if (normalizedClientId == null) {
      return <ClientMember>[];
    }
    final users = await _authRepository.getUsers();
    final members = users
        .where(
          (user) =>
              isSubClientRole(user.role) &&
              normalizeId(user.parentClientId) == normalizedClientId,
        )
        .map(_memberFromUser)
        .toList();
    members.sort((a, b) {
      if ((a.isActive ?? true) != (b.isActive ?? true)) {
        return (b.isActive ?? true) ? 1 : -1;
      }
      final aDate = a.updatedAt ?? a.createdAt;
      final bDate = b.updatedAt ?? b.createdAt;
      if (aDate == null && bDate == null) {
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      }
      if (aDate == null) {
        return 1;
      }
      if (bDate == null) {
        return -1;
      }
      return bDate.compareTo(aDate);
    });
    return members;
  }

  @override
  Future<ClientMember> saveMember(ClientMember member) async {
    final normalizedClientId = normalizeId(member.clientId);
    final normalizedUserId = normalizeId(member.userId) ?? normalizeId(member.id);
    if (normalizedClientId == null) {
      throw Exception('Client ID is required.');
    }
    if (normalizedUserId == null) {
      return _normalizedMember(member, clientId: normalizedClientId);
    }

    final users = await _authRepository.getUsers();
    final existingUser = users.where((user) => user.id == normalizedUserId).firstOrNull;
    final savedUser = await _authRepository.saveUser(
      UserModel(
        id: normalizedUserId,
        role: 'sub-client',
        parentClientId: normalizedClientId,
        email: member.email ?? existingUser?.email,
        name: member.name ?? existingUser?.name,
        photo: member.photo ?? existingUser?.photo,
        phone: member.phone ?? existingUser?.phone,
        position: member.position ?? existingUser?.position,
        isActive: member.isActive ?? existingUser?.isActive ?? true,
        isOnline: existingUser?.isOnline ?? false,
        password: existingUser?.password,
        createdAt: existingUser?.createdAt ?? member.createdAt,
        updatedAt: member.updatedAt ?? existingUser?.updatedAt,
      ),
    );
    return _memberFromUser(savedUser);
  }

  @override
  Future<void> deleteMember(String memberId, {String? clientId}) async {
    final normalizedMemberId = normalizeId(memberId);
    if (normalizedMemberId == null) {
      return;
    }
    await _authRepository.deleteUser(normalizedMemberId);
  }

  ClientMember _memberFromUser(UserModel user) {
    return ClientMember(
      id: user.id,
      clientId: normalizeId(user.parentClientId),
      userId: user.id,
      email: user.email,
      photo: user.photo,
      name: user.name,
      phone: user.phone,
      position: user.position,
      isActive: user.isActive ?? true,
      createdAt: user.createdAt,
      updatedAt: user.updatedAt,
    );
  }

  ClientMember _normalizedMember(ClientMember member, {required String clientId}) {
    final now = DateTime.now();
    return member.copyWith(
      id: normalizeId(member.id) ?? normalizeId(member.userId),
      clientId: clientId,
      userId: normalizeId(member.userId) ?? normalizeId(member.id),
      email: member.email?.trim().toLowerCase(),
      photo: member.photo?.trim(),
      name: toTitleCase(member.name?.trim() ?? ''),
      phone: normalizePhilippinePhone(member.phone) ?? member.phone?.trim(),
      position: member.position?.trim(),
      createdAt: member.createdAt ?? now,
      updatedAt: now,
    );
  }
}
