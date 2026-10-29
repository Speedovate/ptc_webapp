import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/support_thread.dart';
import 'package:webapp/services/support_contact_scope.dart';

void main() {
  final investor = UserModel(id: '30', role: 'investor');
  test('personal support view excludes other accounts from its menu badge', () {
    const viewer = UserModel(id: '20', role: 'dispatcher');
    expect(
      canSeeSupportThread(
        viewer: viewer,
        thread: const SupportThread(requesterUserId: '21'),
        canBrowseAllThreads: false,
      ),
      isFalse,
    );
    expect(
      canSeeSupportThread(
        viewer: viewer,
        thread: const SupportThread(requesterUserId: '20'),
        canBrowseAllThreads: false,
      ),
      isTrue,
    );
    expect(
      canSeeSupportThread(
        viewer: viewer,
        thread: const SupportThread(requesterUserId: '21'),
        canBrowseAllThreads: true,
      ),
      isTrue,
    );
  });
  test(
    'investor thread visibility matches own and assigned crew conversations',
    () {
      const contacts = [
        UserModel(id: '40', role: 'driver', parentClientId: '30'),
        UserModel(id: '41', role: 'helper', parentClientId: '31'),
        UserModel(id: '42', role: 'client', parentClientId: '30'),
      ];
      for (final id in ['30', '40', '41', '42', '1', 'unknown']) {
        expect(
          canSeeSupportThread(
            viewer: investor,
            thread: SupportThread(requesterUserId: id),
            canBrowseAllThreads: true,
            contacts: contacts,
          ),
          ['30', '40'].contains(id),
          reason: 'requester=$id',
        );
      }
    },
  );
  test('investor sees main support and own drivers/helpers only', () {
    expect(
      canSeeSupportContact(investor, UserModel(id: '1', role: 'admin')),
      true,
    );
    for (final role in ['driver', 'helper']) {
      expect(
        canSeeSupportContact(
          investor,
          UserModel(id: '40', role: role, parentClientId: '30'),
        ),
        true,
      );
      expect(
        canSeeSupportContact(
          investor,
          UserModel(id: '41', role: role, parentClientId: '31'),
        ),
        false,
      );
      expect(
        canSeeSupportContact(investor, UserModel(id: '42', role: role)),
        false,
      );
    }
    for (final role in ['admin', 'dispatcher', 'client', 'investor']) {
      expect(
        canSeeSupportContact(
          investor,
          UserModel(id: '43', role: role, parentClientId: '30'),
        ),
        false,
      );
    }
    expect(canSeeSupportContact(investor, investor), false);
  });
  test('non investor visibility unchanged', () {
    expect(
      canSeeSupportContact(UserModel(id: '1', role: 'admin'), investor),
      true,
    );
  });
}
