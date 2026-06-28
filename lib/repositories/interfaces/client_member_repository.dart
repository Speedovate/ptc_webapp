import 'package:webapp/models/client_member.dart';

abstract class ClientMemberRepository {
  Future<void> initialize();
  Future<List<ClientMember>> getMembersForClient(String clientId);
  Future<ClientMember> saveMember(ClientMember member);
  Future<void> deleteMember(String memberId, {String? clientId});
}
