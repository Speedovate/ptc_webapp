import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/dispatcher_access_config.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/role_access.request.dart';
import 'package:webapp/services/role_access_service.dart';

// Exercise service updates against serialized role documents, without starting
// the application's global network/queue services in this unit test.
class RoleDocuments extends RoleAccessRequest {
  final database = FakeFirebaseFirestore();
  final updates = StreamController<void>.broadcast();
  Completer<List<DispatcherAccessConfig>>? pendingRead;
  int watchers = 0;

  @override
  Stream<void> watchRoleAccessCacheUpdates() {
    watchers++;
    return updates.stream;
  }

  @override
  Future<List<DispatcherAccessConfig>> getAllRoleAccessConfigs() async {
    final pending = pendingRead;
    if (pending != null) {
      pendingRead = null;
      return pending.future;
    }
    final docs = await database.collection('role_access').get();
    return docs.docs
        .map((doc) => DispatcherAccessConfig.fromMap(doc.data()))
        .toList();
  }

  @override
  Future<DispatcherAccessConfig> saveRoleAccess(
    DispatcherAccessConfig config,
  ) async {
    await database
        .collection('role_access')
        .doc(config.role)
        .set(config.toMap());
    return config;
  }
}

void main() {
  test(
    'KPI permissions save, restore, and react to remote revoke without duplicate subscriptions',
    () async {
      final request = RoleDocuments();
      final service = RoleAccessService(request: request);
      service.setCurrentUser(const UserModel(id: '8', role: 'dispatcher'));
      await service.initialize();
      await service.initialize();
      expect(request.watchers, 1);
      expect(service.canAccess(DispatcherAccessCapability.pmKpiRead), false);
      final original = DispatcherAccessConfig.defaults(roleKey: 'dispatcher');
      final enabled = original.copyWith(
        capabilities: {
          ...original.capabilities,
          DispatcherAccessCapability.pmKpiRead: true,
          DispatcherAccessCapability.pmKpiUpdate: false,
        },
      );
      await service.saveRoleAccess(enabled);
      expect(service.canAccess(DispatcherAccessCapability.pmKpiRead), true);
      expect(service.canAccess(DispatcherAccessCapability.pmKpiUpdate), false);

      final reopened = RoleAccessService(request: request);
      reopened.setCurrentUser(const UserModel(id: '8', role: 'dispatcher'));
      await reopened.initialize();
      expect(reopened.canAccess(DispatcherAccessCapability.pmKpiRead), true);
      await request.saveRoleAccess(original);
      final revoked = Completer<void>();
      service.addListener(() {
        if (!service.canAccess(DispatcherAccessCapability.pmKpiRead) &&
            !revoked.isCompleted) {
          revoked.complete();
        }
      });
      request.updates.add(null);
      await revoked.future.timeout(const Duration(seconds: 2));
      service.dispose();
      reopened.dispose();
      await request.updates.close();
    },
  );

  test('older permission fetch cannot undo a completed local save', () async {
    final request = RoleDocuments();
    final service = RoleAccessService(request: request);
    service.setCurrentUser(const UserModel(id: '8', role: 'dispatcher'));
    await service.initialize();
    final stale = Completer<List<DispatcherAccessConfig>>();
    request.pendingRead = stale;
    final refresh = service.refresh();
    final original = DispatcherAccessConfig.defaults(roleKey: 'dispatcher');
    await service.saveRoleAccess(
      original.copyWith(
        capabilities: {
          ...original.capabilities,
          DispatcherAccessCapability.pmKpiRead: true,
        },
      ),
    );
    stale.complete([original]);
    await refresh;
    expect(service.canAccess(DispatcherAccessCapability.pmKpiRead), true);
    service.dispose();
    await request.updates.close();
  });
}
